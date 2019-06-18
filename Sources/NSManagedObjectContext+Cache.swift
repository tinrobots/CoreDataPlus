//
// CoreDataPlus
//
// Copyright © 2016-2019 Tinrobots.
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

import CoreData

// MARK: - Cache

private let managedObjectsCacheKey = "\(bundleIdentifier).NSManagedObjectContext.cache"
private typealias ManagedObjectsCache = [String: NSManagedObject]

extension NSManagedObjectContext {
  /// **CoreDataPlus**
  ///
  /// Caches a NSManagedObject `object` for a `key` in this context.
  /// - Note: The NSManagedObject `object` must have the same NSManagedObjectContext of `self` otherwise it will be not cached.
  public final func setCachedManagedObject(_ object: NSManagedObject?, forKey key: String) {
    switch object {
    case let managedObject? where managedObject.managedObjectContext != nil && managedObject.managedObjectContext !== self:
      // TODO: - better management
      if !ProcessInfo.isRunningUnitTests {
        assertionFailure("The managedObject \(managedObject.objectID) has a NSManagedObjectContext \(managedObject.managedObjectContext!) different from \(self) and it will be not cached.")
      }

    case let managedObject? where managedObject.managedObjectContext == nil:
      // TODO: - better management
      if !ProcessInfo.isRunningUnitTests {
        assertionFailure("The managedObject \(managedObject.objectID) doesn't have a NSManagedObjectContext and it will be not cached.")
      }

    default:
      var cache = userInfo[managedObjectsCacheKey] as? ManagedObjectsCache ?? [:]
      cache[key] = object
      userInfo[managedObjectsCacheKey] = cache
    }

    // TODO if the object is from another context we could use object(with:) or existingObject(with:) to cache in the current context
  }

  /// **CoreDataPlus**
  ///
  /// Returns a cached NSManagedObject `object` in this context for a given `key`.
  public final func cachedManagedObject(forKey key: String) -> NSManagedObject? {
    guard let cache = userInfo[managedObjectsCacheKey] as? ManagedObjectsCache else { return nil }
    return cache[key]
  }

  /// **CoreDataPlus**
  ///
  /// Clears all cached NSManagedObject objects in this context.
  public final func clearCachedManagedObjects() {
    let cache = userInfo[managedObjectsCacheKey]
    if (cache as? ManagedObjectsCache) != nil {
      userInfo[managedObjectsCacheKey] = nil
    }
  }
}
