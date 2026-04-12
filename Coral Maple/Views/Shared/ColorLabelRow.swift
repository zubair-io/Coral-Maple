import SwiftUI
import CoralCore

/// Row of colored dots for color labels. Tap to toggle; tap active to clear.
struct ColorLabelRow: View {
    let activeLabel: ColorLabel?
    let onToggle: (ColorLabel) -> Void

    private static let labels: [(ColorLabel, Color)] = [
        (.red, .red),
        (.orange, .orange),
        (.yellow, .yellow),
        (.green, .green),
        (.blue, .blue),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.labels, id: \.0) { label, color in
                Circle()
                    .fill(color)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if activeLabel == label {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture {
                        onToggle(label)
                    }
                    .accessibilityLabel("\(label.rawValue) label")
                    .accessibilityAddTraits(activeLabel == label ? .isSelected : [])
            }
        }
    }
}
