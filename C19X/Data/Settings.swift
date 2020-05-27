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
    private let log = OSLog(subsystem: "org.c19x", category: "Controller")
    private let userDefaults = UserDefaults.standard
    private let securedStorage = SecuredStorage()
    // Status value is in secured storage
    private let keyStatusLastTimestamp = "Status.LastTimestamp"
    private let keyContactsCount = "Contacts.Count"
    private let keyContactsLastTimestamp = "Contacts.LastTimestamp"
    // Advice value is in secured storage
    private let keyAdviceLastTimestamp = "Advice.LastTimestamp"

    init() {
    }
    
    func reset() -> Bool {
        guard securedStorage.remove() else {
            return false
        }
        userDefaults.removeObject(forKey: keyStatusLastTimestamp)
        userDefaults.removeObject(forKey: keyContactsCount)
        userDefaults.removeObject(forKey: keyContactsLastTimestamp)
        userDefaults.removeObject(forKey: keyAdviceLastTimestamp)
        return true
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
        guard let status = securedStorage.status(), let timestamp = userDefaults.object(forKey: keyContactsLastTimestamp) as? Date else {
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
    
}
