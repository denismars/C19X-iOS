//
//  Network.swift
//  C19X
//
//  Created by Freddy Choi on 23/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import os

protocol Network {
    /**
     Synchronise time with server to enable authenticated messaging.
     */
    func synchroniseTime(_ callback: ((TimeMillis?, Error?) -> Void)?)
    
    /**
     Get registration data from central server.
     */
    func getRegistration(_ callback: ((SerialNumber?, SharedSecret?, Error?) -> Void)?)
    
    /**
     Get settings from central server.
     */
    func getSettings(callback: ((ServerSettings?, Error?) -> Void)?)
    
    /**
     Post health status to central server for sharing.
     */
    func postStatus(_ status: Status, pattern: ContactPattern, serialNumber: SerialNumber, sharedSecret: SharedSecret, _ callback: ((_ didPost: Status?, _ error: Error?) -> Void)?)
    
    /**
     Get personal message from central server.
     */
    func getMessage(serialNumber: SerialNumber, sharedSecret: SharedSecret, callback: ((Message?, Error?) -> Void)?)
    
    /**
     Get infection data [BeaconCodeSeed:Status] for on-device matching.
     */
    func getInfectionData(callback: ((InfectionData?, Error?) -> Void)?)
}

/**
 Timestamp as milliseconds since epoch as in Java.
 */
typealias TimeMillis = Int64

