//
//  BeaconCodes.swift
//  C19X
//
//  Created by Freddy Choi on 11/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CryptoKit
import BigInt
import os

protocol BeaconCodes {
    func get() -> BeaconCode?
    func get(_ day: Day) -> [BeaconCode]?
}

typealias BeaconCode = Int64
typealias BeaconCodeSeed = Data

class ConcreteBeaconCodes : BeaconCodes {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "BeaconCodes")
    private var dayCodes: DayCodes
    private var dayCode: DayCode?
    private var values:[BeaconCode]?
    
    init(_ dayCodes: DayCodes) {
        self.dayCodes = dayCodes
    }
    
    func get() -> BeaconCode? {
        if dayCode == nil {
            guard let code = dayCodes.get() else {
                os_log("No day code available", log: log, type: .fault)
                return nil
            }
            dayCode = code
        }
        guard let code = dayCodes.get() else {
            os_log("No day code available", log: log, type: .fault)
            return nil
        }
        if values == nil || dayCode != code {
            os_log("Generating beacon codes for new day", log: log, type: .debug)
            self.dayCode = code
            values = generate(seedOf(dayCode!))
        }
        guard let values = values else {
            os_log("No beacon code available", log: log, type: .fault)
            return nil
        }
        return values[Int.random(in: 0 ... (values.count - 1))]
    }
    
    func get(_ day: Day) -> [BeaconCode]? {
        guard let dayCode = dayCodes.get(day) else {
            os_log("No day code available", log: log, type: .fault)
            return nil
        }
        return generate(seedOf(dayCode))
    }
    
    /*
        Cryptographically separate day code from beacon code seed (seeds are published by cloud server for on-device matching)
    */
    /**
     Cryptographically separate day code from beacon code seed. Seeds are published
     by the cloud server for on-device matching.
     */
    private func seedOf(_ dayCode: DayCode) -> BeaconCodeSeed {
        var data = withUnsafeBytes(of: dayCode) { Data($0) }
        data.reverse()
        let hash = SHA256.hash(data: data)
        return BeaconCodeSeed(hash)
    }

    private func generate(_ beaconCodeSeed: BeaconCodeSeed) -> [BeaconCode] {
        let codes = 24 * 10
        let range = BigInt(BeaconCode.max)
        os_log("Generating forward secure beacon codes (codes=%d,range=%s)", log: log, type: .debug, codes, range.description)
        var hash = SHA256.hash(data: beaconCodeSeed)
        var values = [BeaconCode](repeating: 0, count: codes)
        for i in (0 ... (codes - 1)).reversed() {
            let hashData = Data(hash)
            let value = BigInt(hashData)
            values[i] = DayCode(value % range)
            hash = SHA256.hash(data: hashData)
            debugPrint("Beacon code : \(i) -> \(values[i]) <= \(value)")
        }
        os_log("Generated forward secure beacon codes (codes=%d,range=%s)", log: log, type: .debug, codes, range.description)
        return values
    }

}
