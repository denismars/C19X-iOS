//
//  Network.swift
//  C19X
//
//  Created by Freddy Choi on 23/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import CryptoKit
import os

class Network {
    private let log = OSLog(subsystem: "org.C19X", category: "Network")
    private var server: String?
    private var timeDelta: Int64 = 0
    private var getLookupInBackgroundInProgress = false
    public var listeners: [NetworkListener] = []
        
    func set(server: String) {
        self.server = server
    }
    
    // Get time and adjust delta to synchronise with server
    public func getTimeFromServerAndSynchronise(_ callback: ((Bool) -> Void)? = nil) {
        os_log("Synchronise time request", log: self.log, type: .debug)
        guard let server = server, let url = URL(string: server + "time") else {
            os_log("Synchronise time failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        os_log("Synchronise time request (url=%s)", log: self.log, type: .debug, url.description)
        let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let dataString = String(bytes: data!, encoding: .utf8) {
                if (httpResponse.statusCode == 200) {
                    let serverTime = Int64(dataString)!
                    let clientTime = Int64(NSDate().timeIntervalSince1970 * 1000)
                    self.timeDelta = clientTime - serverTime
                    os_log("Synchronised time with server (delta=%d)", log: self.log, type: .debug, self.timeDelta)
                    if callback != nil {
                        callback!(true)
                    }
                    return
                }
            }
            os_log("Synchronise time failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            if callback != nil {
                callback!(false)
            }
        })
        task.resume()
    }
    
    // Get timestamp that is synchronised with server
    public func getTimestamp() -> Int64 {
        Int64(NSDate().timeIntervalSince1970 * 1000) + timeDelta
    }
    
