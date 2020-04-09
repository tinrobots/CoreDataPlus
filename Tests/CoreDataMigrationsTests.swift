//
// CoreDataPlus
//
// Copyright © 2016-2020 Tinrobots.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import XCTest
import CoreData
@testable import CoreDataPlus

class CoreDataMigrationsTests: XCTestCase {
  let fileManager = FileManager.default
  var containerSQLite: NSPersistentContainer!
  let lock = NSLock()

  override func setUp() {
    super.setUp()
    containerSQLite = NSPersistentContainer(name: "SampleModel-\(UUID())", managedObjectModel: model)
    containerSQLite.loadPersistentStores { (description, error) in
      XCTAssertNil(error)
    }
  }

  override func tearDown() {
    containerSQLite.persistentStoreCoordinator.performAndWait {
      let stores = containerSQLite.persistentStoreCoordinator.persistentStores
      for store in stores {
        try! containerSQLite.viewContext.persistentStoreCoordinator?.remove(store)
        if let url = store.url {
          /// This command causes a "BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by API violation: vnode unlinked while in use..."
          /// it's not important for these tests but we can avoid it removing the NSPersistentStore before destroying it
          try! NSPersistentStoreCoordinator.destroyStore(at: url)
        }
      }
    }
    containerSQLite = nil
    super.tearDown()
  }

  // MARK: - LightWeight Migration

  func testMigrationFromVersion1ToVersion2() throws {
    let context = containerSQLite.viewContext
    let url = containerSQLite.persistentStoreDescriptions[0].url!
    context.fillWithSampleData()
    try context.save()

    let allCars = try Car.fetch(in: context) // 125
    let sportCars = try ExpensiveSportCar.fetch(in: context) // 5

    if #available(iOS 11, tvOS 11, watchOS 4, macOS 10.13, *) {
      XCTAssertEqual(allCars.first!.entity.indexes.count, 0)
    }

    let targetVersion = SampleModelVersion.version2
    let steps = SampleModelVersion.version1.migrationSteps(to: .version2)
    XCTAssertEqual(steps.count, 1)

    let sourceURL = url
    let targetURL = url

    let version = SampleModelVersion(persistentStoreURL: sourceURL as URL)
    XCTAssertTrue(version == .version1)

    // When
    let progress = Progress(totalUnitCount: 1)
    var completionSteps = 0
    var completion = 0.0
    let token = progress.observe(\.fractionCompleted, options: [.new]) { (progress, change) in
      completion = progress.fractionCompleted
      completionSteps += 1
    }

    try CoreDataMigration.migrateStore(at: sourceURL, targetVersion: targetVersion, progress: progress)
    let migratedContext = NSManagedObjectContext(model: targetVersion.managedObjectModel(), storeURL: targetURL)
    let luxuryCars = try LuxuryCar.fetch(in: migratedContext)
    XCTAssertEqual(sportCars.count, luxuryCars.count)

    let cars = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Car"))
    XCTAssertTrue(cars.count >= 1)

