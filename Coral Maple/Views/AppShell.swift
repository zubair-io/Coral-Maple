import SwiftUI
import CoralCore

struct AppShell: View {
    @State private var viewModel = UnifiedLibraryViewModel()
    @State private var editSession = EditSession()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTab: DetailTab = .info

    // Sources
    @State private var filesystemSource = FilesystemSource()
    @State private var photoKitSource = PhotoKitSource()

    // Last viewed folder persistence
    @AppStorage("lastContainerID") private var lastContainerID: String = ""
    @AppStorage("lastContainerName") private var lastContainerName: String = ""
    @State private var hasRestoredLastFolder = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SourceTreeView(filesystemSource: filesystemSource, photoKitSource: photoKitSource)
                .background(JM.sidebar)
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 320)
            #endif
        } content: {
            centerPanel
        } detail: {
            DetailPanelView(selectedTab: $selectedTab)
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
            #else
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 300)
            #endif
        }
        .background(JM.bg)
        .environment(viewModel)
        .environment(editSession)
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.appMode) { _, newMode in
            withAnimation(.easeInOut(duration: 0.2)) {
                switch newMode {
                case .fullImage(let assetID):
                    columnVisibility = .doubleColumn
                    selectedTab = .color  // Auto-switch to Color panel
                    // Begin editing
                    if let asset = viewModel.loadedAssetsByID[assetID],
                       let source = viewModel.activeSource {
                        Task { await editSession.beginEditing(asset: asset, source: source) }
                    }
                case .browse:
                    columnVisibility = .all
                    selectedTab = .info
                    Task { await editSession.endEditing() }
                }
            }
        }
        .onChange(of: viewModel.activeContainer?.id) { _, newID in
            if let newID, let name = viewModel.activeContainer?.name {
                lastContainerID = newID
                lastContainerName = name
            }
        }
        .task {
            // Wire edit-session → view-model so the grid thumbnail refreshes
            // after each save. Captured once; fine for the app lifetime.
            editSession.onThumbnailRegenerated = { [viewModel] assetID, image in
                Task { await viewModel.applyRegeneratedThumbnail(image, for: assetID) }
            }

            guard !hasRestoredLastFolder, !lastContainerID.isEmpty else { return }
            hasRestoredLastFolder = true
            await restoreLastFolder()
        }
    }

    private var centerPanel: some View {
        Group {
            switch viewModel.appMode {
            case .browse:
                ImageGridView()
            case .fullImage(let assetID):
                FullImageView(assetID: assetID)
            }
        }
        .background(JM.bg)
    }

    private func restoreLastFolder() async {
        let id = lastContainerID
        let name = lastContainerName

        if id.hasPrefix("smb://") { return }

        let source: any LibrarySource
        if id.hasPrefix("photokit://") {
            source = photoKitSource
        } else {
            // Wait for bookmarks to be resolved and scopedURLs populated —
            // without this, the security scope isn't available and opendir
            // fails with EPERM on sandboxed volumes.
            await filesystemSource.ensureReady()
            source = filesystemSource
        }

        let container = SourceContainer(id: id, name: name, children: [], imageCount: 0)
        await viewModel.loadAssets(from: container, source: source)
    }
}
