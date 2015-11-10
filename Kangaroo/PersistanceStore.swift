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

final
class PersistanceStore: NSIncrementalStore {
    var storage: IncrementalStorageProtocol {
        guard let storage = PersistanceStoreRegistry.sharedInstance.store else {
            assertionFailure("Persistance store does not storage implementation")
            abort()
        }
        return storage
    }
    
    // Only for predicates
    var correspondenceTable = [String: String]()
    
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
        return try requestHandler(request, context!)!
    }
    
    private func requestHandlerForType(requestType: NSPersistentStoreRequestType) -> ((NSPersistentStoreRequest, NSManagedObjectContext) throws -> AnyObject?) {
        switch requestType {
        case .FetchRequestType: return executeFetchRequest
        case .SaveRequestType: return executeSaveRequest
        case .BatchDeleteRequestType, .BatchUpdateRequestType:
            assertionFailure("Batch updates for deletion and update are not handled now")
            abort()
        }
    }
    
    private func getPredicateWithTranslatedIds(basicPredicate: NSPredicate) -> NSPredicate {
        var wordsOfPredicate = basicPredicate.predicateFormat.componentsSeparatedByString(" ")
        for i in 0...wordsOfPredicate.count-2 {
            let objectIdDescription = wordsOfPredicate[i...i+1].joinWithSeparator(" ")
            if let key = correspondenceTable[objectIdDescription] {
                wordsOfPredicate.removeAtIndex(i)
                wordsOfPredicate[i] = key
            }
        }
        return self.storage.predicateProcessing(wordsOfPredicate.joinWithSeparator(" "))
    }
    
    func createObjects(entityName: String, context: NSManagedObjectContext, identifiers: [String]) -> [AnyObject] {
        let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context)!
        return identifiers.map { key in
            let objectID = self.newObjectIDForEntity(entityDescription, referenceObject: key)
            self.correspondenceTable[objectID.description] = key
            return context.objectWithID(objectID)
        }
    }
    
    func executeFetchRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) throws -> AnyObject? {
        guard let fr = request as? NSFetchRequest, entityName = fr.entityName else {
            return nil
        }

        var predicateForStorage = fr.predicate
        if let predicate = fr.predicate {
            predicateForStorage = getPredicateWithTranslatedIds(predicate)
        }
        let fetchedIDs: [String] = storage.fetchRecordIDs(entityName, predicate: predicateForStorage, sortDescriptors: fr.sortDescriptors)
        return createObjects(entityName, context: context, identifiers: fetchedIDs)
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
    
    func executeSaveRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) throws -> AnyObject? {
        guard let saveRequest = request as? NSSaveChangesRequest else {
            return nil
        }

        if let objectsForSave = saveRequest.insertedObjects {
            for newObject in objectsForSave {
                let attributes = self.objectDictionaryOfAttributes(newObject)
                let relations = self.objectDictionaryOfRelationShips(newObject)
                let key = objectStorageID(newObject)
                try storage.saveRecord(key, dictOfAttribs: attributes, dictOfRelats: relations)
            }
        }
        if let objectsForUpdate = saveRequest.updatedObjects {
            for updatedObject in objectsForUpdate {
                let key = objectStorageID(updatedObject)
                let attributes = self.objectDictionaryOfAttributes(updatedObject)
                let relations = self.objectDictionaryOfRelationShips(updatedObject)
                try storage.updateRecord(updatedObject, key: key, dictOfAttribs: attributes, dictOfRelats: relations)
            }
        }
        if let objectsForDelete = saveRequest.deletedObjects {
            for deletedObject in objectsForDelete {
                try storage.deleteRecord(deletedObject, key: objectStorageID(deletedObject))
            }
        }
        return []
    }
    
    func executeBatchUpdateRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        return nil
    }
}
