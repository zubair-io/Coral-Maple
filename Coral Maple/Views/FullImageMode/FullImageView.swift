import SwiftUI
import CoralCore

struct FullImageView: View {
    let assetID: String
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0
    @State private var zoomAnchor: UnitPoint = .center
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var loadedImage: CGImage?
    @State private var isLoadingFullRes = true
    @FocusState private var isFocused: Bool

    private var asset: ImageAsset? {
        viewModel.loadedAssetsByID[assetID]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                JM.canvas.ignoresSafeArea()

                if let loadedImage {
                    Image(decorative: loadedImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale, anchor: zoomAnchor)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        .simultaneousGesture(dragGesture)
                }

                if isLoadingFullRes {
                    ProgressView()
                        .controlSize(.small)
                        .tint(JM.textMuted)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if loadedImage != nil {
                    zoomIndicator
                }
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
            await loadImage()
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
        // Culling hotkeys
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
            FullImageToolbarView()
        }
    }

    // MARK: - Load image

    private func loadImage() async {
        guard let source = viewModel.activeSource,
              let asset else { return }
        isLoadingFullRes = true
        loadedImage = nil
        zoomScale = 1.0
        baseZoomScale = 1.0
        zoomAnchor = .center
        offset = .zero
        baseOffset = .zero

        do {
            // Show thumbnail first (from memory cache — instant)
            let thumbSize = CGSize(width: 800, height: 800)
            if let thumb = await viewModel.thumbnail(for: asset, size: thumbSize, source: source) {
                loadedImage = thumb
            }

            // Load full resolution
            let full = try await source.fullImage(for: asset)
            withAnimation(.easeIn(duration: 0.15)) {
                loadedImage = full
                isLoadingFullRes = false
            }
        } catch {
            NSLog("[CoralMaple] FullImageView: failed to load %@: %@", asset.filename, "\(error)")
            isLoadingFullRes = false
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = max(0.5, min(baseZoomScale * value.magnification, 10))
            }
            .onEnded { value in
                zoomScale = max(0.5, min(baseZoomScale * value.magnification, 10))
                baseZoomScale = zoomScale
                if zoomScale <= 1.01 {
                    zoomAnchor = .center
                    offset = .zero
                    baseOffset = .zero
                    baseZoomScale = 1.0
                    zoomScale = 1.0
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if zoomScale > 1 {
                    offset = CGSize(
                        width: baseOffset.width + value.translation.width,
                        height: baseOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { value in
                if zoomScale > 1 {
                    baseOffset = offset
                } else {
                    // Swipe navigation when not zoomed
                    if value.translation.width < -50 {
                        viewModel.navigate(direction: 1)
                    } else if value.translation.width > 50 {
                        viewModel.navigate(direction: -1)
                    }
                }
            }
    }

    // MARK: - Zoom indicator

    private var zoomIndicator: some View {
        Text("\(Int(zoomScale * 100))%")
            .font(JM.Font.caption(.medium))
            .foregroundStyle(JM.textMain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(JM.surface.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(8)
    }
}
