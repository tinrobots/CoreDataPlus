// CoreDataPlus

import CoreData

extension NSFetchRequestResult where Self: NSManagedObject {
  /// The entity name.
  /// - Warning: The NSManagedObjectModel must be loaded or the execution will be stopped.
  public static var entityName: String {
    if let name = entity().name {
      return name
    }
    // https://stackoverflow.com/questions/37909392/exc-bad-access-when-calling-new-entity-method-in-ios-10-macos-sierra-core-da
    // https://stackoverflow.com/questions/43231873/nspersistentcontainer-unittests-with-ios10/43286175
    // https://www.jessesquires.com/blog/swift-coredata-and-testing/
    // https://github.com/jessesquires/rdar-19368054

    // Returning a string representation of Self metatype doesn't work if you have a NSManagedObject subclass
    // with a name different from the NSEntityDescription name.
    // return String(describing: Self.self)

    // see testEntityName()
    fatalError("Have you loaded your NSManagedObjectModel yet?")
  }

  // MARK: - Fetch

  /// Returns a new fetch request initialized with the entity represented by this subclass (`self`).
  /// - Warning: This fetch request is created with a string name (`entityName`), and cannot respond to -entity until used by an NSManagedObjectContex.
  public static func newFetchRequest() -> NSFetchRequest<Self> {
    NSFetchRequest<Self>(entityName: entityName)
  }

  /// - Returns: an object for a specified `id` even if the object needs to be fetched.
  /// If the object is not registered in the context, it may be fetched or returned as a fault.
  /// If use existingObject(with:) if you don't want a faulted object.
  public static func object(with id: NSManagedObjectID, in context: NSManagedObjectContext) -> Self? {
    context.object(with: id) as? Self
  }

  /// - Returns: the object for the specified ID or nil if the object does not exist.
  /// If there is a managed object with the given ID already registered in the context, that object is returned directly; otherwise the corresponding object is faulted into the context.
  /// This method might perform I/O if the data is uncached.
  /// - Important: Unlike object(with:), this method never returns a fault.
  public static func existingObject(with id: NSManagedObjectID, in context: NSManagedObjectContext) throws -> Self? {
    try context.existingObject(with: id) as? Self
  }

  /// Performs a configurable fetch request in a context.
  /// - Note: It always accesses the underlying persistent stores to retrieve the latest results.
  /// - Attention: Core Data makes heavy use of Futures, especially for relationship values.
  /// For fetch requests with batching enabled, you probably do not want a Swift *Array* but instead an *NSArray* to avoid making an immediate copy of the future.
  /// See `fetchAsNSArray(in:with:)`. (Relationships are defined as *NSSet* and not as Swift *Set* for the same very reason).
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - configuration: Configuration closure applied **only** before fetching.
  /// - Throws: It throws an error in cases of failure.
  /// - Returns: An array of objects meeting the criteria specified by request fetched from *the receiver* and from *the persistent stores* associated with the receiver’s persistent store coordinator.
  public static func fetch(in context: NSManagedObjectContext, with configuration: (NSFetchRequest<Self>) -> Void = { _ in }) throws -> [Self] {
    // Check the Discussion paragraph for the fetch(_:) documentation:
    // https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/1506672-fetch
    // When you execute an instance of NSFetchRequest, it always accesses the underlying persistent stores to retrieve the latest results.
    // https://developer.apple.com/documentation/coredata/nsfetchrequest
    let request = NSFetchRequest<Self>(entityName: entityName)
    configuration(request)
    return try context.fetch(request)
  }

