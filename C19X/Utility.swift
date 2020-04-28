//
//  Utilities.swift
//  C19X
//
//  Created by Freddy Choi on 23/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import Compression

open class ByteArray {
    private var byteArray : [UInt8]
    
    public init(_ byteArray : [UInt8]) {
        self.byteArray = byteArray;
    }
    
    public init(_ data : Data) {
        self.byteArray = [UInt8](data);
    }
    
    /// Method to get a single byte from the byte array.
    public func getUInt8(_ index: Int) -> UInt8 {
        let returnValue = byteArray[index]
        return returnValue
    }
    
    /// Method to get an Int16 from two bytes in the byte array (little-endian).
    public func getInt16(_ index: Int) -> Int16 {
        return Int16(bitPattern: getUInt16(index))
    }
    
    /// Method to get a UInt16 from two bytes in the byte array (little-endian).
    public func getUInt16(_ index: Int) -> UInt16 {
        let returnValue = UInt16(byteArray[index]) |
            UInt16(byteArray[index + 1]) << 8
        return returnValue
    }
    
    /// Method to get an Int32 from four bytes in the byte array (little-endian).
    public func getInt32(_ index: Int) -> Int32 {
        return Int32(bitPattern: getUInt32(index))
    }
    
    /// Method to get a UInt32 from four bytes in the byte array (little-endian).
    public func getUInt32(_ index: Int) -> UInt32 {
        let returnValue = UInt32(byteArray[index]) |
            UInt32(byteArray[index + 1]) << 8 |
            UInt32(byteArray[index + 2]) << 16 |
            UInt32(byteArray[index + 3]) << 24
        return returnValue
    }
    
    /// Method to get an Int64 from eight bytes in the byte array (little-endian).
    public func getInt64(_ index: Int) -> Int64 {
        return Int64(bitPattern: getUInt64(index))
    }
    
    /// Method to get a UInt64 from eight bytes in the byte array (little-endian).
    public func getUInt64(_ index: Int) -> UInt64 {
        let returnValue = UInt64(byteArray[index]) |
            UInt64(byteArray[index + 1]) << 8 |
            UInt64(byteArray[index + 2]) << 16 |
            UInt64(byteArray[index + 3]) << 24 |
            UInt64(byteArray[index + 4]) << 32 |
            UInt64(byteArray[index + 5]) << 40 |
            UInt64(byteArray[index + 6]) << 48 |
            UInt64(byteArray[index + 7]) << 56
        return returnValue
    }
}

extension UUID {
    init(numbers: (Int64, Int64)) {
        var firstNumber = numbers.0
        var secondNumber = numbers.1
        let firstData = Data(bytes: &firstNumber, count: MemoryLayout<Int64>.size)
        let secondData = Data(bytes: &secondNumber, count: MemoryLayout<Int64>.size)
        
        let bytes = [UInt8](firstData) + [UInt8](secondData)
        
        let tuple: uuid_t = (bytes[7], bytes[6], bytes[5], bytes[4],
                             bytes[3], bytes[2], bytes[1], bytes[0],
                             bytes[15], bytes[14], bytes[13], bytes[12],
                             bytes[11], bytes[10], bytes[9], bytes[8])
        
        self.init(uuid: tuple)
    }
    
    var intTupleValue: (Int64, Int64) {
        let tuple = self.uuid
        
        let firstBytes: [UInt8] = [tuple.0, tuple.1, tuple.2, tuple.3,
                                   tuple.4, tuple.5, tuple.6, tuple.7]
        
        let secondBytes: [UInt8] = [tuple.8, tuple.9, tuple.10, tuple.11,
                                    tuple.12, tuple.13, tuple.14, tuple.15]
        
        let firstData = Data(firstBytes)
        let secondData = Data(secondBytes)
        
        let first = firstData.withUnsafeBytes { $0.pointee } as Int64
        let second = secondData.withUnsafeBytes { $0.pointee } as Int64
        
        return (first, second)
    }
}

/// Extension for making base64 representations of `Data` safe for
/// transmitting via URL query parameters
extension Data {
    
    /// Instantiates data by decoding a base64url string into base64
    ///
    /// - Parameter string: A base64url encoded string
    init?(base64URLEncoded string: String) {
        self.init(base64Encoded: string.toggleBase64URLSafe(on: false))
    }
    
    /// Encodes the string into a base64url safe representation
    ///
    /// - Returns: A string that is base64 encoded but made safe for passing
    ///            in as a query parameter into a URL string
    func base64URLEncodedString() -> String {
        return self.base64EncodedString().toggleBase64URLSafe(on: true)
    }
}

extension String {
    
    /// Encodes or decodes into a base64url safe representation
    ///
    /// - Parameter on: Whether or not the string should be made safe for URL strings
    /// - Returns: if `on`, then a base64url string; if `off` then a base64 string
    func toggleBase64URLSafe(on: Bool) -> String {
        if on {
            // Make base64 string safe for passing into URL query params
            let base64url = self.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "=", with: "")
            return base64url
        } else {
            // Return to base64 encoding
            var base64 = self.replacingOccurrences(of: "_", with: "/")
                .replacingOccurrences(of: "-", with: "+")
            // Add any necessary padding with `=`
            if base64.count % 4 != 0 {
                base64.append(String(repeating: "=", count: 4 - base64.count % 4))
            }
            return base64
        }
    }
    
}
