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
    private let permittedBackgroundTaskIdentifier = "org.C19X.fetch"
    public var device: Device!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        os_log("Application will finishing launching", log: log, type: .debug)
        
        device = Device()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: permittedBackgroundTaskIdentifier, using: nil) { task in
            self.handleBackgroundTask(task: task)
        }
        return true
    }
    
    private func handleBackgroundTask(task: BGTask) {
        task.setTaskCompleted(success: true)
//        os_log("Handling background task (time=%s)", log: log, type: .debug, Date().description)
//        device.update() {
//            self.scheduleBackgroundTask()
//            task.setTaskCompleted(success: true)
//        }
//        task.expirationHandler = {
//            os_log("Handle background beacon task expired (time=%s)", log: self.log, type: .fault, Date().description)
//            self.scheduleBackgroundTask()
//            task.setTaskCompleted(success: false)
//        }
    }
    
    func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: permittedBackgroundTaskIdentifier)
    }

    func scheduleBackgroundTask() {
        guard !device.parameters.isFirstUse() else {
            os_log("Scheduling background task ignored until data sharing has been agreed by user", log: log, type: .debug)
            return
        }
        os_log("Scheduling background task", log: log, type: .debug)
        let request = BGProcessingTaskRequest(identifier: permittedBackgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Schedule background task successful", log: log, type: .fault)
        } catch {
            os_log("Schedule background task failed (error=%s)", log: log, type: .fault, String(describing: error))
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

