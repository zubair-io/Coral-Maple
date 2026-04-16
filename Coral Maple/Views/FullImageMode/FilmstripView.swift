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
        FilmstripCell(asset: asset, isActive: isActive)
    }
}

private struct FilmstripCell: View {
    let asset: ImageAsset
    let isActive: Bool
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @State private var thumbnail: CGImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(JM.surfaceAlt)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isActive ? JM.primary : .clear, lineWidth: 2)
            )
            .accessibilityLabel(asset.filename)
            .onAppear {
                guard thumbnail == nil, loadTask == nil else { return }
                loadTask = Task {
                    guard let source = viewModel.activeSource else { return }
                    let size = CGSize(width: 144, height: 144)
                    thumbnail = await viewModel.thumbnail(for: asset, size: size, source: source)
                }
            }
            .onDisappear {
                loadTask?.cancel()
                loadTask = nil
            }
    }
}
