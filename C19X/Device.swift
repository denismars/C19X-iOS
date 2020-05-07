//
//  Device.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CryptoKit
import BigInt
import CoreData
import os

public class Device: AbstractNetworkListener {
    private let log = OSLog(subsystem: "org.C19X", category: "Device")
    private static let serviceUUID = UUID(uuidString: "0022D481-83FE-1F13-0000-000000000000")!
    
    public static let statusNormal = 0
    public static let statusSymptom = 1
    public static let statusDiagnosis = 2
    
    private let lookupCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("lookup")
    
    public var serialNumber: UInt64 = 0
    public var sharedSecret: Data = Data()
    private var status: Int = 0
    
    public var codes: Codes?
    public var message: String = ""
    public var lookup: Data = Data(count: 1)
    private var serverDataUpdateSince: Date?
    
    public var parameters = Parameters()
    public var contactRecords = ContactRecords()
    public var network = Network()
    public var beaconTransmitter = BeaconTransmitter(serviceUUID)
    public var beaconReceiver = BeaconReceiver(serviceUUID)
    public var riskAnalysis = RiskAnalysis()
    
    override init() {
        super.init()
        
        beaconReceiver.listeners.append(contactRecords)
        beaconTransmitter.listeners.append(contactRecords)
        network.listeners.append(self)
    }
    
