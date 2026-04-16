import CoreImage
import Foundation

/// Maps AdjustmentModel fields to a chain of CIFilter operations.
/// Returns a function that transforms a CIImage through the adjustment pipeline.
///
/// WB + exposure are handled at RAW decode time — they are NOT in this chain.
/// The chain order: Contrast → Highlights/Shadows → Whites/Blacks →
/// Vibrance → Saturation → Clarity → Texture → Dehaze → Sharpen → NR
enum CIFilterMapping {

    /// Apply all post-decode adjustments to a CIImage.
    /// Returns a new CIImage with the filter chain composed (lazy — no pixels computed).
    static func apply(_ adjustments: AdjustmentModel, to image: CIImage) -> CIImage {
        var result = image

        // 0a. White balance — post-decode temperature/tint adjustment.
        // neutral=(6500, 0) means "apply this as the new WB", leaving image at (6500, 0) equivalent.
        // targetNeutral=(temperature, tint) shifts the image from 6500K/0 to the user's target.
        if adjustments.temperature != 6500 || adjustments.tint != 0 {
            result = applyWhiteBalance(
                temperature: adjustments.temperature,
                tint: adjustments.tint,
                to: result
            )
        }

        // 0b. Exposure — post-decode exposure adjust (linear scale in EV stops).
        if adjustments.exposure != 0 {
            result = applyExposure(adjustments.exposure, to: result)
        }

        // 1. Contrast
        if adjustments.contrast != 0 {
            result = applyContrast(adjustments.contrast, to: result)
        }

        // 2. Highlights + Shadows
        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            result = applyHighlightsShadows(
                highlights: adjustments.highlights,
                shadows: adjustments.shadows,
                to: result
            )
        }

        // 3. Whites + Blacks (tone curve)
        if adjustments.whites != 0 || adjustments.blacks != 0 {
            result = applyWhitesBlacks(whites: adjustments.whites, blacks: adjustments.blacks, to: result)
        }

        // 4. Vibrance (saturation-aware)
        if adjustments.vibrance != 0 {
            result = applyVibrance(adjustments.vibrance, to: result)
        }

        // 5. Saturation
        if adjustments.saturation != 0 {
            result = applySaturation(adjustments.saturation, to: result)
        }

        // 6. Clarity (local contrast — large-radius unsharp mask)
        if adjustments.clarity != 0 {
            result = applyClarity(adjustments.clarity, to: result)
        }

        // 7. Texture (high-frequency detail — small-radius unsharp mask)
        if adjustments.texture != 0 {
            result = applyTexture(adjustments.texture, to: result)
        }

        // 8. Dehaze
        if adjustments.dehaze != 0 {
            result = applyDehaze(adjustments.dehaze, to: result)
        }

        // 9. Sharpening
        if adjustments.sharpenAmount != 0 {
            result = applySharpening(
                amount: adjustments.sharpenAmount,
                radius: adjustments.sharpenRadius,
                to: result
            )
        }

        // 10. Noise Reduction
        if adjustments.nrLuminance != 0 || adjustments.nrColor != 25 {
            result = applyNoiseReduction(
                luminance: adjustments.nrLuminance,
                color: adjustments.nrColor,
                to: result
            )
        }

