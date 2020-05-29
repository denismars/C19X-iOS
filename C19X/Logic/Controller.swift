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

/**
 Controller for encapsulating all application data and logic.
 */
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
     Synchronise device data with server data.
     */
    func synchronise()
    
    /**
     Set health status, locally and remotely.
     */
    func status(_ setTo: Status)
}

enum ControllerState: String {
    case foreground, background
}

class ConcreteController : Controller, ReceiverDelegate {
    private let log = OSLog(subsystem: "org.c19x.logic", category: "Controller")
    var delegates: [ControllerDelegate] = []

    let database: Database = ConcreteDatabase()
    private let network: Network = ConcreteNetwork(Settings.shared)
    let settings = Settings.shared
    var transceiver: Transceiver?
    
    init() {
        _ = settings.reset()
    }
    
    func foreground() {
        os_log("foreground", log: self.log, type: .debug)
        checkRegistration()
        initialiseTransceiver()
        synchronise()
        delegates.forEach{ $0.controller(.foreground) }
    }
    
    func background() {
        os_log("background", log: self.log, type: .debug)
        delegates.forEach{ $0.controller(.background) }
    }
    
    func synchronise() {
        os_log("synchronise", log: self.log, type: .debug)
        synchroniseStatus()
        synchroniseMessage()
        synchroniseTime()
        synchroniseSettings()
    }
    
    func status(_ setTo: Status) {
        let (from, _) = settings.status()
        os_log("Set status (from=%s,to=%s)", log: self.log, type: .debug, from.description, setTo.description)
        // Set status locally
        let _ = settings.status(setTo)
        // Set status remotely
        synchroniseStatus()
    }
    
    /**
     Register device if required.
     */
    private func checkRegistration() {
        os_log("Registration (state=%s)", log: self.log, type: .debug, settings.registrationState().rawValue)
        guard settings.registrationState() == .unregistered else {
            return
        }
        os_log("Registration required", log: self.log, type: .debug)
        settings.registrationState(.registering)
        network.getRegistration { serialNumber, sharedSecret, error in
            guard let serialNumber = serialNumber, let sharedSecret = sharedSecret, error == nil else {
                os_log("Registration failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                return
            }
            guard let success = self.settings.registration(serialNumber: serialNumber, sharedSecret: sharedSecret), success else {
                os_log("Registration failed (error=secureStorageFailed)", log: self.log, type: .fault)
                return
            }
            os_log("Registration successful (serialNumber=%s)", log: self.log, type: .debug, serialNumber.description)
            self.delegates.forEach { $0.registration(serialNumber)}
            
            // Tasks after registration
            self.initialiseTransceiver()
            self.synchroniseStatus()
            self.synchroniseMessage()
        }
    }
    
    /**
     Initialise transceiver.
     */
    private func initialiseTransceiver() {
        guard transceiver == nil else {
            return
        }
        os_log("Initialise transceiver", log: self.log, type: .debug)
        guard let (serialNumber, sharedSecret) = settings.registration() else {
            os_log("Initialise transceiver failed (error=unregistered)", log: self.log, type: .fault)
            return
        }
        transceiver = ConcreteTransceiver(sharedSecret, codeUpdateAfter: 120)
        transceiver?.append(self)
        os_log("Initialise transceiver successful (serialNumber=%s)", log: self.log, type: .debug, serialNumber.description)
        delegates.forEach { $0.transceiver(self.transceiver!) }
    }

    /**
     Synchronise time with server.
     */
    private func synchroniseTime() {
        os_log("Synchronise time", log: self.log, type: .debug)
        network.synchroniseTime() { _, error  in
            guard error == nil else {
                os_log("Synchronise time failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                return
            }
            os_log("Synchronise time successful", log: self.log, type: .debug)
        }
    }
    
    /**
     Synchronise settings with server.
     */
    private func synchroniseSettings() {
        os_log("Synchronise settings", log: self.log, type: .debug)
        network.getSettings() { serverSettings, error  in
            guard let serverSettings = serverSettings, error == nil else {
                os_log("Synchronise settings failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                return
            }
            self.settings.update(serverSettings)
            os_log("Synchronise settings successful", log: self.log, type: .debug)
            self.applySettings()
        }
    }
    
    /**
     Apply current settings now.
     */
    private func applySettings() {
        // Enforce retention period
        let removeBefore = Date().addingTimeInterval(-settings.retentionPeriod())
        database.remove(removeBefore)
        settings.contacts(database.contacts.count, lastUpdate: database.contacts.last?.time)
        delegates.forEach { $0.database(database.contacts) }
    }
    
    /**
     Synchronise status with server.
     */
    private func synchroniseStatus() {
        let (local,timestamp) = settings.status()
        guard timestamp != Date.distantPast else {
            // Only share authorised status data
            return
        }
        os_log("Synchronise status", log: self.log, type: .debug)
        guard let (serialNumber, sharedSecret) = settings.registration() else {
            os_log("Synchronise status failed (error=unregistered)", log: self.log, type: .fault)
            return
        }
        network.postStatus(local, serialNumber: serialNumber, sharedSecret: sharedSecret) { status, error in
            guard error == nil else {
                os_log("Synchronise status failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                return
            }
            guard let remote = status, remote == local else {
                os_log("Synchronise status failed (error=mismatch)", log: self.log, type: .fault)
                return
            }
            os_log("Synchronise status successful (remote=%s)", log: self.log, type: .debug, remote.description)
        }
    }
    
    /**
     Synchronise personal message with server.
     */
    private func synchroniseMessage() {
        os_log("Synchronise message", log: self.log, type: .debug)
        guard let (serialNumber, sharedSecret) = settings.registration() else {
            os_log("Synchronise message failed (error=unregistered)", log: self.log, type: .fault)
            return
        }
        network.getMessage(serialNumber: serialNumber, sharedSecret: sharedSecret) { message, error in
            guard let message = message, error == nil else {
                os_log("Synchronise message failed (error=%s)", log: self.log, type: .fault, String(describing: error))
                return
            }
            guard let _ = self.settings.message(message) else {
                os_log("Synchronise message failed (error=secureStorageFailed)", log: self.log, type: .fault)
                return
            }
            os_log("Synchronise message successful", log: self.log, type: .debug)
            self.delegates.forEach { $0.message(message) }
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
    func controller(_ didUpdateState: ControllerState)
    
    func registration(_ serialNumber: SerialNumber)
    
    func transceiver(_ initialised: Transceiver)
    
    func transceiver(_ didUpdateState: CBManagerState)
    
    func transceiver(_ didDetectContactAt: Date)
    
    func message(_ didUpdateTo: Message)
    
    func database(_ didUpdateContacts: [Contact])
}
