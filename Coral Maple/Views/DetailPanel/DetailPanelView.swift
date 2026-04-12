import SwiftUI
import CoralCore

/// Detail panel tabs.
enum DetailTab: String, CaseIterable {
    case info   = "Info"
    case color  = "Color"
    case meta   = "Meta"
    case scopes = "Scopes"

    var icon: String {
        switch self {
        case .info:   return "info.circle"
        case .color:  return "slider.horizontal.3"
        case .meta:   return "doc.text"
        case .scopes: return "waveform.path.ecg"
        }
    }
}

/// Right panel — content switches based on the active bottom tab.
struct DetailPanelView: View {
    @Binding var selectedTab: DetailTab
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            ScrollView {
                switch selectedTab {
                case .info:
                    InfoTabView()
                case .color:
                    ColorTabView()
                case .meta:
                    MetaTabView()
                case .scopes:
                    ScopesTabView()
                }
            }

            Divider()
                .background(JM.border)

            // Bottom tab bar
            tabBar
        }
        .background(JM.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                let isActive = selectedTab == tab
                let isDisabled = tab == .scopes && viewModel.appMode == .browse

                Button {
                    if !isDisabled { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(isActive ? JM.primary : .clear)
                            .frame(height: 2)
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.rawValue)
                            .font(JM.Font.caption(.medium))
                    }
                    .foregroundStyle(
                        isDisabled ? JM.textMuted.opacity(0.4) :
                            isActive ? JM.textMain : JM.textMuted
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isActive ? JM.surface : JM.surfaceAlt)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }
}
