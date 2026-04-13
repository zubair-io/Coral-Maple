import CoreGraphics
import Foundation
import UniformTypeIdentifiers

// MARK: - SourceType

public enum SourceType: String, Sendable, Codable, Hashable {
    case photoKit
    case filesystem
}

// MARK: - ImageAsset

/// Unified identity for an image regardless of its data source.
public struct ImageAsset: Identifiable, Sendable, Hashable {
    /// PhotoKit local identifier or file URL absoluteString.
    public let id: String
    public let sourceType: SourceType
    public let filename: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let creationDate: Date?
    /// Non-nil for filesystem assets; nil for PhotoKit assets.
    public let fileURL: URL?
    public let uniformType: UTType?

    public init(
        id: String,
        sourceType: SourceType,
        filename: String,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        creationDate: Date? = nil,
        fileURL: URL? = nil,
        uniformType: UTType? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.fileURL = fileURL
        self.uniformType = uniformType
    }
}

// MARK: - Image Extension Utilities

extension ImageAsset {
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "bmp", "gif", "webp",
        "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "dng", "pef", "srw"
    ]

    public static func isImageFilename(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }
}

// MARK: - SourceContainer

/// A folder, album, or smart album that contains images.
public struct SourceContainer: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public var children: [SourceContainer]
    public var imageCount: Int

    public init(
        id: String,
        name: String,
        children: [SourceContainer] = [],
        imageCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.children = children
        self.imageCount = imageCount
    }
}

// MARK: - LibrarySource

/// Abstraction over a data source that provides images (PhotoKit or filesystem).
public protocol LibrarySource: Sendable {
    /// Top-level containers (albums, root folders).
    func rootContainers() async throws -> [SourceContainer]

    /// Immediate subfolders of a container. Default returns empty.
    func subfolders(in container: SourceContainer) async throws -> [SourceContainer]

    /// Total number of assets in a container (cheap — no enumeration).
    func assetCount(in container: SourceContainer) async throws -> Int

    /// A page of assets starting at `offset`, up to `limit` items.
    func assets(in container: SourceContainer, offset: Int, limit: Int) async throws -> [ImageAsset]

    /// Generate a thumbnail for an asset at the requested size.
    func thumbnail(for asset: ImageAsset, size: CGSize) async throws -> CGImage

    /// Load the full-resolution image.
    func fullImage(for asset: ImageAsset) async throws -> CGImage

    /// Load file data for metadata extraction. Returns enough bytes to read EXIF/IPTC.
    func metadataData(for asset: ImageAsset) async throws -> Data
}

extension LibrarySource {
    public func subfolders(in container: SourceContainer) async throws -> [SourceContainer] { [] }

    public func metadataData(for asset: ImageAsset) async throws -> Data { Data() }
}
