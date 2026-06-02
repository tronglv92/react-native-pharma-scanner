import Foundation
import NitroModules

/// Converts `StructuredDocumentResult` into document-type-specific JSON strings.
/// Replaces `TemplateExtractor` for the structured OCR path, leveraging cell-level
/// table data, pre-extracted key-value pairs, and detected entities instead of regex
/// parsing of flat text.
final class StructuredJsonBuilder {

  // MARK: - Public API

  /// Build a JSON string from structured document data.
  /// - Parameters:
  ///   - result: The structured document result from `DocumentOcrProcessor.recognizeStructuredDocument()`
  ///   - requestedType: The document type requested by the caller ("auto", "invoice", etc.)
  /// - Returns: A tuple of (jsonString, resolvedDocumentType, confidence)
  func buildJson(
    from result: StructuredDocumentResult,
    requestedType: String
  ) -> (jsonString: String, documentType: String, confidence: Double) {
    let resolvedType = requestedType == "auto" ? result.documentType : requestedType

    switch resolvedType {
    case "invoice":
      let json = buildInvoiceJson(from: result)
      return (json, "invoice", result.confidence)
    case "prescription":
      let json = buildPrescriptionJson(from: result)
      return (json, "prescription", result.confidence)
    case "receipt":
      let json = buildReceiptJson(from: result)
      return (json, "receipt", result.confidence)
    default:
      let json = buildGenericJson(from: result, documentType: resolvedType)
      return (json, resolvedType, result.confidence)
    }
  }

  // MARK: - Invoice Builder

