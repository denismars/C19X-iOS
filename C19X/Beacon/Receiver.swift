//
//  Receiver.swift
//  C19X
//
//  Created by Freddy Choi on 24/03/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import os

/**
 Beacon receiver scans for peripherals with fixed service UUID.
 */
protocol Receiver {
    var delegates: [ReceiverDelegate] { get set }
    
    init(queue: DispatchQueue)
    
    /**
     Scan for beacons.
     */
    func startScan(_ source: String)
    
    /**
     Reconnect to all known peripherals.
     */
    func reconnect(_ source: String)
}

/**
 RSSI in dBm.
 */
typealias RSSI = Int

/**
 Beacon receiver delegate listens for beacon detection events (beacon code, rssi).
 */
protocol ReceiverDelegate {
    /**
     Beacon code has been detected.
     */
    func receiver(didDetect: BeaconCode, rssi: RSSI)
}

/**
 Beacon peripheral for collating information (beacon code) acquired from asynchronous callbacks.
 */
class Beacon {
    var peripheral: CBPeripheral
    var characteristic: CBCharacteristic?
    var rssi: RSSI?
    var code: BeaconCode?
    var codeUpdatedAt: Date
    let statistics = TimeIntervalSample()
    
    /**
     Beacon identifier is the same as the peripheral identifier.
     */
    var uuidString: String { get { peripheral.identifier.uuidString } }
    /**
     Beacon expires if beacon code was acquired yesterday (day code changes at midnight everyday) or 30 minutes has elapsed.
     */
    var isExpired: Bool { get {
        guard rssi != nil, code != nil else {
            return true
        }
        let now = Date()
        let today = UInt64(now.timeIntervalSince1970).dividedReportingOverflow(by: UInt64(86400))
        let createdOnDay = UInt64(codeUpdatedAt.timeIntervalSince1970).dividedReportingOverflow(by: UInt64(86400))
        return createdOnDay != today || codeUpdatedAt.distance(to: Date()) > TimeInterval(1800)
    } }
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.codeUpdatedAt = Date()
    }

    init(peripheral: CBPeripheral, rssi: RSSI) {
        self.peripheral = peripheral
        self.rssi = rssi
        self.codeUpdatedAt = Date()
    }
}

/**
 Beacon receiver scans for peripherals with fixed service UUID in foreground and background modes. Background scan
 is made possible by using the CentralManager:didDiscover callback to trigger Central:scanForPeripherals calls. The trick
 is making use of the iOS peripheral scan process which reports all discovered devices after every new scan call, even
 when the device was already discovered in a previous call. The actual scan interval will be governed by iOS and it will be
 longer whilst in background mode, but practical experiments have shown the interval is rarely more than two minutes. This
 solution has a low energy impact on the device, and more importantly, avoids establishing an open connection to an infinite
 number of peripherals to listen for keep alive notifications, which can cause irrecoverable faults (device reboot required)
 on Android bluetooth stacks.
 */