  /// Performs a configurable fetch request in a context.
  /// - Note: When fetching data from Core Data, you don’t always know how many values you’ll be getting back.
  /// Core Data solves this problem by using a subclass of `NSArray` that will dynamically pull in data from the underlying store on demand.
  /// On the other hand, a Swift `Array` requires having every element in the array all at once, and bridging an `NSArray` to a Swift `Array` requires retrieving every single value.
  /// - Warning: **Batched requests** are supported only when returning a `NSArray`.
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - configuration: Configuration closure applied **only** before fetching.
  /// - Throws: It throws an error in cases of failure.
  /// - Returns: Returns an array of objects that meet the criteria specified by a given fetch request.
  public static func fetchNSArray(in context: NSManagedObjectContext, with configuration: (NSFetchRequest<Self>) -> Void = { _ in }) throws -> NSArray {
    // Check the Discussion paragraph for the fetch(_:) documentation:
    // https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/1506672-fetch

    // When you execute an instance of NSFetchRequest, it always accesses the underlying persistent stores to retrieve the latest results.
    // https://developer.apple.com/documentation/coredata/nsfetchrequest

    let request = NSFetchRequest<Self>(entityName: entityName)
    configuration(request)

    return try context.fetchNSArray(request)
  }

  /// Fetches all the `NSManagedObjectID` for a given predicate.
  /// - Note: it always accesses the underlying persistent stores to retrieve the latest results.
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - includingSubentities: A Boolean value that indicates whether the fetch request includes subentities in the results.
  ///   - predicate: Matching predicate.
  ///   - affectedStores: An array of persistent stores specified for the fetch request.
  /// - Returns: A list of `NSManagedObjectID`.
  /// - Throws: It throws an error in cases of failure.
  public static func fetchObjectIDs(in context: NSManagedObjectContext, includingSubentities: Bool = true, where predicate: NSPredicate, affectedStores: [NSPersistentStore]? = nil) throws -> [NSManagedObjectID] {
    let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
    // If includesPropertyValues is false, then Core Data fetches only the object ID information for the matching records—it does not populate the row cache.
    //
    // If you set the value to managedObjectIDResultType,
    // and do not include property values in the request, sort orderings are demoted to “best efforts” hints.
    // https://developer.apple.com/documentation/coredata/nsfetchrequest/1506189-resulttype?changes=_3_2
    //
    // If includesPropertyValues is true and resultType is set to managedObjectIDResultType,
    // the properties are fetched even though they are not being presented to the application and can result in a significant performance penalty.
    // https://developer.apple.com/documentation/coredata/nsfetchrequest/1506387-includespropertyvalues?changes=_3_2
    request.includesPropertyValues = false
    request.returnsObjectsAsFaults = true
    request.resultType = .managedObjectIDResultType
    request.includesSubentities = includingSubentities
    request.predicate = predicate
    request.affectedStores = affectedStores

    return try context.fetch(request)
  }

  // MARK: - First

  /// Fetches an object matching the given predicate.
  /// - Note: it always accesses the underlying persistent stores to retrieve the latest results.
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - predicate: Matching predicate.
  ///   - includesPendingChanges: A Boolean value that indicates whether, when the fetch is executed, it matches against currently unsaved changes in the managed object context.
  ///   - affectedStores: An array of persistent stores specified for the fetch request.
  /// - Throws: It throws an error in cases of failure.
  /// - Returns: A **materialized** object matching the predicate.
  public static func fetchOne(in context: NSManagedObjectContext, where predicate: NSPredicate, includesPendingChanges: Bool = true, affectedStores: [NSPersistentStore]? = nil) throws -> Self? {
    return try fetch(in: context) { request in
      request.predicate = predicate
      request.returnsObjectsAsFaults = false
      request.includesPendingChanges = includesPendingChanges
      request.affectedStores = affectedStores
      request.fetchLimit = 1
    }.first
  }

  /// Attempts to find an object matching a predicate or creates a new one and configures it (if multiple objects are found, configures the **first** one).
  ///
  /// For uniqueness, use `findUniqueOrCreate(in:where:with) instead.
  /// - Note: It searches for a matching materialized object in the given context before accessing the underlying persistent stores.
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - predicate: Matching predicate.
  ///   - configuration: Configuration closure called **only** when creating a new object.
  /// - Returns: A matching object or a configured new one.
  /// - Throws: It throws an error in cases of failure.
  public static func findOneOrCreate(in context: NSManagedObjectContext, where predicate: NSPredicate, with configuration: (Self) -> Void) throws -> Self {
    guard let object = try materializedObjectOrFetch(in: context, where: predicate) else {
      let newObject = Self(context: context)
      configuration(newObject)
      return newObject
    }
    return object
  }

