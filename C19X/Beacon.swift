//
//  Beacon.swift
//  C19X
//
//  Created by Freddy Choi on 22/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import CoreBluetooth
import os


public class BeaconReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "BeaconReceiver")
    private let delay:TimeInterval = 10
    private var serviceCBUUID: CBUUID!
    private var characteristicUuidPrefix: String!
    private var centralManager: CBCentralManager!
    private var peripherals: Set<CBPeripheral> = []
    private var peripheralsBeaconCode = [CBPeripheral : Int64]()
    public var lastScanTimestamp: Date?
    public var listeners: [BeaconListener] = []
    private var scanActive = true

    public init(_ serviceUUID: UUID) {
        super.init()
        self.serviceCBUUID = CBUUID(nsuuid: serviceUUID)
        self.characteristicUuidPrefix = String(serviceUUID.uuidString.prefix(18))
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // Stop receiver on bluetooth power off
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if (central.state == .poweredOn) {
            startScan()
        } else {
            stopScan()
        }
    }
    
    // Start beacon receiver
    public func startScan() {
        os_log("Start receiver request", log: log, type: .debug)
        scanActive = true
        guard centralManager.state == .poweredOn else {
            os_log("Start receiver failed, bluetooth is not on", log: log, type: .fault)
            return
        }
        
        if (centralManager.isScanning) {
            centralManager.stopScan()
        }
        centralManager.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
        os_log("Start receiver successful (serviceUUID=%s)", log: log, type: .debug, serviceCBUUID.description)
        lastScanTimestamp = Date()
        for listener in listeners {
            listener.beaconListenerDidUpdate(didStartScan: lastScanTimestamp!)
        }
    }
        
    public func stopScan() {
        os_log("Stop receiver request", log: log, type: .debug)
        scanActive = false
        if (centralManager.isScanning) {
            centralManager.stopScan()
            os_log("Stop receiver successful", log: log, type: .debug)
        } else {
            os_log("Stop receiver unnecessary, already stopped", log: log, type: .debug)
        }
    }

    // Connect to peripheral if not currently connected
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        os_log("Detected device (peripheral=%s,rssi=%d)", log: self.log, type: .debug, peripheral.identifier.description, RSSI.intValue)
        if (!peripherals.contains(peripheral)) {
            os_log("Connecting to peripheral (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
            if (centralManager.isScanning) {
                centralManager.stopScan()
            }
            peripherals.insert(peripheral)
            centralManager.connect(peripheral)
        }
    }
    
    // Discover services on peripheral connect
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self;
        peripheral.discoverServices([serviceCBUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnect(peripheral)
    }
    
    // Discover characteristics on peripheral service discovery
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, services.count > 0 else {
            disconnect(peripheral)
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    // Filter characteristic by service ID and decode beacon code
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            disconnect(peripheral)
            return;
        }
        for characteristic in characteristics {
            if (characteristic.uuid.uuidString.starts(with: characteristicUuidPrefix)) {
                let beaconCodeUuid = String(characteristic.uuid.uuidString.suffix(17).uppercased().filter("0123456789ABCDEF".contains))
                peripheralsBeaconCode[peripheral] = Int64(beaconCodeUuid, radix: 16)
                peripheral.readRSSI()
                return
            }
        }
        disconnect(peripheral)
    }
    
    // Read RSSI value
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let beaconCode = peripheralsBeaconCode[peripheral] {
            let rssi = RSSI.intValue
            os_log("Detected beacon (method=scan,beacon=%s,rssi=%d)", log: log, type: .debug, beaconCode.description, rssi)
            for listener in listeners {
                listener.beaconListenerDidUpdate(beaconCode: beaconCode, rssi: rssi)
            }
        }
        disconnect(peripheral)
    }
        
    // Disconnect peripheral on completion
    private func disconnect(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
        peripherals.remove(peripheral)
        os_log("Disconnected from peripheral (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
        if (scanActive) {
            DispatchQueue.main.asyncAfter(deadline: .future(by: delay)) {
                self.startScan()
            }
        }
    }
}

public class BeaconTransmitter: NSObject, CBPeripheralManagerDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "BeaconTransmitter")
    private var serviceUUID: UUID!
    private var serviceCBUUID: CBUUID!
    private var beaconCode: Int64?
    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    private var peripherals: Set<CBPeripheral> = []
    private var peripheralsBeaconCode = [CBPeripheral : Int64]()
    public var listeners: [BeaconListener] = []

    public init(_ serviceUUID: UUID) {
        super.init()
        self.serviceUUID = serviceUUID
        self.serviceCBUUID = CBUUID(nsuuid: serviceUUID)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    // Set beacon code and restart transmitter with new code if bluetooth is powered on
    public func setBeaconCode(beaconCode: Int64) {
        os_log("Set transmitter beacon code (beacon=%s)", log: self.log, type: .debug, beaconCode.description)
        self.beaconCode = beaconCode
        if (peripheralManager.isAdvertising) {
            stopTransmitter()
            startTransmitter()
        }
    }
    
    // Start transmitter on bluetooth power on
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if (peripheral.state == .poweredOn) {
            startTransmitter()
        } else {
            stopTransmitter()
        }
    }
    
    // Handle write request
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if (request.value != nil) {
                let byteArray = ByteArray(request.value!)
                let beaconCode = byteArray.getInt64(0);
                let rssi = Int(byteArray.getInt32(8));
                os_log("Detected beacon (method=write,beacon=%s,rssi=%d)", log: self.log, type: .debug, beaconCode.description, rssi)
                for listener in listeners {
                    listener.beaconListenerDidUpdate(beaconCode: beaconCode, rssi: rssi)
                }
            }
        }
    }
    
    // Start beacon transmitter
    private func startTransmitter() {
        os_log("Start transmitter request", log: self.log, type: .debug)
        
        guard beaconCode != nil else {
            os_log("Start transmitter failed, missing beacon code", log: self.log, type: .fault)
            return
        }
            
        guard peripheralManager.state == .poweredOn else {
            os_log("Start transmitter failed, bluetooth is not on", log: self.log, type: .fault)
            return
        }
        
        let (serviceId, _) = serviceUUID.intTupleValue
        let characteristicCBUUID = CBUUID(nsuuid: UUID(numbers: (serviceId, beaconCode!)))
        let characteristic = CBMutableCharacteristic(type: characteristicCBUUID, properties: [.write], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: serviceCBUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceCBUUID]])
        os_log("Start transmitter successful (beacon=%s,service=%s)", log: self.log, type: .debug, beaconCode!.description, serviceCBUUID.description)
    }
    
    private func stopTransmitter() {
        os_log("Stop transmitter request", log: self.log, type: .debug)
        guard peripheralManager.isAdvertising else {
            os_log("Stop transmitter unnecessary, already stopped", log: self.log, type: .debug)
            return
        }
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        os_log("Stop transmitter successful", log: self.log, type: .debug)
    }
}

public protocol BeaconListener {
    func beaconListenerDidUpdate(didStartScan:Date)
    
    func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int)
}

public class AbstractBeaconListener: BeaconListener {
    public func beaconListenerDidUpdate(didStartScan: Date) {}
    
    public func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int) {}
}
