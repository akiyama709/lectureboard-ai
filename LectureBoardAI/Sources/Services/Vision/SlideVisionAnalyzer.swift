import Foundation
import LectureBoardCore
import Vision

actor SlideVisionAnalyzer {
  private let assembler: SlideAnalysisAssembler

  init(assembler: SlideAnalysisAssembler = .init()) {
    self.assembler = assembler
  }

  func analyze(_ frame: CapturedPowerPointFrame) async throws -> SlideVisualAnalysis {
    var textRequest = RecognizeTextRequest()
    textRequest.recognitionLevel = .accurate
    textRequest.automaticallyDetectsLanguage = true
    textRequest.usesLanguageCorrection = true
    textRequest.minimumTextHeightFraction = 0.008

    var rectangleRequest = DetectRectanglesRequest()
    rectangleRequest.minimumAspectRatio = 0.05
    rectangleRequest.maximumAspectRatio = 1
    rectangleRequest.quadratureToleranceDegrees = 20
    rectangleRequest.minimumSize = 0.03
    rectangleRequest.minimumConfidence = 0.50
    rectangleRequest.maximumObservations = 24

    let handler = ImageRequestHandler(frame.image)
    let (recognizedText, rectangles) = try await handler.perform(
      textRequest,
      rectangleRequest
    )

    return assembler.assemble(
      textObservations: recognizedText.compactMap(textObservation),
      geometryObservations: rectangles.map(geometryObservation)
    )
  }

  private func textObservation(
    _ observation: RecognizedTextObservation
  ) -> SlideTextObservation? {
    guard let candidate = observation.topCandidates(1).first else { return nil }
    return SlideTextObservation(
      id: observation.uuid,
      text: candidate.string,
      region: topLeftRegion(observation.boundingBox),
      confidence: Double(candidate.confidence),
      isTitleCandidate: observation.isTitle
    )
  }

  private func geometryObservation(
    _ observation: RectangleObservation
  ) -> SlideGeometryObservation {
    SlideGeometryObservation(
      id: observation.uuid,
      region: topLeftRegion(observation.boundingBox),
      confidence: Double(observation.confidence)
    )
  }

  private func topLeftRegion(_ region: Vision.NormalizedRect) -> LectureBoardCore.NormalizedRect {
    let rectangle = region.verticallyFlipped().cgRect
    return LectureBoardCore.NormalizedRect(
      x: Double(rectangle.minX),
      y: Double(rectangle.minY),
      width: Double(rectangle.width),
      height: Double(rectangle.height)
    )
  }
}
