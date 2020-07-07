//
//  Database.swift
//  C19X
//
//  Created by Freddy Choi on 14/05/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreData
import os

protocol Database {
    var contacts: [Contact] { get }
    var batteries: [Battery] { get }
    
    /**
     Add new contact record.
     */
    func insert(time: Date, code: BeaconCode, rssi: RSSI)

    /**
     Add new battery record.
     */
    func insert(time: Date, state: BatteryState, level: BatteryLevel)

    /**
     Remove all database records before given date.
     */
    func remove(_ before: Date)
}

class ConcreteDatabase: Database {
    private let log = OSLog(subsystem: "org.c19x.data", category: "Database")
    private var persistentContainer: NSPersistentContainer

    private var lock = NSLock()
    var contacts: [Contact] = []
    var batteries: [Battery] = []

    init() {
        persistentContainer = NSPersistentContainer(name: "C19X")
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = storeDirectory.appendingPathComponent("C19X.sqlite")
        let description = NSPersistentStoreDescription(url: url)
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        persistentContainer.persistentStoreDescriptions = [description]
        persistentContainer.loadPersistentStores { description, error in
            description.options.forEach() { option in
                os_log("Loaded persistent stores (key=%s,value=%s)", log: self.log, type: .debug, option.key, option.value.description)
            }
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        load()
    }
    
    func insert(time: Date, code: BeaconCode, rssi: RSSI) {
        os_log("insert (time=%s,code=%s,rssi=%d)", log: log, type: .debug, time.description, code.description, rssi)
        lock.lock()
        do {
            let managedContext = persistentContainer.viewContext
            let object = NSEntityDescription.insertNewObject(forEntityName: "Contact", into: managedContext) as! Contact
            object.setValue(time, forKey: "time")
            object.setValue(Int64(code), forKey: "code")
            object.setValue(Int32(rssi), forKey: "rssi")
            try managedContext.save()
            contacts.append(object)
        } catch let error as NSError {
            os_log("insert failed (time=%s,code=%s,rssi=%d,error=%s)", log: log, type: .debug, time.description, code.description, rssi, error.description)
        }
        lock.unlock()
    }

    func insert(time: Date, state: BatteryState, level: BatteryLevel) {
        os_log("insert (time=%s,state=%s,level=%s)", log: log, type: .debug, time.description, state.description, level.description)
        lock.lock()
        do {
            let managedContext = persistentContainer.viewContext
            let object = NSEntityDescription.insertNewObject(forEntityName: "Battery", into: managedContext) as! Contact
            object.setValue(time, forKey: "time")
            object.setValue(state.description, forKey: "state")
            object.setValue(Float(level), forKey: "level")
            try managedContext.save()
            contacts.append(object)
        } catch let error as NSError {
            os_log("insert failed (time=%s,state=%s,level=%s,error=%s)", log: log, type: .debug, time.description, state.description, level.description, error.description)
        }
        lock.unlock()
    }

    func remove(_ before: Date) {
        os_log("remove (before=%s)", log: self.log, type: .debug, before.description)
        lock.lock()
        let managedContext = persistentContainer.viewContext
        let contactFetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Contact")
        let batteryFetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Battery")
        do {
            let contactObjects: [Contact] = try managedContext.fetch(contactFetchRequest) as! [Contact]
            contactObjects.forEach() { o in
                if let time = o.value(forKey: "time") as? Date {
                    if (time.compare(before) == .orderedAscending) {
                        managedContext.delete(o)
                    }
                }
            }
            let batteryObjects: [Battery] = try managedContext.fetch(batteryFetchRequest) as! [Battery]
            batteryObjects.forEach() { o in
                if let time = o.value(forKey: "time") as? Date {
                    if (time.compare(before) == .orderedAscending) {
                        managedContext.delete(o)
                    }
                }
            }
            try managedContext.save()
            load()
        } catch let error as NSError {
            os_log("Remove failed (error=%s)", log: self.log, type: .fault, error.description)
        }
        lock.unlock()
    }
    
    private func load() {
        os_log("Load", log: self.log, type: .debug)
        let managedContext = persistentContainer.viewContext
        let contactFetchRequest = NSFetchRequest<Contact>(entityName: "Contact")
        let batteryFetchRequest = NSFetchRequest<Battery>(entityName: "Battery")
        do {
            self.contacts = try managedContext.fetch(contactFetchRequest)
            self.batteries = try managedContext.fetch(batteryFetchRequest)
            os_log("Loaded (contacts=%d,batteries=%s)", log: self.log, type: .debug, self.contacts.count, self.batteries.count)
        } catch let error as NSError {
            os_log("Load failed (error=%s)", log: self.log, type: .fault, error.description)
        }
    }
}
