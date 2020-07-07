//
//  Notification.swift
//  C19X
//
//  Created by Freddy Choi on 06/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import UIKit
import NotificationCenter
import os

/**
 Notifications and screen on trigger while device is locked.
 */
protocol Notification {
    /**
     Show notification immediately if in background.
     */
    func show(_ title: String, _ body: String)
    
    /**
     Remove all notifications on app termination.
     */
    func removeAll()
    
    /**
     Enable or disable screen on trigger when the device is locked
     */
    func screenOnTrigger(_ enabled: Bool)
}

class ConcreteNotification: NSObject, Notification, UNUserNotificationCenterDelegate {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "Notification")
    private let onDemandNotificationIdentifier = "C19X.onDemandNotificationIdentifier"
    private let onDemandNotificationDelay = TimeInterval(2)
    private let repeatingNotificationIdentifier = "C19X.repeatingNotificationIdentifier"
    private let repeatingNotificationDelay = TimeInterval(3 * 60)
    private var deviceIsLocked: Bool = false
    private var screenOnTriggerActive: Bool = false
    
    override init() {
        super.init()
        requestAuthorisation()
        
        // Register for device lock and unlock events
        NotificationCenter.default.addObserver(self, selector: #selector(self.onDeviceLock(_:)), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onDeviceUnlock(_:)), name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    }
    
    func show(_ title: String, _ body: String) {
        removeAllNotifications([repeatingNotificationIdentifier])
        if deviceIsLocked {
            scheduleNotification(onDemandNotificationIdentifier, title, body, delay: repeatingNotificationDelay, repeats: true)
        } else {
            scheduleNotification(onDemandNotificationIdentifier, title, body, delay: onDemandNotificationDelay, repeats: false)
        }
    }
    
    func removeAll() {
        removeAllNotifications(nil)
    }
    
    func screenOnTrigger(_ enabled: Bool) {
        os_log("screenOnTrigger (enabled=%s)", log: self.log, type: .debug, enabled.description)
        screenOnTriggerActive = enabled
        if !enabled {
            removeAllNotifications([repeatingNotificationIdentifier])
        }
    }
    
    @objc func onDeviceLock(_ sender: NotificationCenter) {
        os_log("onDeviceLock", log: self.log, type: .debug)
        deviceIsLocked = true
        if screenOnTriggerActive {
            scheduleNotification(repeatingNotificationIdentifier, "Contact Tracing Enabled", "Tracking contacts", delay: repeatingNotificationDelay, repeats: true)
        }
    }
    
    @objc func onDeviceUnlock(_ sender: NotificationCenter) {
        os_log("onDeviceUnlock", log: self.log, type: .debug)
        deviceIsLocked = false
        removeAllNotifications([repeatingNotificationIdentifier])
    }

    private func requestAuthorisation() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                os_log("requestAuthorisation, authorisation failed (error=%s)", log: self.log, type: .fault, error.localizedDescription)
            } else if granted {
                os_log("requestAuthorisation, authorisation granted", log: self.log, type: .debug)
            } else {
                os_log("requestAuthorisation, authorisation denied", log: self.log, type: .fault)
            }
        }
        UNUserNotificationCenter.current().delegate = self
    }
        
    private func scheduleNotification(_ identifier: String, _ title: String, _ body: String, delay: TimeInterval, repeats: Bool) {
        // Request authorisation for notification
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                os_log("notification denied, authorisation failed (error=%s)", log: self.log, type: .fault, error.localizedDescription)
            } else if granted {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: repeats)
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(request)
                os_log("notification (title=%s,body=%s,delay=%s,repeats=%s)", log: self.log, type: .debug, title, body, delay.description, repeats.description)
            } else {
                os_log("notification denied, authorisation denied", log: self.log, type: .fault)
            }
        }
    }
    
    private func removeAllNotifications(_ identifiers: [String]?) {
        guard let identifiers = identifiers else {
            os_log("removeAllNotifications", log: log, type: .debug)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [onDemandNotificationIdentifier, repeatingNotificationIdentifier])
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            return
        }
        os_log("removeAllNotifications (identifiers=%s)", log: log, type: .debug, identifiers.description)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK:- UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Silence notification when the app is in the foreground
        os_log("willPresent (action=silenceForegroundNotifications)", log: log, type: .debug)
        completionHandler(UNNotificationPresentationOptions(rawValue: 0))
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        os_log("didReceive (response=%s)", log: log, type: .debug, response.description)
    }
}
