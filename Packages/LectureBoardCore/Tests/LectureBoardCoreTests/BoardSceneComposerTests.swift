import Testing

@testable import LectureBoardCore

struct BoardSceneComposerTests {
  @Test func rendersOnlyConfirmedAndPinnedIntentStates() {
    let cases: [(state: BoardIntentState, shouldRender: Bool)] = [
      (.deferred, false),
      (.proposed, false),
      (.confirmed, true),
      (.pinned, true),
      (.dismissed, false),
    ]
    #expect(cases.count == BoardIntentState.allCases.count)
    #expect(
      BoardIntentState.allCases.allSatisfy { state in
        cases.contains { $0.state == state }
      }
    )

    for testCase in cases {
      let intent = makeIntent(state: testCase.state)
      let scene = BoardSceneComposer().append(
        intents: [intent],
        to: BoardScene(slideNumber: 1),
        slideOccupied: []
      )

      #expect(
        scene.elements.isEmpty == !testCase.shouldRender,
        "Unexpected public-scene visibility for \(testCase.state)"
      )
    }
  }

  @Test func unapprovedIntentStatesDoNotChangeAnExistingScene() {
    let existingScene = BoardScene(
      slideNumber: 4,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
          text: "Existing confirmed content"
        )
      ]
    )

    for state in [BoardIntentState.proposed, .deferred, .dismissed] {
      let result = BoardSceneComposer().append(
        intents: [makeIntent(state: state)],
        to: existingScene,
        slideOccupied: []
      )

      #expect(result == existingScene, "\(state) changed an existing public scene")
    }
  }

  @Test func mixedInputElementsReferenceOnlyAllowedIntentIDs() {
    let deferred = makeIntent(title: "Deferred", state: .deferred)
    let proposed = makeIntent(title: "Proposed", state: .proposed)
    let confirmed = makeIntent(title: "Confirmed", state: .confirmed)
    let pinned = makeIntent(title: "Pinned", state: .pinned)
    let dismissed = makeIntent(title: "Dismissed", state: .dismissed)

    let scene = BoardSceneComposer().append(
      intents: [deferred, proposed, confirmed, pinned, dismissed],
      to: BoardScene(slideNumber: 1),
      slideOccupied: []
    )

    let renderedIntentIDs = Set(scene.elements.compactMap(\.sourceIntentID))
    #expect(renderedIntentIDs == Set([confirmed.id, pinned.id]))
  }

  @Test func reportsOnlyPlacedIntentAndAllowsUnplacedIntentToBeRetried() {
    let composer = BoardSceneComposer(
      layoutEngine: BoardLayoutEngine(margin: 0.015, gridStep: 1)
    )
    let first = makeIntent(title: "First", state: .confirmed)
    let second = makeIntent(title: "Second", state: .confirmed)

    let initial = composer.appending(
      intents: [first, second],
      to: BoardScene(slideNumber: 1),
      slideOccupied: []
    )

    #expect(initial.placedIntents == [first])
    #expect(initial.unplacedIntents == [second])
    #expect(Set(initial.scene.elements.compactMap(\.sourceIntentID)) == [first.id])

    let retried = composer.appending(
      intents: initial.unplacedIntents,
      to: BoardScene(slideNumber: 1),
      slideOccupied: []
    )

    #expect(retried.placedIntents == [second])
    #expect(retried.unplacedIntents.isEmpty)
    #expect(Set(retried.scene.elements.compactMap(\.sourceIntentID)) == [second.id])
  }

  @Test func completelyUnavailableLayoutDoesNotReportAnIntentAsPlaced() {
    let composer = BoardSceneComposer(
      layoutEngine: BoardLayoutEngine(margin: 0.51, gridStep: 0.02)
    )
    let intent = makeIntent(state: .confirmed)
    let original = BoardScene(slideNumber: 3)

    let result = composer.appending(
      intents: [intent],
      to: original,
      slideOccupied: []
    )

    #expect(result.scene == original)
    #expect(result.placedIntents.isEmpty)
    #expect(result.unplacedIntents == [intent])
  }

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

  private func makeIntent(
    title: String = "Intent",
    state: BoardIntentState
  ) -> BoardIntent {
    BoardIntent(
      kind: .keyword,
      title: title,
      items: ["Item"],
      sourceSegmentIDs: [],
      importance: 0.8,
      confidence: 0.9,
      language: .englishUS,
      state: state
    )
  }
}
