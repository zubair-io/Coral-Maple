import Foundation
import CoralCore

/// Assertion helpers for XMP round-trip testing.
public enum XMPTestHelpers {

    /// Assert that serialized XMP data contains a specific key=value attribute.
    public static func assertXMPContains(data: Data, key: String, value: String) -> Bool {
        guard let xml = String(data: data, encoding: .utf8) else { return false }
        return xml.contains("\(key)=\"\(value)\"")
    }

    /// Round-trip an AdjustmentModel through serialize → parse and check equality.
    public static func assertXMPRoundTrip(_ model: AdjustmentModel) -> Bool {
        let serializer = XMPSerializer()
        let parser = XMPParser()
        let data = serializer.serialize(model)
        guard let parsed = try? parser.parse(data: data) else { return false }
        return model == parsed
    }
}
