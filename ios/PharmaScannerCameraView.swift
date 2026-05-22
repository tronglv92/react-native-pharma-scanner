import AVFoundation
import UIKit

class PharmaScannerCameraView: UIView {
  private var previewLayer: AVCaptureVideoPreviewLayer?

  private let overlayLayer: CAShapeLayer = {
    let layer = CAShapeLayer()
    layer.strokeColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0).cgColor // #4CAF50
    layer.fillColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 0.15).cgColor
    layer.lineWidth = 3.0
    layer.lineJoin = .round
    layer.lineCap = .round
    return layer
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    backgroundColor = .black

    let session = CameraManager.shared.captureSession
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    self.layer.addSublayer(layer)
    previewLayer = layer

    self.layer.addSublayer(overlayLayer)

    CameraManager.shared.bindOverlay(self)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
    overlayLayer.frame = bounds
  }

  func updateDetection(_ detection: DocumentDetection?) {
    guard let detection = detection, detection.detected else {
      overlayLayer.path = nil
      return
    }

    let c = detection.corners
    let w = bounds.width
    let h = bounds.height

    let path = UIBezierPath()
    path.move(to: CGPoint(x: c.topLeft.x * w, y: c.topLeft.y * h))
    path.addLine(to: CGPoint(x: c.topRight.x * w, y: c.topRight.y * h))
    path.addLine(to: CGPoint(x: c.bottomRight.x * w, y: c.bottomRight.y * h))
    path.addLine(to: CGPoint(x: c.bottomLeft.x * w, y: c.bottomLeft.y * h))
    path.close()

    overlayLayer.path = path.cgPath
  }
}
