import SwiftUI
import CoralCore

/// Full image viewer with real-pixel zoom.
///
/// `pixelScale` is **real screen pixels per image pixel**:
/// - 1.0 = pixel-perfect (one image pixel = one real screen pixel — true 100%)
/// - Below 1.0 = zoomed out (fit-to-view is usually 0.10–0.20 for RAW files)
/// - Above 1.0 = zoomed in beyond native (image pixels enlarged to multiple
///   screen pixels)
///
/// Why real pixels and not points: on a 2× retina display a points-based
/// "100%" would actually be 2× zoom and would never produce crisp output.
/// Working in real pixels lets us hand the renderer a target sized for the
/// actual hardware, which is what makes 100% look truly 1:1.
struct FullImageView: View {
    let assetID: String
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @Environment(EditSession.self) private var editSession
    @Environment(\.displayScale) private var displayScale

    /// Current zoom, in real screen pixels per image pixel. 0 means "fit"
    /// (resolved against the viewport at lookup time).
    @State private var pixelScale: CGFloat = 0  // 0 = fit
    @State private var baseScale: CGFloat = 0
    @State private var panOffset: CGSize = .zero
    @State private var basePan: CGSize = .zero
    /// Resolved scale captured at the start of a pinch — `value.magnification`
    /// is cumulative, so we anchor against this instead of the live pixelScale.
    @State private var pinchStartScale: CGFloat?
    @State private var thumbnailImage: CGImage?
    @State private var showExportSheet = false
    @State private var viewportSize: CGSize = .zero
    @FocusState private var isFocused: Bool

    private var asset: ImageAsset? { viewModel.loadedAssetsByID[assetID] }

