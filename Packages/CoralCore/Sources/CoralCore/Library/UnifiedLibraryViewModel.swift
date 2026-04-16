import CoreGraphics
import Foundation
import Observation

// MARK: - Sort & Filter

public enum SortOrder: String, Sendable, CaseIterable {
    case dateDesc  = "Date (Newest)"
    case dateAsc   = "Date (Oldest)"
    case nameAsc   = "Name (A–Z)"
    case nameDesc  = "Name (Z–A)"
    case ratingDesc = "Rating"
    case flagFirst  = "Picks First"
}

public struct FilterCriteria: Sendable, Equatable {
    public var minRating: Int?
    public var flags: Set<Flag>?
    public var labels: Set<ColorLabel>?
    public var onlyEdited: Bool

    public init(minRating: Int? = nil, flags: Set<Flag>? = nil, labels: Set<ColorLabel>? = nil, onlyEdited: Bool = false) {
        self.minRating = minRating
        self.flags = flags
        self.labels = labels
        self.onlyEdited = onlyEdited
    }

    public static let none = FilterCriteria()

    public var isActive: Bool { self != .none }
}

// MARK: - AppMode

public enum AppMode: Sendable, Equatable {
    case browse
    case fullImage(assetID: String)
}

// MARK: - UnifiedLibraryViewModel

@Observable
@MainActor
public final class UnifiedLibraryViewModel {

    // MARK: Published state

    /// Subfolders in the current container — shown as folder tiles at the top of the grid.
    public private(set) var subfolders: [SourceContainer] = []

    /// Sparse array — slots for every asset. nil = not yet loaded (shows placeholder).
    public private(set) var assetSlots: [ImageAsset?] = []
    /// Total count of assets in the current container.
    public private(set) var totalAssetCount: Int = 0
    /// Which page indices have been loaded or are in-flight.
    private var loadedPages: Set<Int> = []
    private var pageFailures: [Int: Int] = [:]  // page -> failure count
    private static let maxPageRetries = 3
    private static let pageSize = 50

    public var selectedAssetIDs: Set<String> = [] {
        didSet { selectedAssetChanged() }
    }
    public var activeContainer: SourceContainer?
    public var sortOrder: SortOrder = .dateDesc {
        didSet {
            if oldValue != sortOrder { resortCurrentAssets() }
        }
    }
    public var filterCriteria: FilterCriteria = .none
    public private(set) var isLoading = false
    public var appMode: AppMode = .browse

    /// The currently selected single asset (nil if multi-select or nothing selected).
    public private(set) var selectedAsset: ImageAsset?

    /// Culling state for the selected asset, loaded from the sidecar store.
    public private(set) var selectedCulling: CullingState?

    // MARK: Dependencies

    private let sidecarStore: XMPSidecarStore
    private let thumbnailLoader: ThumbnailLoader

    /// The source that was used to load the current set of assets.
    public private(set) var activeSource: (any LibrarySource)?

    /// Cached culling states keyed by asset ID.
    private var cullingCache: [String: CullingState] = [:]

    /// All asset IDs we've loaded so far (for selection lookup).
    public private(set) var loadedAssetsByID: [String: ImageAsset] = [:]

    /// Monotonic generation counter — incremented on each `loadAssets` call.
    /// Every async continuation checks this before writing state, so a stale
    /// load from a previously-selected folder is silently dropped.
    private var loadGeneration: UInt64 = 0

    public init(sidecarStore: XMPSidecarStore = XMPSidecarStore(), thumbnailLoader: ThumbnailLoader = ThumbnailLoader()) {
        self.sidecarStore = sidecarStore
        self.thumbnailLoader = thumbnailLoader
    }

    // MARK: - Loading

