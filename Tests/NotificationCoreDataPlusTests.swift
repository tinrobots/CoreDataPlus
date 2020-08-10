// CoreDataPlus

import XCTest
import CoreData
@testable import CoreDataPlus

@available(iOS 13.0, iOSApplicationExtension 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
final class NotificationCoreDataPlusTests: CoreDataPlusInMemoryTestCase {
  /// To issue a NSManagedObjectContextObjectsDidChangeNotification from a background thread, call the NSManagedObjectContext’s processPendingChanges method.
  /// http://openradar.appspot.com/14310964
  /// NSManagedObjectContext’s `perform` method encapsulates an autorelease pool and a call to processPendingChanges, `performAndWait` does not.

  /**
   Track Changes in Other Threads Using Notifications

   Changes you make to a managed object in one context are not propagated to a corresponding managed object in a different context unless you either refetch or re-fault the object.
   If you need to track in one thread changes made to managed objects in another thread, there are two approaches you can take, both involving notifications.
   For the purposes of explanation, consider two threads, “A” and “B”, and suppose you want to propagate changes from B to A.
   Typically, on thread A you register for the managed object context save notification, NSManagedObjectContextDidSaveNotification.
   When you receive the notification, its user info dictionary contains arrays with the managed objects that were inserted, deleted, and updated on thread B.
   Because the managed objects are associated with a different thread, however, you should not access them directly.
   Instead, you pass the notification as an argument to mergeChangesFromContextDidSaveNotification: (which you send to the context on thread A). Using this method, the context is able to safely merge the changes.

   If you need finer-grained control, you can use the managed object context change notification, NSManagedObjectContextObjectsDidChangeNotification—the notification’s user info dictionary again contains arrays with the managed objects that were inserted, deleted, and updated. In this scenario, however, you register for the notification on thread B.
   When you receive the notification, the managed objects in the user info dictionary are associated with the same thread, so you can access their object IDs.
   You pass the object IDs to thread A by sending a suitable message to an object on thread A. Upon receipt, on thread A you can refetch the corresponding managed objects.

   Note that the change notification is sent in NSManagedObjectContext’s processPendingChanges method.
   The main thread is tied into the event cycle for the application so that processPendingChanges is invoked automatically after every user event on contexts owned by the main thread.
   This is not the case for background threads—when the method is invoked depends on both the platform and the release version, so you should not rely on particular timing.
   ▶️ If the secondary context is not on the main thread, you should call processPendingChanges yourself at appropriate junctures.
   (You need to establish your own notion of a work “cycle” for a background thread—for example, after every cluster of actions.)
   **/

  /**
   From Apple DTS (about automaticallyMergesChangesFromParent and didChange notification):

   Core Data triggers the didChange notification when the context is “indeed” changed, or the changes will have impact to you. Here is the logic:

   1. Merging new objects does change the context, so the notification is always triggered.
   2. Merging deleted objects changes the context when the deleted objects are in use (or in other word, are held by your code).
   3. Merging updated objects changes the context when the updated objects are in use and not faulted.
   **/

  // MARK: - NSManagedObjectContextObjectsDidChange

  func testObserveInsertionsOnDidChangeNotification() {
    let context = container.viewContext
    let expectation = self.expectation(description: "\(#function)\(#line)")

    context.performAndWait {
      let car = Car(context: context)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = "1"
      car.maker = "123!"
    }

    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === context)
        XCTAssertEqual(payload.insertedObjects.count, 1)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    waitForExpectations(timeout: 2)
    cancellable.cancel()
  }


  func testObserveInsertionsOnDidChangeNotificationOnBackgroundContext() {
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let backgroundContext = container.newBackgroundContext()
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: backgroundContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === backgroundContext)
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(payload.insertedObjects.count, 1)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    backgroundContext.performAndWait {
      let car = Car(context: backgroundContext)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = "1"
      car.maker = "123!"
      backgroundContext.processPendingChanges() // on a background context, processPendingChanges() must be called to trigger the notification
    }
    waitForExpectations(timeout: 5)
    cancellable.cancel()
  }

  func testObserveAsyncInsertionsOnDidChangeNotificationOnBackgroundContext() {
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let backgroundContext = container.newBackgroundContext()
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: backgroundContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === backgroundContext)
        XCTAssertFalse(Thread.isMainThread) // `perform` is async, and it is responsible for posting this notification.
        XCTAssertEqual(payload.insertedObjects.count, 1)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    // perform, as stated in the documentation, calls internally processPendingChanges
    backgroundContext.perform {
      XCTAssertFalse(Thread.isMainThread)
      let car = Car(context: backgroundContext)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = "1"
      car.maker = "123!"
    }
    waitForExpectations(timeout: 5)
    cancellable.cancel()
  }

  func testObserveAsyncInsertionsOnDidChangeNotificationOnBackgroundContextAndDispatchQueue() {
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let backgroundContext = container.newBackgroundContext()
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: backgroundContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === backgroundContext)
        XCTAssertFalse(Thread.isMainThread) // `perform` is async, and it is responsible for posting this notification.
        XCTAssertEqual(payload.insertedObjects.count, 200)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    // performBlockAndWait will always run in the calling thread.
    // Using a DispatchQueue, we are making sure that it's not run on the Main Thread
    DispatchQueue.global().async {
      backgroundContext.performAndWait {
        XCTAssertFalse(Thread.isMainThread)
        (1...100).forEach({ i in
          let car = Car(context: backgroundContext)
          car.maker = "FIAT"
          car.model = "Panda"
          car.numberPlate = UUID().uuidString
          car.maker = "123!"
          let person = Person(context: backgroundContext)
          person.firstName = UUID().uuidString
          person.lastName = UUID().uuidString
          car.owner = person
        })
        XCTAssertTrue(backgroundContext.hasChanges, "The context should have uncommitted changes.")
        backgroundContext.processPendingChanges()
      }
    }

    waitForExpectations(timeout: 5)
    cancellable.cancel()
  }


  func testObserveInsertionsOnDidChangeNotificationOnPrivateContext() throws {
    let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    privateContext.persistentStoreCoordinator = container.persistentStoreCoordinator
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: privateContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === privateContext)
        XCTAssertEqual(payload.insertedObjects.count, 1)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    privateContext.performAndWait {
      let car = Car(context: privateContext)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = "1"
      car.maker = "123!"
      privateContext.processPendingChanges()
    }
    waitForExpectations(timeout: 5)
    cancellable.cancel()
  }

  func testObserveRefreshedObjectsOnDidChangeNotification() throws {
    let context = container.viewContext
    context.fillWithSampleData()
    try context.save()
    let registeredObjectsCount = context.registeredObjects.count
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === context)
        XCTAssertTrue(payload.insertedObjects.isEmpty)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertEqual(payload.refreshedObjects.count, registeredObjectsCount)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    context.refreshAllObjects()

    waitForExpectations(timeout: 5)
    cancellable.cancel()
  }

  // probably it's not a valid test
  func testObserveOnlyInsertionsOnDidChangeUsingBackgroundContextsAndAutomaticallyMergesChangesFromParent() throws {
    let backgroundContext1 = container.newBackgroundContext()
    let backgroundContext2 = container.newBackgroundContext()
    backgroundContext2.automaticallyMergesChangesFromParent = true // This cause a change not a save, obviously

    // From Apple DTS:
    // Core Data triggers the didChange notification when the context is “indeed” changed, or the changes will have impact to you. Here is the logic:
    //  1. Merging new objects does change the context, so the notification is always triggered.
    //  2. Merging deleted objects changes the context when the deleted objects are in use (or in other word, are held by your code).
    //  3. Merging updated objects changes the context when the updated objects are in use and not faulted.

    let expectation = self.expectation(description: "\(#function)\(#line)")
    expectation.expectedFulfillmentCount = 1
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: backgroundContext2)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === backgroundContext2)
        XCTAssertEqual(payload.insertedObjects.count, 1)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    try backgroundContext1.performSaveAndWait { context in
      let car = Car(context: backgroundContext1)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = "1"
      car.maker = "123!"
    }

    // no objects are used (kept and materialized by backgroundContext2) so a delete notification will not be triggered
    try backgroundContext1.performSaveAndWait { context in
      try Car.delete(in: context)
    }

    waitForExpectations(timeout: 2)
    cancellable.cancel()
  }

  func testObserveMultipleChangesOnMaterializedObjects() throws {
    let viewContext = container.newBackgroundContext()
    viewContext.automaticallyMergesChangesFromParent = true // This cause a change not a save, obviously

    let backgroundContext1 = container.newBackgroundContext()
    let backgroundContext2 = container.newBackgroundContext()

    let expectation1 = self.expectation(description: "Changes on Contex1")
    let expectation2 = self.expectation(description: "Changes on Contex2")
    let expectation3 = self.expectation(description: "New Changes on Contex1")

    // From Apple DTS:
    // Core Data triggers the didChange notification when the context is “indeed” changed, or the changes will have impact to you. Here is the logic:
    //  1. Merging new objects does change the context, so the notification is always triggered.
    //  2. Merging deleted objects changes the context when the deleted objects are in use (or in other word, are held by your code).
    //  3. Merging updated objects changes the context when the updated objects are in use and not faulted.

    var count = 0
    var holds = Set<NSManagedObject>()
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(payload.managedObjectContext === viewContext)
        switch count {
        case 0:
          XCTAssertFalse(Thread.isMainThread)
          XCTAssertEqual(payload.insertedObjects.count, 1)
          XCTAssertTrue(payload.deletedObjects.isEmpty)
          XCTAssertTrue(payload.refreshedObjects.isEmpty)
          XCTAssertTrue(payload.updatedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)

          // To register changes from other contexts, we need to materialize and keep object inserted from other contexts
          // otherwise you will receive notifications only for used objects (in this case there are used objects by context0)
          payload.insertedObjects.forEach {
            $0.willAccessValue(forKey: nil)
            holds.insert($0)
          }
          count += 1
          expectation1.fulfill()
        case 1:
          XCTAssertFalse(Thread.isMainThread)
          XCTAssertEqual(payload.refreshedObjects.count, 1)
          count += 1
          expectation2.fulfill()
        case 2:
          XCTAssertTrue(Thread.isMainThread)
          XCTAssertEqual(payload.updatedObjects.count, 1)
          count += 1
          expectation3.fulfill()
        default:
          #if !targetEnvironment(macCatalyst)
          // DTS:
          // It seems like when ‘automaticallyMergesChangesFromParent’ is true, Core Data on macOS still merge the changes,
          // even though the changes are from the same context, which is not optimized.
          //
          // FB:
          // There are subtle differences in behavior of the runloop between UIApplication and NSApplication.
          // Observing just change notifications makes no promises about how many there may be because change notifications are
          // posted at the end of the run loop and whenever CoreData feels like it (the application lifecycle spins the main run loop).
          // Save notifications get called once per save.
          XCTFail("Unexpected change.")
          #endif
        }
    }


    let numberPlate = "123!"
    try backgroundContext1.performSaveAndWait { context in
      let car = Car(context: context)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = numberPlate
    }

    wait(for: [expectation1], timeout: 5)

    try backgroundContext2.performSaveAndWait { context in
      let uniqueCar = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), numberPlate) }
      guard let car = uniqueCar else {
        XCTFail("Car not found")
        return
      }
      car.model = "**Panda**"
    }

    wait(for: [expectation2], timeout: 5)

    try viewContext.performSaveAndWait { context in
      let uniqueCar = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), numberPlate) }
      guard let car = uniqueCar else {
        XCTFail("Car not found")
        return
      }
      car.maker = "**FIAT**"
    }

    wait(for: [expectation3], timeout: 5)
    cancellable.cancel()
  }

  func testObserveRefreshesOnMaterializedObjects() throws {
    let backgroundContext1 = container.newBackgroundContext()
    let backgroundContext2 = container.newBackgroundContext()

    // 10 Pandas are created on backgroundContext2
    try backgroundContext2.performSaveAndWait { context in
      (1...10).forEach { numberPlate in
        let car = Car(context: context)
        car.maker = "FIAT"
        car.model = "Panda"
        car.numberPlate = "\(numberPlate)"
      }
    }

    // From Apple DTS:
    // Core Data triggers the didChange notification when the context is “indeed” changed, or the changes will have impact to you. Here is the logic:
    //  1. Merging new objects does change the context, so the notification is always triggered.
    //  2. Merging deleted objects changes the context when the deleted objects are in use (or in other word, are held by your code).
    //  3. Merging updated objects changes the context when the updated objects are in use and not faulted.

    let viewContext = container.viewContext
    viewContext.automaticallyMergesChangesFromParent = true // This cause a change not a save, obviously

    // We fetch and materialize only 2 Pandas: changes are expected only when they impact these two cars.
    let fetch = Car.newFetchRequest()
    fetch.predicate = NSPredicate(format: "%K IN %@", #keyPath(Car.numberPlate), ["1", "2"] )
    let cars = try viewContext.fetch(fetch)
    cars.forEach { $0.willAccessValue(forKey: nil) }
    XCTAssertEqual(cars.count, 2)

    let expectation1 = self.expectation(description: "DidChange for Panda with number plate: 2")
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(payload.managedObjectContext === viewContext)
        XCTAssertTrue(payload.insertedObjects.isEmpty)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertEqual(payload.refreshedObjects.count, 1)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation1.fulfill()
    }


    // car with n. 3, doesn't impact the didChange because it's not materialized in context0
    try backgroundContext2.performSaveAndWait { context in
      let uniqueCar = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), "3") }
      guard let car = uniqueCar else {
        XCTFail("Car not found")
        return
      }
      car.model = "**Panda**"
    }

    // car with n. 6, doesn't impact the didChange because it's not materialized in context0
    try backgroundContext1.performSaveAndWait { context in
      let uniqueCar = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), "6") }
      guard let car = uniqueCar else {
        XCTFail("Car not found")
        return
      }
      car.delete()
    }

    // car with n. 2, impact the didChange because it's materialized in context0
    try backgroundContext2.performSaveAndWait { context in
      let uniqueCar = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), "2") }
      guard let car = uniqueCar else {
        XCTFail("Car not found")
        return
      }
      car.model = "**Panda**"
    }

    waitForExpectations(timeout: 5)
    cancellable.cancel()
  }

  // MARK: - NSManagedObjectContextWillSave and NSManagedObjectContextDidSave

  func testObserveInsertionsOnWillSaveNotification() throws {
    let context = container.viewContext
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextWillSave, object: context)
      .map { Payload.NSManagedObjectContextWillSave(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === context)
        expectation.fulfill()
    }

    let car = Car(context: context)
    car.maker = "FIAT"
    car.model = "Panda"
    car.numberPlate = "1"
    car.maker = "123!"

    try context.save()
    waitForExpectations(timeout: 2)
    cancellable.cancel()
  }

  func testObserveInsertionsOnDidSaveNotification() throws {
    let context = container.viewContext
    let expectation = self.expectation(description: "\(#function)\(#line)")
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)
      .map { Payload.NSManagedObjectContextDidSave(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertFalse(payload.isEmpty)
        XCTAssertTrue(payload.managedObjectContext === context)
        XCTAssertEqual(payload.insertedObjects.count, 1)
        XCTAssertTrue(payload.deletedObjects.isEmpty)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.updatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    let car = Car(context: context)
    car.maker = "FIAT"
    car.model = "Panda"
    car.numberPlate = "1"
    car.maker = "123!"

    try context.save()
    waitForExpectations(timeout: 2)
    cancellable.cancel()
  }

  func testObserveInsertionsUpdatesAndDeletesOnDidSaveNotification() throws {
    let context = container.viewContext
    let expectation = self.expectation(description: "\(#function)\(#line)")

    let car1 = Car(context: context)
    car1.maker = "FIAT"
    car1.model = "Panda"
    car1.numberPlate = UUID().uuidString
    car1.maker = "maker"

    let car2 = Car(context: context)
    car2.maker = "FIAT"
    car2.model = "Punto"
    car2.numberPlate = UUID().uuidString
    car2.maker = "maker"

    try context.save()

    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: context)
      .map { Payload.NSManagedObjectContextDidSave(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === context)
        XCTAssertEqual(payload.insertedObjects.count, 2)
        XCTAssertEqual(payload.deletedObjects.count, 1)
        XCTAssertEqual(payload.updatedObjects.count, 1)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation.fulfill()
    }

    // 2 inserts
    let car3 = Car(context: context)
    car3.maker = "FIAT"
    car3.model = "Qubo"
    car3.numberPlate = UUID().uuidString
    car3.maker = "maker"

    let car4 = Car(context: context)
    car4.maker = "FIAT"
    car4.model = "500"
    car4.numberPlate = UUID().uuidString
    car4.maker = "maker"

    // 1 update
    car1.model = "new Panda"
    // 1 delete
    car2.delete()

    try context.save()
    waitForExpectations(timeout: 2)
    cancellable.cancel()
  }

  func testObserveMultipleChangesUsingPersistentStoreCoordinatorWithChildAndParentContexts() throws {
    // Given
    let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
    let storeURL = URL.newDatabaseURL(withID: UUID())
    try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)

    let parentContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    parentContext.persistentStoreCoordinator = psc

    let childContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    childContext.parent = parentContext

    let childContext2 = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    childContext2.parent = parentContext

    let expectation = self.expectation(description: "\(#function)\(#line)")
    let expectation2 = self.expectation(description: "\(#function)\(#line)")

    let car1Plate = UUID().uuidString
    let car2Plate = UUID().uuidString

    // When, Then
    try childContext.performAndWaitResult { context in
      let car1 = Car(context: context)
      let car2 = Car(context: context)
      car1.maker = "FIAT"
      car1.model = "Panda"
      car1.numberPlate = car1Plate
      car1.maker = "maker"

      car2.maker = "FIAT"
      car2.model = "Punto"
      car2.numberPlate = car2Plate
      car2.maker = "maker"
      try context.save()
    }

    try parentContext.performAndWaitResult { context in
      try context.save()
    }

    // Changes are propagated from the child to the parent during the save.
    var count = 0
    let cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: parentContext)
      .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        if count == 0 {
          XCTAssertTrue(payload.managedObjectContext === parentContext)
          XCTAssertEqual(payload.insertedObjects.count, 2)
          XCTAssertTrue(payload.deletedObjects.isEmpty)
          XCTAssertTrue(payload.updatedObjects.isEmpty)
          XCTAssertTrue(payload.refreshedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
          count += 1
        } else if count == 1 {
          XCTAssertTrue(payload.managedObjectContext === parentContext)
          XCTAssertTrue(payload.insertedObjects.isEmpty)
          XCTAssertTrue(payload.deletedObjects.isEmpty)
          XCTAssertEqual(payload.updatedObjects.count, 1)
          XCTAssertTrue(payload.refreshedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
          count += 1
        } else if count == 2 {
          XCTAssertTrue(payload.managedObjectContext === parentContext)
          XCTAssertTrue(payload.insertedObjects.isEmpty)
          XCTAssertEqual(payload.deletedObjects.count, 1)
          XCTAssertTrue(payload.updatedObjects.isEmpty)
          XCTAssertTrue(payload.refreshedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
          count += 1
        } else if count == 3 {
          XCTAssertTrue(payload.managedObjectContext === parentContext)
          XCTAssertEqual(payload.insertedObjects.count, 1)
          XCTAssertTrue(payload.deletedObjects.isEmpty)
          XCTAssertTrue(payload.updatedObjects.isEmpty)
          XCTAssertTrue(payload.refreshedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedObjects.isEmpty)
          XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
          expectation.fulfill()
        }
    }

    let cancellable2 = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: parentContext)
      .map { Payload.NSManagedObjectContextDidSave(notification: $0) }
      .sink { payload in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertTrue(payload.managedObjectContext === parentContext)
        XCTAssertEqual(payload.insertedObjects.count, 3)
        XCTAssertEqual(payload.deletedObjects.count, 1)
        XCTAssertEqual(payload.updatedObjects.count, 1)
        XCTAssertTrue(payload.refreshedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedObjects.isEmpty)
        XCTAssertTrue(payload.invalidatedAllObjects.isEmpty)
        expectation2.fulfill()
    }

    try childContext.performSaveAndWait { context in
      // 2 inserts
      let car3 = Car(context: context)
      car3.maker = "FIAT"
      car3.model = "Qubo"
      car3.numberPlate = UUID().uuidString

      let car4 = Car(context: context)
      car4.maker = "FIAT"
      car4.model = "500"
      car4.numberPlate = UUID().uuidString
      // the save triggers the didChange event
    }

    try childContext.performSaveAndWait { context in
      let uniqueCar1 = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), car1Plate) }
      guard let car1 = uniqueCar1 else {
        XCTFail("Car not found.")
        return
      }
      car1.model = "Panda 1**"
      car1.maker = "FIAT**"
      car1.numberPlate = "111**"
    }

    try childContext.performSaveAndWait { context in
      let uniqueCar2 = try Car.fetchUnique(in: context) { $0.predicate = NSPredicate(format: "%K == %@", #keyPath(Car.numberPlate), car2Plate) }
      guard let car2 = uniqueCar2 else {
        XCTFail("Car not found.")
        return
      }
      car2.delete()
    }

    try childContext2.performSaveAndWait { context in
      let car5 = Car(context: context)
      car5.maker = "FIAT"
      car5.model = "500"
      car5.numberPlate = UUID().uuidString
    }

    try parentContext.performAndWaitResult { context in
      try context.save() // triggers the didSave event
    }

    waitForExpectations(timeout: 10)


    // cleaning stuff
    let store = psc.persistentStores.first!
    try psc.remove(store)
    try NSPersistentStoreCoordinator.destroyStore(at: storeURL)
    cancellable.cancel()
    cancellable2.cancel()
  }

  // MARK: - Entity Observer Example

    func testObserveInsertedOnDidChangeEventForSpecificEntities() {
      let context = container.viewContext
      let expectation1 = expectation(description: "\(#function)\(#line)")

      // Attention: sometimes entity() returns nil due to a CoreData bug occurring in the Unit Test targets or when Generics are used.
      // let entity = NSEntityDescription.entity(forEntityName: type.entity().name!, in: context)!

      func findObjectsOfType<T:NSManagedObject>(_ type: T.Type, in objects: Set<NSManagedObject>, observeSubEntities: Bool = true) -> Set<T> {
        let entity = type.entity()
        if observeSubEntities {
          return objects.filter { $0.entity.isSubEntity(of: entity, recursive: true) || $0.entity == entity } as? Set<T> ?? []
        } else {
          return objects.filter { $0.entity == entity } as? Set<T> ?? []
        }
      }

      let cancellable = NotificationCenter.default.publisher(for: Notification.Name.NSManagedObjectContextObjectsDidChange, object: context)
        .map { Payload.NSManagedObjectContextObjectsDidChange(notification: $0) }
        .sink { payload in
          let inserts = findObjectsOfType(SportCar.self, in: payload.insertedObjects, observeSubEntities: true)
          let inserts2 = findObjectsOfType(Car.self, in: payload.insertedObjects, observeSubEntities: true)
          let inserts3 = findObjectsOfType(Car.self, in: payload.insertedObjects, observeSubEntities: false)
          let deletes = findObjectsOfType(SportCar.self, in: payload.deletedObjects, observeSubEntities: true)
          let udpates = findObjectsOfType(SportCar.self, in: payload.updatedObjects, observeSubEntities: true)
          let refreshes = findObjectsOfType(SportCar.self, in: payload.refreshedObjects, observeSubEntities: true)
          let invalidates = findObjectsOfType(SportCar.self, in: payload.invalidatedObjects, observeSubEntities: true)
          let invalidatesAll = payload.invalidatedAllObjects.filter { $0.entity == SportCar.entity() }

          XCTAssertEqual(inserts.count, 1)
          XCTAssertEqual(inserts2.count, 2)
          XCTAssertEqual(inserts3.count, 1)
          XCTAssertTrue(deletes.isEmpty)
          XCTAssertTrue(udpates.isEmpty)
          XCTAssertTrue(refreshes.isEmpty)
          XCTAssertTrue(invalidates.isEmpty)
          XCTAssertTrue(invalidatesAll.isEmpty)
          expectation1.fulfill()
      }

      let sportCar = SportCar(context: context)
      sportCar.maker = "McLaren"
      sportCar.model = "570GT"
      sportCar.numberPlate = "203"

      let car = Car(context: context)
      car.maker = "FIAT"
      car.model = "Panda"
      car.numberPlate = "1"

      let person1 = Person(context: context)
      person1.firstName = "Edythe"
      person1.lastName = "Moreton"

      waitForExpectations(timeout: 2)
      cancellable.cancel()
    }

  // MARK: - NSPersistentStoreRemoteChange

  func testInvestigationPersistentStoreRemoteChangeAndBatchOperations() throws {
    // Cross coordinator change notifications:
    // This notification notifies when history has been made even when batch operations are done.

    let container1 = InMemoryPersistentContainer.makeNew(named: "123")
    let container2 = InMemoryPersistentContainer.makeNew(named: "123")

    // Given
    let viewContext1 = container1.viewContext
    viewContext1.name = "viewContext1"
    viewContext1.transactionAuthor = "author1"

    let expectation1 = expectation(description: "NSPersistentStoreRemoteChange Notification sent by container1")
    let cancellable1 = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: container1.persistentStoreCoordinator)
      .map { Payload.NSPersistentStoreRemoteChange(notification: $0) }
      .sink { payload in
        XCTAssertNotNil(payload.historyToken)
        XCTAssertEqual(payload.storeURL, container1.persistentStoreCoordinator.persistentStores.first?.url)
      expectation1.fulfill()
    }

    let expectation2 = expectation(description: "NSPersistentStoreRemoteChange Notification sent by container2")
    let cancellable2 = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: container2.persistentStoreCoordinator)
      .map { Payload.NSPersistentStoreRemoteChange(notification: $0) }
      .sink { payload in
              XCTAssertNotNil(payload.historyToken)
        XCTAssertEqual(payload.storeURL, container2.persistentStoreCoordinator.persistentStores.first?.url)
      expectation2.fulfill()
    }

    let object = [#keyPath(Car.maker): "FIAT",
                  #keyPath(Car.numberPlate): "123",
                  #keyPath(Car.model): "Panda"]

    let result = try Car.batchInsert(using: viewContext1, resultType: .count, objects: [object])
    XCTAssertEqual(result.count!, 1)

    waitForExpectations(timeout: 5, handler: nil)
    cancellable1.cancel()
    cancellable2.cancel()
  }
}