import SwiftUI
import CoralCore

/// Toolbar for full-image mode — back, filename, export.
struct FullImageToolbarView: ToolbarContent {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @Binding var showExportSheet: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                viewModel.exitFullImage()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(JM.Font.body(.medium))
            }
            .accessibilityLabel("Return to browse")
        }

        ToolbarItem(placement: .principal) {
            if let asset = viewModel.selectedAsset {
                Text(asset.filename)
                    .font(JM.Font.body(.medium))
                    .foregroundStyle(JM.textMain)
                    .padding(.horizontal, 16)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
            }
            .accessibilityLabel("Export")
        }
    }
}
