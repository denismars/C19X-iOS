//
//  ViewController.swift
//  C19X
//
//  Created by Freddy Choi on 28/04/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit

class ViewController: UIViewController, BeaconListener, NetworkListener {
    private var beacon: Beacon!
    private var network: Network!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        beacon = Beacon(serviceId: 9803801938501395, beaconCode: 1)
        beacon.listeners.append(self)
        
        network = Network()
        network.listeners.append(self)
    }
    

    internal func beaconListenerDidUpdate(beaconCode: Int64, rssi: Int) {
        debugPrint("Beacon (code=\(beaconCode),rssi=\(rssi))")
    }

    func networkListenerDidUpdate(serialNumber: Int64, sharedSecret: Data) {
        debugPrint("Network (serialNumber=\(serialNumber)")
    }
    
    func networkListenerDidUpdate(status: Int) {
        debugPrint("Network (status=\(status)")
    }
    
    func networkListenerDidUpdate(message: String) {
        debugPrint("Network (message=\(message)")
    }
    
    func networkListenerDidUpdate(parameters: [String : String]) {
        debugPrint("Network (parameters=\(parameters)")
    }
    
    func networkListenerDidUpdate(lookup: Data) {
        debugPrint("Network (lookup=\(lookup.count)")
    }
    
    func networkListenerFailedUpdate(serialNumber: Int64?) {
        debugPrint("Network failure (serialNumber=\(serialNumber)")
    }
    func networkListenerFailedUpdate(status: Int?) {
        debugPrint("Network failure (status=\(status)")
    }

}

