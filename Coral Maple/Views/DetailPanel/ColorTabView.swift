import SwiftUI
import CoralCore

/// Detail panel Color tab — adjustment sliders bound to EditSession.
struct ColorTabView: View {
    @Environment(EditSession.self) private var editSession

    private var isEnabled: Bool { editSession.isEditing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isEnabled {
                toneSection
                Divider().background(JM.border)
                whiteBalanceSection
                Divider().background(JM.border)
                presenceSection
                Divider().background(JM.border)
                sharpeningSection
                Divider().background(JM.border)
                noiseReductionSection
                Divider().background(JM.border)
                actionRow
            } else {
                Text("Open an image to edit")
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    // MARK: - Binding

    private var adj: Binding<AdjustmentModel> {
        Binding(
            get: { editSession.adjustments },
            set: { editSession.adjustments = $0 }
        )
    }

    // MARK: - Tone

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("TONE")
            colorSlider("Exposure", range: -4...4, step: 0.05, defaultVal: 0,
                         value: adj.exposure, colors: [.black, .gray, .white])
            colorSlider("Contrast", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.contrast, colors: [.gray, .white])
            colorSlider("Highlights", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.highlights, colors: [.gray, .white])
            colorSlider("Shadows", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.shadows, colors: [Color(hex: 0x333333), .gray])
            colorSlider("Whites", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.whites, colors: [.gray, .white])
            colorSlider("Blacks", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.blacks, colors: [.black, .gray])
        }
    }

    // MARK: - White Balance

    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("WHITE BALANCE")
                Spacer()
                // WB preset
                Menu {
                    Button("As Shot") { editSession.applyAsShotWB() }
                    Button("Daylight (5500K)") { adj.wrappedValue.temperature = 5500; adj.wrappedValue.tint = 0 }
                    Button("Cloudy (6500K)") { adj.wrappedValue.temperature = 6500; adj.wrappedValue.tint = 0 }
                    Button("Shade (7500K)") { adj.wrappedValue.temperature = 7500; adj.wrappedValue.tint = 0 }
                    Button("Tungsten (3200K)") { adj.wrappedValue.temperature = 3200; adj.wrappedValue.tint = 0 }
                    Button("Flash (5400K)") { adj.wrappedValue.temperature = 5400; adj.wrappedValue.tint = 0 }
                } label: {
                    Text("Preset")
                        .font(JM.Font.caption(.medium))
                        .foregroundStyle(JM.primary)
                }

                // Eyedropper — toggles EditSession state; tap image to sample
                Button {
                    editSession.isEyedropperActive.toggle()
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 12))
                        .foregroundStyle(editSession.isEyedropperActive ? JM.primary : JM.textMuted)
                }
                .buttonStyle(.plain)
                .help("Click, then tap a neutral gray area in the image")
            }

            colorSlider("Temp", range: 2000...12000, step: 50, defaultVal: 6500,
                         value: adj.temperature, colors: [.blue, .orange])
            colorSlider("Tint", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.tint, colors: [.green, .pink])
        }
    }

    // MARK: - Presence

    private var presenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PRESENCE")
            colorSlider("Vibrance", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.vibrance, colors: [.gray, Color(hex: 0xFF6B6B)])
            colorSlider("Saturation", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.saturation, colors: [.gray, Color(hex: 0xFF4444)])
            colorSlider("Clarity", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.clarity, colors: [.gray, .white])
            colorSlider("Texture", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.texture, colors: [.gray, .white])
            colorSlider("Dehaze", range: -100...100, step: 1, defaultVal: 0,
                         value: adj.dehaze, colors: [Color(hex: 0x8888AA), .white])
        }
    }

    // MARK: - Sharpening

    private var sharpeningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("SHARPENING")
            colorSlider("Amount", range: 0...150, step: 1, defaultVal: 0,
                         value: adj.sharpenAmount, colors: [.gray, .white])
            colorSlider("Radius", range: 0.5...3, step: 0.1, defaultVal: 1.0,
                         value: adj.sharpenRadius, colors: [.gray, .white])
            colorSlider("Detail", range: 0...100, step: 1, defaultVal: 25,
                         value: adj.sharpenDetail, colors: [.gray, .white])
            colorSlider("Masking", range: 0...100, step: 1, defaultVal: 0,
                         value: adj.sharpenMasking, colors: [.gray, .white])
        }
    }

    // MARK: - Noise Reduction

    private var noiseReductionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("NOISE REDUCTION")
            colorSlider("Luminance", range: 0...100, step: 1, defaultVal: 0,
                         value: adj.nrLuminance, colors: [.gray, .white])
            colorSlider("Color", range: 0...100, step: 1, defaultVal: 25,
                         value: adj.nrColor, colors: [.gray, .white])
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack {
            Button("Revert") { editSession.revert() }
            Spacer()
            Button("Copy") {
                _ = editSession.copyAdjustments()
            }
            Button("Paste") {
                if let copied = editSession.copiedAdjustments {
                    editSession.pasteAdjustments(copied)
                }
            }
            .disabled(editSession.copiedAdjustments == nil)
        }
        .font(JM.Font.caption(.medium))
        .foregroundStyle(JM.textMuted)
        .buttonStyle(.plain)
    }

    // MARK: - Colored slider with default snap

    private func colorSlider(
        _ name: String,
        range: ClosedRange<Double>,
        step: Double,
        defaultVal: Double,
        value: Binding<Double>,
        colors: [Color]
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(name)
                    .font(JM.Font.caption())
                    .foregroundStyle(JM.textMain)
                Spacer()
                Text(formatValue(value.wrappedValue, step: step))
                    .font(JM.Font.caption(.medium))
                    .foregroundStyle(JM.textMain)
                    .monospacedDigit()
            }
            // Colored gradient track with slider
            ZStack(alignment: .leading) {
                // Gradient track background
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 4)
                    .clipShape(Capsule())
                    .opacity(0.6)

                // Slider
                Slider(value: value, in: range, step: step)
                    .tint(.clear) // hide default tint, we show gradient
                    .accessibilityLabel(name)
            }
            // Double-tap to reset to default
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    value.wrappedValue = defaultVal
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(JM.Font.sectionHeader)
            .tracking(0.6)
            .foregroundStyle(JM.textMuted)
    }

    private func formatValue(_ value: Double, step: Double) -> String {
        if step >= 1 { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}
