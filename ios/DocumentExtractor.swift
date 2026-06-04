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

    // Local LLM path (Qwen3-1.7B via llama.cpp)
    if customPrompt == "__local_llm__" {
      return try await localLlmExtraction(
        imageUri: imageUri,
        documentType: documentType,
        startTime: startTime
      )
    }

    // FoundationModels path (iOS 26+, on-device AI)
    if customPrompt == "__foundation_models__" {
      return try await foundationModelExtraction(
        imageUri: imageUri,
        documentType: documentType,
        startTime: startTime
      )
    }

    // All other extraction (Mistral) is handled in JS.
    // Native fallback: return raw OCR text.
    return try await ocrFallback(
      imageUri: imageUri,
      documentType: documentType,
      startTime: startTime
    )
  }

  // MARK: - Local LLM extraction (Qwen3 via llama.cpp)

  private func localLlmExtraction(
    imageUri: String,
    documentType: String,
    startTime: CFAbsoluteTime
  ) async throws -> DocumentExtractionResult {
    // 1. Run OCR via existing OcrProcessor
    let processor = OcrProcessor()
    let ocrStart = CFAbsoluteTimeGetCurrent()
    let ocrResult = try await processor.recognizeText(imageUri: imageUri)
    let ocrText = String(ocrResult.text)
    let ocrTimeMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000

    guard !ocrText.isEmpty else {
      throw ExtractorError(message: "No text recognized in the image.")
    }

    // 2. Check model availability
    let llm = LlamaCppManager.shared
    guard llm.isModelDownloaded else {
      throw ExtractorError(message: "Local LLM model not downloaded. Please download the model first.")
    }

    // 3. Load model if not already loaded
    if !llm.isModelLoaded {
      try llm.loadModel()
    }

    // 4. Build prompt with JSON schema for document type
    let schema = schemaForDocumentType(documentType)
    let prompt = llm.buildPrompt(ocrText: ocrText, jsonSchema: schema)

    // 5. Generate structured JSON
    let rawOutput = try await llm.generate(prompt: prompt)

    // 6. Extract JSON from output
    let jsonString = extractJSON(from: rawOutput) ?? "{}"
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    return DocumentExtractionResult(
      documentType: documentType == "auto" ? "invoice" : documentType,
      data: jsonString,
      rawText: ocrText,
      confidence: 0.80,
      extractionMethod: "local_llm",
      processingTimeMs: elapsed,
      ocrTimeMs: ocrTimeMs,
      warnings: []
    )
  }

  /// Returns a JSON schema string for the given document type.
  private func schemaForDocumentType(_ documentType: String) -> String {
    switch documentType {
    case "invoice", "auto":
      return """
      {
        "invoiceNumber": "string",
        "date": "string",
        "dueDate": "string",
        "seller": { "name": "string", "address": "string", "taxId": "string" },
        "buyer": { "name": "string", "address": "string", "taxId": "string" },
        "items": [{ "name": "string", "quantity": "number", "unit": "string", "unitPrice": "number", "amount": "number" }],
        "subtotal": "number",
        "tax": "number",
        "total": "number",
        "currency": "string",
        "notes": "string"
      }
      """
    case "prescription":
      return """
      {
        "patientName": "string",
        "doctorName": "string",
        "date": "string",
        "facility": "string",
        "diagnosis": "string",
        "medications": [{ "name": "string", "dosage": "string", "quantity": "string", "instructions": "string" }],
        "notes": "string"
      }
      """
    case "receipt":
      return """
      {
        "storeName": "string",
        "storeAddress": "string",
        "date": "string",
        "items": [{ "name": "string", "quantity": "number", "price": "number" }],
        "subtotal": "number",
        "tax": "number",
        "total": "number",
        "paymentMethod": "string"
      }
      """
    case "id_card":
      return """
      {
        "fullName": "string",
        "dateOfBirth": "string",
        "idNumber": "string",
        "address": "string",
        "issueDate": "string",
        "expiryDate": "string",
        "issuingAuthority": "string"
      }
      """
    default:
      return """
      {
        "documentType": "string",
        "content": "object",
        "extractedFields": "object"
      }
      """
    }
  }

  /// Finds and returns the first valid JSON object in the given string.
  private func extractJSON(from text: String) -> String? {
    // Find the first '{' and match to its closing '}'
    guard let startIdx = text.firstIndex(of: "{") else { return nil }

    var depth = 0
    var endIdx: String.Index?
    for i in text.indices[startIdx...] {
      let c = text[i]
      if c == "{" { depth += 1 }
      else if c == "}" {
        depth -= 1
        if depth == 0 {
          endIdx = i
          break
        }
      }
    }

    guard let end = endIdx else { return nil }
    let jsonCandidate = String(text[startIdx...end])

    // Validate it's actually parseable JSON
    if let data = jsonCandidate.data(using: .utf8),
       (try? JSONSerialization.jsonObject(with: data)) != nil {
      return jsonCandidate
    }
    return jsonCandidate // Return even if not perfectly valid — caller can handle
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
      warnings: ["Use Mistral mode for structured extraction."]
    )
  }
}