  /// Tries to find the first existing object in the context (memory) matching a predicate.
  /// If it doesn’t find a matching materialized object in the context, tries to load it using a fetch request (if multiple objects are found, returns the **first** one).
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - predicate: Matching predicate.
  /// - Returns: The first materialized matching object (if any).
  /// - Throws: It throws an error in cases of failure.
  public static func materializedObjectOrFetch(in context: NSManagedObjectContext, where predicate: NSPredicate) throws -> Self? {
    // first we should fetch an existing object in the context as a performance optimization
    guard let object = materializedObject(in: context, where: predicate) else {
      // if it's not in memory, we should execute a fetch to see if it exists
      // NSFetchRequest always accesses the underlying persistent stores to retrieve the latest results.
      return try fetchOne(in: context, where: predicate)
    }
    return object
  }

  // MARK: - Unique

  /// Attempts to find an unique object matching a predicate or creates a new one and configures it;
  /// if uniqueness is not guaranted (more than one object matching the predicate) a fatal error will occour.
  ///
  /// If uniqueness is not relevant, use `findOneOrCreate(in:where:with) instead.
  /// - Note: it always accesses the underlying persistent stores to retrieve the latest results.
  ///
  /// - Parameters:
  ///   - context: Searched context.
  ///   - predicate: Matching predicate.
  ///   - affectedStores: An array of persistent stores specified for the fetch request.
  ///   - assignedStore: A persistent store in which the newly inserted object will be saved.
  ///   - configuration: Configuration closure called **only** when creating a new object.
  /// - Returns: A matching object or a configured new one.
  /// - Throws: It throws an error in cases of failure.
  public static func findUniqueOrCreate(in context: NSManagedObjectContext,
                                        where predicate: NSPredicate,
                                        affectedStores: [NSPersistentStore]? = nil,
                                        assignedStore: NSPersistentStore? = nil,
                                        with configuration: (Self) -> Void) throws -> Self {
    let uniqueObject = try fetchUnique(in: context, where: predicate, affectedStores: affectedStores)
    guard let object = uniqueObject else {
      let newObject = Self(context: context)
      configuration(newObject)
      if let store = assignedStore {
        context.assign(newObject, to: store)
      }
      return newObject
    }

    return object
  }

  /// Executes a fetch request where **at most** a single object is expected as result; if more than one object are fetched, a fatal error will occour.
  /// - Note: To guarantee uniqueness the fetch accesses the underlying persistent stores to retrieve the latest results and, also, matches against currently
  /// unsaved changes in the managed object context.
  ///
  /// - Parameters:
  ///   - context: Searched context
  ///   - predicate: Matching predicate.
  ///   - affectedStores: An array of persistent stores specified for the fetch request.
  /// - Returns: An unique object matching the given configuration (if any).
  public static func fetchUnique(in context: NSManagedObjectContext, where predicate: NSPredicate, affectedStores: [NSPersistentStore]? = nil) throws -> Self? {
    let result = try fetch(in: context) { request in
      request.predicate = predicate
      request.includesPendingChanges = true // default, uniqueness should be guaranteed
      request.affectedStores = affectedStores
      request.fetchLimit = 2
    }

    switch result.count {
      case 0:
        return nil
      case 1:
        return result[0]
      default:
        fatalError("Returned multiple objects, expected max 1.")
    }
  }

  // MARK: - Delete

