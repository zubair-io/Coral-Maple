import SwiftUI
import CoralCore

/// Root view — three-column layout on all platforms.
/// On Mac/iPad landscape: all three columns visible.
/// On iPad portrait / iPhone: sidebar is a slide-over drawer.
struct AppShell: View {
    @State private var viewModel = UnifiedLibraryViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTab: DetailTab = .info

    // Sources
    @State private var filesystemSource = FilesystemSource()
    @State private var photoKitSource = PhotoKitSource()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            leftPanel
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 320)
            #endif
        } content: {
            centerPanel
        } detail: {
            DetailPanelView(selectedTab: $selectedTab)
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
            #endif
        }
        .background(JM.bg)
        .environment(viewModel)
        .preferredColorScheme(.dark)
    }

    // MARK: - Panels

    private var leftPanel: some View {
        Group {
            switch viewModel.appMode {
            case .browse:
                SourceTreeView(filesystemSource: filesystemSource, photoKitSource: photoKitSource)
            case .fullImage:
                FilmstripView()
            }
        }
        .background(JM.sidebar)
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
}
