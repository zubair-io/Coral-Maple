import Foundation
import Testing
@testable import CoralCore

@Suite("XMP Round-Trip Tests")
struct XMPRoundTripTests {

    let parser = XMPParser()
    let serializer = XMPSerializer()

    @Test("Default model round-trips cleanly")
    func defaultModelRoundTrip() throws {
        let model = AdjustmentModel()
        let data = serializer.serialize(model)
        let parsed = try parser.parse(data: data)
        #expect(parsed.exposure == model.exposure)
        #expect(parsed.contrast == model.contrast)
        #expect(parsed.culling.rating == model.culling.rating)
        #expect(parsed.culling.flag == model.culling.flag)
    }

    @Test("Non-default model round-trips with all fields")
    func fullModelRoundTrip() throws {
        var model = AdjustmentModel()
        model.exposure = 1.5
        model.contrast = -30
        model.highlights = -40
        model.shadows = 30
        model.whites = 10
        model.blacks = -5
        model.temperature = 5800
        model.tint = -2
        model.vibrance = 20
        model.saturation = -10
        model.clarity = 15
        model.texture = 25
        model.dehaze = 10
        model.sharpenAmount = 40
        model.sharpenRadius = 1.2
        model.sharpenDetail = 50
        model.sharpenMasking = 30
        model.nrLuminance = 20
        model.nrColor = 40
        model.culling = CullingState(rating: 5, flag: .pick, colorLabel: .green)

        let data = serializer.serialize(model)
        let parsed = try parser.parse(data: data)

        #expect(parsed.exposure == model.exposure)
        #expect(parsed.contrast == model.contrast)
        #expect(parsed.highlights == model.highlights)
        #expect(parsed.shadows == model.shadows)
        #expect(parsed.whites == model.whites)
        #expect(parsed.blacks == model.blacks)
        #expect(parsed.temperature == model.temperature)
        #expect(parsed.tint == model.tint)
        #expect(parsed.vibrance == model.vibrance)
        #expect(parsed.saturation == model.saturation)
        #expect(parsed.clarity == model.clarity)
        #expect(parsed.texture == model.texture)
        #expect(parsed.dehaze == model.dehaze)
        #expect(parsed.sharpenAmount == model.sharpenAmount)
        #expect(parsed.sharpenRadius == model.sharpenRadius)
        #expect(parsed.sharpenDetail == model.sharpenDetail)
        #expect(parsed.sharpenMasking == model.sharpenMasking)
        #expect(parsed.nrLuminance == model.nrLuminance)
        #expect(parsed.nrColor == model.nrColor)
        #expect(parsed.culling.rating == 5)
        #expect(parsed.culling.flag == .pick)
        #expect(parsed.culling.colorLabel == .green)
    }

    @Test("Unknown namespace fields are preserved")
    func passthroughPreservation() throws {
        var model = AdjustmentModel()
        model.passthroughFields = ["lr:CustomField": "test_value"]

        let data = serializer.serialize(model)
        let xml = String(data: data, encoding: .utf8)!
        #expect(xml.contains("lr:CustomField=\"test_value\""))

        let parsed = try parser.parse(data: data)
        #expect(parsed.passthroughFields["lr:CustomField"] == "test_value")
    }

    @Test("Malformed XML throws XMPError.malformedXML")
    func malformedXML() {
        let bad = Data("<not valid xml".utf8)
        #expect(throws: XMPError.malformedXML) {
            try parser.parse(data: bad)
        }
    }

    @Test("Partial XMP with missing fields defaults correctly")
    func partialXMP() throws {
        let xml = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
              xmp:Rating="3"
              crs:Exposure2012="+1.5"
            />
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        let data = Data(xml.utf8)
        let parsed = try parser.parse(data: data)

        #expect(parsed.exposure == 1.5)
        #expect(parsed.culling.rating == 3)
        // All other fields should be defaults
        #expect(parsed.contrast == 0)
        #expect(parsed.temperature == 6500)
        #expect(parsed.culling.flag == Flag.unflagged)
    }
}
