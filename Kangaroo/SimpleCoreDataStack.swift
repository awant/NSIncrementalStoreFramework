
import Foundation
import CoreData


private
class ManagerHolder {
    static let managerController = ManagerHolder()
    var manager: AnyObject?
    
    func coreDataManager<T: CoreDataConfig>() -> SimpleCoreDataStack<T> {
        if let manager = self.manager as? SimpleCoreDataStack<T> {
            return manager
        } else {
            let newManager: SimpleCoreDataStack<T> = SimpleCoreDataStack()
            self.manager = newManager
            return self.manager as! SimpleCoreDataStack<T>
        }
    }
    
}

public
class SimpleCoreDataManager<T: CoreDataConfig> {
    private var coreDataPrivateManager: SimpleCoreDataStack<T> {
        return ManagerHolder.managerController.coreDataManager()
    }
    
    //private var simpleCoreDataStack = SimpleCoreDataStack<T>()
    
    public init() {}

    private var moc: NSManagedObjectContext? {
        return coreDataPrivateManager.managedObjectContext
    }
}

public
extension SimpleCoreDataManager {
    func executeAsyncFetchRequest<T: CoreDataRepresentable>(predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?, completion: [T] -> Void) {
        let fetchRequest = NSFetchRequest(entityName: T.entityName)
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.predicate = predicate
        let asyncRequest = NSAsynchronousFetchRequest(fetchRequest: fetchRequest) { (fetchResult) -> Void in
            if let result = fetchResult.finalResult as? [T] {
                completion(result)
            } else {
                completion([])
            }
        }
        try! moc!.executeRequest(asyncRequest)
    }
    
    func executeFetchRequest<T: CoreDataRepresentable>(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [T] {
        let fetchRequest = NSFetchRequest(entityName: T.entityName)
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.predicate = predicate

        return try! moc!.executeFetchRequest(fetchRequest) as! [T]
    }
    
    func save() {
        try! self.moc!.save()
    }
}

private
class SimpleCoreDataStack<T: CoreDataConfig>: NSObject {
    
    lazy var applicationDocumentsDirectory: NSURL = {
        return NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).last!
    }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
        return NSManagedObjectModel(contentsOfURL: T.modelURL())!
    }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator? = {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        do {
            try T.configurateStoreCoordinator(coordinator)
            return coordinator
        } catch let error as NSError {
            NSLog("Unresolved error \(error), \(error.userInfo)")
            abort()
        }
    }()
    
    lazy var managedObjectContext: NSManagedObjectContext? = {
        guard let coordinator = self.persistentStoreCoordinator else {
            return nil
        }
        
        let moc = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        moc.persistentStoreCoordinator = coordinator
        return moc
    }()
    
    func saveContext () {
        guard let moc = self.managedObjectContext else {
            return
        }
        if moc.hasChanges {
            do {
                try moc.save()
            } catch let error as NSError {
                print("error: \(error)")
                abort()
            }
        }
    }
}
