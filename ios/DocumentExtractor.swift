import Foundation
import UIKit
import NitroModules

final class DocumentExtractor {
  static let shared = DocumentExtractor()

  private var apiKey: String?
  private var baseUrl: String = "https://generativelanguage.googleapis.com"

  private init() {}

  func configure(apiKey: String, baseUrl: String) {
    self.apiKey = apiKey
    self.baseUrl = baseUrl.isEmpty ? "https://generativelanguage.googleapis.com" : baseUrl
  }

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

    let useLLM = !forceOffline
      && NetworkMonitor.shared.isConnected
      && apiKey != nil
      && !(apiKey?.isEmpty ?? true)

    if useLLM {
      // Vision-first: send image directly to Gemini
      do {
        let imageData = try loadImageData(from: imageUri)
        let llm = LLMExtractor(apiKey: apiKey!, baseUrl: baseUrl)
        let result = try await llm.extractFromImage(
          imageData: imageData,
          documentType: documentType,
          language: language,
          customPrompt: customPrompt
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let resolvedType = result.detectedDocumentType ?? documentType

        return DocumentExtractionResult(
          documentType: resolvedType,
          data: result.jsonString,
          rawText: "",
          confidence: 0.90,
          extractionMethod: "vision",
          processingTimeMs: elapsed,
          ocrTimeMs: 0,
          warnings: []
        )
      } catch {
        // Vision failed — fall back to OCR + template
        let fallbackResult = try await ocrAndTemplateFallback(
          imageUri: imageUri,
          documentType: documentType,
          language: language,
          startTime: startTime,
          warnings: ["Vision extraction failed: \(error.localizedDescription). Fell back to OCR + template."]
        )
        return fallbackResult
      }
    } else {
      // Offline / no API key — OCR + template
      var warnings: [String] = []
      if forceOffline {
        warnings.append("Offline mode forced by user.")
      } else if apiKey == nil || (apiKey?.isEmpty ?? true) {
        warnings.append("No API key configured. Using template extraction.")
      } else if !NetworkMonitor.shared.isConnected {
        warnings.append("No network connection. Using template extraction.")
      }

      return try await ocrAndTemplateFallback(
        imageUri: imageUri,
        documentType: documentType,
        language: language,
        startTime: startTime,
        warnings: warnings
      )
    }
  }

  private func foundationModelExtraction(
    imageUri: String,
    documentType: String,
    startTime: CFAbsoluteTime
  ) async throws -> DocumentExtractionResult {
    guard #available(iOS 26.0, *) else {
      throw LLMExtractorError(message: "Foundation Models requires iOS 26 or later.")
    }

    let imageData = try loadImageData(from: imageUri)
    guard let uiImage = UIImage(data: imageData) else {
      throw LLMExtractorError(message: "Failed to create image from data.")
    }

    let ocrStart = CFAbsoluteTimeGetCurrent()
    let ocrText = try await FoundationModelInvoiceExtractor.recognizeText(from: uiImage)
    let ocrTimeMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000

    guard !ocrText.isEmpty else {
      throw LLMExtractorError(message: "No text recognized in the image.")
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
        throw LLMExtractorError(message: "Invalid image URI: \(imageUri)")
      }
      path = fileUrl.path
    } else {
      path = imageUri
    }
    guard FileManager.default.fileExists(atPath: path) else {
      throw LLMExtractorError(message: "Image file not found at: \(path)")
    }
    return try Data(contentsOf: URL(fileURLWithPath: path))
  }

  private func ocrAndTemplateFallback(
    imageUri: String,
    documentType: String,
    language: String,
    startTime: CFAbsoluteTime,
    warnings: [String]
  ) async throws -> DocumentExtractionResult {
    let processor = OcrProcessor()
    let ocrResult = try await processor.recognizeText(imageUri: imageUri)
    let ocrText = String(ocrResult.text)
    let ocrTimeMs = ocrResult.processingTimeMs
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    // Return raw OCR text — structured extraction is handled by the JS template engine
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
      warnings: warnings + ["Template extraction moved to JS engine. Use Template (offline) mode for structured extraction."]
    )
  }
}
