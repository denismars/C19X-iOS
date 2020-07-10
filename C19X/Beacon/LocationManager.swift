//
//  LocationManager.swift
//  C19X
//
//  Created by Freddy Choi on 06/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreLocation
import os

/**
 Location manager is being used to enable background beacon detection where the physical device is either new, or been
 out of range for over circa 20 minutes. Given two iOS devices, both running the app but never encountered each other. If
 both devices have remained inactive (app in background) and in solitude (no detection) for over 20 minutes, when the two
 encounter each other, no detection will occur because of the combination of iOS background advert and scan limitations
 where service UUID is not exchanged (in overflow area). However, enabling beacon ranging will trigger the overflow area
 data to be exchanged when (i) the screen is ON and (ii) app is in background mode. The first is achieved by running a
 repeating local notification that triggers screen ON briefly at regular intervals. The latter is achieved by enabling location
 monitoring in background which keeps the app in background mode indefinitely.
 Experiments have been conducted to try removing location monitoring or use lower power alternatives (visits), but the
 solution does not work unless location monitoring is used to keep the app in background mode.
 Please node, the CLLocationManagerDelegate methods are not implemented by ConcreteLocationManager, thus proofing
 that this app does not record your location.
*/
protocol LocationManager {
}

class ConcreteLocationManager: NSObject, LocationManager, CLLocationManagerDelegate {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "LocationManager")
    private let locationManager: CLLocationManager
    private let uuid = UUID(uuidString: beaconServiceCBUUID.uuidString)!
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.allowsBackgroundLocationUpdates = true
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = false
        }

        locationManager.startUpdatingLocation()
        let beaconRegion = CLBeaconRegion(proximityUUID: uuid, identifier: uuid.uuidString)
        if #available(iOS 13.0, *) {
            locationManager.startMonitoring(for: beaconRegion)
            locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
            os_log("init (iOS 13.0+)", log: log, type: .debug)
        } else {
            locationManager.startMonitoring(for: beaconRegion)
            locationManager.startRangingBeacons(in: beaconRegion)
            os_log("init (iOS 13.0-)", log: log, type: .debug)
        }
    }
    
    deinit {
        let beaconRegion = CLBeaconRegion(proximityUUID: uuid, identifier: uuid.uuidString)
        if #available(iOS 13.0, *) {
            locationManager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
            locationManager.stopMonitoring(for: beaconRegion)
        } else {
            locationManager.stopRangingBeacons(in: beaconRegion)
            locationManager.stopMonitoring(for: beaconRegion)
        }
        locationManager.stopUpdatingLocation()
        os_log("deinit", log: log, type: .debug)
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        os_log("didEnterRegion", log: log, type: .debug)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        os_log("didExitRegion", log: log, type: .debug)
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        os_log("didRangeBeacons", log: log, type: .debug)
    }
    
}
