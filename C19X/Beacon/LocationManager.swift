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
    /**
     Start movement monitoring.
     */
    func start(_ source: String)

    /**
     Stop movement monitoring.
     */
    func stop(_ source: String)
    
    /**
     Register delegate
     */
    func append(_ delegate: LocationManagerDelegate)
}

protocol LocationManagerDelegate : NSObjectProtocol {
    
    /**
     Device has moved. This could be movement or heading changes. Please note the delegate
     does not actually receive any location data, as the solution does not track user locations.
     */
    func locationManager(didDetect: LocationChange)
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

enum LocationChange: String {
    case visit, significantChange, region, location, heading
}

class ConcreteLocationManager: NSObject, LocationManager, CLLocationManagerDelegate {
    private let log = OSLog(subsystem: "org.c19x.beacon", category: "LocationManager")
    private let locationManager = CLLocationManager()
    private let regionRadius = CLLocationDistance(10)
    private var delegates: [LocationManagerDelegate] = []
    private var region: CLRegion?
    
    // Movement detection methods. Methods that relaunches app will do so
    // even after the user force-quits app (let's hope that really is true)
    // Visit : Very low power, launches app, detects activity
    // Significant change : Low power, launches app, detects 500m change, updates about every 5 minutes
    // Region : Medium power, launches app, detects entry and exit of regions
    // Location : High power, does not launch app, detects any movement in real time
    // Heading : High power, does not launch app, detects any change of direction in real time
    private let detectionMethods: [LocationChange] = [.visit, .significantChange, .region]
    

    override init() {
        super.init()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.delegate = self

        // Distance filter (in meters) for methodLocation
        locationManager.distanceFilter = (regionRadius < locationManager.maximumRegionMonitoringDistance ? regionRadius : locationManager.maximumRegionMonitoringDistance)
        // Angular filter (in degrees) for methodHeading
        locationManager.headingFilter = CLLocationDegrees(20)
        
        start("init")
    }
    
    func append(_ delegate: LocationManagerDelegate) {
        delegates.append(delegate)
    }
    
    func start(_ source: String) {
        os_log("start (source=%s,methods=%s)", log: log, type: .debug, source, detectionMethods.description)
        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            os_log("requestAlwaysAuthorization (status=%s)", log: log, type: .debug, CLLocationManager.authorizationStatus().description)
            locationManager.requestAlwaysAuthorization()
        }
        
        if detectionMethods.contains(.visit) {
            locationManager.startMonitoringVisits()
        }
        
        if detectionMethods.contains(.significantChange) {
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                locationManager.startMonitoringSignificantLocationChanges()
            } else {
                os_log("detection method unsupported (method=.significantChange)", log: log, type: .fault)
            }
        }

        if detectionMethods.contains(.region) {
            if CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
                // requestLocation -> didUpdateLocation -> locationUpdate -> startMonitoring(for:region)
                locationManager.requestLocation()
            } else {
                os_log("detection method unsupported (method=.region)", log: log, type: .fault)
            }
        }
        
        // Only works in App foreground / background modes
        if detectionMethods.contains(.location) {
            if CLLocationManager.locationServicesEnabled() {
                locationManager.startUpdatingLocation()
            } else {
                os_log("detection method unsupported (method=.location)", log: log, type: .fault)
            }
        }
        
        // Only works in App foreground / background modes
        if detectionMethods.contains(.heading) {
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            } else {
                os_log("detection method unsupported (method=.heading)", log: log, type: .fault)
            }
        }
    }
    
    func stop(_ source: String) {
        os_log("stop (source=%s,methods=%s)", log: log, type: .debug, source, detectionMethods.description)
        if detectionMethods.contains(.visit) { locationManager.stopMonitoringVisits() }
        if detectionMethods.contains(.significantChange) { locationManager.stopMonitoringSignificantLocationChanges() }
        if detectionMethods.contains(.region), region != nil {
            locationManager.stopMonitoring(for: region!)
            region = nil
        }
        if detectionMethods.contains(.location) { locationManager.stopUpdatingLocation() }
        if detectionMethods.contains(.heading) { locationManager.stopUpdatingHeading() }
    }
    
    /// Location is never recorded or shared.
    private func locationUpdate(_ type: LocationChange, _ coordinate: CLLocationCoordinate2D? = nil) {
        os_log("locationUpdate (type=%s)", log: log, type: .debug, type.rawValue)
        delegates.forEach { $0.locationManager(didDetect: type) }

        if detectionMethods.contains(.region) {
            if let coordinate = coordinate {
                // Stop monitoring existing region
                if region != nil {
                    locationManager.stopMonitoring(for: region!)
                    region = nil
                }
                // Start monitoring next region
                let radius = (regionRadius < locationManager.maximumRegionMonitoringDistance ? regionRadius : locationManager.maximumRegionMonitoringDistance)
                region = CLCircularRegion(center: coordinate, radius: radius, identifier: "Circle")
                region?.notifyOnExit = true
                region?.notifyOnEntry = false
                locationManager.startMonitoring(for: region!)
                os_log("startMonitoring (region=%s)", log: log, type: .debug, region!.description)
            } else {
                // requestLocation -> didUpdateLocations -> locationUpdate(coordinate) -> startMonitoring(for:region)
                locationManager.requestLocation()
            }
        }
    }
    
    // MARK:- CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        os_log("didChangeAuthorization (status=%s)", log: log, type: .debug, status.description)
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        os_log("didVisit", log: log, type: .debug)
        locationUpdate(.visit, visit.coordinate)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        os_log("didUpdateLocations", log: log, type: .debug)
        locationUpdate(.location, locations.last?.coordinate)
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        os_log("didEnterRegion", log: log, type: .debug)
        locationUpdate(.region)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        os_log("didExitRegion", log: log, type: .debug)
        locationUpdate(.region)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        os_log("didUpdateHeading", log: log, type: .debug)
        locationUpdate(.heading)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        os_log("didFailWithError (error=%s)", log: log, type: .fault, error.localizedDescription)
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        os_log("locationManagerDidPauseLocationUpdates", log: log, type: .debug)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        os_log("locationManagerDidResumeLocationUpdates", log: log, type: .debug)
    }
}
