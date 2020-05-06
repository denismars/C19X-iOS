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
import os

public class Device: AbstractNetworkListener {
    private let log = OSLog(subsystem: "org.C19X", category: "Device")
    public static let statusNormal = 0
    public static let statusSymptom = 1
    public static let statusDiagnosis = 2
    
    private let lookupCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("lookup")

    public var serialNumber: UInt64 = 0
    public var sharedSecret: Data = Data()
    public var codes: Codes?
    private var status = statusNormal
    public var message: String = ""
    public var lookup: Data = Data(count: 1)
    private var serverDataUpdateSince: Date?

    public var parameters: Parameters!
    public var contactRecords: ContactRecords!
    public var riskAnalysis: RiskAnalysis!
    public var beaconTransmitter: BeaconTransmitter!
    public var beaconReceiver: BeaconReceiver!
    public var network: Network!
    
    override init() {
        super.init()
        
        parameters = Parameters()
        contactRecords = ContactRecords(parameters: parameters)

        network = Network(device: self)
        riskAnalysis = RiskAnalysis(device: self)

        let serviceUUID = UUID(uuidString: "0022D481-83FE-1F13-0000-000000000000")!
        beaconReceiver = BeaconReceiver(serviceUUID)
        beaconReceiver.listeners.append(contactRecords)
        beaconTransmitter = BeaconTransmitter(serviceUUID)
        beaconTransmitter.listeners.append(contactRecords)

        network.listeners.append(self)

        //reset()
        load()
        scheduleUpdates()
    }
    
