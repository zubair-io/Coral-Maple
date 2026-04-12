import SwiftUI
import CoralCore

/// Center panel in full-image mode — zoomable image canvas.
struct FullImageView: View {
    let assetID: String
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    private var asset: ImageAsset? {
        viewModel.assetSlots.compactMap { $0 }.first { $0.id == assetID }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                JM.canvas
                    .ignoresSafeArea()

                if asset != nil {
                    // Placeholder — full image loading will be backed by the pipeline in Phase 2
                    Rectangle()
                        .fill(JM.surfaceAlt)
                        .aspectRatio(
                            CGFloat(asset?.pixelWidth ?? 4) / CGFloat(max(asset?.pixelHeight ?? 3, 1)),
                            contentMode: .fit
                        )
                        .scaleEffect(zoomScale)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        .gesture(dragGesture)
                        .overlay(alignment: .bottomLeading) {
                            zoomIndicator
                        }
                } else {
                    Text("Image not found")
                        .foregroundStyle(JM.textMuted)
                }
            }
        }
        .background(JM.canvas)
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
        #endif
        .toolbar {
            FullImageToolbarView()
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = max(0.5, min(value.magnification, 10))
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if zoomScale > 1 {
                    offset = value.translation
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
