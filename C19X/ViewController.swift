//
//  ViewController.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit
import os

class ViewController: UIViewController, BeaconListener, NetworkListener {
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
    
    private weak var refreshLastUpdateLabelsTimer: Timer!
    private var statusLastUpdateTimestamp: Date!
    private var contactLastUpdateTimestamp: Date!
    
    override func viewDidLoad() {
        os_log("View did load", log: self.log, type: .debug)
        super.viewDidLoad()
        
        device = appDelegate.device
        
        device.beacon.listeners.append(self)
        device.network.listeners.append(self)

        statusView.layer.cornerRadius = 10
        contactView.layer.cornerRadius = 10

        let now = Date();
        statusLastUpdateTimestamp = now
        contactLastUpdateTimestamp = now
        
        statusSelector.selectedSegmentIndex = device.getStatus()
        updateStatusDescriptionText()
        
        beaconListenerDidUpdate(beaconCode: 0, rssi: 0)
        contactDescription.numberOfLines = 0
        contactDescription.sizeToFit()

        refreshLastUpdateLabelsAndScheduleAgain()
        refreshContactTimeAndScheduleAgain()
    }
    
    @IBAction func statusSelectorValueChanged(_ sender: Any) {
        os_log("Status selector value changed (selectedSegmentIndex=%d)", log: self.log, type: .debug, statusSelector.selectedSegmentIndex)
        statusSelector.isEnabled = false
        updateStatusDescriptionText()
        device.network.postStatus(statusSelector.selectedSegmentIndex)
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
        statusLastUpdate.text = "Shared " + statusLastUpdateTimestamp.elapsed()
        contactLastUpdate.text = "Updated " + contactLastUpdateTimestamp.elapsed()
        os_log("Refresh last update labels (status=%s,contact=%s)", log: self.log, type: .debug, statusLastUpdate.text!, contactLastUpdate.text!)
    }
    
    private func refreshLastUpdateLabelsAndScheduleAgain() {
        updateLastUpdateLabels()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(120))) {
            self.refreshLastUpdateLabelsAndScheduleAgain()
        }
    }
    
    private func updateContactTime() {
        let (value, unit, time) = device.contactRecords.descriptionForToday()
        self.contactTimeValue.text = value
        self.contactTimeUnit.text = unit
        self.contactLastUpdate.text = "Updated " + self.contactLastUpdateTimestamp.elapsed()
        
        var progress = Float(time) / Float(self.device.parameters.exposureDurationThreshold)
        if (progress > 1) {
            progress = 1
        }
        self.contactTimeBarchart.progress = progress
        if (self.device.riskAnalysis.contact == RiskAnalysis.contactInfectious) {
            self.contactTimeBarchart.tintColor = UIColor.systemRed
        } else if (time < self.device.parameters.exposureDurationThreshold) {
            self.contactTimeBarchart.tintColor = UIColor.systemGreen
        } else {
            self.contactTimeBarchart.tintColor = UIColor.systemOrange
        }
        os_log("Update contact time labels (value=%s,unit=%s)", log: self.log, type: .debug, value, unit)
    }
    
    private func refreshContactTimeAndScheduleAgain() {
        updateContactTime()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .seconds(120))) {
            self.refreshContactTimeAndScheduleAgain()
        }
    }
    
    internal func beaconListenerDidUpdate(beaconCode: Int64, rssi: Int) {
        contactLastUpdateTimestamp = Date()
        updateContactTime()
    }

    func networkListenerDidUpdate(serialNumber: UInt64, sharedSecret: Data) {
    }
    
    func networkListenerDidUpdate(status: Int) {
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

    func networkListenerFailedUpdate(statusError: Error?) {
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

    func networkListenerDidUpdate(message: String) {
    }
    
    func networkListenerDidUpdate(parameters: Parameters) {
    }
    
    func networkListenerDidUpdate(lookup: Data) {
    }
    
    func networkListenerFailedUpdate(registrationError: Error?) {
    }

}