    private func scheduleUpdates() {
        update()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.future(by: parameters.getBeaconCodeUpdateInterval(), randomise: 120)) {
            self.update()
        }
    }
    
    /**
     All device update tasks, e.g. beacon code rotation, downloads. Calling before time limits has no effect.
     */
    public func update(callback: (() -> Void)? = nil) {
        
        // Rotate beacon code and enforce retention
        if beaconTransmitter.beaconCodeSince == nil || beaconTransmitter.beaconCodeSince!.distance(to: Date()) > parameters.getBeaconCodeUpdateInterval() {
            changeBeaconCode()
            enforceRetentionPeriod()
        }
        
        if serverDataUpdateSince == nil || serverDataUpdateSince!.distance(to: Date()) > (24 * 60 * 60) {
            // No registration required
            network.getLookupInBackground()
            network.getTimeFromServerAndSynchronise() { t in
                self.network.getParameters() { p in
                    // Registration required
                    guard self.isRegistered() else {
                        if callback != nil {
                            callback!()
                        }
                        return
                    }
                    self.network.getMessage(serialNumber: self.serialNumber, sharedSecret: self.sharedSecret) { m in
                        if callback != nil {
                            callback!()
                        }
                    }
                }
            }
        }
        if callback != nil {
            callback!()
        }
    }
    
    public func isRegistered() -> Bool {
        return codes != nil
    }
    
    public func set(status: Int) {
        if let _ = Keychain.shared.set("status", status.description) {
            self.status = status
            riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: parameters, lookup: lookup)
        }
    }
    
    public func getStatus() -> Int {
        return status
    }
    
    private func changeBeaconCode() {
        os_log("Change beacon code request", log: log, type: .debug)
        guard let beaconCodes = codes else {
            os_log("Change beacon code failed, pending registration", log: log, type: .fault)
            return
        }
        let beaconCode = beaconCodes.get(parameters.getRetentionPeriodInDays())
        beaconTransmitter.setBeaconCode(beaconCode: beaconCode)
        os_log("Change beacon code successful (code=%s)", log: log, type: .debug, beaconCode.description)
    }
    
    private func enforceRetentionPeriod() {
        os_log("Enforce retention period", log: log, type: .debug)
        let date = Date() - parameters.getRetentionPeriod()
        contactRecords.remove(recordsBefore: date)
        os_log("Enforce retention period successful (cutoff=%s)", log: log, type: .debug, date.description)
    }
    
    public func reset() {
        os_log("Reset", log: log, type: .error)
        let _ = Keychain.shared.remove("serialNumber")
        let _ = Keychain.shared.remove("sharedSecret")
        let _ = Keychain.shared.remove("status")
        parameters.reset()
        contactRecords.reset()
        if FileManager().fileExists(atPath: lookupCacheUrl.path) {
            do {
                try FileManager().removeItem(atPath: lookupCacheUrl.path)
            } catch {}
        }
    }
    
    public func start() {
        os_log("Start", log: log, type: .debug)
        // Registration
        if
            let serialNumberKeychainValue = Keychain.shared.get("serialNumber"),
            let sharedSecretKeychainValue = Keychain.shared.get("sharedSecret"),
            let serialNumber = UInt64(serialNumberKeychainValue),
            let sharedSecret = Data(base64Encoded: sharedSecretKeychainValue) {
            self.serialNumber = serialNumber
            self.sharedSecret = sharedSecret
            self.codes = Codes(sharedSecret: self.sharedSecret)
            os_log("Registration loaded from keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
        } else {
            os_log("Registration required", log: log, type: .info)
            network.getRegistration()
        }
        
        // Status
        if
            let statusKeychainValue = Keychain.shared.get("status"),
            let status = Int(statusKeychainValue) {
            self.status = status
            os_log("Status loaded from keychain (status=%d)", log: log, type: .debug, self.status)
        }
        
        // Lookup
        if FileManager().fileExists(atPath: lookupCacheUrl.path) {
            do {
                let data = try Data(NSData(contentsOfFile: lookupCacheUrl.path))
                self.lookup = data
                os_log("Lookup data loaded from cache (bytes=%u)", log: log, type: .debug, self.lookup.count)
            } catch {}
        } else {
            os_log("Lookup data download required, this will be done automatically in the background", log: log, type: .info)
        }
        
        // Schedule background updates (foreground, see appDelegate for background)
        scheduleUpdates()
        
        // Beacons
        beaconTransmitter.start()
        beaconReceiver.start()
    }
    
    public override func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {
        if
            let setSerialNumber = Keychain.shared.set("serialNumber", String(serialNumber)),
            let setSharedSecret = Keychain.shared.set("sharedSecret", sharedSecret.base64EncodedString()),
            setSerialNumber,
            setSharedSecret {
            os_log("Registration saved to keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
            self.serialNumber = serialNumber
            self.sharedSecret = sharedSecret
            self.codes = Codes(sharedSecret: sharedSecret)
            os_log("Starting beacon transmitter following registration", log: log, type: .debug)
        } else {
            os_log("Registration not saved to keychain (serialNumber=%u)", log: log, type: .fault, self.serialNumber)
        }
    }
    
    public override func networkListenerFailedUpdate(registrationError: Error?) {
        os_log("Registration failed, retrying in 10 minutes (error=%s)", log: log, type: .debug, String(describing: registrationError))
        DispatchQueue.main.asyncAfter(deadline: .future(by: 600)) {
            self.network.getRegistration()
        }
    }
    
    public override func networkListenerDidUpdate(status:Int) {
        set(status: status)
    }
    
    public override func networkListenerDidUpdate(message:String) {
        self.message = message
    }
    
    public override func networkListenerDidUpdate(lookup: Data) {
        self.lookup = lookup
        do {
            if FileManager().fileExists(atPath: lookupCacheUrl.path) {
                try? FileManager().removeItem(atPath: lookupCacheUrl.path)
            }
            try self.lookup.write(to: lookupCacheUrl, options: [.atomic, .noFileProtection])
            os_log("Lookup data saved to cache (bytes=%u)", log: log, type: .debug, self.lookup.count)
        } catch {
            os_log("Lookup data save to cache failed (error=%s)", log: log, type: .fault, String(describing: error))
        }
        riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: parameters, lookup: lookup)
    }
    
    public override func networkListenerDidUpdate(parameters: [String:String]) {
        self.parameters.set(dictionary: parameters)
        riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: self.parameters, lookup: lookup)
    }
}

