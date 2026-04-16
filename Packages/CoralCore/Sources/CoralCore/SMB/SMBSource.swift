import CoreGraphics
import Foundation
import ImageIO
import AMSMB2

/// `LibrarySource` implementation for direct SMB connections via AMSMB2.
/// Bypasses the iOS smbclientd limitation entirely.
public final class SMBSource: LibrarySource, @unchecked Sendable {

    private let config: SMBServerConfig
    private let password: String
    private var client: SMB2Manager?

    // Image extensions are centralized in ImageAsset.imageExtensions

    public init(config: SMBServerConfig, password: String) {
        self.config = config
        self.password = password
    }

    // MARK: - Connection

    private func ensureConnected() async throws -> SMB2Manager {
        if let client { return client }

        guard let serverURL = config.serverURL else {
            throw SMBError.invalidURL(config.host)
        }

        let credential = URLCredential(
            user: config.username,
            password: password,
            persistence: .forSession
        )

        guard let newClient = SMB2Manager(url: serverURL, credential: credential) else {
            throw SMBError.connectionFailed(config.host)
        }

        try await newClient.connectShare(name: config.share)
        self.client = newClient
        return newClient
    }

    public func disconnect() async {
        if let client {
            try? await client.disconnectShare()
            self.client = nil
        }
    }

    // MARK: - LibrarySource

    public func rootContainers() async throws -> [SourceContainer] {
        let client = try await ensureConnected()
        let items = try await client.contentsOfDirectory(atPath: "/")

        var containers: [SourceContainer] = []
        for item in items {
            let name = (item[.nameKey] as? String) ?? ""
            if name.hasPrefix(".") { continue }
            let isDir = (item[.isDirectoryKey] as? Bool) ?? false
            if isDir {
                containers.append(SourceContainer(
                    id: smbID(path: "/\(name)"),
                    name: name,
                    children: [],
                    imageCount: 0
                ))
            }
        }

        return containers
    }

    /// List immediate subfolders of a container (for sidebar navigation).
    public func subfolders(in container: SourceContainer) async throws -> [SourceContainer] {
        let path = smbPath(from: container.id)
        let client = try await ensureConnected()
        let items = try await client.contentsOfDirectory(atPath: path)

        var results: [SourceContainer] = []
        for item in items {
            let name = (item[.nameKey] as? String) ?? ""
            if name.hasPrefix(".") { continue }
            let isDir = (item[.isDirectoryKey] as? Bool) ?? false
            if isDir {
                let subPath = path == "/" ? "/\(name)" : "\(path)/\(name)"
                results.append(SourceContainer(
                    id: smbID(path: subPath),
                    name: name,
                    children: [],
                    imageCount: 0
                ))
            }
        }
        return results
    }

    public func assetCount(in container: SourceContainer) async throws -> Int {
        let path = smbPath(from: container.id)
        return try await countImages(atPath: path)
    }

    public func assets(in container: SourceContainer, offset: Int, limit: Int) async throws -> [ImageAsset] {
        let path = smbPath(from: container.id)
        let all = try await listImages(atPath: path)
        guard offset < all.count else { return [] }
        let end = min(offset + limit, all.count)
        return Array(all[offset..<end])
    }

