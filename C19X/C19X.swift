//
//  C19X.swift
//  C19X
//
//  Created by Freddy Choi on 18/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation

class C19X {
    let beaconQueue = DispatchQueue(label: "beaconQueue")
    var database: Database
    var transmitter: Transmitter
    var receiver: Receiver
    
    init() {
        database = ConcreteDatabase()
        let dayCodes = ConcreteDayCodes("sharedSecret1".data(using: .utf8)!)
        let beaconCodes = ConcreteBeaconCodes(dayCodes)
        receiver = ConcreteReceiver(queue: beaconQueue, database: database)
        transmitter = ConcreteTransmitter(queue: beaconQueue, beaconCodes: beaconCodes, database: database)
    }
}
