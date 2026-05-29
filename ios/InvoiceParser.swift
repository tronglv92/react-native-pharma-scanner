import Foundation
import NitroModules

class InvoiceParser {

  // MARK: - Public

  func parse(ocrResult: OcrResult) -> InvoiceResult {
    let rawText = String(ocrResult.text)
    let lines = buildSortedLines(from: ocrResult)

    var warnings: [String] = []

    let seller = parseSeller(lines: lines, warnings: &warnings)
    let buyer = parseBuyer(lines: lines, warnings: &warnings)
    let metadata = parseMetadata(lines: lines, rawText: rawText, warnings: &warnings)
    let items = parseLineItems(lines: lines, warnings: &warnings)
    let totals = parseTotals(lines: lines, warnings: &warnings)
    let confidence = computeConfidence(seller: seller, buyer: buyer, metadata: metadata, items: items, totals: totals)

    return InvoiceResult(
      seller: seller,
      buyer: buyer,
      metadata: metadata,
      items: items,
      totals: totals,
      rawText: rawText,
      confidence: confidence,
      processingTimeMs: ocrResult.processingTimeMs,
      warnings: warnings
    )
  }

  // MARK: - Line Model

  private struct ParsedLine {
    let text: String
    let y: Double
    let x: Double
    let width: Double
    let height: Double
    let confidence: Double
  }

  // MARK: - Build sorted lines

  private func buildSortedLines(from ocrResult: OcrResult) -> [ParsedLine] {
    var result: [ParsedLine] = []
    for block in ocrResult.blocks {
      for line in block.lines {
        result.append(ParsedLine(
          text: String(line.text),
          y: line.boundingBox.y,
          x: line.boundingBox.x,
          width: line.boundingBox.width,
          height: line.boundingBox.height,
          confidence: line.confidence
        ))
      }
    }
    return result.sorted { $0.y < $1.y }
  }

  // MARK: - Normalize text for matching

