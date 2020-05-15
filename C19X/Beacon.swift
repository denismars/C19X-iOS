import Foundation
import CoreBluetooth
import os

private let beaconQueue: DispatchQueue = DispatchQueue(label: "BeaconQueue")

/**
 * Beacon receiver for detecting a fixed service UUID and then discovering
 * a variable characteristic UUID where the upper 64-bit is fixed (same as
 * the service UUID) and the lower 64-bit is the beacon code.
 */
public class BeaconReceiver: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "BeaconReceiver")
    private var serviceCBUUID: CBUUID!
    private var beaconCharacteristicPrefix: Int64!
    private var centralManager: CBCentralManager?
    private var queue: [CBPeripheral] = []
    private var peripherals: [CBPeripheral:Timer] = [:]
    private var beaconCodes: [CBPeripheral:UInt64] = [:]
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
        let (prefix,_) = serviceUUID.intTupleValue
        self.beaconCharacteristicPrefix = prefix
    }
    
    public func start() {
        centralManager = CBCentralManager(delegate: self, queue: beaconQueue, options: [CBCentralManagerOptionRestoreIdentifierKey : "org.C19X.beaconReceiver",
             CBCentralManagerOptionShowPowerAlertKey : true])
    }
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        os_log("Central manager restored", log: log, type: .debug)
        centralManager = central
        for listener in listeners {
            listener.beaconListenerDidUpdate(central: central)
        }
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        os_log("Bluetooth state change (state=%s)", log: log, type: .debug, String(describing: central.state.rawValue))
        if (central.state == .poweredOn) {
            central.scanForPeripherals(withServices: [serviceCBUUID], options: nil)
            os_log("Start scan (serviceUUID=%s)", log: log, type: .debug, serviceCBUUID.description)
        } else {
            os_log("Stop scan", log: log, type: .debug)
        }
        for listener in listeners {
            listener.beaconListenerDidUpdate(central: central)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        os_log("Detected device (peripheral=%s,rssi=%d)", log: self.log, type: .debug, peripheral.identifier.description, RSSI.intValue)
        queue.append(peripheral)
        processQueue()
    }
    
    private func processQueue() {
        guard queue.count > 0 else {
            return
        }
        
        guard let central = centralManager, central.state == .poweredOn else {
            return
        }
        
        let peripheral = queue.remove(at: 0)
        os_log("Connecting to peripheral (peripheral=%s,queue=%d)", log: log, type: .debug, peripheral.identifier.description, queue.count)
        central.connect(peripheral)
        peripherals[peripheral] = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            self.disconnect(peripheral)
        }
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
        guard let services = peripheral.services else {
            disconnect(peripheral)
            return
        }
        for service in services {
            if (service.uuid == serviceCBUUID) {
                os_log("Discovered service (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
                peripheral.discoverCharacteristics(nil, for: service)
                return
            }
        }
        disconnect(peripheral)
    }
    
    // Filter characteristic by service UUID and decode beacon code
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else {
            disconnect(peripheral)
            return;
        }
        for characteristic in characteristics {
            os_log("Discovered characteristic (peripheral=%s,characteristic=%s)", log: log, type: .debug, peripheral.identifier.description, characteristic.uuid.uuidString)
            if let (prefix,suffix) = UUID(uuidString: characteristic.uuid.uuidString)?.intTupleValue, prefix == beaconCharacteristicPrefix {
                os_log("Discovered characteristic (peripheral=%s,beaconCode=%s)", log: log, type: .debug, peripheral.identifier.description, String(describing: suffix))
                beaconCodes[peripheral] = suffix
                peripheral.readRSSI()
                return
            }
        }
        disconnect(peripheral)
    }
    
    // Read RSSI value
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let beaconCode = beaconCodes[peripheral] else {
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
    
    // Disconnect peripheral on completion
    private func disconnect(_ peripheral: CBPeripheral) {
        os_log("Disconnecting from peripheral (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
        if let timer = peripherals[peripheral] {
            timer.invalidate()
            peripherals[peripheral] = nil
            beaconCodes[peripheral] = nil
        }
        guard let central = centralManager, central.state == .poweredOn else {
            return
        }
        peripheral.delegate = nil
        central.cancelPeripheralConnection(peripheral)
        os_log("Disconnected from peripheral (peripheral=%s)", log: log, type: .debug, peripheral.identifier.description)
        processQueue()
    }
}

class BeaconTransmitter: NSObject, CBPeripheralManagerDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "BeaconTransmitter")
    private var serviceUUID: UUID!
    private var serviceCBUUID: CBUUID!
    private var beaconCode: UInt64?
    private var peripheralManager: CBPeripheralManager?
    var listeners: [BeaconListener] = []
    /**
     Beacon code was set at this time
     */
    var beaconCodeSince: Date?

    init(_ serviceUUID: UUID) {
        super.init()
        self.serviceUUID = serviceUUID
        self.serviceCBUUID = CBUUID(nsuuid: serviceUUID)
    }
    
    func start() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: beaconQueue, options: [CBPeripheralManagerOptionRestoreIdentifierKey : "org.C19X.beaconTransmitter",
        CBPeripheralManagerOptionShowPowerAlertKey : true])
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        os_log("Peripheral manager restored", log: log, type: .debug)
        peripheralManager = peripheral
        peripheralManagerDidUpdateState(peripheral)
    }

    // Set beacon code and restart transmitter with new code if bluetooth is powered on
    func setBeaconCode(beaconCode: UInt64) {
        os_log("Set transmitter beacon code (beacon=%s)", log: self.log, type: .debug, beaconCode.description)
        self.beaconCode = beaconCode
        beaconCodeSince = Date()
        guard let _ = peripheralManager else {
            return
        }
        stopTransmitter()
        startTransmitter()
    }
    
    // Update notification characteristic
    func updateRandomCharacteristic() {
        guard let peripheralManager = peripheralManager else {
            return
        }
        guard peripheralManager.isAdvertising else {
            return
        }
        os_log("Update random characteristic", log: self.log, type: .debug)
        var bytes = [UInt8](repeating: 0, count: 1)
        let _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        //peripheralManager.updateValue(Data(bytes), for: randomCharacteristic, onSubscribedCentrals: nil)
    }
    
    // Start transmitter on bluetooth power on
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if (peripheral.state == .poweredOn) {
            startTransmitter()
        } else {
            stopTransmitter()
        }
        for listener in listeners {
            listener.beaconListenerDidUpdate(peripheral: peripheral)
        }
    }
    
    // Handle write request
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value {
                let byteArray = ByteArray(data)
                let beaconCode = byteArray.getUInt64(0)
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
        
        guard let beaconCode = beaconCode else {
            os_log("Start transmitter failed, missing beacon code", log: self.log, type: .fault)
            return
        }
            
        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else {
            os_log("Start transmitter failed, bluetooth is not on", log: self.log, type: .fault)
            return
        }
        
        let (serviceId, _) = serviceUUID.intTupleValue
        let characteristicCBUUID = CBUUID(nsuuid: UUID(numbers: (serviceId, beaconCode)))
        let characteristic = CBMutableCharacteristic(type: characteristicCBUUID, properties: [.write], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: serviceCBUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceCBUUID]])
        os_log("Start transmitter successful (beacon=%s,service=%s)", log: self.log, type: .debug, beaconCode.description, serviceCBUUID.description)
    }
    
    private func stopTransmitter() {
        os_log("Stop transmitter request", log: self.log, type: .debug)
        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn, peripheralManager.isAdvertising else {
            os_log("Stop transmitter unnecessary, already stopped", log: self.log, type: .debug)
            return
        }
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        os_log("Stop transmitter successful", log: self.log, type: .debug)
    }
}

