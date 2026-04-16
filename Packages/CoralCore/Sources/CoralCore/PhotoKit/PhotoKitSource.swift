import CoreGraphics
import Foundation
import Photos

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// `LibrarySource` implementation for Apple Photos via PhotoKit.
public final class PhotoKitSource: LibrarySource, @unchecked Sendable {

    private let bridge: PhotoKitBridge
    private let imageManager: PHImageManager

    /// Cached fetch result for the current container — avoids re-fetching on every page.
    private var cachedFetchResult: PHFetchResult<PHAsset>?
    private var cachedContainerID: String?

    public init(bridge: PhotoKitBridge = PhotoKitBridge(), imageManager: PHImageManager = .default()) {
        self.bridge = bridge
        self.imageManager = imageManager
        bridge.onChange = { [weak self] in
            self?.cachedFetchResult = nil
            self?.cachedContainerID = nil
        }
        bridge.startObserving()
    }

    // MARK: - LibrarySource

    public func rootContainers() async throws -> [SourceContainer] {
        if bridge.currentStatus != .authorized && bridge.currentStatus != .limited {
            let status = await bridge.requestAuthorization()
            guard status == .authorized || status == .limited else {
                return []
            }
        }

        var containers: [SourceContainer] = []

        // All Photos
        let allPhotos = PHAsset.fetchAssets(with: .image, options: nil)
        containers.append(SourceContainer(
            id: "photokit://all-photos",
            name: "All Photos",
            imageCount: allPhotos.count
        ))

        // Favorites
        let favorites = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
        if let fav = favorites.firstObject {
            let count = PHAsset.fetchAssets(in: fav, options: nil).count
            containers.append(SourceContainer(
                id: "photokit://smart/\(fav.localIdentifier)",
                name: "Favorites",
                imageCount: count
            ))
        }

        // User albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            containers.append(SourceContainer(
                id: "photokit://album/\(collection.localIdentifier)",
                name: collection.localizedTitle ?? "Untitled",
                imageCount: count
            ))
        }

        return containers
    }

    public func assetCount(in container: SourceContainer) async throws -> Int {
        let fetchResult = try fetchResultFor(container: container)
        return fetchResult.count
    }

    public func assets(in container: SourceContainer, offset: Int, limit: Int) async throws -> [ImageAsset] {
        let fetchResult = try fetchResultFor(container: container)
        let count = fetchResult.count
        guard offset < count else { return [] }
        let end = min(offset + limit, count)

        var results = [ImageAsset]()
        results.reserveCapacity(end - offset)

        for i in offset..<end {
            let phAsset = fetchResult.object(at: i)
            results.append(ImageAsset(
                id: phAsset.localIdentifier,
                sourceType: .photoKit,
                filename: "",
                pixelWidth: phAsset.pixelWidth,
                pixelHeight: phAsset.pixelHeight,
                creationDate: phAsset.creationDate,
                fileURL: nil
            ))
        }

        return results
    }

    // MARK: - Fetch result cache

    private func fetchResultFor(container: SourceContainer) throws -> PHFetchResult<PHAsset> {
        if container.id == cachedContainerID, let cached = cachedFetchResult {
            return cached
        }

        let fetchResult: PHFetchResult<PHAsset>

        if container.id == "photokit://all-photos" {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        } else if container.id.hasPrefix("photokit://smart/") || container.id.hasPrefix("photokit://album/") {
            let prefix = container.id.hasPrefix("photokit://smart/") ? "photokit://smart/" : "photokit://album/"
            let localID = String(container.id.dropFirst(prefix.count))
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [localID], options: nil
            )
            guard let collection = collections.firstObject else {
                throw PhotoKitError.assetNotFound(localID)
            }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            throw PhotoKitError.assetNotFound(container.id)
        }

        cachedFetchResult = fetchResult
        cachedContainerID = container.id
        return fetchResult
    }

    public func thumbnail(for asset: ImageAsset, size: CGSize) async throws -> CGImage {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw PhotoKitError.assetNotFound(asset.id)
        }
        return try await requestCGImage(
            for: phAsset,
            targetSize: size,
            deliveryMode: .highQualityFormat,
            resizeMode: .fast
        )
    }

    public func fullImage(for asset: ImageAsset) async throws -> CGImage {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw PhotoKitError.assetNotFound(asset.id)
        }
        let size = CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight)
        return try await requestCGImage(
            for: phAsset,
            targetSize: size,
            deliveryMode: .highQualityFormat,
            resizeMode: .none
        )
    }

    // MARK: - Shared image request helper

    private func requestCGImage(
        for phAsset: PHAsset,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.resizeMode = resizeMode
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            // PHImageManager can call the handler more than once (degraded then full).
            // A continuation must resume exactly once — guard with a Sendable class.
            final class ResumeGuard: @unchecked Sendable {
                private var _resumed = false
                private let lock = NSLock()
                var resumed: Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    return _resumed
                }
                /// Returns true if this is the first call (i.e. we should resume).
                func tryResume() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if _resumed { return false }
                    _resumed = true
                    return true
                }
            }
            let guard_ = ResumeGuard()

            imageManager.requestImage(
                for: phAsset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // If cancelled or errored, resume with error (this is the final callback).
                if let error = info?[PHImageErrorKey] as? Error {
                    if guard_.tryResume() {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    if guard_.tryResume() {
                        continuation.resume(throwing: PhotoKitError.decodeFailed(phAsset.localIdentifier))
                    }
                    return
                }

                // Skip degraded callbacks — wait for the final result
                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }

                // Final, non-degraded result
                guard guard_.tryResume() else { return }

                #if canImport(UIKit)
                if let cgImage = image?.cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: PhotoKitError.decodeFailed(phAsset.localIdentifier))
                }
                #elseif canImport(AppKit)
                if let image = image {
                    var rect = CGRect(origin: .zero, size: image.size)
                    if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                        continuation.resume(returning: cgImage)
                    } else {
                        continuation.resume(throwing: PhotoKitError.decodeFailed(phAsset.localIdentifier))
                    }
                } else {
                    continuation.resume(throwing: PhotoKitError.decodeFailed(phAsset.localIdentifier))
                }
                #endif
            }
        }
    }

    public func metadataData(for asset: ImageAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [asset.id], options: nil)
            guard let phAsset = fetchResult.firstObject else {
                continuation.resume(throwing: PhotoKitError.assetNotFound(asset.id))
                return
            }

            let resources = PHAssetResource.assetResources(for: phAsset)
            guard let resource = resources.first else {
                continuation.resume(throwing: PhotoKitError.decodeFailed(asset.id))
                return
            }

            var data = Data()
            var resumed = false
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            let requestID = PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                data.append(chunk)
            } completionHandler: { error in
                guard !resumed else { return }
                resumed = true
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }

            // Cancel once we have enough bytes for EXIF/IPTC extraction.
            // The completion handler fires after cancellation with the data
            // accumulated so far — no error is produced.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) {
                if data.count >= 256 * 1024, !resumed {
                    PHAssetResourceManager.default().cancelDataRequest(requestID)
                }
            }
        }
    }
}

// MARK: - Errors

public enum PhotoKitError: Error, Sendable {
    case assetNotFound(String)
    case thumbnailFailed(String)
    case decodeFailed(String)
    case unauthorized
}
