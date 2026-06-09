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

    // Assess image quality before processing
    let qualityWarnings = assessImageQuality(imageUri: imageUri)

    // Local LLM path (Qwen3-1.7B via llama.cpp)
    if customPrompt == "__local_llm__" {
      var result = try await localLlmExtraction(
        imageUri: imageUri,
        documentType: documentType,
        startTime: startTime
      )
      result = appendWarnings(result, qualityWarnings)
      return result
    }

    // All other extraction (Mistral) is handled in JS.
    // Native fallback: return raw OCR text.
    var result = try await ocrFallback(
      imageUri: imageUri,
      documentType: documentType,
      startTime: startTime
    )
    result = appendWarnings(result, qualityWarnings)
    return result
  }

  // MARK: - Image Quality Assessment

  private func assessImageQuality(imageUri: String) -> [String] {
    guard let quality = try? ImageQualityAssessor.assess(imageUri: imageUri) else {
      return []
    }
    var warnings = quality.warnings
    if quality.rating == "poor" {
      warnings.append("IMAGE_QUALITY:poor - results may be unreliable")
    }
    return warnings
  }

  private func appendWarnings(_ result: DocumentExtractionResult, _ extra: [String]) -> DocumentExtractionResult {
    guard !extra.isEmpty else { return result }
    var allWarnings = Array(result.warnings)
    allWarnings.append(contentsOf: extra)
    return DocumentExtractionResult(
      documentType: result.documentType,
      data: result.data,
      rawText: result.rawText,
      confidence: result.confidence,
      extractionMethod: result.extractionMethod,
      processingTimeMs: result.processingTimeMs,
      ocrTimeMs: result.ocrTimeMs,
      warnings: allWarnings
    )
  }

  // MARK: - Confidence Scoring

  private func computeAggregateConfidence(ocrResult: OcrResult) -> Double {
    var totalWeight: Double = 0
    var weightedSum: Double = 0

    for block in ocrResult.blocks {
      for line in block.lines {
        let weight = Double(line.text.count)
        weightedSum += line.confidence * weight
        totalWeight += weight
      }
    }

    guard totalWeight > 0 else { return 0.5 }
    return weightedSum / totalWeight
  }

  private func lowConfidenceWarnings(ocrResult: OcrResult) -> [String] {
    var warnings: [String] = []
    for block in ocrResult.blocks {
      for line in block.lines {
        if line.confidence < 0.7 && !line.text.isEmpty {
          let pct = Int(line.confidence * 100)
          let truncated = String(line.text.prefix(50))
          warnings.append("LOW_OCR_CONFIDENCE:\(truncated) (\(pct)%)")
        }
      }
    }
    return warnings
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

    // 7. Compute confidence from OCR quality
    let ocrConfidence = computeAggregateConfidence(ocrResult: ocrResult)
    let confidence = min(ocrConfidence, 0.90)
    let warnings = lowConfidenceWarnings(ocrResult: ocrResult)

    return DocumentExtractionResult(
      documentType: documentType == "auto" ? "invoice" : documentType,
      data: jsonString,
      rawText: ocrText,
      confidence: confidence,
      extractionMethod: "local_llm",
      processingTimeMs: elapsed,
      ocrTimeMs: ocrTimeMs,
      warnings: warnings
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
    let resolvedType = (documentType == "auto") ? "invoice" : documentType
    let data: [String: Any] = ["_documentType": resolvedType, "content": ["lines": lines]]
    let jsonString = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]))
      .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

    // Compute confidence from OCR quality, scaled down for fallback mode
    let ocrConfidence = computeAggregateConfidence(ocrResult: ocrResult)
    let confidence = ocrConfidence * 0.3
    var warnings = ["Use Mistral mode for structured extraction."]
    warnings.append(contentsOf: lowConfidenceWarnings(ocrResult: ocrResult))

    return DocumentExtractionResult(
      documentType: resolvedType,
      data: jsonString,
      rawText: ocrText,
      confidence: confidence,
      extractionMethod: "ocr_only",
      processingTimeMs: elapsed,
      ocrTimeMs: ocrTimeMs,
      warnings: warnings
    )
  }
}
