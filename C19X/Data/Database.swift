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
    var delegates: [DatabaseDelegate] { get set }
    
    /**
     Add new contact record.
     */
    func add(_ contact: Contact)
    
    /**
     Remove all database records before given date.
     */
    func remove(_ before: Date)

    /**
     Add new event.
     */
    func add(_ event: String)
}

protocol DatabaseDelegate {
    
    func database(added: Contact)
    
    func database(changed: [Contact])
}

class ConcreteDatabase: Database, ReceiverDelegate {
    private let log = OSLog(subsystem: "org.c19x.data", category: "Database")
    private var persistentContainer: NSPersistentContainer

    private var lock = NSLock()
    var contacts: [Contact] = []
    var delegates: [DatabaseDelegate] = []

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
        loadContacts()
        loadEvents()
        //deleteEvents()
    }
    
    func add(_ contact: Contact) {
        os_log("Add (contact=%s)", log: self.log, type: .debug, contact.description)
        lock.lock()
        let managedContext = persistentContainer.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "Contact", in: managedContext)!
        let object = NSManagedObject(entity: entity, insertInto: managedContext)
        object.setValue(contact.time, forKey: "time")
        object.setValue(Int64(contact.code), forKey: "code")
        object.setValue(Int32(contact.rssi), forKey: "rssi")
        do {
            try managedContext.save()
            contacts.append(contact)
            os_log("Added (contact=%s)", log: self.log, type: .debug, contact.description)
            for delegate in delegates {
                delegate.database(added: contact)
            }
        } catch let error as NSError {
            os_log("Add failed (contact=%s)", log: self.log, type: .fault, contact.description, error.description)
        }
        lock.unlock()
    }
    
    func add(_ event: String) {
//        //os_log("Add (event=%s)", log: self.log, type: .debug, event.description)
//        do {
//            let managedContext = persistentContainer.viewContext
//            let object = NSEntityDescription.insertNewObject(forEntityName: "Event", into: managedContext)
//            object.setValue(Date(), forKey: "time")
//            object.setValue(event, forKey: "event")
//            try managedContext.save()
//            //os_log("Added (event=%s)", log: log, type: .debug, event.description)
//        } catch let error as NSError {
//            os_log("Add failed (event=%s)", log: self.log, type: .fault, event.description, error.description)
//        }
    }
    
    func remove(_ before: Date) {
        os_log("Remove (before=%s)", log: self.log, type: .debug, before.description)
        lock.lock()
        let managedContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Contact")
        do {
            let objects: [Contact] = try managedContext.fetch(fetchRequest) as! [Contact]
            objects.forEach() { o in
                if let time = o.value(forKey: "time") as? Date {
                    if (time.compare(before) == .orderedAscending) {
                        managedContext.delete(o)
                    }
                }
            }
            try managedContext.save()
            loadContacts()
            os_log("Removed (before=%s)", log: self.log, type: .debug, before.description)
            for delegate in delegates {
                delegate.database(changed: contacts)
            }
        } catch let error as NSError {
            os_log("Remove failed (error=%s)", log: self.log, type: .fault, error.description)
        }
        lock.unlock()
    }
    
    private func loadContacts() {
        os_log("Load contacts", log: self.log, type: .debug)
        let managedContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<Contact>(entityName: "Contact")
        do {
            self.contacts = try managedContext.fetch(fetchRequest)
            os_log("Loaded contacts (count=%d)", log: self.log, type: .debug, self.contacts.count)
            for delegate in delegates {
                delegate.database(changed: self.contacts)
            }
        } catch let error as NSError {
            os_log("Load contacts failed (error=%s)", log: self.log, type: .fault, error.description)
        }
    }

    private func deleteEvents() {
        os_log("Delete events", log: self.log, type: .debug)
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
        let managedContext = persistentContainer.viewContext
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        do {
            if let batchDeleteResult = try managedContext.execute(deleteRequest) as? NSBatchDeleteResult {
                os_log("Deleted events (result=%s)", log: self.log, type: .debug, batchDeleteResult.description)
            }
        } catch let error as NSError {
            os_log("Delete failed (error=%s)", log: self.log, type: .fault, error.description)
        }
    }
    
    private func loadEvents() {
        os_log("Load events", log: self.log, type: .debug)
        let fetchRequest = NSFetchRequest<Event>(entityName: "Event")
        let managedContext = persistentContainer.viewContext
        do {
            let records = try managedContext.fetch(fetchRequest)
            os_log("Loaded events (count=%d)", log: self.log, type: .debug, records.count)
            records.forEach() { event in
                debugPrint(event.time!.description + "," + event.event!)
            }
        } catch let error as NSError {
            os_log("Load failed (error=%s)", log: self.log, type: .fault, error.description)
        }
    }

    // MARK:- ReceiverDelegate
    
    func receiver(didDetect: BeaconCode, rssi: RSSI) {
//        let contact = C19XContact(time: Date(), code: didDetect, rssi: rssi)
//        add(contact)
    }
}
