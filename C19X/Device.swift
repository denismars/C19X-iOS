////
////  Device.swift
////  C19X
////
////  Created by Freddy Choi on 28/04/2020.
////  Copyright © 2020 C19X. All rights reserved.
////
//
//import Foundation
//import CryptoKit
//import CoreData
//import os
//
//class Device {
//    
//    private let log = OSLog(subsystem: "org.C19X", category: "Device")
//    private static let serviceUUID = UUID(uuidString: "0022D481-83FE-1F13-0000-000000000000")!
//    
//    public static let statusNormal = 0
//    public static let statusSymptom = 1
//    public static let statusDiagnosis = 2
//    
//    private let lookupCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("lookup")
//    
//    public var serialNumber: UInt64 = 0
//    public var sharedSecret: Data = Data()
//    private var status: Int = 0
//    
//    public var codes: DayCodes?
//    public var message: String = ""
//    public var lookup: Data = Data(count: 1)
//    private var serverDataUpdateSince: Date?
//    
//    public var parameters = Parameters()
//    public var contactRecords = ContactRecords()
//    public var network = ConcreteNetwork(Settings.shared)
//    var beaconTransmitter = BeaconTransmitter(serviceUUID)
//    var beaconReceiver = BeaconReceiver(serviceUUID)
//    public var riskAnalysis = ConcreteRiskAnalysis(Settings.shared)
//    
//    override init() {
//        super.init()
//        
//        beaconReceiver.listeners.append(contactRecords)
//        beaconTransmitter.listeners.append(contactRecords)
//        network.listeners.append(self)
//    }
//        
//    public func start() {
//        os_log("Start", log: log, type: .debug)
//        reset()
//
//        // Registration
//        if
//            let serialNumberKeychainValue = Keychain.shared.get("serialNumber"),
//            let sharedSecretKeychainValue = Keychain.shared.get("sharedSecret"),
//            let serialNumber = UInt64(serialNumberKeychainValue),
//            let sharedSecret = Data(base64Encoded: sharedSecretKeychainValue) {
//            os_log("Registration loaded from keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
//            networkListenerDidUpdate(serialNumber: serialNumber, sharedSecret: sharedSecret)
//        } else {
//            os_log("Registration required", log: log, type: .info)
//            //network.getRegistration()
//        }
//        
//        // Status
//        if
//            let statusKeychainValue = Keychain.shared.get("status"),
//            let status = Int(statusKeychainValue) {
//            self.status = status
//            os_log("Status loaded from keychain (status=%d)", log: log, type: .debug, self.status)
//        }
//        
//        // Lookup
//        if FileManager().fileExists(atPath: lookupCacheUrl.path) {
//            do {
//                let data = try Data(NSData(contentsOfFile: lookupCacheUrl.path))
//                self.lookup = data
//                os_log("Lookup data loaded from cache (bytes=%u)", log: log, type: .debug, self.lookup.count)
//            } catch {}
//        } else {
//            os_log("Lookup data download required, this will be done automatically in the background", log: log, type: .info)
//        }
//        
//        // Schedule background updates (foreground, see appDelegate for background)
//        scheduleUpdates()
//        
//        // Beacons
//        beaconTransmitter.start()
//        beaconReceiver.start()
//    }
//    
//
//    private func scheduleUpdates() {
//        update()
//        DispatchQueue.main.asyncAfter(deadline: DispatchTime.future(by: parameters.getBeaconCodeUpdateInterval(), randomise: 120)) {
//            self.update()
//        }
//    }
//    
//    /**
//     All device update tasks, e.g. beacon code rotation, downloads. Calling before time limits has no effect.
//     */
//    public func update(callback: (() -> Void)? = nil) {
//        
//        // Rotate beacon code and enforce retention
//        if beaconTransmitter.beaconCodeSince == nil || beaconTransmitter.beaconCodeSince!.distance(to: Date()) > parameters.getBeaconCodeUpdateInterval() {
//            changeBeaconCode()
//            enforceRetentionPeriod()
//        }
//        
//        if serverDataUpdateSince == nil || serverDataUpdateSince!.distance(to: Date()) > (24 * 60 * 60) {
//            // No registration required
////            network.getLookupInBackground()
////            network.getTimeFromServerAndSynchronise() { t in
////                self.network.getParameters() { p in
////                    // Registration required
////                    guard self.isRegistered() else {
////                        if callback != nil {
////                            callback!()
////                        }
////                        return
////                    }
////                    self.network.getMessage(serialNumber: self.serialNumber, sharedSecret: self.sharedSecret) { m in
////                        if callback != nil {
////                            callback!()
////                        }
////                    }
////                }
////            }
//        }
//        if callback != nil {
//            callback!()
//        }
//    }
//    
//    public func isRegistered() -> Bool {
//        return codes != nil
//    }
//    
//    public func set(status: Int) {
//        if let _ = Keychain.shared.set("status", status.description) {
//            self.status = status
//            //riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: parameters, lookup: lookup)
//        }
//    }
//    
//    public func getStatus() -> Int {
//        return status
//    }
//    
//    private func changeBeaconCode() {
//        os_log("Change beacon code request", log: log, type: .debug)
//        guard let beaconCodes = codes else {
//            os_log("Change beacon code failed, pending registration", log: log, type: .fault)
//            return
//        }
//        let beaconCode = beaconCodes.get()
//        //beaconTransmitter.setBeaconCode(beaconCode: UInt(beaconCode))
//        os_log("Change beacon code successful (code=%s)", log: log, type: .debug, beaconCode!.description)
//    }
//    
//    private func enforceRetentionPeriod() {
//        os_log("Enforce retention period", log: log, type: .debug)
//        let date = Date() - (parameters.getRetentionPeriod())
//        contactRecords.remove(recordsBefore: date)
//        os_log("Enforce retention period successful (cutoff=%s)", log: log, type: .debug, date.description)
//    }
//    
//    public func reset() {
//        os_log("Reset", log: log, type: .error)
//        let _ = Keychain.shared.remove("serialNumber")
//        let _ = Keychain.shared.remove("sharedSecret")
//        let _ = Keychain.shared.remove("status")
//        parameters.reset()
//        contactRecords.reset()
//        if FileManager().fileExists(atPath: lookupCacheUrl.path) {
//            do {
//                try FileManager().removeItem(atPath: lookupCacheUrl.path)
//            } catch {}
//        }
//    }
//    
//    override func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {
//        if
//            let setSerialNumber = Keychain.shared.set("serialNumber", String(serialNumber)),
//            let setSharedSecret = Keychain.shared.set("sharedSecret", sharedSecret.base64EncodedString()),
//            setSerialNumber, setSharedSecret {
//            os_log("Registration saved to keychain (serialNumber=%u)", log: log, type: .debug, serialNumber)
//            self.serialNumber = serialNumber
//            self.sharedSecret = sharedSecret
//            self.codes = ConcreteDayCodes(sharedSecret)
//            os_log("Starting beacon transmitter following registration", log: log, type: .debug)
//            changeBeaconCode()
//        } else {
//            os_log("Registration not saved to keychain (serialNumber=%u)", log: log, type: .fault, serialNumber)
//        }
//    }
//    
//    override func networkListenerFailedUpdate(registrationError: Error?) {
//        os_log("Registration failed, retrying in 10 minutes (error=%s)", log: log, type: .debug, String(describing: registrationError))
//        DispatchQueue.main.asyncAfter(deadline: .future(by: 600)) {
//            //self.network.getRegistration()
//        }
//    }
//    
//    override func networkListenerDidUpdate(status:Int) {
//        set(status: status)
//    }
//    
//    override func networkListenerDidUpdate(message:String) {
//        self.message = message
//    }
//    
//    override func networkListenerDidUpdate(lookup: Data) {
//        self.lookup = lookup
//        do {
//            if FileManager().fileExists(atPath: lookupCacheUrl.path) {
//                try? FileManager().removeItem(atPath: lookupCacheUrl.path)
//            }
//            try self.lookup.write(to: lookupCacheUrl, options: [.atomic, .noFileProtection])
//            os_log("Lookup data saved to cache (bytes=%u)", log: log, type: .debug, self.lookup.count)
//        } catch {
//            os_log("Lookup data save to cache failed (error=%s)", log: log, type: .fault, String(describing: error))
//        }
//        //riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: parameters, lookup: lookup)
//    }
//    
//    override func networkListenerDidUpdate(parameters: [String:String]) {
//        self.parameters.set(dictionary: parameters)
//        //riskAnalysis.update(status: status, contactRecords: contactRecords, parameters: self.parameters, lookup: lookup)
//    }
//}
//
//
//public class Parameters {
//    private let userDefaults = UserDefaults.standard
//    private let keyFirstUse = "Parameters.FirstUse"
//    private let keyNotification = "Parameters.Notification"
//    private let keyServerAddress = "Parameters.ServerAddress"
//    private let keyGovernmentAdvice = "Parameters.GovernmentAdvice"
//    private let keyRetentionPeriod = "Parameters.RetentionPeriod"
//    private let keyBeaconCodeUpdateInterval = "Parameters.BeaconCodeUpdateInterval"
//    private let keyRssiHistogram = "Parameters.RssiHistogram"
//    private let keyTimeHistogram = "Parameters.TimeHistogram"
//    private let keyTimestampStatus = "Timestamp.Status"
//    private let keyTimestampContact = "Timestamp.Contact"
//    private let keyTimestampAdvice = "Timestamp.Advice"
//    private let keyCounterContacts = "Counter.Contacts"
//
//    override init() {
//        super.init()
//        if userDefaults.object(forKey: keyFirstUse) == nil {
//            reset()
//        }
//    }
//    
//    public func reset() {
//        userDefaults.set(true, forKey: keyFirstUse)
//        userDefaults.set("https://c19x-dev.servehttp.com/", forKey: keyServerAddress)
//        //userDefaults.set(RiskAnalysis.adviceStayAtHome, forKey: keyGovernmentAdvice)
//        userDefaults.set(14, forKey: keyRetentionPeriod)
//        userDefaults.set(30, forKey: keyBeaconCodeUpdateInterval)
//        let rssiHistogram: [Int:Double] = [:]
//        userDefaults.set(rssiHistogram, forKey: keyRssiHistogram)
//        let timeHistogram: [Int:Double] = [:]
//        userDefaults.set(timeHistogram, forKey: keyTimeHistogram)
//        userDefaults.removeObject(forKey: keyTimestampStatus)
//        userDefaults.removeObject(forKey: keyTimestampContact)
//        userDefaults.removeObject(forKey: keyTimestampAdvice)
//        userDefaults.removeObject(forKey: keyCounterContacts)
//    }
//    
//    public func isFirstUse() -> Bool {
//        return userDefaults.object(forKey: keyFirstUse) == nil || userDefaults.bool(forKey: keyFirstUse)
//    }
//
//    public func isNotificationEnabled() -> Bool {
//        return userDefaults.object(forKey: keyNotification) == nil || userDefaults.bool(forKey: keyNotification)
//    }
//
//    public func set(isFirstUse: Bool) {
//        userDefaults.set(isFirstUse, forKey: keyFirstUse)
//    }
//
//    public func set(notification: Bool) {
//        userDefaults.set(notification, forKey: keyNotification)
//    }
//
//    public func set(statusUpdate: Date) {
//        userDefaults.set(statusUpdate, forKey: keyTimestampStatus)
//    }
//    
//    public func getStatusUpdateTimestamp() -> Date? {
//        return userDefaults.object(forKey: keyTimestampStatus) as? Date
//    }
//    
//    public func set(contactUpdate: Date) {
//        userDefaults.set(contactUpdate, forKey: keyTimestampContact)
//    }
//    
//    public func getContactUpdateTimestamp() -> Date? {
//        return userDefaults.object(forKey: keyTimestampContact) as? Date
//    }
//    
//    public func set(adviceUpdate: Date) {
//        userDefaults.set(adviceUpdate, forKey: keyTimestampAdvice)
//    }
//
//    public func getAdviceUpdateTimestamp() -> Date? {
//        return userDefaults.object(forKey: keyTimestampAdvice) as? Date
//    }
//    
//    public func set(contacts: Int) {
//        userDefaults.set(contacts, forKey: keyCounterContacts)
//    }
//
//    public func getCounterContacts() -> Int? {
//        return userDefaults.object(forKey: keyCounterContacts) as? Int
//    }
//
//    public func getServerAddress() -> String {
//        return userDefaults.string(forKey: keyServerAddress)!
//    }
//
//    public func getGovernmentAdvice() -> Int {
//        return userDefaults.integer(forKey: keyGovernmentAdvice)
//    }
//
//    public func getRetentionPeriod() -> TimeInterval {
//        return TimeInterval(userDefaults.integer(forKey: keyRetentionPeriod) * 24 * 60 * 60)
//    }
//
//    public func getRetentionPeriodInDays() -> Int {
//        return userDefaults.integer(forKey: keyRetentionPeriod)
//    }
//
//    public func getBeaconCodeUpdateInterval() -> TimeInterval {
//        return TimeInterval(userDefaults.integer(forKey: keyBeaconCodeUpdateInterval) * 60)
//    }
//
//    public func getRssiHistogram() -> [Int:Double] {
//        return userDefaults.object(forKey: keyRssiHistogram) as! [Int : Double]
//    }
//
//    public func getTimeHistogram() -> [Int:Double] {
//        return userDefaults.object(forKey: keyTimeHistogram) as! [Int : Double]
//    }
//
//    private func parseHistogram(_ string: String) -> [Int : Double] {
//        var histogram: [Int : Double] = [:]
//        string.split(separator: ",").forEach() { entry in
//            let kv = entry.split(separator: ":")
//            if let k = Int(kv[0]), let v = Double(kv[1]) {
//                histogram[k] = v
//            }
//        }
//        return histogram
//    }
//    
//    /**
//     Set parameters from dictionary, e.g. downloaded from server
//     */
//    public func set(dictionary:[String:String]) {
//        if let v = dictionary["serverAddress"] {
//            userDefaults.set(v, forKey: keyServerAddress)
//        }
//        if let v = dictionary["governmentAdvice"], let n = Int(v) {
//            userDefaults.set(n, forKey: keyGovernmentAdvice)
//        }
//        if let v = dictionary["retentionPeriod"], let n = Int(v) {
//            // Days
//            userDefaults.set(n, forKey: keyRetentionPeriod)
//        }
//        if let v = dictionary["rssiHistogram"] {
//            let h = parseHistogram(v)
//            userDefaults.set(h, forKey: keyRssiHistogram)
//        }
//        if let v = dictionary["timeHistogram"] {
//            let h = parseHistogram(v)
//            userDefaults.set(h, forKey: keyTimeHistogram)
//        }
//        if let v = dictionary["beaconCodeUpdateInterval"], let n = Int(v) {
//            // Minutes
//            userDefaults.set(n, forKey: keyBeaconCodeUpdateInterval)
//        }
//    }
//}
