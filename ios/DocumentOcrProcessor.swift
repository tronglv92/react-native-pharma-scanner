import Vision
import NitroModules
import CoreImage
import UIKit

/// Wraps RecognizeDocumentsRequest (iOS 26+) for structured document OCR.
/// Falls back to VNRecognizeTextRequest on older iOS versions.
class DocumentOcrProcessor {

  func recognizeDocument(imageUri: String) async throws -> OcrResult {
    guard let url = URL(string: imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "DocumentOcrProcessor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }

    let imageWidth = ciImage.extent.width
    let imageHeight = ciImage.extent.height

    if #available(iOS 26.0, *) {
      do {
        return try await recognizeWithDocumentsRequest(ciImage: ciImage, imageWidth: imageWidth, imageHeight: imageHeight)
      } catch {
        print("[DocumentOcrProcessor] RecognizeDocumentsRequest failed: \(error.localizedDescription). Falling back to VNRecognizeTextRequest.")
        let processor = OcrProcessor()
        return try await processor.recognizeText(imageUri: imageUri)
      }
    } else {
      let processor = OcrProcessor()
      return try await processor.recognizeText(imageUri: imageUri)
    }
  }

  // MARK: - iOS 26+ RecognizeDocumentsRequest

  @available(iOS 26.0, *)
  private func recognizeWithDocumentsRequest(ciImage: CIImage, imageWidth: CGFloat, imageHeight: CGFloat) async throws -> OcrResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.automaticallyDetectLanguage = true
    request.textRecognitionOptions.useLanguageCorrection = true

    let observations = try await request.perform(on: ciImage)

    var allTextParts: [String] = []
    var allBlocks: [TextBlock] = []

    for observation in observations {
      let container = observation.document
      processContainer(
        container,
        confidence: observation.confidence,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        textParts: &allTextParts,
        blocks: &allBlocks
      )
    }

    let fullText = allTextParts.joined(separator: "\n")
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    return OcrResult(text: fullText, blocks: allBlocks, processingTimeMs: elapsed)
  }

  @available(iOS 26.0, *)
  private func processContainer(
    _ container: DocumentObservation.Container,
    confidence: Float,
    imageWidth: CGFloat,
    imageHeight: CGFloat,
    textParts: inout [String],
    blocks: inout [TextBlock]
  ) {
    // Process paragraphs
    for paragraph in container.paragraphs {
      let paragraphText = paragraph.transcript
      if !paragraphText.isEmpty {
        textParts.append(paragraphText)

        let boundingBox = regionToPixelRect(paragraph.boundingRegion, imageWidth: imageWidth, imageHeight: imageHeight)
        let line = TextLine(
          text: paragraphText,
          boundingBox: boundingBox,
          confidence: Double(confidence),
          elements: []
        )
        blocks.append(TextBlock(text: paragraphText, boundingBox: boundingBox, lines: [line]))
      }
    }

    // Process tables
    for table in container.tables {
      let tableText = formatTable(table, confidence: confidence, imageWidth: imageWidth, imageHeight: imageHeight, blocks: &blocks)
      if !tableText.isEmpty {
        textParts.append(tableText)
      }
    }

    // Process barcodes
    for barcode in container.barcodes {
      if let payload = barcode.payloadString {
        let barcodeText = "[BARCODE: \(payload)]"
        textParts.append(barcodeText)

        let boundingBox = barcodeToPixelRect(barcode, imageWidth: imageWidth, imageHeight: imageHeight)
        let line = TextLine(
          text: barcodeText,
          boundingBox: boundingBox,
          confidence: 1.0,
          elements: []
        )
        blocks.append(TextBlock(text: barcodeText, boundingBox: boundingBox, lines: [line]))
      }
    }
  }

  @available(iOS 26.0, *)
  private func formatTable(
    _ table: DocumentObservation.Container.Table,
    confidence: Float,
    imageWidth: CGFloat,
    imageHeight: CGFloat,
    blocks: inout [TextBlock]
  ) -> String {
    var rowTexts: [[String]] = []

    for row in table.rows {
      guard !row.isEmpty else { continue }
      var cellTexts: [String] = []
      for cell in row {
        let cellText = cell.content.text.transcript.replacingOccurrences(of: "\n", with: " ")
        cellTexts.append(cellText)
      }
      if !cellTexts.isEmpty {
        rowTexts.append(cellTexts)
      }
    }

    guard !rowTexts.isEmpty else { return "" }

    // Format as pipe-delimited table
    var tableLines: [String] = []
    for row in rowTexts {
      let rowText = "| " + row.joined(separator: " | ") + " |"
      tableLines.append(rowText)
    }

    let tableText = tableLines.joined(separator: "\n")
    if !tableText.isEmpty {
      let boundingBox = regionToPixelRect(table.boundingRegion, imageWidth: imageWidth, imageHeight: imageHeight)
      let line = TextLine(
        text: tableText,
        boundingBox: boundingBox,
        confidence: Double(confidence),
        elements: []
      )
      blocks.append(TextBlock(text: tableText, boundingBox: boundingBox, lines: [line]))
    }

    return tableText
  }

  // MARK: - Coordinate conversion

  @available(iOS 26.0, *)
  private func regionToPixelRect(_ region: NormalizedRegion, imageWidth: CGFloat, imageHeight: CGFloat) -> FrameRect {
    let normalizedBox = region.normalizedPath.boundingBox
    return FrameRect(
      x: normalizedBox.origin.x * imageWidth,
      y: (1.0 - normalizedBox.origin.y - normalizedBox.height) * imageHeight,
      width: normalizedBox.width * imageWidth,
      height: normalizedBox.height * imageHeight
    )
  }

  @available(iOS 26.0, *)
  private func barcodeToPixelRect(_ barcode: BarcodeObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> FrameRect {
    let minX = min(barcode.topLeft.x, barcode.bottomLeft.x)
    let maxX = max(barcode.topRight.x, barcode.bottomRight.x)
    let minY = min(barcode.topLeft.y, barcode.topRight.y)
    let maxY = max(barcode.bottomLeft.y, barcode.bottomRight.y)

    return FrameRect(
      x: minX * imageWidth,
      y: (1.0 - maxY) * imageHeight,
      width: (maxX - minX) * imageWidth,
      height: (maxY - minY) * imageHeight
    )
  }
}
