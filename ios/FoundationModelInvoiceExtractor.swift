// FoundationModelInvoiceExtractor.swift
// Extracts structured invoice data from a UIImage using Vision OCR + Apple FoundationModels.
// Requires iOS 26+, Apple Silicon (A17 Pro / M1+), Apple Intelligence enabled.

import SwiftUI
import Vision
import FoundationModels

// MARK: - @Generable Data Model

@available(iOS 26.0, *)
@Generable
struct InvoiceAddress: Codable {
  @Guide(description: "Street address line")
  var street: String

  @Guide(description: "City name")
  var city: String

  @Guide(description: "State abbreviation, e.g. IN, AZ")
  var state: String

  @Guide(description: "ZIP or postal code")
  var zip_code: String
}

@available(iOS 26.0, *)
@Generable
struct InvoiceSeller: Codable {
  @Guide(description: "Seller or company name")
  var name: String

  var address: InvoiceAddress

  @Guide(description: "Tax ID, e.g. 945-82-2137")
  var tax_id: String

  @Guide(description: "IBAN or bank account number")
  var iban: String
}

@available(iOS 26.0, *)
@Generable
struct InvoiceClient: Codable {
  @Guide(description: "Client or buyer company name")
  var name: String

  var address: InvoiceAddress

  @Guide(description: "Tax ID, e.g. 942-80-0517")
  var tax_id: String
}

@available(iOS 26.0, *)
@Generable
struct InvoiceItem: Codable {
  @Guide(description: "Line item number")
  var no: Int

  @Guide(description: "Product or service description")
  var description: String

  @Guide(description: "Quantity ordered")
  var quantity: Double

  @Guide(description: "Unit of measure, e.g. each, pcs, kg")
  var unit: String

  @Guide(description: "Net price per unit")
  var net_price: Double

  @Guide(description: "Net worth = quantity * net_price")
  var net_worth: Double

  @Guide(description: "VAT percentage, e.g. 10")
  var vat_percent: Double

  @Guide(description: "Gross worth including VAT")
  var gross_worth: Double
}

@available(iOS 26.0, *)
@Generable
struct InvoiceSummary: Codable {
  @Guide(description: "VAT percentage applied")
  var vat_percent: Double

  @Guide(description: "Total net worth before VAT")
  var net_worth: Double

  @Guide(description: "Total VAT amount")
  var vat: Double

  @Guide(description: "Total gross worth including VAT")
  var gross_worth: Double
}

@available(iOS 26.0, *)
@Generable
struct InvoiceData: Codable {
  @Guide(description: "Invoice number")
  var invoice_no: String

  @Guide(description: "Date of issue in YYYY-MM-DD format")
  var date_of_issue: String

  var seller: InvoiceSeller
  var client: InvoiceClient

  @Guide(description: "All line items from the invoice table")
  var items: [InvoiceItem]

  var summary: InvoiceSummary
}

// MARK: - Extraction Error

enum InvoiceExtractionError: LocalizedError {
  case imageConversionFailed
  case ocrFailed(Error)
  case ocrEmpty
  case modelUnavailable(String)
  case generationFailed(Error)

  var errorDescription: String? {
    switch self {
    case .imageConversionFailed:
      return "Failed to convert UIImage to CGImage."
    case .ocrFailed(let err):
      return "Vision OCR failed: \(err.localizedDescription)"
    case .ocrEmpty:
      return "No text recognized in the image."
    case .modelUnavailable(let reason):
      return "On-device model unavailable: \(reason)"
    case .generationFailed(let err):
      return "FoundationModels generation failed: \(err.localizedDescription)"
    }
  }
}

// MARK: - Extractor

@available(iOS 26.0, *)
final class FoundationModelInvoiceExtractor {

  /// Perform OCR on a UIImage and return text lines sorted top-to-bottom.
  static func recognizeText(from image: UIImage) async throws -> String {
    guard let cgImage = image.cgImage else {
      throw InvoiceExtractionError.imageConversionFailed
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en", "vi"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    return try await withCheckedThrowingContinuation { continuation in
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: InvoiceExtractionError.ocrFailed(error))
        return
      }

      guard let observations = request.results else {
        continuation.resume(returning: "")
        return
      }

