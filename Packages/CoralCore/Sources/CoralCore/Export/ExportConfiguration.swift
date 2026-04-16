import Foundation

/// Configuration for image export.
public struct ExportConfiguration: Sendable, Codable {

    public enum ResizeMode: Sendable, Codable, Hashable {
        case original
        case longEdge(Int)
    }

    public var format: ExportFormat = .jpeg
    public var quality: Double = 0.92        // 0...1, for JPEG/HEIC
    public var resizeMode: ResizeMode = .original
    public var includeMetadata: Bool = true

    public init() {}
}
