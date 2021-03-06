// CoreDataPlus

import XCTest
import CoreData
@testable import CoreDataPlus

@available(iOS 13.0, iOSApplicationExtension 13.0, macCatalyst 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
class OnDiskWithProgrammaticallyModelTestCase: XCTestCase {
  var container: NSPersistentContainer!

  override func setUp() {
    super.setUp()
    container = OnDiskWithProgrammaticallyModelPersistentContainer.makeNew()
  }

  override func tearDown() {
    do {
      if let onDiskContainer = container as? OnDiskWithProgrammaticallyModelPersistentContainer {
        try onDiskContainer.destroy()
      }
    } catch {
      XCTFail("The persistent container couldn't be destroyed.")
    }
    container = nil
    super.tearDown()
  }
}

// MARK: - On Disk NSPersistentContainer with Programmatically Model

@available(iOS 13.0, iOSApplicationExtension 13.0, macCatalyst 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
final class OnDiskWithProgrammaticallyModelPersistentContainer: NSPersistentContainer {
  static func makeNew() -> OnDiskWithProgrammaticallyModelPersistentContainer {
    Self.makeNew(id: UUID())
  }

  static func makeNew(id: UUID) -> OnDiskWithProgrammaticallyModelPersistentContainer {
    let url = URL.newDatabaseURL(withID: id)
    let container = OnDiskWithProgrammaticallyModelPersistentContainer(name: "SampleModel2",
                                                                       managedObjectModel: V1.makeManagedObjectModel())
    let description = NSPersistentStoreDescription()
    description.url = url
    description.shouldMigrateStoreAutomatically = false
    description.shouldInferMappingModelAutomatically = false

    // Enable history tracking and remote notifications
    description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    container.persistentStoreDescriptions = [description]

    container.loadPersistentStores { (description, error) in
      XCTAssertNil(error)
    }
    return container
  }

  /// Destroys the database and reset all the registered contexts.
  func destroy() throws {
    guard let url = persistentStoreDescriptions[0].url else { return }
    guard !url.absoluteString.starts(with: "/dev/null") else { return }

    // unload each store from the used context to avoid the sqlite3 bug warning.
    do {
      if let store = persistentStoreCoordinator.persistentStores.first {
        try persistentStoreCoordinator.remove(store)
      }
      try NSPersistentStoreCoordinator.destroyStore(at: url)
    } catch {
      fatalError("\(error) while destroying the store.")
    }
  }
}