  /// Maps structured data to the InvoiceData schema:
  /// seller, buyer, metadata, items (from tables), totals
  private func buildInvoiceJson(from result: StructuredDocumentResult) -> String {
    let kvPairs = result.summary.keyValuePairs
    let paragraphs = result.paragraphs
    let tables = result.tables

    // --- Seller ---
    var seller: [String: String] = [
      "companyName": "",
      "taxCode": "",
      "address": "",
      "phone": "",
      "bankAccount": ""
    ]

    // Company name: look in top paragraphs for "CONG TY" pattern, or kv pairs
    seller["companyName"] = kvLookup(
      ["don vi ban hang", "nguoi ban", "seller", "cong ty"],
      in: kvPairs
    )
    if seller["companyName"]!.isEmpty {
      // Check top paragraphs for company name
      for p in paragraphs where p.position == "top" {
        let norm = normVi(p.text)
        if norm.contains("cong ty") || norm.contains("cty") {
          // Extract the company name line
          let lines = p.text.components(separatedBy: "\n")
          for line in lines {
            let lineNorm = normVi(line)
            if lineNorm.contains("cong ty") || lineNorm.contains("cty") {
              seller["companyName"] = line.trimmingCharacters(in: .whitespaces)
              break
            }
          }
          if !seller["companyName"]!.isEmpty { break }
        }
      }
    }

    seller["taxCode"] = kvLookup(
      ["ma so thue", "so thue", "tax code", "tax id", "mst"],
      in: kvPairs
    )
    // Fallback: find 10-14 digit number in identifiers
    if seller["taxCode"]!.isEmpty {
      for id in result.summary.identifiers {
        let digits = id.filter { $0.isNumber }
        if digits.count >= 10 && digits.count <= 14 {
          seller["taxCode"] = id
          break
        }
      }
    }

    seller["address"] = kvLookup(
      ["dia chi", "address", "d/c"],
      in: kvPairs
    )
    seller["phone"] = kvLookup(
      ["dien thoai", "dt", "tel", "phone", "so dien thoai"],
      in: kvPairs
    )
    // Fallback: use phone entity
    if seller["phone"]!.isEmpty {
      for entity in result.detectedEntities where entity.type == "phone" {
        seller["phone"] = entity.value
        break
      }
    }
    seller["bankAccount"] = kvLookup(
      ["so tai khoan", "bank account", "stk"],
      in: kvPairs
    )

    // --- Buyer ---
    var buyer: [String: String] = [
      "companyName": "",
      "taxCode": "",
      "address": ""
    ]

    buyer["companyName"] = kvLookup(
      ["nguoi mua", "buyer", "ben mua", "khach hang", "ten don vi", "ho ten nguoi mua"],
      in: kvPairs
    )
    // Buyer tax code: look for second tax code occurrence
    let buyerTaxKeys = ["ma so thue", "tax code", "mst"]
    let allTaxKvs = kvPairs.filter { kv in
      let norm = normVi(kv.key)
      return buyerTaxKeys.contains(where: { norm.contains($0) })
    }
    if allTaxKvs.count >= 2 {
      buyer["taxCode"] = allTaxKvs[1].value
    } else {
      // Try looking for buyer-specific tax label
      buyer["taxCode"] = kvLookup(
        ["ma so thue nguoi mua", "mst nguoi mua"],
        in: kvPairs
      )
    }

    buyer["address"] = kvLookupAfter(
      ["dia chi", "address"],
      after: ["nguoi mua", "buyer", "ben mua"],
      in: kvPairs
    )

    // --- Metadata ---
    var metadata: [String: String] = [
      "serial": "",
      "number": "",
      "date": "",
      "form": ""
    ]

    metadata["serial"] = kvLookup(["ky hieu", "serial"], in: kvPairs)
    metadata["number"] = kvLookup(["so", "number", "so hoa don"], in: kvPairs)
    metadata["form"] = kvLookup(["mau so", "form"], in: kvPairs)

    // Date: prefer summary.dates, then kv pair
    if let firstDate = result.summary.dates.first {
      metadata["date"] = firstDate
    } else {
      metadata["date"] = kvLookup(["ngay", "date"], in: kvPairs)
    }

    // --- Items (from tables) ---
    var items: [[String: Any]] = []

    let invoiceColumnAliases: [String: [String]] = [
      "stt": ["stt", "no", "tt", "#"],
      "productName": ["ten hang", "ten hang hoa", "name of goods", "description", "ten san pham", "dien giai", "noi dung"],
      "lotNumber": ["so lo", "lot", "lot number", "lo"],
      "expiryDate": ["han dung", "han su dung", "expiry", "exp", "hsd"],
      "unit": ["dvt", "don vi tinh", "unit", "don vi"],
      "quantity": ["so luong", "quantity", "sl", "s.l"],
      "unitPrice": ["don gia", "unit price", "gia"],
      "amount": ["thanh tien", "amount", "total", "tien"]
    ]

    let mappedItems = mapTableToItems(tables, columnAliases: invoiceColumnAliases)
    for (index, row) in mappedItems.enumerated() {
      var item: [String: Any] = [
        "stt": row["stt"].flatMap { Int($0) } ?? (index + 1),
        "productName": row["productName"] ?? "",
        "lotNumber": row["lotNumber"] ?? "",
        "expiryDate": row["expiryDate"] ?? "",
        "unit": row["unit"] ?? "",
        "quantity": row["quantity"].flatMap { parseVietnameseNumber($0) } ?? 0.0,
        "unitPrice": row["unitPrice"].flatMap { parseVietnameseNumber($0) } ?? 0.0,
        "amount": row["amount"].flatMap { parseVietnameseNumber($0) } ?? 0.0
      ]
      // Skip empty rows (no product name and no amount)
      let name = item["productName"] as? String ?? ""
      let amount = item["amount"] as? Double ?? 0.0
      if name.isEmpty && amount == 0.0 { continue }
      items.append(item)
    }

    // --- Totals ---
    var totals: [String: Any] = [
      "subtotal": 0.0,
      "vatRate": 0.0,
      "vatAmount": 0.0,
      "totalPayment": 0.0,
      "amountInWords": ""
    ]

    // From key-value pairs
    let subtotalStr = kvLookup(
      ["cong tien hang", "cong tien", "total amount", "net worth"],
      in: kvPairs
    )
    if !subtotalStr.isEmpty {
      totals["subtotal"] = parseVietnameseNumber(subtotalStr)
    }

    let vatRateStr = kvLookup(
      ["thue suat", "vat rate", "thue suat gtgt"],
      in: kvPairs
    )
    if !vatRateStr.isEmpty {
      // Extract percentage number
      if let regex = try? NSRegularExpression(pattern: #"(\d+)"#),
         let match = regex.firstMatch(in: vatRateStr, range: NSRange(vatRateStr.startIndex..., in: vatRateStr)),
         let range = Range(match.range(at: 1), in: vatRateStr),
         let val = Double(String(vatRateStr[range])) {
        totals["vatRate"] = val
      }
    }

    let vatAmountStr = kvLookup(
      ["tien thue", "vat amount", "tien thue gtgt"],
      in: kvPairs
    )
    if !vatAmountStr.isEmpty {
      totals["vatAmount"] = parseVietnameseNumber(vatAmountStr)
    }

    let totalPaymentStr = kvLookup(
      ["tong tien thanh toan", "tong cong", "tong tien", "gross worth", "total payment"],
      in: kvPairs
    )
    if !totalPaymentStr.isEmpty {
      totals["totalPayment"] = parseVietnameseNumber(totalPaymentStr)
    }

    // Fallback: use money entities for totals — pick the largest as totalPayment
    if (totals["totalPayment"] as? Double ?? 0) == 0 && !result.summary.moneyAmounts.isEmpty {
      let amounts = result.summary.moneyAmounts.map { parseVietnameseNumber($0) }
      if let maxAmount = amounts.max(), maxAmount > 0 {
        totals["totalPayment"] = maxAmount
      }
    }

    totals["amountInWords"] = kvLookup(
      ["bang chu", "so tien viet bang chu", "amount in words"],
      in: kvPairs
    )

    // --- Assemble ---
    let data: [String: Any] = [
      "seller": seller,
      "buyer": buyer,
      "metadata": metadata,
      "items": items,
      "totals": totals
    ]
    return toJSONString(data)
  }

  // MARK: - Prescription Builder

  /// Maps structured data to the PrescriptionData schema:
  /// patient, doctor, medications (from tables or paragraphs), date
  private func buildPrescriptionJson(from result: StructuredDocumentResult) -> String {
    let kvPairs = result.summary.keyValuePairs

    // --- Patient ---
    var patient: [String: String] = [
      "name": "",
      "age": "",
      "gender": "",
      "address": "",
      "diagnosis": ""
    ]

    patient["name"] = kvLookup(
      ["ho ten", "benh nhan", "patient", "ho va ten"],
      in: kvPairs
    )
    patient["age"] = kvLookup(["tuoi", "age"], in: kvPairs)
    patient["gender"] = kvLookup(["gioi tinh", "gender", "gioi"], in: kvPairs)
    patient["address"] = kvLookup(["dia chi", "address"], in: kvPairs)
    patient["diagnosis"] = kvLookup(["chan doan", "diagnosis", "cd"], in: kvPairs)

    // --- Doctor ---
    var doctor: [String: String] = [
      "name": "",
      "department": "",
      "hospital": ""
    ]

    doctor["name"] = kvLookup(["bac si", "doctor", "bs"], in: kvPairs)
    doctor["department"] = kvLookup(["khoa", "department"], in: kvPairs)
    doctor["hospital"] = kvLookup(["benh vien", "hospital", "phong kham", "co so kham"], in: kvPairs)

    // Fallback: look for hospital name in top paragraphs
    if doctor["hospital"]!.isEmpty {
      for p in result.paragraphs where p.position == "top" {
        let norm = normVi(p.text)
        if norm.contains("benh vien") || norm.contains("phong kham") {
          doctor["hospital"] = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
          break
        }
      }
    }

    // --- Medications (from tables if available) ---
    var medications: [[String: String]] = []

    let medColumnAliases: [String: [String]] = [
      "name": ["ten thuoc", "thuoc", "medication", "drug", "name", "ten", "noi dung"],
      "dosage": ["lieu dung", "dosage", "lieu", "ham luong", "cach dung"],
      "quantity": ["so luong", "quantity", "sl", "so lo"],
      "instructions": ["huong dan", "instructions", "cach dung", "ghi chu", "note"]
    ]

    let mappedMeds = mapTableToItems(result.tables, columnAliases: medColumnAliases)
    if !mappedMeds.isEmpty {
      for row in mappedMeds {
        let name = row["name"] ?? ""
        if name.isEmpty { continue }
        medications.append([
          "name": name,
          "dosage": row["dosage"] ?? "",
          "quantity": row["quantity"] ?? "",
          "instructions": row["instructions"] ?? ""
        ])
      }
    }

    // Date
    let date = result.summary.dates.first ?? kvLookup(["ngay", "date"], in: kvPairs)

    // --- Assemble ---
    let data: [String: Any] = [
      "patient": patient,
      "doctor": doctor,
      "medications": medications,
      "date": date,
      "notes": kvLookup(["ghi chu", "notes", "luu y"], in: kvPairs)
    ]
    return toJSONString(data)
  }

  // MARK: - Receipt Builder

  /// Maps structured data to the ReceiptData schema:
  /// vendor, items (from tables), totals
  private func buildReceiptJson(from result: StructuredDocumentResult) -> String {
    let kvPairs = result.summary.keyValuePairs

    // --- Vendor ---
    var vendor: [String: String] = [
      "name": "",
      "address": "",
      "phone": ""
    ]

    vendor["name"] = kvLookup(
      ["cua hang", "vendor", "seller", "don vi", "ten cua hang"],
      in: kvPairs
    )
    // Fallback: first top-position paragraph as vendor name
    if vendor["name"]!.isEmpty {
      for p in result.paragraphs where p.position == "top" {
        let text = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          // Take the first line of the first top paragraph
          vendor["name"] = text.components(separatedBy: "\n").first ?? text
          break
        }
      }
    }

    vendor["address"] = kvLookup(["dia chi", "address"], in: kvPairs)
    vendor["phone"] = kvLookup(["dien thoai", "phone", "tel", "dt"], in: kvPairs)
    if vendor["phone"]!.isEmpty {
      for entity in result.detectedEntities where entity.type == "phone" {
        vendor["phone"] = entity.value
        break
      }
    }

    // --- Items (from tables) ---
    var items: [[String: Any]] = []

    let receiptColumnAliases: [String: [String]] = [
      "name": ["ten", "ten hang", "name", "description", "san pham", "noi dung", "mat hang"],
      "quantity": ["so luong", "quantity", "sl"],
      "unitPrice": ["don gia", "unit price", "gia"],
      "amount": ["thanh tien", "amount", "total", "tien", "tong"]
    ]

    let mappedItems = mapTableToItems(result.tables, columnAliases: receiptColumnAliases)
    for row in mappedItems {
      let name = row["name"] ?? ""
      if name.isEmpty { continue }
      items.append([
        "name": name,
        "quantity": row["quantity"].flatMap { parseVietnameseNumber($0) } ?? 0.0,
        "unitPrice": row["unitPrice"].flatMap { parseVietnameseNumber($0) } ?? 0.0,
        "amount": row["amount"].flatMap { parseVietnameseNumber($0) } ?? 0.0
      ])
    }

    // --- Totals ---
    let subtotalStr = kvLookup(["cong", "subtotal", "tam tinh"], in: kvPairs)
    let subtotal = subtotalStr.isEmpty ? 0.0 : parseVietnameseNumber(subtotalStr)

    let taxStr = kvLookup(["thue", "tax", "vat"], in: kvPairs)
    let tax = taxStr.isEmpty ? 0.0 : parseVietnameseNumber(taxStr)

    var total = 0.0
    let totalStr = kvLookup(["tong", "total", "tong cong", "tong tien"], in: kvPairs)
    if !totalStr.isEmpty {
      total = parseVietnameseNumber(totalStr)
    }
    // Fallback: use largest money entity
    if total == 0 && !result.summary.moneyAmounts.isEmpty {
      let amounts = result.summary.moneyAmounts.map { parseVietnameseNumber($0) }
      total = amounts.max() ?? 0
    }

    // Date
    let date = result.summary.dates.first ?? kvLookup(["ngay", "date"], in: kvPairs)

    // --- Assemble ---
    let data: [String: Any] = [
      "vendor": vendor,
      "date": date,
      "receiptNumber": kvLookup(["so", "receipt no", "so phieu", "ma phieu"], in: kvPairs),
      "items": items,
      "subtotal": subtotal,
      "tax": tax,
      "total": total,
      "paymentMethod": kvLookup(["hinh thuc thanh toan", "payment method", "thanh toan"], in: kvPairs)
    ]
    return toJSONString(data)
  }

