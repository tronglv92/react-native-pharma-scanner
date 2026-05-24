import AVFoundation
import UIKit

class PharmaScannerCameraView: UIView {
  private var previewLayer: AVCaptureVideoPreviewLayer?

  // Document detection overlay (quad shape)
  private let documentOverlayLayer: CAShapeLayer = {
    let layer = CAShapeLayer()
    layer.strokeColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0).cgColor // #4CAF50
    layer.fillColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 0.15).cgColor
    layer.lineWidth = 3.0
    layer.lineJoin = .round
    layer.lineCap = .round
    return layer
  }()

  // Barcode detection overlay (container for rect sublayers)
  private let barcodeOverlayLayer = CALayer()

  // Overlay style properties
  private var overlayStrokeColor: UIColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0) // #4CAF50
  private var overlayFillColorValue: UIColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 0.15)
  private var overlayLineWidthValue: CGFloat = 3.0
  private var showOverlayValue: Bool = true

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

    self.layer.addSublayer(documentOverlayLayer)
    self.layer.addSublayer(barcodeOverlayLayer)

    CameraManager.shared.bindOverlay(self)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
    documentOverlayLayer.frame = bounds
    barcodeOverlayLayer.frame = bounds
  }

  // MARK: - React Native prop setters

  @objc func setOverlayColor(_ hexString: NSString?) {
    guard let hex = hexString as String?, let color = UIColor(hexString: hex) else { return }
    overlayStrokeColor = color
    documentOverlayLayer.strokeColor = color.cgColor
  }

  @objc func setOverlayLineWidth(_ width: NSNumber?) {
    guard let w = width else { return }
    overlayLineWidthValue = CGFloat(w.doubleValue)
    documentOverlayLayer.lineWidth = overlayLineWidthValue
  }

  @objc func setOverlayFillColor(_ hexString: NSString?) {
    guard let hex = hexString as String?, let color = UIColor(hexString: hex) else { return }
    overlayFillColorValue = color
    documentOverlayLayer.fillColor = color.cgColor
  }

  @objc func setShowOverlay(_ show: Bool) {
    showOverlayValue = show
    documentOverlayLayer.isHidden = !show
    barcodeOverlayLayer.isHidden = !show
  }

  // MARK: - Document detection overlay

  func updateDetection(_ detection: DocumentDetection?) {
    clearBarcodeOverlays()

    guard showOverlayValue else {
      documentOverlayLayer.path = nil
      return
    }

    guard let detection = detection, detection.detected else {
      documentOverlayLayer.path = nil
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

    documentOverlayLayer.path = path.cgPath
  }

  // MARK: - Barcode detection overlay

  func updateBarcodeDetections(_ results: [BarcodeResult]?) {
    // Clear document overlay when showing barcodes
    documentOverlayLayer.path = nil

    clearBarcodeOverlays()

    guard showOverlayValue else { return }

    guard let results = results, !results.isEmpty else { return }

    let w = bounds.width
    let h = bounds.height

    for result in results {
      guard let box = result.boundingBox else { continue }

      let rect = CGRect(
        x: box.x * w,
        y: box.y * h,
        width: box.width * w,
        height: box.height * h
      )

      let shapeLayer = CAShapeLayer()
      shapeLayer.strokeColor = overlayStrokeColor.cgColor
      shapeLayer.fillColor = overlayFillColorValue.cgColor
      shapeLayer.lineWidth = overlayLineWidthValue
      shapeLayer.lineJoin = .round
      shapeLayer.lineCap = .round
      shapeLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4.0).cgPath

      barcodeOverlayLayer.addSublayer(shapeLayer)
    }
  }

  func clearBarcodeOverlays() {
    barcodeOverlayLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
  }

  func clearAllOverlays() {
    documentOverlayLayer.path = nil
    clearBarcodeOverlays()
  }
}

// MARK: - UIColor hex string extension

extension UIColor {
  convenience init?(hexString: String) {
    var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }

    var rgbValue: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&rgbValue) else { return nil }

    switch hex.count {
    case 6: // #RRGGBB
      let r = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
      let g = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
      let b = CGFloat(rgbValue & 0xFF) / 255.0
      self.init(red: r, green: g, blue: b, alpha: 1.0)
    case 8: // #RRGGBBAA
      let r = CGFloat((rgbValue >> 24) & 0xFF) / 255.0
      let g = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
      let b = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
      let a = CGFloat(rgbValue & 0xFF) / 255.0
      self.init(red: r, green: g, blue: b, alpha: a)
    default:
      return nil
    }
  }
}
