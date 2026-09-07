import Foundation

public struct BoardLayoutEngine: Sendable {
  public var margin: Double
  public var gridStep: Double

  public init(margin: Double = 0.015, gridStep: Double = 0.02) {
    self.margin = margin
    self.gridStep = gridStep
  }

  public func placement(
    for intent: BoardIntent,
    slideOccupied: [NormalizedRect],
    boardOccupied: [NormalizedRect]
  ) -> NormalizedRect? {
    let obstacles = (slideOccupied + boardOccupied).map { expanded($0, by: margin) }
    for size in candidateSizes(for: intent) {
      let available = candidateRects(size: size).filter { candidate in
        obstacles.allSatisfy { candidate.intersectionArea(with: $0) <= 0.0001 }
      }
      if let placement = available.max(by: {
        score($0, intent: intent) < score($1, intent: intent)
      }) {
        return placement
      }
    }
    return nil
  }

  private func candidateSizes(for intent: BoardIntent) -> [(width: Double, height: Double)] {
    let desired = desiredSize(for: intent.kind)
    guard intent.kind == .keyword, hasCompactKeywordContent(intent) else { return [desired] }
    return [desired, (0.24, 0.15), (0.20, 0.12)]
  }

  private func hasCompactKeywordContent(_ intent: BoardIntent) -> Bool {
    guard intent.items.count == 1 else { return false }
    let itemLength = intent.items[0].reduce(into: 0) { count, character in
      if !character.isWhitespace { count += 1 }
    }
    return (1...24).contains(itemLength)
  }

  private func desiredSize(for kind: BoardIntentKind) -> (width: Double, height: Double) {
    switch kind {
    case .causalChain, .conceptMap:
      return (0.30, 0.34)
    case .comparison:
      return (0.38, 0.26)
    case .definition, .warning:
      return (0.30, 0.22)
    case .list:
      return (0.30, 0.28)
    case .question, .example, .keyword:
      return (0.30, 0.18)
    }
  }

  private func candidateRects(size: (width: Double, height: Double)) -> [NormalizedRect] {
    var result: [NormalizedRect] = []
    var y = margin
    while y + size.height <= 1 - margin {
      var x = margin
      while x + size.width <= 1 - margin {
        result.append(NormalizedRect(x: x, y: y, width: size.width, height: size.height))
        x += gridStep
      }
      y += gridStep
    }
    return result
  }

  private func expanded(_ rect: NormalizedRect, by amount: Double) -> NormalizedRect {
    NormalizedRect(
      x: rect.x - amount,
      y: rect.y - amount,
      width: rect.width + 2 * amount,
      height: rect.height + 2 * amount
    ).clamped()
  }

  private func score(_ candidate: NormalizedRect, intent: BoardIntent) -> Double {
    if let preferred = intent.preferredRegion {
      return candidate.intersectionArea(with: preferred) * 12
    }
    let rightPreference = candidate.x + candidate.width / 2
    let lowerPreference = candidate.y + candidate.height / 2
    let edgePenalty = min(candidate.x, candidate.y, 1 - candidate.maxX, 1 - candidate.maxY)
    return 0.62 * rightPreference + 0.23 * lowerPreference + 0.15 * edgePenalty
  }
}
