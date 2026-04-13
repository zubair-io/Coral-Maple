import Foundation

/// Thread-safe read/write/discover API for XMP sidecar files.
///
/// Uses `NSFileCoordinator` for safe concurrent access. All methods are async
/// and never block the main thread.
public actor XMPSidecarStore {

    private let resolver: SidecarPathResolver
    private let parser: XMPParser
    private let serializer: XMPSerializer
    private let fileManager: FileManager

    public init(
        resolver: SidecarPathResolver = SidecarPathResolver(),
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.parser = XMPParser()
        self.serializer = XMPSerializer()
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Read the adjustment model from an asset's sidecar. Returns nil if no sidecar exists.
    public func read(for asset: ImageAsset) throws -> AdjustmentModel? {
        let url = resolver.sidecarURL(for: asset)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        var coordinatorError: NSError?
        var result: Result<AdjustmentModel, Error>?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                let data = try Data(contentsOf: readURL)
                let model = try parser.parse(data: data)
                result = .success(model)
            } catch {
                result = .failure(error)
            }
        }

        if let coordErr = coordinatorError { throw coordErr }
        switch result {
        case .success(let model): return model
        case .failure(let error): throw error
        case .none: return nil
        }
    }

    /// Write an adjustment model to the asset's sidecar file.
    /// Creates parent directories if needed.
    public func write(_ model: AdjustmentModel, for asset: ImageAsset) throws {
        let url = resolver.sidecarURL(for: asset)

        // Ensure parent directory exists
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let data = serializer.serialize(model)

        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordErr = coordinatorError { throw coordErr }
        if let err = writeError { throw XMPError.writeFailure(err.localizedDescription) }
    }

    /// Check whether a sidecar exists for the given asset.
    public func exists(for asset: ImageAsset) -> Bool {
        let url = resolver.sidecarURL(for: asset)
        return fileManager.fileExists(atPath: url.path)
    }

    /// Discover all `.xmp` files in a directory (non-recursive).
    public func discover(in directory: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.filter { $0.pathExtension.lowercased() == "xmp" }
    }

    /// Resolve the sidecar URL for an asset (exposed for tests / UI display).
    public func sidecarURL(for asset: ImageAsset) -> URL {
        resolver.sidecarURL(for: asset)
    }
}
