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
    var controller: Controller!
    
    //var device: Device!
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        os_log("Application will finishing launching", log: log, type: .debug)
        controller = ConcreteController()
        //device = Device()
        
        // Schedule regular background task to stop - rest - start beacon to keep it running indefinitely
        // State preservation and restoration work most of the time. It can handle bluetooth off/on reliably,
        // and it can handle airplane mode on/off most of the time, especially when bluetooth off period
        // isn't too long. CoreBluetooth struggles the most in situations where a connected peripheral goes
        // out of range and returns, when both devices are in background mode the whole time. Bringing the
        // app back to foreground instantly resumes the connection but that's not great.
        //
        // Test procedure for background task during development
        // 1. Run app, send it to background mode (sleep button or de-focus app)
        // 2. Pause app in Xcode, log should show "[App] Schedule background task"
        // 3. On the (lldb) prompt, run:
        //    e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"org.c19x.BGAppRefreshTask"]
        //    ... should respond with "Simulating launch for task with identifier org.c19x.BGAppRefreshTask"
        // 4. Resume app in Xcode, log should show "[App] Background app refresh start"
        //
        // To test early termination of background task
        // 5. While the background task is running, pause app in Xcode
        // 6. On the (lldb) prompt, run:
        //    e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"org.c19x.BGAppRefreshTask"]
        //    ... should respond with "Simulating expiration for task with identifier org.c19x.BGAppRefreshTask"
        // 7. Resume app in Xcode, log should show "[App] Background app refresh expired"
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: permittedBGAppRefreshTaskIdentifier, using: nil) { task in
            self.handle(task: task as! BGAppRefreshTask)
        }
        return true
    }
    
    func handle(task: BGAppRefreshTask) {
        statisticsBGAppRefreshTask.add()
        os_log("Background app refresh start (time=%s,statistics=%s)", log: log, type: .debug, Date().description, statisticsBGAppRefreshTask.description)
        guard let transceiver = controller.transceiver else {
            task.setTaskCompleted(success: true)
            os_log("Background app refresh end, transceiver has not been initialised yet (time=%s)", log: log, type: .debug, Date().description)
            return
        }
        task.expirationHandler = {
            transceiver.start("BGAppRefreshTask|expiration")
            os_log("Background app refresh expired (time=%s)", log: self.log, type: .fault, Date().description)
            task.setTaskCompleted(success: true)
        }
        transceiver.stop("BGAppRefreshTask")
        transceiver.start("BGAppRefreshTask")
        os_log("Background app refresh end (time=%s)", log: self.log, type: .debug, Date().description)
        task.setTaskCompleted(success: true)
        enableBGAppRefreshTask()
    }
    
    /**
     Enable background app refresh task for resetting and resting the beacon at regular intervals.
     This should be called from SceneDelegate:sceneDidEnterBackground.
     */
    func enableBGAppRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: permittedBGAppRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval.hour)
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Background app refresh task enabled (time=%s)", log: log, type: .fault, Date().description)
        } catch {
            os_log("Background app refresh task enable failed (error=%s)", log: log, type: .fault, String(describing: error))
        }
    }
    
    /**
     Disable background app refresh task for resetting and resting the beacon at regular intervals.
     This should be called from SceneDelegate:sceneDidEnterForeground.
     */
    func disableBGAppRefreshTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: permittedBGAppRefreshTaskIdentifier)
        os_log("Background app refresh task disabled (time=%s)", log: log, type: .fault, Date().description)
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

