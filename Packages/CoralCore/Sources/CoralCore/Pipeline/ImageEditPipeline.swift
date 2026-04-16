import CoreGraphics
import CoreImage
import Foundation
import Metal

/// GPU-backed image editing pipeline using Core Image.
///
/// Composes RAW decode + adjustment filter chain into a lazy CIImage,
/// then renders to CGImage via a Metal-backed CIContext.
/// The CIContext handles automatic tiling for >50MP images.
public final class ImageEditPipeline: @unchecked Sendable {

    private let ciContext: CIContext
    private let decoder: RAWDecodeEngine

    public init() {
        let device = MTLCreateSystemDefaultDevice()
        if let device {
            self.ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                .cacheIntermediates: false,
            ])
        } else {
            self.ciContext = CIContext(options: [
                .cacheIntermediates: false,
            ])
        }
        self.decoder = RAWDecodeEngine()
    }

    // MARK: - Decode

    /// Decode a file. The decode is always neutral — WB and exposure are
    /// applied post-decode so sliders respond without re-decoding.
    public func decode(url: URL) throws -> CIImage {
        try decoder.decode(url: url)
    }

    /// Decode from data.
    public func decode(data: Data, filename: String = "") throws -> CIImage {
        try decoder.decode(data: data, filename: filename)
    }

    // MARK: - Process

    /// Apply the full adjustment chain to a decoded CIImage.
    /// Returns a lazy CIImage — no pixels computed until render.
    public func process(input: CIImage, adjustments: AdjustmentModel) -> CIImage {
        CIFilterMapping.apply(adjustments, to: input)
    }

    // MARK: - Render

    /// Render a processed CIImage to CGImage at its full extent.
    public func render(_ ciImage: CIImage) -> CGImage? {
        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 else { return nil }
        return ciContext.createCGImage(ciImage, from: extent)
    }

    /// Render at a specific target size (for preview). Scales down before rendering.
    public func renderPreview(_ ciImage: CIImage, targetSize: CGSize) -> CGImage? {
        let extent = ciImage.extent
        guard extent.width > 0 && extent.height > 0 else { return nil }

        let scaleX = targetSize.width / extent.width
        let scaleY = targetSize.height / extent.height
        let scale = min(scaleX, scaleY, 1.0) // never upscale

        let scaled: CIImage
        if scale < 1.0 {
            scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            scaled = ciImage
        }

        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    /// Encode a processed CIImage as opaque JPEG bytes at a target size.
    /// Used by RenderedPreviewCache — `CIContext.jpegRepresentation` always
    /// produces opaque output, avoiding ImageIO's "saving opaque image with
    /// AlphaPremulLast" warning that fires when we write a CGImage with alpha.
    public func encodePreviewJPEG(
        processed: CIImage,
        targetSize: CGSize,
        quality: Double = 0.85
    ) -> Data? {
        let extent = processed.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scaleX = targetSize.width / extent.width
        let scaleY = targetSize.height / extent.height
        let scale = min(scaleX, scaleY, 1.0) // never upscale

        let scaled: CIImage = scale < 1.0
            ? processed.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : processed

        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        return ciContext.jpegRepresentation(
            of: scaled,
            colorSpace: colorSpace,
            options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
            ]
        )
    }

    /// Render to Data in a specific format (for export).
    public func renderToData(
        _ ciImage: CIImage,
        format: ExportFormat,
        quality: Double = 0.92
    ) -> Data? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        switch format {
        case .jpeg:
            return ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
            ])
        case .heic:
            return ciContext.heifRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace, options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality
            ])
        case .png:
            return ciContext.pngRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace, options: [:])
        case .tiff:
            return ciContext.tiffRepresentation(of: ciImage, format: .RGBA16, colorSpace: colorSpace, options: [:])
        }
    }
}

// MARK: - Export Format

public enum ExportFormat: String, Sendable, Codable, CaseIterable {
    case jpeg = "JPEG"
    case heic = "HEIC"
    case tiff = "TIFF"
    case png = "PNG"
}