    public func loadAssets(from container: SourceContainer, source: any LibrarySource) async {
        // Bump generation — any in-flight load for the previous folder will
        // see a stale `gen` and stop writing into our arrays.
        loadGeneration &+= 1
        let gen = loadGeneration

        await thumbnailLoader.cancelAll()

        // Release iterator + security scope resources for the old folder.
        if let oldContainer = activeContainer {
            (activeSource as? FilesystemSource)?.resetCache(for: oldContainer.id)
        }

        activeContainer = container
        activeSource = source
        loadedAssetsByID = [:]
        loadedPages = []
        pageFailures = [:]
        totalAssetCount = 0
        assetSlots = []
        subfolders = []
        isLoading = true

        do {
            // Load subfolders and asset count in parallel
            async let fetchedSubfolders = source.subfolders(in: container)
            async let fetchedCount = source.assetCount(in: container)

            subfolders = (try? await fetchedSubfolders) ?? []

            // Bail if the user already clicked another folder
            guard gen == loadGeneration else { return }

            totalAssetCount = try await fetchedCount
            guard gen == loadGeneration else { return }

            assetSlots = Array(repeating: nil, count: totalAssetCount)
            isLoading = false
            await loadPage(0, generation: gen)
        } catch {
            guard gen == loadGeneration else { return }
            NSLog("[CoralMaple] loadAssets: ERROR %@", "\(error)")
            totalAssetCount = 0
            assetSlots = []
            subfolders = []
            isLoading = false
        }
    }

    /// Called by the grid when a cell at `index` becomes visible.
    /// Loads the page containing that index if not already loaded.
    public func ensureLoaded(around index: Int) {
        let page = index / Self.pageSize
        guard !loadedPages.contains(page) else { return }
        loadedPages.insert(page)
        let gen = loadGeneration
        Task { await loadPage(page, generation: gen) }
    }

    private func loadPage(_ page: Int, generation gen: UInt64) async {
        guard gen == loadGeneration else { return }
        guard let source = activeSource, let container = activeContainer else { return }
        let offset = page * Self.pageSize
        guard offset < totalAssetCount else { return }

        do {
            let assets = try await source.assets(in: container, offset: offset, limit: Self.pageSize)
            // Check generation AFTER the await — another folder may have been selected.
            guard gen == loadGeneration else { return }
            for (i, asset) in assets.enumerated() {
                let slotIndex = offset + i
                guard slotIndex < assetSlots.count else { break }
                assetSlots[slotIndex] = asset
                loadedAssetsByID[asset.id] = asset
            }
        } catch {
            guard gen == loadGeneration else { return }
            NSLog("[CoralMaple] loadPage %d: ERROR %@", page, "\(error)")
            let failures = (pageFailures[page] ?? 0) + 1
            pageFailures[page] = failures
            if failures >= Self.maxPageRetries {
                NSLog("[CoralMaple] loadPage %d: giving up after %d failures", page, failures)
            } else {
                loadedPages.remove(page)  // allow retry
            }
        }
    }

    // MARK: - Sorting

    private func resortCurrentAssets() {
        // Collect all loaded assets, sort them, rebuild the sparse array
        var loaded = assetSlots.compactMap { $0 }
        guard !loaded.isEmpty else { return }

        loaded.sort { a, b in
            switch sortOrder {
            case .dateDesc:
                return (a.creationDate ?? .distantPast) > (b.creationDate ?? .distantPast)
            case .dateAsc:
                return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
            case .nameAsc:
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            case .nameDesc:
                return a.filename.localizedStandardCompare(b.filename) == .orderedDescending
            case .ratingDesc:
                return (cullingCache[a.id]?.rating ?? 0) > (cullingCache[b.id]?.rating ?? 0)
            case .flagFirst:
                let ap = cullingCache[a.id]?.flag.sortPriority ?? 1
                let bp = cullingCache[b.id]?.flag.sortPriority ?? 1
                return ap < bp
            }
        }

        // Rebuild sparse array: sorted loaded assets at the front, nil for the rest
        var newSlots = [ImageAsset?](repeating: nil, count: totalAssetCount)
        for (i, asset) in loaded.enumerated() {
            guard i < newSlots.count else { break }
            newSlots[i] = asset
        }
        assetSlots = newSlots
    }

    // MARK: - Selection

    public func selectAsset(_ id: String) {
        selectedAssetIDs = [id]
    }