  // MARK: - Generic Builder

  /// Structured dump for unknown or unsupported document types.
  private func buildGenericJson(from result: StructuredDocumentResult, documentType: String) -> String {
    // Key-value pairs as dictionary
    var kvDict: [String: String] = [:]
    for kv in result.summary.keyValuePairs {
      kvDict[kv.key] = kv.value
    }

    // Tables as array of 2D string arrays
    var tablesArray: [[[String]]] = []
    for table in result.tables {
      var tableData: [[String]] = []
      for row in table.rows {
        tableData.append(row.cells.map { String($0) })
      }
      tablesArray.append(tableData)
    }

    // Entities grouped by type
    var entities: [String: [String]] = ["money": [], "dates": [], "phones": [], "emails": []]
    for entity in result.detectedEntities {
      switch entity.type {
      case "money":
        entities["money"]?.append(entity.value)
      case "date":
        entities["dates"]?.append(entity.value)
      case "phone":
        entities["phones"]?.append(entity.value)
      case "email":
        entities["emails"]?.append(entity.value)
      default:
        if entities[entity.type] == nil {
          entities[entity.type] = []
        }
        entities[entity.type]?.append(entity.value)
      }
    }

    // Paragraphs grouped by position
    var paragraphGroups: [String: [String]] = ["header": [], "body": [], "footer": []]
    for p in result.paragraphs {
      switch p.position {
      case "top":
        paragraphGroups["header"]?.append(p.text)
      case "bottom":
        paragraphGroups["footer"]?.append(p.text)
      default:
        paragraphGroups["body"]?.append(p.text)
      }
    }

    let data: [String: Any] = [
      "_documentType": documentType,
      "keyValuePairs": kvDict,
      "tables": tablesArray,
      "entities": entities,
      "barcodes": result.barcodes.map { String($0) },
      "paragraphs": paragraphGroups
    ]
    return toJSONString(data)
  }

