import Foundation

/// Every adjustment field the app supports. Value type — cheap to copy, compare, serialize.
/// Fields use CRS (Camera Raw Settings) naming where an Adobe equivalent exists.
///
/// Default values are the "identity" state — applying an adjustment model where every field
/// is default produces an image identical to the original.
public struct AdjustmentModel: Sendable, Equatable, Codable, Hashable {

    // MARK: Culling

    public var culling: CullingState

    // MARK: Tone

    /// Exposure in EV, −4…+4, default 0.
    public var exposure: Double
    /// Contrast, −100…+100, default 0.
    public var contrast: Double
    /// Highlights, −100…+100, default 0.
    public var highlights: Double
    /// Shadows, −100…+100, default 0.
    public var shadows: Double
    /// Whites, −100…+100, default 0.
    public var whites: Double
    /// Blacks, −100…+100, default 0.
    public var blacks: Double

    // MARK: White Balance

    /// Color temperature in Kelvin, 2000…12000, default 6500 (daylight).
    public var temperature: Double
    /// Tint, −100…+100, default 0.
    public var tint: Double

    // MARK: Presence

    /// Vibrance, −100…+100, default 0.
    public var vibrance: Double
    /// Saturation, −100…+100, default 0.
    public var saturation: Double
    /// Clarity, −100…+100, default 0.
    public var clarity: Double
    /// Texture, −100…+100, default 0.
    public var texture: Double
    /// Dehaze, −100…+100, default 0.
    public var dehaze: Double

    // MARK: Sharpening

    public var sharpenAmount: Double  // 0…150, default 0
    public var sharpenRadius: Double  // 0.5…3.0, default 1.0
    public var sharpenDetail: Double  // 0…100, default 25
    public var sharpenMasking: Double // 0…100, default 0

    // MARK: Noise Reduction

    public var nrLuminance: Double // 0…100, default 0
    public var nrColor: Double     // 0…100, default 25

    // MARK: Passthrough

    /// Unknown namespace fields encountered during XMP parse.
    /// Preserved on round-trip so we don't destroy data from other tools.
    public var passthroughFields: [String: String]

    // MARK: Init

    public init(
        culling: CullingState = CullingState(),
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        temperature: Double = 6500,
        tint: Double = 0,
        vibrance: Double = 0,
        saturation: Double = 0,
        clarity: Double = 0,
        texture: Double = 0,
        dehaze: Double = 0,
        sharpenAmount: Double = 0,
        sharpenRadius: Double = 1.0,
        sharpenDetail: Double = 25,
        sharpenMasking: Double = 0,
        nrLuminance: Double = 0,
        nrColor: Double = 25,
        passthroughFields: [String: String] = [:]
    ) {
        self.culling = culling
        self.exposure = Self.clamp(exposure, -4...4)
        self.contrast = Self.clamp(contrast, -100...100)
        self.highlights = Self.clamp(highlights, -100...100)
        self.shadows = Self.clamp(shadows, -100...100)
        self.whites = Self.clamp(whites, -100...100)
        self.blacks = Self.clamp(blacks, -100...100)
        self.temperature = Self.clamp(temperature, 2000...12000)
        self.tint = Self.clamp(tint, -100...100)
        self.vibrance = Self.clamp(vibrance, -100...100)
        self.saturation = Self.clamp(saturation, -100...100)
        self.clarity = Self.clamp(clarity, -100...100)
        self.texture = Self.clamp(texture, -100...100)
        self.dehaze = Self.clamp(dehaze, -100...100)
        self.sharpenAmount = Self.clamp(sharpenAmount, 0...150)
        self.sharpenRadius = Self.clamp(sharpenRadius, 0.5...3.0)
        self.sharpenDetail = Self.clamp(sharpenDetail, 0...100)
        self.sharpenMasking = Self.clamp(sharpenMasking, 0...100)
        self.nrLuminance = Self.clamp(nrLuminance, 0...100)
        self.nrColor = Self.clamp(nrColor, 0...100)
        self.passthroughFields = passthroughFields
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// True when every adjustment is at its default (identity) value.
    /// When true, no sidecar file is needed unless culling state is non-default.
    public var isDefault: Bool {
        self == AdjustmentModel()
    }

    /// True when only culling fields have been set (no image adjustments).
    public var hasImageAdjustments: Bool {
        var copy = self
        copy.culling = CullingState()
        copy.passthroughFields = [:]
        return copy != AdjustmentModel()
    }
}
