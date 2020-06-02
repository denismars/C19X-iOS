//
//  Settings.swift
//  C19X
//
//  Created by Freddy Choi on 26/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import os

class Settings {
    static let shared = Settings()
    private let log = OSLog(subsystem: "org.c19x.data", category: "Settings")
    private let userDefaults = UserDefaults.standard
    private let securedStorage = SecuredStorage()
    // keyStatusValue : Status value is in secured storage
    private let keyContactsCount = "Contacts.Count"
    // keyAdviceValue : Advice value is in secured storage
    private let keyRegistrationState = "RegistrationState"
    private let keySettings = "Settings"
    private let keySettingsTimeDelta = "Settings.TimeDelta"
    private let keySettingsServer = "Settings.Server"
    private let keySettingsRetentionPeriod = "Settings.RetentionPeriod"
    private let keySettingsProximity = "Settings.Proximity"
    private let keySettingsExposure = "Settings.Exposure"
    private let keySettingsDefaultAdvice = "Settings.DefaultAdvice"

    private let keyTimestampTime = "Timestamp.Time"
    private let keyTimestampStatus = "Timestamp.Status"
    private let keyTimestampStatusRemote = "Timestamp.Status.Remote"
    private let keyTimestampContact = "Timestamp.Contact"
    private let keyTimestampAdvice = "Timestamp.Advice"
    private let keyTimestampMessage = "Timestamp.Message"
    private let keyTimestampSettings = "Timestamp.Settings"
    private let keyTimestampInfectionData = "Timestamp.InfectionData"

    /**
     Clear all application data
     */
    func reset() {
        os_log("reset", log: self.log, type: .debug)
        userDefaults.removeObject(forKey: keyContactsCount)
        userDefaults.removeObject(forKey: keyRegistrationState)
        userDefaults.removeObject(forKey: keySettings)
        userDefaults.removeObject(forKey: keySettingsTimeDelta)
        userDefaults.removeObject(forKey: keySettingsServer)
        userDefaults.removeObject(forKey: keySettingsRetentionPeriod)
        userDefaults.removeObject(forKey: keySettingsProximity)
        userDefaults.removeObject(forKey: keySettingsExposure)
        userDefaults.removeObject(forKey: keySettingsDefaultAdvice)
        userDefaults.removeObject(forKey: keyTimestampTime)
        userDefaults.removeObject(forKey: keyTimestampStatus)
        userDefaults.removeObject(forKey: keyTimestampStatusRemote)
        userDefaults.removeObject(forKey: keyTimestampContact)
        userDefaults.removeObject(forKey: keyTimestampAdvice)
        userDefaults.removeObject(forKey: keyTimestampMessage)
        userDefaults.removeObject(forKey: keyTimestampSettings)
        userDefaults.removeObject(forKey: keyTimestampInfectionData)
        do {
            let fileURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("infectionData.json")
            try FileManager.default.removeItem(at: fileURL)
        } catch {}
        securedStorage.remove()
    }
    
    func set(_ setTo: ServerSettings) {
        let timestamp = Date()
        userDefaults.set(setTo, forKey: keySettings)
        userDefaults.set(timestamp, forKey: keyTimestampSettings)
        if let value = setTo["server"] {
            server(ServerAddress(value))
        }
        if let value = setTo["retention"], let days = Int(value) {
            let retentionPeriod = Double(days) * TimeInterval.day
            userDefaults.set(retentionPeriod, forKey: keySettingsRetentionPeriod)
        }
        if let value = setTo["proximity"], let proximity = Int(value) {
            userDefaults.set(proximity, forKey: keySettingsProximity)
        }
        if let value = setTo["exposure"], let exposure = Int(value) {
            userDefaults.set(exposure, forKey: keySettingsExposure)
        }
        if let value = setTo["advice"], let advice = Int(value) {
            userDefaults.set(advice, forKey: keySettingsDefaultAdvice)
        }
    }
    
    func get() -> (ServerSettings?, Date) {
        guard let settings = userDefaults.object(forKey: keySettings) as? ServerSettings, let timestamp = userDefaults.object(forKey: keyTimestampSettings) as? Date else {
            return (nil, Date.distantPast)
        }
        return (settings, timestamp)
    }
    