  // MARK: - Helpers

  /// Normalize Vietnamese text for diacritic-insensitive comparison.
  private func normVi(_ text: String) -> String {
    return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
  }

  /// Check if text contains any of the given keywords (after normalization).
  private func matchesAny(_ text: String, _ keywords: [String]) -> Bool {
    let norm = normVi(text)
    return keywords.contains { norm.contains($0) }
  }

  /// Look up a value in key-value pairs by fuzzy key matching.
  /// Returns the first matching value, or empty string if none found.
  private func kvLookup(_ keywords: [String], in kvPairs: [KeyValuePair]) -> String {
    for kv in kvPairs {
      let normKey = normVi(kv.key)
      for keyword in keywords {
        if normKey.contains(keyword) {
          let value = kv.value.trimmingCharacters(in: .whitespaces)
          if !value.isEmpty { return value }
        }
      }
    }
    return ""
  }

  /// Look up a value that appears after a specific context in the kv list.
  /// Useful for finding buyer address (the "address" kv pair that comes after "buyer" kv pair).
  private func kvLookupAfter(
    _ keywords: [String],
    after contextKeywords: [String],
    in kvPairs: [KeyValuePair]
  ) -> String {
    var foundContext = false
    for kv in kvPairs {
      let normKey = normVi(kv.key)
      if !foundContext {
        for ck in contextKeywords {
          if normKey.contains(ck) {
            foundContext = true
            break
          }
        }
        continue
      }
      // After context, look for the target keyword
      for keyword in keywords {
        if normKey.contains(keyword) {
          let value = kv.value.trimmingCharacters(in: .whitespaces)
          if !value.isEmpty { return value }
        }
      }
    }
    return ""
  }

