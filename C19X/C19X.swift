//
//  C19X.swift
//  C19X
//
//  Created by Freddy Choi on 18/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation

class C19X {
    var beacon: Transceiver
    var database: Database
    
    init() {
        beacon = Transceiver("sharedSecret1".data(using: .utf8)!, codeUpdateAfter: 120)
        database = ConcreteDatabase()
    }
}
