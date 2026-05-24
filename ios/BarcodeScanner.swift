import Vision
import AVFoundation
import NitroModules

class BarcodeScanner {

  // MARK: - Still Image Scanning

  func scanBarcodes(imageUri: String, formats: [BarcodeFormat]) async throws -> [BarcodeResult] {
    guard let url = URL(string: imageUri) else {
      throw NSError(domain: "BarcodeScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image URI: \(imageUri)"])
    }

    guard let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "BarcodeScanner", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }

    let imageWidth = ciImage.extent.width
    let imageHeight = ciImage.extent.height

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNDetectBarcodesRequest { request, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        guard let observations = request.results as? [VNBarcodeObservation] else {
          continuation.resume(returning: [])
          return
        }

        let results = observations.compactMap { observation -> BarcodeResult? in
          guard let format = Self.vnSymbologyToBarcodeFormat(observation.symbology) else {
            return nil
          }
          let payload = observation.payloadStringValue ?? ""
          let box = observation.boundingBox
          let boundingBox = FrameRect(
            x: box.origin.x * imageWidth,
            y: (1.0 - box.origin.y - box.height) * imageHeight,
            width: box.width * imageWidth,
            height: box.height * imageHeight
          )
          return BarcodeResult(format: format, value: payload, rawValue: payload, boundingBox: boundingBox)
        }
        continuation.resume(returning: results)
      }

      let symbologies = formats.compactMap { Self.barcodeFormatToVNSymbology($0) }
      if !symbologies.isEmpty {
        request.symbologies = symbologies
      }

      let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Format Mapping

  static func barcodeFormatToVNSymbology(_ format: BarcodeFormat) -> VNBarcodeSymbology? {
    switch format {
    case .qrCode:
      return .qr
    case .code128:
      return .code128
    case .pdf417:
      return .pdf417
    case .dataMatrix:
      return .dataMatrix
    case .ean13:
      return .ean13
    case .ean8:
      return .ean8
    }
  }

  static func vnSymbologyToBarcodeFormat(_ symbology: VNBarcodeSymbology) -> BarcodeFormat? {
    switch symbology {
    case .qr:
      return .qrCode
    case .code128:
      return .code128
    case .pdf417:
      return .pdf417
    case .dataMatrix:
      return .dataMatrix
    case .ean13:
      return .ean13
    case .ean8:
      return .ean8
    default:
      return nil
    }
  }

  static func barcodeFormatToAVMetadataObjectType(_ format: BarcodeFormat) -> AVMetadataObject.ObjectType? {
    switch format {
    case .qrCode:
      return .qr
    case .code128:
      return .code128
    case .pdf417:
      return .pdf417
    case .dataMatrix:
      return .dataMatrix
    case .ean13:
      return .ean13
    case .ean8:
      return .ean8
    }
  }

  static func avMetadataObjectTypeToBarcodeFormat(_ type: AVMetadataObject.ObjectType) -> BarcodeFormat? {
    switch type {
    case .qr:
      return .qrCode
    case .code128:
      return .code128
    case .pdf417:
      return .pdf417
    case .dataMatrix:
      return .dataMatrix
    case .ean13:
      return .ean13
    case .ean8:
      return .ean8
    default:
      return nil
    }
  }
}
