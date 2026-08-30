import Foundation

public struct SlideTextObservation: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var text: String
  public var region: NormalizedRect
  public var confidence: Double
  public var isTitleCandidate: Bool

  public init(
    id: UUID = UUID(),
    text: String,
    region: NormalizedRect,
    confidence: Double,
    isTitleCandidate: Bool = false
  ) {
    self.id = id
    self.text = text
    self.region = region
    self.confidence = confidence
    self.isTitleCandidate = isTitleCandidate
  }
}

public struct SlideGeometryObservation: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var region: NormalizedRect
  public var confidence: Double

  public init(
    id: UUID = UUID(),
    region: NormalizedRect,
    confidence: Double
  ) {
    self.id = id
    self.region = region
    self.confidence = confidence
  }
}

public struct SlideVisualAnalysis: Codable, Hashable, Sendable {
  public var title: String
  public var textBlocks: [SlideTextBlock]
  public var strokeCandidateRegions: [NormalizedRect]
  public var graphicRegions: [NormalizedRect]
  public var occupiedRegions: [NormalizedRect]

  public init(
    title: String = "",
    textBlocks: [SlideTextBlock] = [],
    strokeCandidateRegions: [NormalizedRect] = [],
    graphicRegions: [NormalizedRect] = [],
    occupiedRegions: [NormalizedRect] = []
  ) {
    self.title = title
    self.textBlocks = textBlocks
    self.strokeCandidateRegions = strokeCandidateRegions
    self.graphicRegions = graphicRegions
    self.occupiedRegions = occupiedRegions
  }

  private enum CodingKeys: String, CodingKey {
    case title
    case textBlocks
    case strokeCandidateRegions
    case graphicRegions
    case occupiedRegions
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    textBlocks = try container.decode([SlideTextBlock].self, forKey: .textBlocks)
    strokeCandidateRegions =
      try container.decodeIfPresent(
        [NormalizedRect].self,
        forKey: .strokeCandidateRegions
      ) ?? []
    graphicRegions = try container.decode([NormalizedRect].self, forKey: .graphicRegions)
    occupiedRegions = try container.decode([NormalizedRect].self, forKey: .occupiedRegions)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(textBlocks, forKey: .textBlocks)
    try container.encode(strokeCandidateRegions, forKey: .strokeCandidateRegions)
    try container.encode(graphicRegions, forKey: .graphicRegions)
    try container.encode(occupiedRegions, forKey: .occupiedRegions)
  }
}

public struct SlideAnalysisConfiguration: Hashable, Sendable {
  public var minimumTextConfidence: Double
  public var minimumGeometryConfidence: Double
  public var minimumTextArea: Double
  public var minimumGeometryArea: Double
  public var maximumGeometryArea: Double
  public var occupancyPadding: Double
  public var mergeTolerance: Double
  public var titleBandMaximumY: Double

  public init(
    minimumTextConfidence: Double = 0.35,
    minimumGeometryConfidence: Double = 0.50,
    minimumTextArea: Double = 0.000_1,
    minimumGeometryArea: Double = 0.002,
    maximumGeometryArea: Double = 0.90,
    occupancyPadding: Double = 0.008,
    mergeTolerance: Double = 0.002,
    titleBandMaximumY: Double = 0.28
  ) {
    self.minimumTextConfidence = min(max(minimumTextConfidence, 0), 1)
    self.minimumGeometryConfidence = min(max(minimumGeometryConfidence, 0), 1)
    self.minimumTextArea = min(max(minimumTextArea, 0), 1)
    self.minimumGeometryArea = min(max(minimumGeometryArea, 0), 1)
    self.maximumGeometryArea = min(
      max(maximumGeometryArea, self.minimumGeometryArea),
      1
    )
    self.occupancyPadding = min(max(occupancyPadding, 0), 0.25)
    self.mergeTolerance = min(max(mergeTolerance, 0), 0.25)
    self.titleBandMaximumY = min(max(titleBandMaximumY, 0), 1)
  }
}

public struct SlideAnalysisAssembler: Sendable {
  public var configuration: SlideAnalysisConfiguration

  public init(configuration: SlideAnalysisConfiguration = .init()) {
    self.configuration = configuration
  }

