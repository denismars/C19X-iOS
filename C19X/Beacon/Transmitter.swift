//
//  Transmitter.swift
//  C19X
//
//  Created by Freddy Choi on 23/03/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import os

/**
 Beacon transmitter broadcasts a fixed service UUID to enable background scan by iOS. When iOS
 enters background mode, the UUID will disappear from the broadcast, so Android devices need to
 search for Apple devices and then connect and discover services to read the UUID.
*/
protocol Transmitter {
    /**
     Create a transmitter  that uses the same sequential dispatch queue as the receiver.
     Transmitter starts automatically when Bluetooth is enabled. Use the updateBeaconCode() function
     to manually change the beacon code being broadcasted by the transmitter. The code is also
     automatically updated after the given time interval.
     */
    init(queue: DispatchQueue, beaconCodes: BeaconCodes, updateCodeAfter: TimeInterval)
    
    /**
     Start transmitter. The actual start is triggered by bluetooth state changes.
     */
    func start(_ source: String)

    /**
     Stops and resets transmitter.
     */
    func stop(_ source: String)

    /**
     Delegates for receiving beacon detection events. This is necessary because some Android devices (Samsung J6)
     does not support BLE transmit, thus making the beacon characteristic writable offers a mechanism for such devices
     to detect a beacon transmitter and make their own presence known by sending its own beacon code and RSSI as
     data to the transmitter.
     */
    func append(_ delegate: ReceiverDelegate)
    
    /**
     Change beacon code being broadcasted by adjusting the lower 64-bit of characteristic UUID.
     */
    func updateBeaconCode()
}

/**
 Service UUID for beacon service. This is a fixed UUID to enable iOS devices to find each other even
 in background mode. Android devices will need to find Apple devices first using the manufacturer code
 then discover services to identify actual beacons.
 */
let beaconServiceCBUUID = CBUUID(string: "0022D481-83FE-1F13-0000-000000000000")

/**
 Characteristic UUID template for beacon service. Beacon code is encoded in the lower 64-bit of the 128-bit UUID.
 In theory, the whole 128-bit can be used for the beacon code as the service only exposes one characteristic. The
 beacon code has been encoded in the characteristic UUID to enable reliable read without an actual read operation,
 and also enables the characteristic to be a writable characteristic for non-transmitting Android devices to submit
 their beacon code and RSSI as data. The characteristic also supports notify on iOS devices  to offer a mechanism
 for keeping the transmitter and receiver from entering suspended / killed state.
 */
let beaconCharacteristicCBUUID = CBUUID(string: "0022D481-83FE-1F13-0000-000000000000")

/**
 Transmitter offers a single service with a single characteristic for broadcasting the beacon code as the lower 64-bit
 of the characteristic UUID. The characteristic is also writable to enable non-transmitting Android devices (receive only,
 like the Samsung J6) to make their presence known by writing their beacon code and RSSI as data to this characteristic.
 
 Keeping the transmitter and receiver working in iOS background mode is a major challenge, in particular when both
 iOS devices are in background mode. The transmitter on iOS offers a notifying beacon characteristic that is triggered
 by writing anything to the characteristic. On characteristic write, the transmitter will call updateValue after 8 seconds
 to notify the receivers, to wake up the receivers with a didUpdateValueFor call. The process can repeat as a loop
 between the transmitter and receiver to keep both devices awake. This is unnecessary for Android-Android and also
 Android-iOS and iOS-Android detection, which can rely solely on scanForPeripherals for detection.
 
 The notification based wake up method relies on an open connection which seems to be fine for iOS but may cause
 problems for Android. Experiments have found that Android devices cannot accept new connections (without explicit
 disconnect) indefinitely and the bluetooth stack ceases to function after around 500 open connections. The device
 will need to be rebooted to recover. However, if each connection is disconnected, the bluetooth stack can work
 indefinitely, but frequent connect and disconnect can still cause the same problem. The recommendation is to
 (1) always disconnect from Android as soon as the work is complete, (2) minimise the number of connections to
 an Android device, and (3) maximise time interval between connections. With all these in mind, the transmitter
 on Android does not support notify and also a connect is only performed on first contact to get the bacon code.
 */
