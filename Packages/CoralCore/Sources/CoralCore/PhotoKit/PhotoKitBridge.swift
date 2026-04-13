import Foundation
import Photos

/// Manages PhotoKit authorization and change observation.
public final class PhotoKitBridge: NSObject, @unchecked Sendable {

    public enum AuthorizationStatus: Sendable {
        case authorized
        case limited
        case denied
        case restricted
        case notDetermined
    }

    private let library: PHPhotoLibrary

    /// Fires when the photo library content changes.
    public var onChange: (@Sendable () -> Void)?

    public init(library: PHPhotoLibrary = .shared()) {
        self.library = library
        super.init()
    }

    public var currentStatus: AuthorizationStatus {
        Self.mapStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAuthorization() async -> AuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.mapStatus(status)
    }

    /// Start observing photo library changes.
    public func startObserving() {
        library.register(self)
    }

    /// Stop observing photo library changes.
    public func stopObserving() {
        library.unregisterChangeObserver(self)
    }

    private static func mapStatus(_ status: PHAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .authorized:      return .authorized
        case .limited:         return .limited
        case .denied:          return .denied
        case .restricted:      return .restricted
        case .notDetermined:   return .notDetermined
        @unknown default:      return .denied
        }
    }
}

extension PhotoKitBridge: PHPhotoLibraryChangeObserver {
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?()
    }
}
