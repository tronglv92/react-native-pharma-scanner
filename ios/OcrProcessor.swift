import Vision
import NitroModules

class OcrProcessor {

  func recognizeText(imageUri: String) async throws -> OcrResult {
    guard let url = URL(string: imageUri),
          let ciImage = CIImage(contentsOf: url) else {
      throw NSError(domain: "OcrProcessor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
    }

    let imageWidth = ciImage.extent.width
    let imageHeight = ciImage.extent.height

    if #available(iOS 18.0, *) {
      return try await recognizeTextModern(ciImage: ciImage, imageWidth: imageWidth, imageHeight: imageHeight)
    } else {
      return try await recognizeTextLegacy(ciImage: ciImage, imageWidth: imageWidth, imageHeight: imageHeight)
    }
  }

  // MARK: - iOS 18+ (new Vision API — avoids VNRecognizeTextRequest entirely)

  @available(iOS 18.0, *)
  private func recognizeTextModern(ciImage: CIImage, imageWidth: CGFloat, imageHeight: CGFloat) async throws -> OcrResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true

    let observations = try await request.perform(on: ciImage)

    let blocks: [TextBlock] = observations.compactMap { obs in
      guard let candidate = obs.topCandidates(1).first else { return nil }

      let minX = min(obs.topLeft.x, obs.bottomLeft.x)
      let maxX = max(obs.topRight.x, obs.bottomRight.x)
      let minY = min(obs.topLeft.y, obs.topRight.y)
      let maxY = max(obs.bottomLeft.y, obs.bottomRight.y)

      let blockRect = FrameRect(
        x: minX * imageWidth,
        y: (1.0 - maxY) * imageHeight,
        width: (maxX - minX) * imageWidth,
        height: (maxY - minY) * imageHeight
      )

      let text = String(candidate.string)
      let line = TextLine(
        text: text,
        boundingBox: blockRect,
        confidence: Double(candidate.confidence),
        elements: []
      )

      return TextBlock(text: text, boundingBox: blockRect, lines: [line])
    }

    let fullText = blocks.map { $0.text }.joined(separator: "\n")
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

    return OcrResult(text: fullText, blocks: blocks, processingTimeMs: elapsed)
  }

  // MARK: - iOS < 18 (legacy VNRecognizeTextRequest)

  private func recognizeTextLegacy(ciImage: CIImage, imageWidth: CGFloat, imageHeight: CGFloat) async throws -> OcrResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
          let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
          continuation.resume(returning: OcrResult(text: "", blocks: [], processingTimeMs: elapsed))
          return
        }

        let blocks: [TextBlock] = observations.compactMap { obs in
          guard let candidate = obs.topCandidates(1).first else { return nil }

          let box = obs.boundingBox
          let blockRect = FrameRect(
            x: box.origin.x * imageWidth,
            y: (1.0 - box.origin.y - box.height) * imageHeight,
            width: box.width * imageWidth,
            height: box.height * imageHeight
          )

          let line = TextLine(
            text: candidate.string,
            boundingBox: blockRect,
            confidence: Double(candidate.confidence),
            elements: []
          )

          return TextBlock(text: candidate.string, boundingBox: blockRect, lines: [line])
        }

        let fullText = blocks.map { $0.text }.joined(separator: "\n")
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        continuation.resume(returning: OcrResult(text: fullText, blocks: blocks, processingTimeMs: elapsed))
      }

      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["vi", "en"]
      request.usesLanguageCorrection = true

      let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  // MARK: - Frame processing (camera)

  func processFrame(_ sampleBuffer: CMSampleBuffer, imageWidth: CGFloat, imageHeight: CGFloat) -> OcrResult? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

    let startTime = CFAbsoluteTimeGetCurrent()
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.recognitionLanguages = ["en"]

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return nil
    }

    guard let observations = request.results as? [VNRecognizedTextObservation] else { return nil }

    let blocks: [TextBlock] = observations.compactMap { obs in
      guard let candidate = obs.topCandidates(1).first else { return nil }
      let box = obs.boundingBox
      let blockRect = FrameRect(
        x: box.origin.x * imageWidth,
        y: (1.0 - box.origin.y - box.height) * imageHeight,
        width: box.width * imageWidth,
        height: box.height * imageHeight
      )
      let line = TextLine(text: candidate.string, boundingBox: blockRect, confidence: Double(candidate.confidence), elements: [])
      return TextBlock(text: candidate.string, boundingBox: blockRect, lines: [line])
    }

    let fullText = blocks.map { $0.text }.joined(separator: "\n")
    let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
    return OcrResult(text: fullText, blocks: blocks, processingTimeMs: elapsed)
  }
}
