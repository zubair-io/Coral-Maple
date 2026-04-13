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

/// Simple generic LRU cache backed by a dictionary with timestamp-based eviction.
/// All operations are O(1) amortized (eviction scans once per insert over capacity).
struct LRUCache<Key: Hashable, Value>: Sendable where Key: Sendable, Value: Sendable {

    private var storage: [Key: (value: Value, timestamp: UInt64)] = [:]
    private var nextTimestamp: UInt64 = 0
    private(set) var capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    mutating func get(_ key: Key) -> Value? {
        guard var entry = storage[key] else { return nil }
        nextTimestamp += 1
        entry.timestamp = nextTimestamp
        storage[key] = entry
        return entry.value
    }

    mutating func set(_ key: Key, value: Value) {
        nextTimestamp += 1
        storage[key] = (value: value, timestamp: nextTimestamp)
        if storage.count > capacity {
            // Evict oldest
            if let oldest = storage.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                storage.removeValue(forKey: oldest)
            }
        }
    }

    var count: Int { storage.count }

    mutating func evictOldest() {
        if let oldest = storage.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
            storage.removeValue(forKey: oldest)
        }
    }

    mutating func removeAll() {
        storage.removeAll()
        nextTimestamp = 0
    }
}
