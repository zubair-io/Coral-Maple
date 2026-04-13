import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `LibrarySource` implementation for the local filesystem.
/// Walks user-selected directories, builds a folder tree, and generates thumbnails
/// via ImageIO (no UIKit/AppKit dependency).
public final class FilesystemSource: LibrarySource, @unchecked Sendable {

    private let bookmarkStore: BookmarkStore
    private let fileManager: FileManager

    /// Maps container ID (url.absoluteString) → the security-scoped URL resolved from the bookmark.
    /// Security-scoped access only works on the original resolved URL, not one reconstructed from a string.
    private var scopedURLs: [String: URL] = [:]

    /// Supported image UTTypes for browsing.
    public static let supportedTypes: Set<UTType> = [
        .jpeg, .png, .tiff, .heic, .heif, .bmp, .gif, .webP,
        .rawImage,
    ]

    public init(bookmarkStore: BookmarkStore = BookmarkStore(), fileManager: FileManager = .default) {
        self.bookmarkStore = bookmarkStore
        self.fileManager = fileManager
    }

    // MARK: - LibrarySource

    public func rootContainers() async throws -> [SourceContainer] {
        let urls = try bookmarkStore.restore()
        var results: [SourceContainer] = []
        for url in urls {
            // On iOS/iPadOS, SMB paths via smbclientd/LiveFiles don't support FileManager listing.
            // Only File Provider Storage paths work.
            if url.path.contains("/LiveFiles/com.apple.filesystems.smbclientd/") {
                NSLog("[CoralMaple] rootContainers: SKIPPING incompatible SMB LiveFiles path: %@", url.path)
                bookmarkStore.remove(url: url)
                continue
            }
            let container = buildContainer(for: url)
            scopedURLs[container.id] = url
            results.append(container)
        }
        return results
    }

    /// Incremental enumerator state per container — enumerates only as many files as requested.
    private var iterators: [String: IncrementalEnumerator] = [:]

