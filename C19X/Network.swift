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

public class Network {
    private let log = OSLog(subsystem: "org.C19X", category: "Network")
    private var server: String = "https://appserver-test.c19x.org/"
    // Time data
    private var timeDelta: Int64 = 0
    // Device data
    private var device: Device!
    public var listeners: [NetworkListener] = []

    init(device: Device) {
        self.device = device
    }
        
    // Get time and adjust delta to synchronise with server
    public func getTimeFromServerAndSynchronise() {
        os_log("Synchronised time request", log: self.log, type: .debug)
        let url = URL(string: server + "time")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let dataString = String(bytes: data!, encoding: .utf8) {
                if (httpResponse.statusCode == 200) {
                    let serverTime = Int64(dataString)!
                    let clientTime = Int64(NSDate().timeIntervalSince1970 * 1000)
                    self.timeDelta = clientTime - serverTime
                    os_log("Synchronised time with server (delta=%d)", log: self.log, type: .debug, self.timeDelta)
                    return
                }
            }
            os_log("Synchronised time with server failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        })
        task.resume()
    }
    
    // Get timestamp that is synchronised with server
    public func getTimestamp() -> Int64 {
        Int64(NSDate().timeIntervalSince1970 * 1000) + timeDelta
    }
    
    // Get registration serial number and key
    public func getRegistration() {
        os_log("Registration request", log: self.log, type: .debug)
        let url = URL(string: server + "registration")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let dataString = String(bytes: data!, encoding: .utf8) {
                if (httpResponse.statusCode == 200) {
                    let values = dataString.components(separatedBy: ",")
                    self.device.serialNumber = UInt64(values[0])!
                    self.device.sharedSecret = Data(base64Encoded: values[1])!
                    os_log("Registration successful (serialNumber=%u)", log: self.log, type: .debug, self.device.serialNumber)
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(serialNumber: self.device.serialNumber, sharedSecret: self.device.sharedSecret)
                    }
                    return
                }
            }
            os_log("Registration failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            for listener in self.listeners {
                listener.networkListenerFailedUpdate(registrationError: error)
            }
        })
        task.resume()
    }
    
    // Post status
    public func postStatus(_ status: Int) {
        os_log("Post status request (status=%u)", log: self.log, type: .debug, status)
        let string = String(getTimestamp()) + "," + String(status)
        let encrypted = AES.encrypt(key: device.sharedSecret, string: string)!.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
        let url = URL(string: server + "status?key=" + String(device.serialNumber) + "&value=" + encrypted)
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let dataString = String(bytes: data!, encoding: .utf8), let status = Int(dataString) {
                    os_log("Post status successful (status=%u)", log: self.log, type: .debug, status)
                    self.device.set(status: status)
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(status: self.device.getStatus())
                    }
                    return
                }
            }
            os_log("Post status failed (error=%s)", log: self.log, type: .fault, String(describing: error))
            for listener in self.listeners {
                listener.networkListenerFailedUpdate(statusError: error)
            }
        })
        task.resume()
    }
    
    // Get device specific message
    public func getMessage() {
        os_log("Get message request", log: self.log, type: .debug)
        let string = String(getTimestamp())
        let encrypted = AES.encrypt(key: device.sharedSecret, string: string)!.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
        let url = URL(string: server + "message?key=" + String(device.serialNumber) + "&value=" + encrypted)
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let message = String(bytes: data!, encoding: .utf8) {
                    os_log("Get message successful (message=%s)", log: self.log, type: .debug, message)
                    self.device.message = message
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(message: self.device.message)
                    }
                    return
                }
            }
            os_log("Get message failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        })
        task.resume()
    }
    
    // Get lookup table immediately
    public func getLookupImmediately() {
        os_log("Get lookup immediately request", log: self.log, type: .debug)
        let url = URL(string: server + "lookup")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let lookup = data {
                if (httpResponse.statusCode == 200) {
                    os_log("Get lookup immediately successful (bytes=%u)", log: self.log, type: .debug, lookup.count)
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(lookup: lookup)
                    }
                    return
                }
            }
            os_log("Get lookup immediately failed (error=%s)", log: self.log, type: .fault, String(describing: error))
        })
        task.resume()
    }
    
    
    
    // Get lookup table in background
    public func getLookupInBackground() {
        os_log("Get lookup in background request", log: self.log, type: .debug)
        let url = URL(string: server + "lookup")!
        DownloadManager.shared.set() { data in
            if let lookup = data {
                os_log("Get lookup in background successful (bytes=%u)", log: self.log, type: .debug, lookup.count)
                for listener in self.listeners {
                    listener.networkListenerDidUpdate(lookup: lookup)
                }
            } else {
                os_log("Get lookup in background failed", log: self.log, type: .fault)
            }
        }
        let backgroundTask = DownloadManager.shared.session.downloadTask(with: url)
        backgroundTask.countOfBytesClientExpectsToSend = 200
        backgroundTask.countOfBytesClientExpectsToReceive = 67108864 / 8
        backgroundTask.resume()
    }
    
    // Get application parameters
    public func getParameters() {
        os_log("Get parameters request", log: self.log, type: .debug)
        let url = URL(string: server + "parameters")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let json = try? JSONSerialization.jsonObject(with: data!, options: [])
                    if let dictionary = json as? [String: String] {
                        self.device.parameters.set(dictionary)
                        os_log("Get parameters successful (parameters=%s)", log: self.log, type: .debug, String(describing: dictionary))
                        for listener in self.listeners {
                            listener.networkListenerDidUpdate(parameters: self.device.parameters)
                        }
                        return
                    }
                }
            }
            os_log("Get parameters failed (error=%s)", log: self.log, type: .fault, String(describing: error))
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

    func networkListenerDidUpdate(parameters:Parameters)

    func networkListenerDidUpdate(lookup:Data)

}

public class AbstractNetworkListener: NetworkListener {
    public func networkListenerDidUpdate(serialNumber:UInt64, sharedSecret:Data) {}

    public func networkListenerFailedUpdate(registrationError:Error?) {}

    public func networkListenerDidUpdate(status:Int) {}
    
    public func networkListenerFailedUpdate(statusError:Error?) {}

    public func networkListenerDidUpdate(message:String) {}

    public func networkListenerDidUpdate(parameters:Parameters) {}

    public func networkListenerDidUpdate(lookup:Data) {}
}