    /**
     Set registration state.
     */
    func registrationState(_ setTo: RegistrationState) {
        userDefaults.set(setTo.rawValue, forKey: keyRegistrationState)
    }
    
    /**
     Get registration state.
     */
    func registrationState() -> RegistrationState {
        guard let s = userDefaults.string(forKey: keyRegistrationState), let state = RegistrationState(rawValue: s) else {
            return RegistrationState.unregistered
        }
        return state
    }
    
    /**
     Set registration.
     */
    func registration(serialNumber: SerialNumber, sharedSecret: SharedSecret) -> Bool? {
        let success = securedStorage.registration(serialNumber: serialNumber, sharedSecret: sharedSecret)
        if let success = success, success {
            registrationState(.registered)
        } else {
            registrationState(.unregistered)
        }
        return success
    }
    
    /**
     Get registration.
     */
    func registration() -> (serialNumber: SerialNumber, sharedSecret: SharedSecret)? {
        securedStorage.registration()
    }
    
    /**
     Set time delta between device and server.
     */
    func timeDelta(_ setTo: TimeMillis) {
        let timestamp = Date()
        userDefaults.set(setTo, forKey: keySettingsTimeDelta)
        userDefaults.set(timestamp, forKey: keyTimestampTime)
    }
    
    /**
     Get time delta.
     */
    func timeDelta() -> (TimeMillis, Date) {
        guard let timeDelta = userDefaults.object(forKey: keySettingsTimeDelta) as? TimeMillis, let timestamp = userDefaults.object(forKey: keyTimestampTime) as? Date else {
            return (0, Date.distantPast)
        }
        return (timeDelta, timestamp)
    }

    /**
     Set health status.
     */
    func status(_ setTo: Status) -> Date? {
        guard securedStorage.status(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyTimestampStatus)
        return timestamp
    }

