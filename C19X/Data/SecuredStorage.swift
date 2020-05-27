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
     Remove all app data in keychain.
     */
    func remove() -> Bool {
        return Keychain.shared.remove("serialNumber") && Keychain.shared.remove("sharedSecret") && Keychain.shared.remove("status") && Keychain.shared.remove("advice")
    }
}

/**
 Device registration number.
 */
typealias SerialNumber = UInt64

/**
 Health status.
 */
enum Status: Int {
    case healthy = 0, symptomatic, confirmedDiagnosis
}

/**
 Isolation advice.
 */
enum Advice: Int {
    case normal = 0, stayAtHome, selfIsolation
}