  /// Specifies the objects (matching a given `predicate`) that should be removed from its persistent store when changes are committed.
  /// If objects have not yet been saved to a persistent store, they are simply removed from the context.
  /// If the dataset to delete is very large, use the `limit` value to decide the number of objects to be deleted otherwise the operation could last an unbounded amount time.
  /// If `includingSubentities` is set to `false`, sub-entities will be ignored.
  /// - Note: `NSBatchDeleteRequest` would be more efficient but requires a context with an `NSPersistentStoreCoordinator` directly connected (no child context).
  /// - Throws: It throws an error in cases of failure.
  public static func delete(in context: NSManagedObjectContext, includingSubentities: Bool = true, where predicate: NSPredicate = NSPredicate(value: true), limit: Int? = nil, affectedStores: [NSPersistentStore]? = nil) throws {
    try autoreleasepool {
      try fetch(in: context) { request in
        request.includesPropertyValues = false
        request.includesSubentities = includingSubentities
        request.predicate = predicate
        request.affectedStores = affectedStores // TODO add params in the documentation
        if let limit = limit {
          // there could be a very large data set, the delete operation could last an unbounded amount time
          request.fetchLimit = limit
        }
      }.lazy.forEach(context.delete(_:))
    }
  }

  /// Removes all entities from within the specified `NSManagedObjectContext` excluding a given list of entities.
  ///
  /// - Parameters:
  ///   - context: The `NSManagedObjectContext` to remove the Entities from.
  ///   - objects: An Array of `NSManagedObjects` belonging to the `NSManagedObjectContext` to exclude from deletion.
  ///   - affectedStores: An array of persistent stores specified for the fetch request.
  /// - Throws: It throws an error in cases of failure.
  /// - Note: `NSBatchDeleteRequest` would be more efficient but requires a context with an `NSPersistentStoreCoordinator` directly connected (no child context).
  public static func delete(in context: NSManagedObjectContext, except objects: [Self], affectedStores: [NSPersistentStore]? = nil) throws {
    let predicate = NSPredicate(format: "NOT (self IN %@)", objects)
    try delete(in: context, includingSubentities: true, where: predicate, affectedStores: affectedStores)
  }

  // MARK: - Count

  /// Counts the results of a configurable fetch request in a context.
  /// - Throws: It throws an error in cases of failure.
  public static func count(in context: NSManagedObjectContext, for configuration: (NSFetchRequest<Self>) -> Void = { _ in }) throws -> Int {
    let request = newFetchRequest()
    configuration(request)

    let result = try context.count(for: request)
    // result is equal to NSNotFound if an error occurs (an exception is expected to be thrown)
    guard result != NSNotFound else { return 0 }

    return result
  }

  // MARK: - Materialized Object

  /// Iterates over the context’s registeredObjects set (which contains all managed objects the context currently knows about) until it finds one that is not a fault matching for a given predicate.
  /// Faulted objects are not considered to prevent Core Data to make a round trip to the persistent store.
  ///
  /// - Parameters:
  ///   - context: Searched context
  ///   - predicate: Matching predicate.
  /// - Returns: The first materialized object matching the predicate.
  public static func materializedObject(in context: NSManagedObjectContext, where predicate: NSPredicate) -> Self? {
    for object in context.registeredObjects where !object.isFault {
      guard let result = object as? Self, predicate.evaluate(with: result) else { continue }

      return result
    }
    return nil
  }

  /// Iterates over the context’s registeredObjects set (which contains all managed objects the context currently knows about) until it finds
  /// all the objects that aren't a fault matching for a given predicate.
  /// Faulted objects are not considered to prevent Core Data to make a round trip to the persistent store.
  ///
  /// - Parameters:
  ///   - context: Searched context
  ///   - predicate: Matching predicate.
  /// - Returns: Materialized objects matching the predicate.
  public static func materializedObjects(in context: NSManagedObjectContext, where predicate: NSPredicate) -> [Self] {
    let results = context.registeredObjects
      .filter { !$0.isFault && $0 is Self }
      .filter { predicate.evaluate(with: $0) }
      .compactMap { $0 as? Self }
    return results
  }
}

// MARK: - Batch Operations

