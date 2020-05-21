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
    private let permittedBGAppRefreshTaskIdentifier = "org.c19x.BGAppRefreshTask"
    private let permittedBGProcessingTaskIdentifier = "org.c19x.BGProcessingTask"
    private let statisticsBGAppRefreshTask = TimeIntervalSample()
    let c19x = C19X()

    public var device: Device!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        os_log("Application will finishing launching", log: log, type: .debug)
        c19x.database.add("App launch")
        device = Device()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: permittedBGAppRefreshTaskIdentifier, using: nil) { task in
            self.handle(task: task as! BGAppRefreshTask)
        }
        return true
    }
    
    func handle(task: BGAppRefreshTask) {
        statisticsBGAppRefreshTask.add()
        os_log("Background app refresh start (time=%s,statistics=%s)", log: log, type: .debug, Date().description, statisticsBGAppRefreshTask.description)
        task.expirationHandler = {
            os_log("Background app refresh expired (time=%s)", log: self.log, type: .fault, Date().description)
            task.setTaskCompleted(success: true)
        }
        c19x.beacon.receiver.scan("backgroundAppRefresh")
        task.setTaskCompleted(success: true)
        os_log("Background app refresh end (time=%s)", log: log, type: .debug, Date().description)
        scheduleBGAppRefreshTask()
    }

    func scheduleBGAppRefreshTask() {
        os_log("Schedule background task (time=%s)", log: log, type: .fault, Date().description)
        let request = BGAppRefreshTaskRequest(identifier: permittedBGAppRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
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

