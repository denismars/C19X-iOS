//
//  Device.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CryptoKit
import CoreData
import os

class Device: AbstractNetworkListener {
    
    private let log = OSLog(subsystem: "org.C19X", category: "Device")
    private static let serviceUUID = UUID(uuidString: "0022D481-83FE-1F13-0000-000000000000")!
    
    public static let statusNormal = 0
    public static let statusSymptom = 1
    public static let statusDiagnosis = 2
    
    private let lookupCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("lookup")
    
    public var serialNumber: UInt64 = 0
    public var sharedSecret: Data = Data()
    private var status: Int = 0
    
    public var codes: DayCodes?
    public var message: String = ""
    public var lookup: Data = Data(count: 1)
    private var serverDataUpdateSince: Date?
    
    public var parameters = Parameters()
    public var contactRecords = ContactRecords()
    public var network = Network()
    var beaconTransmitter = BeaconTransmitter(serviceUUID)
    var beaconReceiver = BeaconReceiver(serviceUUID)
    public var riskAnalysis = RiskAnalysis()
    
    override init() {
        super.init()
        
        beaconReceiver.listeners.append(contactRecords)
        beaconTransmitter.listeners.append(contactRecords)
        network.listeners.append(self)
    }
        
    public func start() {
        os_log("Start", log: log, type: .debug)
        reset()

        // Parameters
        network.set(server: parameters.getServerAddress())
        
        // Registration
        if
            let serialNumberKeychainValue = Keychain.shared.get("serialNumber"),
            let sharedSecretKeychainValue = Keychain.shared.get("sharedSecret"),
            let serialNumber = UInt64(serialNumberKeychainValue),
            let sharedSecret = Data(base64Encoded: sharedSecretKeychainValue) {
            os_log("Registration loaded from keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
            networkListenerDidUpdate(serialNumber: serialNumber, sharedSecret: sharedSecret)
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
        let beaconCode = beaconCodes.get()
        //beaconTransmitter.setBeaconCode(beaconCode: UInt(beaconCode))
        os_log("Change beacon code successful (code=%s)", log: log, type: .debug, beaconCode!.description)
    }
    
    private func enforceRetentionPeriod() {
        os_log("Enforce retention period", log: log, type: .debug)
        let date = Date() - (parameters.getRetentionPeriod())
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
    
    override func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {
        if
            let setSerialNumber = Keychain.shared.set("serialNumber", String(serialNumber)),
            let setSharedSecret = Keychain.shared.set("sharedSecret", sharedSecret.base64EncodedString()),
            setSerialNumber, setSharedSecret {
            os_log("Registration saved to keychain (serialNumber=%u)", log: log, type: .debug, serialNumber)
            self.serialNumber = serialNumber
            self.sharedSecret = sharedSecret
            self.codes = ConcreteDayCodes(sharedSecret)
            os_log("Starting beacon transmitter following registration", log: log, type: .debug)
            changeBeaconCode()
        } else {
            os_log("Registration not saved to keychain (serialNumber=%u)", log: log, type: .fault, serialNumber)
        }
    }
    
    override func networkListenerFailedUpdate(registrationError: Error?) {
        os_log("Registration failed, retrying in 10 minutes (error=%s)", log: log, type: .debug, String(describing: registrationError))
        DispatchQueue.main.asyncAfter(deadline: .future(by: 600)) {
            self.network.getRegistration()
        }
    }
    
    override func networkListenerDidUpdate(status:Int) {
        set(status: status)
    }
    
    override func networkListenerDidUpdate(message:String) {
        self.message = message
    }
    
    override func networkListenerDidUpdate(lookup: Data) {
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
    
    override func networkListenerDidUpdate(parameters: [String:String]) {
        self.parameters.set(dictionary: parameters)
        network.set(server: self.parameters.getServerAddress())
        riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: self.parameters, lookup: lookup)
    }
}


public class Parameters: AbstractNetworkListener {
    private let userDefaults = UserDefaults.standard
    private let keyFirstUse = "Parameters.FirstUse"
    private let keyNotification = "Parameters.Notification"
    private let keyServerAddress = "Parameters.ServerAddress"
    private let keyGovernmentAdvice = "Parameters.GovernmentAdvice"
    private let keyRetentionPeriod = "Parameters.RetentionPeriod"
    private let keyBeaconCodeUpdateInterval = "Parameters.BeaconCodeUpdateInterval"
    private let keyRssiHistogram = "Parameters.RssiHistogram"
    private let keyTimeHistogram = "Parameters.TimeHistogram"
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
        userDefaults.set("https://c19x-dev.servehttp.com/", forKey: keyServerAddress)
        userDefaults.set(RiskAnalysis.adviceStayAtHome, forKey: keyGovernmentAdvice)
        userDefaults.set(14, forKey: keyRetentionPeriod)
        userDefaults.set(30, forKey: keyBeaconCodeUpdateInterval)
        let rssiHistogram: [Int:Double] = [:]
        userDefaults.set(rssiHistogram, forKey: keyRssiHistogram)
        let timeHistogram: [Int:Double] = [:]
        userDefaults.set(timeHistogram, forKey: keyTimeHistogram)
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
        return TimeInterval(userDefaults.integer(forKey: keyRetentionPeriod) * 24 * 60 * 60)
    }

    public func getRetentionPeriodInDays() -> Int {
        return userDefaults.integer(forKey: keyRetentionPeriod)
    }

    public func getBeaconCodeUpdateInterval() -> TimeInterval {
        return TimeInterval(userDefaults.integer(forKey: keyBeaconCodeUpdateInterval) * 60)
    }

    public func getRssiHistogram() -> [Int:Double] {
        return userDefaults.object(forKey: keyRssiHistogram) as! [Int : Double]
    }

    public func getTimeHistogram() -> [Int:Double] {
        return userDefaults.object(forKey: keyTimeHistogram) as! [Int : Double]
    }

    private func parseHistogram(_ string: String) -> [Int : Double] {
        var histogram: [Int : Double] = [:]
        string.split(separator: ",").forEach() { entry in
            let kv = entry.split(separator: ":")
            if let k = Int(kv[0]), let v = Double(kv[1]) {
                histogram[k] = v
            }
        }
        return histogram
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
        if let v = dictionary["rssiHistogram"] {
            let h = parseHistogram(v)
            userDefaults.set(h, forKey: keyRssiHistogram)
        }
        if let v = dictionary["timeHistogram"] {
            let h = parseHistogram(v)
            userDefaults.set(h, forKey: keyTimeHistogram)
        }
        if let v = dictionary["beaconCodeUpdateInterval"], let n = Int(v) {
            // Minutes
            userDefaults.set(n, forKey: keyBeaconCodeUpdateInterval)
        }
    }
}

public struct ContactRecord {
    let time: Date!
    let beacon: UInt64!
    let rssi: Int!
}

class ContactRecords: AbstractBeaconListener {
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
        //load()
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
    
    override func beaconListenerDidUpdate(beaconCode: UInt64, rssi: Int) {
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
                    let beacon = o.value(forKey: "beacon") as? UInt64,
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

class RiskAnalysis {
    private let log = OSLog(subsystem: "org.C19X", category: "RiskAnalysis")
    
    public static let contactOk = 0
    public static let contactInfectious = 1
    
    public static let adviceFreedom = 0
    public static let adviceStayAtHome = 1
    public static let adviceSelfIsolate = 2
    
    public var contact = RiskAnalysis.contactOk
    public var advice = RiskAnalysis.adviceStayAtHome
    
    public var listeners: [RiskAnalysisListener] = []
    
    private func filter(records: [ContactRecord], lookup: Data, infectious: Bool) -> [ContactRecord] {
        let range = UInt64(lookup.count * 8)
        return records.filter { record in
            let index = record.beacon % range
            return get(lookup, index: index) == infectious
        }
    }
    
    private func rssiHistogram(records: [ContactRecord]) -> [Int:Int] {
        var histogram: [Int:Int] = [:]
        records.forEach() { record in
            if histogram[record.rssi] == nil {
                histogram[record.rssi] = 1
            } else {
                histogram[record.rssi]! += 1
            }
        }
        return histogram
    }
    
    private func timeHistogram(records: [ContactRecord]) -> [Int:Int] {
        var histogram: [Int:Int] = [:]
        let now = Date()
        let daySeconds:UInt64 = 24*60*60
        let (today,_) = UInt64(now.timeIntervalSince1970).dividedReportingOverflow(by: daySeconds)
        records.forEach() { record in
            let (day,_) = UInt64(record.time.timeIntervalSince1970).dividedReportingOverflow(by: daySeconds)
            let delta = abs(Int(today - day))
            if histogram[delta] == nil {
                histogram[delta] = 1
            } else {
                histogram[delta]! += 1
            }
        }
        return histogram
    }
    
    private func multiply(_ counts:[Int:Int], _ weights:[Int:Double]) -> Double {
        var sumWeight = Double.zero
        weights.values.forEach() { weight in sumWeight += weight }
        guard !sumWeight.isZero else {
            // Unweighted
            var sumCount = 0
            counts.values.forEach() { count in sumCount += count }
            return (sumCount == 0 ? Double.zero : Double(1))
        }
        // Weighted
        var product = Double.zero
        counts.forEach() { key, value in
            if let weight = weights[key] {
                product += (Double(value) * weight)
            }
        }
        return product / sumWeight
    }
    
    public func analyse(contactRecords: ContactRecords, lookup: Data) -> (infectious:[ContactRecord], rssiHistogram:[Int:Int], timeHistogram:[Int:Int]) {
        let infectious = filter(records: contactRecords.records, lookup: lookup, infectious: true)
        let rssiCounts = rssiHistogram(records: infectious)
        let timeCounts = timeHistogram(records: infectious)
        return (infectious, rssiCounts, timeCounts)
    }
    
    private func analyse(contactRecords: ContactRecords, lookup: Data, rssiWeights: [Int : Double], timeWeights: [Int : Double]) -> (infectious: Int, risk: Double) {
        let (infectious, rssiHistogram, timeHistogram) = analyse(contactRecords: contactRecords, lookup: lookup)
        let rssiValue = multiply(rssiHistogram, rssiWeights)
        let timeValue = multiply(timeHistogram, timeWeights)
        os_log("Analysis data (infectious=%d,rssiValue=%f,timeValue=%f)", log: self.log, type: .debug, infectious.count, rssiValue, timeValue)
        return (infectious.count, rssiValue * timeValue)
    }
    
    public func update(status: Int, contactRecords: ContactRecords, parameters: Parameters, lookup: Data) {
        let previousContactStatus = contact
        let previousAdvice = advice
        let contactCount = contactRecords.records.count
        let (infectiousCount, infectionRisk) = analyse(contactRecords: contactRecords, lookup: lookup, rssiWeights: parameters.getRssiHistogram(), timeWeights: parameters.getTimeHistogram())
        
        if (status != Device.statusNormal) {
            advice = RiskAnalysis.adviceSelfIsolate;
        } else {
            contact = (infectiousCount == 0 ? RiskAnalysis.contactOk : RiskAnalysis.contactInfectious)
            advice = (infectionRisk.isZero ? parameters.getGovernmentAdvice() :
                RiskAnalysis.adviceSelfIsolate)
        }
        os_log("Analysis updated (contactCount=%u,infectiousCount=%u,contact=%d,advice=%d,risk=%f)", log: self.log, type: .debug, contactCount, infectiousCount, contact, advice, infectionRisk)
        for listener in listeners {
            listener.riskAnalysisDidUpdate(previousContactStatus: previousContactStatus, currentContactStatus: contact, previousAdvice: previousAdvice, currentAdvice: advice, contactCount: contactCount)
        }
    }
    
    private func get(_ data: Data, index: UInt64) -> Bool {
        let block = Int(index / 8)
        let bit = Int(index % 8)
        return ((data[block] >> bit) & 1) != 0;
    }
    
}

public protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int)
}

public class AbstractRiskAnalysisListener: RiskAnalysisListener {
    public func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int) {}
}
