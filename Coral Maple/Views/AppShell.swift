import SwiftUI
import CoralCore

struct AppShell: View {
    @State private var viewModel = UnifiedLibraryViewModel()
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
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.appMode) { _, newMode in
            withAnimation(.easeInOut(duration: 0.2)) {
                switch newMode {
                case .fullImage:
                    columnVisibility = .doubleColumn
                case .browse:
                    columnVisibility = .all
                }
            }
        }
        // Save last loaded folder
        .onChange(of: viewModel.activeContainer?.id) { _, newID in
            if let newID, let name = viewModel.activeContainer?.name {
                lastContainerID = newID
                lastContainerName = name
            }
        }
        // Restore last folder on launch
        .task {
            guard !hasRestoredLastFolder, !lastContainerID.isEmpty else { return }
            hasRestoredLastFolder = true
            // Small delay to let sources load first
            try? await Task.sleep(for: .milliseconds(500))
            restoreLastFolder()
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

    private func restoreLastFolder() {
        let id = lastContainerID
        let name = lastContainerName
        let container = SourceContainer(id: id, name: name, children: [], imageCount: 0)

        let source: any LibrarySource
        if id.hasPrefix("photokit://") {
            source = photoKitSource
        } else if id.hasPrefix("smb://") {
            // SMB sources need to be connected first — skip for now
            return
        } else {
            source = filesystemSource
        }

        Task {
            await viewModel.loadAssets(from: container, source: source)
        }
    }
}
