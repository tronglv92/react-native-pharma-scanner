import NitroModules
import AVFoundation
import UIKit

class HybridPharmaScanner: HybridPharmaScannerSpec {
  private let cameraManager = CameraManager.shared

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
}
