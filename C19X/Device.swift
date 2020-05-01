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

    public var parameters: Parameters!
    public var contactRecords: ContactRecords!
    public var riskAnalysis: RiskAnalysis!
    public var beacon: Beacon!
    public var network: Network!
    
    override init() {
        super.init()
        
        parameters = Parameters()
        contactRecords = ContactRecords(parameters: parameters)

        network = Network(device: self)
        riskAnalysis = RiskAnalysis(device: self)

        beacon = Beacon(serviceId: 9803801938501395)
        beacon.listeners.append(contactRecords)

        network.listeners.append(self)

        reset()
        load()
        
        network.getTimeFromServerAndSynchronise()
        network.getParameters()
    }
    
    public func set(status: Int) {
        self.status = status
        let _ = Keychain.remove(key: "status")
        let _ = Keychain.put(key: "status", value: status.description)
        os_log("Set status (status=%d)", log: log, type: .debug, status)
    }
    
    public func getStatus() -> Int {
        return self.status
    }
    
    private func reset() {
        os_log("Reset (REMOVE FOR PRODUCTION USE)", log: log, type: .error)
        let _ = Keychain.remove(key: "serialNumber")
        let _ = Keychain.remove(key: "sharedSecret")
        let _ = Keychain.remove(key: "status")
    }
    
    private func load() {
        os_log("Load", log: log, type: .debug)
        // Registration
        let serialNumber = Keychain.get(key: "serialNumber")
        let sharedSecretBase64Encoded = Keychain.get(key: "sharedSecret")
        if (serialNumber != nil && sharedSecretBase64Encoded != nil) {
            self.serialNumber = UInt64(serialNumber!)!
            self.sharedSecret = Data(base64Encoded: sharedSecretBase64Encoded!)!
            self.codes = Codes(sharedSecret: self.sharedSecret)
            os_log("Registration loaded from keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
            startTransmitterAndScheduleCodeChange()
        } else {
            os_log("Registration required", log: log, type: .info)
            network.getRegistration()
        }
        
        // Status
        let statusString = Keychain.get(key: "status")
        if (statusString != nil) {
            if let status = Int(statusString!) {
                self.status = status
                network.postStatus(status)
            }
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
    
    private func startTransmitterAndScheduleCodeChange() {
        if (codes != nil) {
            let beaconCode = codes!.get(parameters.retentionPeriod)
            beacon.setBeaconCode(beaconCode: beaconCode)
            os_log("Beacon transmitter code update (code=%s)", log: log, type: .debug, beaconCode.description)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(parameters.beaconTransmitterCodeDuration))) {
                self.startTransmitterAndScheduleCodeChange()
            }
        }
    }
    
    public override func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {
        let _ = Keychain.remove(key: "serialNumber")
        let _ = Keychain.remove(key: "sharedSecret")
        if Keychain.put(key: "serialNumber", value: String(serialNumber)), Keychain.put(key: "sharedSecret", value: sharedSecret.base64EncodedString()) {
            os_log("Registration saved to keychain (serialNumber=%u)", log: log, type: .debug, self.serialNumber)
        }
        self.serialNumber = serialNumber
        self.sharedSecret = sharedSecret
        self.codes = Codes(sharedSecret: sharedSecret)
        os_log("Starting beacon transmitter following registration", log: log, type: .debug)
        startTransmitterAndScheduleCodeChange()
    }
    
    public override func networkListenerFailedUpdate(registrationError: Error?) {
        os_log("Registration failed, retrying in 10 minutes (error=%s)", log: log, type: .debug, String(describing: registrationError))
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(10 * 60))) {
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
    public var signalStrengthThreshold = (-82.03 - 4.57);
    public var contactDurationThreshold = 5 * 60000;
    public var exposureDurationThreshold = 15 * 60000;
    public var beaconReceiverOnDuration = 15000;
    public var beaconReceiverOffDuration = 85000;
    public var beaconTransmitterCodeDuration = 30 * 60000;
    
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
        if let v = dictionary["contactDurationThreshold"], let n = Int(v) {
            contactDurationThreshold = n
        }
        if let v = dictionary["exposureDurationThreshold"], let n = Int(v) {
            exposureDurationThreshold = n
        }
        if let v = dictionary["beaconReceiverOnDuration"], let n = Int(v) {
            beaconReceiverOnDuration = n
        }
        if let v = dictionary["beaconReceiverOffDuration"], let n = Int(v) {
            beaconReceiverOffDuration = n
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
    struct DailyRecords: Codable {
        var day: [UInt64:[Int64:UInt64]] = [:]
    }

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
    
    public func descriptionForToday() -> (value:String, unit:String, milliseconds:UInt64) {
        let timestamp = UInt64(NSDate().timeIntervalSince1970 * 1000)
        let (day,_) = timestamp.dividedReportingOverflow(by: dayMillis)
        if (dailyRecords.day[day] == nil) {
            return ("0", "minute", 0)
        } else {
            var sum:UInt64 = 0
            dailyRecords.day[day]!.values.forEach { duration in
                sum += duration
            }
            let (value, unit) = sum.duration()
            return (String(value), unit, sum)
        }
    }
    
    public func sum() -> [Int64:UInt64] {
        var sum: [Int64:UInt64] = [:]
        lock.lock()
        enforceRetention()
        dailyRecords.day.values.forEach { day in
            day.forEach { beaconCode, duration in
                if sum[beaconCode] == nil {
                    sum[beaconCode] = duration
                } else {
                    sum[beaconCode]! += duration
                }
            }
        }
        lock.unlock()
        return sum
    }
    
    private func add(beaconCode: Int64, rssi: Int) throws {
        if (Double(rssi) >= parameters.signalStrengthThreshold) {
            let timestamp = UInt64(NSDate().timeIntervalSince1970 * 1000)
            if lastSeen.beacon[beaconCode] == nil {
                lastSeen.beacon[beaconCode] = timestamp
                os_log("Contact (type=first,beacon=%s,rssi=%d)", log: self.log, type: .debug, beaconCode.description, rssi)
            } else {
                let elapsed = timestamp - lastSeen.beacon[beaconCode]!
                if elapsed > parameters.contactDurationThreshold {
                    os_log("Contact (type=newPeriod,beacon=%s,rssi=%d)", log: self.log, type: .debug, beaconCode.description, rssi)
                } else {
                    let (day,_) = timestamp.dividedReportingOverflow(by: dayMillis)
                    if (dailyRecords.day[day] == nil) {
                        dailyRecords.day[day] = [:]
                        dailyRecords.day[day]![beaconCode] = elapsed
                        os_log("Contact (type=continuous|newDay,beacon=%s,rssi=%d,elapsed=%u,total=%u)", log: self.log, type: .debug, beaconCode.description, rssi, elapsed, dailyRecords.day[day]![beaconCode]!)
                    } else if (dailyRecords.day[day]![beaconCode] == nil) {
                        dailyRecords.day[day]![beaconCode] = elapsed
                        os_log("Contact (type=continuous|newDay,beacon=%s,rssi=%d,elapsed=%u,total=%u)", log: self.log, type: .debug, beaconCode.description, rssi, elapsed, dailyRecords.day[day]![beaconCode]!)
                    } else {
                        dailyRecords.day[day]![beaconCode]! += elapsed
                        os_log("Contact (type=continuous,beacon=%s,rssi=%d,elapsed=%u,total=%u)", log: self.log, type: .debug, beaconCode.description, rssi, elapsed, dailyRecords.day[day]![beaconCode]!)
                    }
                }
                lastSeen.beacon[beaconCode] = timestamp
            }
        } else {
            os_log("Contact discarded, weak signal (beacon=%s,rssi=%d,threshold=%d)", log: self.log, type: .debug, beaconCode.description, rssi, parameters.signalStrengthThreshold)
        }
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
    private var device: Device!
    
    public static let contactOk = 0
    public static let contactInfectious = 1
    
    public static let adviceFreedom = 0
    public static let adviceStayAtHome = 1
    public static let adviceSelfIsolate = 2
    
    public var contact = RiskAnalysis.contactOk
    public var advice = RiskAnalysis.adviceStayAtHome
    
    public var contactTime: UInt64 = 0
    public var exposureTime: UInt64 = 0
    
    init(device: Device) {
        self.device = device
    }
        
    private static func getExposureToInfection(contactRecords: ContactRecords, lookup: Data) -> (total:UInt64, infectious:UInt64) {
        let range = Int64(lookup.count * 8)
        let records = contactRecords.sum()
        let infectious = records.filter { key, value in
            let index = Int(abs(key % range))
            return get(lookup, index: index)
        }
        
        var sumTotal = UInt64(0)
        records.values.forEach { duration in
            sumTotal += UInt64(duration)
        }
        var sumInfectious = UInt64(0)
        infectious.values.forEach { duration in
            sumInfectious += UInt64(duration)
        }
        return (sumTotal, sumInfectious)
    }
    
    public func update() {
        let (contactTime, exposureTime) = RiskAnalysis.getExposureToInfection(contactRecords: device.contactRecords, lookup: device.lookup)
        if (device.getStatus() != Device.statusNormal) {
            advice = RiskAnalysis.adviceSelfIsolate;
        } else {
            contact = (exposureTime == 0 ? RiskAnalysis.contactOk : RiskAnalysis.contactInfectious)
            advice = (exposureTime >= device.parameters.contactDurationThreshold ?
                RiskAnalysis.adviceSelfIsolate :
                device.parameters.governmentAdvice)
        }
        debugPrint("Risk analysis (total=\(contactTime),infectious=\(exposureTime),contact=\(contact),advice=\(advice))")
    }
    
    private static func get(_ data: Data, index: Int) -> Bool {
        return ((data[index / 8] >> (index % 8)) & 1) != 0;
    }

}

public protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(contact:Int, advice:Int, contactTime:UInt64, exposureTime:UInt64)
}


public class AbstractRiskAnalysisListener: RiskAnalysisListener {
    public func riskAnalysisDidUpdate(contact:Int, advice:Int, contactTime:UInt64, exposureTime:UInt64) {}
}