  /// Map table rows to dictionaries using column header detection.
  ///
  /// Handles different invoice templates by:
  /// 1. Trying row 0 as header first
  /// 2. If row 0 doesn't match, trying row 1 (for tables with a title/group header in row 0)
  /// 3. Trying combined row 0 + row 1 text (for multi-row headers like "Số lượng\nQuantity")
  /// 4. If no header matches at all, falling back to positional inference based on cell data types
  private func mapTableToItems(
    _ tables: [StructuredTable],
    columnAliases: [String: [String]]
  ) -> [[String: String]] {
    var allItems: [[String: String]] = []

    for table in tables {
      guard table.rows.count >= 2 else { continue }

      let (columnMap, dataStartRow) = detectColumns(
        in: table,
        columnAliases: columnAliases
      )

      guard dataStartRow < table.rows.count else { continue }

      for rowIdx in dataStartRow..<table.rows.count {
        let row = table.rows[rowIdx]
        var item: [String: String] = [:]

        for (fieldName, colIdx) in columnMap {
          if colIdx < row.cells.count {
            let cellValue = row.cells[colIdx].trimmingCharacters(in: .whitespaces)
            item[fieldName] = cellValue
          }
        }

        // Skip fully empty rows
        if item.values.allSatisfy({ $0.isEmpty }) { continue }
        allItems.append(item)
      }
    }

    return allItems
  }