class BeaconRepeater: AbstractBeaconListener {
    private var beaconTransmitter: BeaconTransmitter
    private var lastUpdate = Date.distantPast
    private let repeatInterval = TimeInterval(8)
    private var dispatchQueue = DispatchQueue(label: "BeaconRepeater")
    
    init(_ beaconTransmitter: BeaconTransmitter) {
        self.beaconTransmitter = beaconTransmitter
    }
    
    override func beaconListenerDidUpdate(beaconCode: UInt64, rssi: Int) {
        guard Date().timeIntervalSince(lastUpdate) > repeatInterval else {
            return
        }
        
        let timer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        timer.setEventHandler() {
            self.beaconTransmitter.updateRandomCharacteristic()
        }
        timer.schedule(deadline: DispatchTime.now() + repeatInterval)
        timer.resume()
    }
}

public protocol BeaconListener {
    func beaconListenerDidUpdate(central: CBCentralManager)
    
    func beaconListenerDidUpdate(peripheral: CBPeripheralManager)
    
    func beaconListenerDidUpdate(beaconCode:UInt64, rssi:Int)
}

public class AbstractBeaconListener: BeaconListener {
    public func beaconListenerDidUpdate(central: CBCentralManager) {}
    
    public func beaconListenerDidUpdate(peripheral: CBPeripheralManager) {}

    public func beaconListenerDidUpdate(beaconCode:UInt64, rssi:Int) {}
}
