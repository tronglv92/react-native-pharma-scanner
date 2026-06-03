import Foundation
import UIKit
import NitroModules

private struct ExtractorError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

final class DocumentExtractor {
  static let shared = DocumentExtractor()

  private init() {}

  /// No-op — kept for Nitro bridge API compatibility.
  func configure(apiKey: String, baseUrl: String) {}

  func extract(
    imageUri: String,
    documentType: String,
    language: String,
    customPrompt: String?,
    forceOffline: Bool,
  ) async throws -> DocumentExtractionResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    // FoundationModels path (iOS 26+, on-device AI)
    if customPrompt == "__foundation_models__" {
      return try await foundationModelExtraction(
        imageUri: imageUri,
        documentType: documentType,
        startTime: startTime
      )
    }

    // All other extraction (Mistral, Template) is handled in JS.
    // Native fallback: return raw OCR text.
    return try await ocrFallback(
      imageUri: imageUri,
      documentType: documentType,
      startTime: startTime
    )
  }

  private func foundationModelExtraction(
    imageUri: String,
    documentType: String,
    startTime: CFAbsoluteTime
  ) async throws -> DocumentExtractionResult {
    guard #available(iOS 26.0, *) else {
      throw ExtractorError(message: "Foundation Models requires iOS 26 or later.")
    }

    let imageData = try loadImageData(from: imageUri)
    guard let uiImage = UIImage(data: imageData) else {
      throw ExtractorError(message: "Failed to create image from data.")
    }

    let ocrStart = CFAbsoluteTimeGetCurrent()
    let ocrText = try await FoundationModelInvoiceExtractor.recognizeText(from: uiImage)
    let ocrTimeMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000

    guard !ocrText.isEmpty else {
      throw ExtractorError(message: "No text recognized in the image.")
    }

    let invoiceData = try await FoundationModelInvoiceExtractor.extractInvoice(ocrText: ocrText)
    let jsonString = invoiceData.toJSONString() ?? "{}"
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    return DocumentExtractionResult(
      documentType: documentType == "auto" ? "invoice" : documentType,
      data: jsonString,
      rawText: ocrText,
      confidence: 0.92,
      extractionMethod: "foundation_models",
      processingTimeMs: elapsed,
      ocrTimeMs: ocrTimeMs,
      warnings: []
    )
  }

  private func loadImageData(from imageUri: String) throws -> Data {
    let path: String
    if imageUri.hasPrefix("file://") {
      guard let fileUrl = URL(string: imageUri) else {
        throw ExtractorError(message: "Invalid image URI: \(imageUri)")
      }
      path = fileUrl.path
    } else {
      path = imageUri
    }
    guard FileManager.default.fileExists(atPath: path) else {
      throw ExtractorError(message: "Image file not found at: \(path)")
    }
    return try Data(contentsOf: URL(fileURLWithPath: path))
  }

  private func ocrFallback(
    imageUri: String,
    documentType: String,
    startTime: CFAbsoluteTime
  ) async throws -> DocumentExtractionResult {
    let processor = OcrProcessor()
    let ocrResult = try await processor.recognizeText(imageUri: imageUri)
    let ocrText = String(ocrResult.text)
    let ocrTimeMs = ocrResult.processingTimeMs
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    let lines = ocrText.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let data: [String: Any] = ["_documentType": documentType, "content": ["lines": lines]]
    let jsonString = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

    return DocumentExtractionResult(
      documentType: documentType,
      data: jsonString,
      rawText: ocrText,
      confidence: 0.1,
      extractionMethod: "ocr_only",
      processingTimeMs: elapsed,
      ocrTimeMs: ocrTimeMs,
      warnings: ["Use Template (offline) or Mistral mode for structured extraction."]
    )
  }
}
