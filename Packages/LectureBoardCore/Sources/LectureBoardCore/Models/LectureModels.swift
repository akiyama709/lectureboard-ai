import Foundation

public struct TranscriptSegment: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var text: String
  public var startTime: TimeInterval
  public var endTime: TimeInterval
  public var language: LanguageTag
  public var confidence: Double
  public var isFinal: Bool
  public var emphasis: Double

  public init(
    id: UUID = UUID(),
    text: String,
    startTime: TimeInterval,
    endTime: TimeInterval,
    language: LanguageTag,
    confidence: Double = 1,
    isFinal: Bool = true,
    emphasis: Double = 0.5
  ) {
    self.id = id
    self.text = text
    self.startTime = startTime
    self.endTime = endTime
    self.language = language
    self.confidence = confidence
    self.isFinal = isFinal
    self.emphasis = emphasis
  }
}

public struct SlideTextBlock: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var text: String
  public var region: NormalizedRect

  public init(id: UUID = UUID(), text: String, region: NormalizedRect) {
    self.id = id
    self.text = text
    self.region = region
  }
}

public struct SlideContext: Codable, Hashable, Sendable {
  public var slideNumber: Int
  public var title: String
  public var textBlocks: [SlideTextBlock]
  public var speakerNotes: String
  public var occupiedRegions: [NormalizedRect]
  public var dwellTime: TimeInterval
  public var languages: [LanguageTag]

  public init(
    slideNumber: Int,
    title: String,
    textBlocks: [SlideTextBlock] = [],
    speakerNotes: String = "",
    occupiedRegions: [NormalizedRect] = [],
    dwellTime: TimeInterval = 0,
    languages: [LanguageTag] = []
  ) {
    self.slideNumber = slideNumber
    self.title = title
    self.textBlocks = textBlocks
    self.speakerNotes = speakerNotes
    self.occupiedRegions = occupiedRegions
    self.dwellTime = dwellTime
    self.languages = languages
  }

  public var searchableText: String {
    ([title] + textBlocks.map(\.text) + [speakerNotes]).joined(separator: " ")
  }
}
