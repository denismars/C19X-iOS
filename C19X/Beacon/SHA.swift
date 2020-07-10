//
//  SHA.swift
//  C19X
//
//  Created by Freddy Choi on 09/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CommonCrypto

/**
 SHA hashing algorithm bridge for CommonCrypto implementations.
 */
class SHA {
    
    /**
     Compute SHA256 hash of data.
     */
    static func hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    /**
     Convert SHA256 hash to Java long value.
     */
    static func javaLongValue(digest: Data) -> Int64 {
        let data = [UInt8](digest)
        let valueData: [UInt8] = [data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]].reversed()
        let value = valueData.withUnsafeBytes { $0.load(as: Int64.self) }
        return value
    }
}
