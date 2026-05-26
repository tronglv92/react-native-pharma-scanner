import VisionKit
import UIKit

class DocumentScannerManager {
  private var delegate: ScannerDelegate?

  func scanDocument() async throws -> [CapturedImage] {
    return try await withCheckedThrowingContinuation { continuation in
      let scannerDelegate = ScannerDelegate(continuation: continuation)
      self.delegate = scannerDelegate

      DispatchQueue.main.async {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = scannerDelegate

        guard let scene = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
          continuation.resume(throwing: NSError(
            domain: "DocumentScannerManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find root view controller to present scanner"]
          ))
          self.delegate = nil
          return
        }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
          presenter = presented
        }

        presenter.present(scanner, animated: true)
      }
    }
  }
}

private class ScannerDelegate: NSObject, VNDocumentCameraViewControllerDelegate {
  private var continuation: CheckedContinuation<[CapturedImage], Error>?

  init(continuation: CheckedContinuation<[CapturedImage], Error>) {
    self.continuation = continuation
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    controller.dismiss(animated: true)

    var images: [CapturedImage] = []
    let tempDir = FileManager.default.temporaryDirectory

    for i in 0..<scan.pageCount {
      let pageImage = scan.imageOfPage(at: i)
      guard let jpegData = pageImage.jpegData(compressionQuality: 0.9) else { continue }

      let fileName = UUID().uuidString + ".jpg"
      let fileURL = tempDir.appendingPathComponent(fileName)

      do {
        try jpegData.write(to: fileURL)
        images.append(CapturedImage(
          uri: fileURL.absoluteString,
          width: Double(pageImage.size.width * pageImage.scale),
          height: Double(pageImage.size.height * pageImage.scale),
          base64: nil
        ))
      } catch {
        continue
      }
    }

    continuation?.resume(returning: images)
    continuation = nil
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    continuation?.resume(returning: [])
    continuation = nil
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true)
    continuation?.resume(throwing: error)
    continuation = nil
  }
}
