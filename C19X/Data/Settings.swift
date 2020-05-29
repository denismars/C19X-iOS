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
    private let keyStatusLastTimestamp = "Status.LastTimestamp"
    private let keyContactsCount = "Contacts.Count"
    private let keyContactsLastTimestamp = "Contacts.LastTimestamp"
    // keyAdviceValue : Advice value is in secured storage
    private let keyAdviceLastTimestamp = "Advice.LastTimestamp"
    private let keyRegistrationState = "RegistrationState"
    private let keySettingsServer = "Settings.Server"
    private let keySettingsRetentionPeriod = "Settings.RetentionPeriod"

    init() {
    }
    
    /**
     Clear all application data
     */
    func reset() {
        os_log("reset", log: self.log, type: .debug)
        userDefaults.removeObject(forKey: keyStatusLastTimestamp)
        userDefaults.removeObject(forKey: keyContactsCount)
        userDefaults.removeObject(forKey: keyContactsLastTimestamp)
        userDefaults.removeObject(forKey: keyAdviceLastTimestamp)
        userDefaults.removeObject(forKey: keySettingsServer)
        userDefaults.removeObject(forKey: keyRegistrationState)
        userDefaults.removeObject(forKey: keySettingsRetentionPeriod)
        securedStorage.remove()
    }
    
    func update(_ setTo: ServerSettings) {
        if let value = setTo["serverAddress"] {
            server(ServerAddress(value))
        }
        if let value = setTo["retentionPeriod"], let days = Int(value) {
            let retentionPeriod = Double(days) * TimeInterval.day
            userDefaults.set(retentionPeriod, forKey: keySettingsRetentionPeriod)
        }
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
     Set health status.
     */
    func status(_ setTo: Status) -> Date? {
        guard securedStorage.status(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyStatusLastTimestamp)
        return timestamp
    }
    
    /**
     Get health status and last update timestamp.
     */
    func status() -> (status: Status, timestamp: Date) {
        guard let status = securedStorage.status(), let timestamp = userDefaults.object(forKey: keyStatusLastTimestamp) as? Date else {
            return (.healthy, Date.distantPast)
        }
        return (status, timestamp)
    }
    
    /**
     Set contacts count and last update timestamp
     */
    func contacts(_ setTo: Int) -> Date {
        let timestamp = Date()
        userDefaults.set(setTo, forKey: keyContactsCount)
        userDefaults.set(timestamp, forKey: keyContactsLastTimestamp)
        return timestamp
    }

    /**
     Set contacts count and last update timestamp
     */
    func contacts(_ setTo: Int, lastUpdate: Date?) {
        userDefaults.set(setTo, forKey: keyContactsCount)
        guard let timestamp = lastUpdate else {
            userDefaults.removeObject(forKey: keyContactsLastTimestamp)
            return
        }
        userDefaults.set(timestamp, forKey: keyContactsLastTimestamp)
    }

    /**
     Set contacts status and last update timestamp
     */
    func contacts(_ setTo: Status) -> Date? {
        guard securedStorage.contactStatus(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyContactsLastTimestamp)
        return timestamp
    }

    /**
     Get contacts status, count and last update timestamp
     */
    func contacts() -> (count: Int, status: Status, timestamp: Date) {
        let count = userDefaults.integer(forKey: keyContactsCount)
        let status = securedStorage.contactStatus() ?? Status.healthy
        guard let timestamp = userDefaults.object(forKey: keyContactsLastTimestamp) as? Date else {
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
        userDefaults.set(timestamp, forKey: keyAdviceLastTimestamp)
        return timestamp
    }
    
    /**
     Get isolation advice and last update timestamp.
     */
    func advice() -> (advice: Advice, timestamp: Date) {
        guard let advice = securedStorage.advice(), let timestamp = userDefaults.object(forKey: keyAdviceLastTimestamp) as? Date else {
            return (.stayAtHome, Date.distantPast)
        }
        return (advice, timestamp)
    }
    
    /**
     Set personal message.
     */
    func message(_ setTo: Message) -> Date? {
        guard securedStorage.message(setTo) ?? false else {
            return nil
        }
        let timestamp = Date()
        userDefaults.set(timestamp, forKey: keyAdviceLastTimestamp)
        return timestamp
    }
    
    /**
     Get personal message and last advice update timestamp.
     */
    func message() -> (message: Message, timestamp: Date) {
        guard let message = securedStorage.message(), let timestamp = userDefaults.object(forKey: keyAdviceLastTimestamp) as? Date else {
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
            return "https://c19x-dev.servehttp.com/"
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