      // Sort by bounding box Y position: top-to-bottom.
      // Vision bounding boxes have origin at bottom-left, so higher Y = higher on page.
      // Sort descending by Y to get top-to-bottom reading order.
      let sorted = observations.sorted { a, b in
        let aY = a.boundingBox.origin.y + a.boundingBox.height
        let bY = b.boundingBox.origin.y + b.boundingBox.height
        if abs(aY - bY) < 0.01 {
          // Same row — sort left to right
          return a.boundingBox.origin.x < b.boundingBox.origin.x
        }
        return aY > bY
      }

      let lines = sorted.compactMap { obs -> String? in
        obs.topCandidates(1).first?.string
      }

      let text = lines.joined(separator: "\n")
      continuation.resume(returning: text)
    }
  }

  /// Extract structured InvoiceData from OCR text using Apple FoundationModels.
  static func extractInvoice(ocrText: String) async throws -> InvoiceData {
    let model = SystemLanguageModel.default

    switch model.availability {
    case .available:
      break
    case .unavailable(.deviceNotEligible):
      throw InvoiceExtractionError.modelUnavailable("Device not eligible for Apple Intelligence (requires A17 Pro or M1+).")
    case .unavailable(.appleIntelligenceNotEnabled):
      throw InvoiceExtractionError.modelUnavailable("Apple Intelligence is not enabled. Enable it in Settings > Apple Intelligence & Siri.")
    case .unavailable(.modelNotReady):
      throw InvoiceExtractionError.modelUnavailable("On-device model is still downloading. Try again later.")
    default:
      throw InvoiceExtractionError.modelUnavailable("Model is not available.")
    }

    let session = LanguageModelSession {
      """
      You are a precise document data extraction assistant. \
      You will receive OCR text from an invoice image. \
      Extract all fields exactly as they appear in the text. \
      For dates, convert MM/DD/YYYY to YYYY-MM-DD format. \
      For numbers that use comma as thousands separator (e.g. 1,394.67 or 1 394,67), \
      convert to plain decimal (1394.67). \
      Numbers with a dot as decimal separator should stay as-is (e.g. 689.70). \
      Extract every single line item from the ITEMS table — do not skip any rows. \
      For the summary section, extract the totals row values.
      """
    }

    let prompt = """
    Extract the structured invoice data from the following OCR text.
    Return every field accurately. Do not invent data that is not present.

    OCR TEXT:
    \(ocrText)
    """

    do {
      let response = try await session.respond(to: prompt, generating: InvoiceData.self)
      return response.content
    } catch {
      throw InvoiceExtractionError.generationFailed(error)
    }
  }

  /// Full pipeline: UIImage -> OCR -> structured InvoiceData
  static func extract(from image: UIImage) async throws -> InvoiceData {
    let ocrText = try await recognizeText(from: image)
    guard !ocrText.isEmpty else {
      throw InvoiceExtractionError.ocrEmpty
    }
    return try await extractInvoice(ocrText: ocrText)
  }
}

// MARK: - JSON encoding helper

@available(iOS 26.0, *)
extension InvoiceData {
  func toJSONString(prettyPrinted: Bool = true) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    guard let data = try? encoder.encode(self) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

// MARK: - SwiftUI ViewModel

@available(iOS 26.0, *)
@MainActor
@Observable
final class InvoiceScannerViewModel {
  var invoice: InvoiceData?
  var ocrText: String = ""
  var jsonOutput: String = ""
  var errorMessage: String?
  var isProcessing = false
  var selectedImage: UIImage?
  var showImagePicker = false

  func scanDocument(image: UIImage) {
    isProcessing = true
    errorMessage = nil
    invoice = nil
    ocrText = ""
    jsonOutput = ""

    Task {
      do {
        let text = try await FoundationModelInvoiceExtractor.recognizeText(from: image)
        self.ocrText = text

        let result = try await FoundationModelInvoiceExtractor.extractInvoice(ocrText: text)
        self.invoice = result
        self.jsonOutput = result.toJSONString() ?? "{}"
      } catch {
        self.errorMessage = error.localizedDescription
      }
      self.isProcessing = false
    }
  }
}

// MARK: - Image Picker

@available(iOS 26.0, *)
struct ImagePicker: UIViewControllerRepresentable {
  @Binding var image: UIImage?
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.delegate = context.coordinator
    picker.sourceType = .photoLibrary
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: ImagePicker
    init(_ parent: ImagePicker) { self.parent = parent }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      parent.image = info[.originalImage] as? UIImage
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}

// MARK: - SwiftUI View

@available(iOS 26.0, *)
struct InvoiceScannerView: View {
  @State private var viewModel = InvoiceScannerViewModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {

          // Image preview
          if let image = viewModel.selectedImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: 240)
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .shadow(radius: 4)
          } else {
            RoundedRectangle(cornerRadius: 12)
              .fill(Color(.systemGray5))
              .frame(height: 180)
              .overlay {
                VStack(spacing: 8) {
                  Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                  Text("Select an invoice image")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
              }
          }

          // Action button
          Button {
            viewModel.showImagePicker = true
          } label: {
            Label("Scan Document with FoundationModels", systemImage: "doc.text.magnifyingglass")
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
          }
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.isProcessing)

