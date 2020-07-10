//
//  MotionDetection.swift
//  C19X
//
//  Created by Freddy Choi on 10/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit
import CoreMotion
import os

protocol MotionDetection {
}

class ConcreteMotionDetection : NSObject, MotionDetection {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "MotionDetection")
    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    private var shouldRestartMotionUpdates = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        start()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func start() {
        self.shouldRestartMotionUpdates = true
        self.restartMotionUpdates()
    }

    private func stop() {
        self.shouldRestartMotionUpdates = false
        self.motionManager.stopDeviceMotionUpdates()
    }

    @objc private func appDidEnterBackground() {
        self.restartMotionUpdates()
    }

    @objc private func appDidBecomeActive() {
        self.restartMotionUpdates()
    }

    private func restartMotionUpdates() {
        guard shouldRestartMotionUpdates else {
            return
        }
        motionManager.stopDeviceMotionUpdates()
        motionManager.deviceMotionUpdateInterval = TimeInterval(5)
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: operationQueue) { deviceMotion, error in
            guard let deviceMotion = deviceMotion else {
                return
            }
            os_log("deviceMotionUpdate (motion=%s)", log: self.log, type: .debug, deviceMotion.description)
        }
    }
}
