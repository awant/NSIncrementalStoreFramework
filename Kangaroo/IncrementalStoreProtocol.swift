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
     Returns object identifiers from storage
     
     - parameter entityName: the Name of entity to create
     - parameter sortDescriptors: how can we want to sort objects
     - parameter newEntityCreator: function, which get (entityName, local keys of objects) for create
     - returns: objects from storage (empty for a while)
     */
    func fetchRecords<T: Hashable>(entityName: String, predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?) -> [T:[String:AnyObject]]
    
    // For notifications about fetching from remote cloud
    var fetchNotificationName: String { get set }
    var newObjectsName: String { get set }
    
    /**
     Get values and version of object in storage identified by key
     
     - parameter key: local identifier of object
     - returns: values and version of object
     */
//    func valueAndVersion(key: String, fromField field: String) -> AnyObject?
//    
//    /**
//     Create new empty object in storage and return key of it
//     
//     - returns: key of new object
//     */
//    func getKeyOfNewObjectWithEntityName(entityName: String) -> AnyObject
//    
//    /**
//     Save record in storage
//     
//     - parameter objectForSave: representation of object in storage
//     - parameter key: local identifier of object
//     */
//    func saveRecord(key: String, dictOfAttribs: [String : AnyObject], dictOfRelats: [String : [String]]) throws
//    
//    /**
//     Update record in storage
//     
//     - parameter objectForUpdate: representation of object in storage
//     - parameter key: local identifier of object
//     */
//    func updateRecord(objectForUpdate: AnyObject, key: AnyObject, dictOfAttribs: [String : AnyObject], dictOfRelats: [String : [String]]) throws
//    
//    /**
//     Delete record in storage
//     
//     - parameter objectForDelete: representation of object in storage
//     - parameter key: local identifier of object
//     */
//    func deleteRecord(objectForDelete: AnyObject, key: AnyObject) throws
//    
//    /**
//     Get keys of referenced objects.
//     
//     - parameter keyObject: local identifier of object
//     - parameter fieldName: name of this reference
//     - returns: key(String) or keys(Array) from this field of object
//     */
//    func getKeyOfDestFrom(keyObject: String, to fieldName: String) -> AnyObject
//    
//    func predicateProcessing(basicPredicateInString: String) -> NSPredicate
}

