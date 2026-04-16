import SwiftUI
import UniformTypeIdentifiers
import CoralCore

/// Combined Info + Meta tab — file info, camera EXIF, location, IPTC, rating/flags.
struct InfoTabView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @State private var metadata: ImageMetadata?
    @State private var isLoadingMeta = false
    @State private var metadataLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let asset = viewModel.selectedAsset {
                fileSection(asset)
                Divider().background(JM.border)
                cullingSection(asset)
                Divider().background(JM.border)
                cameraSection
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

    // MARK: - File section

    private func fileSection(_ asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("FILE")

            infoRow("Name", asset.filename)

            if let w = metadata?.pixelWidth, let h = metadata?.pixelHeight, w > 0, h > 0 {
                infoRow("Dimensions", "\(w) × \(h)")
                let mp = Double(w * h) / 1_000_000
                infoRow("Megapixels", String(format: "%.1f MP", mp))
            } else if asset.pixelWidth > 0 {
                infoRow("Dimensions", "\(asset.pixelWidth) × \(asset.pixelHeight)")
            }

            if let type = asset.uniformType {
                infoRow("Format", type.localizedDescription ?? type.identifier)
            }

            if let depth = metadata?.bitDepth {
                infoRow("Bit Depth", "\(depth)-bit")
            }

            if let cs = metadata?.colorSpace {
                infoRow("Color Space", cs)
            }

            // Sidecar badge
            HStack(spacing: 6) {
                Text("Sidecar")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
                Spacer()
                if let culling = viewModel.selectedCulling, culling != CullingState() {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(".xmp")
                            .font(JM.Font.caption(.medium))
                    }
                    .foregroundStyle(JM.successText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(JM.successBg)
                    .clipShape(Capsule())
                } else {
                    Text("No sidecar")
                        .font(JM.Font.caption())
                        .foregroundStyle(JM.textMuted)
                }
            }
        }
    }

    // MARK: - Culling section

    private func cullingSection(_ asset: ImageAsset) -> some View {
        let culling = viewModel.selectedCulling ?? CullingState()

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("RATING & FLAGS")

            FlagPillsView(flag: culling.flag) { flag in
                Task { await viewModel.toggleFlag(flag, for: asset.id) }
            }

            RatingView(rating: culling.rating) { rating in
                Task { await viewModel.setRating(rating, for: asset.id) }
            }

            ColorLabelRow(activeLabel: culling.colorLabel) { label in
                Task { await viewModel.toggleLabel(label, for: asset.id) }
            }
        }
    }

    // MARK: - Camera section

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("CAMERA")

            if isLoadingMeta {
                Text("Loading...")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
            } else if let meta = metadata {
                if let model = meta.cameraModel {
                    infoRow("Camera", model)
                }
                if let make = meta.cameraMake, meta.cameraModel == nil {
                    infoRow("Make", make)
                }
                if let lens = meta.lens {
                    infoRow("Lens", lens)
                }
                if let fl = meta.focalLength {
                    infoRow("Focal Length", fl)
                }
                if let ap = meta.aperture {
                    infoRow("Aperture", ap)
                }
                if let ss = meta.shutterSpeed {
                    infoRow("Shutter", ss)
                }
                if let iso = meta.iso {
                    infoRow("ISO", iso)
                }
                if let flash = meta.flash {
                    infoRow("Flash", flash)
                }
                if let date = meta.dateTaken {
                    infoRow("Date Taken", date)
                }

                if meta.cameraModel == nil && meta.lens == nil && meta.aperture == nil {
                    Text("No EXIF data")
                        .font(JM.Font.caption())
                        .foregroundStyle(JM.textMuted)
                }
            } else {
                Text("No metadata")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
            }
        }
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
                    // Local file — read directly (fastest)
                    meta = ImageMetadata.from(url: fileURL)
                } else {
                    // SMB / PhotoKit — download header data for metadata extraction
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
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(JM.textMuted)
            Text("Select an image to see details")
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

// MARK: - Simple flow layout for keyword tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
