//
//  RiskAnalysis.swift
//  C19X
//
//  Created by Freddy Choi on 27/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import os

protocol RiskAnalysis {
    func advice(contacts: [Contact], settings: Settings, callback: ((Advice, Status, ExposureOverTime, ExposureProximity) -> Void)?)
}

typealias ExposurePeriod = Int
typealias ExposureOverTime = [ExposurePeriod:RSSI]
typealias ExposureProximity = [RSSI:Int]

class ConcreteRiskAnalysis : RiskAnalysis {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "RiskAnalysis")
    private let queue = DispatchQueue(label: "org.c19x.logic.RiskAnalysis", qos: .background)
    
    func advice(contacts: [Contact], settings: Settings, callback: ((Advice, Status, ExposureOverTime, ExposureProximity) -> Void)?) {
        // Get status and default advice
        let (status,_,_) = settings.status()
        let (defaultAdvice,_,_) = settings.advice()
        let exposureThreshold = settings.exposure()
        // Match in background
        queue.async {
            let (exposurePeriod, exposureOverTime, exposureProximity) = self.match(contacts, settings)
            let advice = (status != .healthy ? Advice.selfIsolation : (exposurePeriod < exposureThreshold ? defaultAdvice : Advice.selfIsolation))
            let contactStatus = (exposurePeriod == 0 ? Status.healthy : Status.infectious)
            os_log("Advice (advice=%s,default=%s,status=%s,contactStatus=%s,exposure=%s,proximity=%s)", log: self.log, type: .debug, advice.description, defaultAdvice.description, status.description, contactStatus.description, exposurePeriod.description, exposureProximity.description)
            callback?(advice, contactStatus, exposureOverTime, exposureProximity)
        }
    }

    /**
     Match contacts against infection data.
     */
    private func match(_ contacts: [Contact], _ settings: Settings) -> (ExposurePeriod, ExposureOverTime, ExposureProximity) {
        let (infectionData, _) = settings.infectionData()
        let rssiThreshold = settings.proximity()
        let beaconsForMatching = beacons(contacts)
        let exposureOverTime = exposure(beaconsForMatching, infectionData)
        let exposureProximity = proximity(exposureOverTime)
        let exposurePeriod = period(exposureProximity, threshold: rssiThreshold)
        return (exposurePeriod, exposureOverTime, exposureProximity)
    }
    
    /**
     Create map of beacon codes for matching.
     */
    private func beacons(_ contacts: [Contact]) -> [BeaconCode:[Contact]] {
        var beacons: [BeaconCode:[Contact]] = [:]
        contacts.forEach() { contact in
            let beaconCode = BeaconCode(contact.code)
            if beacons[beaconCode] == nil {
                beacons[beaconCode] = [contact]
            } else {
                beacons[beaconCode]!.append(contact)
            }
        }
        return beacons
    }
    
    /**
     Regenerate beacon codes from infection data for matching to establish exposure over time.
     */
    private func exposure(_ beacons: [BeaconCode:[Contact]], _ infectionData: InfectionData) -> ExposureOverTime {
        var exposureOverTime = ExposureOverTime()
        infectionData.forEach() { beaconCodeSeed, status in
            guard status != .healthy else {
                // Matching symptomatic or confirmed diagnosis only
                return
            }
            // Regenerate beacon codes based on seed
            let beaconCodesForMatching = ConcreteBeaconCodes.beaconCodes(beaconCodeSeed, count: ConcreteBeaconCodes.codesPerDay)
            beaconCodesForMatching.forEach() { beaconCode in
                guard let contacts = beacons[beaconCode] else {
                    // Unmatched
                    return
                }
                contacts.forEach() { contact in
                    guard let time = contact.time else {
                        // No time stamp
                        return
                    }
                    let exposurePeriod = ExposurePeriod(lround(time.timeIntervalSinceNow / TimeInterval.minute))
                    let exposureProximity = RSSI(contact.rssi)
                    // Identify nearest encounter for each exposure period
                    if exposureOverTime[exposurePeriod] == nil || exposureOverTime[exposurePeriod]! < exposureProximity {
                        exposureOverTime[exposurePeriod] = exposureProximity
                    }
                }
            }
        }
        return exposureOverTime
    }
    
    /**
     Histogram of exposure proximity
     */
    private func proximity(_ exposure: ExposureOverTime) -> ExposureProximity {
        var proximity = ExposureProximity()
        exposure.forEach() { _, rssi in
            guard let count = proximity[rssi] else {
                proximity[rssi] = 1
                return
            }
            proximity[rssi] = count + 1
        }
        return proximity
    }
    
    /**
     Calculate exposure period.
     */
    private func period(_ proximity: ExposureProximity, threshold: RSSI) -> ExposurePeriod {
        var period: ExposurePeriod = 0
        proximity.forEach() { rssi, count in
            guard rssi >= threshold else {
                return
            }
            period += count
        }
        return period
    }
}

protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int)
}