    // Get registration serial number and key
    public func getRegistration(callback: ((Bool) -> Void)? = nil) {
        os_log("Registration request", log: self.log, type: .debug)
        guard let server = server, let url = URL(string: server + "registration") else {
            os_log("Registration failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let dataString = String(bytes: data!, encoding: .utf8) {
                if (httpResponse.statusCode == 200) {
                    let values = dataString.components(separatedBy: ",")
                    if let serialNumber = UInt64(values[0]), let sharedSecret = Data(base64Encoded: values[1]) {
                        os_log("Registration successful (serialNumber=%u)", log: self.log, type: .debug, serialNumber)
                        for listener in self.listeners {
                            listener.networkListenerDidUpdate(serialNumber: serialNumber, sharedSecret: sharedSecret)
                        }
                        if callback != nil {
                            callback!(true)
                        }
                        return
                    }
                }
            }
            os_log("Registration failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            for listener in self.listeners {
                listener.networkListenerFailedUpdate(registrationError: error)
            }
            if callback != nil {
                callback!(false)
            }
        })
        task.resume()
    }
    
    // Post status
    func postStatus(_ status: Int, device:Device, callback: ((Bool) -> Void)? = nil) {
        os_log("Post status request (status=%u)", log: self.log, type: .debug, status)
        guard let server = server else {
            os_log("Post status failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        let (_, rssiHistogram, timeHistogram) = device.riskAnalysis.analyse(contactRecords: device.contactRecords, lookup: device.lookup)
        let string = String(getTimestamp()) + "|" + String(status) + "|" + rssiHistogram.description + "|" + timeHistogram.description
        os_log("Post status (string=%s)", log: self.log, type: .fault, string)
        let encrypted = AES.encrypt(key: device.sharedSecret, string: string)!.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
        let url = URL(string: server + "status?key=" + String(device.serialNumber) + "&value=" + encrypted)
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let dataString = String(bytes: data!, encoding: .utf8), let status = Int(dataString) {
                    os_log("Post status successful (status=%u)", log: self.log, type: .debug, status)
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(status: status)
                    }
                    if callback != nil {
                        callback!(true)
                    }
                    return
                }
            }
            os_log("Post status failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            for listener in self.listeners {
                listener.networkListenerFailedUpdate(statusError: error)
            }
            if callback != nil {
                callback!(false)
            }
        })
        task.resume()
    }
    
    // Get device specific message
    public func getMessage(serialNumber: UInt64, sharedSecret: Data, callback: ((Bool) -> Void)? = nil) {
        os_log("Get message request", log: self.log, type: .debug)
        guard let server = server else {
            os_log("Get message failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        let string = String(getTimestamp())
        let encrypted = AES.encrypt(key: sharedSecret, string: string)!.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
        let url = URL(string: server + "message?key=" + String(serialNumber) + "&value=" + encrypted)
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let message = String(bytes: data!, encoding: .utf8) {
                    os_log("Get message successful (message=%s)", log: self.log, type: .debug, message)
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(message: message)
                    }
                    if callback != nil {
                        callback!(true)
                    }
                    return
                }
            }
            os_log("Get message failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            if callback != nil {
                callback!(false)
            }
        })
        task.resume()
    }
    
    // Get lookup table immediately
    public func getLookupImmediately(callback: ((Bool) -> Void)? = nil) {
        os_log("Get lookup immediately request", log: self.log, type: .debug)
        guard let server = server else {
            os_log("Get lookup immediately failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        let url = URL(string: server + "lookup")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let lookup = data {
                if (httpResponse.statusCode == 200) {
                    os_log("Get lookup immediately successful (bytes=%u)", log: self.log, type: .debug, lookup.count)
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(lookup: lookup)
                    }
                    if callback != nil {
                        callback!(true)
                    }
                    return
                }
            }
            os_log("Get lookup immediately failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            if callback != nil {
                callback!(false)
            }
        })
        task.resume()
    }
    
    
    
    // Get lookup table in background
    public func getLookupInBackground(callback: ((Bool) -> Void)? = nil) {
        os_log("Get lookup in background request", log: self.log, type: .debug)
        guard let server = server else {
            os_log("Get lookup in background failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        guard !getLookupInBackgroundInProgress else {
            os_log("Get lookup in background in progress, skipping request", log: self.log, type: .debug)
            return
        }
        getLookupInBackgroundInProgress = true
        let url = URL(string: server + "lookup")!
        DownloadManager.shared.set() { data in
            if let lookup = data {
                os_log("Get lookup in background successful (bytes=%u)", log: self.log, type: .debug, lookup.count)
                for listener in self.listeners {
                    listener.networkListenerDidUpdate(lookup: lookup)
                }
                if callback != nil {
                    callback!(true)
                }
            } else {
                os_log("Get lookup in background failed", log: self.log, type: .fault)
                if callback != nil {
                    callback!(false)
                }
            }
            self.getLookupInBackgroundInProgress = false
        }
        let backgroundTask = DownloadManager.shared.session.downloadTask(with: url)
        backgroundTask.countOfBytesClientExpectsToSend = 200
        backgroundTask.countOfBytesClientExpectsToReceive = 67108864 / 8
        backgroundTask.resume()
    }
    
    // Get application parameters
    public func getParameters(callback: ((Bool) -> Void)? = nil) {
        os_log("Get parameters request", log: self.log, type: .debug)
        guard let server = server else {
            os_log("Get parameters failed, server undefined", log: self.log, type: .debug)
            if callback != nil {
                callback!(false)
            }
            return
        }
        let url = URL(string: server + "parameters")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let json = try? JSONSerialization.jsonObject(with: data!, options: [])
                    if let dictionary = json as? [String: String] {
                        os_log("Get parameters successful (parameters=%s)", log: self.log, type: .debug, String(describing: dictionary))
                        for listener in self.listeners {
                            listener.networkListenerDidUpdate(parameters: dictionary)
                        }
                        if callback != nil {
                            callback!(true)
                        }
                        return
                    }
                }
            }
            os_log("Get parameters failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            if callback != nil {
                callback!(false)
            }
        })
        task.resume()
    }
}

// Download manager for background download of lookup table
private class DownloadManager : NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static var shared = DownloadManager()
    private var callback: ((Data?) -> Void)?
    public var session : URLSession!
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "C19XBackgroundDownloadManager")
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
    }
    
    deinit {
        session.finishTasksAndInvalidate()
    }
    
    func set(callback: ((Data?) -> Void)? = nil) {
        self.callback = callback
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if callback != nil {
            let data = try? Data(NSData(contentsOfFile: location.path))
            callback!(data)
        }
        try? FileManager.default.removeItem(at: location)
    }
}

public protocol NetworkListener {
    func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data)

    func networkListenerFailedUpdate(registrationError:Error?)

    func networkListenerDidUpdate(status:Int)
    
    func networkListenerFailedUpdate(statusError:Error?)

    func networkListenerDidUpdate(message:String)

    func networkListenerDidUpdate(parameters:[String:String])

    func networkListenerDidUpdate(lookup:Data)

}

public class AbstractNetworkListener: NetworkListener {
    public func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {}

    public func networkListenerFailedUpdate(registrationError:Error?) {}

    public func networkListenerDidUpdate(status:Int) {}
    
    public func networkListenerFailedUpdate(statusError:Error?) {}

    public func networkListenerDidUpdate(message:String) {}

    public func networkListenerDidUpdate(parameters:[String:String]) {}

    public func networkListenerDidUpdate(lookup:Data) {}
}
