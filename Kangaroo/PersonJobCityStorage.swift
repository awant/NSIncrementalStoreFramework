//
//  PersonJobCityParseStorage.swift
//  ResultsFetcher
//
//  Created by Awant on 23.09.15.
//  Copyright © 2015 Artemiy Sobolev. All rights reserved.
//

import Foundation
// ObjectID is unique only for a class, but hardly to get duplicated keys (it's not mentioned in docs)
import Parse

class PersonJobCityParseStorage: IncrementalStorageProtocol {
    var receivedObjects: [String: PFObject]?
    var relatedEntitiesNames: [String]?
    var objectsForSave = [String:PFObject]()
    
    var personForSave: PFObject?
    var jobForSave: PFObject?
    var cityForSave: PFObject?
    
    func fetchRecords(entityName: String, relatedEntitiesNames: [String]?, sortDescriptors: [NSSortDescriptor]?, newEntityCreator: (String, [AnyObject]?) -> AnyObject) -> AnyObject? {
        let query = PFQuery(className: entityName)
        if let relatedEN = relatedEntitiesNames {
            self.relatedEntitiesNames = relatedEntitiesNames
            for entityName in relatedEN {
                query.includeKey(entityName)
            }
        }
        
        var loadedObjects: [PFObject]?
        do {
            loadedObjects = try query.findObjects()
        } catch {}
        
        var arrayOfKeys: [String]?
        if let lObjects = loadedObjects {
            arrayOfKeys = [String]()
            self.receivedObjects = [String: PFObject]()
            for object in lObjects {
                arrayOfKeys!.append(object.objectId!)
                self.receivedObjects![object.objectId!] = object
            }
        }
        return newEntityCreator(entityName, arrayOfKeys)
    }
    // field is the property of parseObject, for example: person["name"] = "Name"; "name" is field
    func valueAndVersion(key: String, fromField field: String) -> AnyObject? {
        if let receivedObject = self.receivedObjects![key] {
            return receivedObject[field]
        }
        for receivedObject in self.receivedObjects! {
            guard self.relatedEntitiesNames != nil else {
                return nil
            }
            for relatedEntityName in self.relatedEntitiesNames! {
                let relatedObject = (receivedObject.1[relatedEntityName] as! PFObject)
                if relatedObject.objectId == key {
                    return relatedObject[field]
                }
            }
        }
        return nil
    }
    
    func getKeyOfDestFrom(keyObject: String , to fieldName: String) -> AnyObject? {
        if let receivedObject = self.receivedObjects![keyObject] {
                return receivedObject[fieldName].objectId
        }
        print("something else")
        return nil
    }
    
    func getKeyOfNewObjectWithEntityName(entityName: String) -> AnyObject {
        var newObject = PFObject(className: entityName)
        do {
            try newObject.save()
        } catch {}
        self.objectsForSave[newObject.objectId!] = newObject
        return newObject.objectId!
    }
    
    func saveRecord(key: String, dictOfAttribs: [String:AnyObject], dictOfRelats: [String:[String]]) -> AnyObject? {
        //print(dictOfAttribs)
        //print(dictOfRelats)
        for attrib in dictOfAttribs {
            // we should check for existing
            objectsForSave[key]![attrib.0] = attrib.1
        }
        for (field, relateKeys) in dictOfRelats {
            if relateKeys.count == 1 {
                self.objectsForSave[key]![field] = self.objectsForSave[relateKeys.first!]
            } else {
                self.objectsForSave[key]![field] = relateKeys.map { (let key) -> PFObject in
                    // we should check for existing
                    return self.objectsForSave[key]!
                }
            }
        }
        do {
            try self.objectsForSave[key]!.save()
        } catch {}
        return []
    }
    
    func updateRecord(objectForUpdate: AnyObject, key: AnyObject) -> AnyObject? {
        return nil
    }
    
    func deleteRecord(objectForDelete: AnyObject, key: AnyObject) -> AnyObject? {
        return nil
    }
}
