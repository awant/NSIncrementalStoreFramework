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
enum StorageCache {
    case NoCache, LocalCache
}

public
class PersistanceStoreRegistry {
    static let sharedInstance = PersistanceStoreRegistry()
    var store: IncrementalStorageProtocol?
    var coordinator: NSPersistentStoreCoordinator?
    var cacheState: StorageCache?
    public class func register(store: IncrementalStorageProtocol, coordinator: NSPersistentStoreCoordinator, cacheState: StorageCache, fileURL: NSURL? = nil) throws {
        // TODO: Check for store existing
        PersistanceStoreRegistry.sharedInstance.store = store
        PersistanceStoreRegistry.sharedInstance.coordinator = coordinator
        PersistanceStoreRegistry.sharedInstance.cacheState = cacheState
        do {
            try coordinator.addPersistentStoreWithType(PersistanceStore.type, configuration: nil, URL: fileURL, options: nil)
        } catch let error as NSError {
            throw error
        }
    }
}

enum FetchError: ErrorType {
    case UnsupportedReturnType
}

private
class Cache {
    // Dictionary: [entityName:[resourceID:objectID]]
    var tableIds = [String  : [String : NSManagedObjectID]]()
    // Dictionary: [objectID:[fieldName:values]]
    var valuesTable = [NSManagedObjectID : [String : AnyObject]]()
    
    // Use for translate relationships from resourceIDs to objectIDs
    func translateRelationshipsForObjectWithID(objectID: NSManagedObjectID) {
        //TODO: change values from resourceIds to objectIds
    }
    
    func update(objectID: NSManagedObjectID, entityName: String, resourceId: String, values: [String : AnyObject]) {
        if tableIds[entityName] == nil {
            tableIds[entityName] = [resourceId:objectID]
        } else {
            tableIds[entityName]![resourceId] = objectID
        }
        valuesTable[objectID] = values
    }
    
    func getObjectIds(entityName: String, resourceIds: [String]) -> [NSManagedObjectID] {
        var retObjects = [NSManagedObjectID]()
        
        guard let dictOfObjectIds = tableIds[entityName] else {
            return retObjects
        }
        for resourceId in resourceIds {
            if let objectId = dictOfObjectIds[resourceId] {
                retObjects.append(objectId)
            }
        }
        return retObjects
    }
    
    func getValuesFromObjectID(objectID: NSManagedObjectID) -> [String : AnyObject] {
        // TODO: check for existing this objectID
        return valuesTable[objectID]!
    }
    
    func isResourceIdExist(entityName: String, resourceId: String) -> Bool {
        guard let dictOfObjectIds = tableIds[entityName] else {
            return false
        }
        if dictOfObjectIds[resourceId] != nil {
            return true
        }
        return false
    }
}

final
class PersistanceStore: NSIncrementalStore {
    
    // Hold processing data with ids
    private var cache = Cache()
    
    // What cache should we use
    private var cacheState: StorageCache {
        return PersistanceStoreRegistry.sharedInstance.cacheState!
    }
    
    // Local cache
    lazy private var backingStack: BackingStack = {
        guard let coordinator = PersistanceStoreRegistry.sharedInstance.coordinator else {
            assertionFailure("Persistance store does not have coordinator")
            abort()
        }
        if self.cacheState == .NoCache {
            assertionFailure("Persistance store does not have cache")
            abort()
        }
        return BackingStack(storeId: PersistanceStore.type, withMOM: coordinator.managedObjectModel)
    }()
    
    
    // TODO: make class which will hold several PersistanceStore
    private var storage: IncrementalStorageProtocol {
        guard let storage = PersistanceStoreRegistry.sharedInstance.store else {
            assertionFailure("Persistance store does not storage implementation")
            abort()
        }
        return storage
    }
    
    // MARK: - NSIncrementalStore Override functions
    
    override class func initialize() {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    class var type: String {
        return NSStringFromClass(self)
    }
    
    override func loadMetadata() throws {
        self.metadata = [NSStoreUUIDKey : NSProcessInfo().globallyUniqueString,  NSStoreTypeKey : self.dynamicType.type]
    }
    
    override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        let requestHandler = requestHandlerForType(request.requestType)
        return try requestHandler(request, context!)!
    }
    
    override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        print("newValuesForObjectWithID was called")
        let values = cache.getValuesFromObjectID(objectID)
        return NSIncrementalStoreNode(objectID: objectID, withValues: values, version: 1)
    }
    
    override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        print("newValueForRelationship was called")
        // TODO: Change!
