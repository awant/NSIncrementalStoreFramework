
import Foundation
import CoreData

public
protocol CoreDataConfig {
    static func configurationName() -> String
    static func modelURL() -> NSURL
    static func configurateStoreCoordinator(coordinator: NSPersistentStoreCoordinator) throws
}