public class Codes {
    private static let log = OSLog(subsystem: "org.C19X", category: "Codes")
    private static let epoch = UInt64(ISO8601DateFormatter().date(from: "2020-01-01T00:00:00+0000")!.timeIntervalSince1970 * 1000)
    private static let range = BigUInt(9223372036854775807)
    private static let days = 365 * 10
    private static let dayMillis = UInt64(24 * 60 * 60 * 1000)
    
    private var values:[Int64] = []
    
    init(sharedSecret: Data) {
        self.values = Codes.getValues(sharedSecret: sharedSecret)
    }
    
    public func get(_ days: Int) -> Int64 {
        let now = UInt64(NSDate().timeIntervalSince1970 * 1000)
        let (today,_) = (now - Codes.epoch).dividedReportingOverflow(by: Codes.dayMillis)
        
        let day = (days <= 1 ? Int(today) : Int(today) - random(days - 1))
        os_log("Randomly selected code (day=%u,code=%s)", log: Codes.log, type: .debug, day, values[day].description)
        return values[day]
    }
    
    private func random(_ range: Int) -> Int {
        var bytes = [UInt8](repeating: 0, count: 1)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Int(bytes[0] % UInt8(range))
        } else {
            os_log("Secure random number generator failed, defaulting to Int.random (error=%d)", log: Codes.log, type: .fault, status)
            return Int.random(in: 0 ... Int(range))
        }
    }
    
    private static func getValues(sharedSecret: Data) -> [Int64] {
        os_log("Generating forward secure codes (days=%d)", log: log, type: .debug, days)
        var codes = [Int64](repeating: 0, count: days)
        var hash = SHA256.hash(data: sharedSecret)
        for i in (0 ... (days - 1)).reversed() {
            let hashData = Data(hash)
            codes[i] = Int64(BigUInt(hashData) % range)
            hash = SHA256.hash(data: hashData)
            //debugPrint("\(i) -> \(codes[i])")
        }
        os_log("Generated forward secure codes (days=%d)", log: log, type: .debug, days)
        return codes
    }
}

public class Parameters: AbstractNetworkListener {
    private let userDefaults = UserDefaults.standard
    private let keyFirstUse = "Parameters.FirstUse"
    private let keyNotification = "Parameters.Notification"
    private let keyServerAddress = "Parameters.ServerAddress"
    private let keyGovernmentAdvice = "Parameters.GovernmentAdvice"
    private let keyRetentionPeriod = "Parameters.RetentionPeriod"
    private let keySignalStrengthThreshold = "Parameters.SignalStrengthThreshold"
    private let keyBeaconCodeUpdateInterval = "Parameters.BeaconCodeUpdateInterval"
    private let keyTimestampStatus = "Timestamp.Status"
    private let keyTimestampContact = "Timestamp.Contact"
    private let keyTimestampAdvice = "Timestamp.Advice"

    override init() {
        super.init()
        if userDefaults.object(forKey: keyFirstUse) == nil {
            reset()
        }
    }
    
    public func reset() {
        userDefaults.set(true, forKey: keyFirstUse)
        userDefaults.set("https://appserver-test.c19x.org", forKey: keyServerAddress)
        userDefaults.set(RiskAnalysis.adviceStayAtHome, forKey: keyGovernmentAdvice)
        userDefaults.set(14, forKey: keyRetentionPeriod)
        userDefaults.set(-77.46, forKey: keySignalStrengthThreshold)
        userDefaults.set(30, forKey: keyBeaconCodeUpdateInterval)
        userDefaults.removeObject(forKey: keyTimestampStatus)
        userDefaults.removeObject(forKey: keyTimestampContact)
        userDefaults.removeObject(forKey: keyTimestampAdvice)
    }
    
    public func isFirstUse() -> Bool {
        return userDefaults.object(forKey: keyFirstUse) == nil || userDefaults.bool(forKey: keyFirstUse)
    }

    public func isNotificationEnabled() -> Bool {
        return userDefaults.object(forKey: keyNotification) == nil || userDefaults.bool(forKey: keyNotification)
    }

    public func set(isFirstUse: Bool) {
        userDefaults.set(isFirstUse, forKey: keyFirstUse)
    }

