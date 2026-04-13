import Foundation

// MARK: - Flag

public enum Flag: String, Sendable, Codable, Hashable, CaseIterable {
    case pick
    case reject
    case unflagged
}

// MARK: - ColorLabel

public enum ColorLabel: String, Sendable, Codable, Hashable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
}

// MARK: - CullingState

/// Rating, flag, and color label for an image. Persisted to XMP via `xmp:Rating`,
/// `papp:Flag`, and `papp:ColorLabel`.
public struct CullingState: Sendable, Equatable, Codable, Hashable {
    /// 0 = unrated, 1–5 = star rating. Clamped on init.
    public private(set) var rating: Int
    public var flag: Flag
    public var colorLabel: ColorLabel?

    public init(rating: Int = 0, flag: Flag = .unflagged, colorLabel: ColorLabel? = nil) {
        self.rating = min(max(rating, 0), 5)
        self.flag = flag
        self.colorLabel = colorLabel
    }

    /// Set rating, clamped to 0–5.
    public mutating func setRating(_ value: Int) {
        rating = min(max(value, 0), 5)
    }

    /// Toggle a flag: if the flag is already active, reset to `.unflagged`.
    public mutating func toggleFlag(_ value: Flag) {
        flag = (flag == value) ? .unflagged : value
    }

    /// Set a color label. Setting the same label again clears it (mutually exclusive toggle).
    public mutating func toggleLabel(_ value: ColorLabel) {
        colorLabel = (colorLabel == value) ? nil : value
    }
}