    if #available(iOS 11, tvOS 11, watchOS 4, macOS 10.13, *) {
      cars.forEach { car in
        if car is LuxuryCar || car is SportCar {
          XCTAssertEqual(car.entity.indexes.count, 0)
        } else if car is Car {
          let index = car.entity.indexes.first
          XCTAssertNotNil(index, "There should be a compound index")
          XCTAssertEqual(index!.elements.count, 2)
        } else {
          XCTFail("Undefined")
        }
      }
    }

    try CoreDataMigration.migrateStore(from: sourceURL, to: targetURL, targetVersion: targetVersion)

    XCTAssertEqual(completionSteps, 1)
    XCTAssertEqual(completion, 1.0)

    migratedContext._fix_sqlite_warning_when_destroying_a_store()
    token.invalidate()
  }

  // MARK: - HeavyWeight Migration

  func testMigrationFromVersion2ToVersion3() throws {
    let bundle = Bundle(for: CoreDataMigrationsTests.self)
    let _sourceURL = bundle.url(forResource: "SampleModelV2", withExtension: "sqlite")!

    // Being the test run multiple times, we create an unique copy for every test
    let uuid = UUID().uuidString
    let sourceURL = bundle.bundleURL.appendingPathComponent("SampleModelV2_copy-\(uuid).sqlite")
    try FileManager.default.copyItem(at: _sourceURL, to: sourceURL)
    XCTAssertTrue(fileManager.fileExists(atPath: sourceURL.path))

    let targetURL = sourceURL
    let version = SampleModelVersion(persistentStoreURL: sourceURL as URL)

    XCTAssertTrue(version == .version2)

    try CoreDataMigration.migrateStore(from: sourceURL, to: targetURL, targetVersion: SampleModelVersion.version3)

    let migratedContext = NSManagedObjectContext(model: SampleModelVersion.version3.managedObjectModel(), storeURL: targetURL)
    let cars = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Car"))
    let makers = try Maker.fetch(in: migratedContext)
    XCTAssertEqual(makers.count, 11)
    XCTAssertEqual(cars.count, 125)

    cars.forEach { object in
      let owner = object.value(forKey: "owner") as? NSManagedObject
      let maker = object.value(forKey: "createdBy") as? NSManagedObject
      XCTAssertNotNil(maker)
      let name = maker!.value(forKey: "name") as! String
      maker!.setValue("--\(name)--", forKey: "name")
      let previousOwners = object.value(forKey: "previousOwners") as! Set<NSManagedObject>

      if let carOwner = owner {
        XCTAssertTrue(previousOwners.contains(carOwner))
        let previousCars = carOwner.value(forKey: "previousCars") as! Set<NSManagedObject>
        XCTAssertTrue(previousCars.contains(object))
      } else {
        XCTAssertEqual(previousOwners.count, 0)
      }
    }

    try migratedContext.save()
    XCTAssertTrue(fileManager.fileExists(atPath: targetURL.path))
    XCTAssertTrue(fileManager.fileExists(atPath: sourceURL.path))

    migratedContext._fix_sqlite_warning_when_destroying_a_store()

    try NSPersistentStoreCoordinator.destroyStore(at: sourceURL)
  }

  func testMigrationFromVersion1ToVersion3() throws {
    let bundle = Bundle(for: CoreDataMigrationsTests.self)
    let _sourceURL = bundle.url(forResource: "SampleModelV1", withExtension: "sqlite")!

    // Being the test run multiple times, we create an unique copy for every test
    let uuid = UUID().uuidString
    let sourceURL = bundle.bundleURL.appendingPathComponent("SampleModelV1_copy-\(uuid).sqlite")
    try FileManager.default.copyItem(at: _sourceURL, to: sourceURL)
    XCTAssertTrue(fileManager.fileExists(atPath: sourceURL.path))

    let version = SampleModelVersion(persistentStoreURL: sourceURL as URL)

    XCTAssertTrue(version == .version1)

    let targetURL = URL.temporaryDirectoryURL.appendingPathComponent("SampleModel").appendingPathExtension("sqlite")
    let progress = Progress(totalUnitCount: 1)
    var completionSteps = 0
    var completion = 0.0
    let token = progress.observe(\.fractionCompleted, options: [.new]) { (progress, change) in
      completion = progress.fractionCompleted
      completionSteps += 1
    }
    try CoreDataMigration.migrateStore(from: sourceURL, to: targetURL, targetVersion: SampleModelVersion.version3, deleteSource: true, progress: progress)

    let migratedContext = NSManagedObjectContext(model: SampleModelVersion.version3.managedObjectModel(), storeURL: targetURL)
    let makers = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Maker"))
    XCTAssertEqual(makers.count, 11)

    makers.forEach { (maker) in
      let name = maker.value(forKey: "name") as! String
      maker.setValue("--\(name)--", forKey: "name")
    }
    try migratedContext.save()

    XCTAssertEqual(completionSteps, 2)
    XCTAssertEqual(completion, 1.0)

    XCTAssertFalse(fileManager.fileExists(atPath: sourceURL.path))
    XCTAssertTrue(fileManager.fileExists(atPath: targetURL.path))

    migratedContext._fix_sqlite_warning_when_destroying_a_store()
    token.invalidate()
  }
}

extension NSManagedObjectContext {
  convenience init(model: NSManagedObjectModel, storeURL: URL) {
    let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
    try! psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
    self.init(concurrencyType: .mainQueueConcurrencyType)
    persistentStoreCoordinator = psc
  }

  func _fix_sqlite_warning_when_destroying_a_store() {
    /// solve the warning: "BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by API violation: vnode unlinked while in use..."
    for store in persistentStoreCoordinator!.persistentStores {
      try! persistentStoreCoordinator?.remove(store)
    }
  }
}
