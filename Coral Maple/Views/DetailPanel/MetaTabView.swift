import SwiftUI
import CoralCore

/// Detail panel Meta tab — location, dates, IPTC, edit history.
struct MetaTabView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @State private var metadata: ImageMetadata?
    @State private var isLoadingMeta = false
    @State private var metadataLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.selectedAsset != nil {
                locationSection
                Divider().background(JM.border)
                datesSection
                Divider().background(JM.border)
                iptcSection
            } else {
                noSelectionView
            }
        }
        .padding(12)
        .onChange(of: viewModel.selectedAsset?.id) { _, _ in
            loadMetadata()
        }
        .onAppear { loadMetadata() }
    }

    // MARK: - Location section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("LOCATION")

            if let lat = metadata?.latitude, let lon = metadata?.longitude {
                infoRow("Latitude", String(format: "%.6f", lat))
                infoRow("Longitude", String(format: "%.6f", lon))
            } else {
                Text("No GPS data")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
            }
        }
    }

    // MARK: - Dates section

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("DATES")

            if let date = metadata?.dateTaken {
                infoRow("Date Taken", date)
            }
            if let date = metadata?.dateModified {
                infoRow("Date Modified", date)
            }
            if metadata?.dateTaken == nil && metadata?.dateModified == nil {
                Text("No date information")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
            }
        }
    }

    // MARK: - IPTC section

    private var iptcSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("IPTC")

            if let meta = metadata {
                if let title = meta.title {
                    infoRow("Title", title)
                }
                if let caption = meta.caption {
                    infoRow("Caption", caption)
                }
                if let copyright = meta.copyright {
                    infoRow("Copyright", copyright)
                }
                if let creator = meta.creator {
                    infoRow("Creator", creator)
                }
                if let keywords = meta.keywords, !keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keywords")
                            .font(JM.Font.caption())
                            .foregroundStyle(JM.textMuted)
                        FlowLayout(spacing: 4) {
                            ForEach(keywords, id: \.self) { kw in
                                Text(kw)
                                    .font(JM.Font.caption(.medium))
                                    .foregroundStyle(JM.textMain)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(JM.surfaceAlt)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                if meta.title == nil && meta.caption == nil && meta.copyright == nil && (meta.keywords?.isEmpty ?? true) {
                    Text("No IPTC data")
                        .font(JM.Font.caption())
                        .foregroundStyle(JM.textMuted)
                }
            }
        }
    }

    // MARK: - Load metadata

    private func loadMetadata() {
        metadataLoadTask?.cancel()
        guard let asset = viewModel.selectedAsset,
              let source = viewModel.activeSource else {
            metadata = nil
            return
        }

        isLoadingMeta = true
        metadata = nil

        metadataLoadTask = Task {
            do {
                let meta: ImageMetadata
                if let fileURL = asset.fileURL {
                    meta = ImageMetadata.from(url: fileURL)
                } else {
                    let data = try await source.metadataData(for: asset)
                    meta = ImageMetadata.from(data: data)
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    metadata = meta
                    isLoadingMeta = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    metadata = ImageMetadata()
                    isLoadingMeta = false
                }
            }
        }
    }

    // MARK: - Helpers

    private var noSelectionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(JM.textMuted)
            Text("Select an image to see metadata")
                .font(JM.Font.caption())
                .foregroundStyle(JM.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(JM.Font.sectionHeader)
            .tracking(0.6)
            .foregroundStyle(JM.textMuted)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(JM.Font.caption())
                .foregroundStyle(JM.textMuted)
            Spacer()
            Text(value)
                .font(JM.Font.caption(.medium))
                .foregroundStyle(JM.textMain)
                .lineLimit(1)
        }
    }
}
