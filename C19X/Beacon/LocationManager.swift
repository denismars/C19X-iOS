//
//  LocationManager.swift
//  C19X
//
//  Created by Freddy Choi on 06/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreLocation

protocol LocationManager {
}

/**
 Location manager for ranging a fictional iBeacon. The purpose of LocationManager is not to track location but to enable
 background detection of beacons when app is in background/suspended/terminated state.s
 */
class ConcreteLocationManager: NSObject, LocationManager, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let uuid = UUID(uuidString: "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6")!
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.pausesLocationUpdatesAutomatically = false
        if #available(iOS 9.0, *) {
          locationManager.allowsBackgroundLocationUpdates = true
        }
        if #available(iOS 13.0, *) {
            locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        } else {
            locationManager.startRangingBeacons(in: CLBeaconRegion(proximityUUID: uuid, identifier: "iBeacon"))
        }
    }
}
