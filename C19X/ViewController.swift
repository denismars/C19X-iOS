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

class ViewController: UIViewController, BeaconListener, NetworkListener, RiskAnalysisListener, ReceiverDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "ViewController")
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
    private var device: Device!
    private var c19x: C19X!
    
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
        device = appDelegate.device
        c19x = appDelegate.c19x
        
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

        // Status
        statusSelector.selectedSegmentIndex = device.getStatus()
        statusSelector.isEnabled = false
        updateStatusDescriptionText()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        os_log("View did appear", log: self.log, type: .debug)
        super.viewDidAppear(animated)
        checkFirstUse()
    }
    
    private func checkFirstUse() {
        if (device.parameters.isFirstUse()) {
            self.device.parameters.set(isFirstUse: false)
        }
        self.start()
//      CHANGED METHOD TO ASK PERMISSION ON EVERY UPDATE
//        if (device.parameters.isFirstUse()) {
//            os_log("User confirmation required for first use", log: self.log, type: .debug)
//            // Present data sharing dialog on first use
//            let dialog = UIAlertController(title: "Share Infection Status", message: "This app will share your infection status anonymously to help stop the spread of COVID-19.", preferredStyle: .alert)
//            dialog.addAction(UIAlertAction(title: "Don't Allow", style: .default) { _ in
//                self.device.parameters.set(isFirstUse: true)
//                self.device.reset()
//                let alert = UIAlertController(title: "Closing App", message: "This app cannot work without sharing your infection status.", preferredStyle: .alert)
//                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
//                    exit(0)
//                })
//                self.present(alert, animated: true)
//            })
//            dialog.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
//                self.device.parameters.set(isFirstUse: false)
//                self.start()
//            })
//            self.present(dialog, animated: true)
//        } else {
//            self.start()
//        }
    }
    
    private func start() {
        c19x.transmitter.delegates.append(self)
        c19x.receiver.delegates.append(self)
        //transmitter.delegates.append(database)
        //receiver.delegates.append(transmitter as! ConcreteTransmitter)
        //receiver.delegates.append(database)
        
        //enableImmediateLookupUpdate()

        device.network.listeners.append(self)
        device.beaconReceiver.listeners.append(self)
        device.beaconTransmitter.listeners.append(self)
        device.riskAnalysis.listeners.append(self)
        //device.start()

        //refreshLastUpdateLabelsAndScheduleAgain()
        
        statusSelector.selectedSegmentIndex = device.getStatus()
        updateStatusDescriptionText()
        device.riskAnalysis.update(status: statusSelector.selectedSegmentIndex, contactRecords: device.contactRecords, parameters: device.parameters, lookup: device.lookup)
        statusSelector.isEnabled = true

    }
    
    func receiver(didDetect: BeaconCode, rssi: RSSI) {
        DispatchQueue.main.async {
            if let contacts = self.device.parameters.getCounterContacts() {
                self.device.parameters.set(contacts: contacts + 1)
                self.contactValue.text = (contacts + 1).description
            } else {
                self.device.parameters.set(contacts: 1)
                self.contactValue.text = "1"
            }
            self.contactLastUpdate.text = Date().description
        }
    }
    
    private func requestAuthorisationForNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                os_log("Request notification authorisation failed (error=%s)", log: self.log, type: .fault, error.localizedDescription)
            }
            self.device.parameters.set(notification: granted)
        }
    }
    
    @IBAction func statusSelectorValueChanged(_ sender: Any) {
        os_log("Status selector value changed (selectedSegmentIndex=%d)", log: self.log, type: .debug, statusSelector.selectedSegmentIndex)
        if (device.isRegistered()) {
            updateStatusDescriptionText()
            device.riskAnalysis.update(status: statusSelector.selectedSegmentIndex, contactRecords: device.contactRecords, parameters: device.parameters, lookup: device.lookup)
            let dialog = UIAlertController(title: "Share Infection Data", message: "Share your infection status and contact pattern anonymously to help stop the spread of COVID-19?", preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: "Don't Allow", style: .default, handler: nil))
            dialog.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                if let statusSelector = self.statusSelector, let device = self.device {
                    device.network.postStatus(statusSelector.selectedSegmentIndex, device: device)
                }
            })
            present(dialog, animated: true)
        } else {
            let alert = UIAlertController(title: "Device Not Registered", message: "Status update can not be shared at this time.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
            statusSelector.selectedSegmentIndex = self.device.getStatus()
            updateStatusDescriptionText()
            device.riskAnalysis.update(status: statusSelector.selectedSegmentIndex, contactRecords: device.contactRecords, parameters: device.parameters, lookup: device.lookup)
        }
    }
    
    private func updateStatusDescriptionText() {
        switch statusSelector.selectedSegmentIndex {
        case 0:
            statusDescription.text = "I do not have a high temperature or a new continuous cough."
            break
        case 1:
            statusDescription.text = "I have a high temperature and/or a new continuous cough."
            break
        case 2:
            statusDescription.text = "I have a confirmed diagnosis of Coronavirus (COVID-19)."
            break
        default:
            break
        }
        statusDescription.numberOfLines = 0
        statusDescription.sizeToFit()
    }
    
    private func updateLastUpdateLabels() {
        if let t = device.parameters.getStatusUpdateTimestamp() {
            statusLastUpdate.text = "Shared " + t.elapsed()
        }
        if let t = device.parameters.getContactUpdateTimestamp() {
            contactLastUpdate.text = "Updated " + t.elapsed()
        }
        if let t = device.parameters.getAdviceUpdateTimestamp() {
            adviceLastUpdate.text = "Updated " + t.elapsed()
        }
        os_log("Refresh last update labels (status=%s,contact=%s,advice=%s)", log: self.log, type: .debug, statusLastUpdate.text!, contactLastUpdate.text!, adviceLastUpdate.text!)
    }
    
    private func refreshLastUpdateLabelsAndScheduleAgain() {
        updateLastUpdateLabels()
        DispatchQueue.main.asyncAfter(deadline: .future(by: 120)) {
            self.refreshLastUpdateLabelsAndScheduleAgain()
        }
    }
    
    private func updateContactDescription(_ contact:Int) {
        if (contact == RiskAnalysis.contactOk) {
            self.contactDescription.text = "No report of COVID-19 symptoms or diagnosis has been shared in the last " + String(self.device.parameters.getRetentionPeriodInDays()) + " days."
            self.contactDescriptionStatus.backgroundColor = .systemGreen
        } else {
            self.contactDescription.text = "Report of COVID-19 symptoms or diagnosis has been shared in the last " + String(self.device.parameters.getRetentionPeriodInDays()) + " days."
            self.contactDescriptionStatus.backgroundColor = .systemRed
        }
    }

    private func updateContactValue(_ value:Int) {
        self.contactValue.text = String(value)
        self.contactValue.textColor = UIColor.label
        self.contactValueUnit.text = (value < 2 ? "contact" : "contacts") + " tracked"
    }

    private func updateAdviceDescription(_ advice:Int) {
        switch advice {
        case RiskAnalysis.adviceFreedom:
            self.adviceDescription.text = "No restriction. COVID-19 is now under control, you can safely return to your normal activities."
            self.adviceDescriptionStatus.backgroundColor = .systemGreen
            break
        case RiskAnalysis.adviceStayAtHome:
            self.adviceDescription.text = "Stay at home. Everyone must stay at home to help stop the spread of COVID-19."
            self.adviceDescriptionStatus.backgroundColor = .systemOrange
            break
        case RiskAnalysis.adviceSelfIsolate:
            self.adviceDescription.text = "Self-isolation. Do not leave your home if you have symptoms or confirmed diagnosis of COVID-19 or been in prolonged close contact with someone who does."
            self.adviceDescriptionStatus.backgroundColor = .systemRed
            break
        default:
            break
        }
    }

    internal func beaconListenerDidUpdate(beaconCode: UInt64, rssi: Int) {
        device.parameters.set(contactUpdate: Date())
        DispatchQueue.main.async {
            self.updateContactValue(self.device.contactRecords.records.count)
            self.updateLastUpdateLabels()
        }
    }

    internal func beaconListenerDidUpdate(central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            os_log("Bluetooth state changed (state=poweredOn)", log: self.log, type: .debug)
            requestAuthorisationForNotification()
            DispatchQueue.main.async {
                self.updateContactValue(self.device.contactRecords.records.count)
            }
            break
        case .poweredOff:
            os_log("Bluetooth state changed (state=poweredOff)", log: self.log, type: .debug)
            let dialog = UIAlertController(title: "Contact Tracing Disabled", message: "Turn on Bluetooth to resume.", preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(dialog, animated: true)
            if UIApplication.shared.applicationState != .active {
                raiseNotification(title: "Contact Tracing Disabled", body: "Turn on Bluetooth to resume.")
            }
            break
        case .unauthorized:
            os_log("Bluetooth state changed (state=unauthorised)", log: self.log, type: .debug)
            let dialog = UIAlertController(title: "Contact Tracing Disabled", message: "Allow Bluetooth access in Settings > C19X to enable.", preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(dialog, animated: true)
            if UIApplication.shared.applicationState != .active {
                raiseNotification(title: "Contact Tracing Disabled", body: "Allow Bluetooth access in Settings > C19X to enable.")
            }
            break
        case .unsupported:
            os_log("Bluetooth state changed (state=unsupported)", log: self.log, type: .debug)
            let dialog = UIAlertController(title: "Contact Tracing Disabled", message: "Bluetooth unavailable, restart device to enable.", preferredStyle: .alert)
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(dialog, animated: true)
            if UIApplication.shared.applicationState != .active {
                raiseNotification(title: "Contact Tracing Disabled", body: "Bluetooth unavailable, restart device to enable.")
            }
            break
        default:
            os_log("Bluetooth state changed (state=unknown)", log: self.log, type: .debug)
            break
        }
    }
    
    internal func beaconListenerDidUpdate(peripheral: CBPeripheralManager) {
    }

    internal func networkListenerDidUpdate(serialNumber: UInt64, sharedSecret: Data) {
    }
    
    internal func networkListenerDidUpdate(status: Int) {
        debugPrint("Network (status=\(status))")
        device.parameters.set(statusUpdate: Date())
        DispatchQueue.main.async {
            if (self.statusSelector != nil) {
                self.statusSelector.selectedSegmentIndex = status
                self.updateStatusDescriptionText()
            }
            self.updateLastUpdateLabels()
        }
    }

    internal func networkListenerFailedUpdate(statusError: Error?) {
        debugPrint("Network failure (statusError=\(String(describing: statusError))")
        DispatchQueue.main.async {
            self.updateLastUpdateLabels()
            // Present alert
            let alert = UIAlertController(title: "Server Not Available", message: "Status update can not be shared at this time.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
            
            if let statusSelector = self.statusSelector, let device = self.device {
                statusSelector.selectedSegmentIndex = device.getStatus()
                device.riskAnalysis.update(status: statusSelector.selectedSegmentIndex, contactRecords: device.contactRecords, parameters: device.parameters, lookup: device.lookup)
            }
        }
    }

    internal func networkListenerDidUpdate(message: String) {
        DispatchQueue.main.async {
            if (self.adviceMessage.text != message) {
                self.adviceMessage.text = message
                self.raiseNotification(title: "Information Update", body: "You have a new message.")
            }
        }
    }
    
    internal func networkListenerDidUpdate(parameters: [String:String]) {
    }
    
    internal func networkListenerDidUpdate(lookup: Data) {
    }
    
    internal func networkListenerFailedUpdate(registrationError: Error?) {
    }

    internal func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int) {
        device.parameters.set(adviceUpdate: Date())
        DispatchQueue.main.async {
            self.updateContactValue(contactCount)
            self.updateContactDescription(currentContactStatus)
            self.updateAdviceDescription(currentAdvice)
            if (currentAdvice != previousAdvice) {
                self.raiseNotification(title: "Information Update", body: "You have received new advice.")
            }
        }
    }

    @objc func adviceUpdateLabelTapped(_ sender: UITapGestureRecognizer) {
        os_log("Lookup update immediately requested", log: self.log, type: .debug)
        self.device.network.getLookupImmediately() { _ in
            os_log("Lookup update immediately completed", log: self.log, type: .debug)
        }
    }
    
    private func enableImmediateLookupUpdate() {
        let labelTap = UITapGestureRecognizer(target: self, action: #selector(self.adviceUpdateLabelTapped(_:)))
        self.adviceLastUpdate.isUserInteractionEnabled = true
        self.adviceLastUpdate.addGestureRecognizer(labelTap)
    }
    
    private func raiseNotification(title: String, body: String) {
        let identifier = "org.C19X.notification"
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard (settings.authorizationStatus == .authorized) ||
                  (settings.authorizationStatus == .provisional) else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = UNNotificationSound.default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

            if settings.alertSetting == .enabled {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(request)
            }
        }
    }

}

class TransmitterTrigger : ReceiverDelegate {
    private var transmitter: Transmitter
    private var scheduled = false
    
    init(_ transmitter: Transmitter) {
        self.transmitter = transmitter
    }
    
    func receiver(didDetect: BeaconCode, rssi: RSSI) {
        if !scheduled {
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(5))) {
                self.transmitter.updateBeaconCode()
                self.scheduled = false
            }
        }
    }
    
    
}
