import Foundation

struct LLMExtractorError: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

final class LLMExtractor {

  struct Result {
    let jsonString: String
    let detectedDocumentType: String?
  }

  private let apiKey: String
  private let baseUrl: String
  private let model: String
  private let session: URLSession

  init(apiKey: String, baseUrl: String, model: String = "gemini-2.0-flash") {
    self.apiKey = apiKey
    self.baseUrl = baseUrl
    self.model = model
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    self.session = URLSession(configuration: config)
  }

  func extractFromImage(imageData: Data, documentType: String, language: String, customPrompt: String?) async throws -> Result {
    let urlString = "\(baseUrl)/v1beta/models/\(model):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else {
      throw LLMExtractorError(message: "Invalid URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let systemPrompt = DocumentPrompts.visionSystemPrompt(language: language)
    let schemaPrompt = DocumentPrompts.visionSchemaPrompt(for: documentType)
    let textPrompt = customPrompt?.isEmpty == false ? customPrompt! : schemaPrompt

    let base64String = imageData.base64EncodedString()

    let body: [String: Any] = [
      "system_instruction": [
        "parts": [["text": systemPrompt]]
      ],
      "contents": [
        [
          "parts": [
            [
              "inline_data": [
                "mime_type": "image/jpeg",
                "data": base64String
              ]
            ],
            ["text": textPrompt]
          ]
        ]
      ],
      "generationConfig": [
        "responseMimeType": "application/json",
        "maxOutputTokens": 4096
      ]
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMExtractorError(message: "Invalid response type")
    }

    guard httpResponse.statusCode == 200 else {
      let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
      throw LLMExtractorError(message: "Gemini Vision API error \(httpResponse.statusCode): \(errorBody)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = json["candidates"] as? [[String: Any]],
          let firstCandidate = candidates.first,
          let content = firstCandidate["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let firstPart = parts.first,
          let text = firstPart["text"] as? String else {
      throw LLMExtractorError(message: "Failed to parse Gemini Vision response")
    }

    let jsonString = extractJSON(from: text)

    guard let jsonData = jsonString.data(using: .utf8),
          let _ = try? JSONSerialization.jsonObject(with: jsonData) else {
      throw LLMExtractorError(message: "Vision LLM returned invalid JSON")
    }

    var detectedType: String? = nil
    if documentType == "auto",
       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let dt = parsed["_documentType"] as? String {
      detectedType = dt
    }

    return Result(jsonString: jsonString, detectedDocumentType: detectedType)
  }

  func extract(ocrText: String, documentType: String, language: String, customPrompt: String?) async throws -> Result {
    let urlString = "\(baseUrl)/v1beta/models/\(model):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else {
      throw LLMExtractorError(message: "Invalid URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let systemPrompt = DocumentPrompts.systemPrompt(language: language)
    let schemaPrompt = DocumentPrompts.schemaPrompt(for: documentType)

    let userContent: String
    if let customPrompt = customPrompt, !customPrompt.isEmpty {
      userContent = """
      \(customPrompt)

      OCR Text:
      \(ocrText)
      """
    } else {
      userContent = """
      \(schemaPrompt)

      OCR Text:
      \(ocrText)
      """
    }

    let body: [String: Any] = [
      "system_instruction": [
        "parts": [["text": systemPrompt]]
      ],
      "contents": [
        [
          "parts": [["text": userContent]]
        ]
      ],
      "generationConfig": [
        "responseMimeType": "application/json",
        "maxOutputTokens": 4096
      ]
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMExtractorError(message: "Invalid response type")
    }

    guard httpResponse.statusCode == 200 else {
      let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
      throw LLMExtractorError(message: "Gemini API error \(httpResponse.statusCode): \(errorBody)")
    }

    // Parse Gemini response: { candidates: [{ content: { parts: [{ text: "..." }] } }] }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = json["candidates"] as? [[String: Any]],
          let firstCandidate = candidates.first,
          let content = firstCandidate["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let firstPart = parts.first,
          let text = firstPart["text"] as? String else {
      throw LLMExtractorError(message: "Failed to parse Gemini response")
    }

    let jsonString = extractJSON(from: text)

    // Validate it's parseable JSON
    guard let jsonData = jsonString.data(using: .utf8),
          let _ = try? JSONSerialization.jsonObject(with: jsonData) else {
      throw LLMExtractorError(message: "LLM returned invalid JSON")
    }

    // Extract detected document type for auto-detect mode
    var detectedType: String? = nil
    if documentType == "auto",
       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
       let dt = parsed["_documentType"] as? String {
      detectedType = dt
    }

    return Result(jsonString: jsonString, detectedDocumentType: detectedType)
  }

  /// Extracts JSON from potential markdown code blocks
  private func extractJSON(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // If it starts with { or [, assume it's raw JSON (Gemini with responseMimeType usually returns raw JSON)
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
      return trimmed
    }

    // Try to extract from ```json ... ``` blocks
    if let jsonBlockRange = trimmed.range(of: "```json\\s*\\n", options: .regularExpression),
       let endRange = trimmed.range(of: "\\n```", options: .regularExpression, range: jsonBlockRange.upperBound..<trimmed.endIndex) {
      return String(trimmed[jsonBlockRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Try to extract from ``` ... ``` blocks
    if let startRange = trimmed.range(of: "```\\s*\\n", options: .regularExpression),
       let endRange = trimmed.range(of: "\\n```", options: .regularExpression, range: startRange.upperBound..<trimmed.endIndex) {
      return String(trimmed[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Last resort: find first { to last }
    if let start = trimmed.firstIndex(of: "{"),
       let end = trimmed.lastIndex(of: "}") {
      return String(trimmed[start...end])
    }

    return trimmed
  }
}
