
import Foundation
import CoreData

public
protocol CoreDataRepresentable: NSObjectProtocol {
    static var entityName: String { get }
    static func fetchRequest() -> NSFetchRequest
}

public
extension CoreDataRepresentable {
    static func fetchRequest() -> NSFetchRequest {
        return NSFetchRequest(entityName: self.entityName)
    }
}

