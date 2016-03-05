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
    
    // What type of cache should we use
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
        let values = cache.getValuesFromObjectID(objectID)
        return NSIncrementalStoreNode(objectID: objectID, withValues: values, version: 1)
    }
    
    override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        // TODO: implement
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
        var retObjects = [NSManagedObject]()
        let objectsFromCache = cache.getObjectIds(entityName, resourceIds: resourceIds)
        for objectId in objectsFromCache {
            let object = context.objectWithID(objectId)
            retObjects.append(object)
        }
        return retObjects
    }
    
    func executeFetchRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) throws -> AnyObject? {
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
                records = try! executeAsyncFetchRequest(fetchRequest, context: context)
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
    
    func executeAsyncFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) throws -> [String:[String:AnyObject]] {
        try! executeRemoteFetchRequest(fetchRequest, context: context)
        return try! backingStack.getRecordsFromLocalCache(fetchRequest)
    }
    
    func executeRemoteFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) throws {
        let updateContexts = { (records: [String:[String:AnyObject]]) in
            try! self.backingStack.updateLocalCacheWithRecords(records, withRequest: fetchRequest)
            let newObjects = self.updateContextAndCache(records, entityDescription: fetchRequest.entity!, context: context)
            var userInfo = [NSObject : AnyObject]()
            userInfo[self.storage.newObjectsName] = newObjects
            NSNotificationCenter.defaultCenter().postNotificationName(self.storage.RecordsWereReceivedNotification, object: nil, userInfo: userInfo)
        }
        
        let priority = DISPATCH_QUEUE_PRIORITY_DEFAULT
        dispatch_async(dispatch_get_global_queue(priority, 0)) {
            let records = self.executeSyncFetchRequest(fetchRequest)
            dispatch_async(dispatch_get_main_queue()) {
                updateContexts(records)
            }
        }
    }
    
    // save similarly to load
    func saveObjects(objects: Set<NSManagedObject>, withContext context: NSManagedObjectContext) {
        // TODO: think about .LocalCache
        if cacheState != .NoCache {
            abort()
        }
        var recordsForSave = [(name: String, atributes: [String : AnyObject])]()
        for newObject in objects {
            var attributes = [String : AnyObject]()
            for attrib in newObject.entity.attributesByName {
                // TODO: check attrib.1
                attributes[attrib.0] = newObject.valueForKey(attrib.0)
            }
            for relationship in newObject.entity.relationshipsByName {
                // TODO: translate relationships
            }
            recordsForSave += [(newObject.entity.name!, attributes)]
        }
        self.storage.saveRecords(recordsForSave)
    }
    
    // update request
    func updateObjects(objects: Set<NSManagedObject>, withContext context: NSManagedObjectContext) {
        print("updatedObjects")
        abort()
    }
    
    // delete request
    func deleteObjects(objects: Set<NSManagedObject>, withContext context: NSManagedObjectContext) {
        print("deletedObjects")
        abort()
    }
    
    func executeSaveRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) throws -> AnyObject? {
        guard let saveRequest = request as? NSSaveChangesRequest else {
            return nil
        }
        if let objectsForSave = saveRequest.insertedObjects {
            saveObjects(objectsForSave, withContext: context)
            return []
        }
        if let objectsForUpdate = saveRequest.updatedObjects {
            updateObjects(objectsForUpdate, withContext: context)
            return []
        }
        if let objectsForDelete = saveRequest.deletedObjects {
            deleteObjects(objectsForDelete, withContext: context)
            return []
        }
        print("Doesn't support 'lockedObjects' yet")
        abort()
    }
    
    func executeBatchUpdateRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext) -> AnyObject? {
        print("executeBatchUpdateRequest was called")
        return nil
    }
    
    // MARK: Supporting methods
    
    // TODO: to implement another types of predicates
    private func getTranslatedPredicate(rudePredicate: NSPredicate?, withContext context: NSManagedObjectContext) -> NSPredicate? {
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
    
}