    private func scheduleUpdates() {
        update()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.future(by: parameters.beaconCodeUpdateInterval, randomise: 120)) {
            self.update()
        }
    }
    
    /**
     All device update tasks, e.g. beacon code rotation, downloads. Calling before time limits has no effect.
     */
    public func update(callback: (() -> Void)? = nil) {
        if beaconTransmitter.beaconCodeSince == nil || beaconTransmitter.beaconCodeSince!.distance(to: Date()) > parameters.beaconCodeUpdateInterval {
            changeBeaconCode()
        }
        
        if serverDataUpdateSince == nil || serverDataUpdateSince!.distance(to: Date()) > (24 * 60 * 60) {
            // No registration required
            network.getTimeFromServerAndSynchronise() { t in
                self.network.getParameters() { p in
                    self.network.getLookupImmediately() { l in
                        // Registration required
                        guard self.isRegistered() else {
                            if callback != nil {
                                callback!()
                            }
                            return
                        }
                        self.network.getMessage() { m in
                            if callback != nil {
                                callback!()
                            }
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
        if (self.status != status) {
            self.status = status
            let result = Keychain.update("status", status.description)
            os_log("Set status (status=%d,result=%s)", log: log, type: .debug, status, result)
        }
    }
    
    public func getStatus() -> Int {
        return self.status
    }
    
    private func changeBeaconCode() {
        os_log("Change beacon code request", log: log, type: .debug)
        guard let beaconCodes = codes else {
            os_log("Change beacon code failed, pending registration", log: log, type: .fault)
            return
        }
        let beaconCode = beaconCodes.get(parameters.retentionPeriod)
        beaconTransmitter.setBeaconCode(beaconCode: beaconCode)
        os_log("Change beacon code successful (code=%s)", log: log, type: .debug, beaconCode.description)
    }

    private func reset() {
        os_log("Reset (REMOVE FOR PRODUCTION USE)", log: log, type: .error)
        let _ = Keychain.remove("serialNumber")
        let _ = Keychain.remove("sharedSecret")
        let _ = Keychain.remove("status")
    }
    
    private func load() {
        os_log("Load", log: log, type: .debug)
        // Registration
        if
            let serialNumberKeychainValue = Keychain.get(key: "serialNumber"),
            let sharedSecretKeychainValue = Keychain.get(key: "sharedSecret"),
            let serialNumber = UInt64(serialNumberKeychainValue),
            let sharedSecret = Data(base64Encoded: sharedSecretKeychainValue) {
            self.serialNumber = serialNumber
            self.sharedSecret = sharedSecret
            self.codes = Codes(sharedSecret: self.sharedSecret)
            os_log("Registration loaded from keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
            update()
        } else {
            os_log("Registration required", log: log, type: .info)
            network.getRegistration()
        }
        
        // Status
        if
            let statusKeychainValue = Keychain.get(key: "status"),
            let status = Int(statusKeychainValue) {
            self.status = status
            update()
        }
        
        // Lookup
        if FileManager().fileExists(atPath: lookupCacheUrl.path) {
            do {
                let data = try Data(NSData(contentsOfFile: lookupCacheUrl.path))
                self.lookup = data
                os_log("Lookup data loaded from cache (bytes=%u)", log: log, type: .debug, self.lookup.count)
            } catch {}
        } else {
            os_log("Lookup data download required", log: log, type: .info)
            //network.getLookupImmediately()
        }

    }
    
    public override func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {
        if Keychain.create("serialNumber", String(serialNumber)), Keychain.create("sharedSecret", sharedSecret.base64EncodedString()) {
            os_log("Registration saved to keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
            self.serialNumber = serialNumber
            self.sharedSecret = sharedSecret
            self.codes = Codes(sharedSecret: sharedSecret)
            os_log("Starting beacon transmitter following registration", log: log, type: .debug)
            update()
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
        riskAnalysis.update()
    }
    
    public override func networkListenerDidUpdate(parameters: Parameters) {
        riskAnalysis.update()
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
    public var serverAddress = "https://appserver-test.c19x.org";
    public var governmentAdvice = RiskAnalysis.adviceStayAtHome;
    public var retentionPeriod = 14;
    public var signalStrengthThreshold = -77.46;
    public var beaconCodeUpdateInterval = TimeInterval(30 * 60);
    
    public func set(_ dictionary:[String:String]) {
        if let v = dictionary["serverAddress"] {
            serverAddress = v
        }
        if let v = dictionary["governmentAdvice"], let n = Int(v) {
            governmentAdvice = n
        }
        if let v = dictionary["retentionPeriod"], let n = Int(v) {
            retentionPeriod = n
        }
        if let v = dictionary["signalStrengthThreshold"], let n = Double(v) {
            signalStrengthThreshold = n
        }
        if let v = dictionary["beaconCodeUpdateInterval"], let n = Int(v) {
            beaconCodeUpdateInterval = TimeInterval(n / 1000)
        }
    }
}

public class ContactRecords: AbstractBeaconListener {
    private let log = OSLog(subsystem: "org.C19X", category: "ContactRecords")
    private let dayMillis = UInt64(24 * 60 * 60 * 1000)

    private var parameters: Parameters
    private var timer: Timer!
    
    struct LastSeen: Codable {
        var beacon: [Int64:UInt64] = [:]
    }
    public struct Record: Codable {
        var timestamp: UInt64!
        var beaconCode: Int64!
        var rssi: Int!
    }
    struct DailyRecords: Codable {
        var day: [UInt64:[Record]] = [:]
    }

    private var lastTimestamp: UInt64?
    private var dailyTotal: UInt = 0
    private var lastSeen = LastSeen()
    private var dailyRecords = DailyRecords()

    private let lock = NSLock()
    
    init(parameters: Parameters) {
        self.parameters = parameters
        super.init()
        //load()
        // Enforce retention and backup every hour
        self.timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            self.lock.lock()
            self.enforceRetention()
            self.backup()
            self.lock.unlock()
        }
    }
    
    deinit {
        self.timer.invalidate()
    }
    
    public override func beaconListenerDidUpdate(beaconCode: Int64, rssi: Int) {
        lock.lock()
        do {
            try add(beaconCode: beaconCode, rssi: rssi)
        } catch {}
        lock.unlock()
    }
    
    public func get() -> [Record] {
        var all: [Record] = []
        lock.lock()
        enforceRetention()
        dailyRecords.day.values.forEach { day in
            all.append(contentsOf: day)
        }
        lock.unlock()
        return all
    }
    
    public func count() -> Int {
        let (day,_) = UInt64(NSDate().timeIntervalSince1970).dividedReportingOverflow(by: 24 * 60 * 60)
        if (dailyRecords.day[day] == nil) {
            return 0
        } else {
            return dailyRecords.day[day]!.filter() { record in
                return Double(record.rssi) > parameters.signalStrengthThreshold
            }.count
        }
    }
    
    private func add(beaconCode: Int64, rssi: Int) throws {
        let record = Record(timestamp: UInt64(NSDate().timeIntervalSince1970), beaconCode: beaconCode, rssi: rssi)
        let (day,_) = record.timestamp.dividedReportingOverflow(by: 24 * 60 * 60)
        if (dailyRecords.day[day] == nil) {
            dailyRecords.day[day] = []
        }
        dailyRecords.day[day]!.append(record)
        os_log("Contact (beacon=%s,rssi=%d,dayCount=%d)", log: self.log, type: .debug, beaconCode.description, rssi, dailyRecords.day[day]!.count)
    }
    
    private func enforceRetention() {
        let (day,_) = UInt64(NSDate().timeIntervalSince1970 * 1000).dividedReportingOverflow(by: dayMillis)
        let cutoff = day - UInt64(parameters.retentionPeriod)
        os_log("Enforcing retention period (days=%u)", log: self.log, type: .debug, parameters.retentionPeriod)
        dailyRecords.day.keys.forEach { key in
            if key < cutoff {
                dailyRecords.day.removeValue(forKey: key)
            }
        }
    }
    
    private func backup() {
        os_log("Back up request", log: self.log, type: .debug)
        do {
            let lastSeenData = try JSONEncoder().encode(self.lastSeen)
            debugPrint(String(data: lastSeenData, encoding: .utf8)!)
            let dailyRecordsData = try JSONEncoder().encode(self.dailyRecords)
            debugPrint(String(data: dailyRecordsData, encoding: .utf8)!)

            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            try lastSeenData.write(to: folder.appendingPathComponent("lastSeen"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try dailyRecordsData.write(to: folder.appendingPathComponent("dailyRecords"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            os_log("Back up successful (lastSeen=%s,dailyRecords=%s)", log: self.log, type: .debug, String(describing: lastSeenData), String(describing: dailyRecordsData))
        } catch {
            os_log("Back up failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        }
    }
    
    private func load() {
        os_log("Load request", log: self.log, type: .debug)
        do {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("lastSeen").path), FileManager.default.fileExists(atPath: folder.appendingPathComponent("dailyRecords").path) {
                
                let lastSeenData = try Data(NSData(contentsOfFile: folder.appendingPathComponent("lastSeen").path))
                let dailyRecordsData = try Data(NSData(contentsOfFile: folder.appendingPathComponent("dailyRecords").path))
                
                let lastSeen = try JSONDecoder().decode(LastSeen.self, from: lastSeenData)
                let dailyRecords = try JSONDecoder().decode(DailyRecords.self, from: dailyRecordsData)
                
                self.lastSeen = lastSeen
                self.dailyRecords = dailyRecords
                os_log("Load successful (lastSeen=%s,dailyRecords=%s)", log: self.log, type: .debug, String(describing: lastSeenData), String(describing: dailyRecordsData))
            }
        } catch {
            os_log("Load failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        }
    }
}

public class RiskAnalysis {
    private let log = OSLog(subsystem: "org.C19X", category: "RiskAnalysis")
    private var device: Device!
    
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

    init(device: Device) {
        self.device = device
    }
        
    private static func getExposureToInfection(contactRecords: ContactRecords, rssiThreshold: Double, lookup: Data) -> (total:Int, infectious:Int) {
        let range = Int64(lookup.count * 8)
        let records = contactRecords.get()
        let infectious = records.filter { record in
            guard Double(record.rssi) > rssiThreshold else {
                return false
            }
            let index = Int(abs(record.beaconCode % range))
            return get(lookup, index: index)
        }
        
        return (records.count, infectious.count)
    }
    
    public func update() {
        let (contactCount, exposureCount) = RiskAnalysis.getExposureToInfection(contactRecords: device.contactRecords, rssiThreshold: device.parameters.signalStrengthThreshold, lookup: device.lookup)
        if (device.getStatus() != Device.statusNormal) {
            advice = RiskAnalysis.adviceSelfIsolate;
        } else {
            contact = (exposureCount == 0 ? RiskAnalysis.contactOk : RiskAnalysis.contactInfectious)
            advice = (exposureCount == 0 ? device.parameters.governmentAdvice :
                RiskAnalysis.adviceSelfIsolate)
        }
        os_log("Risk analysis (contacts=%u,exposures=%u,contact=%d,advice=%d)", log: self.log, type: .debug, contactCount, exposureCount, contact, advice)
        for listener in listeners {
            listener.riskAnalysisDidUpdate(contact: contact, advice: advice, contactCount: contactCount, exposureCount: exposureCount)
        }
    }
    
    private static func get(_ data: Data, index: Int) -> Bool {
        return ((data[index / 8] >> (index % 8)) & 1) != 0;
    }

}

public protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(contact:Int, advice:Int, contactCount:Int, exposureCount:Int)
}

public class AbstractRiskAnalysisListener: RiskAnalysisListener {
    public func riskAnalysisDidUpdate(contact:Int, advice:Int, contactCount:Int, exposureCount:Int) {}
}
