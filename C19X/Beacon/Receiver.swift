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
    
    init(queue: DispatchQueue, database: Database)
    /**
     Scan for beacons.
     */
    func startScan()
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
    private let database: Database
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
    
    private var statistics = TimeIntervalSample()
    private var scanTimer: DispatchSourceTimer?

    private let emptyData = Data(repeating: 0, count: 0)
    /**
     Delegates for receiving beacon detection events.
     */
    var delegates: [ReceiverDelegate] = []

    required init(queue: DispatchQueue, database: Database) {
        self.queue = queue
        self.database = database
        super.init()
        // Creating a central manager that supports state restore
        central = CBCentralManager(delegate: self, queue: queue, options: [
            CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Receiver",
            CBCentralManagerOptionShowPowerAlertKey : true])
    }
    
    func startScan() {
        os_log("Scan start", log: log, type: .debug)
        guard let central = central, central.state == .poweredOn else {
            os_log("Scan start failed, bluetooth is not powered on", log: log, type: .fault)
            return
        }
        queue.async {
            central.scanForPeripherals(withServices: [serviceCBUUID])
        }
        queue.async {
            central.retrieveConnectedPeripherals(withServices: [serviceCBUUID]).forEach() { peripheral in
                os_log("Scan, reusing connected peripheral (peripheral=%s)", log: self.log, type: .debug, peripheral.identifier.uuidString)
                self.centralManager(central, didConnect: peripheral)
            }
        }
//        queue.async {
//            self.beacons.values.forEach() { beacon in
//                os_log("Scan, reissuing connect peripheral (peripheral=%s)", log: self.log, type: .debug, peripheral.identifier.uuidString)
//                self.connect("scan", beacon.peripheral)
//            }
//        }
//        queue.async {
//            let uuids = self.beacons.values.map() { beacon in beacon.peripheral.identifier }
//            central.retrievePeripherals(withIdentifiers: uuids).forEach() { peripheral in
//                os_log("Scan, reusing known peripheral (peripheral=%s)", log: self.log, type: .debug, peripheral.identifier.uuidString)
////                self.centralManager(central, didConnect: peripheral)
//            }
//        }
    }
    
    func stopScan() {
        os_log("Scan stop", log: log, type: .debug)
        guard let central = central else {
            return
        }
        queue.async {
            if central.isScanning {
                central.stopScan()
            }
        }
    }
        
    /**
     Schedule scan for beacons after a delay
     */
    func scheduleScan(_ source: String) {
        scanTimer?.cancel()
        scanTimer = DispatchSource.makeTimerSource(queue: queue)
        scanTimer?.schedule(deadline: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(8)))
        scanTimer?.setEventHandler { [weak self] in
            if let log = self?.log {
                os_log("Scheduled scan (source=%s)", log: log, type: .debug, source)
            }
            self?.startScan()
        }
        scanTimer?.resume()
    }
    
    private func connect(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        database.add("Receiver connect (uuid=\(uuid))")
        stopScan()
        queue.async {
            os_log("Connect (source=%s,peripheral=%s,delay=%d)", log: self.log, type: .debug, source, uuid, self.connectDelay.intValue)
            self.central.connect(peripheral, options: [CBConnectPeripheralOptionStartDelayKey : self.connectDelay])
        }
    }
    
    private func disconnect(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        queue.async {
            os_log("Disconnect (source=%s,peripheral=%s)", log: self.log, type: .debug, source, uuid)
            self.central.cancelPeripheralConnection(peripheral)
        }
    }
    
    private func readRSSI(_ source: String, _ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        guard peripheral.state == .connected else {
            return
        }
        queue.async {
            os_log("Read RSSI (source=%s,peripheral=%s)", log: self.log, type: .debug, source, uuid)
            peripheral.readRSSI()
        }
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
        beacons.values.forEach() { beacon in
            readRSSI("restoreState", beacon.peripheral)
        }
        database.add("Receiver restore")
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("State updated (toState=%s)", log: log, type: .debug, central.state.description)
        database.add("Receiver state update (state=\(central.state.description))")
        if (central.state == .poweredOn) {
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let uuid = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        if beacons[uuid] == nil {
            beacons[uuid] = Beacon(peripheral: peripheral)
            peripheral.delegate = self
            os_log("Discovered (peripheral=%s,rssi=%d,state=%s,new=true)", log: self.log, type: .debug, uuid, rssi, peripheral.state.description)
            database.add("Receiver discovered (uuid=\(uuid),new=true)")
        } else {
            os_log("Discovered (peripheral=%s,rssi=%d,state=%s,new=false)", log: self.log, type: .debug, uuid, rssi, peripheral.state.description)
            database.add("Receiver discovered (uuid=\(uuid),new=false)")
        }
        if peripheral.state != .connected {
            connect("didDiscover", peripheral)
        }
        scheduleScan("didDiscover")
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connected (peripheral=%s)", log: log, type: .debug, uuid)
        readRSSI("didConnect", peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Failed to connect (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        database.add("Receiver failed to connect (uuid=\(uuid),error=\(String(describing: error)))")
        connect("didFailToConnect", peripheral)
        scheduleScan("didFailToConnect")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnected (peripheral=%s,error=%s)", log: log, type: .debug, uuid, String(describing: error))
        database.add("Receiver disconnected (uuid=\(uuid),error=\(String(describing: error)))")
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
            queue.async {
                os_log("Discover services (peripheral=%s)", log: self.log, type: .debug, uuid)
                peripheral.discoverServices([serviceCBUUID])
            }
        }
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
                queue.async {
                    os_log("Discover characteristics (peripheral=%s)", log: self.log, type: .debug, uuid)
                    peripheral.discoverCharacteristics(nil, for: service)
                }
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
                queue.async {
                    os_log("Write value (peripheral=%s)", log: self.log, type: .debug, uuid)
                    peripheral.writeValue(self.emptyData, for: characteristic, type: .withResponse)
                }
                if let rssi = beacon.rssi {
                    statistics.add()
                    os_log("Detected beacon (method=discover,peripheral=%s,beaconCode=%s,rssi=%d,statistics={%s})", log: log, type: .debug, uuid, beaconCode.description, rssi, statistics.description)
                    queue.async {
                        for delegate in self.delegates {
                            delegate.receiver(didDetect: beaconCode, rssi: rssi)
                        }
                        self.database.add("Receiver detected (uuid=\(uuid),beacon=\(beaconCode),rssi=\(rssi))")
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
