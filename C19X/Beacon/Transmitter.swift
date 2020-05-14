//
//  Transmitter.swift
//  C19X
//
//  Created by Freddy Choi on 24/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import os

/**
Beacon transmitter broadcasts fixed service UUID to enable background scan.
*/
protocol Transmitter {
    init(_ delegate:ReceiverDelegate?, beaconCodes: BeaconCodes)
    /**
     Change beacon code being broadcasted by adjusting the lower 64-bit of characteristic UUID.
     The beacon code is supplied by the beacon codes generator.
     */
    func updateBeaconCode()
}

/**
 Service UUID for beacon service.
 */
let serviceCBUUID = CBUUID(string: "0022D481-83FE-1F13-0000-000000000000")

/**
 Characteristic UUID template for beacon service. Beacon code is encoded in the lower 64-bit of the 128-bit UUID.
 In theory, the whole 128-bit can be used for the beacon code as the service only exposes one characteristic. The
 beacon code has been encoded in the characteristic UUID to enable reliable read without an actual read operation,
 and also enables the characteristic to be a writable characteristic for non-transmitting Android devices to submit
 their beacon code and RSSI as data.
 */
let characteristicCBUUID = CBUUID(string: "0022D481-83FE-1F13-0000-000000000000")

class ConcreteTransmitter : NSObject, Transmitter, CBPeripheralManagerDelegate {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "Transmitter")
    private let beaconCodes: BeaconCodes!
    private var peripheral: CBPeripheralManager!
    /**
     Receiver delegate for capturing beacon code and RSSI from non-transmitting Android devices that write
     data to the beacon characteristic to notify the transmitter of their presence.
     */
    private var delegate: ReceiverDelegate!

    required init(_ delegate:ReceiverDelegate?, beaconCodes: BeaconCodes) {
        self.delegate = delegate
        self.beaconCodes = beaconCodes
        super.init()
        self.peripheral = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionRestoreIdentifierKey : "org.C19X.beacon.Transmitter",
        CBPeripheralManagerOptionShowPowerAlertKey : true])
    }
    
    func updateBeaconCode() {
        os_log("Update beacon code", log: log, type: .debug)
        guard let peripheral = peripheral else {
            os_log("Update denied, no peripheral", log: log, type: .fault)
            return
        }
        guard peripheral.state == .poweredOn else {
            os_log("Update denied, bluetooth is not on", log: log, type: .fault)
            return
        }
        guard let beaconCode = beaconCodes.get() else {
            os_log("Update denied, beacon codes exhausted", log: log, type: .fault)
            return
        }
        if peripheral.isAdvertising {
            peripheral.stopAdvertising()
        }
        peripheral.removeAllServices()
        let service = CBMutableService(type: serviceCBUUID, primary: true)
        // Beacon code is encoded in the lower 64-bits of the characteristic UUID
        let (upper, _) = characteristicCBUUID.values
        let beaconCharacteristicCBUUID = CBUUID(upper: upper, lower: beaconCode)
        let beaconCharacteristic = CBMutableCharacteristic(type: beaconCharacteristicCBUUID, properties: [.write], value: nil, permissions: [.writeable])
        service.characteristics = [beaconCharacteristic]
        peripheral.add(service)
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceCBUUID]])
        os_log("Update beacon code successful (code=%s,characteristic=%s)", log: self.log, type: .debug, beaconCode.description, beaconCharacteristicCBUUID.uuidString)
    }
    
    // MARK:- CBPeripheralManagerDelegate
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        os_log("State restored", log: log, type: .debug)
        updateBeaconCode()
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        os_log("Update state (state=%s)", log: log, type: .debug, peripheral.state.description)
        if (peripheral.state == .poweredOn) {
            updateBeaconCode()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let uuid = request.central.identifier.uuidString
            if let data = request.value, let beaconData = BeaconData(data) {
                peripheral.respond(to: request, withResult: .success)
                os_log("Detected beacon (method=write,peripheral=%s,beaconCode=%s,rssi=%d)", log: log, type: .debug, uuid, beaconData.beaconCode.description, beaconData.rssi)
                if let delegate = delegate {
                    delegate.receiver(didDetect: beaconData.beaconCode, rssi: beaconData.rssi)
                }
            } else {
                os_log("Invalid write request (peripheral=%s)", log: log, type: .fault, uuid)
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            }
        }
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
