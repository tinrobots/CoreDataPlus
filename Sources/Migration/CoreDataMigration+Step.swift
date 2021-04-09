// CoreDataPlus

import CoreData

extension CoreDataMigration {
  /// Represents a single step during a migration process.
  public final class Step {
    public let sourceModel: NSManagedObjectModel
    public let destinationModel: NSManagedObjectModel
    public let mappings: [NSMappingModel]

    init(source: NSManagedObjectModel, destination: NSManagedObjectModel, mappings: [NSMappingModel]) {
      self.sourceModel = source
      self.destinationModel = destination
      self.mappings = mappings
    }
  }
}
