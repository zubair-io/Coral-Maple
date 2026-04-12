import SwiftUI

/// Detail panel Meta tab — location, dates, IPTC, snapshots.
/// Stub for Phase 1.
struct MetaTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(JM.textMuted)
            Text("Metadata")
                .font(JM.Font.body(.medium))
                .foregroundStyle(JM.textMain)
            Text("Location, dates, IPTC fields, and edit snapshots will appear here.")
                .font(JM.Font.caption())
                .foregroundStyle(JM.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
