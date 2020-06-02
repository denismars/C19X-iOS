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
    func advice(contacts: [Contact], settings: Settings) -> (advice: Advice, contactStatus: Status)
}

/// Beacon code and status, expanded from beacon code seeds and status.
typealias MatchingData = [BeaconCode:Status]

typealias ExposurePeriod = Int
typealias ExposureOverTime = [ExposurePeriod:RSSI]
typealias ExposureProximity = [RSSI:Int]
typealias Histogram = [Int:Int]
typealias Probability = Double

class ConcreteRiskAnalysis : RiskAnalysis {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "RiskAnalysis")
    
    func advice(contacts: [Contact], settings: Settings) -> (advice: Advice, contactStatus: Status) {
        let (status,_,_) = settings.status()
        let (defaultAdvice,_,_) = settings.advice()
        let exposureThreshold = settings.exposure()
        let symptomatic = exposure(contacts, withStatus: .symptomatic, settings: settings)
        let confirmedDiagnosis = exposure(contacts, withStatus: .confirmedDiagnosis, settings: settings)
        let exposureTotal = symptomatic + confirmedDiagnosis
        let advice = (status != .healthy ? Advice.selfIsolation : (exposureTotal < exposureThreshold ? defaultAdvice : Advice.selfIsolation))
        let contactStatus = (confirmedDiagnosis > 0 ? Status.confirmedDiagnosis : (symptomatic > 0 ? Status.symptomatic : Status.healthy))
        os_log("Advice (advice=%s,default=%s,status=%s,contactStatus=%s,symptomatic=%s,confirmedDiagnosis=%s)", log: self.log, type: .debug, advice.description, defaultAdvice.description, status.description, contactStatus.description, symptomatic.description, confirmedDiagnosis.description)
        return (advice, contactStatus)
    }
    
    /// Regenerate beacon codes for beacon code seeds on device
    private func beaconCodes(_ infectionData: InfectionData) -> MatchingData {
        var data = MatchingData()
        infectionData.forEach() { beaconCodeSeed, status in
            let beaconCodes = ConcreteBeaconCodes.beaconCodes(beaconCodeSeed, count: ConcreteBeaconCodes.codesPerDay)
            beaconCodes.forEach() { beaconCode in
                guard data[beaconCode] == nil || data[beaconCode] == status else {
                    let from = data[beaconCode]!
                    if (status.rawValue > from.rawValue) {
                        data[beaconCode] = status
                    }
                    os_log("Beacon code collision (code=%s,from=%s,to=%s)", log: self.log, type: .fault, beaconCode.description, from.description, status.description)
                    return
                }
                data[beaconCode] = status
            }
        }
        return data
    }
    
    /**
     Match contacts with infection data to establish exposure proximity, showing number of exposure periods for each RSSI value.
     */
    private func match(_ contacts: [Contact], withStatus: Status, infectionData: InfectionData) -> ExposureProximity {
        let matchingData = beaconCodes(infectionData)
        var exposureOverTime = ExposureOverTime()
        contacts.forEach() { contact in
            let beaconCode = BeaconCode(contact.code)
            guard let status = matchingData[beaconCode], status == withStatus, let time = contact.time else {
                return
            }
            let period = ExposurePeriod(lround(time.timeIntervalSinceNow / TimeInterval.minute))
            let rssi = RSSI(contact.rssi)
            if exposureOverTime[period] == nil || exposureOverTime[period]! < rssi {
                exposureOverTime[period] = rssi
            }
        }
        let exposureProximity = proximity(exposureOverTime)
        return exposureProximity
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
    private func exposure(_ contacts: [Contact], withStatus: Status, settings: Settings) -> ExposurePeriod {
        let (infectionData, _) = settings.infectionData()
        let proximity = settings.proximity()
        let exposureProximity = match(contacts, withStatus: withStatus, infectionData: infectionData)
        var sum: ExposurePeriod = 0
        exposureProximity.forEach() { rssi, count in
            guard rssi >= proximity else {
                return
            }
            sum += count
        }
        os_log("Exposure (status=%s,sum=%s)", log: self.log, type: .debug, withStatus.description, sum.description)
        return sum
    }
}

protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int)
}
