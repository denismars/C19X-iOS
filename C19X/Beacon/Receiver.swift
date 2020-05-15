//
//  Receiver.swift
//  C19X
//
//  Created by Freddy Choi on 23/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import os

/**
 Beacon receiver scans for peripherals with fixed service UUID.
 */
protocol Receiver {
    init(_ delegate:ReceiverDelegate?)
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
    var rssi: RSSI?
    var code: BeaconCode?
    var isConnected = false
    private var createdAt: Date
    let statistics = TimeIntervalSample()
    var timer: DispatchSourceTimer?
    
    /**
     Beacon identifier is the same as the peripheral identifier.
     */
    var uuidString: String { get { peripheral.identifier.uuidString } }
    /**
     Beacon expires if beacon code was acquired yesterday (day code changes at midnight everyday) or 30 minutes has elapsed.
     */
    var isExpired: Bool { get {
        let now = Date()
        let today = UInt64(now.timeIntervalSince1970).dividedReportingOverflow(by: UInt64(86400))
        let createdOnDay = UInt64(createdAt.timeIntervalSince1970).dividedReportingOverflow(by: UInt64(86400))
        return createdOnDay != today || createdAt.distance(to: Date()) > TimeInterval(1800)
    } }
    
    init(peripheral: CBPeripheral, delegate: CBPeripheralDelegate, rssi: RSSI) {
        self.peripheral = peripheral
        self.peripheral.delegate = delegate
        self.rssi = rssi
        self.createdAt = Date()
    }

