//
//  ViewController.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit
import CoreBluetooth
import os

class ViewController: UIViewController, ControllerDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "ViewController")
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
    private var controller: Controller!
    
    @IBOutlet weak var statusView: UIView!
    @IBOutlet weak var statusSelector: UISegmentedControl!
    @IBOutlet weak var statusDescription: UILabel!
    @IBOutlet weak var statusLastUpdate: UILabel!
    
    @IBOutlet weak var contactView: UIView!
    @IBOutlet weak var contactDescription: UILabel!
    @IBOutlet weak var contactDescriptionStatus: UIImageView!
    @IBOutlet weak var contactLastUpdate: UILabel!
    @IBOutlet weak var contactValue: UILabel!
    @IBOutlet weak var contactValueUnit: UILabel!
    
    @IBOutlet weak var adviceView: UIView!
    @IBOutlet weak var adviceDescription: UILabel!
    @IBOutlet weak var adviceDescriptionStatus: UIImageView!
    @IBOutlet weak var adviceMessage: UILabel!
    @IBOutlet weak var adviceLastUpdate: UILabel!
    
    private weak var refreshLastUpdateLabelsTimer: Timer!
    
    override func viewDidLoad() {
        os_log("View did load", log: self.log, type: .debug)
        super.viewDidLoad()
        controller = appDelegate.controller
        controller.delegates.append(self)
        
        // UI tweaks
        statusView.layer.cornerRadius = 10
        contactView.layer.cornerRadius = 10
        adviceView.layer.cornerRadius = 10

        contactDescription.numberOfLines = 0
        contactDescription.sizeToFit()
        
        adviceDescription.numberOfLines = 0
        adviceDescription.sizeToFit()
        
        adviceMessage.numberOfLines = 0
        adviceMessage.sizeToFit()
        
        enableImmediateUpdate()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        os_log("View did appear", log: self.log, type: .debug)
        super.viewDidAppear(animated)
        updateViewData(status: true, contacts: true, advice: true)
    }

    private func updateViewData(status: Bool = false, contacts: Bool = false, advice: Bool = false) {
        os_log("updateViewData (status=%s,contacts=%s,advice=%s)", log: self.log, type: .debug, status.description, contacts.description, advice.description)
        if (status) {
            DispatchQueue.main.async {
                let (value, timestamp, _) = self.controller.settings.status()
                self.statusSelector.selectedSegmentIndex = value.rawValue
                self.statusDescription(value)
                self.statusLastUpdate.text = (timestamp == Date.distantPast ? "" : timestamp.description)
            }
        }
        if (contacts) {
            DispatchQueue.main.async {
                let (value, status, timestamp) = self.controller.settings.contacts()
                self.contactValue.text = String(value)
                self.contactValueUnit.text = (value < 2 ? "contact" : "contacts") + " tracked"
                self.contactDescription(status)
                self.contactLastUpdate.text = (timestamp == Date.distantPast ? "" : timestamp.description)
            }
        }
        if (advice) {
            DispatchQueue.main.async {
                let (_, value, adviceTimestamp) = self.controller.settings.advice()
                let (message, messageTimestamp) = self.controller.settings.message()
                let timestamp = (adviceTimestamp > messageTimestamp ? adviceTimestamp : messageTimestamp)
                self.adviceDescription(value)
                self.adviceLastUpdate.text = (timestamp == Date.distantPast ? "" : timestamp.description)
                self.adviceMessage.text = message
            }
        }
    }
    
    @IBAction func statusSelectorValueChanged(_ sender: Any) {
        guard let status = Status(rawValue: statusSelector.selectedSegmentIndex) else {
            os_log("Status selector changed to invalid value (index=%d)", log: self.log, type: .fault, statusSelector.selectedSegmentIndex)
            return
        }
        statusDescription(status)
        os_log("Status selector value changed (status=%s)", log: self.log, type: .debug, status.description)
        let dialog = UIAlertController(title: "Share Infection Data", message: "Share your infection status and contact pattern anonymously to help stop the spread of COVID-19?", preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: "Don't Allow", style: .default) { _ in
            // Revert to stored value
            self.updateViewData(status: true)
        })
        dialog.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
            // Set status locally and remotely
            self.controller.status(status)
            self.updateViewData(status: true)
        })
        present(dialog, animated: true)
    }
    
    // MARK:- Set text descriptions
    
    private func statusDescription(_ setTo: Status) {
        switch setTo {
        case .healthy:
            statusDescription.text = "I do not have a high temperature or a new continuous cough."
            break
        case .symptomatic:
            statusDescription.text = "I have a high temperature and/or a new continuous cough."
            break
        case .confirmedDiagnosis:
            statusDescription.text = "I have a confirmed diagnosis of Coronavirus (COVID-19)."
            break
        default:
            break
        }
        statusDescription.numberOfLines = 0
        statusDescription.sizeToFit()
    }
    
    private func contactDescription(_ setTo: Status) {
        switch setTo {
        case .healthy:
            contactDescription.text = "No report of COVID-19 symptoms or diagnosis has been shared."
            contactDescriptionStatus.backgroundColor = .systemGreen
            break
        default:
            contactDescription.text = "Report of COVID-19 symptoms or diagnosis has been shared."
            contactDescriptionStatus.backgroundColor = .systemRed
            break
        }
    }

    private func adviceDescription(_ setTo: Advice) {
        switch setTo {
        case .normal:
            self.adviceDescription.text = "No restriction. COVID-19 is now under control, you can safely return to your normal activities."
            self.adviceDescriptionStatus.backgroundColor = .systemGreen
            break
        case .stayAtHome:
            self.adviceDescription.text = "Stay at home. Everyone must stay at home to help stop the spread of COVID-19."
            self.adviceDescriptionStatus.backgroundColor = .systemOrange
            break
        case .selfIsolation:
            self.adviceDescription.text = "Self-isolation. Do not leave your home if you have symptoms or confirmed diagnosis of COVID-19 or been in prolonged close contact with someone who does."
            self.adviceDescriptionStatus.backgroundColor = .systemRed
            break
        }
    }
    
    private func notification(title: String, body: String, backgroundOnly: Bool = false) {
        DispatchQueue.main.async {
            if backgroundOnly && UIApplication.shared.applicationState != .background {
                os_log("notification denied, application active (backgroundOnly=true)", log: self.log, type: .debug)
                return
            }
            if UIApplication.shared.applicationState != .background {
                os_log("notification (method=foreground,title=%s,body=%s)", log: self.log, type: .debug, title, body)
                let dialog = UIAlertController(title: title, message: body, preferredStyle: .alert)
                dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(dialog, animated: true)
            } else {
                // Request authorisation for notification
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert]) { granted, error in
                    if let error = error {
                        os_log("notification denied, authorisation failed (error=%s)", log: self.log, type: .fault, error.localizedDescription)
                    } else if granted {
                        // Raise notification
                        os_log("notification (method=background,title=%s,body=%s)", log: self.log, type: .debug, title, body)
                        let identifier = "org.C19X.notification"
                        let content = UNMutableNotificationContent()
                        content.title = title
                        content.body = body
                        content.sound = UNNotificationSound.default
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                        center.removePendingNotificationRequests(withIdentifiers: [identifier])
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request)
                    } else {
                        os_log("notification denied, authorisation denied", log: self.log, type: .fault)
                    }
                }
            }
        }
    }
    
    // MARK:- ControllerDelegate
    
    func controller(_ didUpdateState: ControllerState) {
        os_log("controller did update state (state=%s)", log: self.log, type: .debug, didUpdateState.rawValue)
        updateViewData(status: true, contacts: true, advice: true)
    }
    
    func registration(_ serialNumber: SerialNumber) {
        os_log("registration (serialNumber=%s)", log: self.log, type: .debug, serialNumber.description)
    }
    
    func transceiver(_ initialised: Transceiver) {
        os_log("transceiver initialised", log: self.log, type: .debug)
        updateViewData(contacts: true)
    }
    
    func transceiver(_ didDetectContactAt: Date) {
        os_log("transceiver did detect contact (timestamp=%s)", log: self.log, type: .debug, didDetectContactAt.description)
        updateViewData(contacts: true)
    }
    
    func transceiver(_ didUpdateState: CBManagerState) {
        os_log("transceiver did update state (state=%s)", log: self.log, type: .debug, didUpdateState.description)
        switch didUpdateState {
        case .poweredOn:
//            notification(title: "Contact Tracing Enabled", body: "Turn OFF Bluetooth to pause.", backgroundOnly: true)
            break
        case .poweredOff:
            notification(title: "Contact Tracing Disabled", body: "Turn ON Bluetooth to resume.")
            break
        case .unauthorized:
            notification(title: "Contact Tracing Disabled", body: "Allow Bluetooth access in Settings > C19X to enable.")
            break
        case .unsupported:
            notification(title: "Contact Tracing Disabled", body: "Bluetooth unavailable, restart device to enable.")
            break
        default:
            notification(title: "Contact Tracing Disabled", body: "Bluetooth unavailable, restart device to enable.")
            break
        }
    }
    
    func message(_ didUpdateTo: Message) {
        os_log("Message did update", log: self.log, type: .debug)
        updateViewData(advice: true)
    }
    
    func database(_ didUpdateContacts: [Contact]) {
        os_log("Database did update", log: self.log, type: .debug)
        updateViewData(contacts: true)
    }
    
    func advice(_ didUpdateTo: Advice, _ contactStatus: Status) {
        os_log("Advice did update", log: self.log, type: .debug)
        updateViewData(contacts: true, advice: true)
    }

    // MARK:- Enable immediate update by double tapping on advice view
    
    @objc func immediateUpdate(_ sender: UITapGestureRecognizer) {
        os_log("Immediate update requested", log: self.log, type: .debug)
        controller.synchronise(true)
    }

    private func enableImmediateUpdate() {
        let doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.immediateUpdate(_:)))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        self.adviceView.isUserInteractionEnabled = true
        self.adviceView.addGestureRecognizer(doubleTapGestureRecognizer)
    }
    

}
