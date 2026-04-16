import CoreGraphics
import CoreImage
import Foundation
import Observation

/// Observable state that bridges adjustment sliders, the image pipeline,
/// and XMP sidecar persistence.
///
/// **Usage:**
/// 1. Call `beginEditing(asset:source:)` when entering full-image mode
/// 2. Bind UI sliders to `adjustments` fields
/// 3. Observe `previewImage` to display the processed result
/// 4. Call `endEditing()` when leaving full-image mode
@Observable
@MainActor
public final class EditSession {

    // MARK: - Published state

    /// Current adjustments. Bind sliders directly to these fields.
    public var adjustments: AdjustmentModel = AdjustmentModel() {
        didSet {
            if oldValue != adjustments {
                NSLog("[CoralMaple] EditSession: adjustments changed (exposure=%.2f contrast=%.0f)",
                      adjustments.exposure, adjustments.contrast)
                scheduleRender()
                scheduleSave()
            }
        }
    }

    /// The rendered preview image for display.
    public private(set) var previewImage: CGImage?

    /// Native size of the decoded image (full RAW resolution).
    public private(set) var nativeImageSize: CGSize = .zero

    /// Whether a render is in progress.
    public private(set) var isRendering = false

    /// Whether we're actively editing an asset.
    public private(set) var isEditing = false

    /// The asset being edited.
    public private(set) var asset: ImageAsset?

    /// Whether the WB eyedropper is active — next tap on image samples WB.
    public var isEyedropperActive = false

