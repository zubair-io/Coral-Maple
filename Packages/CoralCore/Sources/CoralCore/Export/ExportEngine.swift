import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Renders a processed image to disk at full resolution.
public struct ExportEngine: Sendable {

    public init() {}

    /// Export an image with adjustments applied.
    /// `scopedURL` is the security-scoped bookmark URL that grants sandbox access
    /// to the image's parent folder. Pass nil for PhotoKit/SMB sources.
    /// Returns the URL of the exported file.
    public func export(
        asset: ImageAsset,
        adjustments: AdjustmentModel,
        config: ExportConfiguration,
        source: any LibrarySource,
        pipeline: ImageEditPipeline,
        scopedURL: URL? = nil
    ) async throws -> URL {
        // Start security scope if provided (filesystem sources in sandbox)
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scopedURL?.stopAccessingSecurityScopedResource() } }

        // 1. Decode the full image (always neutral — WB/exposure are post-decode filters)
        let decoded: CIImage
        if let fileURL = asset.fileURL {
            decoded = try pipeline.decode(url: fileURL)
        } else {
            let data = try await source.fullImageData(for: asset)
            decoded = try pipeline.decode(data: data, filename: asset.filename)
        }

        // 2. Apply adjustments
        var processed = pipeline.process(input: decoded, adjustments: adjustments)

        // 3. Resize if needed
        if case .longEdge(let maxDim) = config.resizeMode {
            let extent = processed.extent
            let longest = max(extent.width, extent.height)
            if longest > CGFloat(maxDim) {
                let scale = CGFloat(maxDim) / longest
                processed = processed.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        // 4. Render to data
        guard let data = pipeline.renderToData(processed, format: config.format, quality: config.quality) else {
            throw PipelineError.exportFailed("render failed")
        }

        // 5. Write to disk
        let outputDir = exportDirectory()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let stem = (asset.filename as NSString).deletingPathExtension
        let ext: String
        switch config.format {
        case .jpeg: ext = "jpg"
        case .heic: ext = "heic"
        case .tiff: ext = "tiff"
        case .png: ext = "png"
        }

        var outputURL = outputDir.appendingPathComponent("\(stem)_export.\(ext)")

        // 6. Strip metadata if requested
        if !config.includeMetadata {
            outputURL = try stripMetadata(from: data, to: outputURL)
        } else {
            try data.write(to: outputURL)
        }

        return outputURL
    }

    /// Write image data to disk with EXIF/IPTC/GPS metadata stripped.
    private func stripMetadata(from data: Data, to outputURL: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, type, 1, nil) else {
            try data.write(to: outputURL)
            return outputURL
        }

        // Copy the image but remove metadata dictionaries
        let removeKeys: [CFString] = [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyTIFFDictionary,
        ]
        var cleanProps: [CFString: Any] = [:]
        for key in removeKeys {
            cleanProps[key] = kCFNull
        }

        CGImageDestinationAddImageFromSource(dest, source, 0, cleanProps as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try data.write(to: outputURL)
            return outputURL
        }
        return outputURL
    }

    private func exportDirectory() -> URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Coral Maple Exports", isDirectory: true)
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Exports", isDirectory: true)
        #endif
    }
}