//        if relationship.toMany {
//            var keys: [AnyObject]!
//            keys = storage.getKeyOfDestFrom(self.referenceObjectForObjectID(objectID) as! String, to: relationship.name) as! [AnyObject]
//            return keys.map({ self.newObjectIDForEntity(relationship.destinationEntity!, referenceObject: $0) } )
//        } else {
//            var key: AnyObject!
//            key = storage.getKeyOfDestFrom(self.referenceObjectForObjectID(objectID) as! String, to: relationship.name)
//            return self.newObjectIDForEntity(relationship.destinationEntity!, referenceObject: key)
//        }
        return cache.valuesTable.keys.first!
    }
    
    
    // MARK: - Private functions
    
    private func requestHandlerForType(requestType: NSPersistentStoreRequestType) -> ((NSPersistentStoreRequest, NSManagedObjectContext) throws -> AnyObject?) {
        switch requestType {
        case .FetchRequestType: return executeFetchRequest
        case .SaveRequestType: return executeSaveRequest
        case .BatchDeleteRequestType, .BatchUpdateRequestType:
            assertionFailure("Batch updates for deletion and update are not handled now")
            abort()
        }
    }
    
    func updateContextAndCache(fetchedRecords: [String:[String:AnyObject]], entityDescription: NSEntityDescription, context: NSManagedObjectContext) -> [NSManagedObject] {
        print("updateContextAndCache was called")
        var newObjects = [NSManagedObject]()
        for record in fetchedRecords {
            if !cache.isResourceIdExist(entityDescription.name!, resourceId: record.0) {
                let objectId = self.newObjectIDForEntity(entityDescription, referenceObject: record.0)
                cache.update(objectId, entityName: entityDescription.name!, resourceId: record.0, values: record.1)
                newObjects.append(context.objectWithID(objectId))
            }
        }
        return newObjects
    }
    
    func getFetchedObjects(entityName: String, resourceIds: [String], context: NSManagedObjectContext) -> [NSManagedObject] {
        print("getFetchedObjects was called")
        var retObjects = [NSManagedObject]()
        let objectsFromCache = cache.getObjectIds(entityName, resourceIds: resourceIds)
        for objectId in objectsFromCache {
            let object = context.objectWithID(objectId)
            retObjects.append(object)
        }
        return retObjects
    }
    
    func executeFetchRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) throws -> AnyObject? {
        print("executeFetchRequest was called")
        guard let fetchRequest = request as? NSFetchRequest, entityName = fetchRequest.entityName else {
            return nil
        }
        fetchRequest.predicate = getTranslatedPredicate(fetchRequest.predicate, withContext: context)
        
        if fetchRequest.resultType == .ManagedObjectResultType {
            var records: [String:[String:AnyObject]]!
            switch cacheState {
            case .NoCache:
                records = executeSyncFetchRequest(fetchRequest)
            case .LocalCache:
                records = executeAsyncFetchRequest(fetchRequest, context: context)
            }
            updateContextAndCache(records, entityDescription: fetchRequest.entity!, context: context)
            return getFetchedObjects(entityName, resourceIds: records.map{return $0.0}, context: context)
        } else {
            throw FetchError.UnsupportedReturnType
        }
    }
    
    func executeSyncFetchRequest(fetchRequest: NSFetchRequest) -> [String:[String:AnyObject]] {
        let entityName = fetchRequest.entityName!
        let predicate = fetchRequest.predicate
        let sortDescriptors = fetchRequest.sortDescriptors
        
        let recordsFromStorage: [String:[String:AnyObject]] = storage.fetchRecords(entityName, predicate: predicate, sortDescriptors: sortDescriptors)
        return recordsFromStorage
    }
    
    func executeAsyncFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) -> [String:[String:AnyObject]] {
        executeRemoteFetchRequest(fetchRequest, context: context)
        return backingStack.getRecordsFromLocalCache(fetchRequest)
    }
    
    func executeRemoteFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) {
        print("executeRemoteFetchRequest was called")
        let updateContexts = { (records: [String:[String:AnyObject]]) in
            self.backingStack.updateLocalCacheWithRecords(records, withRequest: fetchRequest)
            let newObjects = self.updateContextAndCache(records, entityDescription: fetchRequest.entity!, context: context)
            var userInfo = [NSObject : AnyObject]()
            userInfo[self.storage.newObjectsName] = newObjects
            NSNotificationCenter.defaultCenter().postNotificationName(self.storage.fetchNotificationName, object: nil, userInfo: userInfo)
        }
        
        let priority = DISPATCH_QUEUE_PRIORITY_DEFAULT
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            let records = self.executeSyncFetchRequest(fetchRequest)
            dispatch_async(dispatch_get_main_queue()) {
                updateContexts(records)
            }
        }
    }
    
    
    
//    func objectIDForEntity(entity: NSEntityDescription, withResourceIdentifier identifier: String) -> NSManagedObjectID {
//        print("objectIDForEntity")
//        var objectId: NSManagedObjectID? = nil
        
//        if let objectIDsByResourceIdentifier = self.idTable[entity.name!] {
//            objectId = objectIDsByResourceIdentifier[identifier]
//        }
        