class ConcreteReceiver: NSObject, Receiver, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "Receiver")
    /**
     Delay between connection attempts, using CoreBluetooth connect delay rather than dispatch source timer
     to extend delay between the 10 seconds background processing window. Please note, the delay might be
     greater or less than this figure, but a 60 seconds delay translates to about 0 - 120 seconds in practice.
     */
    private let connectDelay:NSNumber = 60
    private let queue: DispatchQueue!
    /**
     Central manager for managing all connections, using a single manager for simplicity.
     */
    private var central: CBCentralManager!
    /**
     Characteristic UUID encodes the characteristic identifier in the upper 64-bits and the beacon code in the lower 64-bits
     to achieve reliable read of beacon code without an actual GATT read operation.
    */
    private let (characteristicCBUUIDUpper,_) = beaconCharacteristicCBUUID.values
    /**
     Table of all known beacons.
     */
    private var beacons: [String: Beacon] = [:]
    /**
     Dummy data for writing to the transmitter to trigger state restoration or resume from suspend state to background state.
     */
    private let emptyData = Data(repeating: 0, count: 0)
    /**
     Shifting timer for triggering scan for peripherals several seconds after resume from suspend state to background state,
     but before re-entering suspend state. The time limit is under 10 seconds as desribed in Apple documentation.
     */
    private var scanTimer: DispatchSourceTimer?
    /**
     Shifting timer for triggering notify for subscribers several seconds after resume from suspend state to background state,
     but before re-entering suspend state. The time limit is under 10 seconds as desribed in Apple documentation.
     */
    private var notifyTimer: DispatchSourceTimer?
    /**
     Delegates for receiving beacon detection events.
     */
    var delegates: [ReceiverDelegate] = []
    /**
     Optional utility data for tracking detection time interval statistics and up time.
     */
    private let statistics = TimeIntervalSample()


    required init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        // Creating a central manager that supports state restore
        central = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Receiver",
            CBCentralManagerOptionShowPowerAlertKey : true])
    }
    
    func startScan(_ source: String) {
        statistics.add()
        os_log("Scan start (source=%s,statistics={%s})", log: log, type: .debug, source, statistics.description)
        guard let central = central, central.state == .poweredOn else {
            os_log("Scan start failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        
        // Known peripherals -> State check (Optional)
        beacons.values.forEach() { beacon in
            // os_log("Scan, state check (peripheral=%s,state=%s)", log: self.log, type: .debug, beacon.uuidString, beacon.peripheral.state.description)
        }
        // Scan for peripherals -> didDiscover (may or may not report already connected peripherals)
        central.scanForPeripherals(withServices: [beaconServiceCBUUID])
        // Connected peripherals -> Read RSSI
        central.retrieveConnectedPeripherals(withServices: [beaconServiceCBUUID]).forEach() { peripheral in
            let uuid = peripheral.identifier.uuidString
            if beacons[uuid] == nil {
                beacons[uuid] = Beacon(peripheral: peripheral)
                peripheral.delegate = self
            }
            os_log("Scan, read RSSI for connected (peripheral=%s)", log: self.log, type: .debug, uuid)
            readRSSI("scan", peripheral)
        }
    }
        
    /**
     Schedule scan for beacons after a delay of 8 seconds to start scan again just before
     state change from background to suspended. Scan is sufficient for finding Android
     devices repeatedly in both foreground and background states.
     */
    func scheduleScan(_ source: String) {
        scanTimer?.cancel()
        scanTimer = DispatchSource.makeTimerSource(queue: queue)
        scanTimer?.schedule(deadline: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(8)))
        scanTimer?.setEventHandler { [weak self] in
            self?.startScan("scheduleScan|"+source)
        }
        scanTimer?.resume()
    }
    
    /// Reconnect all known peripherals
    func reconnect(_ source: String) {
        os_log("Reconnect (peripherals=%s)", log: log, type: .debug, source, beacons.count.description)
        beacons.values.forEach() { beacon in
            if beacon.peripheral.state == .connected {
                readRSSI("reconnect", beacon.peripheral)
            } else {
                connect("reconnect", beacon.peripheral)
            }
        }
    }
    
    /// Connect peripheral
    private func connect(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connect (source=%s,peripheral=%s,delay=%d)", log: log, type: .debug, source, uuid, connectDelay.intValue)
        central.connect(peripheral, options: [CBConnectPeripheralOptionStartDelayKey : connectDelay])
    }
    
    /// Disconnect peripheral
    private func disconnect(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnect (source=%s,peripheral=%s)", log: log, type: .debug, source, uuid)
        central.cancelPeripheralConnection(peripheral)
    }
    
    /// Read RSSI
    private func readRSSI(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        guard peripheral.state == .connected else {
            return
        }
        os_log("Read RSSI (source=%s,peripheral=%s)", log: self.log, type: .debug, source, uuid)
        peripheral.readRSSI()
    }
    
    /// Read beacon code
    private func readCode(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        guard peripheral.state == .connected else {
            return
        }
        os_log("Read beacon code (source=%s,peripheral=%s)", log: self.log, type: .debug, source, uuid)
        peripheral.discoverServices([beaconServiceCBUUID])
    }
    
    /// Notify receiver delegates of beacon detection
    private func notifyDelegates(_ source: String, _ beacon: Beacon) {
        guard !beacon.isExpired, let code = beacon.code, let rssi = beacon.rssi else {
            return
        }
        beacon.statistics.add()
        for delegate in self.delegates {
            delegate.receiver(didDetect: code, rssi: rssi)
        }
        // Invalidate RSSI after notify
        beacon.rssi = nil
        os_log("Detected beacon (source=%s,peripheral=%s,code=%s,rssi=%s,statistics={%s})", log: self.log, type: .debug, source, String(describing: beacon.uuidString), String(describing: code), String(describing: rssi), String(describing: beacon.statistics.description))
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        os_log("Restore", log: log, type: .debug)
        self.central = central
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restoredPeripherals {
                peripheral.delegate = self
                let uuid = peripheral.identifier.uuidString
                if let beacon = beacons[uuid] {
                    beacon.peripheral = peripheral
                } else {
                    beacons[uuid] = Beacon(peripheral: peripheral)
                }
                os_log("Restored (peripheral=%s)", log: log, type: .debug, uuid)
            }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Bluetooth power on -> Start scanning for peripherals, Reconnect known peripherals
        os_log("State updated (toState=%s)", log: log, type: .debug, central.state.description)
        if (central.state == .poweredOn) {
            startScan("updateState")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Discover peripheral -> Connect to read RSSI and beacon code -> Schedule scan again
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        if beacons[uuid] == nil {
            // New peripheral -> Connect -> Read Code
            beacons[uuid] = Beacon(peripheral: peripheral, rssi: rssi)
            peripheral.delegate = self
            os_log("Discovered (peripheral=%s,rssi=%d,state=%s,new=true)", log: self.log, type: .debug, uuid, rssi, peripheral.state.description)
            connect("didDiscover", peripheral)
        } else if let beacon = beacons[uuid] {
            // Existing peripheral -> Read Code if expired, else Notify delegates of beacon detection
            beacon.rssi = rssi
            os_log("Discovered (peripheral=%s,rssi=%d,state=%s,new=false)", log: self.log, type: .debug, uuid, rssi, peripheral.state.description)
            if peripheral.state == .connected {
                if beacon.isExpired {
                    readCode("didDiscover", peripheral)
                } else {
                    notifyDelegates("didDiscover", beacon)
                    disconnect("didDiscover", peripheral)
                }
            } else {
                connect("didDiscover", peripheral)
            }
        }
        scheduleScan("didDiscover")
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Connect peripheral -> Read RSSI if required, Read Code if expired, or Notify delegates of beacon detection
        let uuid = peripheral.identifier.uuidString
        os_log("Connected (peripheral=%s)", log: log, type: .debug, uuid)
        peripheral.delegate = self
        if let beacon = beacons[uuid] {
            if beacon.rssi == nil {
                readRSSI("didConnect", peripheral)
            } else if beacon.isExpired {
                readCode("didConnect", peripheral)
            } else {
                notifyDelegates("didConnect", beacon)
                disconnect("didConnect", peripheral)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Connect failed -> Connect, Schedule scan again
        let uuid = peripheral.identifier.uuidString
        os_log("Failed to connect (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        if String(describing: error).contains("Device is invalid") {
            os_log("Remove invalid peripheral (peripheral=%s)", log: log, type: .debug, uuid)
            beacons[uuid] = nil
        } else {
            connect("didFailToConnect", peripheral)
        }
        scheduleScan("didFailToConnect")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Disconnected -> Connect, Schedule scan again
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnected (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        connect("didDisconnectPeripheral", peripheral)
        scheduleScan("didDisconnectPeripheral")
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        // Read RSSI -> Read Code if expired, or Notify delegates of beacon detection
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        os_log("Read RSSI (peripheral=%s,rssi=%d,error=%s)", log: log, type: .debug, uuid, rssi, String(describing: error))
        if let beacon = beacons[uuid] {
            beacon.rssi = rssi
            if beacon.isExpired {
                readCode("didReadRSSI", peripheral)
            } else {
                notifyDelegates("didReadRSSI", beacon)
                disconnect("didReadRSSI", peripheral)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        // Discover services -> Discover characteristics, or Disconnect
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        os_log("Discovered services (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        guard let services = peripheral.services else {
            disconnect("didDiscoverServices|noService", peripheral)
            return
        }
        for service in services {
            os_log("Discovered service (peripheral=%s,service=%s)", log: log, type: .debug, uuid, service.uuid.description)
            if (service.uuid == beaconServiceCBUUID) {
                os_log("Discovered beacon service (peripheral=%s)", log: log, type: .debug, uuid)
                peripheral.discoverCharacteristics(nil, for: service)
                return
            }
        }
        disconnect("didDiscoverServices|notFound", peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Discover characteristics -> Notify delegates of beacon detection -> Write blank data to transmitter -> Disconnect
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        os_log("Discovered characteristics (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        guard let beacon = beacons[uuid], let characteristics = service.characteristics else {
            disconnect("didDiscoverCharacteristicsFor|noCharacteristic", peripheral)
            return
        }
        for characteristic in characteristics {
            os_log("Discovered characteristic (peripheral=%s,characteristic=%s)", log: log, type: .debug, uuid, characteristic.uuid.description)
            let (upper,beaconCode) = characteristic.uuid.values
            if upper == characteristicCBUUIDUpper {
                os_log("Discovered beacon characteristic (peripheral=%s,beaconCode=%s)", log: log, type: .debug, uuid, beaconCode.description)
                beacon.code = beaconCode
                beacon.codeUpdatedAt = Date()
                notifyDelegates("didDiscover", beacon)
                os_log("Write value (peripheral=%s)", log: self.log, type: .debug, uuid)
                peripheral.writeValue(emptyData, for: characteristic, type: .withResponse)
                return
            }
        }
        disconnect("didDiscoverCharacteristicsFor|notFound", peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // Wrote data -> Disconnect
        let uuid = peripheral.identifier.uuidString
        os_log("Wrote characteristic (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        disconnect("didWriteValueFor", peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        <#code#>
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        peripheral.writeValue(emptyData, for: characteristic, type: .withResponse)
    }
    
    private func notifyTransmitter(_ source: String, _ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
        let uuid = peripheral.identifier.uuidString
        notifyTimer?.cancel()
        notifyTimer = DispatchSource.makeTimerSource(queue: queue)
        notifyTimer?.schedule(deadline: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(8)))
        notifyTimer?.setEventHandler { [weak self] in
            guard let s = self else {
                return
            }
            os_log("Notify transmitter (source=%s,peripheral=%s)", log: s.log, type: .debug, source, uuid)
            peripheral.writeValue(s.emptyData, for: characteristic, type: .withResponse)
        }
    }
}