  private func normalize(_ text: String) -> String {
    // Remove Vietnamese diacritics for fuzzy matching
    let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
    return folded.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Parse Vietnamese number format

  /// Parses Vietnamese number format: dots for thousands, comma for decimal
  /// e.g. "74.607.600" -> 74607600, "1.234,56" -> 1234.56
  private func parseVietnameseNumber(_ text: String) -> Double {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Remove any non-numeric chars except dots, commas, minus
    cleaned = cleaned.replacingOccurrences(of: "[^0-9.,\\-]", with: "", options: .regularExpression)

    guard !cleaned.isEmpty else { return 0 }

    // If contains comma, treat it as decimal separator (Vietnamese style)
    if cleaned.contains(",") {
      // Remove thousand separators (dots)
      cleaned = cleaned.replacingOccurrences(of: ".", with: "")
      // Replace comma with dot for Swift parsing
      cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
    } else {
      // No comma: check if dots are thousand separators
      // Pattern: digits with dots every 3 digits = thousand separators
      let dotParts = cleaned.split(separator: ".")
      if dotParts.count > 1 {
        let allGroupsThree = dotParts.dropFirst().allSatisfy { $0.count == 3 }
        if allGroupsThree {
          // Dots are thousand separators
          cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        }
        // else: single dot might be decimal
      }
    }

    return Double(cleaned) ?? 0
  }

  // MARK: - Regex helpers

  private func firstMatch(in text: String, pattern: String) -> String? {
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

  private func lineContains(_ line: ParsedLine, anyOf keywords: [String]) -> Bool {
    let norm = normalize(line.text)
    return keywords.contains { norm.contains($0) }
  }

  // MARK: - Extract value after keyword on same or next line

  private func extractValueAfterKeyword(lines: [ParsedLine], keywords: [String], fromIndex: inout Int) -> String {
    for i in fromIndex..<lines.count {
      let norm = normalize(lines[i].text)
      for kw in keywords {
        if let kwRange = norm.range(of: kw) {
          let afterKw = norm[kwRange.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
          fromIndex = i + 1
          if !afterKw.isEmpty {
            // Return the original text portion (with diacritics)
            let original = lines[i].text
            // Find the keyword position in original text (case-insensitive)
            if let origRange = original.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
              let val = original[origRange.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
              if !val.isEmpty { return val }
            }
            return afterKw
          }
          // Value might be on next line
          if i + 1 < lines.count {
            fromIndex = i + 2
            return lines[i + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
          }
        }
      }
    }
    return ""
  }

  // MARK: - Parse Seller

  private func parseSeller(lines: [ParsedLine], warnings: inout [String]) -> InvoiceSeller {
    var companyName = ""
    var taxCode = ""
    var address = ""
    var phone = ""
    var bankAccount = ""

    // Seller section is typically in the upper portion of the invoice
    // Look for MST / Ma so thue for tax code
    let taxKeywords = ["mst", "ma so thue", "mã số thuế", "ma so thue:"]
    let addressKeywords = ["dia chi", "địa chỉ", "đ/c"]
    let phoneKeywords = ["dien thoai", "điện thoại", "dt:", "đt:", "tel:", "phone:"]
    let bankKeywords = ["so tai khoan", "số tài khoản", "stk:", "tk:"]

    // Find seller company name - usually appears near the top, before MST
    // Look for "Don vi ban hang" or company name line
    let sellerNameKeywords = ["don vi ban hang", "đơn vị bán hàng", "nguoi ban", "người bán"]

    var searchIdx = 0

    // Try to find seller name via keyword
    for i in 0..<min(lines.count, 20) {
      let norm = normalize(lines[i].text)
      for kw in sellerNameKeywords {
        if norm.contains(kw) {
          let afterKw = lines[i].text
          if let range = afterKw.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
            let val = afterKw[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
            if !val.isEmpty {
              companyName = val
            } else if i + 1 < lines.count {
              companyName = lines[i + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
          }
          searchIdx = i + 1
          break
        }
      }
      if !companyName.isEmpty { break }
    }

    // If no keyword found, look for a company name pattern (CONG TY / CTY)
    if companyName.isEmpty {
      for i in 0..<min(lines.count, 15) {
        let norm = normalize(lines[i].text)
        if norm.contains("cong ty") || norm.contains("cty") || norm.contains("công ty") {
          companyName = lines[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
          searchIdx = i + 1
          break
        }
      }
    }

    // Tax code
    for i in searchIdx..<min(lines.count, 25) {
      let norm = normalize(lines[i].text)
      for kw in taxKeywords {
        if norm.contains(kw) {
          // Extract numeric tax code
          if let match = firstMatch(in: lines[i].text, pattern: "\\b(\\d[\\d\\-]{9,14})\\b") {
            taxCode = match
          } else if i + 1 < lines.count, let match = firstMatch(in: lines[i + 1].text, pattern: "\\b(\\d[\\d\\-]{9,14})\\b") {
            taxCode = match
          }
          break
        }
      }
      if !taxCode.isEmpty { break }
    }

    // Address (seller)
    var addrIdx = searchIdx
    address = extractValueAfterKeyword(lines: lines, keywords: addressKeywords, fromIndex: &addrIdx)

    // Phone
    var phoneIdx = 0
    phone = extractValueAfterKeyword(lines: lines, keywords: phoneKeywords, fromIndex: &phoneIdx)
    // Also try regex for phone pattern
    if phone.isEmpty {
      for i in 0..<min(lines.count, 25) {
        if let match = firstMatch(in: lines[i].text, pattern: "((?:0|\\+84)\\d[\\d\\s\\.\\-]{7,12})") {
          phone = match.replacingOccurrences(of: " ", with: "")
          break
        }
      }
    }

    // Bank account
    var bankIdx = 0
    bankAccount = extractValueAfterKeyword(lines: lines, keywords: bankKeywords, fromIndex: &bankIdx)

    if companyName.isEmpty { warnings.append("Could not parse seller company name") }
    if taxCode.isEmpty { warnings.append("Could not parse seller tax code") }

    return InvoiceSeller(companyName: companyName, taxCode: taxCode, address: address, phone: phone, bankAccount: bankAccount)
  }

  // MARK: - Parse Buyer

  private func parseBuyer(lines: [ParsedLine], warnings: inout [String]) -> InvoiceBuyer {
    var companyName = ""
    var taxCode = ""
    var address = ""

    let buyerNameKeywords = [
      "ten don vi", "tên đơn vị",
      "ho ten don vi", "họ tên đơn vị",
      "don vi mua", "đơn vị mua",
      "nguoi mua hang", "người mua hàng",
      "ten nguoi mua", "tên người mua",
    ]
    let buyerTaxKeywords = ["ma so thue", "mã số thuế", "mst"]
    let addressKeywords = ["dia chi", "địa chỉ", "đ/c"]

    // Find buyer section - typically after seller section
    // Look for "Nguoi mua hang" or similar header
    var buyerSectionStart = 0
    for i in 0..<lines.count {
      let norm = normalize(lines[i].text)
      if norm.contains("nguoi mua") || norm.contains("ben mua") || norm.contains("khach hang") {
        buyerSectionStart = i
        break
      }
    }

    // Buyer company name
    for i in buyerSectionStart..<lines.count {
      let norm = normalize(lines[i].text)
      for kw in buyerNameKeywords {
        if norm.contains(kw) {
          let original = lines[i].text
          if let range = original.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
            let val = original[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
            if !val.isEmpty {
              companyName = val
            } else if i + 1 < lines.count {
              companyName = lines[i + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
          }
          break
        }
      }
      if !companyName.isEmpty { break }
    }

    // Buyer tax code - find MST after buyer section start
    var foundBuyerTax = false
    // We need the second MST occurrence (first is seller's)
    var mstCount = 0
    for i in 0..<lines.count {
      let norm = normalize(lines[i].text)
      for kw in buyerTaxKeywords {
        if norm.contains(kw) {
          mstCount += 1
          if mstCount >= 2 || i >= buyerSectionStart {
            if let match = firstMatch(in: lines[i].text, pattern: "\\b(\\d[\\d\\-]{9,14})\\b") {
              taxCode = match
              foundBuyerTax = true
            } else if i + 1 < lines.count, let match = firstMatch(in: lines[i + 1].text, pattern: "\\b(\\d[\\d\\-]{9,14})\\b") {
              taxCode = match
              foundBuyerTax = true
            }
            break
          }
        }
      }
      if foundBuyerTax { break }
    }

    // Buyer address - find address after buyer section
    for i in buyerSectionStart..<lines.count {
      let norm = normalize(lines[i].text)
      for kw in addressKeywords {
        if norm.contains(kw) {
          let original = lines[i].text
          if let range = original.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
            let val = original[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
            if !val.isEmpty {
              address = val
            } else if i + 1 < lines.count {
              address = lines[i + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
          }
          break
        }
      }
      if !address.isEmpty { break }
    }

    if companyName.isEmpty { warnings.append("Could not parse buyer company name") }
    if taxCode.isEmpty { warnings.append("Could not parse buyer tax code") }

    return InvoiceBuyer(companyName: companyName, taxCode: taxCode, address: address)
  }

  // MARK: - Parse Metadata

  private func parseMetadata(lines: [ParsedLine], rawText: String, warnings: inout [String]) -> InvoiceMetadata {
    var serial = ""
    var number = ""
    var date = ""
    var form = ""

    let serialKeywords = ["ky hieu", "ký hiệu", "serial"]
    let numberKeywords = ["so:", "số:", "so :", "số :", "number"]
    let formKeywords = ["mau so", "mẫu số", "form"]

    // Serial (Ky hieu)
    for line in lines {
      let norm = normalize(line.text)
      for kw in serialKeywords {
        if norm.contains(kw) {
          let original = line.text
          if let range = original.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
            let val = original[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
            if !val.isEmpty { serial = val }
          }
          break
        }
      }
      if !serial.isEmpty { break }
    }

    // Invoice number (So)
    for line in lines {
      let norm = normalize(line.text)
      for kw in numberKeywords {
        if norm.contains(kw) {
          // Extract number pattern (digits, possibly with leading zeros)
          if let match = firstMatch(in: line.text, pattern: "(\\d{4,})") {
            number = match
          }
          break
        }
      }
      if !number.isEmpty { break }
    }

    // Form (Mau so)
    for line in lines {
      let norm = normalize(line.text)
      for kw in formKeywords {
        if norm.contains(kw) {
          let original = line.text
          if let range = original.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
            let val = original[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
            if !val.isEmpty { form = val }
          }
          break
        }
      }
      if !form.isEmpty { break }
    }

    // Date - match "Ngay ... thang ... nam ..." pattern
    if let match = firstMatch(in: rawText, pattern: "[Nn]g[aà]y\\s*(\\d{1,2})\\s*th[aá]ng\\s*(\\d{1,2})\\s*n[aă]m\\s*(\\d{4})") {
      date = match
      // Try to extract structured date
      let datePattern = "[Nn]g[aà]y\\s*(\\d{1,2})\\s*th[aá]ng\\s*(\\d{1,2})\\s*n[aă]m\\s*(\\d{4})"
      if let regex = try? NSRegularExpression(pattern: datePattern),
         let m = regex.firstMatch(in: rawText, range: NSRange(rawText.startIndex..., in: rawText)) {
        if m.numberOfRanges >= 4,
           let dayRange = Range(m.range(at: 1), in: rawText),
           let monthRange = Range(m.range(at: 2), in: rawText),
           let yearRange = Range(m.range(at: 3), in: rawText) {
          let day = String(rawText[dayRange]).padding(toLength: 2, withPad: "0", startingAt: 0)
          let month = String(rawText[monthRange]).padding(toLength: 2, withPad: "0", startingAt: 0)
          let year = String(rawText[yearRange])
          date = "\(day)/\(month)/\(year)"
        }
      }
    }

    // Fallback: look for dd/mm/yyyy pattern
    if date.isEmpty {
      if let match = firstMatch(in: rawText, pattern: "(\\d{2}/\\d{2}/\\d{4})") {
        date = match
      }
    }

    if serial.isEmpty { warnings.append("Could not parse invoice serial") }
    if number.isEmpty { warnings.append("Could not parse invoice number") }
    if date.isEmpty { warnings.append("Could not parse invoice date") }

    return InvoiceMetadata(serial: serial, number: number, date: date, form: form)
  }

  // MARK: - Parse Line Items

  private func parseLineItems(lines: [ParsedLine], warnings: inout [String]) -> [InvoiceLineItem] {
    // Find table header row containing STT, Ten hang, DVT, So luong, Don gia, Thanh tien
    let headerKeywords = ["stt", "ten hang", "tên hàng", "dvt", "đvt", "so luong", "số lượng", "don gia", "đơn giá", "thanh tien", "thành tiền"]

    var headerLineIndex = -1
    for i in 0..<lines.count {
      let norm = normalize(lines[i].text)
      let matchCount = headerKeywords.filter { norm.contains($0) }.count
      if matchCount >= 2 {
        headerLineIndex = i
        break
      }
    }

    // Also try to detect table header spread across nearby lines
    if headerLineIndex == -1 {
      for i in 0..<lines.count {
        let norm = normalize(lines[i].text)
        if norm.contains("stt") {
          // Check nearby lines for other header keywords
          let nearbyText = lines[max(0,i-1)...min(lines.count-1, i+2)].map { normalize($0.text) }.joined(separator: " ")
          let matchCount = headerKeywords.filter { nearbyText.contains($0) }.count
          if matchCount >= 3 {
            headerLineIndex = i
            break
          }
        }
      }
    }

    guard headerLineIndex >= 0 else {
      warnings.append("Could not find line items table header")
      return []
    }

    // Find the end of the table: look for "Cong tien hang" or totals section
    let totalsKeywords = ["cong tien hang", "cộng tiền hàng", "cong tien", "tong cong", "tổng cộng", "thue suat"]
    var tableEndIndex = lines.count
    for i in (headerLineIndex + 1)..<lines.count {
      let norm = normalize(lines[i].text)
      for kw in totalsKeywords {
        if norm.contains(kw) {
          tableEndIndex = i
          break
        }
      }
      if tableEndIndex < lines.count { break }
    }

    // Parse rows between header and totals
    var items: [InvoiceLineItem] = []
    var currentItem: (stt: Int, productName: String, lotNumber: String, expiryDate: String, unit: String, quantity: Double, unitPrice: Double, amount: Double)?

    for i in (headerLineIndex + 1)..<tableEndIndex {
      let text = lines[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      let norm = normalize(text)

      // Skip sub-header lines (like column numbers "1 2 3 4 5 6 7")
      if text.allSatisfy({ $0.isNumber || $0.isWhitespace }) && text.count < 20 {
        // Could be column number row, skip if it looks like sequential numbers
        let numbers = text.split(separator: " ").compactMap { Int($0) }
        if numbers.count >= 3 && numbers == Array(numbers.first!...numbers.last!) {
          continue
        }
      }

      // Try to detect if this line starts a new item (starts with STT number)
      if let sttMatch = firstMatch(in: text, pattern: "^\\s*(\\d{1,3})\\s") {
        let stt = Int(sttMatch) ?? 0

        // Save previous item
        if let prev = currentItem {
          items.append(InvoiceLineItem(
            stt: Double(prev.stt), productName: prev.productName, lotNumber: prev.lotNumber,
            expiryDate: prev.expiryDate, unit: prev.unit, quantity: prev.quantity,
            unitPrice: prev.unitPrice, amount: prev.amount
          ))
        }

        // Parse the rest of the line
        // Try to extract numbers from the end (amount, unitPrice, quantity)
        let numbersFromEnd = extractTrailingNumbers(from: text)

        // Extract product name: text between STT and the numeric values
        var productName = text
        // Remove the STT prefix
        if let range = text.range(of: "^\\s*\\d{1,3}\\s+", options: .regularExpression) {
          productName = String(text[range.upperBound...])
        }
        // Remove trailing numbers
        if numbersFromEnd.count > 0 {
          // Find where the first trailing number starts
          let numericPart = numbersFromEnd.map { formatForRemoval($0) }.joined(separator: "|")
          // Simplify: remove everything after the product name portion
          // Use the X position and bounding boxes if available, otherwise heuristic
          let parts = productName.components(separatedBy: CharacterSet.whitespaces)
          var nameEnd = parts.count
          var numericCount = 0
          for j in stride(from: parts.count - 1, through: 0, by: -1) {
            let cleaned = parts[j].replacingOccurrences(of: "[^0-9.,]", with: "", options: .regularExpression)
            if cleaned.count > 0 && Double(cleaned.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: ".", with: "")) != nil {
              numericCount += 1
              nameEnd = j
            } else {
              break
            }
          }
          if numericCount >= 2 {
            productName = parts[0..<nameEnd].joined(separator: " ")
          }
        }

        productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract lot number and expiry date from product name if present
        var lotNumber = ""
        var expiryDate = ""
        if let lotMatch = firstMatch(in: productName, pattern: "(?:Lo|Lô|lo|lô|Lot)\\s*[:\\.]?\\s*([A-Za-z0-9]+)") {
          lotNumber = lotMatch
        }
        if let expMatch = firstMatch(in: norm, pattern: "(?:hsd|hạn sử dụng|han sd|exp)[:\\s]*(\\d{1,2}[/\\-]\\d{1,2}[/\\-]\\d{2,4})") {
          expiryDate = expMatch
        }

        // Extract unit from common Vietnamese units
        var unit = ""
        let unitPatterns = ["hop", "hộp", "chai", "lo", "lọ", "ong", "ống", "vi", "vỉ", "goi", "gói", "tuýp", "tuyp", "tube", "cai", "cái", "vien", "viên"]
        for u in unitPatterns {
          if norm.contains(u) {
            unit = u
            break
          }
        }

        // Assign numbers from end: typically amount, unitPrice, quantity (right to left)
        var quantity = 0.0
        var unitPrice = 0.0
        var amount = 0.0
        if numbersFromEnd.count >= 3 {
          amount = numbersFromEnd[numbersFromEnd.count - 1]
          unitPrice = numbersFromEnd[numbersFromEnd.count - 2]
          quantity = numbersFromEnd[numbersFromEnd.count - 3]
        } else if numbersFromEnd.count == 2 {
          amount = numbersFromEnd[1]
          unitPrice = numbersFromEnd[0]
        } else if numbersFromEnd.count == 1 {
          amount = numbersFromEnd[0]
        }

        currentItem = (stt: stt, productName: productName, lotNumber: lotNumber, expiryDate: expiryDate, unit: unit, quantity: quantity, unitPrice: unitPrice, amount: amount)
      } else if currentItem != nil {
        // Continuation line - append to product name
        currentItem?.productName += " " + text

        // Try to extract lot/expiry from continuation
        if currentItem?.lotNumber.isEmpty == true {
          if let lotMatch = firstMatch(in: text, pattern: "(?:Lo|Lô|lo|lô|Lot)\\s*[:\\.]?\\s*([A-Za-z0-9]+)") {
            currentItem?.lotNumber = lotMatch
          }
        }
        if currentItem?.expiryDate.isEmpty == true {
          if let expMatch = firstMatch(in: norm, pattern: "(?:hsd|han su dung|han sd|exp)[:\\s]*(\\d{1,2}[/\\-]\\d{1,2}[/\\-]\\d{2,4})") {
            currentItem?.expiryDate = expMatch
          }
        }
      }
    }

    // Don't forget the last item
    if let prev = currentItem {
      items.append(InvoiceLineItem(
        stt: Double(prev.stt), productName: prev.productName, lotNumber: prev.lotNumber,
        expiryDate: prev.expiryDate, unit: prev.unit, quantity: prev.quantity,
        unitPrice: prev.unitPrice, amount: prev.amount
      ))
    }

    if items.isEmpty {
      warnings.append("No line items parsed from table")
    }

    return items
  }

  /// Extract trailing numbers from a text line (reading from right to left)
  private func extractTrailingNumbers(from text: String) -> [Double] {
    let parts = text.components(separatedBy: CharacterSet.whitespaces).reversed()
    var numbers: [Double] = []

    for part in parts {
      let cleaned = part.trimmingCharacters(in: .whitespaces)
      if cleaned.isEmpty { continue }
      let num = parseVietnameseNumber(cleaned)
      if num != 0 {
        numbers.insert(num, at: 0)
      } else {
        // Stop when we hit non-numeric text
        break
      }
    }
    return numbers
  }

  private func formatForRemoval(_ number: Double) -> String {
    if number == floor(number) {
      return String(Int(number))
    }
    return String(number)
  }

  // MARK: - Parse Totals

  private func parseTotals(lines: [ParsedLine], warnings: inout [String]) -> InvoiceTotals {
    var subtotal = 0.0
    var vatRate = 0.0
    var vatAmount = 0.0
    var totalPayment = 0.0
    var amountInWords = ""

    let subtotalKeywords = ["cong tien hang", "cộng tiền hàng", "cong tien", "cộng tiền"]
    let vatRateKeywords = ["thue suat gtgt", "thuế suất gtgt", "thue suat", "thuế suất", "vat rate"]
    let vatAmountKeywords = ["tien thue gtgt", "tiền thuế gtgt", "tien thue", "tiền thuế"]
    let totalKeywords = ["tong cong tien thanh toan", "tổng cộng tiền thanh toán", "tong tien thanh toan", "tổng tiền thanh toán", "tong cong", "tổng cộng"]
    let wordsKeywords = ["so tien viet bang chu", "số tiền viết bằng chữ", "bang chu", "bằng chữ"]

    for line in lines {
      let norm = normalize(line.text)

      // Subtotal
      if subtotal == 0 {
        for kw in subtotalKeywords {
          if norm.contains(kw) {
            subtotal = extractNumberFromLine(line.text)
            break
          }
        }
      }

      // VAT rate
      if vatRate == 0 {
        for kw in vatRateKeywords {
          if norm.contains(kw) {
            if let match = firstMatch(in: line.text, pattern: "(\\d+)\\s*%") {
              vatRate = Double(match) ?? 0
            }
            break
          }
        }
      }

      // VAT amount
      if vatAmount == 0 {
        for kw in vatAmountKeywords {
          if norm.contains(kw) {
            vatAmount = extractNumberFromLine(line.text)
            break
          }
        }
      }

      // Total payment
      if totalPayment == 0 {
        for kw in totalKeywords {
          if norm.contains(kw) {
            totalPayment = extractNumberFromLine(line.text)
            break
          }
        }
      }

      // Amount in words
      if amountInWords.isEmpty {
        for kw in wordsKeywords {
          if norm.contains(kw) {
            let original = line.text
            if let range = original.range(of: kw, options: [.caseInsensitive, .diacriticInsensitive]) {
              let val = original[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":;")))
              if !val.isEmpty {
                amountInWords = val
              }
            }
            break
          }
        }
      }
    }

    if totalPayment == 0 { warnings.append("Could not parse total payment") }

    return InvoiceTotals(subtotal: subtotal, vatRate: vatRate, vatAmount: vatAmount, totalPayment: totalPayment, amountInWords: amountInWords)
  }

  /// Extract the largest number from a line of text
  private func extractNumberFromLine(_ text: String) -> Double {
    let pattern = "[\\d][\\d.,]*[\\d]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: range)

    var largest = 0.0
    for match in matches {
      if let r = Range(match.range, in: text) {
        let numStr = String(text[r])
        let val = parseVietnameseNumber(numStr)
        if val > largest {
          largest = val
        }
      }
    }
    return largest
  }

  // MARK: - Confidence

  private func computeConfidence(seller: InvoiceSeller, buyer: InvoiceBuyer, metadata: InvoiceMetadata, items: [InvoiceLineItem], totals: InvoiceTotals) -> Double {
    var score = 0.0
    let totalFields = 7.0

    if !seller.taxCode.isEmpty { score += 1 }
    if !buyer.taxCode.isEmpty { score += 1 }
    if !metadata.serial.isEmpty { score += 1 }
    if !metadata.number.isEmpty { score += 1 }
    if !metadata.date.isEmpty { score += 1 }
    if !items.isEmpty { score += 1 }
    if totals.totalPayment > 0 { score += 1 }

    return score / totalFields
  }
}
