import Foundation

/// Serializes an `AdjustmentModel` to XMP XML data.
///
/// Output uses the standard xpacket envelope, `crs:` namespace for Adobe Camera Raw
/// compatible fields, `xmp:` for rating, and `papp:` for app-specific data.
/// Unknown passthrough fields are re-emitted so round-trips never lose data.
public struct XMPSerializer: Sendable {

    public init() {}

    public func serialize(_ model: AdjustmentModel) -> Data {
        var lines: [String] = []

        lines.append(#"<?xpacket begin="\#u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>"#)
        lines.append(#"<x:xmpmeta xmlns:x="adobe:ns:meta/">"#)
        lines.append(#"  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">"#)
        lines.append(#"    <rdf:Description"#)
        lines.append(#"      xmlns:xmp="http://ns.adobe.com/xap/1.0/""#)
        lines.append(#"      xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/""#)
        lines.append(#"      xmlns:papp="http://ns.justmaple.com/coral-maple/1.0/""#)

        // XMP rating — only emit when > 0 for Adobe interop (absence = unrated)
        if model.culling.rating > 0 {
            lines.append(#"      xmp:Rating="\#(model.culling.rating)""#)
        }

        // CRS fields — only emit non-default values to keep sidecars lean
        func emit(_ key: String, _ value: Double, default defaultVal: Double) {
            if value != defaultVal {
                lines.append("      crs:\(key)=\"\(XMPSerializer.format(value))\"")
            }
        }

        emit("Exposure2012",       model.exposure,       default: 0)
        emit("Contrast2012",       model.contrast,       default: 0)
        emit("Highlights2012",     model.highlights,     default: 0)
        emit("Shadows2012",        model.shadows,        default: 0)
        emit("Whites2012",         model.whites,         default: 0)
        emit("Blacks2012",         model.blacks,         default: 0)
        emit("Temperature",        model.temperature,    default: 6500)
        emit("Tint",               model.tint,           default: 0)
        emit("Vibrance",           model.vibrance,       default: 0)
        emit("Saturation",         model.saturation,     default: 0)
        emit("Clarity2012",        model.clarity,        default: 0)
        emit("Texture",            model.texture,        default: 0)
        emit("Dehaze",             model.dehaze,         default: 0)
        emit("SharpenAmount",      model.sharpenAmount,  default: 0)
        emit("SharpenRadius",      model.sharpenRadius,  default: 1.0)
        emit("SharpenDetail",      model.sharpenDetail,  default: 25)
        emit("SharpenEdgeMasking", model.sharpenMasking, default: 0)
        emit("LuminanceSmoothing", model.nrLuminance,    default: 0)
        emit("ColorNoiseReduction",model.nrColor,        default: 25)

        // papp fields
        if model.culling.flag != .unflagged {
            lines.append("      papp:Flag=\"\(model.culling.flag.rawValue)\"")
        }
        if let label = model.culling.colorLabel {
            lines.append("      papp:ColorLabel=\"\(label.rawValue)\"")
        }

        // Passthrough — preserve unknown fields
        for (key, value) in model.passthroughFields.sorted(by: { $0.key < $1.key }) {
            let escaped = XMPSerializer.escapeXMLAttribute(value)
            lines.append("      \(key)=\"\(escaped)\"")
        }

        lines.append(#"    />"#)
        lines.append(#"  </rdf:RDF>"#)
        lines.append(#"</x:xmpmeta>"#)
        lines.append(#"<?xpacket end="w"?>"#)

        let xml = lines.joined(separator: "\n")
        return Data(xml.utf8)
    }

    // MARK: - Formatting helpers

    /// Format a double for XMP: strip trailing zeros, keep at most 2 decimal places.
    static func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        let s = String(format: "%.2f", value)
        // strip trailing zeros after decimal
        if s.contains(".") {
            var trimmed = s
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
            return trimmed
        }
        return s
    }

    static func escapeXMLAttribute(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
