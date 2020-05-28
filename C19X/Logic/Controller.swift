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
    
    /**
     Notify controller that app has entered foreground mode.
     */
    func foreground()
    
    /**
     Notify controller that app has entered background mode.
     */
    func background()
    
    /**
     Set health status, locally and remotely
     */
    func status(_ setTo: Status)
}


class ConcreteController : Controller, ReceiverDelegate {
    private let log = OSLog(subsystem: "org.c19x.logic", category: "Controller")
    var delegates: [ControllerDelegate] = []

    private let database: Database = ConcreteDatabase()
    private let network: Network = ConcreteNetwork(Settings.shared)
    let settings = Settings.shared
    var transceiver: Transceiver?
    
    init() {
        _ = settings.reset()
    }
    
    func foreground() {
        os_log("foreground", log: self.log, type: .debug)
        network.synchroniseTime()
        synchroniseStatus()
        initialiseTransceiver()
    }
    
    func background() {
        os_log("background", log: self.log, type: .debug)
    }
    
    func status(_ setTo: Status) {
        let (from, _) = settings.status()
        os_log("Set status (from=%s,to=%s)", log: self.log, type: .debug, from.description, setTo.description)
        // Set status locally
        let _ = settings.status(setTo)
        // Set status remotely
        checkRegistration(then: { serialNumber, sharedSecret in
            guard let serialNumber = serialNumber, let sharedSecret = sharedSecret else {
                os_log("Set status remotely failed, not registered", log: self.log, type: .fault)
                self.delegates.forEach { $0.status(nil, from: from, error: NetworkError.unregistered) }
                return
            }
            self.network.postStatus(setTo, serialNumber: serialNumber, sharedSecret: sharedSecret) { status, error in
                if let status = status, error == nil {
                    os_log("Set status remotely successful (from=%s,to=%s,remote=%s)", log: self.log, type: .debug, from.description, setTo.description, status.description)
                } else {
                    os_log("Set status remotely failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                }
                self.delegates.forEach { $0.status(status, from: from, error: error) }
            }
        })
    }
    
    /**
     Post current status to server to ensure the device and server are synchronised, and resume any failed submissions following app termination.
     */
    private func synchroniseStatus() {
        let (from,timestamp) = settings.status()
        guard timestamp != Date.distantPast else {
            // Status was not previously shared
            return
        }
        os_log("Synchronise status", log: self.log, type: .debug)
        checkRegistration(then: { serialNumber, sharedSecret in
            guard let serialNumber = serialNumber, let sharedSecret = sharedSecret else {
                os_log("Synchronise status failed, not registered", log: self.log, type: .fault)
                self.delegates.forEach { $0.status(nil, from: from, error: NetworkError.unregistered) }
                return
            }
            self.network.postStatus(from, serialNumber: serialNumber, sharedSecret: sharedSecret) { status, error in
                if error == nil {
                    os_log("Synchronise status successful", log: self.log, type: .debug)
                } else {
                    os_log("Synchronise status failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                }
                self.delegates.forEach { $0.status(status, from: from, error: error) }
            }
        })
    }
    
    private func initialiseTransceiver() {
        guard transceiver == nil else {
            // Already initialised
            return
        }
        os_log("Initialise transceiver", log: self.log, type: .debug)
        checkRegistration(then: { serialNumber, sharedSecret in
            guard let serialNumber = serialNumber, let sharedSecret = sharedSecret else {
                os_log("Initialise transceiver failed, not registered", log: self.log, type: .fault)
                return
            }
            self.transceiver = ConcreteTransceiver(sharedSecret, codeUpdateAfter: 120)
            self.transceiver?.append(self)
            os_log("Initialise transceiver successful (serialNumber=%s)", log: self.log, type: .debug, serialNumber.description)
            self.delegates.forEach { $0.transceiver(self.transceiver!) }
        })
    }
    
    /**
     Check registration then execute callback.
     */
    private func checkRegistration(then: @escaping (SerialNumber?, SharedSecret?) -> Void) {
        if let (serialNumber, sharedSecret) = settings.registration() {
            then(serialNumber, sharedSecret)
            return
        }
        os_log("Registration required", log: self.log, type: .debug)
        network.getRegistration { serialNumber, sharedSecret, error in
            guard let serialNumber = serialNumber, let sharedSecret = sharedSecret, error == nil else {
                os_log("Registration failed to get shared secret (error=%s)", log: self.log, type: .fault, String(describing: error))
                then(nil, nil)
                return
            }
            guard let success = self.settings.registration(serialNumber: serialNumber, sharedSecret: sharedSecret), success else {
                os_log("Registration failed to write to secure storage", log: self.log, type: .fault)
                then(nil, nil)
                return
            }
            os_log("Registration success (serialNumber=%s)", log: self.log, type: .debug, serialNumber.description)
            then(serialNumber, sharedSecret)
        }
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
    
    func status(_ didUpdateTo: Status?, from: Status, error: Error?)
}
