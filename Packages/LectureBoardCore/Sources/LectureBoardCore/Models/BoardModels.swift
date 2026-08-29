import Foundation

public enum BoardIntentKind: String, Codable, CaseIterable, Sendable {
  case keyword
  case definition
  case list
  case causalChain
  case comparison
  case conceptMap
  case question
  case warning
  case example
}

public enum BoardIntentState: String, Codable, Sendable {
  case deferred
  case proposed
  case confirmed
  case pinned
  case dismissed
}

public struct BoardIntent: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var kind: BoardIntentKind
  public var title: String
  public var items: [String]
  public var sourceSegmentIDs: [UUID]
  public var importance: Double
  public var confidence: Double
  public var language: LanguageTag
  public var preferredRegion: NormalizedRect?
  public var state: BoardIntentState

  public init(
    id: UUID = UUID(),
    kind: BoardIntentKind,
    title: String,
    items: [String],
    sourceSegmentIDs: [UUID],
    importance: Double,
    confidence: Double,
    language: LanguageTag,
    preferredRegion: NormalizedRect? = nil,
    state: BoardIntentState = .proposed
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.items = items
    self.sourceSegmentIDs = sourceSegmentIDs
    self.importance = importance
    self.confidence = confidence
    self.language = language
    self.preferredRegion = preferredRegion
    self.state = state
  }
}

public enum BoardElementKind: String, Codable, Sendable {
  case text
  case roundedRectangle
  case ellipse
  case line
  case arrow
}

public enum BoardStyleRole: String, Codable, Sendable {
  case primary
  case secondary
  case emphasis
  case caution
}

public struct NormalizedPoint: Codable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct BoardElement: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public var kind: BoardElementKind
  public var region: NormalizedRect
  public var text: String?
  public var points: [NormalizedPoint]
  public var role: BoardStyleRole
  public var sourceIntentID: UUID?

  public init(
    id: UUID = UUID(),
    kind: BoardElementKind,
    region: NormalizedRect,
    text: String? = nil,
    points: [NormalizedPoint] = [],
    role: BoardStyleRole = .primary,
    sourceIntentID: UUID? = nil
  ) {
    self.id = id
    self.kind = kind
    self.region = region
    self.text = text
    self.points = points
    self.role = role
    self.sourceIntentID = sourceIntentID
  }
}

public struct BoardScene: Codable, Hashable, Sendable {
  public var slideNumber: Int
  public var elements: [BoardElement]

  public init(slideNumber: Int, elements: [BoardElement] = []) {
    self.slideNumber = slideNumber
    self.elements = elements
  }

  public var occupiedRegions: [NormalizedRect] {
    elements.map(\.region)
  }
}
