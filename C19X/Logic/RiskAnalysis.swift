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
    func risk(afterContactWith: [Contact], accordingTo: InfectionReports)
}

typealias InfectionReports = Data
typealias Histogram = [Int:Int]

class ConcreteRiskAnalysis : RiskAnalysis {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "RiskAnalysis")
    private let settings: Settings
    public var listeners: [RiskAnalysisListener] = []
    
    init(_ settings: Settings) {
        self.settings = settings
    }
    
    func risk(afterContactWith: [Contact], accordingTo: InfectionReports) {
        
    }
//    
//    private func filter(records: [ContactRecord], lookup: Data, infectious: Bool) -> [ContactRecord] {
//        let range = UInt64(lookup.count * 8)
//        return records.filter { record in
//            let index = record.beacon % range
//            return get(lookup, index: index) == infectious
//        }
//    }
//    
//    private func rssi(contacts: [Contact]) -> Histogram {
//        var histogram: Histogram = [:]
//        contacts.forEach() { contact in
//            let rssi = Int(contact.rssi)
//            histogram[rssi] = (histogram[rssi] ?? 0) + 1
//        }
//        return histogram
//    }
//    
//    private func timeHistogram(records: [ContactRecord]) -> Histogram {
//        var histogram: [Int:Int] = [:]
//        let now = Date()
//        let daySeconds:UInt64 = 24*60*60
//        let (today,_) = UInt64(now.timeIntervalSince1970).dividedReportingOverflow(by: daySeconds)
//        records.forEach() { record in
//            let (day,_) = UInt64(record.time.timeIntervalSince1970).dividedReportingOverflow(by: daySeconds)
//            let delta = abs(Int(today - day))
//            if histogram[delta] == nil {
//                histogram[delta] = 1
//            } else {
//                histogram[delta]! += 1
//            }
//        }
//        return histogram
//    }
//    
//    private func multiply(_ counts:[Int:Int], _ weights:[Int:Double]) -> Double {
//        var sumWeight = Double.zero
//        weights.values.forEach() { weight in sumWeight += weight }
//        guard !sumWeight.isZero else {
//            // Unweighted
//            var sumCount = 0
//            counts.values.forEach() { count in sumCount += count }
//            return (sumCount == 0 ? Double.zero : Double(1))
//        }
//        // Weighted
//        var product = Double.zero
//        counts.forEach() { key, value in
//            if let weight = weights[key] {
//                product += (Double(value) * weight)
//            }
//        }
//        return product / sumWeight
//    }
//    
//    public func analyse(contactRecords: ContactRecords, lookup: Data) -> (infectious:[ContactRecord], rssiHistogram:[Int:Int], timeHistogram:[Int:Int]) {
//        let infectious = filter(records: contactRecords.records, lookup: lookup, infectious: true)
//        let rssiCounts = rssiHistogram(records: infectious)
//        let timeCounts = timeHistogram(records: infectious)
//        return (infectious, rssiCounts, timeCounts)
//    }
//    
//    private func analyse(contactRecords: ContactRecords, lookup: Data, rssiWeights: [Int : Double], timeWeights: [Int : Double]) -> (infectious: Int, risk: Double) {
//        let (infectious, rssiHistogram, timeHistogram) = analyse(contactRecords: contactRecords, lookup: lookup)
//        let rssiValue = multiply(rssiHistogram, rssiWeights)
//        let timeValue = multiply(timeHistogram, timeWeights)
//        os_log("Analysis data (infectious=%d,rssiValue=%f,timeValue=%f)", log: self.log, type: .debug, infectious.count, rssiValue, timeValue)
//        return (infectious.count, rssiValue * timeValue)
//    }
//    
//    public func update(status: Int, contactRecords: ContactRecords, parameters: Parameters, lookup: Data) {
//        let previousContactStatus = contact
//        let previousAdvice = advice
//        let contactCount = contactRecords.records.count
//        let (infectiousCount, infectionRisk) = analyse(contactRecords: contactRecords, lookup: lookup, rssiWeights: parameters.getRssiHistogram(), timeWeights: parameters.getTimeHistogram())
//        
//        if (status != Device.statusNormal) {
//            advice = RiskAnalysis.adviceSelfIsolate;
//        } else {
//            contact = (infectiousCount == 0 ? RiskAnalysis.contactOk : RiskAnalysis.contactInfectious)
//            advice = (infectionRisk.isZero ? parameters.getGovernmentAdvice() :
//                RiskAnalysis.adviceSelfIsolate)
//        }
//        os_log("Analysis updated (contactCount=%u,infectiousCount=%u,contact=%d,advice=%d,risk=%f)", log: self.log, type: .debug, contactCount, infectiousCount, contact, advice, infectionRisk)
//        for listener in listeners {
//            listener.riskAnalysisDidUpdate(previousContactStatus: previousContactStatus, currentContactStatus: contact, previousAdvice: previousAdvice, currentAdvice: advice, contactCount: contactCount)
//        }
//    }
//    
//    private func get(_ data: Data, index: UInt64) -> Bool {
//        let block = Int(index / 8)
//        let bit = Int(index % 8)
//        return ((data[block] >> bit) & 1) != 0;
//    }
    
}

protocol RiskAnalysisListener {
    func riskAnalysisDidUpdate(previousContactStatus:Int, currentContactStatus:Int, previousAdvice:Int, currentAdvice:Int, contactCount:Int)
}