    public func subfolders(in container: SourceContainer) async throws -> [SourceContainer] {
        guard let url = URL(string: container.id) else { return [] }
        let scopeURL = findScopedParent(for: url)
        let items = listDirectory(at: url, scopeURL: scopeURL)
        var results: [SourceContainer] = []
        for itemURL in items {
            if itemURL.lastPathComponent.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir)
            if isDir.boolValue {
                results.append(SourceContainer(
                    id: itemURL.absoluteString,
                    name: itemURL.lastPathComponent,
                    children: [],
                    imageCount: 0
                ))
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func assetCount(in container: SourceContainer) async throws -> Int {
        let treeCount = recursiveImageCount(container)
        // If we have a count from the tree, use it as a fast estimate.
        // If 0, the tree might not have been fully built — enumerate to find out.
        if treeCount > 0 { return treeCount }

        // Fall back: do a quick enumeration to get the real count.
        let iter = getOrCreateIterator(for: container)
        // Enumerate everything to know the total. This is the slow path
        // but only hits for shallow containers where the tree count is unknown.
        iter.enumerateAll()
        return iter.assets.count
    }

    public func assets(in container: SourceContainer, offset: Int, limit: Int) async throws -> [ImageAsset] {
        let iter = getOrCreateIterator(for: container)
        // Enumerate just enough to cover offset + limit
        iter.enumerateUpTo(offset + limit)
        let end = min(offset + limit, iter.assets.count)
        guard offset < end else { return [] }
        return Array(iter.assets[offset..<end])
    }

    private func recursiveImageCount(_ container: SourceContainer) -> Int {
        container.imageCount + container.children.reduce(0) { $0 + recursiveImageCount($1) }
    }

    private func getOrCreateIterator(for container: SourceContainer) -> IncrementalEnumerator {
        if let existing = iterators[container.id] { return existing }
        let url = URL(string: container.id)
        let scopeURL = url.flatMap { findScopedParent(for: $0) }
        let iter = IncrementalEnumerator(url: url, scopeURL: scopeURL, fileManager: fileManager)
        iterators[container.id] = iter
        return iter
    }

    /// Reset cached state when switching containers.
    public func resetCache(for containerID: String) {
        iterators.removeValue(forKey: containerID)
    }

    /// Find the bookmarked ancestor URL that grants security-scoped access to `url`.
    private func findScopedParent(for url: URL) -> URL? {
        let path = url.path
        for (_, scopedURL) in scopedURLs {
            if path.hasPrefix(scopedURL.path) {
                return scopedURL
            }
        }
        return nil
    }

    /// Enumerates a directory incrementally. Uses FileManager.enumerator when possible,
    /// falls back to POSIX opendir/readdir for iOS SMB LiveFiles paths.
    private class IncrementalEnumerator {
        private(set) var assets: [ImageAsset] = []
        private var finished = false
        private var enumerator: FileManager.DirectoryEnumerator?
        /// Fallback: all image URLs collected via POSIX, paged from this list.
        private var posixURLs: [URL]?
        private var posixIndex = 0
        private let scopeTarget: URL?
        private var accessing = false

        init(url: URL?, scopeURL: URL?, fileManager: FileManager) {
            guard let url else {
                self.scopeTarget = nil
                self.finished = true
                return
            }
            let target = scopeURL ?? url
            self.scopeTarget = target
            self.accessing = target.startAccessingSecurityScopedResource()

            // Single-level enumeration — don't recurse into subfolders
            self.enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.contentTypeKey, .creationDateKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )

            // Test if it yields anything — if first call returns nil, switch to POSIX
            if let fmEnum = self.enumerator {
                if let first = fmEnum.nextObject() as? URL {
                    // It works — process this first result and keep using FileManager
                    if let asset = Self.makeAsset(from: first) {
                        assets.append(asset)
                    }
                } else {
                    // FileManager returned nothing — try POSIX
                    self.enumerator = nil
                    self.posixURLs = Self.collectImageURLsPOSIX(at: url)
                    if self.posixURLs?.isEmpty ?? true { self.finished = true }
                }
            } else {
                self.posixURLs = Self.collectImageURLsPOSIX(at: url)
                if self.posixURLs?.isEmpty ?? true { self.finished = true }
            }
        }

        deinit {
            if accessing, let target = scopeTarget {
                target.stopAccessingSecurityScopedResource()
            }
        }

        func enumerateUpTo(_ count: Int) {
            guard !finished else { return }
            while assets.count < count {
                guard let next = nextAsset() else {
                    finished = true
                    return
                }
                assets.append(next)
            }
        }

        func enumerateAll() {
            guard !finished else { return }
            while let next = nextAsset() {
                assets.append(next)
            }
            finished = true
        }

        private func nextAsset() -> ImageAsset? {
            // FileManager path
            if let fmEnum = enumerator {
                while let fileURL = fmEnum.nextObject() as? URL {
                    if fileURL.lastPathComponent == ".coral" {
                        fmEnum.skipDescendants()
                        continue
                    }
                    if let asset = Self.makeAsset(from: fileURL) { return asset }
                }
                return nil
            }

            // POSIX fallback path
            if let urls = posixURLs {
                while posixIndex < urls.count {
                    let url = urls[posixIndex]
                    posixIndex += 1
                    if let asset = Self.makeAsset(from: url) { return asset }
                }
                return nil
            }

            return nil
        }

        private static func makeAsset(from fileURL: URL) -> ImageAsset? {
            guard FilesystemSource.isImageFile(fileURL) else { return nil }
            return ImageAsset(
                id: fileURL.absoluteString,
                sourceType: .filesystem,
                filename: fileURL.lastPathComponent,
                pixelWidth: 0,
                pixelHeight: 0,
                creationDate: nil,
                fileURL: fileURL
            )
        }

        /// Recursively collect all file URLs using POSIX opendir/readdir.
        /// Single-level POSIX listing — images only, no recursion.
        private static func collectImageURLsPOSIX(at url: URL) -> [URL] {
            guard let dir = opendir(url.path) else { return [] }
            defer { closedir(dir) }

            var results: [URL] = []
            while let entry = readdir(dir) {
                let name = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                if name == "." || name == ".." || name.hasPrefix(".") { continue }
                // Skip directories — only collect files
                if entry.pointee.d_type == DT_DIR { continue }
                let childURL = url.appendingPathComponent(name)
                if isImageFile(childURL) {
                    results.append(childURL)
                }
            }
            return results
        }
    }

    private static let diskCache = ThumbnailDiskCache()

    public func thumbnail(for asset: ImageAsset, size: CGSize) async throws -> CGImage {
        guard let fileURL = asset.fileURL else {
            throw FilesystemError.fileNotFound(asset.id)
        }

        // Start security scope on the bookmark root — covers both original and .coral/
        let scopeURL = findScopedParent(for: fileURL) ?? fileURL
        let accessing = scopeURL.startAccessingSecurityScopedResource()
        defer { if accessing { scopeURL.stopAccessingSecurityScopedResource() } }

        // Layer 2: check .coral/thumbs/ disk cache (inside security scope)
        if let cached = Self.diskCache.read(for: fileURL) {
            return cached
        }

        // Layer 3: extract from original file (embedded RAW preview or full decode)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw FilesystemError.decodeFailed(fileURL)
        }

        let maxDimension = max(size.width, size.height)
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FilesystemError.decodeFailed(fileURL)
        }