    /// Sample a pixel from the preview and compute WB to make it neutral.
    /// `point` is in unit coordinates (0..1) relative to the preview image.
    public func sampleWhiteBalance(at point: CGPoint) {
        guard let image = decodedImage else { return }

        // Convert unit coords to image pixel coords
        let extent = image.extent
        let x = extent.origin.x + point.x * extent.width
        let y = extent.origin.y + (1.0 - point.y) * extent.height  // flip Y (UI top-left, CI bottom-left)

        // Sample a 5x5 region for stability
        let sampleRect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
            .intersection(extent)
        let avgFilter = image
            .applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: sampleRect)])

        // Render the 1x1 average to get the pixel
        let ciContext = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(avgFilter, toBitmap: &bitmap, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        NSLog("[CoralMaple] Eyedropper sampled RGB: %.3f, %.3f, %.3f", r, g, b)

        // Compute WB adjustment to neutralize this pixel.
        // If R/G ratio > 1, the image is too warm → shift cooler (lower temp).
        // If B/G ratio > 1, the image is too cool → shift warmer (higher temp).
        let currentTemp = adjustments.temperature
        let currentTint = adjustments.tint

        let rg = r / max(g, 0.001)
        let bg = b / max(g, 0.001)

        // Temperature adjustment — R/B ratio drives warm/cool shift
        // If R is higher than B, the pixel looks warm — reduce temp to cool it.
        let tempShift = (rg - bg) * 2000.0  // empirical scale
        let newTemp = max(2000, min(12000, currentTemp - tempShift))

        // Tint adjustment — green channel vs R+B average drives green/magenta shift
        let rbAvg = (r + b) / 2.0
        let tintShift = (g - rbAvg) * 50.0
        let newTint = max(-100, min(100, currentTint - tintShift))

        NSLog("[CoralMaple] Eyedropper: WB %.0f→%.0f, tint %.1f→%.1f",
              currentTemp, newTemp, currentTint, newTint)

        adjustments.temperature = newTemp
        adjustments.tint = newTint
        isEyedropperActive = false
    }

    // MARK: - Private state

    /// Decoded base CIImage (before adjustments). Cached to avoid re-decode.
    private var decodedImage: CIImage?

    /// Cached raw file data for non-local sources (SMB/PhotoKit) — avoids re-downloading.
    private var cachedFileData: Data?

    /// True once the current asset has been decoded into `decodedImage`.
    /// Decode is always neutral — WB/exposure are post-decode filters now —
    /// so we only re-decode when switching to a different asset.
    private var hasDecoded = false

    /// Preview size for rendering (set from the view's geometry).
    public var previewSize: CGSize = CGSize(width: 1920, height: 1080)

    /// Current zoom scale (screen pixels per image pixel). Set by FullImageView.
    /// Used for idle re-renders — when zoomed in, we re-render at
    /// `previewSize * zoomScale` so the user sees real image pixels.
    public var zoomScale: CGFloat = 1.0 {
        didSet {
            if abs(zoomScale - oldValue) > 0.01 {
                scheduleRefine()
            }
        }
    }

    private var renderTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let pipeline: ImageEditPipeline
    private let sidecarStore: XMPSidecarStore
    private let thumbDiskCache: ThumbnailDiskCache
    private let previewCache: RenderedPreviewCache

    /// Callback fired after a save regenerates an edited thumbnail.
    /// The view model wires this to `ThumbnailLoader.prime(...)` so the grid
    /// picks up the new thumbnail without waiting for a re-read.
    /// Invoked on the main actor.
    public var onThumbnailRegenerated: ((_ assetID: String, _ image: CGImage) -> Void)?

    /// The source used to load the full image data.
    private var activeSource: (any LibrarySource)?

    // MARK: - Init

    public init(
        pipeline: ImageEditPipeline = ImageEditPipeline(),
        sidecarStore: XMPSidecarStore = XMPSidecarStore(),
        thumbDiskCache: ThumbnailDiskCache = ThumbnailDiskCache(),
        previewCache: RenderedPreviewCache = RenderedPreviewCache()
    ) {
        self.pipeline = pipeline
        self.sidecarStore = sidecarStore
        self.thumbDiskCache = thumbDiskCache
        self.previewCache = previewCache
    }

    // MARK: - Lifecycle

    /// The as-shot WB from EXIF metadata. Available after beginEditing.
    public private(set) var asShotTemperature: Double = 6500
    public private(set) var asShotTint: Double = 0

    /// Begin editing an asset. Decodes the image and loads existing adjustments.
    public func beginEditing(asset: ImageAsset, source: any LibrarySource) async {
        NSLog("[CoralMaple] EditSession.beginEditing: %@ fileURL=%@", asset.filename, asset.fileURL?.path ?? "nil")
        self.asset = asset
        self.activeSource = source
        self.isEditing = true
        self.decodedImage = nil
        self.cachedFileData = nil
        self.hasDecoded = false

        // Extract as-shot WB from EXIF
        await loadAsShotWB(asset: asset, source: source)
        NSLog("[CoralMaple] EditSession: as-shot WB temp=%.0f tint=%.1f", asShotTemperature, asShotTint)

        // Load existing adjustments from sidecar
        do {
            let model: AdjustmentModel?
            if asset.id.hasPrefix("smb://"), let smb = source as? SMBSource {
                let smbPath = asset.id // log the path
                let stem = (smbPath as NSString).deletingPathExtension
                NSLog("[CoralMaple] EditSession: reading SMB sidecar at %@.xmp", stem)
                model = try await smb.readSidecar(for: asset)
            } else {
                let sidecarURL = await sidecarStore.sidecarURL(for: asset)
                NSLog("[CoralMaple] EditSession: reading sidecar at %@", sidecarURL.path)
                model = try await sidecarStore.read(for: asset)
            }
            if let model {
                NSLog("[CoralMaple] EditSession: loaded sidecar — temp=%.0f tint=%.1f exposure=%.2f",
                      model.temperature, model.tint, model.exposure)
                adjustments = model
            } else {
                NSLog("[CoralMaple] EditSession: no sidecar found, using defaults")
                adjustments = AdjustmentModel()
            }
        } catch {
            NSLog("[CoralMaple] EditSession: sidecar read error: %@", "\(error)")
            adjustments = AdjustmentModel()
        }

        // Cold-open: show the cached rendered preview immediately.
        // If we hit the cache we return right away — the user sees pixels in
        // ~0ms. A background task eagerly decodes the RAW so the first slider
        // drag is fast too, but it doesn't block this function.
        if let cached = previewCache.read(assetID: asset.id, adjustments: adjustments) {
            NSLog("[CoralMaple] EditSession: disk preview cache hit for %@", asset.filename)
            previewImage = cached
            if nativeImageSize == .zero {
                nativeImageSize = CGSize(width: cached.width, height: cached.height)
            }
            // Eagerly decode in background so sliders respond instantly later.
            scheduleBackgroundDecode()
            return
        }

        // No cache — must decode and render now.
        await decodeAndRender(targetSize: fastTargetSize)
        scheduleRefine()
    }

    /// Decode the RAW off the main actor so the UI stays responsive.
    /// Doesn't render — the cached preview is already showing.
    private func scheduleBackgroundDecode() {
        guard let asset, let source = activeSource else { return }
        renderTask = Task {
            let decoded: CIImage?
            if let fileURL = asset.fileURL {
                let p = pipeline
                decoded = await Task.detached {
                    try? p.decode(url: fileURL)
                }.value
            } else {
                if cachedFileData == nil {
                    cachedFileData = try? await source.fullImageData(for: asset)
                }
                if let data = cachedFileData, data.count > 1000 {
                    let p = pipeline
                    let fname = asset.filename
                    decoded = await Task.detached {
                        try? p.decode(data: data, filename: fname)
                    }.value
                } else {
                    let cgImage = try? await source.fullImage(for: asset)
                    decoded = cgImage.map { CIImage(cgImage: $0) }
                }
            }
            guard !Task.isCancelled else { return }
            decodedImage = decoded
            hasDecoded = true
            if let extent = decoded?.extent {
                nativeImageSize = CGSize(width: extent.width, height: extent.height)
            }
            NSLog("[CoralMaple] EditSession: background decode complete, extent=%.0fx%.0f",
                  nativeImageSize.width, nativeImageSize.height)
        }
    }

    private func loadAsShotWB(asset: ImageAsset, source: any LibrarySource) async {
        asShotTemperature = 6500
        asShotTint = 0

        // Read as-shot WB from CIRAWFilter (reads DNG calibration tags correctly)
        let decoder = RAWDecodeEngine()
        if let fileURL = asset.fileURL,
           let wb = decoder.asShotWB(url: fileURL) {
            asShotTemperature = wb.temperature
            asShotTint = wb.tint
            NSLog("[CoralMaple] EditSession: as-shot WB from RAW (local) temp=%.0f tint=%.1f", wb.temperature, wb.tint)
            return
        }
        // For SMB/PhotoKit, we need the file data
        if asset.fileURL == nil, asset.id.hasPrefix("smb://") || asset.sourceType == .photoKit {
            if let data = cachedFileData {
                if let wb = decoder.asShotWB(data: data, filename: asset.filename) {
                    asShotTemperature = wb.temperature
                    asShotTint = wb.tint
                    NSLog("[CoralMaple] EditSession: as-shot WB from cached RAW temp=%.0f tint=%.1f", wb.temperature, wb.tint)
                    return
                }
            }
        }

        // Fallback: read EXIF ColorTemperature if present
        do {
            let meta: ImageMetadata
            if let fileURL = asset.fileURL {
                meta = ImageMetadata.from(url: fileURL)
            } else {
                let data = try await source.metadataData(for: asset)
                NSLog("[CoralMaple] EditSession EXIF: got %d bytes metadata", data.count)
                meta = ImageMetadata.from(data: data)
            }
            NSLog("[CoralMaple] EditSession EXIF: camera=%@ lens=%@ iso=%@ aperture=%@ shutter=%@",
                  meta.cameraModel ?? "nil", meta.lens ?? "nil",
                  meta.iso ?? "nil", meta.aperture ?? "nil", meta.shutterSpeed ?? "nil")
            if let temp = meta.asShotTemperature {
                asShotTemperature = temp
            }
            if let tint = meta.asShotTint {
                asShotTint = tint
            }
        } catch {}
    }

    /// Apply as-shot white balance from EXIF.
    public func applyAsShotWB() {
        adjustments.temperature = asShotTemperature
        adjustments.tint = asShotTint
    }

    /// End editing. Flush sidecar write and release resources.
    public func endEditing() async {
        // Cancel in-flight work — we'll do a final save + thumb regen below.
        renderTask?.cancel()
        refineTask?.cancel()
        saveTask?.cancel()

        // Flush sidecar + regenerate the grid thumbnail before clearing state.
        // This guarantees the browse-mode grid shows the latest edit.
        if let asset, adjustments != AdjustmentModel() {
            do {
                if asset.id.hasPrefix("smb://"), let smb = activeSource as? SMBSource {
                    try await smb.writeSidecar(adjustments, for: asset)
                } else {
                    if let fileURL = asset.fileURL {
                        let parent = fileURL.deletingLastPathComponent()
                        let accessing = parent.startAccessingSecurityScopedResource()
                        defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
                        try await sidecarStore.write(adjustments, for: asset)
                    } else {
                        try await sidecarStore.write(adjustments, for: asset)
                    }
                }
            } catch {}

            // Regenerate thumbnail synchronously so the callback fires before
            // we nil out `asset` / `decodedImage`.
            await regenerateThumbnail(for: asset)

            // Also persist the preview to disk cache for instant cold-open.
            persistCurrentPreviewToCache()
        }

        isEditing = false
        asset = nil
        activeSource = nil
        decodedImage = nil
        hasDecoded = false
        previewImage = nil
    }

    // MARK: - Actions

    /// Revert all adjustments to defaults (preserving culling state).
    public func revert() {
        let culling = adjustments.culling
        adjustments = AdjustmentModel()
        adjustments.culling = culling
    }

    /// Copy current adjustments (for paste to another image).
    public func copyAdjustments() -> AdjustmentModel {
        adjustments
    }

    /// Paste adjustments from another image.
    public func pasteAdjustments(_ source: AdjustmentModel) {
        var pasted = source
        pasted.culling = adjustments.culling // keep current culling
        adjustments = pasted
    }

    // MARK: - Rendering
    //
    // Two-phase rendering for smooth sliders + crisp zoom:
    //   1. Fast pass (50ms debounce): render at previewSize (fit-to-viewport
    //      resolution). Fast enough to follow a slider drag in real time.
    //   2. Refine pass (300ms idle debounce): if zoomed in, re-render at
    //      `previewSize * zoomScale` so 100% / over-native views show real
    //      image pixels instead of an upscaled low-res preview.
    //
    // Any slider change cancels both pending tasks and reschedules. Changing
    // `zoomScale` (e.g. user pinches) schedules only the refine pass.

    /// Fast preview target size — what we render at during slider interaction.
    private var fastTargetSize: CGSize { previewSize }

    /// Refined target size — what we render at once sliders go idle.
    ///
    /// At zoom Z (real screen pixels per image pixel), the user sees the full
    /// image at `nativeSize × Z` screen pixels. To be crisp, the rendered
    /// bitmap must have at least as many pixels as the displayed size, but
    /// never more than native (upscale has no benefit). So:
    ///
    ///   target = nativeSize × min(Z, 1.0)   — capped at native
    ///
    /// We floor at `previewSize` (viewport-resolution fast preview) so the
    /// refine pass is never *lower* quality than the fast pass.
    private var refinedTargetSize: CGSize {
        guard nativeImageSize != .zero else { return previewSize }
        let scale = min(zoomScale, 1.0)
        let w = max(nativeImageSize.width * scale, previewSize.width)
        let h = max(nativeImageSize.height * scale, previewSize.height)
        return CGSize(width: w, height: h)
    }

    private func scheduleRender() {
        renderTask?.cancel()
        refineTask?.cancel()
        renderTask = Task {
            // 50ms debounce for real-time slider interaction
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await decodeAndRender(targetSize: fastTargetSize)
            guard !Task.isCancelled else { return }
            scheduleRefine()
        }
    }

    /// Schedule a high-resolution refine pass after the user stops interacting.
    /// Safe to call redundantly — each call cancels the prior pending refine.
    private func scheduleRefine() {
        refineTask?.cancel()
        // Only worth refining when the refined target exceeds the fast target.
        let refined = refinedTargetSize
        let fast = fastTargetSize
        guard refined.width > fast.width + 1 || refined.height > fast.height + 1 else {
            // Even without a refine, persist the fast render so cold-opens hit.
            persistCurrentPreviewToCache()
            return
        }
        refineTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await decodeAndRender(targetSize: refined)
            guard !Task.isCancelled else { return }
            persistCurrentPreviewToCache()
        }
    }

    /// Snapshot the current adjustments into the disk cache so a future
    /// cold-open of this asset can paint pixels instantly.
    ///
    /// We always cache at `fastTargetSize` (viewport-resolution), not at the
    /// refined zoom resolution: the user lands in fit-mode on every open
    /// (FullImageView resets pixelScale to 0 in its task), so a viewport-sized
    /// preview is exactly what they'll see first. This keeps cache files small
    /// (~hundreds of KB instead of tens of MB) and avoids re-encoding 12k×8k
    /// images on every refine.
    private func persistCurrentPreviewToCache() {
        guard let asset, let decoded = decodedImage else { return }
        let snapshot = adjustments
        let cache = previewCache
        let assetID = asset.id
        let pipeline = self.pipeline
        let targetSize = fastTargetSize
        Task.detached(priority: .utility) {
            let processed = pipeline.process(input: decoded, adjustments: snapshot)
            guard let data = pipeline.encodePreviewJPEG(processed: processed, targetSize: targetSize) else {
                return
            }
            cache.write(assetID: assetID, adjustments: snapshot, jpegData: data)
        }
    }

    private func decodeAndRender(targetSize: CGSize) async {
        guard let asset, let source = activeSource else {
            NSLog("[CoralMaple] EditSession.decodeAndRender: no asset or source")
            return
        }
        isRendering = true

        do {
            // Only decode once per asset — WB/exposure are post-decode filters now.
            if !hasDecoded {
                NSLog("[CoralMaple] EditSession: decoding image (fileURL=%@)", asset.fileURL?.path ?? "nil")

                // Download if needed (SMB/PhotoKit) — async, but on main actor is OK
                if asset.fileURL == nil, cachedFileData == nil {
                    NSLog("[CoralMaple] EditSession: downloading full file data...")
                    cachedFileData = try await source.fullImageData(for: asset)
                    NSLog("[CoralMaple] EditSession: got %d bytes (cached)", cachedFileData?.count ?? 0)
                }

                // Decode off the main actor — RAW demosaicing is CPU-heavy and
                // would block the UI for ~300ms on a 100MP file.
                let p = pipeline
                let fileURL = asset.fileURL
                let data = cachedFileData
                let fname = asset.filename
                let decoded: CIImage? = await Task.detached {
                    if let fileURL {
                        return try? p.decode(url: fileURL)
                    } else if let data, data.count > 1000 {
                        return try? p.decode(data: data, filename: fname)
                    }
                    return nil
                }.value

                guard !Task.isCancelled else { isRendering = false; return }

                if let decoded {
                    decodedImage = decoded
                } else if asset.fileURL == nil {
                    // Last resort — fullImage via source
                    let cgImage = try await source.fullImage(for: asset)
                    decodedImage = CIImage(cgImage: cgImage)
                }

                hasDecoded = true
                if let extent = decodedImage?.extent {
                    nativeImageSize = CGSize(width: extent.width, height: extent.height)
                }
                NSLog("[CoralMaple] EditSession: decode complete, extent=%.0fx%.0f",
                      nativeImageSize.width, nativeImageSize.height)
            }

            guard let decoded = decodedImage, !Task.isCancelled else {
                NSLog("[CoralMaple] EditSession: no decoded image or cancelled")
                isRendering = false
                return
            }

            // Apply adjustment chain
            let processed = pipeline.process(input: decoded, adjustments: adjustments)

            NSLog("[CoralMaple] EditSession: rendering preview at %.0fx%.0f",
                  targetSize.width, targetSize.height)
            let preview = pipeline.renderPreview(processed, targetSize: targetSize)

            guard !Task.isCancelled else {
                isRendering = false
                return
            }

            if let preview {
                NSLog("[CoralMaple] EditSession: preview rendered %dx%d",
                      preview.width, preview.height)
                // Only replace previewImage on success — a nil result (huge
                // zoom target, OOM, etc.) shouldn't wipe the last good frame
                // out from under the UI.
                previewImage = preview
            } else {
                NSLog("[CoralMaple] EditSession: preview render returned nil — keeping last frame")
            }
        } catch {
            NSLog("[CoralMaple] EditSession render error: %@", "\(error)")
        }

        isRendering = false
    }

    // MARK: - Sidecar persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let asset else { return }
            guard adjustments != AdjustmentModel() else { return }

            var saveSucceeded = false
            do {
                if asset.id.hasPrefix("smb://"), let smb = activeSource as? SMBSource {
                    let path = (asset.id as NSString).deletingPathExtension
                    NSLog("[CoralMaple] EditSession: saving SMB sidecar to %@.xmp", path)
                    try await smb.writeSidecar(adjustments, for: asset)
                    NSLog("[CoralMaple] EditSession: SMB sidecar saved OK")
                    saveSucceeded = true
                } else if let fileURL = asset.fileURL {
                    let sidecarURL = fileURL.deletingPathExtension().appendingPathExtension("xmp")
                    NSLog("[CoralMaple] EditSession: saving local sidecar to %@", sidecarURL.path)
                    let parent = fileURL.deletingLastPathComponent()
                    let accessing = parent.startAccessingSecurityScopedResource()
                    defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
                    try await sidecarStore.write(adjustments, for: asset)
                    NSLog("[CoralMaple] EditSession: local sidecar saved OK")
                    saveSucceeded = true
                } else {
                    let url = await sidecarStore.sidecarURL(for: asset)
                    NSLog("[CoralMaple] EditSession: saving PhotoKit sidecar to %@", url.path)
                    try await sidecarStore.write(adjustments, for: asset)
                    saveSucceeded = true
                }
            } catch {
                NSLog("[CoralMaple] EditSession save error: %@", "\(error)")
            }

            guard !Task.isCancelled, saveSucceeded else { return }
            await regenerateThumbnail(for: asset)
        }
    }

    /// Render the processed image at grid-thumbnail size and publish it so the
    /// grid reflects the latest edits without waiting for a re-decode.
    /// Writes to disk for local files; memory-only for SMB/PhotoKit.
    private func regenerateThumbnail(for asset: ImageAsset) async {
        // Guard against stale calls — endEditing and scheduleSave can both
        // try to regen. Only proceed if `asset` still matches the active one
        // (or if called from endEditing which passes the captured asset).
        guard let decoded = decodedImage,
              self.asset?.id == asset.id || !isEditing else { return }

        // Grid thumbs are ~280pt wide × 2x retina; 560 covers that.
        let thumbMaxDim: CGFloat = 560
        let processed = pipeline.process(input: decoded, adjustments: adjustments)
        guard let thumb = pipeline.renderPreview(
            processed,
            targetSize: CGSize(width: thumbMaxDim, height: thumbMaxDim)
        ) else { return }

        NSLog("[CoralMaple] EditSession: regenerated thumbnail %dx%d for %@",
              thumb.width, thumb.height, asset.filename)

        // For local files, persist to .coral/thumbs/ so the cache survives restarts.
        if let fileURL = asset.fileURL {
            let parent = fileURL.deletingLastPathComponent()
            let accessing = parent.startAccessingSecurityScopedResource()
            defer { if accessing { parent.stopAccessingSecurityScopedResource() } }
            thumbDiskCache.write(for: fileURL, image: thumb)
        }

        onThumbnailRegenerated?(asset.id, thumb)
    }
}