extension NSFetchRequestResult where Self: NSManagedObject {
  /// Executes a batch update on the context's persistent store coordinator.
  /// - Parameters:
  ///   - context: The context whose the persistent store coordinator will be used to execute the batch update.
  ///   - configuration: An handler to configure the NSBatchUpdateRequest.
  /// - Returns: a NSBatchUpdateRequest result.
  /// - Throws: It throws an error in cases of failure.
  /// - Note: A batch delete can **only** be done on a SQLite store.
  public static func batchUpdate(using context: NSManagedObjectContext,
                                 resultType: NSBatchUpdateRequestResultType = .statusOnlyResultType,
                                 propertiesToUpdate: [AnyHashable: Any],
                                 includesSubentities: Bool = true,
                                 predicate: NSPredicate? = nil) throws -> NSBatchUpdateResult {
    let batchRequest = NSBatchUpdateRequest(entityName: entityName)
    batchRequest.resultType = resultType
    batchRequest.propertiesToUpdate = propertiesToUpdate
    batchRequest.includesSubentities = includesSubentities
    batchRequest.predicate = predicate

    // swiftlint:disable:next force_cast
    return try context.execute(batchRequest) as! NSBatchUpdateResult
  }

  /// Executes a batch delete on the context's persistent store coordinator.
  /// - Parameters:
  ///   - context: The context whose the persistent store coordinator will be used to execute the batch delete.
  ///   - resultType: The type of the batch delete result (default: `NSBatchDeleteRequestResultType.resultTypeStatusOnly`).
  ///   - configuration: An handler to configure the NSFetchRequest.
  /// - Returns: a NSBatchDeleteResult result.
  /// - Throws: It throws an error in cases of failure.
  /// - Note: A batch delete can **only** be done on a SQLite store.
  @discardableResult
  public static func batchDelete(using context: NSManagedObjectContext,
                                 resultType: NSBatchDeleteRequestResultType = .resultTypeStatusOnly,
                                 configuration: ((NSFetchRequest<Self>) -> Void)? = nil) throws -> NSBatchDeleteResult {
    let request = NSFetchRequest<Self>(entityName: entityName)
    configuration?(request)

    // swiftlint:disable:next force_cast
    let batchRequest = NSBatchDeleteRequest(fetchRequest: request as! NSFetchRequest<NSFetchRequestResult>)
    batchRequest.resultType = resultType

    // swiftlint:disable:next force_cast
    return try context.execute(batchRequest) as! NSBatchDeleteResult
  }

