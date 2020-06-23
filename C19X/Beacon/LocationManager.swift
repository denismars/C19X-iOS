//
//  LocationManager.swift
//  C19X
//
//  Trigger beacon start for suspended / killed app when user moves. This is
//  necessary when all devices are in the vicinity are in suspended state.
//
//  Created by Freddy Choi on 23/06/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreLocation
import os

protocol LocationManager {
    var delegates: [LocationManagerDelegate] { get set }
    
    func start(_ source: String)

    func stop(_ source: String)
}

protocol LocationManagerDelegate {
    func locationManager(didUpdateAt: Date)
}

/**
 Extension to make the state human readable in logs.
 */
extension CLAuthorizationStatus: CustomStringConvertible {
    /**
     Get plain text description fo state.
     */
    public var description: String {
        switch self {
        case .authorizedAlways: return ".authorizedAlways"
        case .authorizedWhenInUse: return ".authorizedWhenInUse"
        case .denied: return ".denied"
        case .notDetermined: return ".notDetermined"
        case .restricted: return ".restricted"
        @unknown default: return "undefined"
        }
    }
}

class ConcreteLocationManager: NSObject, LocationManager, CLLocationManagerDelegate {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "LocationManager")
    var delegates: [LocationManagerDelegate] = []
    private let locationManager: CLLocationManager!
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        // Distance filter for startUpdatingLocation
        locationManager.distanceFilter = CLLocationDistance(1)
        //locationManager.distanceFilter = kCLDistanceFilterNone
        // Angular filter for startUpdatingHeading
        locationManager.headingFilter = CLLocationDegrees(30)
    }
    
    func start(_ source: String) {
        os_log("start (source=%s)", log: log, type: .debug, source)
        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            os_log("requestAlwaysAuthorization (status=%s)", log: log, type: .debug, CLLocationManager.authorizationStatus().description)
            locationManager.requestAlwaysAuthorization()
        }

        if CLLocationManager.locationServicesEnabled() {
            os_log("startUpdatingLocation", log: log, type: .debug)
            locationManager.startUpdatingLocation()
        } else {
            os_log("startUpdatingLocation failed", log: log, type: .fault)
        }
        
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            os_log("startMonitoringSignificantLocationChanges", log: log, type: .debug)
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            os_log("startMonitoringSignificantLocationChanges failed", log: log, type: .fault)
        }

        guard CLLocationManager.headingAvailable() else {
            os_log("start denied partially, heading not available", log: log, type: .fault)
            return
        }
        locationManager.startUpdatingHeading()
    }
    
    func stop(_ source: String) {
        os_log("stop (source=%s)", log: log, type: .debug, source)
        locationManager.stopUpdatingLocation()
    }
    
    // MARK:- CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        os_log("didChangeAuthorization (status=%s)", log: log, type: .debug, status.description)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        os_log("didUpdateLocations", log: log, type: .debug)
        // Location is never recorded or shared. This is being used to detect movement to wake up app.
        delegates.forEach { $0.locationManager(didUpdateAt: Date()) }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        os_log("didUpdateHeading", log: log, type: .debug)
        // Location is never recorded or shared. This is being used to detect movement to wake up app.
        delegates.forEach { $0.locationManager(didUpdateAt: Date()) }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        os_log("didFailWithError (error=%s)", log: log, type: .debug, String(describing: error))
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        os_log("locationManagerDidPauseLocationUpdates", log: log, type: .debug)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        os_log("locationManagerDidResumeLocationUpdates", log: log, type: .debug)
    }
}