class ConcreteTransmitter : NSObject, Transmitter, CBPeripheralManagerDelegate {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "Transmitter")
    /// Dedicated sequential queue for all beacon transmitter and receiver tasks.
    private let queue: DispatchQueue
    /// Beacon code generator for creating cryptographically secure public codes that can be later used for on-device matching.
    private let beaconCodes: BeaconCodes
    /// Automatically change beacon codes at regular intervals.
    private let updateCodeAfter: TimeInterval
    /**
     Characteristic UUID encodes the characteristic identifier in the upper 64-bits and the beacon code in the lower 64-bits
     to achieve reliable read of beacon code without an actual GATT read operation. In theory, the whole 128-bits can be
     used considering the beacon only has one characteristic.
    */
    private let (characteristicCBUUIDUpper,_) = beaconCharacteristicCBUUID.values
    /// Peripheral manager for managing all connections, using a single manager for simplicity.
    private var peripheral: CBPeripheralManager!
    /// Beacon characteristic being broadcasted by the transmitter, this is a mutating characteristic where the beacon code
    /// is encoded in the lower 64-bits of the UUID.
    private var beaconCharacteristic: CBMutableCharacteristic?
    private var beaconService: CBMutableService?
    /// Dummy data for writing to the receivers to trigger state restoration or resume from suspend state to background state.
    private let emptyData = Data(repeating: 0, count: 0)
    /**
     Shifting timer for triggering notify for subscribers several seconds after resume from suspend state to background state,
     but before re-entering suspend state. The time limit is under 10 seconds as desribed in Apple documentation.
     */
    private var notifyTimer: DispatchSourceTimer?
    /// Dedicated sequential queue for the shifting timer.
    private let notifyTimerQueue = DispatchQueue(label: "org.c19x.beacon.transmitter.Timer")
    /// Last beacon code update time, used to update code automatically at regular intervals.
    private var codeUpdatedAt = Date.distantPast
    /// Delegates for receiving beacon detection events.
    private var delegates: [ReceiverDelegate] = []

    required init(queue: DispatchQueue, beaconCodes: BeaconCodes, updateCodeAfter: TimeInterval) {
        self.queue = queue
        self.beaconCodes = beaconCodes
        self.updateCodeAfter = updateCodeAfter
        super.init()
        // Create a peripheral that supports state restoration
        self.peripheral = CBPeripheralManager(delegate: self, queue: queue, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Transmitter",
            CBPeripheralManagerOptionShowPowerAlertKey : true
        ])
    }
    
    func append(_ delegate: ReceiverDelegate) {
        delegates.append(delegate)
    }
    
    func start(_ source: String) {
        os_log("start (source=%s)", log: log, type: .debug, source)
        stopAdvertising(cancelTimer: true)
        if let (_,beaconCode) = beaconCharacteristic?.uuid.values, let beaconService = beaconService {
            startAdvertising(beaconService, after: .seconds(1))
            os_log("start successful, for existing beacon code (source=%s,code=%s)", log: log, type: .debug, source, beaconCode.description)
        } else {
            updateBeaconCode()
            os_log("start successful, for new beacon code (source=%s)", log: log, type: .debug, source)
        }
        notifySubscribers("start|" + source)
    }
    
    func stop(_ source: String) {
        os_log("stop (source=%s)", log: log, type: .debug, source)
        guard peripheral.isAdvertising else {
            os_log("stop denied, already stopped (source=%s)", log: log, type: .fault, source)
            return
        }
        stopAdvertising(cancelTimer: true)
    }
    
    private func startAdvertising(_ beaconService: CBMutableService, after: DispatchTimeInterval) {
        queue.asyncAfter(deadline: DispatchTime.now().advanced(by: after), execute: {
            self.peripheral.removeAllServices()
            self.beaconCharacteristic?.value = nil
            self.peripheral.add(beaconService)
            self.peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [beaconService.uuid]])
        })
    }
    
    private func stopAdvertising(cancelTimer: Bool) {
        guard peripheral.isAdvertising else {
            return
        }
        queue.async {
            self.peripheral.removeAllServices()
            self.peripheral.stopAdvertising()
        }
        if cancelTimer {
            notifyTimer?.cancel()
            notifyTimer = nil
        }
    }
    
    func updateBeaconCode() {
        os_log("updateBeaconCode", log: log, type: .debug)
        guard peripheral.state == .poweredOn else {
            os_log("updateBeaconCode denied, bluetooth is not on", log: log, type: .fault)
            return
        }
        guard let beaconCode = beaconCodes.get() else {
            os_log("updateBeaconCode denied, beacon codes exhausted", log: log, type: .fault)
            return
        }
        
        // Beacon code is encoded in the lower 64-bits of the characteristic UUID
        let (upper, _) = beaconCharacteristicCBUUID.values
        let beaconCharacteristicCBUUID = CBUUID(upper: upper, lower: beaconCode)
        beaconCharacteristic = CBMutableCharacteristic(type: beaconCharacteristicCBUUID, properties: [.write, .notify], value: nil, permissions: [.writeable])
        beaconService = CBMutableService(type: beaconServiceCBUUID, primary: true)
        beaconService!.characteristics = [beaconCharacteristic!]

        // Replace advertised service to broadcast new beacon code
        stopAdvertising(cancelTimer: false)
        startAdvertising(beaconService!, after: .seconds(1))
        codeUpdatedAt = Date()
        os_log("updateBeaconCode successful (code=%s,characteristic=%s)", log: self.log, type: .debug, beaconCode.description, beaconCharacteristicCBUUID.uuidString)
    }
    
    /**
     Generate updateValue notification after 8 seconds to notify all subscribers and keep the iOS receivers awake.
     */
    private func notifySubscribers(_ source: String) {
        notifyTimer?.cancel()
        notifyTimer = DispatchSource.makeTimerSource(queue: notifyTimerQueue)
        notifyTimer?.schedule(deadline: DispatchTime.now().advanced(by: transceiverNotificationDelay))
        notifyTimer?.setEventHandler { [weak self] in
            guard let s = self, let beaconCharacteristic = s.beaconCharacteristic else {
                return
            }
            os_log("Notify subscribers (source=%s)", log: s.log, type: .debug, source)
            s.queue.async { s.peripheral.updateValue(s.emptyData, for: beaconCharacteristic, onSubscribedCentrals: nil) }            
            let updateCodeInterval = Date().timeIntervalSince(s.codeUpdatedAt)
            if updateCodeInterval > s.updateCodeAfter {
                os_log("Automatic beacon code update (lastUpdate=%s,elapsed=%s)", log: s.log, type: .debug, s.codeUpdatedAt.description, updateCodeInterval.description)
                s.updateBeaconCode()
            }
        }
        notifyTimer?.resume()
    }
    
    // MARK:- CBPeripheralManagerDelegate
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        os_log("Restored state", log: log, type: .debug)
        self.peripheral = peripheral
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for service in services {
                os_log("Restored (service=%s)", log: log, type: .debug, service.uuid.uuidString)
                if service.uuid == beaconServiceCBUUID {
                    self.beaconService = service
                }
                if let characteristics = service.characteristics {
                    for characteristic in characteristics {
                        os_log("Restored (characteristic=%s)", log: log, type: .debug, characteristic.uuid.uuidString)
                        let (upper,beaconCode) = characteristic.uuid.values
                        if upper == characteristicCBUUIDUpper, let beaconCharacteristic = characteristic as? CBMutableCharacteristic {
                            os_log("Restored beacon characteristic (code=%s)", log: log, type: .debug, beaconCode.description)
                            self.beaconCharacteristic = beaconCharacteristic
                        }
                    }
                }
            }
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Bluetooth on -> Update beacon code -> Advertise
        os_log("Update state (state=%s)", log: log, type: .debug, peripheral.state.description)
        if (peripheral.state == .poweredOn) {
            start("didUpdateState|powerOn")
        }
    }
    
    /**
     Write request offers a mechanism for non-transmitting BLE devices (e.g. Samsung J6 can only receive) to make
     its presence known by submitting its beacon code and RSSI as data. This also offers a mechanism for iOS to
     write blank data to transmitter to keep bringing it back from suspended state to background state which increases
     its chance of background scanning over a long period without being killed off.
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Write -> Notify delegates -> Write response -> Notify subscribers
        for request in requests {
            let uuid = request.central.identifier.uuidString
            os_log("Write (central=%s)", log: log, type: .debug, uuid)
            if let data = request.value {
                // Receive beacon code and RSSI as data from receiver (e.g. Android device with no BLE transmit capability)
                if let beaconData = BeaconData(data) {
                    os_log("Detected beacon (method=write,peripheral=%s,beaconCode=%s,rssi=%d)", log: log, type: .debug, uuid, beaconData.beaconCode.description, beaconData.rssi)
                    for delegate in delegates {
                        delegate.receiver(didDetect: beaconData.beaconCode, rssi: beaconData.rssi)
                    }
                }
                // Receiver writes blank data on detection of transmitter to bring iOS transmitter back from suspended state
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            }
        }
        notifySubscribers("didReceiveWrite")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        // Read -> Notify subscribers
        // This should never happen, no readable characteristic. For debug only.
        os_log("Read (central=%s)", log: log, type: .debug, request.central.identifier.uuidString)
        notifySubscribers("didReceiveRead")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        // Subscribe -> Notify subscribers
        // iOS receiver subscribes to the beacon characteristic on first contact. This ensures the first call keeps
        // the transmitter and receiver awake. Future loops will rely on didReceiveWrite as the trigger.
        os_log("Subscribe (central=%s)", log: log, type: .debug, central.identifier.uuidString)
        notifySubscribers("didSubscribeTo")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        // Unsubscribe -> Notify subscribers
        // This should never happen, as unsubscribe can only happen on characteristic change, where the characteristic and service
        // are both replaced at the same time. For debug only.
        os_log("Unsubscribe (central=%s)", log: log, type: .debug, central.identifier.uuidString)
        notifySubscribers("didUnsubscribeFrom")
    }
}

/**
 Beacon data bundle transmitted from receiver via characteristic write.
 */
