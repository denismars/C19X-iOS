//
//  BatteryManager.swift
//  C19X
//
//  Created by Freddy Choi on 07/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import UIKit
import NotificationCenter
import os

/**
 Battery manager for monitoring battery drain over time. LocationManager and repeating local Notifications are
 known to contribute towards battery drain. While the impact should have been minimised by only requesting
 coarse-grained location updates and infrequent notifications, it is important to establish the actual impact for
 analysis and refinement.
 */
protocol BatteryManager {
    /**
     Add delegate for battery manager events.
     */
    func append(_ delegate: BatteryManagerDelegate)
}

/**
 Battery level where 0.0 means no charge and 1.0 means fully charged.
 */
typealias BatteryLevel = Float

typealias BatteryState = UIDevice.BatteryState

protocol BatteryManagerDelegate {
    /**
     Update to battery state and level.
     */
    func batteryManager(didUpdateState: BatteryState, level: BatteryLevel)
}

class ConcreteBatteryManager: NSObject, BatteryManager {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "BatteryManager")
    private var batteryLevel: BatteryLevel { UIDevice.current.batteryLevel }
    private var batteryState: BatteryState { UIDevice.current.batteryState }
    private var delegates: [BatteryManagerDelegate] = []
    
    override init() {
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self, selector: #selector(batteryLevelDidChange), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(batteryStateDidChange), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        os_log("batteryManager (state=%s,level=%s)", log: self.log, type: .debug, batteryState.description, batteryLevel.description)
    }
    
    func append(_ delegate: BatteryManagerDelegate) {
        delegates.append(delegate)
    }
    
    @objc func batteryLevelDidChange(_ sender: NotificationCenter) {
        os_log("batteryLevelDidChange (level=%s)", log: self.log, type: .debug, batteryLevel.description)
        delegates.forEach({ $0.batteryManager(didUpdateState: batteryState, level: batteryLevel ) })
    }
    
    @objc func batteryStateDidChange(_ sender: NotificationCenter) {
        os_log("batteryStateDidChange (state=%s)", log: self.log, type: .debug, batteryState.description)
        delegates.forEach({ $0.batteryManager(didUpdateState: batteryState, level: batteryLevel ) })
    }
}

extension UIDevice.BatteryState: CustomStringConvertible {
    /**
     Get plain text description of state.
     */
    public var description: String {
        switch self {
        case .charging: return ".charging"
        case .full: return ".full"
        case .unknown: return ".unknown"
        case .unplugged: return ".unplugged"
        @unknown default: return "undefined"
        }
    }
}
