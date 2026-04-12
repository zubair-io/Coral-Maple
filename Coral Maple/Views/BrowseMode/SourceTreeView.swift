import SwiftUI
import UniformTypeIdentifiers
import CoralCore

struct SourceTreeView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    let filesystemSource: FilesystemSource
    let photoKitSource: PhotoKitSource

    @State private var photoContainers: [SourceContainer] = []
    @State private var folderContainers: [SourceContainer] = []
    @State private var isAddingFolder = false
    @State private var selectedID: String?
    @State private var expandedIDs: Set<String> = ["__section_favorites", "__section_folders", "__section_photos", "__section_smb"]

    // SMB
    @State private var smbConfigs: [SMBServerConfig] = []
    @State private var smbSources: [String: SMBSource] = [:]
    @State private var smbContainers: [String: [SourceContainer]] = [:]
    @State private var smbSubfolders: [String: [SourceContainer]] = [:] // keyed by container.id
    @State private var isAddingSMB = false

    // Favorites
    @State private var favorites: [FavoriteFolder] = []

    var body: some View {
        List(selection: $selectedID) {
            // --- Favorites ---
            if !favorites.isEmpty {
                Section {
                    if expandedIDs.contains("__section_favorites") {
                        ForEach(favorites) { fav in
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(JM.star)
                                Text(fav.name)
                                    .font(JM.Font.body(.regular))
                                    .lineLimit(1)
                            }
                            .tag(fav.id)
                            .contextMenu {
                                Button("Remove from Favorites") {
                                    removeFavorite(id: fav.id)
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        sectionChevron(id: "__section_favorites")
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("FAVORITES")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSection("__section_favorites") }
                }
            }

            // --- Local Folders ---
            Section {
                if expandedIDs.contains("__section_folders") {
                    if folderContainers.isEmpty {
                        Text("No folders added")
                            .font(JM.Font.caption())
                            .foregroundStyle(JM.textMuted)
                    } else {
                        ForEach(visibleFolderEntries, id: \.container.id) { entry in
                            folderRow(entry: entry)
                                .tag(entry.container.id)
                                .contextMenu { favoriteMenuItems(id: entry.container.id, name: entry.container.name, source: "filesystem") }
                        }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    sectionChevron(id: "__section_folders")
                    Image(systemName: "folder").font(.system(size: 10))
                    Text("FOLDERS")
                    Spacer()
                    Button { isAddingFolder = true } label: {
                        Image(systemName: "plus").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleSection("__section_folders") }
            }

            // --- SMB Servers ---
            Section {
                if expandedIDs.contains("__section_smb") {
                    if smbConfigs.isEmpty {
                        Text("No servers")
                            .font(JM.Font.caption())
                            .foregroundStyle(JM.textMuted)
                    } else {
                        ForEach(smbConfigs) { config in
                            smbServerRows(config: config)
                        }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    sectionChevron(id: "__section_smb")
                    Image(systemName: "network").font(.system(size: 10))
                    Text("NETWORK")
                    Spacer()
                    Button { isAddingSMB = true } label: {
                        Image(systemName: "plus").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleSection("__section_smb") }
            }

            // --- Photos Library ---
            Section {
                if expandedIDs.contains("__section_photos") {
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
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 10))
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
        .task { await loadSources() }
        .onChange(of: selectedID) { _, newValue in
            guard let id = newValue else { return }
            loadContainer(id: id)
        }
        #if os(macOS)
        .fileImporter(isPresented: $isAddingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { addFolder(url) }
        }
        #else
        .sheet(isPresented: $isAddingFolder) {
            FolderPicker { url in isAddingFolder = false; addFolder(url) }
        }
        #endif
        .sheet(isPresented: $isAddingSMB) {
            SMBConnectView { config, password in addSMBServer(config: config, password: password) }
        }
    }

    // MARK: - SMB server rows with expandable subfolders

    @ViewBuilder
    private func smbServerRows(config: SMBServerConfig) -> some View {
        let isExpanded = expandedIDs.contains(config.id)
        let topContainers = smbContainers[config.id] ?? []

        // Server header
        HStack(spacing: 4) {
            Button { toggleSection(config.id) } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(JM.textMuted)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 11))
                .foregroundStyle(JM.textMuted)
            Text(config.displayName)
                .font(JM.Font.body(.medium))
                .lineLimit(1)
            Spacer()
            Button { removeSMBServer(config: config) } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(JM.textMuted)
            }
            .buttonStyle(.plain)
        }

        if isExpanded {
            if topContainers.isEmpty {
                Text("Loading...")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
                    .padding(.leading, 30)
                    .task { await loadSMBContainers(config: config) }
            } else {
                ForEach(flattenSMBTree(configID: config.id, containers: topContainers, depth: 0), id: \.container.id) { entry in
                    smbFolderRow(configID: config.id, entry: entry)
                        .tag(entry.container.id)
                        .contextMenu { favoriteMenuItems(id: entry.container.id, name: entry.container.name, source: "smb") }
                }
            }
        }
    }

    private func smbFolderRow(configID: String, entry: FolderEntry) -> some View {
        HStack(spacing: 4) {
            // Expand chevron — always shown for SMB folders since we don't know if they have children
            Button {
                if expandedIDs.contains(entry.container.id) {
                    expandedIDs.remove(entry.container.id)
                } else {
                    expandedIDs.insert(entry.container.id)
                    // Load subfolders on expand
                    if smbSubfolders[entry.container.id] == nil {
                        Task { await loadSMBSubfolders(configID: configID, container: entry.container) }
                    }
                }
            } label: {
                Image(systemName: expandedIDs.contains(entry.container.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(JM.textMuted)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(JM.textMuted)
            Text(entry.container.name)
                .font(JM.Font.body(.regular))
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, CGFloat(entry.depth) * 16 + 16)
    }

    private func flattenSMBTree(configID: String, containers: [SourceContainer], depth: Int) -> [FolderEntry] {
        var result: [FolderEntry] = []
        for c in containers {
            result.append(FolderEntry(container: c, depth: depth))
            if expandedIDs.contains(c.id), let subs = smbSubfolders[c.id] {
                result.append(contentsOf: flattenSMBTree(configID: configID, containers: subs, depth: depth + 1))
            }
        }
        return result
    }

    // MARK: - Favorites

    @ViewBuilder
    private func favoriteMenuItems(id: String, name: String, source: String) -> some View {
        if FavoriteFolderStore.isFavorite(id: id) {
            Button("Remove from Favorites") { removeFavorite(id: id) }
        } else {
            Button("Add to Favorites") { addFavorite(id: id, name: name, source: source) }
        }
    }

    private func addFavorite(id: String, name: String, source: String) {
        let fav = FavoriteFolder(id: id, name: name, sourceType: source)
        FavoriteFolderStore.add(fav)
        favorites = FavoriteFolderStore.loadAll()
    }

    private func removeFavorite(id: String) {
        FavoriteFolderStore.remove(id: id)
        favorites = FavoriteFolderStore.loadAll()
    }

    // MARK: - Helpers

    private func sectionChevron(id: String) -> some View {
        Image(systemName: expandedIDs.contains(id) ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(JM.textMuted)
            .frame(width: 10)
    }

    private func toggleSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expandedIDs.contains(id) { expandedIDs.remove(id) }
            else { expandedIDs.insert(id) }
        }
    }

    private struct FolderEntry {
        let container: SourceContainer
        let depth: Int
    }

    private func folderRow(entry: FolderEntry) -> some View {
        HStack(spacing: 4) {
            if !entry.container.children.isEmpty {
                Button { toggleSection(entry.container.id) } label: {
                    Image(systemName: expandedIDs.contains(entry.container.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(JM.textMuted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }
            Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(JM.textMuted)
            Text(entry.container.name).font(JM.Font.body(.regular)).lineLimit(1)
            Spacer()
            if entry.container.imageCount > 0 {
                Text("\(entry.container.imageCount)").font(JM.Font.caption()).foregroundStyle(JM.textMuted)
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 16)
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

    private func iconForPhotoContainer(_ container: SourceContainer) -> String {
        if container.name == "All Photos" { return "photo.on.rectangle.angled" }
        if container.name == "Favorites" { return "heart" }
        return "rectangle.stack"
    }

    // MARK: - Actions

    private func loadContainer(id: String) {
        // PhotoKit
        if id.hasPrefix("photokit://") {
            let name = (id as NSString).lastPathComponent
            let container = photoContainers.first(where: { $0.id == id })
                ?? SourceContainer(id: id, name: name, children: [], imageCount: 0)
            Task { await viewModel.loadAssets(from: container, source: photoKitSource) }
            return
        }

        // SMB — any smb:// ID
        if id.hasPrefix("smb://") {
            for (configID, source) in smbSources {
                let config = smbConfigs.first { $0.id == configID }
                let prefix = "smb://\(config?.host ?? ""):\(config?.port ?? 445)/\(config?.share ?? "")"
                if id.hasPrefix(prefix) {
                    let name = (id as NSString).lastPathComponent
                    let container = SourceContainer(id: id, name: name, children: [], imageCount: 0)
                    Task { await viewModel.loadAssets(from: container, source: source) }
                    return
                }
            }
            return
        }

        // Local filesystem — try tree first, fall back to creating container from ID
        if let c = findContainer(id: id, in: folderContainers) {
            Task { await viewModel.loadAssets(from: c, source: filesystemSource) }
        } else if id.hasPrefix("file://") {
            // Subfolder not in tree (e.g. from favorites) — create container from ID
            let name = URL(string: id)?.lastPathComponent ?? "Folder"
            let container = SourceContainer(id: id, name: name, children: [], imageCount: 0)
            Task { await viewModel.loadAssets(from: container, source: filesystemSource) }
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
        favorites = FavoriteFolderStore.loadAll()
        do { photoContainers = try await photoKitSource.rootContainers() } catch { photoContainers = [] }
        do {
            folderContainers = try await filesystemSource.rootContainers()
            for c in folderContainers { expandedIDs.insert(c.id) }
        } catch { folderContainers = [] }
        smbConfigs = SMBConfigStore.loadAll()
        for config in smbConfigs {
            if let pw = SMBConfigStore.loadPassword(for: config.id) {
                smbSources[config.id] = SMBSource(config: config, password: pw)
                expandedIDs.insert(config.id)
            }
        }
    }

    private func loadSMBContainers(config: SMBServerConfig) async {
        guard let source = smbSources[config.id] else { return }
        do {
            smbContainers[config.id] = try await source.rootContainers()
        } catch {
            NSLog("[CoralMaple] SMB loadContainers failed: %@", "\(error)")
            smbContainers[config.id] = []
        }
    }

    private func loadSMBSubfolders(configID: String, container: SourceContainer) async {
        guard let source = smbSources[configID] else { return }
        do {
            smbSubfolders[container.id] = try await source.subfolders(in: container)
        } catch {
            NSLog("[CoralMaple] SMB subfolders failed for %@: %@", container.name, "\(error)")
            smbSubfolders[container.id] = []
        }
    }

    private func addSMBServer(config: SMBServerConfig, password: String) {
        if !smbConfigs.contains(where: { $0.id == config.id }) { smbConfigs.append(config) }
        smbSources[config.id] = SMBSource(config: config, password: password)
        expandedIDs.insert(config.id)
    }

    private func removeSMBServer(config: SMBServerConfig) {
        Task { await smbSources[config.id]?.disconnect() }
        smbSources.removeValue(forKey: config.id)
        smbContainers.removeValue(forKey: config.id)
        smbConfigs.removeAll { $0.id == config.id }
        SMBConfigStore.remove(id: config.id)
    }

    private func addFolder(_ url: URL) {
        guard let container = try? filesystemSource.addFolder(url) else { return }
        folderContainers.append(container)
        expandedIDs.insert(container.id)
        selectedID = container.id
    }
}