class BeaconData {
    let beaconCode: BeaconCode
    let rssi: RSSI

    init?(_ data:Data) {
        let bytes = [UInt8](data)
        if bytes.count != 12 {
            return nil
        }
        // Beacon code is a 64-bit Java long (little-endian) at index 0
        self.beaconCode = BeaconCode(BeaconData.getInt64(0, bytes: bytes))
        // RSSI is a 32-bit Java int (little-endian) at index 8
        self.rssi = RSSI(BeaconData.getInt32(8, bytes: bytes))
    }

    /// Get Int32 from byte array (little-endian).
    static func getInt32(_ index: Int, bytes:[UInt8]) -> Int32 {
        return Int32(bitPattern: getUInt32(index, bytes: bytes))
    }
    
    /// Get UInt32 from byte array (little-endian).
    static func getUInt32(_ index: Int, bytes:[UInt8]) -> UInt32 {
        let returnValue = UInt32(bytes[index]) |
            UInt32(bytes[index + 1]) << 8 |
            UInt32(bytes[index + 2]) << 16 |
            UInt32(bytes[index + 3]) << 24
        return returnValue
    }
    
    /// Get Int64 from byte array (little-endian).
    static func getInt64(_ index: Int, bytes:[UInt8]) -> Int64 {
        return Int64(bitPattern: getUInt64(index, bytes: bytes))
    }
    
    /// Get UInt64 from byte array (little-endian).
    static func getUInt64(_ index: Int, bytes:[UInt8]) -> UInt64 {
        let returnValue = UInt64(bytes[index]) |
            UInt64(bytes[index + 1]) << 8 |
            UInt64(bytes[index + 2]) << 16 |
            UInt64(bytes[index + 3]) << 24 |
            UInt64(bytes[index + 4]) << 32 |
            UInt64(bytes[index + 5]) << 40 |
            UInt64(bytes[index + 6]) << 48 |
            UInt64(bytes[index + 7]) << 56
        return returnValue
    }
}
