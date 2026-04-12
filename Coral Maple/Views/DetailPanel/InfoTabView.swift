import SwiftUI
import UniformTypeIdentifiers
import CoralCore

/// Detail panel Info tab — file info, camera info, rating/flags/labels.
struct InfoTabView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let asset = viewModel.selectedAsset {
                fileSection(asset)
                Divider().background(JM.border)
                cameraSection(asset)
                Divider().background(JM.border)
                cullingSection(asset)
            } else {
                noSelectionView
            }
        }
        .padding(12)
    }

    // MARK: - File section

    private func fileSection(_ asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("FILE")

            infoRow("Name", asset.filename)

            if asset.pixelWidth > 0 && asset.pixelHeight > 0 {
                infoRow("Dimensions", "\(asset.pixelWidth) × \(asset.pixelHeight)")
            }

            if let type = asset.uniformType {
                infoRow("Format", type.localizedDescription ?? type.identifier)
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
                    .overlay(Capsule().stroke(JM.primary.opacity(0.3), lineWidth: 1))
                } else {
                    Text("No sidecar")
                        .font(JM.Font.caption())
                        .foregroundStyle(JM.textMuted)
                }
            }
        }
    }

    // MARK: - Camera section

    private func cameraSection(_ asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("CAMERA")
            Text("EXIF data will appear here")
                .font(JM.Font.caption())
                .foregroundStyle(JM.textMuted)
        }
    }

    // MARK: - Culling section

    private func cullingSection(_ asset: ImageAsset) -> some View {
        let culling = viewModel.selectedCulling ?? CullingState()

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("RATING & FLAGS")

            FlagPillsView(flag: culling.flag) { flag in
                Task {
                    await viewModel.toggleFlag(flag, for: asset.id)
                }
            }

            RatingView(rating: culling.rating) { rating in
                Task {
                    await viewModel.setRating(rating, for: asset.id)
                }
            }

            ColorLabelRow(activeLabel: culling.colorLabel) { label in
                Task {
                    await viewModel.toggleLabel(label, for: asset.id)
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
