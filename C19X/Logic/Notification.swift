//
//  Notification.swift
//  C19X
//
//  Created by Freddy Choi on 06/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import UIKit
import os

protocol Notification {
    func content(title: String, body: String)
}

class ConcreteNotification: NSObject, Notification, UNUserNotificationCenterDelegate {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "Notification")
    private let repeatInterval = TimeInterval(5 * 60)

    func content(title: String, body: String) {
        if #available(iOS 10.0, *) {
            notification10(title, body, delay: repeatInterval, repeats: true)
        }
    }
    
    @available(iOS 10.0, *)
    private func notification10(_ title: String, _ body: String, delay: TimeInterval, repeats: Bool) {
        // Request authorisation for notification
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                os_log("notification denied, authorisation failed (error=%s)", log: self.log, type: .fault, error.localizedDescription)
            } else if granted {
                let identifier = "C19X.notification"
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
}
