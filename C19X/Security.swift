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
    private static let log = OSLog(subsystem: "org.C19X", category: "Keychain")
    
    public static func update(_ key: String, _ value: String) -> Bool {
        os_log("Update (key=%s)", log: Keychain.log, type: .debug, key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        let attributes: [String: Any] = [kSecAttrAccount as String: key,
                                         kSecValueData as String: value]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            os_log("Update requires create (key=%s)", log: Keychain.log, type: .debug, key)
            return create(key, value)
        }
        guard status == errSecSuccess else {
            os_log("Update failed (key=%s)", log: Keychain.log, type: .debug, key)
            return false
        }
        os_log("Update successful (key=%s)", log: Keychain.log, type: .debug, key)
        return true
    }
    
    public static func create(_ key: String, _ value: String) -> Bool {
        os_log("Create (key=%s)", log: Keychain.log, type: .debug, key)
        let valueData = value.data(using: String.Encoding.utf8)!
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecValueData as String: valueData]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            os_log("Create failed (key=%s)", log: Keychain.log, type: .debug, key)
            return false
        }
        os_log("Create successful (key=%s)", log: Keychain.log, type: .debug, key)
        return true
    }
    
    public static func remove(_ key: String) -> Bool {
        os_log("Remove (key=%s)", log: Keychain.log, type: .debug, key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            os_log("Remove failed (key=%s)", log: Keychain.log, type: .debug, key)
            return false
        }
        os_log("Remove successful (key=%s)", log: Keychain.log, type: .debug, key)
        return true
    }

    public static func get(key: String) -> String? {
        os_log("Get (key=%s)", log: Keychain.log, type: .debug, key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnData as String: kCFBooleanTrue!]
        var retrivedData: AnyObject? = nil
        let status = SecItemCopyMatching(query as CFDictionary, &retrivedData)
        guard status == errSecSuccess else {
            os_log("Get failed (key=%s)", log: Keychain.log, type: .debug, key)
            return nil
        }
        guard let valueData = retrivedData as? Data else {
            os_log("Get failed (key=%s)", log: Keychain.log, type: .debug, key)
            return nil
        }
        os_log("Get successful (key=%s)", log: Keychain.log, type: .debug, key)
        return String(data: valueData, encoding: String.Encoding.utf8)
    }
}
