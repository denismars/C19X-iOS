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
    private var createdAt: Date
    let statistics = TimeIntervalSample()
    
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
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
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
    private let connectDelay:NSNumber = 8
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
    
    private var statistics = TimeIntervalSample()
    private let scanQueue = DispatchQueue(label: "org.c19x.beacon.ReceiverScan", attributes: .concurrent)
    private var scanTimer: DispatchSourceTimer?
    private let writeData = Data(repeating: 1, count: 1)
    /**
     Delegates for receiving beacon detection events.
     */
    var delegates: [ReceiverDelegate] = []

    override init() {
        super.init()
        // Creating a central manager that supports state restore
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Receiver",
            CBCentralManagerOptionShowPowerAlertKey : true])
    }
    
    /**
     Scan for beacons.
     */
    func scan() {
        os_log("Scan", log: log, type: .debug)
        guard let central = central, central.state == .poweredOn else {
            os_log("Scan failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        // Scan for peripherals with specific service UUID, this is the only supported background scan mode
        central.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
        os_log("Scanning", log: log, type: .debug)
    }
        
    func scheduleScan(_ source: String) {
        scanTimer?.cancel()
        scanTimer = DispatchSource.makeTimerSource(queue: scanQueue)
        scanTimer?.schedule(deadline: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(8)))
        scanTimer?.setEventHandler { [weak self] in
            if let log = self?.log {
                os_log("Scheduled scan (source=%s)", log: log, type: .debug, source)
            }
            self?.scan()
        }
        scanTimer?.resume()
    }
    
    private func connect(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connect (source=%s,peripheral=%s,delay=%d)", log: self.log, type: .debug, source, uuid, connectDelay.intValue)
        central.connect(peripheral, options: [CBConnectPeripheralOptionStartDelayKey : connectDelay])
    }
    
    private func disconnect(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnect (source=%s,peripheral=%s)", log: self.log, type: .debug, source, uuid)
        central.cancelPeripheralConnection(peripheral)
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
        os_log("State updated (toState=%s)", log: log, type: .debug, central.state.description)
        if (central.state == .poweredOn) {
            scan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        if beacons[uuid] == nil {
            beacons[uuid] = Beacon(peripheral: peripheral)
            os_log("Discovered (peripheral=%s,rssi=%d,state=%s,new=true)", log: self.log, type: .debug, uuid, rssi, peripheral.state.description)
        } else {
            os_log("Discovered (peripheral=%s,rssi=%d,state=%s,new=false)", log: self.log, type: .debug, uuid, rssi, peripheral.state.description)
        }
        if peripheral.state == .disconnected {
            connect("didDiscover", peripheral)
        }
        scheduleScan("didDiscover")
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        os_log("Connected (peripheral=%s)", log: log, type: .debug, uuid)
        statistics.add()
        os_log("Statistics (%s)", log: self.log, type: .debug, statistics.description)
        peripheral.readRSSI()
        //scheduleScan("didConnect")
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        os_log("Failed to connect (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        connect("didFailToConnect", peripheral)
        scheduleScan("didFailToConnect")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnected (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        connect("didDisconnectPeripheral", peripheral)
        scheduleScan("didDisconnectPeripheral")
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        os_log("Read RSSI (peripheral=%s,rssi=%d,error=%s)", log: log, type: .debug, uuid, rssi, String(describing: error))
        if let beacon = beacons[uuid] {
            beacon.rssi = rssi
        }
        peripheral.discoverServices([serviceCBUUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.delegate = self
        let uuid = peripheral.identifier.uuidString
        os_log("Discovered services (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        guard let services = peripheral.services else {
            disconnect("didDiscoverServices|noService", peripheral)
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
        disconnect("didDiscoverServices|notFound", peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
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
                peripheral.writeValue(writeData, for: characteristic, type: .withResponse)
                if let rssi = beacon.rssi {
                    for delegate in delegates {
                        delegate.receiver(didDetect: beaconCode, rssi: rssi)
                    }
                }
                return
            }
        }
        disconnect("didDiscoverCharacteristicsFor|notFound", peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Wrote characteristic (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        disconnect("didWriteValueFor", peripheral)
    }
}
