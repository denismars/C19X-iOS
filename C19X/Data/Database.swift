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
    var records: [DatabaseRecord] { get }
    var delegates: [DatabaseDelegate] { get set }
    
    /**
     Add new database record.
     */
    func add(_ newRecord: DatabaseRecord)
    
    /**
     Remove all database records before given date.
     */
    func remove(_ before: Date)
}

protocol DatabaseDelegate {
    
    func database(addedRecord: DatabaseRecord)
    
    func database(changedRecords: [DatabaseRecord])
}

class ConcreteDatabase: Database, ReceiverDelegate {
    private let log = OSLog(subsystem: "org.c19x.data", category: "Database")
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "C19X")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()
    private var lock = NSLock()
    var records: [DatabaseRecord] = []
    var delegates: [DatabaseDelegate] = []

    init() {
        load()
    }
    
    func add(_ newRecord: DatabaseRecord) {
        os_log("Add (newRecord=%s)", log: self.log, type: .debug, newRecord.description)
        lock.lock()
        let managedContext = persistentContainer.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "Record", in: managedContext)!
        let object = NSManagedObject(entity: entity, insertInto: managedContext)
        object.setValue(newRecord.time, forKey: "time")
        object.setValue(Int64(newRecord.code), forKey: "code")
        object.setValue(Int32(newRecord.rssi), forKey: "rssi")
        do {
            try managedContext.save()
            records.append(newRecord)
            os_log("Added (newRecord=%s)", log: self.log, type: .debug, newRecord.description)
            for delegate in delegates {
                delegate.database(addedRecord: newRecord)
            }
        } catch let error as NSError {
            os_log("Add failed (newRecord=%s)", log: self.log, type: .fault, newRecord.description, error.description)
        }
        lock.unlock()
    }
    
    func remove(_ before: Date) {
        os_log("Remove (before=%s)", log: self.log, type: .debug, before.description)
        lock.lock()
        let managedContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Record")
        do {
            let objects: [NSManagedObject] = try managedContext.fetch(fetchRequest)
            objects.forEach() { o in
                if let time = o.value(forKey: "time") as? Date {
                    if (time.compare(before) == .orderedAscending) {
                        managedContext.delete(o)
                    }
                }
            }
            try managedContext.save()
            load()
            os_log("Removed (before=%s)", log: self.log, type: .debug, before.description)
            for delegate in delegates {
                delegate.database(changedRecords: records)
            }
        } catch let error as NSError {
            os_log("Remove failed (error=%s)", log: self.log, type: .fault, error.description)
        }
        lock.unlock()
    }
    
    private func load() {
        os_log("Load", log: self.log, type: .debug)
        let managedContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Record")
        do {
            let objects: [NSManagedObject] = try managedContext.fetch(fetchRequest)
            var records: [DatabaseRecord] = []
            objects.forEach() { o in
                if let time = o.value(forKey: "time") as? Date,
                   let code = o.value(forKey: "code") as? Int64,
                   let rssi = o.value(forKey: "rssi") as? Int32 {
                    records.append(DatabaseRecord(time: time, code: BeaconCode(code), rssi: RSSI(rssi)))
                }
            }
            self.records = records
            os_log("Loaded (recordCount=%d)", log: self.log, type: .debug, records.count)
            for delegate in delegates {
                delegate.database(changedRecords: records)
            }
        } catch let error as NSError {
            os_log("Load failed (error=%s)", log: self.log, type: .fault, error.description)
        }
    }
    
    // MARK:- ReceiverDelegate
    
    func receiver(didDetect: BeaconCode, rssi: RSSI) {
        let databaseRecord = DatabaseRecord(time: Date(), code: didDetect, rssi: rssi)
        add(databaseRecord)
    }
}

struct DatabaseRecord {
    let time: Date
    let code: BeaconCode
    let rssi: RSSI
    var description: String { get { "time=" + time.description + ",code=" + code.description + ",rssi=" + rssi.description } }
}
