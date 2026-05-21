import AVFoundation
import UIKit

class PharmaScannerCameraView: UIView {
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var simulatorLabel: UILabel?

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

    // if CameraManager.isSimulator {
    //   let label = UILabel()
    //   label.text = "Camera Preview\n(Simulator)"
    //   label.numberOfLines = 0
    //   label.textAlignment = .center
    //   label.textColor = .white
    //   label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
    //   label.translatesAutoresizingMaskIntoConstraints = false
    //   addSubview(label)
    //   NSLayoutConstraint.activate([
    //     label.centerXAnchor.constraint(equalTo: centerXAnchor),
    //     label.centerYAnchor.constraint(equalTo: centerYAnchor),
    //   ])
    //   simulatorLabel = label
    // } else {
      let session = CameraManager.shared.captureSession
      let layer = AVCaptureVideoPreviewLayer(session: session)
      layer.videoGravity = .resizeAspectFill
      self.layer.addSublayer(layer)
      previewLayer = layer
    // }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
  }
}
