//
//  AppDelegate.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit
import BackgroundTasks
import os

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    private let log = OSLog(subsystem: "org.C19X", category: "App")
    public var device: Device!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        os_log("Application will finishing launching", log: log, type: .debug)
        
        device = Device()
        BGTaskScheduler.shared.cancelAllTaskRequests()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "org.C19X.beacon", using: nil) { task in
            self.handleBackgroundTask(task: task)
        }
        return true
    }
    
    public func cancelBackgroundTask() {
        os_log("Cancelling background beacon task", log: log, type: .debug)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "org.C19X.beacon")
    }
    
    public func scheduleBackgroundTask() {
        os_log("Scheduling background beacon task", log: log, type: .debug)
        let request = BGProcessingTaskRequest(identifier: "org.C19X.beacon")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Scheduled background beacon task successful", log: log, type: .fault)
        } catch {
            os_log("Schedule background beacon task failed (error=%s)", log: log, type: .fault, String(describing: error))
        }
    }

    private func handleBackgroundTask(task: BGTask) {
        os_log("Handling background beacon task (time=%s)", log: log, type: .debug, Date().description)
        scheduleBackgroundTask()
        
        // Change beacon code
        let timeSinceBeaconCodeUpdate = device.getTimeSinceBeaconCodeUpdate()
        if (timeSinceBeaconCodeUpdate == nil || timeSinceBeaconCodeUpdate! > TimeInterval(device.parameters.beaconTransmitterCodeDuration / 1000)) {
            os_log("Changeing beacon code (time=%s)", log: log, type: .debug, Date().description)
            device.changeBeaconCode()
        }
        
        // Update lookup
        let timeSinceLookupUpdate = device.getTimeSinceLookupUpdate()
        if (timeSinceLookupUpdate == nil || timeSinceLookupUpdate! > TimeInterval(120)) {
            os_log("Downloading updates from server (time=%s)", log: log, type: .debug, Date().description)
            device.downloadUpdateFromServer()
        }

        os_log("Starting background scan (time=%s)", log: log, type: .debug, Date().description)
        device.beaconReceiver.startScan()

        task.expirationHandler = {
            self.device.beaconReceiver.startScan()
            os_log("Handle background beacon task expired (time=%s)", log: self.log, type: .fault, Date().description)
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: UISceneSession Lifecycle
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    
}

