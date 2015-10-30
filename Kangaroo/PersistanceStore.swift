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
                values[fieldProperty.name] = storage.valueAndVersion(key, fromField: fieldProperty.name)
            }
        }
        return NSIncrementalStoreNode(objectID: objectID, withValues: values, version: 1)
    }
    
    override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        if relationship.toMany {
            let keys = storage.getKeyOfDestFrom(self.referenceObjectForObjectID(objectID) as! String, to: relationship.name) as! [AnyObject]
            return keys.map({ self.newObjectIDForEntity(relationship.destinationEntity!, referenceObject: $0) } )
        } else {
            let key = storage.getKeyOfDestFrom(self.referenceObjectForObjectID(objectID) as! String, to: relationship.name)
            return self.newObjectIDForEntity(relationship.destinationEntity!, referenceObject: key)
        }
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
        guard let fr = request as? NSFetchRequest, entityName = fr.entityName,  properties = fr.entity?.properties else {
            return nil
        }

        let relatedEntitiesNames = properties.filter({ $0 as? NSRelationshipDescription != nil }).map({ $0.name })

        // work with context
        let managedObjectsCreator: [String] -> [AnyObject] = { keys in
            let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context)!
            return keys.map { key in
                let objectID = self.newObjectIDForEntity(entityDescription, referenceObject: key)
                return context.objectWithID(objectID)
            }
        }
        
        return storage.fetchRecords(entityName, relatedEntitiesNames: relatedEntitiesNames, predicate: fr.predicate, sortDescriptors: fr.sortDescriptors, newEntityCreator: managedObjectsCreator)
    }
    
    override func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        var permanentIDs = [NSManagedObjectID]()
        for managedObject in array {
            let objectID = self.newObjectIDForEntity(managedObject.entity, referenceObject: self.storage.getKeyOfNewObjectWithEntityName(managedObject.entity.name!))
            permanentIDs.append(objectID)
        }
        return permanentIDs
    }
    
    func objectStorageID(object: NSManagedObject) -> String {
        return referenceObjectForObjectID(object.objectID) as! String
    }
    
    func objectDictionaryOfRelationShips(object: NSManagedObject) -> [String : [String]] {
        let relationShipProperties = object.entity.properties.filter({ $0 as? NSRelationshipDescription != nil })
        return relationShipProperties.reduce([String : [String]]()) { (var previousValue, property) in
            previousValue[property.name] = object.objectIDsForRelationshipNamed(property.name).map {
                self.referenceObjectForObjectID($0) as! String
            }
            return previousValue
        }
    }
    
    func objectDictionaryOfAttributes(object: NSManagedObject) -> [String : AnyObject] {
        let attributes = object.entity.properties.filter({ $0 as? NSAttributeDescription != nil })
        return attributes.reduce([:]) { (var previousValue: [String : AnyObject], propertyDescription) -> [String : AnyObject] in
            if let propertyValue = object.valueForKey(propertyDescription.name) {
                previousValue[propertyDescription.name] = propertyValue
            }
            return previousValue
        }
    }
    
    func executeSaveRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        guard let saveRequest = request as? NSSaveChangesRequest else {
            return nil
        }

        if let objectsForSave = saveRequest.insertedObjects {
            for newObject in objectsForSave {
                let attributes = self.objectDictionaryOfAttributes(newObject)
                let relations = self.objectDictionaryOfRelationShips(newObject)
                let key = objectStorageID(newObject)
                storage.saveRecord(key, dictOfAttribs: attributes, dictOfRelats: relations)
            }
        }
        if let objectsForUpdate = saveRequest.updatedObjects {
            for updatedObject in objectsForUpdate {
                let key = objectStorageID(updatedObject)
                let attributes = self.objectDictionaryOfAttributes(updatedObject)
                let relations = self.objectDictionaryOfRelationShips(updatedObject)
                storage.updateRecord(updatedObject, key: key, dictOfAttribs: attributes, dictOfRelats: relations)
            }
        }
        if let objectsForDelete = saveRequest.deletedObjects {
            for deletedObject in objectsForDelete {
                storage.deleteRecord(deletedObject, key: objectStorageID(deletedObject))
            }
        }
        return []
    }
    
    func executeBatchUpdateRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        return nil
    }
}
