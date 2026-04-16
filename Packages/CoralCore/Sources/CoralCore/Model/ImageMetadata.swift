import CoreGraphics
import Foundation
import ImageIO

/// Extracted EXIF/IPTC metadata from an image.
public struct ImageMetadata: Sendable {
    // Camera
    public var cameraMake: String?
    public var cameraModel: String?
    public var lens: String?
    public var focalLength: String?
    public var aperture: String?
    public var shutterSpeed: String?
    public var iso: String?
    public var flash: String?

    // Image
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var colorSpace: String?
    public var bitDepth: Int?
    public var fileSize: String?

    // White Balance (as-shot from EXIF)
    public var asShotTemperature: Double?  // Kelvin
    public var asShotTint: Double?

    // Date
    public var dateTaken: String?
    public var dateModified: String?

    // Location
    public var latitude: Double?
    public var longitude: Double?

    // IPTC
    public var title: String?
    public var caption: String?
    public var copyright: String?
    public var creator: String?
    public var keywords: [String]?

    public init() {}

    /// Extract metadata from image data (reads EXIF, IPTC, TIFF properties).
    public static func from(data: Data) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return ImageMetadata() }
        return from(source: source)
    }

    /// Extract metadata from a file URL.
    public static func from(url: URL) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ImageMetadata() }
        return from(source: source)
    }

    private static func from(source: CGImageSource) -> ImageMetadata {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImageMetadata()
        }

        var meta = ImageMetadata()

        // Dimensions
        meta.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
        meta.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
        meta.bitDepth = props[kCGImagePropertyDepth] as? Int
        meta.colorSpace = props[kCGImagePropertyColorModel] as? String

        // EXIF
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let make = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                meta.cameraMake = make[kCGImagePropertyTIFFMake] as? String
                meta.cameraModel = make[kCGImagePropertyTIFFModel] as? String
            }

            meta.lens = exif[kCGImagePropertyExifLensModel] as? String

            if let fl = exif[kCGImagePropertyExifFocalLength] as? Double {
                meta.focalLength = "\(Int(fl))mm"
            }
            if let fn = exif[kCGImagePropertyExifFNumber] as? Double {
                meta.aperture = String(format: "f/%.1f", fn)
            }
            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double {
                if exposure >= 1 {
                    meta.shutterSpeed = String(format: "%.1fs", exposure)
                } else {
                    meta.shutterSpeed = "1/\(Int(1.0 / exposure))s"
                }
            }
            if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoValues.first {
                meta.iso = "ISO \(iso)"
            }
            if let flash = exif[kCGImagePropertyExifFlash] as? Int {
                meta.flash = (flash & 1) == 1 ? "Fired" : "Not fired"
            }
            if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                meta.dateTaken = date
            }
            // White balance from EXIF
            if let wb = exif[kCGImagePropertyExifWhiteBalance] as? Int {
                // 0 = auto, 1 = manual
                _ = wb
            }
        }

        // DNG / TIFF white balance
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = meta.cameraMake ?? (tiff[kCGImagePropertyTIFFMake] as? String)
            meta.cameraModel = meta.cameraModel ?? (tiff[kCGImagePropertyTIFFModel] as? String)
        }

        // As-shot WB: use EXIF ColorTemperature if available (not reliable for most DNGs).
        // The correct way to get as-shot WB is via CIRAWFilter.neutralTemperature,
        // which reads the DNG calibration tags. See RAWDecodeEngine.asShotWB().
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let colorTemp = exif["ColorTemperature" as CFString] as? Double {
                meta.asShotTemperature = colorTemp
            }
        }

        // IPTC
        if let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            meta.caption = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String
            meta.copyright = iptc[kCGImagePropertyIPTCCopyrightNotice] as? String
            meta.creator = iptc[kCGImagePropertyIPTCByline] as? String
            meta.keywords = iptc[kCGImagePropertyIPTCKeywords] as? [String]
        }

        // GPS
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            meta.latitude = gps[kCGImagePropertyGPSLatitude] as? Double
            meta.longitude = gps[kCGImagePropertyGPSLongitude] as? Double
            if let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String, latRef == "S" {
                meta.latitude = meta.latitude.map { -$0 }
            }
            if let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String, lonRef == "W" {
                meta.longitude = meta.longitude.map { -$0 }
            }
        }

        return meta
    }
}
