//
//  SecuredStorage.swift
//  C19X
//
//  Created by Freddy Choi on 26/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation

class SecuredStorage {
    
    /**
     Set device registration serial number and shared secret in keychain.
     */
    func registration(serialNumber: SerialNumber, sharedSecret: SharedSecret) -> Bool? {
        guard let a = Keychain.shared.set("serialNumber", String(serialNumber)), let b = Keychain.shared.set("sharedSecret", sharedSecret.base64EncodedString()) else {
            return nil
        }
        return a && b
    }
    
    /**
     Get device registration serial number and shared secret from keychain.
     */
    func registration() -> (serialNumber: SerialNumber, sharedSecret: SharedSecret)? {
        guard
            let serialNumberKeychainValue = Keychain.shared.get("serialNumber"),
            let sharedSecretKeychainValue = Keychain.shared.get("sharedSecret"),
            let serialNumber = SerialNumber(serialNumberKeychainValue),
            let sharedSecret = SharedSecret(base64Encoded: sharedSecretKeychainValue) else {
            return nil
        }
        return (serialNumber, sharedSecret)
    }

    /**
     Get health status from keychain.
     */
    func status() -> Status? {
        guard let s = Keychain.shared.get("status"), let n = Int(s), let status = Status(rawValue: n) else {
            return nil
        }
        return status
    }
    
    /**
     Set health status in keychain.
     */
    func status(_ setTo: Status) -> Bool? {
        return Keychain.shared.set("status", setTo.rawValue.description)
    }
    
    /**
     Get contact pattern from keychain.
     */
    func pattern() -> ContactPattern? {
        guard let s = Keychain.shared.get("pattern") else {
            return nil
        }
        return ContactPattern(s)
    }
    
    /**
     Set contact pattern in keychain.
     */
    func pattern(_ setTo: ContactPattern) -> Bool? {
        return Keychain.shared.set("pattern", setTo.description)
    }
    

    /**
     Get health status of contacts from keychain.
     */
    func contactStatus() -> Status? {
        guard let s = Keychain.shared.get("contactStatus"), let n = Int(s), let status = Status(rawValue: n) else {
            return nil
        }
        return status
    }
    
    /**
     Set health status of contacts in keychain.
     */
    func contactStatus(_ setTo: Status) -> Bool? {
        return Keychain.shared.set("contactStatus", setTo.rawValue.description)
    }

    /**
     Get isolation advice from keychain.
     */
    func advice() -> Advice? {
        guard let s = Keychain.shared.get("advice"), let n = Int(s), let advice = Advice(rawValue: n) else {
            return nil
        }
        return advice
    }
    
    /**
     Set isolation advice in keychain.
     */
    func advice(_ setTo: Advice) -> Bool? {
        return Keychain.shared.set("advice", setTo.rawValue.description)
    }

    /**
     Get personal message from keychain.
     */
    func message() -> Message? {
        guard let s = Keychain.shared.get("message") else {
            return nil
        }
        return Message(s)
    }
    
    /**
     Set personal message in keychain.
     */
    func message(_ setTo: Message) -> Bool? {
        return Keychain.shared.set("message", String(setTo))
    }


    /**
     Remove all app data in keychain.
     */
    func remove() {
        _ = Keychain.shared.remove("serialNumber")
        _ = Keychain.shared.remove("sharedSecret")
        _ = Keychain.shared.remove("status")
        _ = Keychain.shared.remove("pattern")
        _ = Keychain.shared.remove("advice")
        _ = Keychain.shared.remove("message")
    }
}

/**
 Device registration number.
 */
typealias SerialNumber = UInt64

/**
 Personal message from server.
 */
typealias Message = String

/**
 Contact pattern.
 */
typealias ContactPattern = String

/**
 Health status.
 */
enum Status: Int {
    var description: String { get {
        switch self {
        case .healthy: return ".healthy"
        case .symptomatic: return ".symptomatic"
        case .confirmedDiagnosis: return ".confirmedDiagnosis"
        case .infectious: return ".infectious"
        }
    }}
    case healthy = 0, symptomatic, confirmedDiagnosis, infectious
}

/**
 Isolation advice.
 */
enum Advice: Int {
    var description: String { get {
        switch self {
        case .normal: return ".normal"
        case .stayAtHome: return ".stayAtHome"
        case .selfIsolation: return ".selfIsolation"
        }
    }}
    case normal = 0, stayAtHome, selfIsolation
}
