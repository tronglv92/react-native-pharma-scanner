import CoreImage
import UIKit

class ImageProcessor {

  static func cropAndCorrect(imageUri: String, corners: Corners) throws -> (Data, Int, Int) {
    guard let url = URL(string: imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "ImageProcessor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI"])
    }

    let imageWidth = ciImage.extent.width
    let imageHeight = ciImage.extent.height

    // Convert normalized coordinates (top-left origin) to CIImage pixel coordinates (bottom-left origin)
    let topLeft = CIVector(x: CGFloat(corners.topLeft.x) * imageWidth,
                           y: (1.0 - CGFloat(corners.topLeft.y)) * imageHeight)
    let topRight = CIVector(x: CGFloat(corners.topRight.x) * imageWidth,
                            y: (1.0 - CGFloat(corners.topRight.y)) * imageHeight)
    let bottomLeft = CIVector(x: CGFloat(corners.bottomLeft.x) * imageWidth,
                              y: (1.0 - CGFloat(corners.bottomLeft.y)) * imageHeight)
    let bottomRight = CIVector(x: CGFloat(corners.bottomRight.x) * imageWidth,
                               y: (1.0 - CGFloat(corners.bottomRight.y)) * imageHeight)

    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
      throw NSError(domain: "ImageProcessor", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "CIPerspectiveCorrection filter not available"])
    }

    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(topLeft, forKey: "inputTopLeft")
    filter.setValue(topRight, forKey: "inputTopRight")
    filter.setValue(bottomLeft, forKey: "inputBottomLeft")
    filter.setValue(bottomRight, forKey: "inputBottomRight")

    guard let outputImage = filter.outputImage else {
      throw NSError(domain: "ImageProcessor", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to apply perspective correction"])
    }

    let context = CIContext()
    guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
      throw NSError(domain: "ImageProcessor", code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to render corrected image"])
    }

    let uiImage = UIImage(cgImage: cgImage)
    guard let jpegData = uiImage.jpegData(compressionQuality: 0.9) else {
      throw NSError(domain: "ImageProcessor", code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG"])
    }

    return (jpegData, cgImage.width, cgImage.height)
  }
}