  /// Executes a batch insert on the context's persistent store coordinator.
  /// - Parameters:
  ///   - context: The context whose the persistent store coordinator will be used to execute the batch insert.
  ///   - resultType: The type of the batch insert result (default: `NSBatchInsertRequestResultType.statusOnly`).
  ///   - objects: A dictionary of objects to insert.
  /// - Returns: a NSBatchInsertResult result.
  /// - Throws: It throws an error in cases of failure.
  /// - Note: A batch insert can **only** be done on a SQLite store.
  @available(iOS 13.0, iOSApplicationExtension 13.0, macCatalyst 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
  public static func batchInsert(using context: NSManagedObjectContext,
                                 resultType: NSBatchInsertRequestResultType = .statusOnly,
                                 objects: [[String: Any]]) throws -> NSBatchInsertResult {
    let batchRequest = NSBatchInsertRequest(entityName: entityName, objects: objects)
    batchRequest.resultType = resultType

    // swiftlint:disable:next force_cast
    return try context.execute(batchRequest) as! NSBatchInsertResult
  }

  /// Executes a batch insert on the context's persistent store coordinator.
  /// Doing a batch insert with this method is more memory efficient than the standard batch insert where all the items are passed alltogether.
  /// - Parameters:
  ///   - context: The context whose the persistent store coordinator will be used to execute the batch insert.
  ///   - resultType: The type of the batch insert result (default: `NSBatchInsertRequestResultType.statusOnly`).
  ///   - handler: An handler to provide a dictionary to insert; return `true` to exit the block.
  /// - Throws: It throws an error in cases of failure.
  /// - Returns: a NSBatchInsertResult result.
  /// - Note: A batch insert can **only** be done on a SQLite store.
  @available(iOS 14.0, iOSApplicationExtension 14.0, macCatalyst 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
  public static func batchInsert(using context: NSManagedObjectContext,
                                 resultType: NSBatchInsertRequestResultType = .statusOnly,
                                 dictionaryHandler handler: @escaping (NSMutableDictionary) -> Bool) throws -> NSBatchInsertResult {
    let batchRequest = NSBatchInsertRequest(entityName: entityName, dictionaryHandler: handler)
    batchRequest.resultType = resultType

    // swiftlint:disable:next force_cast
    return try context.execute(batchRequest) as! NSBatchInsertResult
  }

  /// Executes a batch insert on the context's persistent store coordinator.
  /// Doing a batch insert with this method is more memory efficient than the standard batch insert where all the items are passed alltogether.
  /// - Parameters:
  ///   - context: The context whose the persistent store coordinator will be used to execute the batch insert.
  ///   - resultType: The type of the batch insert result (default: `NSBatchInsertRequestResultType.statusOnly`).
  ///   - handler: An handler to provide an object to insert; return `true` to exit the block.
  /// - Throws: It throws an error in cases of failure.
  /// - Returns: a NSBatchInsertResult result.
  /// - Note: A batch insert can **only** be done on a SQLite store.
  @available(iOS 14.0, iOSApplicationExtension 14.0, macCatalyst 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
  public static func batchInsert(using context: NSManagedObjectContext,
                                 resultType: NSBatchInsertRequestResultType = .statusOnly,
                                 managedObjectHandler handler: @escaping (Self) -> Bool) throws -> NSBatchInsertResult {
    let batchRequest = NSBatchInsertRequest(entityName: entityName, managedObjectHandler: { object -> Bool in
      // swiftlint:disable:next force_cast
      return handler(object as! Self)
    })
    batchRequest.resultType = resultType

    // swiftlint:disable:next force_cast
    return try context.execute(batchRequest) as! NSBatchInsertResult
  }
}

// MARK: - Async Fetch

extension NSFetchRequestResult where Self: NSManagedObject {
  /// Performs a configurable asynchronous fetch request in a context.
  ///
  /// - Parameter context: Searched context.
  /// - Parameter estimatedResultCount: A parameter that assists Core Data with scheduling the asynchronous fetch request.
  /// - Parameter configuration: Configuration closure called when preparing the `NSFetchRequest`.
  /// - Parameter completion: A completion block with a `Result` element with either the fetched objects or an error.
  /// - Returns: A `NSAsynchronousFetchResult` *future* instance that can be used to report the fetch progress.
  /// - Throws: It throws an error in cases of failure.
  ///
  /// - Note: This kind of fetch operation supports progress reporting:
  ///   ```
  ///   let progress = Progress(totalUnitCount: 1)
  ///   progress.becomeCurrent(withPendingUnitCount: 1)
  ///   let fetchResultToken = try ENTITY.fetchAsync(in:with:completion:)
  ///   let token = fetchResultToken.progress?.observe(\.completedUnitCount, options: [.old, .new]) { (progress, change) }
  ///   progress.resignCurrent()
  ///
  ///   ```
  /// - Warning: If the ConcurrencyDebug is enabled, the fetch request will cause a thread violation error.
  /// ([more details here](https://stackoverflow.com/questions/31728425/coredata-asynchronous-fetch-causes-concurrency-debugger-error)).
  @discardableResult
  public static func fetchAsync(in context: NSManagedObjectContext,
                                estimatedResultCount: Int = 0,
                                with configuration: (NSFetchRequest<Self>) -> Void = { _ in },
                                completion: @escaping (Result<[Self], Error>) -> Void) throws -> NSAsynchronousFetchResult<Self> {
    let request = Self.newFetchRequest()
    configuration(request)

    let asynchronousRequest = NSAsynchronousFetchRequest(fetchRequest: request) { result in
      if let error = result.operationError {
        completion(.failure(error))
      } else if let fetchedObjects = result.finalResult {
        completion(.success(fetchedObjects))
      } else {
        fatalError("Unexpected behaviour")
      }
    }
    asynchronousRequest.estimatedResultCount = estimatedResultCount

    // swiftlint:disable:next force_cast
    return try context.execute(asynchronousRequest) as! NSAsynchronousFetchResult<Self>
  }
}
