import CoreImage
import Foundation
import UniformTypeIdentifiers

/// Decodes RAW and standard image files into CIImage.
///
/// For RAW files, applies white balance and exposure at decode time using CIRAWFilter
/// for maximum quality (linear-light, full bit-depth processing).
/// For non-RAW files (JPEG, HEIC, PNG, TIFF), returns a plain CIImage.
public struct RAWDecodeEngine: Sendable {

    public init() {}

    /// Read the as-shot WB from a RAW file's metadata (CIRAWFilter reads DNG/EXIF tags).
    /// Returns nil if not available (non-RAW or no WB tags).
    public func asShotWB(url: URL) -> (temperature: Double, tint: Double)? {
        guard Self.isRAWFile(url: url),
              let filter = CIRAWFilter(imageURL: url) else {
            return nil
        }
        return (Double(filter.neutralTemperature), Double(filter.neutralTint))
    }

    /// Read the as-shot WB from RAW file data.
    public func asShotWB(data: Data, filename: String) -> (temperature: Double, tint: Double)? {
        // Write to temp file so CIRAWFilter can read it with the correct extension
        let ext = (filename as NSString).pathExtension.lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try? data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return asShotWB(url: tempURL)
    }

    /// Decode from a file URL.
    ///
    /// The decode is always "neutral" — WB and exposure are applied post-decode
    /// via CIFilters so sliders respond instantly without re-decoding the RAW.
    public func decode(url: URL) throws -> CIImage {
        let isRAW = Self.isRAWFile(url: url)

        if isRAW {
            return try decodeRAW(url: url)
        } else {
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw PipelineError.decodeFailed(url.lastPathComponent)
            }
            return image
        }
    }

    /// Decode from Data (for PhotoKit/SMB assets without a file URL).
    /// `filename` is used to determine the format (e.g. "IMG.DNG").
    public func decode(data: Data, filename: String = "") throws -> CIImage {
        // Write to a temp file so CIRAWFilter can use the extension for format detection.
        // CIRAWFilter(imageData:identifierHint:) often fails to decode RAW from Data alone.
        let ext = (filename as NSString).pathExtension.lowercased()
        let tempName = ext.isEmpty ? "image.dng" : "image.\(ext)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + tempName)

        do {
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if Self.isRAWFile(url: tempURL) {
                return try decodeRAW(url: tempURL)
            } else {
                guard let image = CIImage(contentsOf: tempURL, options: [.applyOrientationProperty: true]) else {
                    throw PipelineError.decodeFailed(filename)
                }
                return image
            }
        } catch let error as PipelineError {
            throw error
        } catch {
            // Temp file write failed — try in-memory as last resort
            guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                throw PipelineError.decodeFailed(filename)
            }
            return image
        }
    }

    // MARK: - RAW decode

    private func decodeRAW(url: URL) throws -> CIImage {
        guard let rawFilter = CIRAWFilter(imageURL: url) else {
            throw PipelineError.decodeFailed(url.lastPathComponent)
        }

        configureRAWFilter(rawFilter)

        guard let output = rawFilter.outputImage else {
            throw PipelineError.decodeFailed(url.lastPathComponent)
        }

        return output
    }

    /// Configures the RAW filter with fully neutral decode parameters.
    /// Exposure and WB are applied as post-decode CIFilters for instant slider
    /// response — the decode only runs once per image (cached in EditSession).
    ///
    /// We decode at 6500K / 0 tint so the output image's baseline WB matches
    /// what CIFilterMapping.applyWhiteBalance assumes (`inputNeutral = 6500/0`).
    private func configureRAWFilter(_ filter: CIRAWFilter) {
        filter.exposure = 0
        filter.neutralTemperature = 6500
        filter.neutralTint = 0
        filter.baselineExposure = 0
    }

    // MARK: - File type detection

    private static let rawExtensions: Set<String> = [
        "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
        "dng", "pef", "srw", "3fr", "ari", "bay", "crw",
        "dcr", "erf", "fff", "iiq", "k25", "kdc", "mef",
        "mos", "mrw", "nrw", "obm", "raw", "rwl", "rwz",
        "sr2", "srf", "x3f"
    ]

    static func isRAWFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if rawExtensions.contains(ext) { return true }
        // Also check UTType conformance
        if let type = UTType(filenameExtension: ext), type.conforms(to: .rawImage) {
            return true
        }
        return false
    }
}

// MARK: - Pipeline Errors

public enum PipelineError: Error, Sendable {
    case decodeFailed(String)
    case renderFailed
    case exportFailed(String)
    case noImage
}
