//
//  ViewController.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit
import os

class ViewController: UIViewController, BeaconListener, NetworkListener, RiskAnalysisListener {
    
    private let log = OSLog(subsystem: "org.C19X", category: "ViewController")
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
    private var device: Device!
    
    @IBOutlet weak var statusView: UIView!
    @IBOutlet weak var statusSelector: UISegmentedControl!
    @IBOutlet weak var statusDescription: UILabel!
    @IBOutlet weak var statusLastUpdate: UILabel!
    
    @IBOutlet weak var contactView: UIView!
    @IBOutlet weak var contactDescription: UILabel!
    @IBOutlet weak var contactLastUpdate: UILabel!
    @IBOutlet weak var contactTimeValue: UILabel!
    @IBOutlet weak var contactTimeUnit: UILabel!
    @IBOutlet weak var contactTimeBarchart: UIProgressView!
    
    @IBOutlet weak var adviceView: UIView!
    @IBOutlet weak var adviceDescription: UILabel!
    @IBOutlet weak var adviceDescriptionStatus: UIImageView!
    @IBOutlet weak var adviceMessage: UILabel!
    @IBOutlet weak var adviceLastUpdate: UILabel!
    
    private weak var refreshLastUpdateLabelsTimer: Timer!
    private var statusLastUpdateTimestamp: Date!
    private var adviceLastUpdateTimestamp: Date!
    
    override func viewDidLoad() {
        os_log("View did load", log: self.log, type: .debug)
        super.viewDidLoad()
        
        device = appDelegate.device
        
        device.beaconReceiver.listeners.append(self)
        device.beaconTransmitter.listeners.append(self)
        device.network.listeners.append(self)
        device.riskAnalysis.listeners.append(self)

        statusView.layer.cornerRadius = 10
        contactView.layer.cornerRadius = 10
        adviceView.layer.cornerRadius = 10

        let now = Date();
        statusLastUpdateTimestamp = now
        adviceLastUpdateTimestamp = now
        
        statusSelector.selectedSegmentIndex = device.getStatus()
        updateStatusDescriptionText()
        
        beaconListenerDidUpdate(beaconCode: 0, rssi: 0)
        contactDescription.numberOfLines = 0
        contactDescription.sizeToFit()

        refreshLastUpdateLabelsAndScheduleAgain()
    }
    
