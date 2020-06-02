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

struct AES {
    
    static func encrypt(key: Data?, string: String?) -> String? {
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
            // Error: Failed to generate IV data
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
            // Error: Failed to encrypt data
            return nil
        }
        
        cryptData.removeSubrange(bytesLength..<cryptData.count)
        
        let ivString = iv.base64URLEncodedString()
        let cryptString = cryptData.base64URLEncodedString()
        let bundle = ivString + "," + cryptString
        
        return bundle
    }
}

