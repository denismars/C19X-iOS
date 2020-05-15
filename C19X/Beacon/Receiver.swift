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
    var delegates: [ReceiverDelegate] { get set }
    
    init(_ transmitter: Transmitter)
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
    var code: BeaconCode?
    var isConnected = false
    private var createdAt: Date
    let statistics = TimeIntervalSample()
    var pulseCharacteristic: CBCharacteristic?
    var pulseTimer: DispatchSourceTimer?
    
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
    
    var hasPulse: Bool { get {
        return pulseCharacteristic != nil
    } }
    
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
    private var transmitter: Transmitter!
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
     Table of all known beacon peripherals.
     */
    private var peripherals: [String: Beacon] = [:]
    /**
     Delegates for receiving beacon detection events.
     */
    var delegates: [ReceiverDelegate] = []
    /**
     Dispatch queue for running beacon reconnection timers.
     */
    private let dispatchQueue = DispatchQueue(label: "org.c19x.beacon.Receiver")
    private var pulseTimer: DispatchSourceTimer?
    private var lastScan: Date?

    required init(_ transmitter: Transmitter) {
        self.transmitter = transmitter
        super.init()
        // Creating a central manager that supports state restore
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Receiver",
            CBCentralManagerOptionShowPowerAlertKey : true])
    }
    
    /**
     Start scanning for beacon peripherals.
     */
    func startScan() {
        if lastScan != nil && Date().timeIntervalSince(lastScan!) < 8 {
            return
        }
        os_log("Scan start", log: log, type: .debug)
        guard let central = central, central.state == .poweredOn else {
            os_log("Scan start failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        // Stop scan to reset central state
        central.stopScan()
        // Scan for peripherals with specific service UUID, this is the only supported background scan mode
        central.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
        os_log("Scanning", log: log, type: .debug)
        lastScan = Date()
        // Read RSSI for all connected iOS peripherals (has pulse)
        peripherals.values.forEach() { beacon in
            if beacon.hasPulse, beacon.peripheral.state == .connected {
                beacon.peripheral.readRSSI()
            }
        }
        // Generate pulse to wake up subscribers
        pulseTimer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        if let timer = pulseTimer {
            timer.setEventHandler {
                os_log("Waking subscribers", log: self.log, type: .debug)
                self.transmitter.pulse()
            }
            timer.schedule(deadline: DispatchTime.now() + 8)
            timer.resume()
        }
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
        guard !beacon.isConnected else {
            os_log("Connect denied, connection in progress", log: log, type: .fault)
            return
        }
        // Connect is delayed to manage power usage and also filter out passing contacts
        beacon.isConnected = true
        central.connect(beacon.peripheral)
        os_log("Connecting (peripheral=%s)", log: log, type: .debug, beacon.uuidString)
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
        } else {
            lastScan = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        os_log("Discovered (peripheral=%s,rssi=%d)", log: self.log, type: .debug, uuid, rssi)
        if peripherals[uuid] == nil {
            peripherals[uuid] = Beacon(peripheral: peripheral, delegate: self)
        }
        if let beacon = peripherals[uuid], !beacon.isConnected {
            connect(peripherals[uuid]!)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connected (peripheral=%s)", log: log, type: .debug, uuid)
        peripheral.discoverServices([serviceCBUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connect failed (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        if let beacon = peripherals[uuid] {
            beacon.isConnected = false
            if beacon.hasPulse {
                connect(beacon)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnected (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        if let beacon = peripherals[uuid] {
            beacon.isConnected = false
            if beacon.hasPulse {
                connect(beacon)
            }
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Discovered services (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
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
        os_log("Discovered characteristics (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        guard let beacon = peripherals[uuid], let characteristics = service.characteristics, characteristics.count > 0 else {
            // This should never happen because service should have at least the beacon characteristic
            os_log("Characteristic missing (peripheral=%s)", log: log, type: .fault, uuid)
            disconnect(peripheral)
            return;
        }
        for characteristic in characteristics {
            os_log("Discovered characteristic (peripheral=%s,characteristic=%s)", log: log, type: .debug, uuid, characteristic.uuid.description)
            if characteristic.uuid == pulseCharacteristicCBUUID {
                os_log("Discovered pulse characteristic (peripheral=%s)", log: log, type: .debug, uuid)
                beacon.pulseCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else {
                let (upper,beaconCode) = characteristic.uuid.values
                if upper == characteristicCBUUIDUpper {
                    os_log("Discovered beacon characteristic (peripheral=%s,beaconCode=%s)", log: log, type: .debug, uuid, beaconCode.description)
                    beacon.code = beaconCode
                }
            }
        }
        peripheral.readRSSI()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        os_log("Read RSSI (peripheral=%s,rssi=%d,error=%s)", log: log, type: .debug, uuid, rssi, String(describing: error))
        guard let beacon = peripherals[uuid] else {
            disconnect(peripheral)
            return
        }
        if let beaconCode = beacon.code {
            beacon.statistics.add()
            os_log("Detected beacon (method=rssi,peripheral=%s,beaconCode=%s,rssi=%d,statistics={%s})", log: log, type: .debug, uuid, beaconCode.description, rssi, beacon.statistics.description)
            for delegate in delegates {
                delegate.receiver(didDetect: beaconCode, rssi: rssi)
            }
        }
        if (!beacon.hasPulse) {
            disconnect(peripheral)
        }
        startScan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Pulse received (peripheral=%s)", log: log, type: .debug, uuid)
        startScan()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        os_log("Service modified (peripheral=%s)", log: log, type: .debug, peripheral.identifier.uuidString)
        startScan()
    }
}
