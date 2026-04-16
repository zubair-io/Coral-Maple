import Foundation

/// Determines the correct `.xmp` sidecar file path for a given asset.
///
/// - **Filesystem assets:** sidecar is a sibling file with the same stem and `.xmp` extension
///   (e.g. `IMG_1234.CR3` → `IMG_1234.xmp`).
/// - **PhotoKit assets:** sidecar is stored at
///   `~/Library/Application Support/CoralMaple/sidecars/<UUID>.xmp` because PhotoKit
///   does not expose a writable path inside the library package.
/// - **SMB assets:** sidecars are written directly to the share by `SMBSource.writeSidecar()`.
///   If an SMB asset reaches this resolver (e.g. via culling), the `.smb` case falls back to
///   `~/Library/Application Support/CoralMaple/sidecars/` as a local cache.
public struct SidecarPathResolver: Sendable {

    /// Root directory for PhotoKit sidecars. Defaults to `~/Pictures/Coral Maple/sidecars`.
    public let photoKitSidecarRoot: URL

    public init(photoKitSidecarRoot: URL? = nil) {
        if let override = photoKitSidecarRoot {
            self.photoKitSidecarRoot = override
        } else {
            // Use app support directory — always writable in sandbox
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.photoKitSidecarRoot = appSupport
                .appendingPathComponent("CoralMaple", isDirectory: true)
                .appendingPathComponent("sidecars", isDirectory: true)
        }
    }

    public func sidecarURL(for asset: ImageAsset) -> URL {
        switch asset.sourceType {
        case .filesystem:
            guard let fileURL = asset.fileURL else {
                // Non-file asset — sanitize ID into a valid filename
                let sanitized = asset.id
                    .replacingOccurrences(of: "://", with: "_")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: ":", with: "_")
                return photoKitSidecarRoot.appendingPathComponent("\(sanitized).xmp")
            }
            return fileURL.deletingPathExtension().appendingPathExtension("xmp")

        case .smb:
            // SMB sidecars are written directly to the share by SMBSource.writeSidecar().
            // This local fallback is used by setCulling when no SMBSource is available.
            let sanitized = asset.id
                .replacingOccurrences(of: "://", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            return photoKitSidecarRoot.appendingPathComponent("\(sanitized).xmp")

        case .photoKit:
            return photoKitSidecarRoot.appendingPathComponent("\(asset.id).xmp")
        }
    }
}
