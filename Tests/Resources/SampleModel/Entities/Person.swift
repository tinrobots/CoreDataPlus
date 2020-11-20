// CoreDataPlus

import Foundation
import CoreData
import CoreDataPlus

@objc(Person)
final public class Person: NSManagedObject {
  @NSManaged public private(set) var id: UUID // preserved after deletion (tombstone)
  @NSManaged public var firstName: String
  @NSManaged public var lastName: String
  @NSManaged public var cars: NSSet? // This is why it must be a NSSet https://twitter.com/an0/status/1157072652290445314
  @NSManaged public var isDriving: Bool // Transient

  public var _cars: Set<Car>? {
    get {
      return cars as? Set<Car>
    }
    set {
      if let newCars = newValue {
        self.cars = NSSet(set: newCars)
      } else {
        self.cars = nil
      }
    }
  }
}

extension Person: UpdateTimestampable {
  @NSManaged public var updatedAt: Date
}

extension Person {

  /// Primitive accessor for `updateAt` property.
  /// It's created by default from Core Data with a *primitive* suffix*.
  @NSManaged private var primitiveUpdatedAt: Date

  @NSManaged private var primitiveId: UUID

  public override func awakeFromInsert() {
    super.awakeFromInsert()
    primitiveUpdatedAt = Date()
    //setPrimitiveValue(NSDate(), forKey: "updatedAt") // we can use one of these two options to set the value
    primitiveId = UUID()
  }

  public override func willSave() {
    super.willSave()
    refreshUpdateDate(observingChanges: false) // we don't want to get notified when this value changes.
  }

}
