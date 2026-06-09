import CoreImage
import UIKit

struct ImageQualityResult {
  let rating: String       // "good", "fair", "poor"
  let blurScore: Double
  let brightnessScore: Double
  let warnings: [String]
}

final class ImageQualityAssessor {

  static func assess(imageUri: String) throws -> ImageQualityResult {
    guard let url = resolveURL(imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "ImageQualityAssessor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image for quality assessment"])
    }

    let blurScore = computeBlurScore(ciImage)
    let brightnessScore = computeBrightness(ciImage)

    var warnings: [String] = []
    var blurRating: String
    var brightnessRating: String

    // Blur thresholds
    if blurScore < 50 {
      blurRating = "poor"
      warnings.append("IMAGE_TOO_BLURRY:Image is very blurry (score: \(Int(blurScore)))")
    } else if blurScore < 150 {
      blurRating = "fair"
      warnings.append("IMAGE_SLIGHTLY_BLURRY:Image could be sharper (score: \(Int(blurScore)))")
    } else {
      blurRating = "good"
    }

    // Brightness thresholds
    if brightnessScore < 40 {
      brightnessRating = "poor"
      warnings.append("IMAGE_TOO_DARK:Image is too dark (brightness: \(Int(brightnessScore)))")
    } else if brightnessScore > 220 {
      brightnessRating = "poor"
      warnings.append("IMAGE_TOO_BRIGHT:Image is overexposed (brightness: \(Int(brightnessScore)))")
    } else if brightnessScore < 70 {
      brightnessRating = "fair"
      warnings.append("IMAGE_SLIGHTLY_DARK:Image is somewhat dark (brightness: \(Int(brightnessScore)))")
    } else if brightnessScore > 200 {
      brightnessRating = "fair"
      warnings.append("IMAGE_SLIGHTLY_BRIGHT:Image is somewhat bright (brightness: \(Int(brightnessScore)))")
    } else {
      brightnessRating = "good"
    }

    // Overall rating: worst of the two
    let rating: String
    if blurRating == "poor" || brightnessRating == "poor" {
      rating = "poor"
    } else if blurRating == "fair" || brightnessRating == "fair" {
      rating = "fair"
    } else {
      rating = "good"
    }

    return ImageQualityResult(
      rating: rating,
      blurScore: blurScore,
      brightnessScore: brightnessScore,
      warnings: warnings
    )
  }

  // MARK: - Blur detection via Laplacian variance

  private static func computeBlurScore(_ image: CIImage) -> Double {
    // Laplacian kernel: [0, 1, 0; 1, -4, 1; 0, 1, 0]
    let weights: [CGFloat] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
    let weightVector = CIVector(values: weights, count: 9)

    guard let convolution = CIFilter(name: "CIConvolution3X3") else {
      return 100.0 // Default to fair if filter unavailable
    }

    // Convert to grayscale first
    let grayscaleImage = convertToGrayscale(image)

    convolution.setValue(grayscaleImage, forKey: kCIInputImageKey)
    convolution.setValue(weightVector, forKey: "inputWeights")
    convolution.setValue(0.0, forKey: "inputBias")

    guard let outputImage = convolution.outputImage else {
      return 100.0
    }

    // Compute variance of the Laplacian output
    // Use CIAreaAverage to get mean, then approximate variance via extent sampling
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let extent = outputImage.extent

    // Sample a center region for performance
    let sampleSize: CGFloat = min(640, min(extent.width, extent.height))
    let sampleRect = CGRect(
      x: extent.midX - sampleSize / 2,
      y: extent.midY - sampleSize / 2,
      width: sampleSize,
      height: sampleSize
    ).intersection(extent)

    guard !sampleRect.isEmpty else { return 100.0 }

    // Render the Laplacian output to a bitmap and compute variance
    var bitmap = [UInt8](repeating: 0, count: Int(sampleRect.width) * Int(sampleRect.height) * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    context.render(
      outputImage,
      toBitmap: &bitmap,
      rowBytes: Int(sampleRect.width) * 4,
      bounds: sampleRect,
      format: .RGBA8,
      colorSpace: colorSpace
    )

    let pixelCount = Int(sampleRect.width) * Int(sampleRect.height)
    guard pixelCount > 0 else { return 100.0 }

    // Compute variance of the red channel (grayscale, so R≈G≈B)
    var sum: Double = 0
    var sumSq: Double = 0
    for i in stride(from: 0, to: bitmap.count, by: 4) {
      let val = Double(bitmap[i])
      sum += val
      sumSq += val * val
    }

    let mean = sum / Double(pixelCount)
    let variance = (sumSq / Double(pixelCount)) - (mean * mean)

    return variance
  }

  // MARK: - Brightness via average pixel intensity

  private static func computeBrightness(_ image: CIImage) -> Double {
    let grayscale = convertToGrayscale(image)

    guard let avgFilter = CIFilter(name: "CIAreaAverage") else {
      return 128.0
    }

    // Downscale for performance
    let extent = grayscale.extent
    let sampleSize: CGFloat = min(640, min(extent.width, extent.height))
    let sampleRect = CGRect(
      x: extent.midX - sampleSize / 2,
      y: extent.midY - sampleSize / 2,
      width: sampleSize,
      height: sampleSize
    ).intersection(extent)

    guard !sampleRect.isEmpty else { return 128.0 }

    avgFilter.setValue(grayscale, forKey: kCIInputImageKey)
    avgFilter.setValue(CIVector(cgRect: sampleRect), forKey: "inputExtent")

    guard let outputImage = avgFilter.outputImage else {
      return 128.0
    }

    let context = CIContext(options: [.useSoftwareRenderer: false])
    var pixel = [UInt8](repeating: 0, count: 4)
    context.render(
      outputImage,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    // Average of RGB (should be same for grayscale)
    let brightness = (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / 3.0
    return brightness
  }

  // MARK: - Helpers

  private static func convertToGrayscale(_ image: CIImage) -> CIImage {
    guard let filter = CIFilter(name: "CIColorControls") else {
      return image
    }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(0.0, forKey: "inputSaturation")
    return filter.outputImage ?? image
  }

  private static func resolveURL(_ imageUri: String) -> URL? {
    if imageUri.hasPrefix("file://") {
      return URL(string: imageUri)
    }
    return URL(fileURLWithPath: imageUri)
  }
}
