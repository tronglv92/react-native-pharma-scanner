import Vision
import AVFoundation
import CoreImage

protocol DocumentDetectorDelegate: AnyObject {
  func documentDetector(_ detector: DocumentDetector, didDetect detection: DocumentDetection)
}

class DocumentDetector {
  weak var delegate: DocumentDetectorDelegate?

  private let stabilityFrameCount = 6
  private let stabilityThreshold: Double = 0.03
  private var recentCorners: [Corners] = []

  private var frameCounter: Int = 0
  private let frameSkip: Int = 3

  // MARK: - One-shot detection

  func detectDocument(imageUri: String) async throws -> DocumentDetection {
    guard let url = URL(string: imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "DocumentDetector", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI"])
    }

    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    let request = makeDocumentRequest()

    try handler.perform([request])

    return processResults(request.results as? [VNRectangleObservation], imageSize: nil)
  }

  // MARK: - Continuous detection (camera frames)

  func processFrame(_ sampleBuffer: CMSampleBuffer) {
    frameCounter += 1
    guard frameCounter % frameSkip == 0 else { return }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    let request = makeDocumentRequest()

    do {
      try handler.perform([request])
    } catch {
      return
    }

    let detection = processResults(request.results as? [VNRectangleObservation], imageSize: nil)
    delegate?.documentDetector(self, didDetect: detection)
  }

  func reset() {
    recentCorners.removeAll()
    frameCounter = 0
  }

  // MARK: - Private

  private func makeDocumentRequest() -> VNDetectDocumentSegmentationRequest {
    let request = VNDetectDocumentSegmentationRequest()
    return request
  }

  private func processResults(_ results: [VNRectangleObservation]?, imageSize: CGSize?) -> DocumentDetection {
    let zeroPoint = Point(x: 0, y: 0)
    let zeroCorners = Corners(topLeft: zeroPoint, topRight: zeroPoint,
                              bottomLeft: zeroPoint, bottomRight: zeroPoint)

    guard let observations = results,
          let observation = observations.first else {
      recentCorners.removeAll()
      return DocumentDetection(detected: false, corners: zeroCorners, confidence: 0, isStable: false)
    }

    // Vision uses bottom-left origin, flip Y to get top-left origin
    let corners = Corners(
      topLeft: Point(x: Double(observation.topLeft.x), y: Double(1.0 - observation.topLeft.y)),
      topRight: Point(x: Double(observation.topRight.x), y: Double(1.0 - observation.topRight.y)),
      bottomLeft: Point(x: Double(observation.bottomLeft.x), y: Double(1.0 - observation.bottomLeft.y)),
      bottomRight: Point(x: Double(observation.bottomRight.x), y: Double(1.0 - observation.bottomRight.y))
    )

    recentCorners.append(corners)
    if recentCorners.count > stabilityFrameCount {
      recentCorners.removeFirst(recentCorners.count - stabilityFrameCount)
    }

    let isStable = checkStability()

    return DocumentDetection(
      detected: true,
      corners: corners,
      confidence: Double(observation.confidence),
      isStable: isStable
    )
  }

  private func checkStability() -> Bool {
    guard recentCorners.count >= stabilityFrameCount else { return false }

    let reference = recentCorners.last!
    for corners in recentCorners.dropLast() {
      if !cornersWithinThreshold(corners, reference) {
        return false
      }
    }
    return true
  }

  private func cornersWithinThreshold(_ a: Corners, _ b: Corners) -> Bool {
    return pointsWithinThreshold(a.topLeft, b.topLeft)
      && pointsWithinThreshold(a.topRight, b.topRight)
      && pointsWithinThreshold(a.bottomLeft, b.bottomLeft)
      && pointsWithinThreshold(a.bottomRight, b.bottomRight)
  }

  private func pointsWithinThreshold(_ a: Point, _ b: Point) -> Bool {
    return abs(a.x - b.x) < stabilityThreshold
      && abs(a.y - b.y) < stabilityThreshold
  }
}
