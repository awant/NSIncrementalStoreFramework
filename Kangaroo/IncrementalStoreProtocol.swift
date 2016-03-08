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
    
    // String key is name of Entity for new record
    // TODO: error handler.
    func saveRecords(dictOfRecords: [(name: String, atributes: [String: AnyObject])])
    
    // For notifications about fetching from remote cloud
    var RecordsWereReceivedNotification: String { get set }
    var newObjectsName: String { get set }
}