    @IBAction func statusSelectorValueChanged(_ sender: Any) {
        os_log("Status selector value changed (selectedSegmentIndex=%d)", log: self.log, type: .debug, statusSelector.selectedSegmentIndex)
        statusSelector.isEnabled = false
        if (device.isRegistered()) {
            updateStatusDescriptionText()
            device.network.postStatus(statusSelector.selectedSegmentIndex)
        } else {
            let alert = UIAlertController(title: "Device Not Registered", message: "Status update can not be shared at this time.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
            statusSelector.selectedSegmentIndex = self.device.getStatus()
            updateStatusDescriptionText()
            statusSelector.isEnabled = true
        }
    }
    
    private func updateStatusDescriptionText() {
        switch statusSelector.selectedSegmentIndex {
        case 0:
            statusDescription.text = "I do not have a high temperature or a new continuous cough"
            break
        case 1:
            statusDescription.text = "I have a high temperature and/or a new continuous cough"
            break
        case 2:
            statusDescription.text = "I have a confirmed diagnosis of Coronavirus (COVID-19)"
            break
        default:
            break
        }
        statusDescription.numberOfLines = 0
        statusDescription.sizeToFit()
    }
    
    private func updateLastUpdateLabels() {
        if let t = appDelegate.device.beaconReceiver.lastScanTimestamp {
            contactLastUpdate.text = "Updated " + t.elapsed()
        } else {
            contactLastUpdate.text = ""
        }
        
        statusLastUpdate.text = "Shared " + statusLastUpdateTimestamp.elapsed()
        adviceLastUpdate.text = "Updated " + adviceLastUpdateTimestamp.elapsed()
        os_log("Refresh last update labels (status=%s,contact=%s,advice=%s)", log: self.log, type: .debug, statusLastUpdate.text!, contactLastUpdate.text!, adviceLastUpdate.text!)
    }
    
    private func refreshLastUpdateLabelsAndScheduleAgain() {
        updateLastUpdateLabels()
        DispatchQueue.main.asyncAfter(deadline: .future(by: 120)) {
            self.refreshLastUpdateLabelsAndScheduleAgain()
        }
    }
    
    private func updateContactTime() {
        let (value, unit, time) = device.contactRecords.descriptionForToday()
        self.contactTimeValue.text = value
        self.contactTimeUnit.text = (unit + " today")
        self.contactLastUpdate.text = "Updated just now"
        
        var progress = Float(time) / Float(self.device.parameters.exposureDurationThreshold)
        if (progress > 1) {
            progress = 1
        }
        self.contactTimeBarchart.progress = progress
        if (self.device.riskAnalysis.contact == RiskAnalysis.contactInfectious) {
            self.contactTimeBarchart.tintColor = .systemRed
        } else if (time < self.device.parameters.exposureDurationThreshold) {
            self.contactTimeBarchart.tintColor = .systemGreen
        } else {
            self.contactTimeBarchart.tintColor = .systemOrange
        }
        os_log("Update contact time labels (value=%s,unit=%s)", log: self.log, type: .debug, value, unit)
    }
    
    private func updateContactDescription() {
        if (self.device.riskAnalysis.contact == RiskAnalysis.contactOk) {
            self.contactDescription.text = "No report of COVID-19 symptoms or diagnosis has been shared in the last " + String(self.device.parameters.retentionPeriod) + " days."
        } else {
            let exposure = (self.device.riskAnalysis.exposureTime > self.device.parameters.exposureDurationThreshold ? "more" : "less")
            let (value,unit) = UInt64(self.device.parameters.exposureDurationThreshold).duration()
            self.contactDescription.text = "Report of COVID-19 symptoms or diagnosis has been shared in the last " + String(self.device.parameters.retentionPeriod) + " days. You may have been exposed for " + exposure + " than " + String(value) + " " + unit + "."
        }
    }

    private func updateAdviceDescription() {
        switch self.device.riskAnalysis.advice {
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
    
    internal func beaconListenerDidUpdate(didStartScan: Date) {
        DispatchQueue.main.async {
            self.updateContactTime()
        }
    }

    internal func beaconListenerDidUpdate(beaconCode: Int64, rssi: Int) {
        DispatchQueue.main.async {
            self.updateContactTime()
        }
    }

    func networkListenerDidUpdate(serialNumber: UInt64, sharedSecret: Data) {
    }
    
    internal func networkListenerDidUpdate(status: Int) {
        debugPrint("Network (status=\(status))")
        statusLastUpdateTimestamp = Date()
        DispatchQueue.main.async {
            if (self.statusSelector != nil) {
                self.statusSelector.selectedSegmentIndex = status
                self.updateStatusDescriptionText()
                self.statusSelector.isEnabled = true
            }
            self.statusLastUpdate.text = "Shared " + self.statusLastUpdateTimestamp.elapsed()
        }
    }

    internal func networkListenerFailedUpdate(statusError: Error?) {
        debugPrint("Network failure (statusError=\(String(describing: statusError))")
        DispatchQueue.main.async {
            // Present alert
            let alert = UIAlertController(title: "Server Not Available", message: "Status update can not be shared at this time.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)

            if (self.statusSelector != nil) {
                self.statusSelector.selectedSegmentIndex = self.device.getStatus()
                self.updateStatusDescriptionText()
                self.statusSelector.isEnabled = true
            }
            self.statusLastUpdate.text = "Shared " + self.statusLastUpdateTimestamp.elapsed()
        }
    }

    internal func networkListenerDidUpdate(message: String) {
        DispatchQueue.main.async {
            self.adviceMessage.text = message
        }
    }
    
    internal func networkListenerDidUpdate(parameters: Parameters) {
    }
    
    func networkListenerDidUpdate(lookup: Data) {
    }
    
    func networkListenerFailedUpdate(registrationError: Error?) {
    }

    internal func riskAnalysisDidUpdate(contact: Int, advice: Int, contactTime: UInt64, exposureTime: UInt64) {
        DispatchQueue.main.async {
            self.updateContactDescription()
            self.updateContactTime()
            self.updateAdviceDescription()
        }
    }

}

