
import CoreData

let kResourceIdentifierAttributeName = "__resourceIdentifier__"

class BackingStack {
    
    var storeId: String
    var managedObjectModel: NSManagedObjectModel
    
    init(storeId: String, withMOM mom: NSManagedObjectModel) {
        self.storeId = storeId
        self.managedObjectModel = mom
    }
    
    func getRecordsFromLocalCache(fetchRequest: NSFetchRequest) -> [String : [String : AnyObject]] {
        print("getRecordsFromLocalCache was called")
        let results = try! backingManagedObjectContext.executeFetchRequest(fetchRequest) as! [NSManagedObject]
        var retResults = [String : [String : AnyObject]]()
        for result in results {
            let resourceId = result.valueForKey(kResourceIdentifierAttributeName) as! String
            var values = [String : AnyObject]()
            for (propertyName, property) in result.entity.propertiesByName {
                if propertyName == kResourceIdentifierAttributeName {
                    continue
                }
                values[propertyName] = result.valueForKey(propertyName)
            }
            retResults[resourceId] = values
        }
        print("getRecordsFromLocalCache was called, before retResults")
        return retResults
    }
    
    func isResourceIDExistInCache(resourceId: String, entityName: String) -> NSManagedObjectID? {
        print("isResourceIDExistInCache")
        let localFetchRequest = NSFetchRequest(entityName: entityName)
        localFetchRequest.resultType = NSFetchRequestResultType.ManagedObjectIDResultType
        localFetchRequest.fetchLimit = 1
        
        let predicate = NSPredicate(format: "%K = %@", kResourceIdentifierAttributeName, resourceId)
        localFetchRequest.predicate = predicate
        let objectLocalIds = try! backingManagedObjectContext.executeFetchRequest(localFetchRequest)
        if objectLocalIds.isEmpty {
            return nil
        } else {
            return (objectLocalIds.last as! NSManagedObjectID)
        }
    }
    
    func updateLocalCacheWithRecords(records: [String:[String:AnyObject]], withRequest fetchRequest: NSFetchRequest) {
        print("updateLocalCacheWithRecords was called")
        let entityName = fetchRequest.entityName!
        for record in records {
            if isResourceIDExistInCache(record.0, entityName: entityName) == nil {
                addNewRecord(record.1, withKey: record.0, withEntity: fetchRequest.entity!)
            }
        }
        try! backingManagedObjectContext.save()
    }
    
    func addNewRecord(values: [String:AnyObject], withKey key: String, withEntity entity: NSEntityDescription) {
        backingManagedObjectContext.performBlockAndWait() {
            let backingObject = NSEntityDescription.insertNewObjectForEntityForName(entity.name!, inManagedObjectContext: self.backingManagedObjectContext)
            backingObject.setValue(key, forKey: kResourceIdentifierAttributeName)
            for (relationshipName, relationship) in entity.relationshipsByName {
                guard let relationships = values[relationshipName] else {
                    print("Can't find values in cloud for name: \(relationshipName)")
                    abort()
                }
                let translatedRelationships = self.updateObjectsForRelationship(relationshipName, relationships: relationships, relationshipDescription: relationship)
                backingObject.setValue(translatedRelationships, forKey: relationshipName)
            }
            
            for (attribName, _) in entity.attributesByName {
                guard let object = values[attribName] else {
                    print("Can't find values in cloud for name: \(attribName)")
                    abort()
                }
                backingObject.setValue(object, forKey: attribName)
            }
        }
    }
    
    func updateObjectsForRelationship(relationshipName: String, relationships: AnyObject, relationshipDescription: NSRelationshipDescription) -> AnyObject {
        print("updateObjectsForRelationship")
        let destEntityName = relationshipDescription.destinationEntity!.name!
        if relationshipDescription.toMany {
            // TODO: Find - can be not NSSet
            let resourceIds = relationships as! NSSet
            let retObjects = NSMutableSet()
            for resourceId in resourceIds {
                if let objectId = isResourceIDExistInCache(resourceId as! String, entityName: destEntityName) {
                    retObjects.addObject(self.backingManagedObjectContext.objectWithID(objectId))
                } else {
                    let backingObject = NSEntityDescription.insertNewObjectForEntityForName(destEntityName, inManagedObjectContext: self.backingManagedObjectContext)
                    backingObject.setValue(resourceId, forKey: kResourceIdentifierAttributeName)
                    retObjects.addObject(backingObject)
                }
            }
            return retObjects
        } else {
            let resourceId = relationships as! String
            if let objectId = isResourceIDExistInCache(resourceId, entityName: destEntityName) {
                return self.backingManagedObjectContext.objectWithID(objectId)
            } else {
                let backingObject = NSEntityDescription.insertNewObjectForEntityForName(destEntityName, inManagedObjectContext: self.backingManagedObjectContext)
                backingObject.setValue(resourceId, forKey: kResourceIdentifierAttributeName)
                return backingObject
            }
        }
    }
    
    lazy var applicationDocumentsDirectory: NSURL = {
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls[urls.count-1] as NSURL
    }()
    
    lazy var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator = {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.cachedModel)
        
        var error: NSError? = nil
        let storeType = NSSQLiteStoreType
        let path = self.storeId + ".sqlite"
        let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent(path)
        let options = [NSMigratePersistentStoresAutomaticallyOption: NSNumber(bool: true),
            NSInferMappingModelAutomaticallyOption: NSNumber(bool: true)];
        
        do {
            try coordinator.addPersistentStoreWithType(storeType, configuration: nil, URL: url, options: options)
        }
        catch (let error) {
            abort()
        }
        
        return coordinator
    }()
    
    lazy var backingManagedObjectContext: NSManagedObjectContext = {
        let context = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        context.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
        context.retainsRegisteredObjects = true
        return context
    }()
    
    lazy var cachedModel: NSManagedObjectModel = {
        let cachedModel = self.managedObjectModel.copy() as! NSManagedObjectModel
        // Now we should define mapping in model between id from Cloud and Objects
        // resourceId is id of object in cloud
        // TODO: add tracking state for updating (date or smth)
        for entity in cachedModel.entities {
            if entity.superentity != nil {
                continue
            }
            let resourceIdProperty = NSAttributeDescription()
            resourceIdProperty.name = kResourceIdentifierAttributeName
            resourceIdProperty.attributeType = NSAttributeType.StringAttributeType
            resourceIdProperty.indexed = true
            
            var properties = entity.properties
            properties.append(resourceIdProperty)
            
            entity.properties = properties
        }
        return cachedModel
    }()
}