  /// Detect column mapping for a table by trying multiple header strategies.
  /// Returns (columnMap, dataStartRowIndex).
  private func detectColumns(
    in table: StructuredTable,
    columnAliases: [String: [String]]
  ) -> (columnMap: [String: Int], dataStartRow: Int) {

    // Strategy 1: Row 0 as header
    let map0 = matchHeaderRow(table.rows[0].cells, columnAliases: columnAliases)
    if !map0.isEmpty {
      return (map0, 1)
    }

    // Strategy 2: Row 1 as header (row 0 might be a title row like "BẢNG KÊ HÀNG HÓA")
    if table.rows.count >= 3 {
      let map1 = matchHeaderRow(table.rows[1].cells, columnAliases: columnAliases)
      if !map1.isEmpty {
        return (map1, 2)
      }
    }

    // Strategy 3: Combined row 0 + row 1 text (multi-row headers)
    if table.rows.count >= 3 {
      let combined = combineHeaderRows(table.rows[0].cells, table.rows[1].cells)
      let mapCombined = matchHeaderRow(combined, columnAliases: columnAliases)
      if !mapCombined.isEmpty {
        return (mapCombined, 2)
      }
    }

    // Strategy 4: Positional inference from data patterns
    let positionalMap = inferColumnsFromData(table: table, columnAliases: columnAliases)
    if !positionalMap.isEmpty {
      // Use row 0 as data if we couldn't match any header
      return (positionalMap, 0)
    }

    return ([:], table.rows.count) // No mapping found
  }

  /// Try to match a single row's cells against column aliases.
  private func matchHeaderRow(
    _ cells: [String],
    columnAliases: [String: [String]]
  ) -> [String: Int] {
    var columnMap: [String: Int] = [:]
    for (colIdx, cell) in cells.enumerated() {
      let normCell = normVi(cell.trimmingCharacters(in: .whitespaces))
      guard !normCell.isEmpty else { continue }

      for (fieldName, aliases) in columnAliases {
        if columnMap[fieldName] != nil { continue }
        for alias in aliases {
          if normCell.contains(alias) {
            columnMap[fieldName] = colIdx
            break
          }
        }
      }
    }
    return columnMap
  }

  /// Combine two header rows into one by joining corresponding cells with a space.
  /// Handles multi-row headers where row 0 might have "Đơn" and row 1 has "giá".
  private func combineHeaderRows(_ row0: [String], _ row1: [String]) -> [String] {
    let count = max(row0.count, row1.count)
    var combined: [String] = []
    for i in 0..<count {
      let a = i < row0.count ? row0[i].trimmingCharacters(in: .whitespaces) : ""
      let b = i < row1.count ? row1[i].trimmingCharacters(in: .whitespaces) : ""
      if a.isEmpty { combined.append(b) }
      else if b.isEmpty { combined.append(a) }
      else { combined.append("\(a) \(b)") }
    }
    return combined
  }

