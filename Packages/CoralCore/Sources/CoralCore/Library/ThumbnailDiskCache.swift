import CoreGraphics
import Foundation
import ImageIO

/// On-disk thumbnail cache stored alongside the photos in `.coral/thumbs/`.
/// For an image at `/Photos/France/IMG_001.CR3`, the thumbnail lives at
/// `/Photos/France/.coral/thumbs/IMG_001.CR3.jpg`.
///
/// Thumbnails travel with the photos — copy the folder to another
/// Mac or external drive and thumbnails come along.
public struct ThumbnailDiskCache: Sendable {

    public init() {}

    /// Read a cached thumbnail. Caller must ensure security scope is active.
    public func read(for fileURL: URL) -> CGImage? {
        let url = thumbURL(for: fileURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // Check if original is newer than cache
        let thumbModDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        let origModDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? .distantFuture
        if origModDate > thumbModDate { return nil }  // stale cache

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    /// Write a thumbnail as a compressed JPEG alongside the original.
    /// Caller must ensure security scope is active.
    /// Uses non-atomic write to work on SMB/NFS volumes.
    public func write(for fileURL: URL, image: CGImage) {
        let url = thumbURL(for: fileURL)
        let dir = url.deletingLastPathComponent()

        // Create .coral/thumbs/ if needed
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // Can't create directory — skip cache silently
            return
        }

        // Render to JPEG data in memory, then write bytes directly (no atomic rename)
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return }

        let data = mutableData as Data
        do {
            try data.write(to: url, options: []) // non-atomic — works on SMB
        } catch {
            // Write failed — skip cache silently, thumbnail still works from memory
        }
    }

    /// Delete the `.coral` folder for a given directory.
    public func clear(in directory: URL) {
        let coralDir = directory.appendingPathComponent(".coral", isDirectory: true)
        try? FileManager.default.removeItem(at: coralDir)
    }

    // MARK: - Path

    /// `/path/to/photos/.coral/thumbs/IMG_001.CR3.jpg`
    private func thumbURL(for fileURL: URL) -> URL {
        let parentDir = fileURL.deletingLastPathComponent()
        let filename = fileURL.lastPathComponent
        return parentDir
            .appendingPathComponent(".coral", isDirectory: true)
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent("\(filename).jpg")
    }
}
