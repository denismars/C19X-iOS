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
    public let device = Device()
    private var beaconTaskLastTimestamp = Date()
    private var updateTaskLastTimestamp = Date()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        os_log("Application finished launching", log: log, type: .debug)
        
        BGTaskScheduler.shared.cancelAllTaskRequests()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "org.C19X.beacon", using: DispatchQueue.global(qos: .utility)) { task in
            self.handleBeaconTask(task: task)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "org.C19X.update", using: DispatchQueue.global(qos: .background)) { task in
            self.handleUpdateTask(task: task)
        }
        
        // Override point for customization after application launch.
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        os_log("Application entered background", log: log, type: .debug)
        scheduleBeaconTask()
        scheduleUpdateTask()
    }
    
    private func scheduleBeaconTask() {
        os_log("Scheduling beacon task", log: log, type: .debug)
        let request = BGProcessingTaskRequest(identifier: "org.C19X.beacon")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
//        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(device.parameters.beaconReceiverOffDuration / 1000))
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Scheduled beacon task successful (date=%s)", log: log, type: .fault, request.earliestBeginDate!.description)
        } catch {
            os_log("Schedule beacon task failed (error=%s)", log: log, type: .fault, String(describing: error))
        }
    }

    private func scheduleUpdateTask() {
        os_log("Scheduling update task", log: log, type: .debug)
        let request = BGAppRefreshTaskRequest(identifier: "org.C19X.update")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Scheduled update task successful (date=%s)", log: log, type: .fault, request.earliestBeginDate!.description)
        } catch {
            os_log("Schedule update task failed (error=%s)", log: log, type: .fault, String(describing: error))
        }
        
    }

    private func handleBeaconTask(task: BGTask) {
        os_log("Handling beacon task (time=%s)", log: log, type: .debug, Date().description)
        if (!beaconTaskLastTimestamp.distance(to: Date()).isLess(than: Double(device.parameters.beaconTransmitterCodeDuration / 1000))) {
            device.beacon.setBeaconCode(beaconCode: (device.codes!.get( device.parameters.retentionPeriod)))
        }
        
        task.expirationHandler = {
            self.device.beacon.stopReceiver()
            os_log("Handle beacon task failed, expired (time=%s)", log: self.log, type: .fault, Date().description)
            task.setTaskCompleted(success: false)
        }

        if (device.beacon.startReceiver()) {
            Timer.scheduledTimer(withTimeInterval: TimeInterval(device.parameters.beaconReceiverOnDuration / 1000), repeats: false) { _ in
                self.device.beacon.stopReceiver()
                os_log("Handle beacon task successful (time=%s)", log: self.log, type: .debug, Date().description)
                task.setTaskCompleted(success: true)
            }
        } else {
            os_log("Handle beacon task successful, bluetooth is off (time=%s)", log: log, type: .debug, Date().description)
            task.setTaskCompleted(success: true)
        }

        scheduleBeaconTask()
    }

    private func handleUpdateTask(task: BGTask) {
        os_log("Handling update task (time=%s)", log: log, type: .debug, Date().description)
        device.network.getTimeFromServerAndSynchronise()
        device.network.getParameters()
        device.network.getLookupInBackground()
        
        task.expirationHandler = {
            os_log("Handle update task failed, expired (time=%s)", log: self.log, type: .fault, Date().description)
        }

        task.setTaskCompleted(success: true)
        scheduleUpdateTask()
        os_log("Handle update task successful (time=%s)", log: log, type: .debug, Date().description)
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

