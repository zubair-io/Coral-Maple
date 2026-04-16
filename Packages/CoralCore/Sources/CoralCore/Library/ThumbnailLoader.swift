import CoreGraphics
import Foundation

/// Async thumbnail loader with three cache layers:
/// 1. In-memory LRU (instant)
/// 2. On-disk JPEG cache (fast — small file read)
/// 3. Source extraction (slow — reads embedded preview from RAW, or full decode for JPEG)
public actor ThumbnailLoader {

    private var memoryCache: LRUCache<String, CGImage>
    private let maxConcurrency: Int

    /// Currently in-flight loads, keyed by `asset.id + size`.
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    /// Simple concurrency limiter — number of loads currently running.
    private var activeCount = 0

    /// Requests waiting for a concurrency slot.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(cacheCapacity: Int = 500, maxConcurrency: Int = 6) {
        self.memoryCache = LRUCache(capacity: cacheCapacity)
        self.maxConcurrency = maxConcurrency
    }

    /// Load a thumbnail. Checks memory → source (which handles disk cache internally).
    public func thumbnail(
        for asset: ImageAsset,
        size: CGSize,
        source: any LibrarySource
    ) async -> CGImage? {
        let maxDim = Int(max(size.width, size.height))
        let memKey = "\(asset.id)_\(maxDim)"

        // Layer 1: memory
        if let cached = memoryCache.get(memKey) {
            return cached
        }

        // Coalesce duplicate requests
        if let existing = inFlight[memKey] {
            return await existing.value
        }

        let task = Task<CGImage?, Never> {
            await acquireSlot()
            defer { Task { await releaseSlot() } }

            do {
                // Source handles disk cache (.coral/) under its own security scope
                let image = try await source.thumbnail(for: asset, size: size)
                await cacheInMemory(key: memKey, image: image)
                return image
            } catch {
                return nil
            }
        }

        inFlight[memKey] = task
        let result = await task.value
        inFlight.removeValue(forKey: memKey)
        return result
    }

    /// Cancel all in-flight loads (e.g. when switching folders).
    public func cancelAll() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    /// Clear memory cache (e.g. on memory warning).
    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    /// Remove cached thumbnails for a specific asset — used after an edit saves
    /// so the grid refetches the regenerated thumbnail.
    public func invalidate(assetID: String) {
        memoryCache.removeAll { key in key.hasPrefix("\(assetID)_") }
    }

    /// Store an already-rendered thumbnail directly in the memory cache.
    /// Used after an edit so the grid shows the new thumbnail immediately,
    /// without waiting for the source to re-read it from disk.
    public func prime(assetID: String, size: CGSize, image: CGImage) {
        let maxDim = Int(max(size.width, size.height))
        memoryCache.set("\(assetID)_\(maxDim)", value: image)
    }

    /// Clear memory cache and reset for a new session.
    public func clearAll() {
        memoryCache.removeAll()
    }

    /// Reduce cache to 25% capacity on memory pressure.
    public func handleMemoryPressure() {
        let targetCount = max(memoryCache.capacity / 4, 10)
        while memoryCache.count > targetCount {
            memoryCache.evictOldest()
        }
    }

    // MARK: - Concurrency limiter

    private func acquireSlot() async {
        if activeCount < maxConcurrency {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            activeCount -= 1
        }
    }

    private func cacheInMemory(key: String, image: CGImage) {
        memoryCache.set(key, value: image)
    }
}

// MARK: - LRU Cache

/// Generic LRU cache with O(1) get, set, and eviction.
/// Backed by a doubly-linked list (recency order) and a hash map (key lookup).
struct LRUCache<Key: Hashable, Value>: Sendable where Key: Sendable, Value: Sendable {

    private final class Node: @unchecked Sendable {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        init(key: Key, value: Value) { self.key = key; self.value = value }
    }

    private var map: [Key: Node] = [:]
    /// Most-recently-used sentinel
    private var head: Node?
    /// Least-recently-used sentinel
    private var tail: Node?
    private(set) var capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int { map.count }

    mutating func get(_ key: Key) -> Value? {
        guard let node = map[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    mutating func set(_ key: Key, value: Value) {
        if let node = map[key] {
            node.value = value
            moveToHead(node)
        } else {
            let node = Node(key: key, value: value)
            map[key] = node
            addToHead(node)
            if map.count > capacity {
                evictOldest()
            }
        }
    }

    mutating func evictOldest() {
        guard let t = tail else { return }
        removeNode(t)
        map.removeValue(forKey: t.key)
    }

    mutating func removeAll() {
        map.removeAll()
        head = nil
        tail = nil
    }

    mutating func removeAll(where predicate: (Key) -> Bool) {
        let keysToRemove = map.keys.filter(predicate)
        for key in keysToRemove {
            if let node = map.removeValue(forKey: key) {
                removeNode(node)
            }
        }
    }

    // MARK: - Linked list operations

    private mutating func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private mutating func removeNode(_ node: Node) {
        let prev = node.prev
        let next = node.next
        prev?.next = next
        next?.prev = prev
        if head === node { head = next }
        if tail === node { tail = prev }
        node.prev = nil
        node.next = nil
    }

    private mutating func moveToHead(_ node: Node) {
        guard head !== node else { return }
        removeNode(node)
        addToHead(node)
    }
}
