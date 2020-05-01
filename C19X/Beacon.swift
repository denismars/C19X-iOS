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

public class Beacon: NSObject, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "Beacon")
    private var serviceId: Int64!
    private var serviceCBUUID: CBUUID!
    private var characteristicUuidPrefix: String!
    private var beaconCode: Int64?
    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    private var peripherals = [CBPeripheral : Int]()
    public var listeners: [BeaconListener] = []

    public init(serviceId: Int64) {
        super.init()
        self.serviceId = serviceId
        self.serviceCBUUID = CBUUID(nsuuid: UUID(numbers: (serviceId, 0)))
        self.characteristicUuidPrefix = String(UUID(numbers: (serviceId, 0)).uuidString.prefix(18))
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // TRANSMITTER ==========
    
    // Set beacon code and restart transmitter with new code if bluetooth is powered on
    public func setBeaconCode(beaconCode: Int64) {
        os_log("Set transmitter beacon code (beacon=%s)", log: self.log, type: .debug, beaconCode.description)
        self.beaconCode = beaconCode
        if (peripheralManager.isAdvertising) {
            stopTransmitter()
            _ = startTransmitter()
        }
    }
    
    // Start transmitter on bluetooth power on
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if (peripheral.state == .poweredOn) {
            _ = startTransmitter()
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
    private func startTransmitter() -> Bool {
        os_log("Start transmitter request", log: self.log, type: .debug)
        if (beaconCode == nil) {
            os_log("Start transmitter failed, missing beacon code", log: self.log, type: .fault)
            return false
        }
            
        if (peripheralManager.state != .poweredOn) {
            os_log("Start transmitter failed, bluetooth is not on", log: self.log, type: .fault)
            return false
        }
        
        let characteristicCBUUID = CBUUID(nsuuid: UUID(numbers: (serviceId, beaconCode!)))
        
        let characteristic = CBMutableCharacteristic(type: characteristicCBUUID, properties: [.write], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: serviceCBUUID, primary: true)
        service.characteristics = [characteristic]
        
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceCBUUID]])
        
        os_log("Start transmitter successful (beacon=%s,service=%s)", log: self.log, type: .debug, beaconCode!.description, serviceCBUUID.description)
        return true
    }
    
    private func stopTransmitter() {
        os_log("Stop transmitter request", log: self.log, type: .debug)
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
            peripheralManager.removeAllServices()
            os_log("Stop transmitter successful", log: self.log, type: .debug)
        } else {
            os_log("Stop transmitter unnecessary, already stopped", log: self.log, type: .debug)
        }
    }

    // RECEIVER ==========
    
    // Start receiver on bluetooth power on
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if (central.state == .poweredOn) {
            _ = startReceiver()
        } else {
            stopReceiver()
        }
    }
    
    // Start beacon receiver
    public func startReceiver() -> Bool {
        os_log("Start receiver request", log: self.log, type: .debug)
        
        if (centralManager.state != .poweredOn) {
            os_log("Start receiver failed, bluetooth is not on", log: self.log, type: .fault)
            return false
        }
        
        if (centralManager.isScanning) {
            centralManager.stopScan()
        }
        
        let serviceUUID = UUID(numbers: (serviceId, 0))
        let serviceCBUUID = CBUUID(nsuuid: serviceUUID)

        centralManager.scanForPeripherals(
            withServices: [serviceCBUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        os_log("Start receiver successful (serviceUUID=%s)", log: self.log, type: .debug, serviceCBUUID.description)
        return true
    }
    
    public func stopReceiver() {
        os_log("Stop receiver request", log: self.log, type: .debug)
        
        if (centralManager.state != .poweredOn) {
            os_log("Stop receiver failed, bluetooth is not on", log: self.log, type: .fault)
            return
        }

        if (centralManager.isScanning) {
            centralManager.stopScan()
            os_log("Stop receiver successful", log: self.log, type: .debug)
        } else {
            os_log("Stop receiver unnecessary, already stopped", log: self.log, type: .debug)
        }
    }

    // Connect to peripheral if not currently connected
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        os_log("Detected device (peripheral=%s,rssi=%d)", log: self.log, type: .debug, peripheral.identifier.description, RSSI.intValue)
        if (peripherals[peripheral] == nil) {
            peripherals[peripheral] = RSSI.intValue
            centralManager.connect(peripheral)
        } else if (peripherals[peripheral]! < RSSI.intValue) {
            peripherals[peripheral] = RSSI.intValue
        }
    }
    
    // Discover services on peripheral connect
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self;
        peripheral.discoverServices([serviceCBUUID])
    }
    
    // Discover characteristics on peripheral service discovery
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            disconnect(peripheral)
            return
        }
        if (services.count == 0) {
            disconnect(peripheral)
        } else {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
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
                let beaconCode = Int64(beaconCodeUuid, radix: 16)
                let rssi = peripherals[peripheral]
                
                if (beaconCode != nil && rssi != nil) {
                    os_log("Detected beacon (method=scan,beacon=%s,rssi=%d)", log: self.log, type: .debug, beaconCode!.description, rssi!)
                    for listener in listeners {
                        listener.beaconListenerDidUpdate(beaconCode: beaconCode!, rssi: rssi!)
                    }
                }
            }
        }
        disconnect(peripheral)
    }
    
    // Disconnect peripheral on completion
    private func disconnect(_ peripheral: CBPeripheral) {
        if (peripherals[peripheral] != nil) {
            centralManager.cancelPeripheralConnection(peripheral)
            peripherals[peripheral] = nil
        }
    }
}

public protocol BeaconListener {
    func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int)
}

public class AbstractBeaconListener: BeaconListener {
    public func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int) {}
}
