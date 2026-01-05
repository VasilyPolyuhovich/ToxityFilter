import XCTest
@testable import ToxityFilter

final class CacheTests: XCTestCase {
    
    func testBasicCacheOperations() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "two")
        cache.set(3, forKey: "three")
        
        XCTAssertEqual(cache.get("one"), 1)
        XCTAssertEqual(cache.get("two"), 2)
        XCTAssertEqual(cache.get("three"), 3)
        XCTAssertEqual(cache.count, 3)
    }
    
    func testEviction() {
        let cache = LRUCache<String, Int>(capacity: 2)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "two")
        cache.set(3, forKey: "three") // Should evict "one"
        
        XCTAssertNil(cache.get("one"), "Least recently used item should be evicted")
        XCTAssertEqual(cache.get("two"), 2)
        XCTAssertEqual(cache.get("three"), 3)
        XCTAssertEqual(cache.count, 2)
    }
    
    func testLRUOrdering() {
        let cache = LRUCache<String, Int>(capacity: 2)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "two")
        
        // Access "one" to make it more recent
        _ = cache.get("one")
        
        // Add new item - should evict "two" not "one"
        cache.set(3, forKey: "three")
        
        XCTAssertEqual(cache.get("one"), 1, "Recently accessed item should not be evicted")
        XCTAssertNil(cache.get("two"), "Least recently used item should be evicted")
        XCTAssertEqual(cache.get("three"), 3)
    }
    
    func testUpdate() {
        let cache = LRUCache<String, Int>(capacity: 2)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "one") // Update value
        
        XCTAssertEqual(cache.get("one"), 2, "Value should be updated")
        XCTAssertEqual(cache.count, 1, "Count should not increase on update")
    }
    
    func testRemove() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "two")
        cache.set(3, forKey: "three")
        
        cache.remove("two")
        
        XCTAssertNil(cache.get("two"))
        XCTAssertEqual(cache.count, 2)
    }
    
    func testRemoveAll() {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "two")
        cache.set(3, forKey: "three")
        
        cache.removeAll()
        
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get("one"))
        XCTAssertNil(cache.get("two"))
        XCTAssertNil(cache.get("three"))
    }
    
    func testStatistics() {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        cache.set(1, forKey: "one")
        cache.set(2, forKey: "two")
        cache.set(3, forKey: "three")
        
        let stats = cache.statistics
        
        XCTAssertEqual(stats.capacity, 10)
        XCTAssertEqual(stats.count, 3)
        XCTAssertEqual(stats.utilization, 0.3, accuracy: 0.001)
    }
    
    func testThreadSafety() async {
        let cache = LRUCache<Int, Int>(capacity: 100)
        
        // Perform concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    cache.set(i, forKey: i)
                }
            }
            
            for i in 0..<100 {
                group.addTask {
                    _ = cache.get(i)
                }
            }
        }
        
        // Cache should remain consistent
        XCTAssertLessThanOrEqual(cache.count, 100)
    }
    
    func testPerformance() {
        let cache = LRUCache<String, String>(capacity: 1000)
        
        measure {
            for i in 0..<1000 {
                cache.set("value\(i)", forKey: "key\(i)")
            }
            
            for i in 0..<1000 {
                _ = cache.get("key\(i)")
            }
        }
    }
}
