import Foundation

/// Thread-safe Least Recently Used (LRU) cache implementation
/// Optimizes performance by caching moderation results for repeated text
public final class LRUCache<Key: Hashable, Value> {
    
    // MARK: - Node
    
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    // MARK: - Properties
    
    private let capacity: Int
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let lock = NSLock()
    
    /// Current number of items in cache
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
    
    // MARK: - Initialization
    
    /// Initialize LRU cache with specified capacity
    /// - Parameter capacity: Maximum number of items to store (default: 1000)
    public init(capacity: Int = 1000) {
        self.capacity = capacity
    }
    
    // MARK: - Public Methods
    
    /// Retrieve value for key, marking it as recently used
    /// - Parameter key: Cache key
    /// - Returns: Cached value if exists, nil otherwise
    public func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let node = cache[key] else {
            return nil
        }
        
        moveToHead(node)
        return node.value
    }
    
    /// Store value with key, evicting least recently used item if at capacity
    /// - Parameters:
    ///   - value: Value to cache
    ///   - key: Cache key
    public func set(_ value: Value, forKey key: Key) {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingNode = cache[key] {
            existingNode.value = value
            moveToHead(existingNode)
            return
        }
        
        let newNode = Node(key: key, value: value)
        cache[key] = newNode
        addToHead(newNode)
        
        if cache.count > capacity {
            if let removed = removeTail() {
                cache.removeValue(forKey: removed.key)
            }
        }
    }
    
    /// Remove specific key from cache
    /// - Parameter key: Key to remove
    public func remove(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let node = cache[key] else { return }
        removeNode(node)
        cache.removeValue(forKey: key)
    }
    
    /// Clear all cached items
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        head = nil
        tail = nil
    }
    
    // MARK: - Private Methods
    
    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil
        
        head?.prev = node
        head = node
        
        if tail == nil {
            tail = node
        }
    }
    
    private func removeNode(_ node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }
        
        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }
    }
    
    private func moveToHead(_ node: Node) {
        removeNode(node)
        addToHead(node)
    }
    
    private func removeTail() -> Node? {
        guard let tailNode = tail else { return nil }
        removeNode(tailNode)
        return tailNode
    }
}

// MARK: - Statistics

public extension LRUCache {
    /// Cache statistics for monitoring performance
    struct Statistics {
        public let capacity: Int
        public let count: Int
        public let utilization: Double
        
        init(capacity: Int, count: Int) {
            self.capacity = capacity
            self.count = count
            self.utilization = Double(count) / Double(capacity)
        }
    }
    
    /// Get current cache statistics
    var statistics: Statistics {
        Statistics(capacity: capacity, count: count)
    }
}
