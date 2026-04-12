import SwiftUI
import CoralCore

/// Pick / Unflagged / Reject tappable pills.
struct FlagPillsView: View {
    let flag: Flag
    let onToggle: (Flag) -> Void

    var body: some View {
        HStack(spacing: 8) {
            flagPill("Pick", icon: "flag.fill", value: .pick, activeBg: JM.successBg, activeText: JM.successText)
            flagPill("Unflag", icon: "minus", value: .unflagged, activeBg: JM.bgActive, activeText: JM.textMain)
            flagPill("Reject", icon: "xmark", value: .reject, activeBg: JM.errorBg, activeText: JM.errorText)
        }
    }

    private func flagPill(_ label: String, icon: String, value: Flag, activeBg: Color, activeText: Color) -> some View {
        let isActive = flag == value
        return Button {
            onToggle(value)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(JM.Font.caption(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? activeBg : JM.surfaceAlt)
            .foregroundStyle(isActive ? activeText : JM.textMuted)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) flag")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