    public func set(notification: Bool) {
        userDefaults.set(notification, forKey: keyNotification)
    }

    public func set(statusUpdate: Date) {
        userDefaults.set(statusUpdate, forKey: keyTimestampStatus)
    }
    
    public func getStatusUpdateTimestamp() -> Date? {
        return userDefaults.object(forKey: keyTimestampStatus) as? Date
    }
    
    public func set(contactUpdate: Date) {
        userDefaults.set(contactUpdate, forKey: keyTimestampContact)
    }
    
    public func getContactUpdateTimestamp() -> Date? {
        return userDefaults.object(forKey: keyTimestampContact) as? Date
    }
    
    public func set(adviceUpdate: Date) {
        userDefaults.set(adviceUpdate, forKey: keyTimestampAdvice)
    }

    public func getAdviceUpdateTimestamp() -> Date? {
        return userDefaults.object(forKey: keyTimestampAdvice) as? Date
    }
    
    public func getServerAddress() -> String {
        return userDefaults.string(forKey: keyServerAddress)!
    }

    public func getGovernmentAdvice() -> Int {
        return userDefaults.integer(forKey: keyGovernmentAdvice)
    }

    public func getRetentionPeriod() -> TimeInterval {
        return TimeInterval(userDefaults.integer(forKey: keyRetentionPeriod) * 24 * 60)
    }

    public func getRetentionPeriodInDays() -> Int {
        return userDefaults.integer(forKey: keyRetentionPeriod)
    }

    public func getSignalStrengthThreshold() -> Double {
        return userDefaults.double(forKey: keySignalStrengthThreshold)
    }

    public func getBeaconCodeUpdateInterval() -> TimeInterval {
        return TimeInterval(userDefaults.integer(forKey: keyBeaconCodeUpdateInterval) * 60)
    }

    /**
     Set parameters from dictionary, e.g. downloaded from server
     */
    public func set(dictionary:[String:String]) {
        if let v = dictionary["serverAddress"] {
            userDefaults.set(v, forKey: keyServerAddress)
        }
        if let v = dictionary["governmentAdvice"], let n = Int(v) {
            userDefaults.set(n, forKey: keyGovernmentAdvice)
        }
        if let v = dictionary["retentionPeriod"], let n = Int(v) {
            // Days
            userDefaults.set(n, forKey: keyRetentionPeriod)
        }
        if let v = dictionary["signalStrengthThreshold"], let n = Double(v) {
            userDefaults.set(n, forKey: keySignalStrengthThreshold)
        }
        if let v = dictionary["beaconCodeUpdateInterval"], let n = Int(v) {
            // Minutes
            userDefaults.set(n, forKey: keyBeaconCodeUpdateInterval)
        }
    }
}

public struct ContactRecord {
    let time: Date!
    let beacon: Int64!
    let rssi: Int!
}

