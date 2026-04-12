import SwiftUI
import UniformTypeIdentifiers
import CoralCore

/// Left panel in browse mode — collapsible tree of sources, albums, and folders.
struct SourceTreeView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    let filesystemSource: FilesystemSource
    let photoKitSource: PhotoKitSource

    @State private var photoContainers: [SourceContainer] = []
    @State private var folderContainers: [SourceContainer] = []
    @State private var isAddingFolder = false
    @State private var selectedID: String?
    @State private var expandedIDs: Set<String> = ["__section_folders", "__section_photos"]

    private var isFoldersSectionExpanded: Bool { expandedIDs.contains("__section_folders") }
    private var isPhotosSectionExpanded: Bool { expandedIDs.contains("__section_photos") }

    var body: some View {
        List(selection: $selectedID) {
            // --- Local Folders (on top) ---
            Section {
                if isFoldersSectionExpanded {
                    if folderContainers.isEmpty {
                        Text("No folders added")
                            .font(JM.Font.caption())
                            .foregroundStyle(JM.textMuted)
                    } else {
                        ForEach(visibleFolderEntries, id: \.container.id) { entry in
                            folderRow(entry: entry)
                                .tag(entry.container.id)
                        }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    sectionChevron(id: "__section_folders")
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text("FOLDERS")
                    Spacer()
                    Button {
                        isAddingFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add folder")
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleSection("__section_folders") }
            }

            // --- Photos Library ---
            Section {
                if isPhotosSectionExpanded {
                    if photoContainers.isEmpty {
                        Text("No access")
                            .font(JM.Font.caption())
                            .foregroundStyle(JM.textMuted)
                    } else {
                        ForEach(photoContainers) { container in
                            Label(container.name, systemImage: iconForPhotoContainer(container))
                                .font(JM.Font.body(.regular))
                                .tag(container.id)
                        }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    sectionChevron(id: "__section_photos")
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 10))
                    Text("PHOTOS LIBRARY")
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleSection("__section_photos") }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(JM.sidebar)
        .task {
            await loadSources()
        }
        .onChange(of: selectedID) { _, newValue in
            guard let id = newValue else { return }
            loadContainer(id: id)
        }
        #if os(macOS)
        .fileImporter(isPresented: $isAddingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                addFolder(url)
            }
        }
        #else
        .sheet(isPresented: $isAddingFolder) {
            FolderPicker { url in
                isAddingFolder = false
                addFolder(url)
            }
        }
        .alert("Cannot Browse This Location", isPresented: $showSMBAlert) {
            Button("OK") {}
        } message: {
            Text("This network location doesn't support direct browsing. Try picking a subfolder closer to where your photos are, or copy the photos to On My iPad first.")
        }
        #endif
    }

    // MARK: - Section collapse

    private func sectionChevron(id: String) -> some View {
        Image(systemName: expandedIDs.contains(id) ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(JM.textMuted)
            .frame(width: 10)
    }

    private func toggleSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }

    // MARK: - Folder row

    private func folderRow(entry: FolderEntry) -> some View {
        HStack(spacing: 4) {
            if !entry.container.children.isEmpty {
                Button {
                    toggleSection(entry.container.id)
                } label: {
                    Image(systemName: expandedIDs.contains(entry.container.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(JM.textMuted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(JM.textMuted)

            Text(entry.container.name)
                .font(JM.Font.body(.regular))
                .lineLimit(1)

            Spacer()

            if entry.container.imageCount > 0 {
                Text("\(entry.container.imageCount)")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 16)
    }

    // MARK: - Flatten folders

    private struct FolderEntry {
        let container: SourceContainer
        let depth: Int
    }

    private var visibleFolderEntries: [FolderEntry] {
        buildVisibleEntries(folderContainers, depth: 0)
    }

    private func buildVisibleEntries(_ containers: [SourceContainer], depth: Int) -> [FolderEntry] {
        var result: [FolderEntry] = []
        for c in containers {
            result.append(FolderEntry(container: c, depth: depth))
            if expandedIDs.contains(c.id), !c.children.isEmpty {
                result.append(contentsOf: buildVisibleEntries(c.children, depth: depth + 1))
            }
        }
        return result
    }

    // MARK: - Helpers

    private func iconForPhotoContainer(_ container: SourceContainer) -> String {
        if container.name == "All Photos" { return "photo.on.rectangle.angled" }
        if container.name == "Favorites" { return "heart" }
        return "rectangle.stack"
    }

    // MARK: - Actions

    private func loadContainer(id: String) {
        if let container = photoContainers.first(where: { $0.id == id }) {
            Task { await viewModel.loadAssets(from: container, source: photoKitSource) }
            return
        }
        if let container = findContainer(id: id, in: folderContainers) {
            Task { await viewModel.loadAssets(from: container, source: filesystemSource) }
            return
        }
    }

    private func findContainer(id: String, in containers: [SourceContainer]) -> SourceContainer? {
        for c in containers {
            if c.id == id { return c }
            if let found = findContainer(id: id, in: c.children) { return found }
        }
        return nil
    }

    private func loadSources() async {
        do {
            photoContainers = try await photoKitSource.rootContainers()
        } catch {
            photoContainers = []
        }
        do {
            folderContainers = try await filesystemSource.rootContainers()
            for c in folderContainers {
                expandedIDs.insert(c.id)
            }
        } catch {
            folderContainers = []
        }
    }

    @State private var showSMBAlert = false

    private func addFolder(_ url: URL) {
        guard let container = try? filesystemSource.addFolder(url) else {
            NSLog("[CoralMaple] addFolder: failed for %@", url.path)
            return
        }
        NSLog("[CoralMaple] addFolder: success — %@ (%d images)", container.name, container.imageCount)

        // If 0 images and it's an SMB LiveFiles path, warn the user
        if container.imageCount == 0 && FilesystemSource.isBrokenSMBPath(url) {
            filesystemSource.removeFolder(url)
            showSMBAlert = true
            return
        }

        folderContainers.append(container)
        expandedIDs.insert(container.id)
        selectedID = container.id
    }
}
