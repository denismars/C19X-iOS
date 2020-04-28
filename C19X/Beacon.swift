//
//  Beacon.swift
//  C19X
//
//  Created by Freddy Choi on 22/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import CoreBluetooth

public class Beacon: NSObject, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var serviceId: Int64!
    private var serviceCBUUID: CBUUID!
    private var characteristicUuidPrefix: String!
    private var beaconCode: Int64!
    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    private var peripherals = [CBPeripheral : NSNumber]()
    public var listeners: [BeaconListener] = []

    public init(serviceId: Int64, beaconCode: Int64) {
        super.init()
        self.serviceId = serviceId
        self.serviceCBUUID = CBUUID(nsuuid: UUID(numbers: (serviceId, 0)))
        self.characteristicUuidPrefix = String(UUID(numbers: (serviceId, 0)).uuidString.prefix(18))
        self.beaconCode = beaconCode
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // TRANSMITTER ==========
    
    // Set beacon code and restart transmitter with new code if bluetooth is powered on
    public func setBeaconCode(beaconCode: Int64) {
        self.beaconCode = beaconCode
        startTransmitter()
    }
    
    // Start transmitter on bluetooth power on
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if (peripheral.state == .poweredOn) {
            startTransmitter()
        }
    }
    
    // Handle write request
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if (request.value != nil) {
                let byteArray = ByteArray(request.value!)
                let beaconCode = byteArray.getInt64(0);
                let rssi = Int(byteArray.getInt32(8));
                for listener in listeners {
                    listener.beaconListenerDidUpdate(beaconCode: beaconCode, rssi: rssi)
                }
            }
        }
    }
    
    // Start beacon transmitter
    private func startTransmitter() {
        if (peripheralManager.state != .poweredOn) {
            return
        }
        
        let characteristicCBUUID = CBUUID(nsuuid: UUID(numbers: (serviceId, beaconCode)))
        
        let characteristic = CBMutableCharacteristic(type: characteristicCBUUID, properties: [.write], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: serviceCBUUID, primary: true)
        service.characteristics = [characteristic]
        
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceCBUUID]])
        
        debugPrint("Transmitter started (beaconCode=\(beaconCode!),service=\(serviceCBUUID!),characteristic=\(characteristicCBUUID))")
    }

    // RECEIVER ==========
    
    // Start receiver on bluetooth power on
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if (central.state == .poweredOn) {
            startReceiver()
        }
    }
    
    // Start beacon receiver
    private func startReceiver() {
        if (centralManager.isScanning) {
            centralManager.stopScan()
        }
        
        let serviceUUID = UUID(numbers: (serviceId, 0))
        let serviceCBUUID = CBUUID(nsuuid: serviceUUID)

        centralManager.scanForPeripherals(
            withServices: [serviceCBUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        debugPrint("Receiver started")
    }

    // Connect to peripheral if not currently connected
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if (peripherals[peripheral] == nil) {
            peripherals[peripheral] = RSSI
            centralManager.connect(peripheral)
        } else if (peripherals[peripheral]!.decimalValue < RSSI.decimalValue) {
            peripherals[peripheral] = RSSI
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
                    for listener in listeners {
                        listener.beaconListenerDidUpdate(beaconCode: beaconCode!, rssi: rssi!.intValue)
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

public protocol BeaconListener: AnyObject {
    func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int)
}