          // Processing indicator
          if viewModel.isProcessing {
            VStack(spacing: 8) {
              ProgressView()
                .controlSize(.large)
              Text("Extracting invoice data...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding()
          }

          // Error
          if let error = viewModel.errorMessage {
            GroupBox("Error") {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }

          // Results
          if let invoice = viewModel.invoice {
            invoiceResultView(invoice)
          }

          // Raw OCR text (collapsible)
          if !viewModel.ocrText.isEmpty {
            DisclosureGroup("Raw OCR Text") {
              Text(viewModel.ocrText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
          }

          // JSON output (collapsible)
          if !viewModel.jsonOutput.isEmpty {
            DisclosureGroup("JSON Output") {
              ScrollView(.horizontal, showsIndicators: false) {
                Text(viewModel.jsonOutput)
                  .font(.system(.caption, design: .monospaced))
                  .padding(8)
              }
              .background(Color(.systemGray6))
              .clipShape(RoundedRectangle(cornerRadius: 8))
            }
          }
        }
        .padding()
      }
      .navigationTitle("Invoice Scanner")
      .sheet(isPresented: $viewModel.showImagePicker) {
        ImagePicker(image: $viewModel.selectedImage)
      }
      .onChange(of: viewModel.selectedImage) { _, newImage in
        if let image = newImage {
          viewModel.scanDocument(image: image)
        }
      }
    }
  }

  @ViewBuilder
  private func invoiceResultView(_ invoice: InvoiceData) -> some View {
    GroupBox("Invoice Details") {
      VStack(alignment: .leading, spacing: 10) {
        fieldRow("Invoice No", invoice.invoice_no)
        fieldRow("Date of Issue", invoice.date_of_issue)

        Divider()

        Text("Seller").font(.headline)
        fieldRow("Name", invoice.seller.name)
        fieldRow("Street", invoice.seller.address.street)
        fieldRow("City", invoice.seller.address.city)
        fieldRow("State", invoice.seller.address.state)
        fieldRow("ZIP", invoice.seller.address.zip_code)
        fieldRow("Tax ID", invoice.seller.tax_id)
        fieldRow("IBAN", invoice.seller.iban)

        Divider()

        Text("Client").font(.headline)
        fieldRow("Name", invoice.client.name)
        fieldRow("Street", invoice.client.address.street)
        fieldRow("City", invoice.client.address.city)
        fieldRow("State", invoice.client.address.state)
        fieldRow("ZIP", invoice.client.address.zip_code)
        fieldRow("Tax ID", invoice.client.tax_id)

        Divider()

        Text("Items (\(invoice.items.count))").font(.headline)
        ForEach(invoice.items, id: \.no) { item in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(item.no). \(item.description)")
              .font(.subheadline.bold())
            HStack {
              Text("Qty: \(item.quantity, specifier: "%.2f") \(item.unit)")
              Spacer()
              Text("Net: \(item.net_price, specifier: "%.2f")")
            }
            .font(.caption)
            HStack {
              Text("Net worth: \(item.net_worth, specifier: "%.2f")")
              Spacer()
              Text("VAT: \(item.vat_percent, specifier: "%.0f")%")
              Spacer()
              Text("Gross: \(item.gross_worth, specifier: "%.2f")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }

        Divider()

        Text("Summary").font(.headline)
        fieldRow("VAT %", String(format: "%.0f", invoice.summary.vat_percent))
        fieldRow("Net Worth", String(format: "%.2f", invoice.summary.net_worth))
        fieldRow("VAT", String(format: "%.2f", invoice.summary.vat))
        fieldRow("Gross Worth", String(format: "%.2f", invoice.summary.gross_worth))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func fieldRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 80, alignment: .leading)
      Text(value)
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Invoice Scanner") {
  InvoiceScannerView()
}
