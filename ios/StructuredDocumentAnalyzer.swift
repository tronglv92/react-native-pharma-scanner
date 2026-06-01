import Foundation
import NitroModules

/// Semantic analysis engine for structured document data.
/// Template-free: uses generic pattern matching, structural signals, and entity types.
class StructuredDocumentAnalyzer {

  // MARK: - Build Summary

  func buildSummary(
    paragraphs: [StructuredParagraph],
    entities: [DetectedEntity],
    rawText: String
  ) -> DocumentSummary {
    var keyValuePairs: [KeyValuePair] = []
    var moneyAmounts: [String] = []
    var dates: [String] = []
    var identifiers: [String] = []

    // Extract key-value pairs from paragraph lines using "Label: Value" pattern
    let kvPattern = try? NSRegularExpression(pattern: #"^(.+?):\s+(.+)$"#, options: .anchorsMatchLines)
    for paragraph in paragraphs {
      let lines = paragraph.text.components(separatedBy: "\n")
      for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        if let match = kvPattern?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
          if let keyRange = Range(match.range(at: 1), in: trimmed),
             let valueRange = Range(match.range(at: 2), in: trimmed) {
            let key = String(trimmed[keyRange]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[valueRange]).trimmingCharacters(in: .whitespaces)
            // Skip if key is too long (likely not a real label)
            if key.count <= 60 {
              keyValuePairs.append(KeyValuePair(key: key, value: value))
            }
          }
        }
      }
    }

    // Collect money amounts from detected entities
    for entity in entities where entity.type == "money" {
      moneyAmounts.append(entity.value)
    }

    // Collect dates from detected entities
    for entity in entities where entity.type == "date" {
      dates.append(entity.value)
    }

    // Vietnamese date regex fallback: dd/mm/yyyy or dd-mm-yyyy
    let viDatePattern = try? NSRegularExpression(pattern: #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#)
    if let viDatePattern = viDatePattern {
      let matches = viDatePattern.matches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText))
      for match in matches {
        if let range = Range(match.range(at: 1), in: rawText) {
          let dateStr = String(rawText[range])
          if !dates.contains(dateStr) {
            dates.append(dateStr)
          }
        }
      }
    }

    // Collect identifiers: tax codes (10-14 digit numbers), phone numbers from entities
    let idPattern = try? NSRegularExpression(pattern: #"\b(\d{10,14})\b"#)
    if let idPattern = idPattern {
      let matches = idPattern.matches(in: rawText, range: NSRange(rawText.startIndex..., in: rawText))
      for match in matches {
        if let range = Range(match.range(at: 1), in: rawText) {
          let id = String(rawText[range])
          if !identifiers.contains(id) {
            identifiers.append(id)
          }
        }
      }
    }

    for entity in entities where entity.type == "phone" {
      if !identifiers.contains(entity.value) {
        identifiers.append(entity.value)
      }
    }

    return DocumentSummary(
      keyValuePairs: keyValuePairs,
      moneyAmounts: moneyAmounts,
      dates: dates,
      identifiers: identifiers
    )
  }

  // MARK: - Detect Document Type

  func detectDocumentType(
    paragraphs: [StructuredParagraph],
    tables: [StructuredTable],
    entities: [DetectedEntity],
    barcodes: [String],
    rawText: String
  ) -> String {
    let textLower = rawText.lowercased()

    var invoiceScore = 0
    var prescriptionScore = 0
    var receiptScore = 0

    // Structural signals: tables with many columns + money entities -> invoice
    let hasLargeTables = tables.contains { table in
      guard let firstRow = table.rows.first else { return false }
      return firstRow.cells.count >= 3
    }
    let hasMoneyEntities = entities.contains { $0.type == "money" }

    if hasLargeTables && hasMoneyEntities {
      invoiceScore += 3
    } else if hasLargeTables {
      invoiceScore += 1
    }
    if hasMoneyEntities {
      invoiceScore += 1
      receiptScore += 1
    }

    // Keyword signals - invoice
    let invoiceKeywords = ["hoa don", "hóa đơn", "invoice", "vat", "ma so thue", "mã số thuế",
                           "don vi ban hang", "đơn vị bán hàng", "nguoi mua", "người mua"]
    for kw in invoiceKeywords {
      if textLower.contains(kw) { invoiceScore += 2 }
    }

    // Keyword signals - prescription
    let prescriptionKeywords = ["benh nhan", "bệnh nhân", "prescription", "chan doan", "chẩn đoán",
                                 "bac si", "bác sĩ", "thuoc", "thuốc", "lieu dung", "liều dùng",
                                 "don thuoc", "đơn thuốc"]
    for kw in prescriptionKeywords {
      if textLower.contains(kw) { prescriptionScore += 2 }
    }

    // Keyword signals - receipt
    let receiptKeywords = ["phieu thu", "phiếu thu", "receipt", "bien lai", "biên lai",
                           "tien mat", "tiền mặt", "thanh toan", "thanh toán"]
    for kw in receiptKeywords {
      if textLower.contains(kw) { receiptScore += 2 }
    }

    // Determine winner
    let maxScore = max(invoiceScore, prescriptionScore, receiptScore)
    guard maxScore >= 3 else { return "unknown" }

    if invoiceScore == maxScore { return "invoice" }
    if prescriptionScore == maxScore { return "prescription" }
    if receiptScore == maxScore { return "receipt" }

    return "unknown"
  }

  // MARK: - Compute Confidence

  func computeConfidence(
    paragraphs: [StructuredParagraph],
    tables: [StructuredTable],
    entities: [DetectedEntity],
    keyValuePairs: [KeyValuePair]
  ) -> Double {
    var score = 0.0
    let maxScore = 4.0

    // Paragraphs found
    if !paragraphs.isEmpty {
      score += 1.0
    }

    // Entities detected
    if !entities.isEmpty {
      score += 1.0
    }

    // Key-value pairs extracted
    if keyValuePairs.count >= 2 {
      score += 1.0
    } else if !keyValuePairs.isEmpty {
      score += 0.5
    }

    // Tables present
    if !tables.isEmpty {
      score += 1.0
    }

    return min(score / maxScore, 1.0)
  }
}
