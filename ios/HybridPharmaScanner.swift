import NitroModules
import AVFoundation
import UIKit

class HybridPharmaScanner: HybridPharmaScannerSpec {
  private let cameraManager = CameraManager.shared
  private let documentScannerManager = DocumentScannerManager()

  func ping() throws -> String {
    return "pong"
  }

  func getVersion() throws -> String {
    return "0.0.1"
  }

  func startCamera() throws -> Void {
    Task {
      let granted = await cameraManager.requestCameraPermission()
      guard granted else {
        print("[PharmaScanner] Camera permission denied")
        return
      }
      try cameraManager.startSession()
    }
  }

  func stopCamera() throws -> Void {
    cameraManager.stopSession()
  }

  func capturePhoto() throws -> Promise<CapturedImage> {
    return Promise.async {
      let (data, width, height) = try await self.cameraManager.capturePhoto()

      // Save JPEG to temp directory
      let fileName = UUID().uuidString + ".jpg"
      let tempDir = FileManager.default.temporaryDirectory
      let fileURL = tempDir.appendingPathComponent(fileName)
      try data.write(to: fileURL)

      return CapturedImage(
        uri: fileURL.absoluteString,
        width: Double(width),
        height: Double(height),
        base64: nil
      )
    }
  }

  func setFlash(mode: FlashMode) throws -> Void {
    let avFlashMode: AVCaptureDevice.FlashMode
    switch mode {
    case .auto:
      avFlashMode = .auto
    case .on:
      avFlashMode = .on
    case .off:
      avFlashMode = .off
    }
    cameraManager.setFlashMode(avFlashMode)
  }

  func setZoom(factor: Double) throws -> Void {
    cameraManager.setZoom(factor: factor)
  }

  func detectDocument(imageUri: String) throws -> Promise<DocumentDetection> {
    return Promise.async {
      let detector = DocumentDetector()
      return try await detector.detectDocument(imageUri: imageUri)
    }
  }

  func cropAndCorrect(imageUri: String, corners: Corners) throws -> Promise<CapturedImage> {
    return Promise.async {
      let (data, width, height) = try ImageProcessor.cropAndCorrect(imageUri: imageUri, corners: corners)

      let fileName = UUID().uuidString + ".jpg"
      let tempDir = FileManager.default.temporaryDirectory
      let fileURL = tempDir.appendingPathComponent(fileName)
      try data.write(to: fileURL)

      return CapturedImage(
        uri: fileURL.absoluteString,
        width: Double(width),
        height: Double(height),
        base64: nil
      )
    }
  }

  func setOnDocumentDetected(callback: @escaping (_ detection: DocumentDetection) -> Void) throws -> Void {
    cameraManager.setOnDocumentDetected(callback)
  }

  func scanDocument() throws -> Promise<[CapturedImage]> {
    return Promise.async {
      return try await self.documentScannerManager.scanDocument()
    }
  }

  func scanBarcodes(options: BarcodeScanOptions) throws -> Promise<[BarcodeResult]> {
    return Promise.async {
      let scanner = BarcodeScanner()
      return try await scanner.scanBarcodes(imageUri: options.imageUri, formats: options.formats)
    }
  }

  func startContinuousScan(formats: [BarcodeFormat], onDetected: @escaping (_ codes: [BarcodeResult]) -> Void) throws -> Void {
    cameraManager.onBarcodesDetectedCallback = onDetected
    cameraManager.startContinuousScan(formats: formats)
  }

  func stopContinuousScan() throws -> Void {
    cameraManager.stopContinuousScan()
  }

  func recognizeText(imageUri: String) throws -> Promise<OcrResult> {
    return Promise.async {
      let processor = OcrProcessor()
      return try await processor.recognizeText(imageUri: imageUri)
    }
  }

  func recognizeDocument(imageUri: String) throws -> Promise<OcrResult> {
    return Promise.async {
      let processor = DocumentOcrProcessor()
      return try await processor.recognizeDocument(imageUri: imageUri)
    }
  }

  func setOnTextRecognized(callback: @escaping (_ result: OcrResult) -> Void) throws -> Void {
    cameraManager.onTextRecognizedCallback = callback
  }

  func scanInvoice(imageUri: String) throws -> Promise<InvoiceResult> {
    return Promise.async {
      let processor = OcrProcessor()
      let ocrResult = try await processor.recognizeText(imageUri: imageUri)
      let parser = InvoiceParser()
      return parser.parse(ocrResult: ocrResult)
    }
  }

  func configure(apiKey: String, baseUrl: String) throws -> Void {
    DocumentExtractor.shared.configure(apiKey: apiKey, baseUrl: baseUrl)
  }

  func recognizeStructuredDocument(imageUri: String) throws -> Promise<StructuredDocumentResult> {
    return Promise.async {
      let processor = DocumentOcrProcessor()
      return try await processor.recognizeStructuredDocument(imageUri: imageUri)
    }
  }

  func extractDocument(imageUri: String, options: ExtractionOptions) throws -> Promise<DocumentExtractionResult> {
    return Promise.async {
      return try await DocumentExtractor.shared.extract(
        imageUri: imageUri,
        documentType: String(options.documentType),
        language: String(options.language),
        customPrompt: options.customPrompt.flatMap { String($0) },
        forceOffline: options.forceOffline ?? false,
        scanOcr: options.scanOcr ?? false
      )
    }
  }
}
