//
//  Controller.swift
//  C19X
//
//  Created by Freddy Choi on 23/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import os

protocol Controller {
    var settings: Settings { get }
    var transceiver: Transceiver? { get }
    
    /// Delegates for receiving application events.
    var delegates: [ControllerDelegate] { get set }
    
    func start()
}


class ConcreteController : Controller, ReceiverDelegate {
    private let log = OSLog(subsystem: "org.c19x", category: "Controller")
    var delegates: [ControllerDelegate] = []

    private let database: Database = ConcreteDatabase()
    let settings = Settings()
    var transceiver: Transceiver?
    
    init() {
    }
    
    func start() {
        initialiseTransceiver(sharedSecret: "Shared".data(using: .utf8)!, codeUpdateAfter: 120)
    }
    
    private func initialiseTransceiver(sharedSecret: SharedSecret, codeUpdateAfter: TimeInterval) {
        transceiver = ConcreteTransceiver(sharedSecret, codeUpdateAfter: 120)
        transceiver?.append(self)
        delegates.forEach { $0.transceiver(transceiver!) }
    }

    // MARK:- ReceiverDelegate
    
    func receiver(didDetect: BeaconCode, rssi: RSSI) {
        database.insert(time: Date(), code: didDetect, rssi: rssi)
        let timestamp = settings.contacts(database.contacts.count)
        os_log("Contact logged (count=%d,timestamp=%s)", log: log, type: .debug, database.contacts.count, timestamp.description)
        delegates.forEach { $0.transceiver(timestamp) }
    }
    
    func receiver(didUpdateState: CBManagerState) {
        os_log("Bluetooth state updated (state=%s)", log: log, type: .debug, didUpdateState.description)
        delegates.forEach { $0.transceiver(didUpdateState)}
    }
}

protocol ControllerDelegate {
    func transceiver(_ initialised: Transceiver)
    
    func transceiver(_ didUpdateState: CBManagerState)
    
    func transceiver(_ didDetectContactAt: Date)
}