    /// Fit-to-view scale (real pixels per image pixel) for the current image
    /// and viewport. Both dimensions are converted to real pixels first.
    private func fitScale(viewport: CGSize, imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return 1 }
        let viewportPx = CGSize(
            width: viewport.width * displayScale,
            height: viewport.height * displayScale
        )
        return min(viewportPx.width / imageSize.width,
                   viewportPx.height / imageSize.height)
    }

    /// Effective pixel scale — resolves "fit" mode to a concrete scale.
    private func effectiveScale(viewport: CGSize) -> CGFloat {
        let imageSize = editSession.nativeImageSize == .zero
            ? CGSize(width: 6000, height: 4000)  // fallback
            : editSession.nativeImageSize
        if pixelScale == 0 {
            return fitScale(viewport: viewport, imageSize: imageSize)
        }
        return pixelScale
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                JM.canvas.ignoresSafeArea()

                if let displayImage = editSession.previewImage ?? thumbnailImage {
                    let imageSize = editSession.nativeImageSize == .zero
                        ? CGSize(width: displayImage.width, height: displayImage.height)
                        : editSession.nativeImageSize
                    let scale = effectiveScale(viewport: geometry.size)
                    // scale is real-px-per-image-px; convert to points for SwiftUI frame.
                    let displayW = imageSize.width * scale / displayScale
                    let displayH = imageSize.height * scale / displayScale

                    Image(decorative: displayImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displayW, height: displayH)
                        .offset(panOffset)
                        .gesture(magnificationGesture(viewport: geometry.size))
                        .simultaneousGesture(dragGesture)
                        .overlay {
                            if editSession.isEyedropperActive {
                                eyedropperOverlay(imageSize: imageSize, scale: scale)
                            }
                        }
                }

                if editSession.isRendering && editSession.previewImage == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(JM.textMuted)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                zoomIndicator(viewport: geometry.size)
            }
            .onAppear {
                viewportSize = geometry.size
                // previewSize in real pixels so the renderer matches the hardware
                editSession.previewSize = CGSize(
                    width: geometry.size.width * displayScale,
                    height: geometry.size.height * displayScale
                )
                editSession.zoomScale = effectiveScale(viewport: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                viewportSize = newSize
                editSession.previewSize = CGSize(
                    width: newSize.width * displayScale,
                    height: newSize.height * displayScale
                )
                editSession.zoomScale = effectiveScale(viewport: newSize)
            }
            .onChange(of: pixelScale) { _, _ in
                editSession.zoomScale = effectiveScale(viewport: viewportSize)
            }
        }
        .background(JM.canvas)
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .task(id: assetID) {
            isFocused = true
            pixelScale = 0      // reset to fit
            baseScale = 0
            panOffset = .zero
            basePan = .zero
            await loadThumbnail()
        }
        #if os(macOS)
        .onKeyPress(.escape) {
            viewModel.exitFullImage()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.navigate(direction: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.navigate(direction: 1)
            return .handled
        }
        .onKeyPress(characters: .init(charactersIn: "pxu012345")) { press in
            guard let id = viewModel.selectedAsset?.id else { return .ignored }
            let ch = press.characters
            if ch == "p" { Task { await viewModel.toggleFlag(.pick, for: id) }; return .handled }
            if ch == "x" { Task { await viewModel.toggleFlag(.reject, for: id) }; return .handled }
            if ch == "u" { Task { await viewModel.toggleFlag(.unflagged, for: id) }; return .handled }
            if let n = Int(ch), (0...5).contains(n) { Task { await viewModel.setRating(n, for: id) }; return .handled }
            return .ignored
        }
        #endif
        .toolbar {
            FullImageToolbarView(showExportSheet: $showExportSheet)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Fit") { pixelScale = 0; baseScale = 0; panOffset = .zero; basePan = .zero }
                Button("100%") {
                    pixelScale = 1.0
                    baseScale = 1.0
                    panOffset = .zero
                    basePan = .zero
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet()
        }
    }

    // MARK: - Eyedropper overlay

    @ViewBuilder
    private func eyedropperOverlay(imageSize: CGSize, scale: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard imageSize.width > 0, imageSize.height > 0 else { return }
                // location is in points; frame width is imageSize * scale / displayScale pts
                let frameW = imageSize.width * scale / displayScale
                let frameH = imageSize.height * scale / displayScale
                let x = location.x / frameW
                let y = location.y / frameH
                guard x >= 0, x <= 1, y >= 0, y <= 1 else { return }
                editSession.sampleWhiteBalance(at: CGPoint(x: x, y: y))
            }
            #if os(macOS)
            .onHover { hovering in
                if hovering {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
    }

    // MARK: - Load thumbnail

    private func loadThumbnail() async {
        guard let source = viewModel.activeSource, let asset else { return }
        thumbnailImage = nil
        let thumbSize = CGSize(width: 800, height: 800)
        thumbnailImage = await viewModel.thumbnail(for: asset, size: thumbSize, source: source)
    }

    // MARK: - Gestures

    private func magnificationGesture(viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Anchor against the scale at gesture start — value.magnification
                // is cumulative since the gesture began, so multiplying it into
                // the live pixelScale every frame compounds and blows up.
                let start = pinchStartScale ?? effectiveScale(viewport: viewport)
                if pinchStartScale == nil { pinchStartScale = start }

                let fit = fitScale(viewport: viewport, imageSize: editSession.nativeImageSize)
                let newScale = max(fit * 0.5, min(start * value.magnification, 8.0))
                pixelScale = newScale
            }
            .onEnded { value in
                let start = pinchStartScale ?? effectiveScale(viewport: viewport)
                let fit = fitScale(viewport: viewport, imageSize: editSession.nativeImageSize)
                let newScale = max(fit * 0.5, min(start * value.magnification, 8.0))
                pixelScale = newScale
                baseScale = newScale
                pinchStartScale = nil

                // Snap back to fit if zoomed out past fit
                if newScale <= fit * 1.02 {
                    pixelScale = 0
                    baseScale = 0
                    panOffset = .zero
                    basePan = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if pixelScale > 0 {
                    // zoomed in — pan
                    panOffset = CGSize(
                        width: basePan.width + value.translation.width,
                        height: basePan.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if pixelScale > 0 {
                    basePan = panOffset
                } else {
                    // fit mode — swipe left/right navigates
                    if value.translation.width < -50 {
                        viewModel.navigate(direction: 1)
                    } else if value.translation.width > 50 {
                        viewModel.navigate(direction: -1)
                    }
                }
            }
    }

    // MARK: - Zoom indicator

    private func zoomIndicator(viewport: CGSize) -> some View {
        let percent = Int(effectiveScale(viewport: viewport) * 100)
        return Text("\(percent)%")
            .font(JM.Font.caption(.medium))
            .foregroundStyle(JM.textMain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(JM.surface.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(8)
    }
}
