import Foundation

/// Determines the correct `.xmp` sidecar file path for a given asset.
///
/// - **Filesystem assets:** sidecar is a sibling file with the same stem and `.xmp` extension
///   (e.g. `IMG_1234.CR3` → `IMG_1234.xmp`).
/// - **PhotoKit assets:** sidecar is stored at
///   `~/Pictures/Coral Maple/sidecars/<UUID>.xmp` because PhotoKit does not expose
///   a writable path inside the library package.
public struct SidecarPathResolver: Sendable {

    /// Root directory for PhotoKit sidecars. Defaults to `~/Pictures/Coral Maple/sidecars`.
    public let photoKitSidecarRoot: URL

    public init(photoKitSidecarRoot: URL? = nil) {
        if let override = photoKitSidecarRoot {
            self.photoKitSidecarRoot = override
        } else {
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
            self.photoKitSidecarRoot = pictures
                .appendingPathComponent("Coral Maple", isDirectory: true)
                .appendingPathComponent("sidecars", isDirectory: true)
        }
    }

    public func sidecarURL(for asset: ImageAsset) -> URL {
        switch asset.sourceType {
        case .filesystem:
            guard let fileURL = asset.fileURL else {
                // Fallback: use PhotoKit path strategy with the asset ID
                return photoKitSidecarRoot.appendingPathComponent("\(asset.id).xmp")
            }
            return fileURL.deletingPathExtension().appendingPathExtension("xmp")

        case .photoKit:
            return photoKitSidecarRoot.appendingPathComponent("\(asset.id).xmp")
        }
    }
}
