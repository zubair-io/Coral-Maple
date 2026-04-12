import SwiftUI
import CoralCore

/// Center panel in browse mode — justified grid of thumbnails.
struct ImageGridView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

    @State private var thumbnailSize: ThumbnailSize = .medium

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.dimension, maximum: thumbnailSize.dimension + 40), spacing: 4)]
    }

    var body: some View {
        VStack(spacing: 0) {
            gridToolbar
            gridContent
        }
    }

    // MARK: - Toolbar

    private var gridToolbar: some View {
        HStack {
            // Breadcrumb
            if let container = viewModel.activeContainer {
                Text(container.name)
                    .font(JM.Font.body(.medium))
                    .foregroundStyle(JM.textMain)
            } else {
                Text("No folder selected")
                    .font(JM.Font.body())
                    .foregroundStyle(JM.textMuted)
            }

            Spacer()

            // Thumbnail size
            Picker("Size", selection: $thumbnailSize) {
                ForEach(ThumbnailSize.allCases, id: \.self) { size in
                    Image(systemName: size.icon)
                        .tag(size)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            // Sort
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        viewModel.sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12))
                    .foregroundStyle(JM.textMuted)
            }
            .accessibilityLabel("Sort order")

            // Filter
            filterMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(JM.surface)
    }

    private var filterMenu: some View {
        Menu {
            Button("All") {
                viewModel.filterCriteria = .none
            }
            Button("Picks Only") {
                viewModel.filterCriteria = FilterCriteria(flags: [.pick])
            }
            Button("4+ Stars") {
                viewModel.filterCriteria = FilterCriteria(minRating: 4)
            }
            Button("Unedited") {
                viewModel.filterCriteria = FilterCriteria(onlyEdited: false)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12))
                if viewModel.filterCriteria.isActive {
                    Circle()
                        .fill(JM.primary)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(viewModel.filterCriteria.isActive ? JM.primary : JM.textMuted)
        }
        .accessibilityLabel("Filter")
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridContent: some View {
        if viewModel.totalAssetCount == 0 && viewModel.subfolders.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    // Subfolders first
                    ForEach(viewModel.subfolders) { folder in
                        FolderTile(folder: folder, size: thumbnailSize.dimension)
                            .onTapGesture {
                                let container = SourceContainer(id: folder.id, name: folder.name, children: [], imageCount: 0)
                                if let source = viewModel.activeSource {
                                    Task { await viewModel.loadAssets(from: container, source: source) }
                                }
                            }
                    }

                    // Images
                    ForEach(0..<viewModel.assetSlots.count, id: \.self) { index in
                        let slot = viewModel.assetSlots[index]

                        if let asset = slot {
                            ThumbnailCell(
                                asset: asset,
                                size: thumbnailSize.dimension,
                                isSelected: viewModel.selectedAssetIDs.contains(asset.id)
                            )
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                viewModel.enterFullImage(assetID: asset.id)
                            })
                            .simultaneousGesture(TapGesture(count: 1).onEnded {
                                viewModel.selectAsset(asset.id)
                            })
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(JM.surfaceAlt)
                                .frame(width: thumbnailSize.dimension, height: thumbnailSize.dimension)
                                .onAppear {
                                    viewModel.ensureLoaded(around: index)
                                }
                        }
                    }
                }
                .padding(4)
                // Force SwiftUI to recreate cells when folder changes
                .id(viewModel.activeContainer?.id ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(JM.textMuted)
            Text("No photos")
                .font(JM.Font.body(.medium))
                .foregroundStyle(JM.textMain)
            Text("Open a folder to get started")
                .font(JM.Font.caption())
                .foregroundStyle(JM.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Thumbnail size

enum ThumbnailSize: String, CaseIterable {
    case small, medium, large

    var dimension: CGFloat {
        switch self {
        case .small:  return 80
        case .medium: return 140
        case .large:  return 220
        }
    }

    var icon: String {
        switch self {
        case .small:  return "square.grid.4x3.fill"
        case .medium: return "square.grid.3x3.fill"
        case .large:  return "square.grid.2x2.fill"
        }
    }
}

// MARK: - Thumbnail Cell

struct ThumbnailCell: View {
    let asset: ImageAsset
    let size: CGFloat
    let isSelected: Bool

    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @State private var thumbnail: CGImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var isVisible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(JM.surfaceAlt)
            .frame(width: size, height: size)
            .overlay {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(JM.primary, lineWidth: isSelected ? 2 : 0)
            )
            .accessibilityLabel(asset.filename)
            .onChange(of: asset.id) { _, _ in
                // Asset changed (folder switch) — clear stale thumbnail
                thumbnail = nil
                loadTask?.cancel()
                loadTask = nil
            }
            .onAppear {
                isVisible = true
                guard thumbnail == nil, loadTask == nil else { return }
                startLoad()
            }
            .onDisappear {
                isVisible = false
                loadTask?.cancel()
                loadTask = nil
            }
    }

    private func startLoad() {
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, isVisible else { return }
            guard let source = viewModel.activeSource else { return }
            let thumbSize = CGSize(width: size * 2, height: size * 2)
            let result = await viewModel.thumbnail(for: asset, size: thumbSize, source: source)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                thumbnail = result
            }
        }
    }
}

// MARK: - Folder Tile

struct FolderTile: View {
    let folder: SourceContainer
    let size: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.3))
                .foregroundStyle(JM.textMuted)
            Text(folder.name)
                .font(JM.Font.caption(.medium))
                .foregroundStyle(JM.textMain)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size)
        .background(JM.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