        // Write to .coral/thumbs/ for next time (still inside security scope)
        Self.diskCache.write(for: fileURL, image: thumbnail)

        return thumbnail
    }

    public func fullImage(for asset: ImageAsset) async throws -> CGImage {
        guard let fileURL = asset.fileURL else {
            throw FilesystemError.fileNotFound(asset.id)
        }

        let scopeURL = findScopedParent(for: fileURL) ?? fileURL
        let accessing = scopeURL.startAccessingSecurityScopedResource()
        defer { if accessing { scopeURL.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FilesystemError.decodeFailed(fileURL)
        }

        return image
    }

    // MARK: - Folder management

    /// Whether a URL is an iOS SMB LiveFiles path that can't be enumerated by third-party apps.
    public static func isBrokenSMBPath(_ url: URL) -> Bool {
        url.path.contains("/LiveFiles/com.apple.filesystems.smbclientd/")
    }

    /// Add a new folder bookmark and return its container.
    /// The URL must come from a file picker / fileImporter (security-scoped).
    public func addFolder(_ url: URL) throws -> SourceContainer {
        // Start security scope — keep it active (don't stop it).
        // The scoped URL is stored in scopedURLs for later use.
        _ = url.startAccessingSecurityScopedResource()

        try bookmarkStore.save(url: url)
        let container = buildContainer(for: url)
        scopedURLs[container.id] = url
        return container
    }

    /// Remove a folder bookmark.
    public func removeFolder(_ url: URL) {
        bookmarkStore.remove(url: url)
    }

    // MARK: - Private

    private func buildContainer(for url: URL) -> SourceContainer {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var children: [SourceContainer] = []
        var imageCount = 0

        // Try FileManager first, fall back to POSIX opendir for SMB LiveFiles paths
        let contents = listDirectory(at: url)

        for itemURL in contents {
            if itemURL.lastPathComponent.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir)
            if isDir.boolValue {
                children.append(buildContainerShallow(for: itemURL))
            } else if Self.isImageFile(itemURL) {
                imageCount += 1
            }
        }

        return SourceContainer(
            id: url.absoluteString,
            name: url.lastPathComponent,
            children: children,
            imageCount: imageCount
        )
    }

    /// List directory contents. Tries multiple strategies:
    /// 1. FileManager inside NSFileCoordinator
    /// 2. FileManager direct
    /// 3. POSIX opendir/readdir
    private func listDirectory(at url: URL, scopeURL: URL? = nil) -> [URL] {
        // Start security scope if provided
        let target = scopeURL ?? url
        let accessing = target.startAccessingSecurityScopedResource()
        defer { if accessing { target.stopAccessingSecurityScopedResource() } }
        // Strategy 1: FileManager inside NSFileCoordinator (needed for File Providers / SMB)
        var coordResult: [URL] = []
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { readURL in
            if let contents = try? fileManager.contentsOfDirectory(
                at: readURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                coordResult = contents
            }
        }
        if !coordResult.isEmpty {
            return coordResult
        }

        // Strategy 2: direct FileManager
        if let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ), !contents.isEmpty {
            return contents
        }

        // Strategy 3: POSIX opendir/readdir
        guard let dir = opendir(url.path) else {
            NSLog("[CoralMaple] listDirectory: opendir FAILED for %@ errno=%d (%@)", url.path, errno, String(cString: strerror(errno)))
            return []
        }
        defer { closedir(dir) }

        var results: [URL] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." || name.hasPrefix(".") { continue }
            results.append(url.appendingPathComponent(name))
        }
        return results
    }

    /// Quick check if a URL is a supported image type by extension.
    static func isImageFile(_ url: URL) -> Bool {
        ImageAsset.isImageFilename(url.lastPathComponent)
    }

    /// Shallow container — name only, no recursive enumeration. Children populated on demand.
    private func buildContainerShallow(for url: URL) -> SourceContainer {
        SourceContainer(
            id: url.absoluteString,
            name: url.lastPathComponent,
            children: [],
            imageCount: 0  // unknown until selected
        )
    }

    private static func imageDimensions(at url: URL) -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return (0, 0)
        }
        return (width, height)
    }
}

// MARK: - Errors

public enum FilesystemError: Error, Sendable {
    case fileNotFound(String)
    case decodeFailed(URL)
    case permissionDenied(URL)
}