    public func toggleSelection(_ id: String) {
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    public func extendSelection(to id: String) {
        guard let lastSelected = selectedAssetIDs.first,
              let startIdx = assetSlots.firstIndex(where: { $0?.id == lastSelected }),
              let endIdx = assetSlots.firstIndex(where: { $0?.id == id }) else {
            selectAsset(id)
            return
        }
        let range = min(startIdx, endIdx)...max(startIdx, endIdx)
        selectedAssetIDs = Set(assetSlots[range].compactMap { $0?.id })
    }

    public func enterFullImage(assetID: String) {
        selectedAssetIDs = [assetID]
        appMode = .fullImage(assetID: assetID)
    }

    public func exitFullImage() {
        appMode = .browse
    }

    /// Navigate to the next or previous image.
    public func navigate(direction: Int) {
        guard let current = selectedAsset,
              let idx = assetSlots.firstIndex(where: { $0?.id == current.id }) else { return }
        let newIdx = idx + direction
        guard assetSlots.indices.contains(newIdx), let next = assetSlots[newIdx] else { return }
        selectedAssetIDs = [next.id]
        if case .fullImage = appMode {
            appMode = .fullImage(assetID: next.id)
        }
    }

    // MARK: - Culling

    public func setCulling(_ state: CullingState, for assetID: String) async {
        guard let asset = loadedAssetsByID[assetID] else { return }

        cullingCache[assetID] = state

        // Write to sidecar
        do {
            var model = try await sidecarStore.read(for: asset) ?? AdjustmentModel()
            model.culling = state
            try await sidecarStore.write(model, for: asset)
        } catch {
            // Sidecar write failed — cache still holds the value for this session
        }

        if selectedAsset?.id == assetID {
            selectedCulling = state
        }
    }

    private func updateCulling(for assetID: String, _ mutate: (inout CullingState) -> Void) async {
        var state = cullingCache[assetID] ?? CullingState()
        mutate(&state)
        await setCulling(state, for: assetID)
    }

    public func setRating(_ rating: Int, for assetID: String) async {
        await updateCulling(for: assetID) { $0.setRating(rating) }
    }

    public func toggleFlag(_ flag: Flag, for assetID: String) async {
        await updateCulling(for: assetID) { $0.toggleFlag(flag) }
    }

    public func toggleLabel(_ label: ColorLabel, for assetID: String) async {
        await updateCulling(for: assetID) { $0.toggleLabel(label) }
    }

    // MARK: - Thumbnails

    public func thumbnail(for asset: ImageAsset, size: CGSize, source: any LibrarySource) async -> CGImage? {
        await thumbnailLoader.thumbnail(for: asset, size: size, source: source)
    }

    /// Replace the cached grid thumbnail for an asset (e.g. after an edit saves).
    /// Invalidates any other cached sizes so they're re-read with the new content.
    public func applyRegeneratedThumbnail(_ image: CGImage, for assetID: String) async {
        await thumbnailLoader.invalidate(assetID: assetID)
        // Prime the size the grid requests — see ImageGridView (280pt × 2 for retina).
        let primeSize = CGSize(width: 560, height: 560)
        await thumbnailLoader.prime(assetID: assetID, size: primeSize, image: image)
        // Publish the regen event so visible grid cells of this asset refresh.
        lastRegeneratedAssetID = assetID
        lastRegeneratedTick &+= 1
    }

    /// The asset whose thumbnail was most recently regenerated. Grid cells
    /// observe this together with `lastRegeneratedTick` to know when to reload.
    public private(set) var lastRegeneratedAssetID: String?

    /// Bumped alongside `lastRegeneratedAssetID` so back-to-back regenerations
    /// of the same asset still trigger a fresh reload.
    public private(set) var lastRegeneratedTick: UInt64 = 0

    // MARK: - Private

    private func selectedAssetChanged() {
        if selectedAssetIDs.count == 1, let id = selectedAssetIDs.first {
            selectedAsset = loadedAssetsByID[id]
            selectedCulling = cullingCache[id]
            loadCullingForSelected()
        } else {
            selectedAsset = nil
            selectedCulling = nil
        }
    }

    private func loadCullingForSelected() {
        guard let asset = selectedAsset else { return }
        let id = asset.id

        if cullingCache[id] != nil { return }

        Task {
            do {
                if let model = try await sidecarStore.read(for: asset) {
                    cullingCache[id] = model.culling
                    if selectedAsset?.id == id {
                        selectedCulling = model.culling
                    }
                }
            } catch {
                // No sidecar or read failed
            }
        }
    }
}

// MARK: - Flag sort priority

extension Flag {
    var sortPriority: Int {
        switch self {
        case .pick: return 0
        case .unflagged: return 1
        case .reject: return 2
        }
    }
}