        return result
    }

    // MARK: - Individual filter implementations

    /// Exposure: CIExposureAdjust. EV value passed directly.
    private static func applyExposure(_ ev: Double, to image: CIImage) -> CIImage {
        image.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: ev
        ])
    }

    /// White balance: CITemperatureAndTint.
    /// `neutral` = the current WB of the image (we treat as 6500K/0 after decode).
    /// `targetNeutral` = the target WB we want to shift the image to.
    private static func applyWhiteBalance(
        temperature: Double,
        tint: Double,
        to image: CIImage
    ) -> CIImage {
        image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: temperature, y: tint)
        ])
    }

    /// Contrast: CIColorControls. Maps -100..+100 → 0.25..1.75 (default 1.0)
    private static func applyContrast(_ value: Double, to image: CIImage) -> CIImage {
        let mapped = 1.0 + (value / 100.0) * 0.75
        return image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: mapped
        ])
    }

    /// Highlights/Shadows: CIHighlightShadowAdjust
    /// highlights: -100..+100 → highlightAmount 0..1 (inverted — lower = more recovery)
    /// shadows: -100..+100 → shadowAmount -1..1
    private static func applyHighlightsShadows(
        highlights: Double,
        shadows: Double,
        to image: CIImage
    ) -> CIImage {
        let highlightAmount = 1.0 - (highlights / 100.0) * 0.5  // -100→1.5, 0→1.0, +100→0.5
        let shadowAmount = shadows / 100.0  // -100→-1, 0→0, +100→1
        return image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": highlightAmount,
            "inputShadowAmount": shadowAmount
        ])
    }

    /// Whites/Blacks: CIToneCurve with 5 control points.
    /// Whites shifts the upper curve; blacks shifts the lower.
    private static func applyWhitesBlacks(whites: Double, blacks: Double, to image: CIImage) -> CIImage {
        let b = blacks / 100.0 * 0.15  // shift lower points by up to ±0.15
        let w = whites / 100.0 * 0.15  // shift upper points by up to ±0.15
        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: max(0, 0 + b)),
            "inputPoint1": CIVector(x: 0.25, y: max(0, min(1, 0.25 + b * 0.5))),
            "inputPoint2": CIVector(x: 0.5, y: 0.5),
            "inputPoint3": CIVector(x: 0.75, y: max(0, min(1, 0.75 + w * 0.5))),
            "inputPoint4": CIVector(x: 1.0, y: min(1, 1.0 + w)),
        ])
    }

    /// Vibrance: saturation-aware boost using CIVibrance.
    /// Maps -100..+100 → -1..+1
    private static func applyVibrance(_ value: Double, to image: CIImage) -> CIImage {
        let amount = value / 100.0
        return image.applyingFilter("CIVibrance", parameters: [
            "inputAmount": amount
        ])
    }

    /// Saturation: CIColorControls. Maps -100..+100 → 0..2 (default 1.0)
    private static func applySaturation(_ value: Double, to image: CIImage) -> CIImage {
        let mapped = 1.0 + value / 100.0
        return image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: mapped
        ])
    }

    /// Clarity: local contrast via large-radius unsharp mask (radius ~30-50).
    /// Boosts mid-tone contrast without affecting fine detail.
    /// Maps -100..+100 → intensity -2..+2
    private static func applyClarity(_ value: Double, to image: CIImage) -> CIImage {
        let intensity = value / 100.0 * 1.5
        return image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 40.0,
            kCIInputIntensityKey: intensity
        ])
    }

    /// Texture: high-frequency detail via small-radius unsharp mask (radius ~2-4).
    /// Maps -100..+100 → intensity -1..+1
    private static func applyTexture(_ value: Double, to image: CIImage) -> CIImage {
        let intensity = value / 100.0
        return image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 3.0,
            kCIInputIntensityKey: intensity
        ])
    }

    /// Dehaze: gamma + contrast boost to cut through haze.
    /// A proper dehaze uses dark channel prior, but for Phase 2
    /// we approximate with exposure + contrast + saturation shift.
    /// Maps -100..+100
    private static func applyDehaze(_ value: Double, to image: CIImage) -> CIImage {
        let amount = value / 100.0
        // Boost contrast and slightly darken to remove haze
        var result = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.0 + amount * 0.3,
            kCIInputSaturationKey: 1.0 + amount * 0.15
        ])
        // Apply gamma to recover from haze
        if amount > 0 {
            result = result.applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": 1.0 + amount * 0.3
            ])
        } else {
            // Negative dehaze = add haze = reduce contrast + lighten
            result = result.applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": 1.0 + amount * 0.2
            ])
        }
        return result
    }

    /// Sharpening: CIUnsharpMask.
    /// amount: 0..150 → intensity 0..1.5
    /// radius: 0.5..3.0 → passed directly
    private static func applySharpening(amount: Double, radius: Double, to image: CIImage) -> CIImage {
        let intensity = amount / 100.0
        return image.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: radius,
            kCIInputIntensityKey: intensity
        ])
    }

    /// Noise reduction: CINoiseReduction.
    /// luminance: 0..100 → noiseLevel 0..0.05
    /// color: 0..100 → sharpness 0..2 (inversely related)
    private static func applyNoiseReduction(luminance: Double, color: Double, to image: CIImage) -> CIImage {
        let noiseLevel = luminance / 100.0 * 0.05
        let sharpness = max(0, 2.0 - color / 100.0 * 2.0)
        return image.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": noiseLevel,
            "inputSharpness": sharpness
        ])
    }
}