    init(peripheral: CBPeripheral, delegate: CBPeripheralDelegate) {
        self.peripheral = peripheral
        self.peripheral.delegate = delegate
        self.createdAt = Date()
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
     Time delay between connect request and actual connection attempt. This is being used to
     offer opportunities for the app to enter suspended state, and also setting the minimum contact
     duration before the contact is recorded.
    */
    private let connectDelay = 4
    /**
     Time delay between reconnect request and actual connect request. This has to be within
     the 10 seconds background processing limit of iOS, otherwise the app is likely to be killed off.
     */
    private let reconnectDelay:Double = 8
    /**
     Central manager for managing all connections, using a single manager for simplicity.
     */
    private var central: CBCentralManager!
    /**
     Characteristic UUID encodes the characteristic identifier in the upper 64-bits and the beacon code in the lower 64-bits
     to achieve reliable read of beacon code without an actual GATT read operation.
    */
    private let (characteristicCBUUIDUpper,_) = characteristicCBUUID.values
    /**
     Table of all known beacon peripherals.
     */
    private var peripherals: [String: Beacon] = [:]
    /**
     Delegate for receiving beacon detection events.
     */
    private var delegate: ReceiverDelegate!
    /**
     Dispatch queue for running beacon reconnection timers.
     */
    private let dispatchQueue = DispatchQueue(label: "org.c19x.beacon.Receiver")

    required init(_ delegate: ReceiverDelegate?) {
        self.delegate = delegate
        super.init()
        // Creating a central manager that supports state restore
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Receiver",
            CBCentralManagerOptionShowPowerAlertKey : true])
    }
    
    /**
     Start scanning for beacon peripherals.
     */
    private func startScan() {
        os_log("Scan start", log: log, type: .debug, serviceCBUUID.description)
        guard let central = central, central.state == .poweredOn else {
            os_log("Scan start failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        // Scan for peripherals with specific service UUID, this is the only supported background scan mode
        central.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
        os_log("Scanning", log: log, type: .debug)
    }
    
    /**
     Stop scanning for beacon peripherals.
     */
    private func stopScan() {
        os_log("Scan stop", log: log, type: .debug, serviceCBUUID.description)
        guard let central = central, central.state == .poweredOn else {
            os_log("Scan stop failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        guard central.isScanning else {
            os_log("Scan stopped already", log: log, type: .debug)
            return
        }
        central.stopScan()
        os_log("Scan stopped", log: log, type: .debug)
    }
    
    /**
     Connect to beacon peripheral to acquire beacon code via asynchronous callbacks.
     */
    private func connect(_ beacon: Beacon) {
        os_log("Connect (peripheral=%s)", log: log, type: .debug, beacon.uuidString)
        guard let central = central, central.state == .poweredOn else {
            os_log("Connect failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        // Connect is delayed to manage power usage and also filter out passing contacts
        central.connect(beacon.peripheral, options: [CBConnectPeripheralOptionStartDelayKey : connectDelay])
        os_log("Connecting (peripheral=%s,delay=%d)", log: log, type: .debug, beacon.uuidString, connectDelay)
    }
    
    /**
     Reconnect to beacon peripheral after disconnection or connection failure to keep in touch.
     This is triggered by centralManager: didFailToConnect / didDisconnectPeripheral, thus
     the delay is introduced here to background processing time limit of around 10 seconds.
     */
    private func reconnect(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Reconnect (peripheral=%s,delay=%f)", log: log, type: .debug, uuid, reconnectDelay)
        if peripherals[uuid] == nil {
            peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self)
        }
        if let beacon = peripherals[uuid] {
            beacon.rssi = nil
            beacon.isConnected = false
            beacon.timer = DispatchSource.makeTimerSource(queue: dispatchQueue)
            if let timer = beacon.timer {
                timer.setEventHandler {
                    os_log("Reconnecting (peripheral=%s)", log: self.log, type: .debug, uuid)
                    self.connect(beacon)
                }
                timer.schedule(deadline: DispatchTime.now() + reconnectDelay)
                timer.resume()
            }
        }
    }

    /**
     Disconnect peripheral, retaining beacon code for reuse.
     */
    private func disconnect(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnect (peripheral=%s)", log: log, type: .debug, uuid)
        if let central = central {
            os_log("Disconnecting (peripheral=%s)", log: log, type: .debug, uuid)
            central.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - CBCentralManagerDelegate
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        os_log("State restored", log: log, type: .debug)
        self.central = central
        var isConnected: [String] = []
        central.retrieveConnectedPeripherals(withServices: [serviceCBUUID]).forEach() { peripheral in
            isConnected.append(peripheral.identifier.uuidString)
        }
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restoredPeripherals {
                let uuid = peripheral.identifier.uuidString
                os_log("Restored (peripheral=%s)", log: log, type: .debug, uuid)
                if let beacon = peripherals[uuid] {
                    beacon.peripheral = peripheral
                    beacon.peripheral.delegate = self
                    beacon.rssi = nil
                    beacon.isConnected = isConnected.contains(uuid)
                } else {
                    peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self)
                }
            }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("Update state (toState=%s)", log: log, type: .debug, central.state.description)
        if (central.state == .poweredOn) {
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        os_log("Discovered (peripheral=%s,rssi=%d)", log: self.log, type: .debug, uuid, rssi)
        if peripherals[uuid] == nil {
            peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self, rssi: rssi)
        }
        let beacon = peripherals[uuid]!
        if !beacon.isConnected {
            connect(peripherals[uuid]!)
        }
//        let beacon = peripherals[uuid]!
//        if let beaconCode = beacon.code, !beacon.isExpired {
//            os_log("Detected beacon (method=scan,peripheral=%s,beaconCode=%s,rssi=%d)", log: log, type: .debug, uuid, beaconCode.description, rssi)
//            if let delegate = delegate {
//                delegate.receiver(didDetect: beaconCode, rssi: rssi)
//            }
//            // SCHEDULE SCAN AGAIN?
//        } else {
//            connect(beacon)
//        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connected (peripheral=%s)", log: log, type: .debug, uuid)
        if peripherals[uuid] == nil {
            peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self)
        }
        let beacon = peripherals[uuid]!
        if let beaconCode = beacon.code, !beacon.isExpired {
            if let rssi = beacon.rssi {
                // Beacon code already known and not expired, RSSI is available, ready for reporting
                beacon.statistics.add()
                os_log("Detected beacon (method=connect,peripheral=%s,beaconCode=%s,rssi=%d,statistics={%s})", log: log, type: .debug, uuid, beaconCode.description, rssi, beacon.statistics.description)
                if let delegate = delegate {
                    delegate.receiver(didDetect: beaconCode, rssi: rssi)
                }
                disconnect(peripheral)
            } else {
                // Beacon code already known and not expired, RSSI is missing, read RSSI
                peripheral.readRSSI()
            }
        } else {
            // Beacon code is unknown or expired
            peripheral.discoverServices([serviceCBUUID])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connect failed (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        reconnect(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnected (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        reconnect(peripheral)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let uuid = peripheral.identifier.uuidString
        guard let services = peripheral.services else {
            // This should never happen because central is scanning for devices with the specific service
            os_log("Service missing (peripheral=%s)", log: log, type: .fault, uuid)
            disconnect(peripheral)
            return
        }
        for service in services {
            os_log("Discovered service (peripheral=%s,service=%s)", log: log, type: .debug, uuid, service.uuid.description)
            if (service.uuid == serviceCBUUID) {
                os_log("Discovered beacon service (peripheral=%s)", log: log, type: .debug, uuid)
                peripheral.discoverCharacteristics(nil, for: service)
                return
            }
        }
        disconnect(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        guard let characteristics = service.characteristics else {
            // This should never happen because service should have at least the beacon characteristic
            os_log("Characteristic missing (peripheral=%s)", log: log, type: .fault, uuid)
            disconnect(peripheral)
            return;
        }
        for characteristic in characteristics {
            os_log("Discovered characteristic (peripheral=%s,characteristic=%s)", log: log, type: .debug, uuid, characteristic.uuid.description)
            let (upper,beaconCode) = characteristic.uuid.values
            if upper == characteristicCBUUIDUpper {
                os_log("Discovered beacon characteristic (peripheral=%s,beaconCode=%s)", log: log, type: .debug, uuid, beaconCode.description)
                if peripherals[uuid] == nil {
                    peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self)
                }
                let beacon = peripherals[uuid]!
                beacon.code = beaconCode
                if let rssi = beacon.rssi {
                    beacon.statistics.add()
                    os_log("Detected beacon (method=discover,peripheral=%s,beaconCode=%s,rssi=%d,statistics={%s})", log: log, type: .debug, uuid, beaconCode.description, rssi, beacon.statistics.description)
                    if let delegate = delegate {
                        delegate.receiver(didDetect: beaconCode, rssi: rssi)
                    }
                    disconnect(peripheral)
                    return
                } else {
                    beacon.peripheral.readRSSI()
                    return
                }
            }
        }
        disconnect(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        os_log("Read RSSI (peripheral=%s,rssi=%d)", log: log, type: .debug, uuid, rssi)
        if peripherals[uuid] == nil {
            peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self, rssi: rssi)
        }
        let beacon = peripherals[uuid]!
        beacon.rssi = rssi
        if let beaconCode = beacon.code, let rssi = beacon.rssi {
            beacon.statistics.add()
            os_log("Detected beacon (method=rssi,peripheral=%s,beaconCode=%s,rssi=%d,statistics={%s})", log: log, type: .debug, uuid, beaconCode.description, rssi, beacon.statistics.description)
            if let delegate = delegate {
                delegate.receiver(didDetect: beaconCode, rssi: rssi)
            }
        }
        disconnect(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        os_log("Service modified (peripheral=%s)", log: log, type: .debug, peripheral.identifier.uuidString)
    }
}