    public func thumbnail(for asset: ImageAsset, size: CGSize) async throws -> CGImage {
        let path = smbPath(from: asset.id)
        let client = try await ensureConnected()
        let maxDim = max(size.width, size.height)

        // 1. Check .coral/thumbs/ cache on the SMB share (same cache as local filesystem)
        let parentPath = (path as NSString).deletingLastPathComponent
        let cachePath = "\(parentPath)/.coral/thumbs/\(asset.filename).jpg"

        if let cacheData = try? await client.contents(atPath: cachePath),
           let cached = CGImageSourceCreateWithData(cacheData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(cached, 0, nil) {
            return image
        }

        // 2. Extract thumbnail from the original file
        let ext = (asset.filename as NSString).pathExtension.lowercased()
        let isRAW = ["cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "dng", "pef", "srw"].contains(ext)

        // RAW: try partial reads first (embedded preview is in the header)
        let chunkSizes: [UInt64] = isRAW ? [UInt64(512 * 1024), UInt64(2 * 1024 * 1024)] : []
        var thumbnail: CGImage?

        for chunkSize in chunkSizes {
            if let data = try? await client.contents(atPath: path, range: 0..<chunkSize),
               let thumb = extractThumbnail(from: data, maxDim: maxDim) {
                thumbnail = thumb
                break
            }
        }

        // Full file fallback
        if thumbnail == nil {
            let data = try await client.contents(atPath: path)
            thumbnail = extractThumbnail(from: data, maxDim: maxDim)
        }

        guard let thumb = thumbnail else {
            throw SMBError.decodeFailed(path)
        }

        // 3. Write to .coral/thumbs/ on the SMB share for next time
        writeThumbnailCache(thumb, atPath: cachePath, client: client)

        return thumb
    }

    public func metadataData(for asset: ImageAsset) async throws -> Data {
        let path = smbPath(from: asset.id)
        let client = try await ensureConnected()
        // EXIF/IPTC/GPS is always in the first 256KB of any image format
        return try await client.contents(atPath: path, range: 0..<(256 * 1024))
    }

    public func fullImageData(for asset: ImageAsset) async throws -> Data {
        let path = smbPath(from: asset.id)
        NSLog("[CoralMaple] SMBSource.fullImageData: downloading %@", path)
        let client = try await ensureConnected()
        let data = try await client.contents(atPath: path)
        NSLog("[CoralMaple] SMBSource.fullImageData: got %d bytes", data.count)
        return data
    }

    /// Write an XMP sidecar next to the image on the SMB share.
    /// e.g. `/Photos/France/IMG_001.DNG` → `/Photos/France/IMG_001.xmp`
    public func writeSidecar(_ model: AdjustmentModel, for asset: ImageAsset) async throws {
        let path = smbPath(from: asset.id)
        let stem = (path as NSString).deletingPathExtension
        let sidecarPath = stem + ".xmp"

        let serializer = XMPSerializer()
        let xmpData = serializer.serialize(model)

        let client = try await ensureConnected()

        // Try to remove existing file first (ignore error if not found)
        do {
            try await client.removeFile(atPath: sidecarPath)
            NSLog("[CoralMaple] SMB: deleted existing sidecar at %@", sidecarPath)
        } catch {
            NSLog("[CoralMaple] SMB: no existing sidecar (or delete failed): %@", "\(error)")
        }

        // Small delay to let SMB server process the delete
        try? await Task.sleep(for: .milliseconds(100))

        try await client.write(data: xmpData, toPath: sidecarPath, progress: nil)
        NSLog("[CoralMaple] SMB: sidecar written to %@", sidecarPath)
    }

    /// Read an XMP sidecar from next to the image on the SMB share.
    public func readSidecar(for asset: ImageAsset) async throws -> AdjustmentModel? {
        let path = smbPath(from: asset.id)
        let stem = (path as NSString).deletingPathExtension
        let sidecarPath = stem + ".xmp"

        let client = try await ensureConnected()
        guard let data = try? await client.contents(atPath: sidecarPath),
              !data.isEmpty else {
            return nil
        }

        let parser = XMPParser()
        return try parser.parse(data: data)
    }

    /// Write thumbnail JPEG to SMB cache in the background — non-blocking.
    private func writeThumbnailCache(_ image: CGImage, atPath path: String, client: SMB2Manager) {
        Task.detached(priority: .utility) {
            guard let mutableData = CFDataCreateMutable(nil, 0),
                  let dest = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else { return }
            let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
            CGImageDestinationAddImage(dest, image, opts as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return }
            let data = mutableData as Data

            let dir = (path as NSString).deletingLastPathComponent
            let parentDir = (dir as NSString).deletingLastPathComponent
            // Create .coral/ then .coral/thumbs/
            try? await client.createDirectory(atPath: parentDir)
            try? await client.createDirectory(atPath: dir)
            try? await client.write(data: data, toPath: path, progress: nil)
        }
    }

    private func extractThumbnail(from data: Data, maxDim: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public func fullImage(for asset: ImageAsset) async throws -> CGImage {
        let path = smbPath(from: asset.id)
        let client = try await ensureConnected()
        let data = try await client.contents(atPath: path)

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SMBError.decodeFailed(path)
        }

        return image
    }

    // MARK: - Private helpers

    /// List images in a single directory (no recursion into subfolders).
    private func listImages(atPath path: String) async throws -> [ImageAsset] {
        let client = try await ensureConnected()
        let items = try await client.contentsOfDirectory(atPath: path)

        var results: [ImageAsset] = []

        for item in items {
            let name = (item[.nameKey] as? String) ?? ""
            if name.hasPrefix(".") { continue }
            let isDir = (item[.isDirectoryKey] as? Bool) ?? false

            if !isDir, Self.isImageFilename(name) {
                let filePath = path == "/" ? "/\(name)" : "\(path)/\(name)"
                let modified = item[.contentModificationDateKey] as? Date

                results.append(ImageAsset(
                    id: smbID(path: filePath),
                    sourceType: .filesystem,
                    filename: name,
                    pixelWidth: 0,
                    pixelHeight: 0,
                    creationDate: modified,
                    fileURL: nil
                ))
            }
        }

        return results
    }

    private func countImages(atPath path: String) async throws -> Int {
        let client = try await ensureConnected()
        let items = try await client.contentsOfDirectory(atPath: path)

        var count = 0
        for item in items {
            let name = (item[.nameKey] as? String) ?? ""
            if name.hasPrefix(".") { continue }
            let isDir = (item[.isDirectoryKey] as? Bool) ?? false

            if !isDir, Self.isImageFilename(name) {
                count += 1
            } else if Self.isImageFilename(name) {
                count += 1
            }
        }

        return count
    }

    private static func isImageFilename(_ name: String) -> Bool {
        ImageAsset.isImageFilename(name)
    }

    /// Encode an SMB path as a container/asset ID: "smb://host:port/share/path"
    private func smbID(path: String) -> String {
        "smb://\(config.host):\(config.port)/\(config.share)\(path)"
    }

    /// Decode a container/asset ID back to a relative SMB path.
    private func smbPath(from id: String) -> String {
        let prefix = "smb://\(config.host):\(config.port)/\(config.share)"
        guard id.hasPrefix(prefix) else { return id }
        let path = String(id.dropFirst(prefix.count))
        return path.isEmpty ? "/" : path
    }
}

// MARK: - Errors

public enum SMBError: Error, Sendable {
    case invalidURL(String)
    case connectionFailed(String)
    case decodeFailed(String)
    case notConnected
}
