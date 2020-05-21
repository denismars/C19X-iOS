//
//  Utilities.swift
//  C19X
//
//  Created by Freddy Choi on 24/03/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth

/**
 CBUUID has been extended to make use of the upper and lower 64-bits for of the UUID for data transfer.
 */
extension CBUUID {
    /**
     Create UUID from upper and lower 64-bits values. Java long compatible conversion.
     */
    convenience init(upper: Int64, lower: Int64) {
        let upperData = (withUnsafeBytes(of: upper) { Data($0) }).reversed()
        let lowerData = (withUnsafeBytes(of: lower) { Data($0) }).reversed()
        let bytes = [UInt8](upperData) + [UInt8](lowerData)
        let data = Data(bytes)
        self.init(data: data)
    }
    
    /**
     Get upper and lower 64-bit values. Java long compatible conversion.
     */
    var values: (upper: Int64, lower: Int64) {
        let data = UUID(uuidString: self.uuidString)!.uuid
        let upperData: [UInt8] = [data.0, data.1, data.2, data.3, data.4, data.5, data.6, data.7].reversed()
        let lowerData: [UInt8] = [data.8, data.9, data.10, data.11, data.12, data.13, data.14, data.15].reversed()
        let upper = upperData.withUnsafeBytes { $0.load(as: Int64.self) }
        let lower = lowerData.withUnsafeBytes { $0.load(as: Int64.self) }
        return (upper, lower)
    }
}

/**
 Extension to make the state human readable in logs.
 */
extension CBManagerState: CustomStringConvertible {
    /**
     Get plain text description of state.
     */
    public var description: String {
        switch self {
        case .poweredOff: return ".poweredOff"
        case .poweredOn: return ".poweredOn"
        case .resetting: return ".resetting"
        case .unauthorized: return ".unauthorized"
        case .unknown: return ".unknown"
        case .unsupported: return ".unsupported"
        @unknown default: return "undefined"
        }
    }
}

/**
Extension to make the state human readable in logs.
*/
extension CBPeripheralState: CustomStringConvertible {
    /**
     Get plain text description fo state.
     */
    public var description: String {
        switch self {
        case .connected: return ".connected"
        case .connecting: return ".connecting"
        case .disconnected: return ".disconnected"
        case .disconnecting: return ".disconnecting"
        @unknown default: return "undefined"
        }
    }
}

/**
 Sample statistics.
 */
class Sample {
    private var n:Int64 = 0
    private var m1:Double = 0.0
    private var m2:Double = 0.0
    private var m3:Double = 0.0
    private var m4:Double = 0.0
    
    /**
     Minimum sample value.
     */
    var min:Double? = nil
    /**
     Maximum sample value.
     */
    var max:Double? = nil
    /**
     Sample size.
     */
    var count:Int64 { get { n } }
    /**
     Mean sample value.
     */
    var mean:Double? { get { n > 0 ? m1 : nil } }
    /**
     Sample variance.
     */
    var variance:Double? { get { n > 1 ? m2 / Double(n - 1) : nil } }
    /**
     Sample standard deviation.
     */
    var standardDeviation:Double? { get { n > 1 ? sqrt(m2 / Double(n - 1)) : nil } }
    /**
     String representation of mean, standard deviation, min and max
     */
    var description: String { get {
        let sCount = n.description
        let sMean = (mean == nil ? "-" : mean!.description)
        let sStandardDeviation = (standardDeviation == nil ? "-" : standardDeviation!.description)
        let sMin = (min == nil ? "-" : min!.description)
        let sMax = (max == nil ? "-" : max!.description)
        return "count=" + sCount + ",mean=" + sMean + ",sd=" + sStandardDeviation + ",min=" + sMin + ",max=" + sMax
    } }

    /**
     Add sample value.
     */
    func add(_ x:Double) {
        // Sample value accumulation algorithm avoids reiterating sample to compute variance.
        let n1 = n
        n += 1
        let d = x - m1
        let d_n = d / Double(n)
        let d_n2 = d_n * d_n;
        let t = d * d_n * Double(n1);
        m1 += d_n;
        m4 += t * d_n2 * Double(n * n - 3 * n + 3) + 6 * d_n2 * m2 - 4 * d_n * m3;
        m3 += t * d_n * Double(n - 2) - 3 * d_n * m2;
        m2 += t;
        if min == nil || x < min! {
            min = x;
        }
        if max == nil || x > max! {
            max = x;
        }
    }
}

/**
 Time interval samples for collecting elapsed time statistics.
 */
class TimeIntervalSample : Sample {
    private var startTime: Date?
    private var timestamp: Date?
    var period: TimeInterval? { get {
        (startTime == nil ? nil : timestamp?.timeIntervalSince(startTime!))
    }}
    
    override var description: String { get {
        let sPeriod = (period == nil ? "-" : period!.description)
        return super.description + ",period=" + sPeriod
    }}
    
    /**
     Add elapsed time since last call to add() as sample.
     */
    func add() {
        guard timestamp != nil else {
            timestamp = Date()
            startTime = timestamp
            return
        }
        let now = Date()
        add(timestamp!.distance(to: now))
        timestamp = now
    }
}