  /// Infer column roles from data patterns when headers can't be matched.
  /// Looks at cell values across rows to guess: which column is names (text),
  /// which are numbers (quantity/price/amount), which are dates, etc.
  private func inferColumnsFromData(
    table: StructuredTable,
    columnAliases: [String: [String]]
  ) -> [String: Int] {
    // Sample up to 5 data rows (skip row 0 which might be an unrecognized header)
    let sampleStart = min(1, table.rows.count - 1)
    let sampleEnd = min(sampleStart + 5, table.rows.count)
    guard sampleEnd > sampleStart else { return [:] }

    let sampleRows = Array(table.rows[sampleStart..<sampleEnd])
    guard let colCount = sampleRows.first?.cells.count, colCount >= 2 else { return [:] }

    // Classify each column by what its values look like
    var colTypes: [Int: ColumnDataType] = [:]
    for colIdx in 0..<colCount {
      var numericCount = 0
      var dateCount = 0
      var textCount = 0
      var shortNumCount = 0 // 1-3 digit numbers (likely STT/sequence)

      for row in sampleRows {
        guard colIdx < row.cells.count else { continue }
        let cell = row.cells[colIdx].trimmingCharacters(in: .whitespaces)
        guard !cell.isEmpty else { continue }

        if isDateLike(cell) {
          dateCount += 1
        } else if isNumericLike(cell) {
          numericCount += 1
          let digits = cell.filter { $0.isNumber }
          if digits.count <= 3 && parseVietnameseNumber(cell) < 1000 {
            shortNumCount += 1
          }
        } else {
          textCount += 1
        }
      }

      let total = numericCount + dateCount + textCount
      guard total > 0 else { continue }

      if shortNumCount == numericCount && numericCount > 0 && numericCount == total {
        colTypes[colIdx] = .sequence
      } else if dateCount > total / 2 {
        colTypes[colIdx] = .date
      } else if numericCount > total / 2 {
        colTypes[colIdx] = .number
      } else {
        colTypes[colIdx] = .text
      }
    }

    // Map inferred types to field names based on what aliases are requested
    var columnMap: [String: Int] = [:]
    let hasField: (String) -> Bool = { columnAliases[$0] != nil }

    // STT: first sequence column
    if hasField("stt") {
      if let sttCol = colTypes.first(where: { $0.value == .sequence })?.key {
        columnMap["stt"] = sttCol
      }
    }

    // Product name: longest text column (by average cell length)
    let textCols = colTypes.filter { $0.value == .text }.map { $0.key }
    if let nameField = (hasField("productName") ? "productName" : hasField("name") ? "name" : nil) {
      if textCols.count == 1 {
        columnMap[nameField] = textCols[0]
      } else if textCols.count > 1 {
        // Pick the column with longest average text
        let best = textCols.max { a, b in
          avgCellLength(col: a, rows: sampleRows) < avgCellLength(col: b, rows: sampleRows)
        }
        if let best = best { columnMap[nameField] = best }
      }
    }

    // Date columns: expiryDate or date field
    let dateCols = colTypes.filter { $0.value == .date }.map { $0.key }
    if hasField("expiryDate"), let dateCol = dateCols.first {
      columnMap["expiryDate"] = dateCol
    }

    // Numeric columns: map to quantity, unitPrice, amount by position (left to right)
    let numCols = colTypes.filter { $0.value == .number }.map { $0.key }.sorted()
    let numericFields: [String]
    if hasField("quantity") && hasField("unitPrice") && hasField("amount") {
      numericFields = ["quantity", "unitPrice", "amount"]
    } else if hasField("quantity") && hasField("amount") {
      numericFields = ["quantity", "amount"]
    } else if hasField("unitPrice") && hasField("amount") {
      numericFields = ["unitPrice", "amount"]
    } else if hasField("amount") {
      numericFields = ["amount"]
    } else if hasField("quantity") {
      numericFields = ["quantity"]
    } else {
      numericFields = []
    }

    if numCols.count >= numericFields.count {
      // Assign from right: rightmost numeric column = amount, next = unitPrice, etc.
      let assignFrom = numCols.suffix(numericFields.count)
      for (i, colIdx) in assignFrom.enumerated() {
        columnMap[numericFields[i]] = colIdx
      }
    } else {
      // Fewer numeric columns than fields — assign what we can from right
      for (i, colIdx) in numCols.reversed().enumerated() {
        let fieldIdx = numericFields.count - 1 - i
        if fieldIdx >= 0 {
          columnMap[numericFields[fieldIdx]] = colIdx
        }
      }
    }

    // Remaining text columns: assign to unit, lotNumber, etc.
    let unmappedTextCols = textCols.filter { col in !columnMap.values.contains(col) }
    if hasField("unit"), columnMap["unit"] == nil, let unitCol = unmappedTextCols.first(where: { col in
      avgCellLength(col: col, rows: sampleRows) < 10 // units are short strings
    }) {
      columnMap["unit"] = unitCol
    }
    if hasField("lotNumber"), columnMap["lotNumber"] == nil {
      let remaining = unmappedTextCols.filter { !columnMap.values.contains($0) }
      if let lotCol = remaining.first { columnMap["lotNumber"] = lotCol }
    }

    return columnMap
  }

