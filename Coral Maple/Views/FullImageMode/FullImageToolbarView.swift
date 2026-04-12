import SwiftUI
import CoralCore

/// Toolbar for full-image mode — back, filename, zoom, flags, export.
struct FullImageToolbarView: ToolbarContent {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

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
            }
        }
    }
}
