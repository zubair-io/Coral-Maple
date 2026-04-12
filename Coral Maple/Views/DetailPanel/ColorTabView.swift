import SwiftUI
import CoralCore

/// Detail panel Color tab — all adjustment sliders.
/// In Phase 1 the sliders are present but disabled (no pipeline yet).
struct ColorTabView: View {
    @Environment(UnifiedLibraryViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.selectedAsset != nil {
                toneSection
                Divider().background(JM.border)
                presenceSection
                Divider().background(JM.border)
                whiteBalanceSection
                Divider().background(JM.border)
                sharpeningSection
                Divider().background(JM.border)
                noiseReductionSection
                Divider().background(JM.border)
                actionRow
            } else {
                Text("Select an image")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    // MARK: - Sections

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("TONE")
            adjustSlider("Exposure", range: -4...4, step: 0.05, value: 0, enabled: false)
            adjustSlider("Contrast", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Highlights", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Shadows", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Whites", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Blacks", range: -100...100, step: 1, value: 0, enabled: false)
        }
    }

    private var presenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PRESENCE")
            adjustSlider("Clarity", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Texture", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Dehaze", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Vibrance", range: -100...100, step: 1, value: 0, enabled: false)
            adjustSlider("Saturation", range: -100...100, step: 1, value: 0, enabled: false)
        }
    }

    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("WHITE BALANCE")
            adjustSlider("Temperature", range: 2000...12000, step: 50, value: 6500, enabled: false)
            adjustSlider("Tint", range: -100...100, step: 1, value: 0, enabled: false)
        }
    }

    private var sharpeningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("SHARPENING")
            adjustSlider("Amount", range: 0...150, step: 1, value: 0, enabled: false)
            adjustSlider("Radius", range: 0.5...3, step: 0.1, value: 1.0, enabled: false)
            adjustSlider("Detail", range: 0...100, step: 1, value: 25, enabled: false)
            adjustSlider("Masking", range: 0...100, step: 1, value: 0, enabled: false)
        }
    }

    private var noiseReductionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("NOISE REDUCTION")
            adjustSlider("Luminance", range: 0...100, step: 1, value: 0, enabled: false)
            adjustSlider("Color", range: 0...100, step: 1, value: 25, enabled: false)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Revert") {}
                .disabled(true)
            Spacer()
            Button("Copy") {}
                .disabled(true)
            Button("Paste") {}
                .disabled(true)
        }
        .font(JM.Font.caption(.medium))
        .foregroundStyle(JM.textMuted)
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(JM.Font.sectionHeader)
            .tracking(0.6)
            .foregroundStyle(JM.textMuted)
    }

    private func adjustSlider(_ name: String, range: ClosedRange<Double>, step: Double, value: Double, enabled: Bool) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(name)
                    .font(JM.Font.caption())
                    .foregroundStyle(enabled ? JM.textMain : JM.textMuted)
                Spacer()
                Text(formatValue(value, step: step))
                    .font(JM.Font.caption(.medium))
                    .foregroundStyle(JM.textMain)
                    .monospacedDigit()
            }
            Slider(value: .constant(value), in: range, step: step)
                .tint(JM.primary)
                .disabled(!enabled)
                .accessibilityLabel(name)
        }
    }

    private func formatValue(_ value: Double, step: Double) -> String {
        if step >= 1 { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
