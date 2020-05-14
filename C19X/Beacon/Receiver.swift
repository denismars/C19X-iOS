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
    var rssi: RSSI
    var code: BeaconCode?
    var timer: Timer?
    private var createdAt: Date
    /**
     Beacon identifier is the same as the peripheral identifier.
     */
    var uuidString: String { get { peripheral.identifier.uuidString } }
    /**
     Beacon data is currently being acquired via asynchonous callbacks.
     */
    var isConnected: Bool { get { timer != nil } }
    /**
     Beacon expires if beacon code was acquired yesterday (day code changes at midnight everyday) or 30 minutes has elapsed.
     */
    var isExpired: Bool { get {
        let now = Date()
        let today = UInt64(now.timeIntervalSince1970).dividedReportingOverflow(by: UInt64(86400))
        let createdOnDay = UInt64(createdAt.timeIntervalSince1970).dividedReportingOverflow(by: UInt64(86400))
        return createdOnDay != today || createdAt.distance(to: Date()) > TimeInterval(1800)
    } }
    
    init(peripheral: CBPeripheral, rssi: RSSI) {
        self.peripheral = peripheral
        self.rssi = rssi
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
    private var central: CBCentralManager!
    /**
    Characteristic UUID encodes the characteristic identifier in the upper 64-bits and the beacon code in the lower 64-bits
    to achieve reliable read of beacon code without an actual GATT read operation.
    */
    private let (characteristicCBUUIDUpper,_) = characteristicCBUUID.values
    private var queue: [String] = []
    private var peripherals: [String: Beacon] = [:]
    private var delegate: ReceiverDelegate!
    /**
     Sample of scan intervals for monitoring scan frequency in background and foreground modes.
     */
    private let scanInterval = TimeIntervalSample()

    required init(_ delegate: ReceiverDelegate?) {
        self.delegate = delegate
        super.init()
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
        central.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
        scanInterval.add()
        if let mean = scanInterval.mean, let sd = scanInterval.standardDeviation, let min = scanInterval.min, let max = scanInterval.max {
            os_log("Scanning (count=%d,mean=%f,standardDeviation=%f,min=%f,max=%f)", log: log, type: .debug, scanInterval.count, mean, sd, min, max)
        } else {
            os_log("Scanning", log: log, type: .debug)
        }
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
            startScan()
            return
        }
        // Timeout set to under 10 seconds to fit within iOS background processing time window
        beacon.timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
            os_log("Connect timeout (peripheral=%s)", log: self.log, type: .debug, beacon.uuidString)
            // Disconnect will always retrigger startScan() via processQueue()
            self.disconnect(beacon.peripheral)
        }
        central.connect(beacon.peripheral)
        os_log("Connecting (peripheral=%s)", log: log, type: .debug, beacon.uuidString)
    }
    
    /**
     Process peripherals in order of discovery.
     */
    private func processQueue() {
        os_log("Process queue (count=%d)", log: log, type: .debug, queue.count)
        guard !queue.isEmpty, let beacon = peripherals[queue.removeFirst()] else {
            os_log("Queue is empty, start scan", log: log, type: .debug, queue.count)
            startScan()
            return
        }
        os_log("Process queued beacon (peripheral=%s)", log: log, type: .debug, beacon.uuidString)
        stopScan()
        connect(beacon)
    }
    
    /**
     Disconnect peripheral, retaining beacon code for reuse.
     */
    private func disconnect(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Disconnect (peripheral=%s)", log: log, type: .debug, uuid)
        // Cancel timeout timer
        if let beacon = peripherals[uuid] {
            if let timer = beacon.timer {
                os_log("Cancel timer (peripheral=%s)", log: log, type: .debug, uuid)
                timer.invalidate()
                beacon.timer = nil
            }
            peripheral.delegate = nil
        }
        if let central = central, central.state == .poweredOn {
            os_log("Cancel connection (peripheral=%s)", log: log, type: .debug, uuid)
            central.cancelPeripheralConnection(peripheral)
        }
        os_log("Disconnected (peripheral=%s)", log: log, type: .debug, uuid)
        // Process queue again to start scan
        processQueue()
    }

    // MARK: - CBCentralManagerDelegate
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        os_log("State restored", log: log, type: .debug)
        self.central = central
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
        if let beacon = peripherals[uuid] {
            // Reuse existing information where possible
            if beacon.isExpired {
                // Refresh beacon code if expired
                if !beacon.isConnected {
                    // Queue peripheral for refresh if not already in progress
                    peripherals[uuid] = Beacon(peripheral: peripheral, rssi: rssi)
                    if (!queue.contains(uuid)) {
                        queue.append(uuid)
                    }
                }
            } else if let beaconCode = beacon.code {
                // Beacon code already known and not expired, no need to reconnect
                os_log("Detected beacon (method=scan,peripheral=%s,beaconCode=%s,rssi=%d)", log: log, type: .debug, uuid, beaconCode.description, rssi)
                if let delegate = delegate {
                    delegate.receiver(didDetect: beaconCode, rssi: rssi)
                }
            }
        } else {
            // Get beacon code for new peripheral
            peripherals[uuid] = Beacon(peripheral: peripheral, rssi: rssi)
            if (!queue.contains(uuid)) {
                queue.append(uuid)
            }
        }
        // Process queue of peripherals (or start scan again when queue is empty)
        processQueue()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connected (peripheral=%s)", log: log, type: .debug, uuid)
        peripheral.delegate = self;
        peripheral.discoverServices([serviceCBUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let uuid = peripheral.identifier.uuidString
        os_log("Connect failed (peripheral=%s)", log: log, type: .debug, uuid)
        disconnect(peripheral)
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
                if let beacon = peripherals[uuid] {
                    beacon.code = beaconCode
                    os_log("Detected beacon (method=connect,peripheral=%s,beaconCode=%s,rssi=%d)", log: log, type: .debug, uuid, beaconCode.description, beacon.rssi)
                    if let delegate = delegate {
                        delegate.receiver(didDetect: beaconCode, rssi: beacon.rssi)
                    }
                } else {
                    // This should never happen, peripheral has been removed before disconnect
                    os_log("Beacon entry missing (peripheral=%s)", log: log, type: .fault, uuid)
                }
                disconnect(peripheral)
                return
            }
        }
        disconnect(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        os_log("Discovered service modification (peripheral=%s)", log: log, type: .debug, peripheral.identifier.uuidString)
    }
}