public class ContactRecords: AbstractBeaconListener {
    private let log = OSLog(subsystem: "org.C19X", category: "ContactRecords")
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "C19X")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()
    public var records: [ContactRecord] = []
    private var lock = NSLock()
    
    override init() {
        super.init()
        load()
    }
    
    public func reset() {
        remove(recordsBefore: Date().advanced(by: 60 * 60))
    }
    
    public func remove(recordsBefore: Date) {
        lock.lock()
        let managedContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Contact")
        do {
            let objects: [NSManagedObject] = try managedContext.fetch(fetchRequest)
            objects.forEach() { o in
                if let time = o.value(forKey: "time") as? Date {
                    if (time.compare(recordsBefore) == .orderedAscending) {
                        managedContext.delete(o)
                    }
                }
            }
            try managedContext.save()
            load()
            os_log("Remove successful (recordsBefore=%s)", log: self.log, type: .debug, recordsBefore.description)
        } catch let error as NSError {
            os_log("Remove failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        }
        lock.unlock()
    }
    
    public override func beaconListenerDidUpdate(beaconCode: Int64, rssi: Int) {
        lock.lock()
        let record = ContactRecord(time: Date(), beacon: beaconCode, rssi: rssi)
        let managedContext = persistentContainer.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "Contact", in: managedContext)!
        let object = NSManagedObject(entity: entity, insertInto: managedContext)
        object.setValue(record.time, forKey: "time")
        object.setValue(record.beacon, forKey: "beacon")
        object.setValue(record.rssi, forKey: "rssi")
        do {
            try managedContext.save()
            records.append(record)
            os_log("Contact save successful (beacon=%s,rssi=%d)", log: self.log, type: .debug, beaconCode.description, rssi)
        } catch let error as NSError {
            os_log("Contact save failed (beacon=%s,rssi=%d,error=%s)", log: self.log, type: .fault, beaconCode.description, rssi, String(describing: error))
        }
        lock.unlock()
    }
        
    private func load() {
        let managedContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Contact")
        do {
            let objects: [NSManagedObject] = try managedContext.fetch(fetchRequest)
            
            var records: [ContactRecord] = []
            objects.forEach() { o in
                if
                    let time = o.value(forKey: "time") as? Date,
                    let beacon = o.value(forKey: "beacon") as? Int64,
                    let rssi = o.value(forKey: "rssi") as? Int {
                    records.append(ContactRecord(time: time, beacon: beacon, rssi: rssi))
                }
            }
            self.records = records
            os_log("Contact load successful", log: self.log, type: .debug)
        } catch let error as NSError {
            os_log("Contact load failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        }
    }
}

public class RiskAnalysis {
    private let log = OSLog(subsystem: "org.C19X", category: "RiskAnalysis")
    
    public static let contactOk = 0
    public static let contactInfectious = 1
    
    public static let adviceFreedom = 0
    public static let adviceStayAtHome = 1
    public static let adviceSelfIsolate = 2
    
    public var contact = RiskAnalysis.contactOk
    public var advice = RiskAnalysis.adviceStayAtHome
    
    public var contactCount: UInt64 = 0
    public var exposureCount: UInt64 = 0
    public var listeners: [RiskAnalysisListener] = []
    
    private static func getExposureToInfection(contactRecords: ContactRecords, rssiThreshold: Double, lookup: Data) -> (total:Int, infectious:Int) {
        
        let range = Int64(lookup.count * 8)
        let records = contactRecords.records
        let infectious = records.filter { record in
            guard Double(record.rssi) > rssiThreshold else {
                return false
            }
            let index = Int(abs(record.beacon % range))
            return get(lookup, index: index)
        }
        
        return (records.count, infectious.count)
    }
    
    public func update(status: Int, contactRecords: ContactRecords, parameters: Parameters, lookup: Data) {
        let previousContactStatus = contact
        let previousAdvice = advice
        let (contactCount, exposureCount) = RiskAnalysis.getExposureToInfection(contactRecords: contactRecords, rssiThreshold: parameters.getSignalStrengthThreshold(), lookup: lookup)
        
        if (status != Device.statusNormal) {
            advice = RiskAnalysis.adviceSelfIsolate;
        } else {
            contact = (exposureCount == 0 ? RiskAnalysis.contactOk : RiskAnalysis.contactInfectious)
            advice = (exposureCount == 0 ? parameters.getGovernmentAdvice() :
                RiskAnalysis.adviceSelfIsolate)
        }
        os_log("Risk analysis (contactCount=%u,exposureCount=%u,contact=%d,advice=%d)", log: self.log, type: .debug, contactCount, exposureCount, contact, advice)
        for listener in listeners {
            listener.riskAnalysisDidUpdate(previousContactStatus: previousContactStatus, currentContactStatus: contact, previousAdvice: previousAdvice, currentAdvice: advice, contactCount: contactCount)
        }
    }
    
    private static func get(_ data: Data, index: Int) -> Bool {
        return ((data[index / 8] >> (index % 8)) & 1) != 0;
    }
    
}

public protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int)
}

public class AbstractRiskAnalysisListener: RiskAnalysisListener {
    public func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int) {}
}
