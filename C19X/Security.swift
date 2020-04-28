//
//  Security.swift
//  C19X
//
//  Created by Freddy Choi on 26/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import CommonCrypto

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
    
    public static func put(key: String, value: String) -> Bool {
        let valueData = value.data(using: String.Encoding.utf8)!
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecValueData as String: valueData]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            return false
        }
        return true
    }
    
    public static func remove(key: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            return false
        }
        return true
    }

    public static func get(key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnData as String: kCFBooleanTrue!]
        var retrivedData: AnyObject? = nil
        let _ = SecItemCopyMatching(query as CFDictionary, &retrivedData)
        guard let valueData = retrivedData as? Data else {
            return nil
        }
        return String(data: valueData, encoding: String.Encoding.utf8)
    }
}