//        if objectId == nil {
//            let resourceId = identifier
//            objectId = self.newObjectIDForEntity(entity, referenceObject: resourceId)
//            
//            if self.idTable[entity.name!] == nil {
//                idTable[entity.name!] = [identifier: objectId!]
//            } else {
//                idTable[entity.name!]![identifier] = objectId!
//            }
//        }
//        
//        return objectId!
//    }
    
    
    
    func executeSaveRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) throws -> AnyObject? {
        print("executeSaveRequest was called")
//        guard let saveRequest = request as? NSSaveChangesRequest else {
//            return nil
//        }
//        
//        if let objectsForSave = saveRequest.insertedObjects {
//            for newObject in objectsForSave {
//                let attributes = self.objectDictionaryOfAttributes(newObject)
//                let relations = self.objectDictionaryOfRelationShips(newObject)
//                let key = objectStorageID(newObject)
//                try storage.saveRecord(key, dictOfAttribs: attributes, dictOfRelats: relations)
//            }
//        }
//        if let objectsForUpdate = saveRequest.updatedObjects {
//            for updatedObject in objectsForUpdate {
//                let key = objectStorageID(updatedObject)
//                let attributes = self.objectDictionaryOfAttributes(updatedObject)
//                let relations = self.objectDictionaryOfRelationShips(updatedObject)
//                try storage.updateRecord(updatedObject, key: key, dictOfAttribs: attributes, dictOfRelats: relations)
//            }
//        }
//        if let objectsForDelete = saveRequest.deletedObjects {
//            for deletedObject in objectsForDelete {
//                try storage.deleteRecord(deletedObject, key: objectStorageID(deletedObject))
//            }
//        }
        return []
    }
    
    func executeBatchUpdateRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        print("executeBatchUpdateRequest was called")
        return nil
    }
    
    // MARK: Supporting methods
    
    // TODO: to implement another types of predicates, now it is simple implementation
    private func getTranslatedPredicate(rudePredicate: NSPredicate?, withContext context: NSManagedObjectContext) -> NSPredicate? {
        print("getTranslatedPredicate was called")
        guard let rudePredicate = rudePredicate else {
            return nil
        }
        
        if let comparisonPredicate = rudePredicate as? NSComparisonPredicate {
            guard let objectId = comparisonPredicate.rightExpression.constantValue as? NSManagedObjectID else {
                // TODO: add expression support
                abort()
            }
            if context.objectRegisteredForID(objectId) != nil {
                let resourceId = referenceObjectForObjectID(objectId) as! String
                return NSPredicate(format: "%@ = %@", comparisonPredicate.leftExpression, resourceId)
            } else {
                abort()
            }
        }
        
        return NSPredicate(value: true)
    }
    
    
//    private func getPredicateWithTranslatedIds(basicPredicate: NSPredicate, storage: IncrementalStorageProtocol) -> NSPredicate {
//        print("getPredicateWithTranslatedIds was called")
//        var wordsOfPredicate = basicPredicate.predicateFormat.componentsSeparatedByString(" ")
//        for i in 0...wordsOfPredicate.count-2 {
//            let objectIdDescription = wordsOfPredicate[i...i+1].joinWithSeparator(" ")
//            if let key = correspondenceTable[objectIdDescription] {
//                wordsOfPredicate.removeAtIndex(i)
//                wordsOfPredicate[i] = key
//            }
//        }
//        return storage.predicateProcessing(wordsOfPredicate.joinWithSeparator(" "))
//    }
//    
//    func createObjects(entityName: String, context: NSManagedObjectContext, identifiers: [String]) -> [AnyObject] {
//        print("createObjects was called")
//        let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context)!
//        return identifiers.map { key in
//            let objectID = self.newObjectIDForEntity(entityDescription, referenceObject: key)
//            self.correspondenceTable[objectID.description] = key
//            return context.objectWithID(objectID)
//        }
//    }
    
//    func objectStorageID(object: NSManagedObject) -> String {
//        print("objectStorageID was called")
//        return referenceObjectForObjectID(object.objectID) as! String
//    }
    
//    func objectDictionaryOfRelationShips(object: NSManagedObject) -> [String : [String]] {
//        print("objectDictionaryOfRelationShips was called")
//        let relationShipProperties = object.entity.properties.filter({ $0 as? NSRelationshipDescription != nil })
//        return relationShipProperties.reduce([String : [String]]()) { (var previousValue, property) in
//            previousValue[property.name] = object.objectIDsForRelationshipNamed(property.name).map {
//                self.referenceObjectForObjectID($0) as! String
//            }
//            return previousValue
//        }
//    }
    
//    func objectDictionaryOfAttributes(object: NSManagedObject) -> [String : AnyObject] {
//        print("objectDictionaryOfAttributes was called")
//        let attributes = object.entity.properties.filter({ $0 as? NSAttributeDescription != nil })
//        return attributes.reduce([:]) { (var previousValue: [String : AnyObject], propertyDescription) -> [String : AnyObject] in
//            if let propertyValue = object.valueForKey(propertyDescription.name) {
//                previousValue[propertyDescription.name] = propertyValue
//            }
//            return previousValue
//        }
//    }
    
}
