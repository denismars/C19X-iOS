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
    let controller: Controller = ConcreteController()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let options = (launchOptions == nil ? "[]" : launchOptions!.description)
        os_log("applicationDidFinishLaunching (launchOptions=%s)", log: log, type: .debug, options)
        controller.foreground("applicationDidFinishLaunching")
        
        // Background app refresh based on BGTaskScheduler
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
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        os_log("applicationDidEnterBackground", log: log, type: .debug)
        scheduleAppRefreshTask()
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        os_log("applicationWillTerminate", log: log, type: .debug)
        controller.notification.removeAll()
    }
    
    // MARK: - Schedule background tasks
    
    func scheduleAppRefreshTask() {
        os_log("scheduleAppRefreshTask (time=%s)", log: log, type: .debug, Date().description)
        let request = BGAppRefreshTaskRequest(identifier: permittedBGAppRefreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval.hour * 1)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            os_log("scheduleAppRefreshTask failed (error=%s)", log: log, type: .fault, String(describing: error))
        }
    }
    
    // MARK: - Handle background tasks
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefreshTask()
        os_log("handleAppRefresh start (time=%s)", log: log, type: .debug, Date().description)
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        let operation = ForegroundOperation(controller)
        task.expirationHandler = {
            // setTaskCompleted called in completion block below
            operationQueue.cancelAllOperations()
        }
        operation.completionBlock = {
            os_log("handleAppRefresh end (time=%s,expired=%s)", log: self.log, type: .debug, Date().description, operation.isCancelled.description)
            task.setTaskCompleted(success: operation.isCancelled)
        }
        operationQueue.addOperations([operation], waitUntilFinished: false)
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

/**
 Background app refresh task to bring controller to foreground periodically.
 
 Bringing controller to foreground will trigger it to check registration, initialise transceiver, apply settings
 and synchronise data with server, which in turn will also update the data presented on the GUI.
 */
class ForegroundOperation : Operation {
    private let log = OSLog(subsystem: "org.C19X", category: "App")
    private let controller: Controller
    
    init(_ controller: Controller) {
        self.controller = controller
    }
    
    override func main() {
        os_log("ForegroundOperation (state=start)", log: log, type: .debug)
        controller.foreground("BGAppRefresh")
        os_log("ForegroundOperation (state=started)", log: log, type: .debug)
        for i in (1...4).reversed() {
            guard !isCancelled else {
                os_log("ForegroundOperation (state=cancelled)", log: log, type: .debug)
                return
            }
            os_log("ForegroundOperation (state=keepAwake,remaining=%ss)", log: log, type: .debug, i.description)
            sleep(1)
        }
        os_log("ForegroundOperation (state=end)", log: log, type: .debug)
    }
}
