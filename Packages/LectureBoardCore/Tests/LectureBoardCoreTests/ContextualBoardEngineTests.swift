import Testing

@testable import LectureBoardCore

struct ContextualBoardEngineTests {
  @Test func classifiesGroundedDefinitionWithoutVoiceCommand() {
    let segment = TranscriptSegment(
      text: "Sustainability means meeting present needs without undermining future possibilities.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0.8
    )
    let slide = SlideContext(slideNumber: 1, title: "Sustainability", dwellTime: 35)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

    #expect(intents.count == 1)
    #expect(intents[0].kind == .definition)
    #expect(intents[0].title == "Sustainability")
    #expect(intents[0].items[0].contains("meeting present needs"))
    #expect(intents[0].sourceSegmentIDs == [segment.id])
  }

  @Test func classifiesCausalExplanation() {
    let segment = TranscriptSegment(
      text: "人間活動が拡大し，そのため資源消費が増え，結果として生態系への負荷が高まります．",
      startTime: 5,
      endTime: 12,
      language: .japanese,
      emphasis: 0.9
    )
    let slide = SlideContext(slideNumber: 3, title: "環境問題の構造", dwellTime: 50)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

    #expect(intents.first?.kind == .causalChain)
    #expect((intents.first?.items.count ?? 0) >= 2)
  }

  @Test func doesNotRepeatAlreadyUsedTranscriptEvidence() {
    let segment = TranscriptSegment(
      text: "統合知とは認識，価値，実践を結ぶことです．",
      startTime: 0,
      endTime: 5,
      language: .japanese,
      emphasis: 0.9
    )
    let existing = BoardIntent(
      kind: .definition,
      title: "統合知",
      items: ["認識，価値，実践を結ぶ"],
      sourceSegmentIDs: [segment.id],
      importance: 0.9,
      confidence: 0.9,
      language: .japanese,
      state: .confirmed
    )

    let result = ContextualBoardEngine().propose(
      slide: SlideContext(slideNumber: 1, title: "統合知"),
      recentSegments: [segment],
      existingIntents: [existing]
    )

    #expect(result.isEmpty)
  }

  @Test func keepsAThresholdPassingCandidateProposedUntilConfirmed() {
    let segment = TranscriptSegment(
      text: "Why does this happen?",
      startTime: 0,
      endTime: 4,
      language: .englishUS,
      confidence: 0.9,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 2, title: "Topic", dwellTime: 60)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

    #expect(intents.count == 1)
    #expect(intents.first?.importance ?? 0 >= 0.58)
    #expect(intents.first?.importance ?? 1 < 0.78)
    #expect(intents.first?.state == .proposed)
  }
}
