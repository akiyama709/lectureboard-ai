import Testing

@testable import LectureBoardCore

struct BoardSceneComposerTests {
  @Test func causalChainProducesVectorArrows() {
    let intent = BoardIntent(
      kind: .causalChain,
      title: "環境問題の構造",
      items: ["人間活動", "資源消費", "生態系への負荷"],
      sourceSegmentIDs: [],
      importance: 0.9,
      confidence: 0.9,
      language: .japanese,
      state: .confirmed
    )

    let scene = BoardSceneComposer().append(
      intents: [intent],
      to: BoardScene(slideNumber: 1),
      slideOccupied: [NormalizedRect(x: 0, y: 0, width: 0.62, height: 1)]
    )

    #expect(scene.elements.filter { $0.kind == .arrow }.count == 2)
    #expect(scene.elements.filter { $0.kind == .text }.count >= 4)
    #expect(scene.elements.allSatisfy { $0.sourceIntentID == intent.id })
  }

  @Test func comparisonProducesTwoNodesAndBidirectionalArrows() {
    let intent = BoardIntent(
      kind: .comparison,
      title: "比較",
      items: ["説明", "理解"],
      sourceSegmentIDs: [],
      importance: 0.8,
      confidence: 0.9,
      language: .japanese,
      state: .confirmed
    )

    let scene = BoardSceneComposer().append(
      intents: [intent],
      to: BoardScene(slideNumber: 1),
      slideOccupied: [NormalizedRect(x: 0, y: 0, width: 0.55, height: 1)]
    )

    #expect(scene.elements.filter { $0.kind == .arrow }.count == 2)
    #expect(scene.elements.contains { $0.text == "説明" })
    #expect(scene.elements.contains { $0.text == "理解" })
  }
}
