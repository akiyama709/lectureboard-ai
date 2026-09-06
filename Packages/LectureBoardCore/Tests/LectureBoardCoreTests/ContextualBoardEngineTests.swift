import Foundation
import Testing

@testable import LectureBoardCore

struct ContextualBoardEngineTests {
  @Test func confirmsSlideGroundedEnglishDefinitionWithProductionDefaults() throws {
    let segment = TranscriptSegment(
      text: "Sustainability means meeting present needs without undermining future possibilities.",
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 0.5,
      emphasis: 0.5
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "Sustainability",
      occupiedRegions: [NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)],
      dwellTime: 40,
      languages: [.englishUS]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.importance < 0.78)
    #expect(intent.kind == .definition)
    #expect(intent.title == "Sustainability")
    #expect(intent.items == ["meeting present needs without undermining future possibilities"])
    #expect(intent.sourceSegmentIDs == [segment.id])
    #expect(intent.state == .confirmed)

    let scene = publicScene(for: intents, slide: slide)
    #expect(!scene.elements.isEmpty)
    #expect(scene.elements.contains { $0.text == "Sustainability" })
    #expect(
      scene.elements.contains {
        $0.text?.contains("meeting present needs without undermining future possibilities") == true
      }
    )
  }

  @Test func confirmsSlideGroundedJapaneseDefinitionWithProductionDefaults() throws {
    let segment = TranscriptSegment(
      text: "統合知とは，認識，価値及び実践を結び付ける知の働きです．",
      startTime: 0,
      endTime: 8,
      language: .japanese,
      confidence: 0.5,
      emphasis: 0.5
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "統合知",
      occupiedRegions: [NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)],
      dwellTime: 40,
      languages: [.japanese]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.importance < 0.78)
    #expect(intent.kind == .definition)
    #expect(intent.title == "統合知")
    #expect(intent.items == ["認識，価値及び実践を結び付ける知の働きです"])
    #expect(intent.sourceSegmentIDs == [segment.id])
    #expect(intent.state == .confirmed)

    let scene = publicScene(for: intents, slide: slide)
    #expect(!scene.elements.isEmpty)
    #expect(scene.elements.contains { $0.text == "統合知" })
    #expect(
      scene.elements.contains {
        $0.text?.contains("認識，価値及び実践を結び付ける知の働きです") == true
      }
    )
  }

  @Test func keepsUngroundedDefinitionProposedAndOutOfPublicScene() throws {
    let segment = TranscriptSegment(
      text: "統合知とは，認識と実践を結び付ける知の働きです．",
      startTime: 0,
      endTime: 8,
      language: .japanese,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "別の論点",
      dwellTime: 120,
      languages: [.japanese]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func keepsLowConfidenceExplicitDefinitionOutOfPublicScene() throws {
    let segment = TranscriptSegment(
      text: "統合知とは，誤認識された説明です．",
      startTime: 0,
      endTime: 8,
      language: .japanese,
      confidence: 0,
      emphasis: 0.5
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "統合知",
      dwellTime: 40,
      languages: [.japanese]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func keepsNonfiniteConfidenceExplicitDefinitionOutOfPublicScene() throws {
    let segment = TranscriptSegment(
      text: "統合知とは，誤認識された説明です．",
      startTime: 0,
      endTime: 8,
      language: .japanese,
      confidence: .nan,
      emphasis: 0.5
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "統合知",
      dwellTime: 40,
      languages: [.japanese]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func rejectsDefinitionWithAnUnrelatedFollowingSentence() throws {
    let segment = TranscriptSegment(
      text: "Sustainability means meeting present needs. The speaker changes topic.",
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "Sustainability",
      dwellTime: 120,
      languages: [.englishUS]
    )
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    let intents = engine.propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func requiresASCIITermBoundariesForDefinitionGrounding() throws {
    let segment = TranscriptSegment(
      text: "AI means automated instruction.",
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 1,
      emphasis: 0.5
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "Chair discussion",
      dwellTime: 40,
      languages: [.englishUS]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func rejectsDefinitionLikeStatementsAndQuestionsFromPublicScene() throws {
    let examples: [(text: String, title: String, language: LanguageTag)] = [
      ("私は彼とは話しません．", "会話", .japanese),
      ("統合知とは何ですか？", "統合知", .japanese),
      ("統合知とは何でしょうか．", "統合知", .japanese),
      ("統合知とはどのようなものか", "統合知", .japanese),
      ("Sustainability means what?", "Sustainability", .englishUS),
      ("Sustainability means which idea", "Sustainability", .englishUS),
    ]
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    for example in examples {
      let slide = SlideContext(
        slideNumber: 1,
        title: example.title,
        dwellTime: 120,
        languages: [example.language]
      )
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 4,
        language: example.language,
        confidence: 1,
        emphasis: 1
      )

      let intents = engine.propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .proposed, "Unexpected confirmation for: \(example.text)")
      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unexpected public scene for: \(example.text)"
      )
    }
  }

  @Test func rejectsBareComparisonSubstringsFromPublicScene() throws {
    let examples = [
      "これは一方向への移動です．",
      "道路は一方通行です．",
    ]
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    for text in examples {
      let slide = SlideContext(slideNumber: 1, title: "交通", dwellTime: 120)
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: .japanese,
        confidence: 1,
        emphasis: 1
      )

      let intents = engine.propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.kind == .comparison)
      #expect(intent.state == .proposed, "Unexpected confirmation for: \(text)")
      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unexpected public scene for: \(text)"
      )
    }
  }

  @Test func rejectsSingleOrdinalSubstringsFromPublicScene() throws {
    let examples: [(text: String, language: LanguageTag)] = [
      ("第一印象が重要です．以上です．", .japanese),
      ("The first result used 1,000 observations.", .englishUS),
    ]
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    for example in examples {
      let slide = SlideContext(
        slideNumber: 1,
        title: "結果",
        dwellTime: 120,
        languages: [example.language]
      )
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 4,
        language: example.language,
        confidence: 1,
        emphasis: 1
      )

      let intents = engine.propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.kind == .list)
      #expect(intent.state == .proposed, "Unexpected confirmation for: \(example.text)")
      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unexpected public scene for: \(example.text)"
      )
    }
  }

  @Test func preservesForwardCausalOrder() throws {
    let segment = TranscriptSegment(
      text: "資源消費が増えます．そのため生態系への負荷が高まります．",
      startTime: 0,
      endTime: 6,
      language: .japanese,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "環境変化", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .causalChain)
    #expect(intent.items == ["資源消費が増えます", "生態系への負荷が高まります"])
    #expect(intent.state == .confirmed)
  }

  @Test func reversesResultOfClauseIntoCauseThenEffectOrder() throws {
    let segment = TranscriptSegment(
      text: "Flooding occurs as a result of heavy rainfall.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "Flood risk", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .causalChain)
    #expect(intent.items == ["heavy rainfall", "Flooding occurs"])
    #expect(intent.state == .confirmed)
  }

  @Test func rejectsAmbiguousCausalGrammarFromPublicScene() throws {
    let examples = [
      "The causes are land-use change and warming.",
      "The results in this study are preliminary.",
      "The word because appears on this slide.",
      "We use because in causal explanations.",
      "We say 'because' in causal explanations.",
    ]
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    for text in examples {
      let slide = SlideContext(slideNumber: 1, title: "Environmental change", dwellTime: 40)
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 6,
        language: .englishUS,
        confidence: 1,
        emphasis: 0.5
      )

      let intents = engine.propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .proposed, "Unexpected confirmation for: \(text)")
      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unexpected public scene for: \(text)"
      )
    }
  }

  @Test func rejectsJapaneseCausalCueSubstringInsideReservoir() throws {
    let segment = TranscriptSegment(
      text: "私はそのため池を訪れます．",
      startTime: 0,
      endTime: 6,
      language: .japanese,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "地域調査", dwellTime: 120)
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    let intents = engine.propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .causalChain)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func rejectsCausalCueWithUnrelatedSurroundingSentences() throws {
    let segment = TranscriptSegment(
      text:
        "We first review the evidence. Rainfall rises. "
        + "Therefore flooding increases. Next, inspect the map.",
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 1,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "Flood risk", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .causalChain)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func reversesBecauseClauseIntoCauseThenEffectOrder() throws {
    let segment = TranscriptSegment(
      text: "The ecosystem is stressed because resource use increases.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "Environmental change", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .causalChain)
    #expect(intent.items == ["resource use increases", "The ecosystem is stressed"])
    #expect(intent.state == .confirmed)
  }

  @Test func confirmsSafeJapaneseAndEnglishComparisons() throws {
    let examples: [(text: String, expected: [String], language: LanguageTag)] = [
      (
        "地域Aでは降水が増えます．一方で，地域Bでは乾燥が進みます．",
        ["地域Aでは降水が増えます", "地域Bでは乾燥が進みます"],
        .japanese
      ),
      (
        "Local action is immediate, whereas global coordination is slower.",
        ["Local action is immediate", "global coordination is slower"],
        .englishUS
      ),
    ]

    for example in examples {
      let slide = SlideContext(
        slideNumber: 1,
        title: "Comparison",
        dwellTime: 120,
        languages: [example.language]
      )
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 6,
        language: example.language,
        confidence: 1,
        emphasis: 1
      )

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.kind == .comparison)
      #expect(intent.items == example.expected)
      #expect(intent.state == .confirmed)
      #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func rejectsAmbiguousComparisonCueFromPublicScene() throws {
    let segment = TranscriptSegment(
      text: "背景を述べます．これに対して説明します．",
      startTime: 0,
      endTime: 6,
      language: .japanese,
      confidence: 1,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "講義", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .comparison)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func confirmsOnlyListsWithTwoOrderedMarkers() throws {
    let examples: [(text: String, expected: [String], language: LanguageTag)] = [
      (
        "第一に，観察します．第二に，比較します．",
        ["観察します", "比較します"],
        .japanese
      ),
      (
        "First, observe the pattern. Second, compare the cases.",
        ["observe the pattern", "compare the cases"],
        .englishUS
      ),
    ]

    for example in examples {
      let slide = SlideContext(
        slideNumber: 1,
        title: "Key points",
        dwellTime: 120,
        languages: [example.language]
      )
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 6,
        language: example.language,
        confidence: 1,
        emphasis: 1
      )

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.kind == .list)
      #expect(intent.items == example.expected)
      #expect(intent.state == .confirmed)
      #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func rejectsOrdinalPrefixesInsideWordsFromPublicScene() throws {
    let segment = TranscriptSegment(
      text: "Firsthand evidence is direct. Secondhand evidence is indirect.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "Research methods", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .list)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func rejectsListWithAnUnrelatedFollowingSentence() throws {
    let segment = TranscriptSegment(
      text: "First, preserve evidence. Second, record provenance. This sentence is unrelated.",
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "Research method", dwellTime: 120)
    let engine = ContextualBoardEngine(scorer: ImportanceScorer(threshold: 0))

    let intents = engine.propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .list)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func matchesDefinitionCaseInsensitivelyAcrossMultipleSpaces() throws {
    let segment = TranscriptSegment(
      text: "Systems Thinking IS   DEFINED   AS connecting parts and relationships.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "  systems   thinking  ",
      dwellTime: 120,
      languages: [.englishUS]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.title == "Systems Thinking")
    #expect(intent.items == ["connecting parts and relationships"])
    #expect(intent.state == .confirmed)
  }

  @Test func preservesCSharpAndDotNetDefinitionTerm() throws {
    let segment = TranscriptSegment(
      text: "C#/.NET means managed-platform interoperability.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "C#/.NET",
      dwellTime: 120,
      languages: [.englishUS]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.title == "C#/.NET")
    #expect(intent.items == ["managed-platform interoperability"])
    #expect(intent.state == .confirmed)
  }

  @Test func partialSegmentsCannotSupplyRepeatedConfirmation() throws {
    let final = TranscriptSegment(
      text: "Why does the system change?",
      startTime: 0,
      endTime: 4,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 1
    )
    let partials = (1...3).map { index in
      TranscriptSegment(
        text: final.text,
        startTime: Double(index),
        endTime: Double(index + 1),
        language: .englishUS,
        confidence: 1,
        isFinal: false,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "System change", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [final] + partials
    )
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.kind == .question)
    #expect(intent.sourceSegmentIDs == [final.id])
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func fourFinalRepetitionsConfirmOneGenericQuestionWithDistinctEvidence() throws {
    let segments = repeatedQuestionSegments()
    let slide = SlideContext(slideNumber: 1, title: "System change", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.kind == .question)
    #expect(intent.items == ["Why does the system change?"])
    #expect(intent.state == .confirmed)
    #expect(intent.sourceSegmentIDs.count == 4)
    #expect(Set(intent.sourceSegmentIDs).count == 4)
    #expect(Set(intent.sourceSegmentIDs) == Set(segments.map(\.id)))
    #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func doesNotMergeQuestionsAndAssertionsAsRepeatedEvidence() throws {
    let texts = [
      "The system is safe.",
      "The system is safe?",
      "The system is safe!",
      "The system is safe.",
    ]
    let segments = texts.enumerated().map { index, text in
      TranscriptSegment(
        text: text,
        startTime: Double(index * 4),
        endTime: Double(index * 4 + 3),
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "Safety", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)

    #expect(intents.allSatisfy { $0.state == .proposed })
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func repeatedStatementsRemainProposed() throws {
    let segments = (0..<4).map { index in
      TranscriptSegment(
        text: "The system is safe.",
        startTime: Double(index * 4),
        endTime: Double(index * 4 + 3),
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "Safety", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)

    #expect(intents.allSatisfy { $0.state == .proposed })
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func repeatedDeclarativeWhClauseRemainsProposed() throws {
    let segments = (0..<4).map { index in
      TranscriptSegment(
        text: "What matters is context.",
        startTime: Double(index * 4),
        endTime: Double(index * 4 + 3),
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)

    #expect(intents.allSatisfy { $0.state == .proposed })
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func duplicateIntervalsCannotSupplyRepeatedEvidence() throws {
    let segments = (0..<4).map { _ in
      TranscriptSegment(
        text: "Why does the system change?",
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "System change", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)

    #expect(intents.allSatisfy { $0.state == .proposed })
    #expect(intents.allSatisfy { $0.sourceSegmentIDs.count == 1 })
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func suppressesExistingPublicDuplicateDespiteTerminalPunctuation() {
    let segment = TranscriptSegment(
      text: "統合知とは，認識と実践を結びます．",
      startTime: 0,
      endTime: 6,
      language: .japanese,
      confidence: 1,
      emphasis: 1
    )
    let existing = BoardIntent(
      kind: .definition,
      title: "統合知．",
      items: ["認識と実践を結びます！"],
      sourceSegmentIDs: [UUID()],
      importance: 0.9,
      confidence: 1,
      language: .japanese,
      state: .confirmed
    )

    let result = ContextualBoardEngine().propose(
      slide: SlideContext(slideNumber: 1, title: "統合知", dwellTime: 120),
      recentSegments: [segment],
      existingIntents: [existing]
    )

    #expect(result.isEmpty)
  }

  @Test func existingProposedDuplicateDoesNotBlockRepeatedPromotion() throws {
    let segments = repeatedQuestionSegments()
    let slide = SlideContext(slideNumber: 1, title: "System change", dwellTime: 120)
    let existing = BoardIntent(
      kind: .question,
      title: slide.title,
      items: ["Why does the system change?"],
      sourceSegmentIDs: [UUID()],
      importance: 0.7,
      confidence: 1,
      language: .englishUS,
      state: .proposed
    )

    let intents = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: segments,
      existingIntents: [existing]
    )
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.kind == .question)
    #expect(intent.state == .confirmed)
    #expect(Set(intent.sourceSegmentIDs) == Set(segments.map(\.id)))
  }

  @Test func suppressesSamePassPublicDuplicates() throws {
    let segments = (0..<2).map { index in
      TranscriptSegment(
        text: "統合知とは，認識と実践を結びます．",
        startTime: Double(index * 6),
        endTime: Double(index * 6 + 5),
        language: .japanese,
        confidence: 1,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "統合知", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.kind == .definition)
    #expect(intent.state == .confirmed)
    #expect(segments.map(\.id).contains(intent.sourceSegmentIDs[0]))
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

  @Test func keepsAThresholdPassingCandidateProposedUntilConfirmed() throws {
    let segment = TranscriptSegment(
      text: "Why does this happen?",
      startTime: 0,
      endTime: 4,
      language: .englishUS,
      confidence: 0,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 2, title: "Topic", dwellTime: 60)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.importance >= 0.58)
    #expect(intent.importance < 0.78)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func nonpositiveProposalLimitReturnsEmptyWithoutTrapping() {
    let segment = TranscriptSegment(
      text: "Sustainability means preserving future possibilities.",
      startTime: 0,
      endTime: 4,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "Sustainability", dwellTime: 120)

    #expect(
      ContextualBoardEngine(maximumProposalsPerPass: 0).propose(
        slide: slide,
        recentSegments: [segment]
      ).isEmpty
    )
    #expect(
      ContextualBoardEngine(maximumProposalsPerPass: -1).propose(
        slide: slide,
        recentSegments: [segment]
      ).isEmpty
    )
  }

  private func publicScene(for intents: [BoardIntent], slide: SlideContext) -> BoardScene {
    BoardSceneComposer().append(
      intents: intents,
      to: BoardScene(slideNumber: slide.slideNumber),
      slideOccupied: slide.occupiedRegions
    )
  }

  private func repeatedQuestionSegments() -> [TranscriptSegment] {
    (0..<4).map { index in
      TranscriptSegment(
        text: "Why does the system change?",
        startTime: Double(index * 4),
        endTime: Double(index * 4 + 3),
        language: .englishUS,
        confidence: 1,
        isFinal: true,
        emphasis: 0.5
      )
    }
  }
}
