import Foundation

/// Parses XMP XML data into an `AdjustmentModel`.
///
/// Handles the standard `crs:` namespace (Adobe Camera Raw Settings),
/// `xmp:` namespace (ratings), and the custom `papp:` namespace
/// (`http://ns.justmaple.com/coral-maple/1.0/`).
///
/// Unknown attributes on the `rdf:Description` element are preserved
/// in `AdjustmentModel.passthroughFields` so we never destroy data
/// written by other tools.
public struct XMPParser: Sendable {

    public init() {}

    public func parse(data: Data) throws -> AdjustmentModel {
        let delegate = XMPParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.didFail else {
            throw XMPError.malformedXML
        }
        return delegate.buildModel()
    }
}

// MARK: - XMLParser delegate

private final class XMPParserDelegate: NSObject, XMLParserDelegate {

    // Known namespace prefixes → URIs
    private static let crsURI  = "http://ns.adobe.com/camera-raw-settings/1.0/"
    private static let xmpURI  = "http://ns.adobe.com/xap/1.0/"
    private static let pappURI = "http://ns.justmaple.com/coral-maple/1.0/"
    private static let rdfURI  = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    private(set) var didFail = false

    // Collected attributes from rdf:Description
    private var crsAttrs: [String: String] = [:]
    private var xmpAttrs: [String: String] = [:]
    private var pappAttrs: [String: String] = [:]
    private var passthrough: [String: String] = [:]

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        // We care about rdf:Description which carries all attributes in flat XMP.
        // With shouldProcessNamespaces=false, elementName includes the prefix.
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "Description" else {
            return
        }

        for (key, value) in attributes {
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let prefix = String(parts[0])
            let local  = String(parts[1])

            switch prefix {
            case "crs":
                crsAttrs[local] = value
            case "xmp":
                xmpAttrs[local] = value
            case "papp":
                pappAttrs[local] = value
            case "rdf", "xmlns", "x":
                break // skip structural namespaces
            default:
                passthrough[key] = value
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        didFail = true
    }

    // MARK: Build model

    func buildModel() -> AdjustmentModel {
        var model = AdjustmentModel()

        // CRS fields
        if let v = crsAttrs["Exposure2012"]       { model.exposure    = Double(v) ?? 0 }
        if let v = crsAttrs["Contrast2012"]        { model.contrast    = Double(v) ?? 0 }
        if let v = crsAttrs["Highlights2012"]      { model.highlights  = Double(v) ?? 0 }
        if let v = crsAttrs["Shadows2012"]         { model.shadows     = Double(v) ?? 0 }
        if let v = crsAttrs["Whites2012"]          { model.whites      = Double(v) ?? 0 }
        if let v = crsAttrs["Blacks2012"]          { model.blacks      = Double(v) ?? 0 }
        if let v = crsAttrs["Temperature"]         { model.temperature = Double(v) ?? 6500 }
        if let v = crsAttrs["Tint"]                { model.tint        = Double(v) ?? 0 }
        if let v = crsAttrs["Vibrance"]            { model.vibrance    = Double(v) ?? 0 }
        if let v = crsAttrs["Saturation"]          { model.saturation  = Double(v) ?? 0 }
        if let v = crsAttrs["Clarity2012"]         { model.clarity     = Double(v) ?? 0 }
        if let v = crsAttrs["Texture"]             { model.texture     = Double(v) ?? 0 }
        if let v = crsAttrs["Dehaze"]              { model.dehaze      = Double(v) ?? 0 }
        if let v = crsAttrs["SharpenAmount"]       { model.sharpenAmount  = Double(v) ?? 0 }
        if let v = crsAttrs["SharpenRadius"]       { model.sharpenRadius  = Double(v) ?? 1.0 }
        if let v = crsAttrs["SharpenDetail"]       { model.sharpenDetail  = Double(v) ?? 25 }
        if let v = crsAttrs["SharpenEdgeMasking"]  { model.sharpenMasking = Double(v) ?? 0 }
        if let v = crsAttrs["LuminanceSmoothing"]  { model.nrLuminance    = Double(v) ?? 0 }
        if let v = crsAttrs["ColorNoiseReduction"] { model.nrColor        = Double(v) ?? 25 }

        // XMP fields
        if let v = xmpAttrs["Rating"] { model.culling.setRating(Int(v) ?? 0) }

        // papp fields
        if let v = pappAttrs["Flag"]       { model.culling.flag = Flag(rawValue: v) ?? .unflagged }
        if let v = pappAttrs["ColorLabel"] { model.culling.colorLabel = ColorLabel(rawValue: v) }

        // Passthrough
        model.passthroughFields = passthrough

        return model
    }
}
