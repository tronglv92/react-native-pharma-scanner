import AVFoundation
import UIKit
import NitroModules

class CameraManager: NSObject {
  static let shared = CameraManager()

  let captureSession = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "com.pharmascanner.sessionQueue")
  private let videoProcessingQueue = DispatchQueue(label: "com.pharmascanner.videoProcessingQueue")
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private var flashMode: AVCaptureDevice.FlashMode = .auto
  private var currentPhotoCaptureDelegate: PhotoCaptureDelegate?
  private(set) var isSessionRunning = false
  private let documentDetector = DocumentDetector()
  var onDocumentDetectedCallback: ((DocumentDetection) -> Void)?
  private weak var overlayView: PharmaScannerCameraView?

  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
  }

  private override init() {
    super.init()
    documentDetector.delegate = self
  }

  func requestCameraPermission() async -> Bool {
    // if CameraManager.isSimulator { return true }

    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    default:
      return false
    }
  }

  func startSession() throws {
    // if CameraManager.isSimulator {
    //   isSessionRunning = true
    //   return
    // }

    sessionQueue.sync {
      guard !self.isSessionRunning else { return }

      self.captureSession.beginConfiguration()
      self.captureSession.sessionPreset = .photo

      guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
        self.captureSession.commitConfiguration()
        return
      }

      do {
        let input = try AVCaptureDeviceInput(device: camera)
        if self.captureSession.canAddInput(input) {
          self.captureSession.addInput(input)
        }
      } catch {
        self.captureSession.commitConfiguration()
        return
      }

      if self.captureSession.canAddOutput(self.photoOutput) {
        self.captureSession.addOutput(self.photoOutput)
      }

      self.videoOutput.alwaysDiscardsLateVideoFrames = true
      self.videoOutput.setSampleBufferDelegate(self, queue: self.videoProcessingQueue)
      if self.captureSession.canAddOutput(self.videoOutput) {
        self.captureSession.addOutput(self.videoOutput)
      }

      self.captureSession.commitConfiguration()
      self.captureSession.startRunning()
      self.isSessionRunning = true
    }
  }

  func stopSession() {
    // if CameraManager.isSimulator {
    //   isSessionRunning = false
    //   return
    // }

    sessionQueue.sync {
      guard self.isSessionRunning else { return }
      self.captureSession.stopRunning()

      for input in self.captureSession.inputs {
        self.captureSession.removeInput(input)
      }
      for output in self.captureSession.outputs {
        self.captureSession.removeOutput(output)
      }

      self.onDocumentDetectedCallback = nil
      self.documentDetector.reset()
      self.isSessionRunning = false
      DispatchQueue.main.async { [weak self] in
        self?.overlayView?.updateDetection(nil)
      }
    }
  }

  func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
    self.flashMode = mode
  }

  func setZoom(factor: Double) {
    // if CameraManager.isSimulator { return }

    sessionQueue.sync {
      guard let device = (self.captureSession.inputs.first as? AVCaptureDeviceInput)?.device else {
        return
      }
      let clampedFactor = min(max(CGFloat(factor), 1.0), device.activeFormat.videoMaxZoomFactor)
      do {
        try device.lockForConfiguration()
        device.videoZoomFactor = clampedFactor
        device.unlockForConfiguration()
      } catch {
        // Ignore zoom errors
      }
    }
  }

  func capturePhoto() async throws -> (Data, CGFloat, CGFloat) {
    // if CameraManager.isSimulator {
    //   return generateMockPhoto()
    // }

    guard isSessionRunning else {
      throw NSError(domain: "CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Camera session is not running."])
    }

    guard !captureSession.inputs.isEmpty else {
      throw NSError(domain: "CameraManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "No camera input available."])
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.sessionQueue.async {
        guard self.captureSession.isRunning else {
          continuation.resume(throwing: NSError(domain: "CameraManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Camera session stopped before capture could begin."]))
          return
        }

        let settings = AVCapturePhotoSettings()
        if self.photoOutput.supportedFlashModes.contains(self.flashMode) {
          settings.flashMode = self.flashMode
        }

        let delegate = PhotoCaptureDelegate(continuation: continuation)
        self.currentPhotoCaptureDelegate = delegate
        self.photoOutput.capturePhoto(with: settings, delegate: delegate)
      }
    }
  }

  func setOnDocumentDetected(_ callback: ((DocumentDetection) -> Void)?) {
    self.onDocumentDetectedCallback = callback
  }

  func bindOverlay(_ view: PharmaScannerCameraView) {
    self.overlayView = view
  }

  // MARK: - Simulator Mock

  private func generateMockPhoto() -> (Data, CGFloat, CGFloat) {
    let width: CGFloat = 1920
    let height: CGFloat = 1080
    let size = CGSize(width: width, height: height)

    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
      // Gradient background
      let colors = [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor]
      let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
      context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])

      // Draw text
      let text = "Simulator Mock Photo"
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 64, weight: .bold),
        .foregroundColor: UIColor.white,
      ]
      let textSize = text.size(withAttributes: attributes)
      let textOrigin = CGPoint(x: (width - textSize.width) / 2, y: (height - textSize.height) / 2)
      text.draw(at: textOrigin, withAttributes: attributes)

      // Timestamp
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      let timestamp = formatter.string(from: Date())
      let tsAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 32),
        .foregroundColor: UIColor.white.withAlphaComponent(0.8),
      ]
      let tsSize = timestamp.size(withAttributes: tsAttributes)
      let tsOrigin = CGPoint(x: (width - tsSize.width) / 2, y: (height - textSize.height) / 2 + textSize.height + 20)
      timestamp.draw(at: tsOrigin, withAttributes: tsAttributes)
    }

    let data = image.jpegData(compressionQuality: 0.9)!
    return (data, width, height)
  }

  // MARK: - PhotoCaptureDelegate

  class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<(Data, CGFloat, CGFloat), any Error>
    private var hasResumed = false

    init(continuation: CheckedContinuation<(Data, CGFloat, CGFloat), any Error>) {
      self.continuation = continuation
      super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
      guard !hasResumed else { return }
      hasResumed = true

      if let error = error {
        continuation.resume(throwing: error)
        CameraManager.shared.currentPhotoCaptureDelegate = nil
        return
      }

      guard let data = photo.fileDataRepresentation() else {
        continuation.resume(throwing: NSError(domain: "CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get photo data"]))
        CameraManager.shared.currentPhotoCaptureDelegate = nil
        return
      }

      let dimensions = photo.resolvedSettings.photoDimensions
      let width = CGFloat(dimensions.width)
      let height = CGFloat(dimensions.height)

      continuation.resume(returning: (data, width, height))
      CameraManager.shared.currentPhotoCaptureDelegate = nil
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    documentDetector.processFrame(sampleBuffer)
  }
}

// MARK: - DocumentDetectorDelegate

extension CameraManager: DocumentDetectorDelegate {
  func documentDetector(_ detector: DocumentDetector, didDetect detection: DocumentDetection) {
    DispatchQueue.main.async { [weak self] in
      self?.overlayView?.updateDetection(detection)
    }
    onDocumentDetectedCallback?(detection)
  }
}
