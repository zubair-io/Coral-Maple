import SwiftUI
import CoralCore

/// Left panel in full-image mode — 80px vertical strip of thumbnails.
struct FilmstripView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                ForEach(viewModel.assetSlots.compactMap { $0 }) { asset in
                    let isActive: Bool = {
                        if case .fullImage(let id) = viewModel.appMode {
                            return id == asset.id
                        }
                        return false
                    }()

                    filmstripThumbnail(asset: asset, isActive: isActive)
                        .onTapGesture {
                            viewModel.enterFullImage(assetID: asset.id)
                        }
                }
            }
            .padding(4)
        }
        .frame(width: 80)
        .background(JM.sidebar)
    }

    private func filmstripThumbnail(asset: ImageAsset, isActive: Bool) -> some View {
        Rectangle()
            .fill(JM.surfaceAlt)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isActive ? JM.primary : .clear, lineWidth: 2)
            )
            .accessibilityLabel(asset.filename)
    }
}
