//
//  Security.swift
//  C19X
//
//  Created by Freddy Choi on 26/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import CommonCrypto
import os

public struct AES {
    
    public static func encrypt(key: Data?, string: String?) -> String? {
        guard let string = string else { return nil }
        
        guard let data = string.data(using: .utf8) else { return nil }
        
        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData   = Data(count: cryptLength)
        
        let keyLength = key!.count
        let options   = CCOptions(kCCOptionPKCS7Padding)
        
        var bytesLength = Int(0)
        
        var iv = Data(count: 16)
        let ivResult = iv.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        
        guard ivResult == errSecSuccess else {
            debugPrint("Error: Failed to generate IV data. Status \(ivResult)")
            return nil
        }
        
        let status = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    key!.withUnsafeBytes { keyBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options, keyBytes.baseAddress, keyLength, ivBytes.baseAddress, dataBytes.baseAddress, data.count, cryptBytes.baseAddress, cryptLength, &bytesLength)
                    }
                }
            }
        }
        
        guard UInt32(status) == UInt32(kCCSuccess) else {
            debugPrint("Error: Failed to crypt data. Status \(status)")
            return nil
        }
        
        cryptData.removeSubrange(bytesLength..<cryptData.count)
        
        let ivString = iv.base64URLEncodedString()
        let cryptString = cryptData.base64URLEncodedString()
        let bundle = ivString + "," + cryptString
        
        return bundle
    }
}

public struct Keychain {
    private let log = OSLog(subsystem: "org.C19X", category: "Keychain")
    private let service: String = "C19X"
    public static let shared = Keychain()
    
    /// Does a certain item exist?
    public func exists(_ key: String) -> Bool? {
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
    private func create(_ key: String, _ value: String) -> Bool {
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
    private func update(_ key: String, _ value: String) -> Bool {
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
    public func set(_ key: String, _ value: String) -> Bool? {
        let e = exists(key)
        if e == nil {
            return nil
        }
        let r = (e! ? update(key, value) : create(key, value))
        os_log("Set (key=%s,result=%s)", log: log, type: .debug, key, r.description)
        return r
    }
    
    // If not present, returns nil. Only throws on error.
    public func get(_ key: String) -> String? {
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
    public func remove(_ key: String) -> Bool {
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
