import Foundation
import CoreBluetooth
import os

/**
 * Beacon receiver for detecting a fixed service UUID and then discovering
 * a variable characteristic UUID where the upper 64-bit is fixed (same as
 * the service UUID) and the lower 64-bit is the beacon code.
 */
public class BeaconReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "BeaconReceiver")
    private var serviceCBUUID: CBUUID!
    private var characteristicUuidPrefix: String!
    private var centralManager: CBCentralManager!
    private var peripherals: Set<CBPeripheral> = []
    private var peripheralBeaconCodes: [CBPeripheral:Int64] = [:]
    public var listeners: [BeaconListener] = []

    /**
     Beacon receiver that scans for a fixed service UUID. The receiver will scan in the foreground and background, and
     state restoration has been enabled to receive events when the app has been suspected and phone restarts.
     
     Please note, state restoration cannot survive app force quit by the user.
     
     - Parameter serviceUUID: Service UUID for identifying the beacon
     */
    public init(_ serviceUUID: UUID) {
        super.init()
        self.serviceCBUUID = CBUUID(nsuuid: serviceUUID)
        self.characteristicUuidPrefix = String(serviceUUID.uuidString.prefix(18))
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beaconReceiver"])
    }
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        os_log("Central manager restored", log: log, type: .debug)
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("Bluetooth state change (state=%s)", log: log, type: .debug, String(describing: central.state))
        if (central.state == .poweredOn) {
            centralManager.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
            os_log("Start scan (serviceUUID=%s)", log: log, type: .debug, serviceCBUUID.description)
        } else {
            centralManager.stopScan()
            os_log("Stop scan", log: log, type: .debug)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        os_log("Detected device (peripheral=%s,rssi=%d)", log: self.log, type: .debug, peripheral.identifier.description, RSSI.intValue)
        guard peripherals.count == 0 else {
            os_log("Connection in progress, skipping device (peripherals=%s)", log: log, type: .debug, peripheral.identifier.description)
            return
        }
        guard centralManager.state == .poweredOn else {
            os_log("Bluetooth is off, skipping device (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
            return
        }
        os_log("Connecting to peripheral (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
        centralManager.connect(peripheral)
        peripherals.insert(peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self;
        peripheral.discoverServices([serviceCBUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnect(peripheral)
    }
    
    // Filter service by service UUID
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, services.count > 0 else {
            disconnect(peripheral)
            return
        }
        for service in services {
            if (service.uuid == serviceCBUUID) {
                peripheral.discoverCharacteristics(nil, for: service)
                return
            }
        }
        disconnect(peripheral)
    }
    
    // Filter characteristic by service UUID and decode beacon code
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics, characteristics.count > 0 else {
            disconnect(peripheral)
            return;
        }
        for characteristic in characteristics {
            if (characteristic.uuid.uuidString.starts(with: characteristicUuidPrefix)) {
                let beaconCodeUuid = String(characteristic.uuid.uuidString.suffix(17).uppercased().filter("0123456789ABCDEF".contains))
                peripheralBeaconCodes[peripheral] = Int64(beaconCodeUuid, radix: 16)
                peripheral.readRSSI()
                return
            }
        }
        disconnect(peripheral)
    }
    
    // Read RSSI value
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let beaconCode = peripheralBeaconCodes[peripheral] else {
            disconnect(peripheral)
            return;
        }
        let rssi = RSSI.intValue
        os_log("Detected beacon (method=scan,beacon=%s,rssi=%d)", log: log, type: .debug, beaconCode.description, rssi)
        for listener in listeners {
            listener.beaconListenerDidUpdate(beaconCode: beaconCode, rssi: rssi)
        }
        disconnect(peripheral)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    }
        
    // Disconnect peripheral on completion
    private func disconnect(_ peripheral: CBPeripheral) {
        peripherals.remove(peripheral)
        peripheralBeaconCodes[peripheral] = nil
        guard centralManager.state == .poweredOn else {
            return
        }
        centralManager.cancelPeripheralConnection(peripheral)
        os_log("Disconnected from peripheral (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
    }
}

public class BeaconTransmitter: NSObject, CBPeripheralManagerDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "BeaconTransmitter")
    private var serviceUUID: UUID!
    private var serviceCBUUID: CBUUID!
    private var beaconCode: Int64?
    private var peripheralManager: CBPeripheralManager!
    public var listeners: [BeaconListener] = []
    /**
     Beacon code was set at this time
     */
    public var beaconCodeSince: Date?

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
        beaconCodeSince = Date()
        stopTransmitter()
        startTransmitter()
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
            if let data = request.value {
                let byteArray = ByteArray(data)
                let beaconCode = byteArray.getInt64(0)
                let rssi = Int(byteArray.getInt32(8))
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
    func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int)
}

public class AbstractBeaconListener: BeaconListener {
    public func beaconListenerDidUpdate(beaconCode:Int64, rssi:Int) {}
}
