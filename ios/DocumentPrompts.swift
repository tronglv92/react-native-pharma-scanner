import Foundation

struct DocumentPrompts {

  static func systemPrompt(language: String) -> String {
    let lang = language == "vi" ? "Vietnamese" : "English"
    return """
    You are a document data extraction specialist. Extract structured data from OCR text.
    The document is primarily in \(lang). Return ONLY valid JSON, no markdown, no explanation.
    If a field cannot be found, use empty string "" for strings, 0 for numbers, and [] for arrays.
    Be precise with numbers: preserve the exact format from the source text for amounts and codes.
    """
  }

  static func visionSystemPrompt(language: String) -> String {
    let lang = language == "vi" ? "Vietnamese" : "English"
    return """
    You are a document data extraction specialist with vision capabilities. \
    You are given an image of a document. Read the document image directly and extract structured data. \
    The document is primarily in \(lang). Return ONLY valid JSON, no markdown, no explanation. \
    If a field cannot be found, use empty string "" for strings, 0 for numbers, and [] for arrays. \
    Be precise with numbers: preserve the exact format visible in the document for amounts, codes, and tax IDs. \
    Read all text carefully, including rotated, stamped, or overlapping areas.
    """
  }

  static func visionSchemaPrompt(for documentType: String) -> String {
    let schema = schemaPrompt(for: documentType)
    // Replace OCR-specific wording with vision-specific wording
    return schema
      .replacingOccurrences(of: "from this", with: "from this document image of a")
      .replacingOccurrences(of: "from the text", with: "from the document image")
  }

  static func schemaPrompt(for documentType: String) -> String {
    switch documentType {
    case "invoice":
      return invoiceSchema
    case "prescription":
      return prescriptionSchema
    case "receipt":
      return receiptSchema
    case "purchase_order":
      return purchaseOrderSchema
    case "delivery_note":
      return deliveryNoteSchema
    case "certificate":
      return certificateSchema
    case "auto":
      return autoSchema
    default:
      return genericSchema
    }
  }

  private static let invoiceSchema = """
  Extract the following JSON structure from this invoice/hoa don:
  {
    "seller": {
      "companyName": "seller company name",
      "taxCode": "seller tax code / MST",
      "address": "seller address",
      "phone": "seller phone",
      "bankAccount": "seller bank account"
    },
    "buyer": {
      "companyName": "buyer company name",
      "taxCode": "buyer tax code / MST",
      "address": "buyer address"
    },
    "metadata": {
      "serial": "invoice serial / ky hieu",
      "number": "invoice number / so",
      "date": "invoice date DD/MM/YYYY",
      "form": "invoice form / mau so"
    },
    "items": [
      {
        "stt": 1,
        "productName": "product name",
        "lotNumber": "lot/batch number",
        "expiryDate": "expiry date",
        "unit": "unit of measure",
        "quantity": 0,
        "unitPrice": 0,
        "amount": 0
      }
    ],
    "totals": {
      "subtotal": 0,
      "vatRate": 0,
      "vatAmount": 0,
      "totalPayment": 0,
      "amountInWords": "total in words"
    }
  }
  """

  private static let prescriptionSchema = """
  Extract the following JSON structure from this prescription/don thuoc:
  {
    "patient": {
      "name": "patient name",
      "age": "patient age",
      "gender": "patient gender",
      "address": "patient address",
      "diagnosis": "diagnosis"
    },
    "doctor": {
      "name": "doctor name",
      "department": "department",
      "hospital": "hospital/clinic name"
    },
    "medications": [
      {
        "name": "medication name",
        "dosage": "dosage information",
        "quantity": "quantity prescribed",
        "instructions": "usage instructions"
      }
    ],
    "date": "prescription date DD/MM/YYYY",
    "notes": "additional notes"
  }
  """

  private static let receiptSchema = """
  Extract the following JSON structure from this receipt/phieu thu:
  {
    "vendor": {
      "name": "vendor/store name",
      "address": "vendor address",
      "phone": "vendor phone"
    },
    "date": "receipt date DD/MM/YYYY",
    "receiptNumber": "receipt number",
    "items": [
      {
        "name": "item name",
        "quantity": 0,
        "unitPrice": 0,
        "amount": 0
      }
    ],
    "subtotal": 0,
    "tax": 0,
    "total": 0,
    "paymentMethod": "payment method"
  }
  """

  private static let purchaseOrderSchema = """
  Extract the following JSON structure from this purchase order/don dat hang:
  {
    "orderNumber": "order number",
    "date": "order date DD/MM/YYYY",
    "supplier": {
      "name": "supplier name",
      "address": "supplier address",
      "phone": "supplier phone"
    },
    "buyer": {
      "name": "buyer name",
      "address": "buyer address",
      "phone": "buyer phone"
    },
    "items": [
      {
        "name": "item name",
        "quantity": 0,
        "unitPrice": 0,
        "amount": 0,
        "unit": "unit of measure"
      }
    ],
    "totalAmount": 0,
    "notes": "additional notes"
  }
  """

  private static let deliveryNoteSchema = """
  Extract the following JSON structure from this delivery note/phieu giao hang:
  {
    "deliveryNumber": "delivery note number",
    "date": "delivery date DD/MM/YYYY",
    "sender": {
      "name": "sender name",
      "address": "sender address"
    },
    "receiver": {
      "name": "receiver name",
      "address": "receiver address"
    },
    "items": [
      {
        "name": "item name",
        "quantity": 0,
        "unit": "unit of measure",
        "lotNumber": "lot/batch number",
        "expiryDate": "expiry date"
      }
    ],
    "notes": "additional notes"
  }
  """

  private static let certificateSchema = """
  Extract the following JSON structure from this certificate/giay chung nhan:
  {
    "type": "certificate type",
    "certificateNumber": "certificate number",
    "issuedTo": "issued to (person or organization)",
    "issuedBy": "issuing authority",
    "issueDate": "issue date DD/MM/YYYY",
    "expiryDate": "expiry date DD/MM/YYYY",
    "details": "key details or description"
  }
  """

  private static let autoSchema = """
  First detect the document type, then extract structured data.
  Return JSON with a "_documentType" field set to one of: "invoice", "prescription", "receipt", "purchase_order", "delivery_note", "certificate", "unknown".
  Then include all extracted fields appropriate for that document type.
  For invoice: include seller, buyer, metadata, items, totals.
  For prescription: include patient, doctor, medications, date, notes.
  For receipt: include vendor, date, receiptNumber, items, subtotal, tax, total, paymentMethod.
  For purchase_order: include orderNumber, date, supplier, buyer, items, totalAmount, notes.
  For delivery_note: include deliveryNumber, date, sender, receiver, items, notes.
  For certificate: include type, certificateNumber, issuedTo, issuedBy, issueDate, expiryDate, details.
  For unknown: include a "content" field with key-value pairs extracted from the text.
  """

  private static let genericSchema = """
  Extract all identifiable structured data from this document as JSON.
  Return a JSON object with a "_documentType" field set to "unknown" and a "content" object
  containing key-value pairs of any information you can identify (names, dates, numbers, addresses, etc).
  """
}