  private enum ColumnDataType {
    case text, number, date, sequence
  }

  private func isDateLike(_ text: String) -> Bool {
    let patterns = [
      #"^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$"#,
      #"^\d{2,4}[/-]\d{1,2}[/-]\d{1,2}$"#
    ]
    for p in patterns {
      if let regex = try? NSRegularExpression(pattern: p),
         regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
        return true
      }
    }
    return false
  }

  private func isNumericLike(_ text: String) -> Bool {
    let cleaned = text
      .replacingOccurrences(of: ".", with: "")
      .replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: " ", with: "")
      .trimmingCharacters(in: .whitespaces)
    return !cleaned.isEmpty && cleaned.allSatisfy { $0.isNumber }
  }

  private func avgCellLength(col: Int, rows: [TableRow]) -> Double {
    var total = 0
    var count = 0
    for row in rows {
      if col < row.cells.count {
        total += row.cells[col].count
        count += 1
      }
    }
    return count > 0 ? Double(total) / Double(count) : 0
  }

  /// Parse Vietnamese number format: dots for thousands, comma for decimal.
  /// e.g., "1.234.567" -> 1234567, "272,00" -> 272.0
  private func parseVietnameseNumber(_ text: String) -> Double {
    var cleaned = text.trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: " ", with: "")

    // Remove currency suffixes
    let suffixes = ["VND", "VNĐ", "đ", "d", "dong", "đồng", "$"]
    for suffix in suffixes {
      cleaned = cleaned.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
    }
    cleaned = cleaned.trimmingCharacters(in: .whitespaces)

    guard !cleaned.isEmpty else { return 0 }

    // Vietnamese: dots for thousands, comma for decimal
    if cleaned.contains(",") {
      let parts = cleaned.components(separatedBy: ",")
      if parts.count == 2 && parts[1].count <= 2 {
        // Comma is decimal separator: 272,00 -> 272.00
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
      } else {
        // Comma is thousands separator
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
      }
    } else {
      // Dots as thousands: 286.000 -> 286000
      let dotParts = cleaned.split(separator: ".")
      if dotParts.count > 1 && dotParts.dropFirst().allSatisfy({ $0.count == 3 || $0.count == 2 }) {
        cleaned = cleaned.replacingOccurrences(of: ".", with: "")
      }
    }

    return Double(cleaned) ?? 0
  }

  /// Serialize a dictionary to a JSON string.
  private func toJSONString(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
      return "{}"
    }
    return String(data: data, encoding: .utf8) ?? "{}"
  }
}
