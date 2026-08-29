import Foundation

public struct BoardSceneComposer: Sendable {
  public var layoutEngine: BoardLayoutEngine

  public init(layoutEngine: BoardLayoutEngine = BoardLayoutEngine()) {
    self.layoutEngine = layoutEngine
  }

  public func append(
    intents: [BoardIntent],
    to scene: BoardScene,
    slideOccupied: [NormalizedRect]
  ) -> BoardScene {
    var result = scene

    for intent in intents where intent.state != .dismissed && intent.state != .deferred {
      guard
        let region = layoutEngine.placement(
          for: intent,
          slideOccupied: slideOccupied,
          boardOccupied: result.occupiedRegions
        )
      else { continue }

      result.elements.append(contentsOf: elements(for: intent, in: region))
    }

    return result
  }

  private func elements(for intent: BoardIntent, in region: NormalizedRect) -> [BoardElement] {
    let frame = BoardElement(
      kind: .roundedRectangle,
      region: region,
      role: intent.importance >= 0.78 ? .emphasis : .secondary,
      sourceIntentID: intent.id
    )

    let titleRegion = NormalizedRect(
      x: region.x + 0.02,
      y: region.y + 0.02,
      width: max(0.05, region.width - 0.04),
      height: min(0.07, region.height * 0.28)
    )
    let title = BoardElement(
      kind: .text,
      region: titleRegion,
      text: intent.title,
      role: .emphasis,
      sourceIntentID: intent.id
    )

    let bodyRegion = NormalizedRect(
      x: region.x + 0.02,
      y: titleRegion.maxY + 0.01,
      width: max(0.05, region.width - 0.04),
      height: max(0.05, region.maxY - titleRegion.maxY - 0.03)
    )

    switch intent.kind {
    case .causalChain where intent.items.count >= 2:
      return [frame, title] + causalChainElements(for: intent, in: bodyRegion)
    case .comparison where intent.items.count >= 2:
      return [frame, title] + comparisonElements(for: intent, in: bodyRegion)
    default:
      return [
        frame,
        title,
        BoardElement(
          kind: .text,
          region: bodyRegion,
          text: intent.items.map { "• \($0)" }.joined(separator: "\n"),
          role: .primary,
          sourceIntentID: intent.id
        ),
      ]
    }
  }

  private func causalChainElements(
    for intent: BoardIntent,
    in region: NormalizedRect
  ) -> [BoardElement] {
    let items = Array(intent.items.prefix(4))
    let count = Double(items.count)
    let gap = min(0.025, region.height * 0.09)
    let nodeHeight = max(0.035, (region.height - gap * (count - 1)) / count)
    var elements: [BoardElement] = []
    var nodeRegions: [NormalizedRect] = []

    for (index, item) in items.enumerated() {
      let node = NormalizedRect(
        x: region.x + region.width * 0.06,
        y: region.y + Double(index) * (nodeHeight + gap),
        width: region.width * 0.88,
        height: nodeHeight
      )
      nodeRegions.append(node)
      elements.append(
        BoardElement(
          kind: .roundedRectangle,
          region: node,
          role: .secondary,
          sourceIntentID: intent.id
        )
      )
      elements.append(
        BoardElement(
          kind: .text,
          region: node.inset(by: min(0.008, node.height * 0.12)),
          text: item,
          role: .primary,
          sourceIntentID: intent.id
        )
      )
    }

    for index in 0..<(nodeRegions.count - 1) {
      let from = nodeRegions[index]
      let to = nodeRegions[index + 1]
      let start = NormalizedPoint(x: from.x + from.width / 2, y: from.maxY)
      let end = NormalizedPoint(x: to.x + to.width / 2, y: to.y)
      elements.append(
        BoardElement(
          kind: .arrow,
          region: boundingRegion(from: start, to: end),
          points: [start, end],
          role: .emphasis,
          sourceIntentID: intent.id
        )
      )
    }

    return elements
  }

  private func comparisonElements(
    for intent: BoardIntent,
    in region: NormalizedRect
  ) -> [BoardElement] {
    let left = NormalizedRect(
      x: region.x,
      y: region.y + region.height * 0.12,
      width: region.width * 0.42,
      height: region.height * 0.72
    )
    let right = NormalizedRect(
      x: region.x + region.width * 0.58,
      y: region.y + region.height * 0.12,
      width: region.width * 0.42,
      height: region.height * 0.72
    )
    let start = NormalizedPoint(x: left.maxX + region.width * 0.02, y: region.y + region.height / 2)
    let end = NormalizedPoint(x: right.x - region.width * 0.02, y: region.y + region.height / 2)

    return [
      BoardElement(
        kind: .roundedRectangle,
        region: left,
        role: .secondary,
        sourceIntentID: intent.id
      ),
      BoardElement(
        kind: .text,
        region: left.inset(by: min(0.01, left.height * 0.1)),
        text: intent.items[0],
        role: .primary,
        sourceIntentID: intent.id
      ),
      BoardElement(
        kind: .roundedRectangle,
        region: right,
        role: .secondary,
        sourceIntentID: intent.id
      ),
      BoardElement(
        kind: .text,
        region: right.inset(by: min(0.01, right.height * 0.1)),
        text: intent.items[1],
        role: .primary,
        sourceIntentID: intent.id
      ),
      BoardElement(
        kind: .arrow,
        region: boundingRegion(from: start, to: end),
        points: [start, end],
        role: .emphasis,
        sourceIntentID: intent.id
      ),
      BoardElement(
        kind: .arrow,
        region: boundingRegion(from: end, to: start),
        points: [end, start],
        role: .emphasis,
        sourceIntentID: intent.id
      ),
    ]
  }

  private func boundingRegion(
    from start: NormalizedPoint,
    to end: NormalizedPoint
  ) -> NormalizedRect {
    let margin = 0.01
    return NormalizedRect(
      x: min(start.x, end.x) - margin,
      y: min(start.y, end.y) - margin,
      width: abs(end.x - start.x) + margin * 2,
      height: abs(end.y - start.y) + margin * 2
    ).clamped()
  }
}
