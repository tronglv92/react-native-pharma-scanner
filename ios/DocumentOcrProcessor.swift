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

  // MARK: - Structured Document Recognition

  func recognizeStructuredDocument(imageUri: String) async throws -> StructuredDocumentResult {
    guard let url = URL(string: imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "DocumentOcrProcessor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }

    let imageWidth = ciImage.extent.width
    let imageHeight = ciImage.extent.height

    if #available(iOS 26.0, *) {
      do {
        return try await recognizeStructuredDocumentModern(ciImage: ciImage, imageWidth: imageWidth, imageHeight: imageHeight)
      } catch {
        print("[DocumentOcrProcessor] RecognizeDocumentsRequest failed: \(error.localizedDescription). Falling back to OcrProcessor.")
        return try await recognizeStructuredDocumentFallback(imageUri: imageUri)
      }
    } else {
      return try await recognizeStructuredDocumentFallback(imageUri: imageUri)
    }
  }

  // MARK: - iOS 26+ Structured Path

  @available(iOS 26.0, *)
  private func recognizeStructuredDocumentModern(ciImage: CIImage, imageWidth: CGFloat, imageHeight: CGFloat) async throws -> StructuredDocumentResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.automaticallyDetectLanguage = true
    request.textRecognitionOptions.useLanguageCorrection = true

    let observations = try await request.perform(on: ciImage)

    var paragraphs: [StructuredParagraph] = []
    var tables: [StructuredTable] = []
    var detectedEntities: [DetectedEntity] = []
    var barcodeStrings: [String] = []
    var allTextParts: [String] = []

    for observation in observations {
      let container = observation.document

      // Extract paragraphs with position classification
      for paragraph in container.paragraphs {
        let text = paragraph.transcript
        guard !text.isEmpty else { continue }

        let boundingBox = regionToPixelRect(paragraph.boundingRegion, imageWidth: imageWidth, imageHeight: imageHeight)
        let normalizedY = boundingBox.y / imageHeight
        let position: String
        if normalizedY < 0.25 {
          position = "top"
        } else if normalizedY > 0.70 {
          position = "bottom"
        } else {
          position = "middle"
        }

        paragraphs.append(StructuredParagraph(text: text, position: position, boundingBox: boundingBox))
        allTextParts.append(text)

        // Extract entities from paragraph's recognized text detectedData
        extractEntitiesFromText(text, into: &detectedEntities)
      }

      // Extract tables as StructuredTable with TableRow arrays
      for table in container.tables {
        var tableRows: [TableRow] = []
        for row in table.rows {
          guard !row.isEmpty else { continue }
          var cellTexts: [String] = []
          for cell in row {
            let cellText = cell.content.text.transcript.replacingOccurrences(of: "\n", with: " ")
            cellTexts.append(cellText)
          }
          if !cellTexts.isEmpty {
            tableRows.append(TableRow(cells: cellTexts))
          }
        }
        if !tableRows.isEmpty {
          let boundingBox = regionToPixelRect(table.boundingRegion, imageWidth: imageWidth, imageHeight: imageHeight)
          tables.append(StructuredTable(rows: tableRows, boundingBox: boundingBox))

          // Add table text to raw text
          let tableText = tableRows.map { $0.cells.joined(separator: " | ") }.joined(separator: "\n")
          allTextParts.append(tableText)
        }
      }

      // Extract barcodes
      for barcode in container.barcodes {
        if let payload = barcode.payloadString {
          barcodeStrings.append(payload)
        }
      }
    }

    let rawText = allTextParts.joined(separator: "\n")
    let analyzer = StructuredDocumentAnalyzer()
    let summary = analyzer.buildSummary(paragraphs: paragraphs, entities: detectedEntities, rawText: rawText)
    let documentType = analyzer.detectDocumentType(
      paragraphs: paragraphs, tables: tables, entities: detectedEntities,
      barcodes: barcodeStrings, rawText: rawText
    )
    let confidence = analyzer.computeConfidence(
      paragraphs: paragraphs, tables: tables, entities: detectedEntities,
      keyValuePairs: summary.keyValuePairs
    )

    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    return StructuredDocumentResult(
      documentType: documentType,
      paragraphs: paragraphs,
      tables: tables,
      detectedEntities: detectedEntities,
      barcodes: barcodeStrings,
      summary: summary,
      rawText: rawText,
      confidence: confidence,
      processingTimeMs: elapsed
    )
  }

  // MARK: - iOS < 26 Fallback Path

  private func recognizeStructuredDocumentFallback(imageUri: String) async throws -> StructuredDocumentResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    let processor = OcrProcessor()
    let ocrResult = try await processor.recognizeText(imageUri: imageUri)

    guard let url = URL(string: imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "DocumentOcrProcessor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }
    let imageHeight = ciImage.extent.height

    // Convert TextBlocks to StructuredParagraphs with position from bounding box Y
    var paragraphs: [StructuredParagraph] = []
    var detectedEntities: [DetectedEntity] = []

    for block in ocrResult.blocks {
      let normalizedY = block.boundingBox.y / imageHeight
      let position: String
      if normalizedY < 0.25 {
        position = "top"
      } else if normalizedY > 0.70 {
        position = "bottom"
      } else {
        position = "middle"
      }
      paragraphs.append(StructuredParagraph(text: block.text, position: position, boundingBox: block.boundingBox))

      // Extract entities from text via regex heuristics
      extractEntitiesFromText(block.text, into: &detectedEntities)
    }

    let rawText = ocrResult.text
    let analyzer = StructuredDocumentAnalyzer()
    let summary = analyzer.buildSummary(paragraphs: paragraphs, entities: detectedEntities, rawText: rawText)
    let documentType = analyzer.detectDocumentType(
      paragraphs: paragraphs, tables: [], entities: detectedEntities,
      barcodes: [], rawText: rawText
    )
    let confidence = analyzer.computeConfidence(
      paragraphs: paragraphs, tables: [], entities: detectedEntities,
      keyValuePairs: summary.keyValuePairs
    ) * 0.7 // Lower confidence for fallback path

    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    return StructuredDocumentResult(
      documentType: documentType,
      paragraphs: paragraphs,
      tables: [],
      detectedEntities: detectedEntities,
      barcodes: [],
      summary: summary,
      rawText: rawText,
      confidence: confidence,
      processingTimeMs: elapsed
    )
  }

  // MARK: - Entity Extraction Helpers

  private func extractEntitiesFromText(_ text: String, into entities: inout [DetectedEntity]) {
    // Money patterns: 1,000,000 VND or 1.000.000d or $100.00
    let moneyPatterns = [
      #"(\d{1,3}(?:[.,]\d{3})+)\s*(?:VND|đ|d|VNĐ|dong|đồng)"#,
      #"(\$\d{1,3}(?:[.,]\d{3})*(?:\.\d{2})?)"#,
      #"(\d{1,3}(?:\.\d{3})+)\s*(?:VND|đ|d)"#
    ]
    for pattern in moneyPatterns {
      if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
          if let range = Range(match.range, in: text) {
            let value = String(text[range])
            if !entities.contains(where: { $0.type == "money" && $0.value == value }) {
              entities.append(DetectedEntity(type: "money", value: value, context: text))
            }
          }
        }
      }
    }

    // Date patterns
    let datePatterns = [
      #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#,
      #"\b(ngày\s+\d{1,2}\s+tháng\s+\d{1,2}\s+năm\s+\d{4})\b"#
    ]
    for pattern in datePatterns {
      if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
          if let range = Range(match.range(at: 1), in: text) {
            let value = String(text[range])
            if !entities.contains(where: { $0.type == "date" && $0.value == value }) {
              entities.append(DetectedEntity(type: "date", value: value, context: text))
            }
          }
        }
      }
    }

    // Phone patterns
    if let phoneRegex = try? NSRegularExpression(pattern: #"\b((?:\+84|0)\d{9,10})\b"#) {
      let matches = phoneRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
      for match in matches {
        if let range = Range(match.range(at: 1), in: text) {
          let value = String(text[range])
          if !entities.contains(where: { $0.type == "phone" && $0.value == value }) {
            entities.append(DetectedEntity(type: "phone", value: value, context: text))
          }
        }
      }
    }

    // Email patterns
    if let emailRegex = try? NSRegularExpression(pattern: #"\b([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})\b"#) {
      let matches = emailRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
      for match in matches {
        if let range = Range(match.range(at: 1), in: text) {
          let value = String(text[range])
          if !entities.contains(where: { $0.type == "email" && $0.value == value }) {
            entities.append(DetectedEntity(type: "email", value: value, context: text))
          }
        }
      }
    }
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
