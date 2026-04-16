import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// On-disk cache for fully-processed preview images.
///
/// Keyed by `(assetID, adjustmentsHash)`, stored as JPEG under the app's
/// caches directory. The primary win is a cold-open: when the user reopens an
/// image they've previously edited, we can paint the last refined render
/// immediately instead of waiting ~300ms for the RAW to re-decode.
///
/// Cache entries never go stale through mutation — if the adjustment set
/// changes, the hash changes and we simply miss (and write a new entry).
/// A byte-budget sweep runs opportunistically to keep the directory bounded.
public struct RenderedPreviewCache: Sendable {

    /// Maximum total bytes in the cache directory. Excess evicted by LRU
    /// (oldest `contentAccessDate` first).
    public let budgetBytes: Int

    /// The cache directory. Created lazily on first write.
    public let directory: URL

    public init(
        directory: URL? = nil,
        budgetBytes: Int = 500 * 1024 * 1024 // 500 MB
    ) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base
                .appendingPathComponent("CoralMaple", isDirectory: true)
                .appendingPathComponent("previews", isDirectory: true)
        }
        self.budgetBytes = budgetBytes
    }

    // MARK: - Read / write

    /// Returns the cached preview for `(assetID, adjustments)` if present.
    /// Touches the file's access date so LRU eviction treats it as recently used.
    public func read(assetID: String, adjustments: AdjustmentModel) -> CGImage? {
        let url = entryURL(assetID: assetID, adjustments: adjustments)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // Mark as recently used — relies on APFS updating access date on touch.
        let now = Date()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)

        return image
    }

    /// Write pre-encoded JPEG bytes to the cache.
    /// Callers should produce these via `ImageEditPipeline.encodePreviewJPEG(...)`,
    /// which routes through `CIContext.jpegRepresentation` and is always
    /// opaque — bypassing ImageIO's alpha-on-JPEG warning that fires when
    /// `CGImageDestination` is fed a CGImage that has an alpha channel.
    public func write(assetID: String, adjustments: AdjustmentModel, jpegData: Data) {
        let url = entryURL(assetID: assetID, adjustments: adjustments)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }

        do {
            try jpegData.write(to: url, options: .atomic)
        } catch {
            return
        }

        // Opportunistic: sweep whenever we write. Cheap on a small directory.
        evictIfOverBudget()
    }

    /// Remove every cached entry for a specific asset (all adjustment variants).
    public func invalidate(assetID: String) {
        let prefix = assetHash(assetID)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        for name in entries where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Delete every cached preview. Called from a user "Clear Cache" action.
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Path & hashing

    private func entryURL(assetID: String, adjustments: AdjustmentModel) -> URL {
        directory.appendingPathComponent("\(assetHash(assetID)).\(adjustmentHash(adjustments)).jpg")
    }

    /// SHA256 of the asset ID, truncated to 16 hex chars. Deterministic and
    /// filesystem-safe (SMB paths, PhotoKit local identifiers, local URLs can
    /// all contain characters we'd rather not put in a filename).
    private func assetHash(_ assetID: String) -> String {
        Self.shortHash(Data(assetID.utf8))
    }

    /// SHA256 of the canonicalized adjustment JSON. Uses `.sortedKeys` so
    /// field order never perturbs the hash.
    private func adjustmentHash(_ adjustments: AdjustmentModel) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(adjustments)) ?? Data()
        return Self.shortHash(data)
    }

    private static func shortHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Eviction

    /// Scan the cache dir; if total size exceeds the budget, delete entries
    /// oldest-modification-date first until we're back under budget.
    private func evictIfOverBudget() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        struct Entry {
            let url: URL
            let size: Int
            let date: Date
        }
        var records: [Entry] = []
        var total = 0
        for url in entries {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let size = values.fileSize ?? 0
            let date = values.contentModificationDate ?? .distantPast
            records.append(Entry(url: url, size: size, date: date))
            total += size
        }

        guard total > budgetBytes else { return }

        // Evict oldest first until under budget.
        records.sort { $0.date < $1.date }
        for entry in records {
            if total <= budgetBytes { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