class ConcreteNetwork: Network {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "Network")
    private let backgroundDownload = BackgroundDownload("org.C19X.logic.ConcreteNetwork")
    private let settings: Settings
        
    init(_ settings: Settings) {
        self.settings = settings
    }
    
    /// Get timestamp that is synchronised with server
    private func getTimestamp() -> Int64 {
        let (timeDelta,_) = settings.timeDelta()
        return Int64(NSDate().timeIntervalSince1970 * 1000) + timeDelta
    }
    
    /// Get time and adjust delta to synchronise with server
    func synchroniseTime(_ callback: ((TimeMillis?, Error?) -> Void)?) {
        os_log("Synchronise time request", log: self.log, type: .debug)
        let clientTime = Int64(NSDate().timeIntervalSince1970 * 1000)
        guard let url = URL(string: settings.server() + "time") else {
            os_log("Synchronise time failed, invalid request", log: self.log, type: .fault)
            callback?(nil, NetworkError.invalidRequest)
            return
        }
        let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            guard error == nil else {
                os_log("Synchronise time failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data, let dataString = String(bytes: data, encoding: .utf8), let serverTime = Int64(dataString) else {
                os_log("Synchronise time failed, invalid response", log: self.log, type: .fault)
                callback?(nil, NetworkError.invalidResponse)
                return
            }
            let timeDelta = clientTime - serverTime
            os_log("Synchronised time with server (delta=%d)", log: self.log, type: .debug, timeDelta)
            callback?(timeDelta, nil)
        })
        task.resume()
    }
    
    /// Get registration serial number and key
    func getRegistration(_ callback: ((SerialNumber?, SharedSecret?, Error?) -> Void)?) {
        os_log("Registration request", log: self.log, type: .debug)
        guard let url = URL(string: settings.server() + "registration") else {
            os_log("Registration failed, invalid request", log: self.log, type: .fault)
            callback?(nil, nil, NetworkError.invalidRequest)
            return
        }
        let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            guard error == nil else {
                os_log("Registration failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, nil, error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data, let dataString = String(bytes: data, encoding: .utf8) else {
                os_log("Registration failed, invalid response", log: self.log, type: .fault)
                callback?(nil, nil, NetworkError.invalidResponse)
                return
            }
            let values = dataString.components(separatedBy: ",")
            guard values.count >= 2, let serialNumber = SerialNumber(values[0]), let sharedSecret = SharedSecret(base64Encoded: values[1]) else {
                os_log("Registration failed, invalid response", log: self.log, type: .fault)
                callback?(nil, nil, NetworkError.invalidResponse)
                return
            }
            os_log("Registration successful (serialNumber=%s)", log: self.log, type: .debug, serialNumber.description)
            callback?(serialNumber, sharedSecret, nil)
        })
        task.resume()
    }
    
    /// Get application parameters
    func getSettings(callback: ((ServerSettings?, Error?) -> Void)?) {
        os_log("Get settings request", log: self.log, type: .debug)
        guard let url = URL(string: settings.server() + "parameters") else {
            os_log("Get settings failed, invalid request", log: self.log, type: .fault)
            callback?(nil, NetworkError.invalidRequest)
            return
        }
        let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            guard error == nil else {
                os_log("Get settings failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []), let dictionary = json as? [String:String], let serverSettings = dictionary as ServerSettings? else {
                os_log("Get settings failed, invalid response", log: self.log, type: .fault)
                callback?(nil, NetworkError.invalidResponse)
                return
            }
            os_log("Get settings successful (settings=%s)", log: self.log, type: .debug, serverSettings.description)
            callback?(serverSettings, nil)
        })
        task.resume()
    }

    /// Post status
    func postStatus(_ status: Status, pattern: ContactPattern, serialNumber: SerialNumber, sharedSecret: SharedSecret, _ callback: ((_ didPost: Status?, _ error: Error?) -> Void)?) {
        // Create and encrypt request
        os_log("Post status request (status=%s)", log: self.log, type: .debug, status.description)
        let value = String(getTimestamp()) + "|" + String(status.rawValue) + "|" + pattern.description
        guard let encrypted = AES.encrypt(key: sharedSecret, string: value), let encoded = encrypted.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed), let url = URL(string: settings.server() + "status?key=" + String(serialNumber) + "&value=" + encoded) else {
            os_log("Post status failed, cannot encrypt and encode URL (value=%s)", log: self.log, type: .fault, value)
                callback?(nil, NetworkError.encryptionFailure)
                return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            guard error == nil else {
                os_log("Post status failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, error)
                return
            }
            guard let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let dataString = String(bytes: data, encoding: .utf8), let statusRawValue = Int(dataString), let status = Status(rawValue: statusRawValue) else {
                os_log("Post status failed, invalid response", log: self.log, type: .fault)
                callback?(nil, NetworkError.invalidResponse)
                return
            }
            os_log("Post status successful (status=%s)", log: self.log, type: .debug, status.description)
            callback?(status, nil)
        })
        task.resume()
    }
    
    /// Get device specific message
    func getMessage(serialNumber: SerialNumber, sharedSecret: SharedSecret, callback: ((Message?, Error?) -> Void)?) {
        os_log("Get message request", log: self.log, type: .debug)
        let value = String(getTimestamp())
        guard let encrypted = AES.encrypt(key: sharedSecret, string: value), let encoded = encrypted.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed), let url = URL(string: settings.server() + "message?key=" + String(serialNumber) + "&value=" + encoded) else {
            os_log("Get message failed, cannot encrypt and encode URL (value=%s)", log: self.log, type: .fault, value)
                callback?(nil, NetworkError.encryptionFailure)
                return
        }
        let request = URLRequest(url: url)
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            guard error == nil else {
                os_log("Get message failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, error)
                return
            }
            guard let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let message = Message(bytes: data, encoding: .utf8) else {
                os_log("Get message failed, invalid response", log: self.log, type: .fault)
                callback?(nil, NetworkError.invalidResponse)
                return
            }
            os_log("Get message successful (message=%s)", log: self.log, type: .debug, message.description)
            callback?(message, nil)
        })
        task.resume()
    }
    
    /// Get infection data for on-device matching
    func getInfectionData(callback: ((InfectionData?, Error?) -> Void)?) {
        getInfectionDataImmediately(callback: callback)
    }
    
    private func getInfectionDataInBackground(callback: ((InfectionData?, Error?) -> Void)?) {
        os_log("Get infection data request (background)", log: self.log, type: .debug)
        guard let url = URL(string: settings.server() + "infectionData") else {
            os_log("Get infection data request failed (error=badRequest)", log: self.log, type: .fault)
            return
        }
        backgroundDownload.get(url) { data, error in
            guard error == nil else {
                os_log("Get infection data failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, error)
                return
            }
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []), let dictionary = json as? [String:String] else {
                os_log("Get infection data failed, invalid response", log: self.log, type: .fault)
                callback?(nil, NetworkError.invalidResponse)
                return
            }
            var infectionData = InfectionData()
            dictionary.forEach { key, value in
                guard let beaconCodeSeed = BeaconCodeSeed(key), let rawValue = Int(value), let status = Status(rawValue: rawValue) else {
                    os_log("Parse infection data failed (key=%s,value=%s)", log: self.log, type: .fault, key, value)
                    return
                }
                infectionData[beaconCodeSeed] = status
            }
            callback?(infectionData, nil)
            os_log("Get infection data successful", log: self.log, type: .debug)
        }
    }
    
    /// Get infection data for on-device matching immediately
    private func getInfectionDataImmediately(callback: ((InfectionData?, Error?) -> Void)?) {
        os_log("Get infection data request (immediate)", log: self.log, type: .debug)
        guard let url = URL(string: settings.server() + "infectionData") else {
            os_log("Get infection data request failed (error=badRequest)", log: self.log, type: .fault)
            return
        }
        let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            guard error == nil else {
                os_log("Get infection data failed, network error (error=%s)", log: self.log, type: .fault, String(describing: error))
                callback?(nil, error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, let data = data, let json = try? JSONSerialization.jsonObject(with: data, options: []), let dictionary = json as? [String:String] else {
                os_log("Get infection data failed, invalid response", log: self.log, type: .fault)
                callback?(nil, NetworkError.invalidResponse)
                return
            }
            var infectionData = InfectionData()
            dictionary.forEach { key, value in
                guard let beaconCodeSeed = BeaconCodeSeed(key), let rawValue = Int(value), let status = Status(rawValue: rawValue) else {
                    os_log("Parse infection data failed (key=%s,value=%s)", log: self.log, type: .fault, key, value)
                    return
                }
                infectionData[beaconCodeSeed] = status
            }
            callback?(infectionData, nil)
            os_log("Get infection data successful", log: self.log, type: .debug)
        })
        task.resume()
    }

}

/// Background download manager
private class BackgroundDownload : NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    private let log = OSLog(subsystem: "org.C19X.logic", category: "BackgroundDownload")
    private var session: URLSession!
    private var isDownloading = false
    private var delegate: ((Data?, Error?) -> Void)?

    init(_ identifier: String) {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        super.init()
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }
    
    deinit {
        session.finishTasksAndInvalidate()
    }
    
    func get(_ url: URL, callback: ((Data?, Error?) -> Void)?) {
        guard !isDownloading else {
            os_log("Get failed (error=inProgress)", log: self.log, type: .fault)
            callback?(nil, NetworkError.inProgress)
            return
        }
        isDownloading = true
        delegate = callback
        let backgroundTask = session.downloadTask(with: url)
        backgroundTask.resume()
    }
    
    // MARK:- URLSessionDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let data = try? Data(NSData(contentsOfFile: location.path)) {
            delegate?(data, nil)
        } else {
            delegate?(nil, NetworkError.invalidResponse)
        }
        try? FileManager.default.removeItem(at: location)
        isDownloading = false
        delegate = nil
    }
}

enum NetworkError: Error {
    case unregistered
    case inProgress
    case encryptionFailure
    case invalidRequest
    case invalidResponse
}
