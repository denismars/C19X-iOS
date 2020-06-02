//
//  DayCodesTest.swift
//  C19XTests
//
//  Created by Freddy Choi on 01/06/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import XCTest
@testable import C19X

//0:0 day=1443087401359677750, seed=7525003092670007258, code=-8129047106903552267
//0:1 day=1443087401359677750, seed=7525003092670007258, code=8443977219705625829
//1:0 day=7940984811893783192, seed=3537033893445398299, code=-850124991640589653
//1:1 day=7940984811893783192, seed=3537033893445398299, code=-5720254713763274613

//0:0 day=1443087401359677750, seed=7525003092670007258, code=-8129047106903552267
//0:1 day=1443087401359677750, seed=7525003092670007258, code=8443977219705625829
//1:0 day=7940984811893783192, seed=3537033893445398299, code=-850124991640589653
//1:1 day=7940984811893783192, seed=3537033893445398299, code=-5720254713763274613

class DayCodesTest: XCTestCase {

    func testDayCodes() throws {
        let sharedSecret = SharedSecret([0])
        let dayCodes = ConcreteDayCodes.dayCodes(sharedSecret, days: 2)
        for i in 0...dayCodes.count-1 {
            let dayCode = dayCodes[i]
            let beaconCodeSeed = ConcreteDayCodes.beaconCodeSeed(dayCode)
            let beaconCodes = ConcreteBeaconCodes.beaconCodes(beaconCodeSeed, count: 2)
            for j in 0...beaconCodes.count-1 {
                let beaconCode = beaconCodes[j]
                print("\(i):\(j) day=\(dayCode), seed=\(beaconCodeSeed), code=\(beaconCode)")
            }
        }
    }
    
    func testDay153Codes() throws {
        let sharedSecret = SharedSecret([0])
        let dayCodes = ConcreteDayCodes.dayCodes(sharedSecret, days: 365 * 5)
        let today = 153
        let dayCode = dayCodes[today]
        let beaconCodeSeed = ConcreteDayCodes.beaconCodeSeed(dayCode)
        let beaconCodes = ConcreteBeaconCodes.beaconCodes(beaconCodeSeed, count: 2)
        for j in 0...beaconCodes.count-1 {
            let beaconCode = beaconCodes[j]
            print("\(today):\(j) dayCode=\(dayCode), beaconCodeSeed=\(beaconCodeSeed), beaconCode=\(beaconCode)")
        }
    }
}
