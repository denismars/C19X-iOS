//
//  Keychain.swift
//  C19X
//
//  Created by Freddy Choi on 26/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import os

struct Keychain {
    private let log = OSLog(subsystem: "org.C19X.data", category: "Keychain")
    private let service: String = "C19X"
    static let shared = Keychain()
    
    /// Does a certain item exist?
    func exists(_ key: String) -> Bool? {
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecReturnData: false,
            ] as NSDictionary, nil)
        if status == errSecSuccess {
            os_log("Exists (key=%s,result=true)", log: log, type: .debug, key)
            return true
        } else if status == errSecItemNotFound {
            os_log("Exists (key=%s,result=false)", log: log, type: .debug, key)
            return false
        } else {
            os_log("Exists failed (key=%s,error=%s)", log: log, type: .fault, key, status.description)
            return nil
        }
    }
    
    /// Adds an item to the keychain.
    func create(_ key: String, _ value: String) -> Bool {
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            // Allow background access:
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: value.data(using: String.Encoding.utf8)!,
            ] as NSDictionary, nil)
        guard status == errSecSuccess else {
            os_log("Create failed (key=%s,error=%s)", log: log, type: .fault, key, status.description)
            return false
        }
        os_log("Create (key=%s,result=true)", log: log, type: .debug, key)
        return true
    }
    
    /// Updates a keychain item.
    func update(_ key: String, _ value: String) -> Bool {
        let status = SecItemUpdate([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,] as NSDictionary, [
                kSecValueData: value.data(using: String.Encoding.utf8)!,
                ] as NSDictionary)
        guard status == errSecSuccess else {
            os_log("Update failed (key=%s,error=%s)", log: log, type: .fault, key, status.description)
            return false
        }
        os_log("Update (key=%s,result=true)", log: log, type: .debug, key)
        return true
    }
    
    /// Stores a keychain item.
    func set(_ key: String, _ value: String) -> Bool? {
        let e = exists(key)
        if e == nil {
            return nil
        }
        let r = (e! ? update(key, value) : create(key, value))
        os_log("Set (key=%s,result=%s)", log: log, type: .debug, key, r.description)
        return r
    }
    
    // If not present, returns nil. Only throws on error.
    func get(_ key: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            kSecReturnData: true,
            ] as NSDictionary, &result)
        if status == errSecSuccess {
            os_log("Get (key=%s,result=true)", log: log, type: .debug, key)
            return String(data: result as! Data, encoding: .utf8)
        } else if status == errSecItemNotFound {
            os_log("Get (key=%s,result=false)", log: log, type: .debug, key)
            return nil
        } else {
            os_log("Get failed (key=%s,error=%s)", log: log, type: .fault, key, status.description)
            return nil
        }
    }
    
    /// Delete a single item.
    func remove(_ key: String) -> Bool {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service,
            ] as NSDictionary)
        guard status == errSecSuccess else {
            os_log("Remove failed (key=%s,error=%s)", log: log, type: .fault, key, status.description)
            return false
        }
        os_log("Remove (key=%s,result=true)", log: log, type: .debug, key)
        return true
    }
}
