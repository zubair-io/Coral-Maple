import SwiftUI
import CoralCore

/// Detail panel Scopes tab — histogram, waveform, parade, vectorscope.
/// Only active in full-image mode; grayed out in browse mode.
struct ScopesTabView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 12) {
            if case .fullImage = viewModel.appMode {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28))
                    .foregroundStyle(JM.textMuted)
                Text("Scopes")
                    .font(JM.Font.body(.medium))
                    .foregroundStyle(JM.textMain)
                Text("Histogram, waveform, parade, and vectorscope will render here in Phase 3.")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
                    .multilineTextAlignment(.center)
            } else {
                Text("Select an image to view scopes")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted.opacity(0.6))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JM.canvas)
    }
}
