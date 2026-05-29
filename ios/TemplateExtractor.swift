import Foundation
import NitroModules

final class TemplateExtractor {

  struct Result {
    let jsonString: String
    let documentType: String
    let confidence: Double
  }

  func extract(ocrText: String, documentType: String, language: String) -> Result {
    let effectiveType = documentType == "auto" ? detectDocumentType(ocrText: ocrText) : documentType

    switch effectiveType {
    case "invoice":
      return extractInvoice(ocrText: ocrText)
    case "prescription":
      return extractPrescription(ocrText: ocrText)
    case "receipt":
      return extractReceipt(ocrText: ocrText)
    default:
      return extractGeneric(ocrText: ocrText, documentType: effectiveType)
    }
  }

  // MARK: - Auto-detect document type

  func detectDocumentType(ocrText: String) -> String {
    let lower = ocrText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))

    let invoiceKeywords = ["hoa don", "hóa đơn", "invoice", "mst", "ma so thue", "gtgt", "vat", "gia tri gia tang", "tax code"]
    let prescriptionKeywords = ["don thuoc", "đơn thuốc", "prescription", "benh nhan", "bệnh nhân", "chan doan", "chẩn đoán"]
    let receiptKeywords = ["phieu thu", "phiếu thu", "receipt", "bien lai", "biên lai"]
    let purchaseOrderKeywords = ["don dat hang", "đơn đặt hàng", "purchase order", "po number"]
    let deliveryKeywords = ["phieu giao", "phiếu giao", "delivery note", "phieu xuat", "phiếu xuất"]
    let certificateKeywords = ["giay chung nhan", "giấy chứng nhận", "certificate", "chung chi", "chứng chỉ"]

    let scores: [(String, Int)] = [
      ("invoice", invoiceKeywords.filter { lower.contains($0) }.count),
      ("prescription", prescriptionKeywords.filter { lower.contains($0) }.count),
      ("receipt", receiptKeywords.filter { lower.contains($0) }.count),
      ("purchase_order", purchaseOrderKeywords.filter { lower.contains($0) }.count),
      ("delivery_note", deliveryKeywords.filter { lower.contains($0) }.count),
      ("certificate", certificateKeywords.filter { lower.contains($0) }.count),
    ]

    let best = scores.max(by: { $0.1 < $1.1 })
    return (best?.1 ?? 0) > 0 ? best!.0 : "unknown"
  }

  // MARK: - Invoice template

  private func extractInvoice(ocrText: String) -> Result {
    let lines = ocrText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    var data: [String: Any] = [:]

    // Find section boundaries
    let buyerStartIdx = findLineIndex(lines: lines, keywords: ["nguoi mua", "nguoi thua", "buyer", "ben mua", "khach hang"])
    let tableStartIdx = findLineIndex(lines: lines, keywords: ["ten hang hoa", "name of goods", "stt"])
    let totalsStartIdx = findLineIndex(lines: lines, keywords: ["cong tien hang", "total amount"])

    // --- SELLER (from start to buyer section) ---
    let sellerEnd = buyerStartIdx ?? tableStartIdx ?? lines.count
    var seller: [String: String] = ["companyName": "", "taxCode": "", "address": "", "phone": "", "bankAccount": ""]

    for i in 0..<sellerEnd {
      let line = lines[i]
      let norm = normVi(line)

      // Company name: look for CONG TY ... (but not just "CONG TY" alone)
      if seller["companyName"]!.isEmpty && (norm.contains("cong ty") || norm.contains("cty")) {
        // Try to build full company name from this line + potentially next lines
        let name = extractCompanyName(line: line, lines: lines, index: i)
        if !name.isEmpty { seller["companyName"] = name }
      }

      // Tax code: various OCR garbling of "Mã số thuế" / "Tax code"
      if seller["taxCode"]!.isEmpty && matchesAny(norm, ["ma so thue", "so thue", "tax code", "tareodo", "thuc ("]) {
        seller["taxCode"] = findTaxCode(line: line, lines: lines, index: i)
      }

      // Address
      if seller["address"]!.isEmpty && matchesAny(norm, ["dia chi", "d/c", "addrs", "address"]) {
        seller["address"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }

      // Phone
      if seller["phone"]!.isEmpty && matchesAny(norm, ["dien thoai", "dt:", "tel"]) {
        seller["phone"] = extractPattern(from: line, pattern: "((?:0|\\+84)\\d[\\d\\s\\.\\-]{7,12})") ?? ""
      }

      // Bank account
      if seller["bankAccount"]!.isEmpty && matchesAny(norm, ["so tai khoan", "so ti khoan", "bank account", "banh wcoon"]) {
        let val = extractValueAfterColon(line: line, lines: lines, index: i)
        if !val.isEmpty { seller["bankAccount"] = val }
      }
    }
    data["seller"] = seller

    // --- BUYER (from buyer section to table/totals) ---
    var buyer: [String: String] = ["companyName": "", "taxCode": "", "address": ""]
    let buyerEnd = tableStartIdx ?? totalsStartIdx ?? lines.count

    if let bStart = buyerStartIdx {
      for i in bStart..<buyerEnd {
        let line = lines[i]
        let norm = normVi(line)

        // Buyer company name from "Ho ten nguoi mua hang" line itself or "Ten don vi" line
        if buyer["companyName"]!.isEmpty {
          if matchesAny(norm, ["nguoi mua", "nguoi thua", "buyer"]) {
            let val = extractValueAfterColon(line: line, lines: lines, index: i)
            if !val.isEmpty { buyer["companyName"] = val }
          }
          if matchesAny(norm, ["ten don vi", "company", "conynnyl name", "don vi mua"]) {
            let val = extractValueAfterColon(line: line, lines: lines, index: i)
            if !val.isEmpty { buyer["companyName"] = val }
          }
        }

        // Buyer tax code
        if buyer["taxCode"]!.isEmpty && matchesAny(norm, ["ma so thue", "mi so thue", "so thue", "tax code", "tm code"]) {
          buyer["taxCode"] = findTaxCode(line: line, lines: lines, index: i)
        }

        // Buyer address
        if buyer["address"]!.isEmpty && matchesAny(norm, ["dia chi", "d/c", "addrs", "address", "dudr"]) {
          buyer["address"] = extractValueAfterColon(line: line, lines: lines, index: i)
        }
      }
    }
    data["buyer"] = buyer

    // --- METADATA ---
    var metadata: [String: String] = ["serial": "", "number": "", "date": "", "form": ""]

    for (i, line) in lines.enumerated() {
      let norm = normVi(line)

      if metadata["serial"]!.isEmpty && matchesAny(norm, ["ky hieu", "serial", "seriul"]) {
        let val = extractValueAfterColon(line: line, lines: lines, index: i)
        if !val.isEmpty { metadata["serial"] = val }
      }
      if metadata["form"]!.isEmpty && matchesAny(norm, ["mau so", "form"]) {
        let val = extractValueAfterColon(line: line, lines: lines, index: i)
        if !val.isEmpty { metadata["form"] = val }
      }
      if metadata["number"]!.isEmpty && matchesAny(norm, ["so (no", "no.f", "so:"]) {
        let num = extractPattern(from: line, pattern: "(\\d{4,})")
        if let n = num { metadata["number"] = n }
        // Also check next line
        if metadata["number"]!.isEmpty, i + 1 < lines.count {
          let nextNum = extractPattern(from: lines[i + 1], pattern: "^(\\d{4,})")
          if let n = nextNum { metadata["number"] = n }
        }
      }
    }

    // Date: try "ngay ... thang ... nam ..." first, then DD/MM/YYYY
    let fullText = ocrText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    if let dateMatch = extractDateFromVietnamese(fullText) {
      metadata["date"] = dateMatch
    } else {
      metadata["date"] = extractPattern(from: ocrText, pattern: "(\\d{1,2}/\\d{1,2}/\\d{4})") ?? ""
    }

    data["metadata"] = metadata

    // --- ITEMS ---
    var items: [[String: Any]] = []

    if let tStart = tableStartIdx {
      // Find where item data begins (skip header lines)
      var dataStart = tStart + 1
      // Skip lines that are table headers (DVT, So luong, Don gia, etc.)
      while dataStart < (totalsStartIdx ?? lines.count) {
        let norm = normVi(lines[dataStart])
        if matchesAny(norm, ["name of goods", "ten hang", "so lo", "lot", "exp", "dvt", "unit", "so luong", "quan", "don gia", "unit price", "thanh tien", "amount", "(no)"]) {
          dataStart += 1
        } else {
          break
        }
      }

      // Now collect item data lines until we hit totals section
      let dataEnd = totalsStartIdx ?? lines.count
      var itemLines: [String] = []
      for i in dataStart..<dataEnd {
        let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty {
          itemLines.append(line)
        }
      }

      if !itemLines.isEmpty {
        // Parse collected item lines
        // The first line(s) are product name, followed by lot, expiry, quantity, price, amount
        var item: [String: Any] = [
          "stt": 1,
          "productName": "",
          "lotNumber": "",
          "expiryDate": "",
          "unit": "",
          "quantity": 0.0,
          "unitPrice": 0.0,
          "amount": 0.0
        ]

        // Build product name from non-numeric lines at the start
        var productNameParts: [String] = []
        var numericStartIdx = 0

        for (idx, il) in itemLines.enumerated() {
          let trimmed = il.trimmingCharacters(in: .whitespaces)
          // If line starts with digit or is a pure number, stop collecting name
          if trimmed.first?.isNumber == true || isNumericLine(trimmed) {
            numericStartIdx = idx
            break
          }
          // Check for STT number at start (like "1" for item #1)
          if let sttMatch = extractPattern(from: trimmed, pattern: "^(\\d+)\\s+(.+)"), sttMatch.count <= 3 {
            // This might be "1  Product Name"
            let rest = extractPattern(from: trimmed, pattern: "^\\d+\\s+(.+)")
            if let r = rest { productNameParts.append(r) }
          } else {
            productNameParts.append(trimmed)
          }
          numericStartIdx = idx + 1
        }
        item["productName"] = productNameParts.joined(separator: " ")

        // Extract numeric values from remaining lines
        var numericValues: [String] = []
        for idx in numericStartIdx..<itemLines.count {
          let line = itemLines[idx]
          // Check if it's a date (lot expiry)
          if let _ = extractPattern(from: line, pattern: "\\d{2}/\\d{2}/\\d{4}") {
            item["expiryDate"] = line.trimmingCharacters(in: .whitespaces)
          } else if isNumericLine(line) {
            numericValues.append(line.trimmingCharacters(in: .whitespaces))
          } else if line.count <= 10 && !line.contains(" ") {
            // Short non-numeric: could be lot number or unit
            let hasDigits = line.contains(where: { $0.isNumber })
            if hasDigits && item["lotNumber"] as? String == "" {
              item["lotNumber"] = line
            } else if !hasDigits && (item["unit"] as? String ?? "").isEmpty {
              item["unit"] = line
            } else {
              // Could be lot number
              if item["lotNumber"] as? String == "" {
                item["lotNumber"] = line
              }
            }
          }
        }

        // Assign numeric values: typically quantity, unitPrice, amount
        let parsedNumbers = numericValues.map { parseVietnameseNumber($0) }
        if parsedNumbers.count >= 3 {
          item["quantity"] = parsedNumbers[parsedNumbers.count - 3]
          item["unitPrice"] = parsedNumbers[parsedNumbers.count - 2]
          item["amount"] = parsedNumbers[parsedNumbers.count - 1]
        } else if parsedNumbers.count == 2 {
          item["unitPrice"] = parsedNumbers[0]
          item["amount"] = parsedNumbers[1]
        } else if parsedNumbers.count == 1 {
          item["amount"] = parsedNumbers[0]
        }

        items.append(item)
      }
    }
    data["items"] = items

    // --- TOTALS ---
    var totals: [String: Any] = ["subtotal": 0.0, "vatRate": 0.0, "vatAmount": 0.0, "totalPayment": 0.0, "amountInWords": ""]

    if let tIdx = totalsStartIdx {
      // Collect lines from totals section to end
      var totalsLines: [(String, String)] = [] // (normalized, original)
      for i in tIdx..<lines.count {
        let line = lines[i]
        if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          totalsLines.append((normVi(line), line))
        }
      }

      // Extract totals using label + next-line-number pattern
      for (idx, entry) in totalsLines.enumerated() {
        let (norm, original) = entry

        // Subtotal: "Cong tien hang" / "Total amount"
        if matchesAny(norm, ["cong tien hang", "cong tien", "total amount"]) && !matchesAny(norm, ["tong", "thanh toan"]) {
          let num = extractLargestNumber(from: original)
          if num > 0 {
            totals["subtotal"] = num
          } else if idx + 1 < totalsLines.count {
            let nextNum = extractLargestNumber(from: totalsLines[idx + 1].1)
            if nextNum > 0 { totals["subtotal"] = nextNum }
          }
        }

        // VAT rate
        if matchesAny(norm, ["thue suat", "vat rate", "gigt", "rat rac"]) {
          if let rate = extractPattern(from: original, pattern: "(\\d+)\\s*%"), let val = Double(rate) {
            totals["vatRate"] = val
          } else if let rate = extractPattern(from: norm, pattern: "(\\d+)\\s*%"), let val = Double(rate) {
            totals["vatRate"] = val
          }
        }

        // VAT amount: "Tien thue GTGT"
        if matchesAny(norm, ["tien thue", "vat amount", "ten duc gigt"]) {
          let num = extractLargestNumber(from: original)
          if num > 0 {
            totals["vatAmount"] = num
          } else if idx + 1 < totalsLines.count {
            let nextNum = extractLargestNumber(from: totalsLines[idx + 1].1)
            if nextNum > 0 { totals["vatAmount"] = nextNum }
          }
        }

        // Total payment: "Tong tien thanh toan"
        if matchesAny(norm, ["tong tien thanh toan", "tong cong", "toral amosu", "toral amount"]) {
          let num = extractLargestNumber(from: original)
          if num > 0 {
            totals["totalPayment"] = num
          } else if idx + 1 < totalsLines.count {
            let nextNum = extractLargestNumber(from: totalsLines[idx + 1].1)
            if nextNum > 0 { totals["totalPayment"] = nextNum }
          }
        }

        // Amount in words: "So tien viet bang chu"
        if matchesAny(norm, ["bang chu", "viet bang chu", "amorar", "amount in words"]) {
          let val = extractValueAfterColon(line: original, lines: lines, index: tIdx + idx)
          if !val.isEmpty { totals["amountInWords"] = val }
        }
      }

      // If subtotal/vatAmount/totalPayment are 0 but we have standalone numbers after labels,
      // try sequential number extraction
      if totals["subtotal"] as? Double == 0 || totals["totalPayment"] as? Double == 0 {
        var numbersAfterTotals: [Double] = []
        for i in tIdx..<lines.count {
          let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
          if isNumericLine(line) {
            numbersAfterTotals.append(parseVietnameseNumber(line))
          }
        }
        // Pattern: subtotal, vatAmount, totalPayment
        if numbersAfterTotals.count >= 3 {
          if totals["subtotal"] as? Double == 0 { totals["subtotal"] = numbersAfterTotals[0] }
          if totals["vatAmount"] as? Double == 0 { totals["vatAmount"] = numbersAfterTotals[1] }
          if totals["totalPayment"] as? Double == 0 { totals["totalPayment"] = numbersAfterTotals[2] }
        }
      }
    }
    data["totals"] = totals

    let confidence = computeInvoiceConfidence(seller: seller, buyer: buyer, metadata: metadata, totals: totals)
    let jsonString = toJSONString(data) ?? "{}"
    return Result(jsonString: jsonString, documentType: "invoice", confidence: confidence)
  }

  // MARK: - Prescription template

  private func extractPrescription(ocrText: String) -> Result {
    let lines = ocrText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    var data: [String: Any] = [:]

    var patient: [String: String] = ["name": "", "age": "", "gender": "", "address": "", "diagnosis": ""]
    var doctor: [String: String] = ["name": "", "department": "", "hospital": ""]
    var medications: [[String: String]] = []

    for (i, line) in lines.enumerated() {
      let norm = normVi(line)

      if matchesAny(norm, ["ho ten", "benh nhan", "patient"]) {
        patient["name"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
      if matchesAny(norm, ["tuoi", "age"]) {
        patient["age"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
      if matchesAny(norm, ["gioi tinh", "gender"]) {
        patient["gender"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
      if matchesAny(norm, ["chan doan", "diagnosis"]) {
        patient["diagnosis"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
      if matchesAny(norm, ["bac si", "doctor", "bs.", "bs:"]) {
        doctor["name"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
      if matchesAny(norm, ["benh vien", "hospital", "phong kham"]) {
        let val = extractValueAfterColon(line: line, lines: lines, index: i)
        doctor["hospital"] = val.isEmpty ? line : val
      }
      if matchesAny(norm, ["khoa", "department"]) {
        doctor["department"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
    }

    data["patient"] = patient
    data["doctor"] = doctor
    data["medications"] = medications
    data["date"] = extractPattern(from: ocrText, pattern: "(\\d{2}/\\d{2}/\\d{4})") ?? ""
    data["notes"] = ""

    let confidence = 0.3
    let jsonString = toJSONString(data) ?? "{}"
    return Result(jsonString: jsonString, documentType: "prescription", confidence: confidence)
  }

  // MARK: - Receipt template

  private func extractReceipt(ocrText: String) -> Result {
    let lines = ocrText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    var data: [String: Any] = [:]

    var vendor: [String: String] = ["name": "", "address": "", "phone": ""]
    if let first = lines.first, !first.isEmpty {
      vendor["name"] = first
    }
    for (i, line) in lines.enumerated() {
      let norm = normVi(line)
      if matchesAny(norm, ["dia chi", "address"]) {
        vendor["address"] = extractValueAfterColon(line: line, lines: lines, index: i)
      }
      if let phone = extractPattern(from: line, pattern: "((?:0|\\+84)\\d[\\d\\s\\.\\-]{7,12})") {
        vendor["phone"] = phone
      }
    }

    data["vendor"] = vendor
    data["date"] = extractPattern(from: ocrText, pattern: "(\\d{2}/\\d{2}/\\d{4})") ?? ""
    data["receiptNumber"] = ""
    data["items"] = [[String: Any]]()
    data["subtotal"] = 0
    data["tax"] = 0

    var total = 0.0
    for (i, line) in lines.enumerated() {
      let norm = normVi(line)
      if matchesAny(norm, ["tong", "total"]) {
        total = extractLargestNumber(from: line)
        if total == 0, i + 1 < lines.count {
          total = extractLargestNumber(from: lines[i + 1])
        }
      }
    }
    data["total"] = total
    data["paymentMethod"] = ""

    let jsonString = toJSONString(data) ?? "{}"
    return Result(jsonString: jsonString, documentType: "receipt", confidence: 0.25)
  }

  // MARK: - Generic fallback

  private func extractGeneric(ocrText: String, documentType: String) -> Result {
    let lines = ocrText.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let data: [String: Any] = [
      "_documentType": documentType,
      "content": ["lines": lines]
    ]
    let jsonString = toJSONString(data) ?? "{}"
    return Result(jsonString: jsonString, documentType: documentType, confidence: 0.2)
  }

  // MARK: - Helper: Normalize Vietnamese text

  private func normVi(_ text: String) -> String {
    return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
  }

  private func matchesAny(_ text: String, _ keywords: [String]) -> Bool {
    return keywords.contains { text.contains($0) }
  }

  // MARK: - Helper: Find line index by keywords

  private func findLineIndex(lines: [String], keywords: [String]) -> Int? {
    for (i, line) in lines.enumerated() {
      let norm = normVi(line)
      if keywords.contains(where: { norm.contains($0) }) {
        return i
      }
    }
    return nil
  }

  // MARK: - Helper: Extract company name

  private func extractCompanyName(line: String, lines: [String], index: Int) -> String {
    // Try to get full company name including continuation
    let norm = normVi(line)

    // Check if line has "CONG TY ... NAME" pattern
    if let range = line.range(of: "CÔNG TY", options: [.caseInsensitive, .diacriticInsensitive]) {
      var name = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
      // If the name seems short, check next line
      if name.count < 30 && index + 1 < lines.count {
        let nextNorm = normVi(lines[index + 1])
        // Only append if next line is NOT a keyword/label line
        if !matchesAny(nextNorm, ["ma so thue", "so thue", "tax code", "dia chi", "addrs", "dien thoai", "tel", "nguoi mua", "buyer"]) {
          let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
          if !nextLine.isEmpty && !nextLine.hasPrefix("(") {
            name = name + " " + nextLine
          }
        }
      }
      return name
    }

    return line
  }

  // MARK: - Helper: Extract tax code

  private func findTaxCode(line: String, lines: [String], index: Int) -> String {
    // Try current line
    if let code = extractPattern(from: line, pattern: "(\\d{10,14})") {
      return code
    }
    // Try next line
    if index + 1 < lines.count {
      if let code = extractPattern(from: lines[index + 1], pattern: "(\\d{10,14})") {
        return code
      }
    }
    return ""
  }

  // MARK: - Helper: Extract value after colon (or from next line)

  private func extractValueAfterColon(line: String, lines: [String], index: Int) -> String {
    // Try to get text after : or ) in the same line
    if let colonRange = line.range(of: ":", options: .backwards) {
      let after = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
      if !after.isEmpty { return after }
    }
    // Try after last )
    if let parenRange = line.range(of: ")", options: .backwards) {
      let after = line[parenRange.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
      if !after.isEmpty { return after }
    }
    // Try extractAfterKeyword style
    let keywords = [":", ";"]
    for kw in keywords {
      if let range = line.range(of: kw) {
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if !after.isEmpty { return after }
      }
    }
    // If this line is just a label, check next line
    if index + 1 < lines.count {
      let nextLine = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
      if !nextLine.isEmpty {
        let nextNorm = normVi(nextLine)
        // Don't grab the next line if it's another label
        if !matchesAny(nextNorm, ["ma so", "so thue", "tax", "dia chi", "address", "dien thoai", "tel", "nguoi", "buyer", "seller", "ten don vi", "hinh thuc", "can cuoc", "ky hieu", "serial"]) {
          return nextLine
        }
      }
    }
    return ""
  }

  // MARK: - Helper: Vietnamese date

  private func extractDateFromVietnamese(_ text: String) -> String? {
    // Match "ngay DD thang MM nam YYYY" (with garbled OCR)
    guard let regex = try? NSRegularExpression(pattern: "(?:ngay|nedy|ngdy).*?(\\d{1,2}).*?(?:thang|thang).*?(\\d{1,2}).*?(?:nam|name).*?(\\d{4})", options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          match.numberOfRanges >= 4,
          let r1 = Range(match.range(at: 1), in: text),
          let r2 = Range(match.range(at: 2), in: text),
          let r3 = Range(match.range(at: 3), in: text) else { return nil }
    let day = String(text[r1])
    let month = String(text[r2])
    let year = String(text[r3])
    return "\(day)/\(month)/\(year)"
  }

  // MARK: - Helper: Check if line is a number

  private func isNumericLine(_ text: String) -> Bool {
    let cleaned = text.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: ".", with: "")
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: " ", with: "")
    return !cleaned.isEmpty && cleaned.allSatisfy { $0.isNumber }
  }

  // MARK: - Helper: Parse Vietnamese number

  private func parseVietnameseNumber(_ text: String) -> Double {
    var cleaned = text.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: " ", with: "")

    // Vietnamese: dots for thousands, comma for decimal
    if cleaned.contains(",") {
      let parts = cleaned.components(separatedBy: ",")
      if parts.count == 2 && parts[1].count <= 2 {
        // Comma is decimal separator: 272,00 -> 272.00
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
      } else {
        // Comma might be thousands separator
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
      }
    } else {
      // Dots as thousands: 286.000.00 -> 28600000 or 286.000 -> 286000
      let dotParts = cleaned.split(separator: ".")
      if dotParts.count > 1 && dotParts.dropFirst().allSatisfy({ $0.count == 3 || $0.count == 2 }) {
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
      }
    }

    return Double(cleaned) ?? 0
  }

  // MARK: - Helpers (original)

  private func extractPattern(from text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
      return String(text[r])
    }
    if let r = Range(match.range, in: text) {
      return String(text[r])
    }
    return nil
  }

  private func extractLargestNumber(from text: String) -> Double {
    guard let regex = try? NSRegularExpression(pattern: "[\\d][\\d.,]*[\\d]") else { return 0 }
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: range)

    var largest = 0.0
    for match in matches {
      if let r = Range(match.range, in: text) {
        let numStr = String(text[r])
        let val = parseVietnameseNumber(numStr)
        if val > largest { largest = val }
      }
    }
    return largest
  }

  private func computeInvoiceConfidence(seller: [String: String], buyer: [String: String], metadata: [String: String], totals: [String: Any]) -> Double {
    var score = 0.0
    let total = 8.0
    if !(seller["companyName"]?.isEmpty ?? true) { score += 1 }
    if !(seller["taxCode"]?.isEmpty ?? true) { score += 1 }
    if !(buyer["companyName"]?.isEmpty ?? true) { score += 1 }
    if !(buyer["taxCode"]?.isEmpty ?? true) { score += 1 }
    if !(metadata["serial"]?.isEmpty ?? true) { score += 1 }
    if !(metadata["number"]?.isEmpty ?? true) { score += 1 }
    if !(metadata["date"]?.isEmpty ?? true) { score += 1 }
    if (totals["totalPayment"] as? Double ?? 0) > 0 { score += 1 }
    return (score / total) * 0.5  // Template max confidence is 0.5
  }

  private func toJSONString(_ dict: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