    /**
     Set status remote timestamp for tracking whether synchronise status is required.
     */
    func statusDidUpdateAtServer() {
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyTimestampStatusRemote)
    }
    
    /**
     Get health status and last update timestamp.
     */
    func status() -> (status: Status, timestamp: Date, remoteTimestamp: Date) {
        guard let status = securedStorage.status(), let timestamp = userDefaults.object(forKey: keyTimestampStatus) as? Date else {
            return (.healthy, Date.distantPast, Date.distantPast)
        }
        guard let remoteTimestamp = userDefaults.object(forKey: keyTimestampStatusRemote) as? Date else {
            return (status, timestamp, Date.distantPast)
        }
        return (status, timestamp, remoteTimestamp)
    }
    
    /**
     Set contacts count and last update timestamp
     */
    func contacts(_ setTo: Int) -> Date {
        let timestamp = Date()
        userDefaults.set(setTo, forKey: keyContactsCount)
        userDefaults.set(timestamp, forKey: keyTimestampContact)
        return timestamp
    }
    
    /**
     Set contacts count and last update timestamp
     */
    func contacts(_ setTo: Int, lastUpdate: Date?) {
        userDefaults.set(setTo, forKey: keyContactsCount)
        guard let timestamp = lastUpdate else {
            userDefaults.removeObject(forKey: keyTimestampContact)
            return
        }
        userDefaults.set(timestamp, forKey: keyTimestampContact)
    }
    
    /**
     Set contacts status and last update timestamp
     */
    func contacts(_ setTo: Status) -> Date? {
        guard securedStorage.contactStatus(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyTimestampContact)
        return timestamp
    }
    
    /**
     Get contacts status, count and last update timestamp
     */
    func contacts() -> (count: Int, status: Status, timestamp: Date) {
        let count = userDefaults.integer(forKey: keyContactsCount)
        let status = securedStorage.contactStatus() ?? Status.healthy
        guard let timestamp = userDefaults.object(forKey: keyTimestampContact) as? Date else {
            return (count, status, Date.distantPast)
        }
        return (count, status, timestamp)
    }
    
    /**
     Set isolation advice.
     */
    func advice(_ setTo: Advice) -> Date? {
        guard securedStorage.advice(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyTimestampAdvice)
        return timestamp
    }
    
    /**
     Get isolation advice and last update timestamp.
     */
    func advice() -> (defaultAdvice: Advice, advice: Advice, timestamp: Date) {
        var defaultAdvice: Advice = .stayAtHome
        if let rawValue = userDefaults.object(forKey: keySettingsDefaultAdvice) as? Int, let a = Advice(rawValue: rawValue) {
            defaultAdvice = a
        }
        guard let advice = securedStorage.advice(), let timestamp = userDefaults.object(forKey: keyTimestampAdvice) as? Date else {
            return (defaultAdvice, .stayAtHome, Date.distantPast)
        }
        return (defaultAdvice, advice, timestamp)
    }
    
    /**
     Set personal message.
     */
    func message(_ setTo: Message) -> Date? {
        guard securedStorage.message(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyTimestampMessage)
        return timestamp
    }
    
    /**
     Get personal message and last update timestamp.
     */
    func message() -> (message: Message, timestamp: Date) {
        guard let message = securedStorage.message(), let timestamp = userDefaults.object(forKey: keyTimestampMessage) as? Date else {
            return ("", Date.distantPast)
        }
        return (message, timestamp)
    }
    
    
    /**
     Set server address.
     */
    func server(_ setTo: ServerAddress) {
        userDefaults.set(setTo, forKey: keySettingsServer)
    }
    
    /**
     Get server address.
     */
    func server() -> ServerAddress {
        guard let server = userDefaults.string(forKey: keySettingsServer) else {
//            return "https://c19x-dev.servehttp.com/"
            return "https://preprod.c19x.org/"
        }
        return server
    }
    
    /**
     Get retention period.
     */
    func retentionPeriod() -> RetentionPeriod {
        guard let value = userDefaults.object(forKey: keySettingsRetentionPeriod), let retentionPeriod = value as? RetentionPeriod else {
            return RetentionPeriod(14 * TimeInterval.day)
        }
        return retentionPeriod
    }
    
    /**
     Set infection data (stored in application support directory in clear text, as its public data)
     */
    func infectionData(_ setTo: InfectionData) {
        do {
            let fileURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("infectionData.json")
            var json: [String:String] = [:]
            setTo.forEach() { beaconCodeSeed, status in
                json[beaconCodeSeed.description] = status.rawValue.description
            }
            try JSONSerialization.data(withJSONObject: json).write(to: fileURL)
            let timestamp = Date()
            userDefaults.set(timestamp, forKey: keyTimestampInfectionData)
        } catch {
            os_log("Failed to write infection data to storage (error=%s)", log: self.log, type: .fault, String(describing: error))
        }
    }

    /**
     Set infection data (stored in application support directory in clear text, as its public data)
     */
    func infectionData() -> (InfectionData, Date) {
        guard let timestamp = userDefaults.object(forKey: keyTimestampInfectionData) as? Date else {
            return (InfectionData(), Date.distantPast)
        }
        var infectionData = InfectionData()
        do {
            let fileURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("infectionData.json")
            let data = try Data(contentsOf: fileURL)
            if let dictionary = try JSONSerialization.jsonObject(with: data) as? [String:String] {
                dictionary.forEach() { key, value in
                    guard let beaconCodeSeed = BeaconCodeSeed(key), let rawValue = Int(value), let status = Status(rawValue: rawValue) else {
                        return
                    }
                    infectionData[beaconCodeSeed] = status
                }
            }
        } catch {
            os_log("Failed to read infection data from storage (error=%s)", log: self.log, type: .fault, String(describing: error))
        }
        return (infectionData, timestamp)
    }
    
    /**
     Get proximity for disease transmission.
     */
    func proximity() -> RSSI {
        guard let value = userDefaults.object(forKey: keySettingsProximity) as? Int else {
            return RSSI(-77)
        }
        return RSSI(value)
    }

    /**
     Get exposure duration for disease transmission.
     */
    func exposure() -> ExposurePeriod {
        guard let value = userDefaults.object(forKey: keySettingsExposure) as? Int else {
            return ExposurePeriod(15)
        }
        return ExposurePeriod(value)
    }
}

/**
 Server address.
 */
typealias ServerAddress = String

/**
 Server-side settings for parsing and synchronising.
 */
typealias ServerSettings = [String:String]

/**
 Retention period for database log data.
 */
typealias RetentionPeriod = TimeInterval

/**
 Device registration state.
 */
enum RegistrationState: String {
    case unregistered, registering, registered
}

/**
 Infection data for on-device matching.
 */
typealias InfectionData = [BeaconCodeSeed:Status]
