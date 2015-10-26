//
//  IncrementalStoreProtocol.swift
//  Kangaroo
//
//  Created by Artemiy Sobolev on 26.10.15.
//  Copyright © 2015 com.mipt. All rights reserved.
//

import Foundation
import CoreData

public
protocol IncrementalStorageProtocol {
    /**
     Returns objects from storage. [AnyObject]? is array of keys of objects in storage. Return persons getting from newEntityCreator
     
     - parameter entityName: the Name of entity to create
     - parameter sortDescriptors: how can we want to sort objects
     - parameter newEntityCreator: function, which get (entityName, local keys of objects) for create
     - returns: objects from storage (empty for a while)
     */
    func fetchRecords(entityName: String, relatedEntitiesNames: [String]?, sortDescriptors: [NSSortDescriptor]?, newEntityCreator: (String, [AnyObject]?) -> AnyObject) -> AnyObject?
    
    /**
     Get values and version of object in storage identified by key
     
     - parameter key: local identifier of object
     - returns: values and version of object
     */
    func valueAndVersion(key: String, fromField field: String) -> AnyObject?
    
    /**
     Create new empty object in storage and return key of it
     
     - returns: key of new object
     */
    func getKeyOfNewObjectWithEntityName(entityName: String) -> AnyObject
    
    /**
     Save record in storage and return nil if can't
     
     - parameter objectForSave: representation of object in storage
     - parameter key: local identifier of object
     - returns: nil, if can't save
     */
    func saveRecord(key: String, dictOfAttribs: [String:AnyObject], dictOfRelats: [String:[String]]) -> AnyObject?
    
    /**
     Update record in storage and return nil if can't
     
     - parameter objectForUpdate: representation of object in storage
     - parameter key: local identifier of object
     - returns: nil, if can't update
     */
    func updateRecord(objectForUpdate: AnyObject, key: AnyObject) -> AnyObject?
    
    /**
     Delete record in storage and return nil if can't
     
     - parameter objectForDelete: representation of object in storage
     - parameter key: local identifier of object
     - returns: nil, if can't delete
     */
    func deleteRecord(objectForDelete: AnyObject, key: AnyObject) -> AnyObject?
    
    func getKeyOfDestFrom(keyObject: String , to fieldName: String) -> AnyObject?
}