  public func assemble(
    textObservations: [SlideTextObservation],
    geometryObservations: [SlideGeometryObservation],
    strokeCandidateRegions: [NormalizedRect] = []
  ) -> SlideVisualAnalysis {
    let acceptedText = textObservations.compactMap(acceptedTextObservation)
      .sorted(by: spatiallyPrecedes)
    let textBlocks = acceptedText.map { observation in
      SlideTextBlock(
        id: observation.id,
        text: observation.text,
        region: observation.region
      )
    }

    let graphicRegions = geometryObservations.compactMap(acceptedGeometryRegion)
      .sorted(by: spatiallyPrecedes)
    let acceptedStrokeCandidateRegions =
      strokeCandidateRegions
      .map { $0.clamped() }
      .filter { $0.area > 0 }
      .sorted(by: spatiallyPrecedes)
    let paddedRegions = (textBlocks.map(\.region) + acceptedStrokeCandidateRegions + graphicRegions)
      .map {
        expanded($0, by: configuration.occupancyPadding)
      }
    let occupiedRegions = merged(paddedRegions).sorted(by: spatiallyPrecedes)

    return SlideVisualAnalysis(
      title: titleCandidate(in: acceptedText),
      textBlocks: textBlocks,
      strokeCandidateRegions: acceptedStrokeCandidateRegions,
      graphicRegions: graphicRegions,
      occupiedRegions: occupiedRegions
    )
  }

  private func acceptedTextObservation(
    _ observation: SlideTextObservation
  ) -> SlideTextObservation? {
    guard observation.confidence >= configuration.minimumTextConfidence else {
      return nil
    }

    let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let region = observation.region.clamped()
    guard region.area >= configuration.minimumTextArea else { return nil }

    return SlideTextObservation(
      id: observation.id,
      text: text,
      region: region,
      confidence: min(max(observation.confidence, 0), 1),
      isTitleCandidate: observation.isTitleCandidate
    )
  }

  private func acceptedGeometryRegion(
    _ observation: SlideGeometryObservation
  ) -> NormalizedRect? {
    guard observation.confidence >= configuration.minimumGeometryConfidence else {
      return nil
    }

    let region = observation.region.clamped()
    guard region.area >= configuration.minimumGeometryArea,
      region.area <= configuration.maximumGeometryArea
    else {
      return nil
    }
    return region
  }

  private func titleCandidate(in observations: [SlideTextObservation]) -> String {
    if let explicitTitle = observations.first(where: \.isTitleCandidate) {
      return explicitTitle.text
    }
    return observations.first(where: { $0.region.y <= configuration.titleBandMaximumY })?
      .text ?? ""
  }

  private func merged(_ source: [NormalizedRect]) -> [NormalizedRect] {
    var result: [NormalizedRect] = []

    for sourceRect in source where sourceRect.area > 0 {
      var candidate = sourceRect
      var index = 0
      while index < result.count {
        if touches(candidate, result[index]) {
          candidate = union(candidate, result.remove(at: index))
          index = 0
        } else {
          index += 1
        }
      }
      result.append(candidate.clamped())
    }

    return result
  }

  private func touches(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Bool {
    let tolerance = configuration.mergeTolerance
    return lhs.x <= rhs.maxX + tolerance
      && rhs.x <= lhs.maxX + tolerance
      && lhs.y <= rhs.maxY + tolerance
      && rhs.y <= lhs.maxY + tolerance
  }

  private func union(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> NormalizedRect {
    let minimumX = min(lhs.x, rhs.x)
    let minimumY = min(lhs.y, rhs.y)
    return NormalizedRect(
      x: minimumX,
      y: minimumY,
      width: max(lhs.maxX, rhs.maxX) - minimumX,
      height: max(lhs.maxY, rhs.maxY) - minimumY
    )
  }

  private func expanded(_ rect: NormalizedRect, by amount: Double) -> NormalizedRect {
    NormalizedRect(
      x: rect.x - amount,
      y: rect.y - amount,
      width: rect.width + 2 * amount,
      height: rect.height + 2 * amount
    ).clamped()
  }

  private func spatiallyPrecedes(_ lhs: SlideTextObservation, _ rhs: SlideTextObservation)
    -> Bool
  {
    spatiallyPrecedes(lhs.region, rhs.region)
  }

  private func spatiallyPrecedes(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Bool {
    if lhs.y != rhs.y { return lhs.y < rhs.y }
    if lhs.x != rhs.x { return lhs.x < rhs.x }
    if lhs.height != rhs.height { return lhs.height > rhs.height }
    return lhs.width > rhs.width
  }
}
