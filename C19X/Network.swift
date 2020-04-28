//
//  Network.swift
//  C19X
//
//  Created by Freddy Choi on 23/04/2020.
//  Copyright © 2020 Freddy Choi. All rights reserved.
//

import Foundation
import CryptoKit

public class Network {
    private var server: String = "https://appserver-test.c19x.org/"
    // Time data
    private var timeDelta: Int64 = 0
    // Registration data
    public var serialNumber: Int64?
    public var sharedSecret: Data?
    // Device data
    public var status: Int = 0
    public var message: String?
    public var parameters: [String: String]?
    public var lookup: Data?
    public var listeners: [NetworkListener] = []

    init() {
        getRegistration()
        runDailyTasksAndScheduleAgain()
    }
    
    @objc private func runDailyTasksAndScheduleAgain() {
        debugPrint("Running daily tasks")
        // Tasks
        getTimeFromServerAndSynchronise()
        getParameters()
        getLookupInBackground()

        // Schedule again
//        let hour = 60 * 60
//        let midnight = ((Int(Date().timeIntervalSince1970.rounded()) / (24 * 60)) + 1) * (24 * 60)
//        let downloadTime = midnight + Int.random(in: (1 * hour) ... (5 * hour))
//        let date = Date(timeIntervalSince1970: Double(downloadTime))
        let date = Date().addingTimeInterval(60)
        let timer = Timer(fireAt: date, interval: 0, target: self, selector: #selector(runDailyTasksAndScheduleAgain), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
    }
    
    // Get time and adjust delta to synchronise with server
    private func getTimeFromServerAndSynchronise() {
        let url = URL(string: server + "time")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, let dataString = String(bytes: data!, encoding: .utf8) {
                if (httpResponse.statusCode == 200) {
                    let serverTime = Int64(dataString)!
                    let clientTime = Int64(NSDate().timeIntervalSince1970 * 1000)
                    self.timeDelta = clientTime - serverTime
                    debugPrint("Get time (serverTime=\(serverTime),clientTime=\(clientTime),timeDelta=\(self.timeDelta))")
                    return
                }
            }
            debugPrint("Get time failed")
        })
        task.resume()
    }
    
    // Get timestamp that is synchronised with server
    public func getTimestamp() -> Int64 {
        Int64(NSDate().timeIntervalSince1970 * 1000) + timeDelta
    }
    
    // Get registration serial number and key
    private func getRegistration() {
        let serialNumber = Keychain.get(key: "serialNumber")
        let sharedSecret = Keychain.get(key: "sharedSecret")
        if (serialNumber != nil && sharedSecret != nil) {
            self.serialNumber = Int64(serialNumber!)!
            self.sharedSecret = Data(base64Encoded: sharedSecret!)!
            debugPrint("Get registration from keychain (serialNumber=\(self.serialNumber!))")
            for listener in listeners {
                listener.networkListenerDidUpdate(serialNumber: self.serialNumber!, sharedSecret: self.sharedSecret!)
            }
        } else {
            let url = URL(string: server + "registration")
            let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
                if error == nil, let httpResponse = response as? HTTPURLResponse, let dataString = String(bytes: data!, encoding: .utf8) {
                    if (httpResponse.statusCode == 200) {
                        let values = dataString.components(separatedBy: ",")
                        self.serialNumber = Int64(values[0])!
                        self.sharedSecret = Data(base64Encoded: values[1])!
                        debugPrint("Get registration (serialNumber=\(self.serialNumber!))")
                        if Keychain.put(key: "serialNumber", value: values[0]), Keychain.put(key: "sharedSecret", value: values[1]) {
                            debugPrint("Put keychain (serialNumber=\(self.serialNumber!))")
                            for listener in self.listeners {
                                listener.networkListenerDidUpdate(serialNumber: self.serialNumber!, sharedSecret: self.sharedSecret!)
                            }
                        }
                        return
                    }
                }
                debugPrint("Get registration failed")
                for listener in self.listeners {
                    listener.networkListenerFailedUpdate(serialNumber: self.serialNumber)
                }
            })
            task.resume()
        }
    }
    
    // Post status
    public func postStatus(_ status: Int) {
        let string = String(getTimestamp()) + "," + String(status)
        let encrypted = AES.encrypt(key: sharedSecret, string: string)!.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
        let url = URL(string: server + "status?key=" + String(serialNumber!) + "&value=" + encrypted)
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let dataString = String(bytes: data!, encoding: .utf8) {
                    debugPrint("Post status (serialNumber=\(self.serialNumber!),status=\(dataString))")
                    self.status = Int(dataString) ?? 0
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(status: self.status)
                    }
                    return
                }
            }
            debugPrint("Post status failed")
            for listener in self.listeners {
                listener.networkListenerFailedUpdate(status: self.status)
            }
        })
        task.resume()
    }
    
    // Get device specific message
    public func getMessage() {
        let string = String(getTimestamp())
        let encrypted = AES.encrypt(key: sharedSecret, string: string)!.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
        let url = URL(string: server + "message?key=" + String(serialNumber!) + "&value=" + encrypted)
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200, let message = String(bytes: data!, encoding: .utf8) {
                    debugPrint("Get message (serialNumber=\(self.serialNumber!),message=\(message))")
                    self.message = message
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(message: self.message!)
                    }
                    return
                }
            }
            debugPrint("Get message failed")
        })
        task.resume()
    }
    
    // Get lookup table immediately
    private func getLookupImmediately() {
        let url = URL(string: server + "lookup")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if (httpResponse.statusCode == 200) {
                    let lookup = data
                    self.lookup = lookup;
                    debugPrint("Get lookup (lookup=\(lookup!.count))")
                    for listener in self.listeners {
                        listener.networkListenerDidUpdate(lookup: self.lookup!)
                    }
                    return
                }
            }
            debugPrint("Get lookup failed")
        })
        task.resume()
    }
    
    // Get lookup table in background
    private func getLookupInBackground(callback: ((Data?) -> Void)? = nil) {
        let url = URL(string: server + "lookup")!
        
        let fileUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(url.lastPathComponent)
        if FileManager().fileExists(atPath: fileUrl.path) {
            try? FileManager().removeItem(atPath: fileUrl.path)
        }
        
        let downloadManager = DownloadManager()
        downloadManager.set() { data in
            if data != nil {
                self.lookup = data
                debugPrint("Get lookup (lookup=\(self.lookup!.count))")
                for listener in self.listeners {
                    listener.networkListenerDidUpdate(lookup: self.lookup!)
                }
            } else {
                debugPrint("Get lookup failed")
            }
        }
        let backgroundTask = downloadManager.session.downloadTask(with: url)
        backgroundTask.countOfBytesClientExpectsToSend = 200
        backgroundTask.countOfBytesClientExpectsToReceive = 4194304
        backgroundTask.resume()
    }
    
    // Get application parameters
    private func getParameters(callback: (([String: String]?) -> Void)? = nil) {
        let url = URL(string: server + "parameters")
        let task = URLSession.shared.dataTask(with: url!, completionHandler: { data, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let json = try? JSONSerialization.jsonObject(with: data!, options: [])
                    if let dictionary = json as? [String: String] {
                        self.parameters = dictionary
                        debugPrint("Get parameters (parameters=\(self.parameters!))")
                        for listener in self.listeners {
                            listener.networkListenerDidUpdate(parameters: self.parameters!)
                        }
                        return
                    }
                }
            }
            debugPrint("Get parameters failed")
        })
        task.resume()
    }
}

// Download manager for background download of lookup table
private class DownloadManager : NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    static var shared = DownloadManager()
    private var callback: ((Data?) -> Void)?

    var session : URLSession {
        get {
            let config = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).background")
            config.isDiscretionary = true
            config.sessionSendsLaunchEvents = true
            return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        }
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

public protocol NetworkListener: AnyObject {
    func networkListenerDidUpdate(serialNumber:Int64, sharedSecret:Data)

    func networkListenerFailedUpdate(serialNumber:Int64?)

    func networkListenerDidUpdate(status:Int)
    
    func networkListenerFailedUpdate(status:Int?)

    func networkListenerDidUpdate(message:String)

    func networkListenerDidUpdate(parameters:[String: String])

    func networkListenerDidUpdate(lookup:Data)

}
