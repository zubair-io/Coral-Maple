import SwiftUI

// MARK: - Just Maple Dark Theme

/// Central source for all Just Maple design tokens.
/// Pull colors and typography from here — never hardcode hex values in views.
enum JM {

    // MARK: Surfaces

    static let bg            = Color(hex: 0x1C1917) // root / page background
    static let surface       = Color(hex: 0x262524) // panels, detail pane
    static let surfaceAlt    = Color(hex: 0x2E2C2A) // tab bar, grouped bg
    static let surfaceHover  = Color(hex: 0x3A3836) // hover state
    static let sidebar       = Color(hex: 0x292524) // left nav panel
    static let inputBg       = Color(hex: 0x1C1917) // text inputs, range tracks
    static let canvas        = Color(hex: 0x141210) // image canvas / scopes bg

    // MARK: Text

    static let textMain  = Color(hex: 0xE7E5E4)
    static let textMuted = Color(hex: 0xA8A29E)

    // MARK: Borders

    static let border = Color(hex: 0x44403C)

    // MARK: Accent

    static let primary      = Color(hex: 0xC4493A) // maple red
    static let primaryLight = Color(hex: 0x422016) // selected nav item fill

    // MARK: Semantic

    static let successBg   = Color(.sRGB, red: 34/255, green: 197/255, blue: 94/255, opacity: 0.15)
    static let successText = Color(hex: 0x4ADE80)
    static let errorBg     = Color(.sRGB, red: 239/255, green: 68/255, blue: 68/255, opacity: 0.15)
    static let errorText   = Color(hex: 0xF87171)
    static let star        = Color(hex: 0xEF9F27)

    // MARK: Interactive overlays

    static let bgHover  = Color.white.opacity(0.06)
    static let bgActive = Color.white.opacity(0.10)

    // MARK: Typography helpers

    enum Font {
        static func body(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: 13, weight: weight, design: .default)
        }

        static func caption(_ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: 11, weight: weight, design: .default)
        }

        static var sectionHeader: SwiftUI.Font {
            .system(size: 10, weight: .medium, design: .default)
        }
    }
}

// MARK: - Color hex initializer

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
