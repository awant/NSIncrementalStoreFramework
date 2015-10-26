//
//  PersistanceStore.swift
//  ResultsFetcher
//
//  Created by Artemiy Sobolev on 11.08.15.
//  Copyright (c) 2015 Artemiy Sobolev. All rights reserved.
//

import Foundation
import CoreData

public
class PersistanceStoreRegistry {
    static let sharedInstance = PersistanceStoreRegistry()
    var store: IncrementalStorageProtocol?
    public class func register(store: IncrementalStorageProtocol, coordinator: NSPersistentStoreCoordinator, fileURL: NSURL) throws {
        PersistanceStoreRegistry.sharedInstance.store = store
        do {
            try coordinator.addPersistentStoreWithType(PersistanceStore.type, configuration: nil, URL: fileURL, options: nil)
        } catch let error as NSError {
            throw error
        }
    }
}


class PersistanceStore: NSIncrementalStore {
    var storage: IncrementalStorageProtocol {
        guard let storage = PersistanceStoreRegistry.sharedInstance.store else {
            assertionFailure("Persistance store does not storage implementation")
            abort()
        }
        return storage
    }
    
    var correspondenceTable = [String: NSManagedObjectID]()
    
    override class func initialize() {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    class var type: String {
        return NSStringFromClass(self)
    }
    
    override func loadMetadata() throws {
        self.metadata = [NSStoreUUIDKey : NSProcessInfo().globallyUniqueString,  NSStoreTypeKey : self.dynamicType.type]
    }
    
    override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        var values = [String : AnyObject]()
        let key: String = self.referenceObjectForObjectID(objectID) as! String
        for property in objectID.entity.properties {
            if let fieldProperty = property as? NSAttributeDescription {
                values[fieldProperty.name] = self.storage.valueAndVersion(key, fromField: fieldProperty.name)
            }
        }
        return NSIncrementalStoreNode(objectID: objectID, withValues: values, version: 1)
    }
    
    override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        let key = self.storage.getKeyOfDestFrom(self.referenceObjectForObjectID(objectID) as! String, to: relationship.name)
        let objectID = self.newObjectIDForEntity(relationship.destinationEntity!, referenceObject: key!)
        return  objectID
    }
    
    override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        let requestHandler = requestHandlerForType(request.requestType)
        return requestHandler!(request, context!)!
    }
    
    func requestHandlerForType(requestType: NSPersistentStoreRequestType) -> ((NSPersistentStoreRequest, NSManagedObjectContext) -> AnyObject?)? {
        switch requestType {
        case .FetchRequestType: return self.executeFetchRequest
        case .SaveRequestType: return self.executeSaveRequest
        case .BatchUpdateRequestType: return self.executeBatchUpdateRequest
        default: return nil
        }
    }
    
    func executeFetchRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        guard let entityName = (request as? NSFetchRequest)?.entityName else {
            return nil
        }
        var relatedEntitiesNames: [String]?
        guard let properties = (request as? NSFetchRequest)?.entity?.properties else {
            return nil
        }
        relatedEntitiesNames = [String]()
        for property in properties {
            if let relProperty = property as? NSRelationshipDescription {
                relatedEntitiesNames!.append(relProperty.name)
            }
        }
        guard let sD = (request as? NSFetchRequest)?.sortDescriptors else {
            return nil
        }
        // work with context
        let managedObjectsCreator: (String, [AnyObject]?) -> AnyObject = { (name, keys) in
            let entityDescription = NSEntityDescription.entityForName(name, inManagedObjectContext: context)!
            if let keys = keys {
                let returningObjects = keys.map { (let key) -> NSManagedObject in
                    let objectID = self.newObjectIDForEntity(entityDescription, referenceObject: key)
                    return context.objectWithID(objectID)
                }
                return returningObjects
            }
            return []
        }
        
        return self.storage.fetchRecords(entityName, relatedEntitiesNames: relatedEntitiesNames, sortDescriptors: sD, newEntityCreator: managedObjectsCreator)
    }
    
    override func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        var permanentIDs = [NSManagedObjectID]()
        for managedObject in array {
            let objectID = self.newObjectIDForEntity(managedObject.entity, referenceObject: self.storage.getKeyOfNewObjectWithEntityName(managedObject.entity.name!))
            permanentIDs.append(objectID)
        }
        return permanentIDs
    }
    
    func executeSaveRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        var dictOfAttribs: [String:AnyObject]?
        var dictOfRelats: [String:[String]]?
        
        if let objectsForSave = (request as! NSSaveChangesRequest).insertedObjects {
            for newObject in objectsForSave {
                dictOfAttribs = [String:AnyObject]()
                dictOfRelats = [String:[String]]()
                let key = self.referenceObjectForObjectID(newObject.objectID) as! String
                for property in newObject.entity.properties {
                    if let relProperty = property as? NSRelationshipDescription {
                        dictOfRelats![relProperty.name] =
                            newObject.objectIDsForRelationshipNamed(relProperty.name).map { (let objectID) -> String in
                                return (self.referenceObjectForObjectID(objectID) as! String)
                        }
                    } else if let attribProperty = property as? NSAttributeDescription {
                        dictOfAttribs![attribProperty.name] = newObject.valueForKey(attribProperty.name)
                    }
                }
                self.storage.saveRecord(key, dictOfAttribs: dictOfAttribs!, dictOfRelats: dictOfRelats!)
            }
        }
        if let objectsForUpdate = (request as! NSSaveChangesRequest).updatedObjects {
            for updatedObject in objectsForUpdate {
                self.storage.updateRecord(updatedObject, key: self.referenceObjectForObjectID(updatedObject.objectID) as! String)
            }
        }
        if let objectsForDelete = (request as! NSSaveChangesRequest).deletedObjects {
            for deletedObject in objectsForDelete {
                self.storage.deleteRecord(deletedObject, key: self.referenceObjectForObjectID(deletedObject.objectID) as! String)
            }
        }
        return []
    }
    
    func executeBatchUpdateRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        return nil
    }
}
