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
import UIKit
import os

/**
 Location manager to detecting device movement. This is NOT being used for location tracking. Movement
 detection is being used to start beacon transceiver on suspended apps. Given two iOS devices running the
 C19X app. If they have both been running in isolation for some time, i.e. two people in separate dwellings in
 a sparsely populated area, the app will enter suspended or even killed state. In theory, CoreBluetooth should
 automatically launch the app when the devices are within range and call didDiscover. In practice, this often
 doesn't happen, and only works if the app is in foreground state (impractical and unlikely) or scan start has
 been called explicitly. There is already a BGAppRefresh task that is expected to run at regular intervals to
 trigger scan start in the background, however, that is also unreliable, thus the only logical way forward is to
 monitor device movement as trigger. This is because if the iOS device is already in close proximity with
 another device, the existing beacon works reliably. The non-detection problem only occurs when the device
 has not been in contact with other devices for some time and enters suspended state, therefore the only
 situation when it should be launched again to scan for devices is following movement.
 */
protocol LocationManager {
    var delegates: [LocationManagerDelegate] { get set }
    
    /**
     Start movement monitoring.
     */
    func start(_ source: String)

    /**
     Stop movement monitoring.
     */
    func stop(_ source: String)
}

protocol LocationManagerDelegate {
    
    /**
     Device has moved. This could be movement or heading changes. Please note the delegate
     does not actually receive any location data, as the solution does not track user locations.
     */
    func locationManager(didUpdateAt: Date)
}

/**
 Extension to make the status human readable in logs.
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
    private let locationManager = CLLocationManager()
    
    // Movement detection methods. Methods that relaunches app will do so
    // even after the user force-quits app (let's hope that really is true)
    // Visits service : Very low power, launches app, detects activity
    private let methodVisits = true
    // Significant change : Low power, launches app, detects 500m change, updates about every 5 minutes
    private let methodSignificantChange = true
    // Location change : High power, does not launch app, detects any movement in real time
    private let methodLocation = false
    // Heading change : High power, does not launch app, detects any change of direction in real time
    private let methodHeading = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        
        // Distance filter (in meters) for methodLocation
        locationManager.distanceFilter = CLLocationDistance(1)
        // Angular filter (in degrees) for methodHeading
        locationManager.headingFilter = CLLocationDegrees(20)
    }
    
    func start(_ source: String) {
        os_log("start (source=%s)", log: log, type: .debug, source)
        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            os_log("requestAlwaysAuthorization (status=%s)", log: log, type: .debug, CLLocationManager.authorizationStatus().description)
            locationManager.requestAlwaysAuthorization()
        }
        
        if methodVisits {
            os_log("methodVisits", log: log, type: .debug)
            locationManager.startMonitoringVisits()
            //os_log("startMonitoringVisits", log: log, type: .debug)
        }
        
        if methodSignificantChange {
            os_log("methodSignificantChange", log: log, type: .debug)
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                locationManager.startMonitoringSignificantLocationChanges()
                //os_log("startMonitoringSignificantLocationChanges", log: log, type: .debug)
            } else {
                os_log("startMonitoringSignificantLocationChanges failed", log: log, type: .fault)
            }
        }

        if methodLocation {
            os_log("methodLocation", log: log, type: .debug)
            if CLLocationManager.locationServicesEnabled() {
                locationManager.startUpdatingLocation()
                //os_log("startUpdatingLocation", log: log, type: .debug)
            } else {
                os_log("startUpdatingLocation failed", log: log, type: .fault)
            }
        }
        
        if methodHeading {
            os_log("methodHeading", log: log, type: .debug)
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
                //os_log("startUpdatingHeading", log: log, type: .debug)
            } else {
                os_log("startUpdatingHeading failed", log: log, type: .fault)
            }
        }
    }
    
    func stop(_ source: String) {
        os_log("stop (source=%s)", log: log, type: .debug, source)
        if methodVisits { locationManager.stopMonitoringVisits() }
        if methodSignificantChange { locationManager.stopMonitoringSignificantLocationChanges() }
        if methodLocation { locationManager.stopUpdatingLocation() }
        if methodHeading { locationManager.stopUpdatingHeading() }
    }
    
    /// Location is never recorded or shared.
    private func notifyDelegates(_ source: String) {
        //os_log("notifyDelegates (source=%s)", log: log, type: .debug, source.description)
        delegates.forEach { $0.locationManager(didUpdateAt: Date()) }
    }
    
    // MARK:- CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        os_log("didChangeAuthorization (status=%s)", log: log, type: .debug, status.description)
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        os_log("didVisit", log: log, type: .debug)
        notifyDelegates("didUpdateLocations")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        os_log("didUpdateLocations", log: log, type: .debug)
        notifyDelegates("didUpdateLocations")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        os_log("didUpdateHeading", log: log, type: .debug)
        notifyDelegates("didUpdateHeading")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        os_log("didFailWithError (error=%s)", log: log, type: .debug, String(describing: error))
        notifyDelegates("didFailWithError")
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        os_log("locationManagerDidPauseLocationUpdates", log: log, type: .debug)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        os_log("locationManagerDidResumeLocationUpdates", log: log, type: .debug)
    }
}
