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

  @Test func doesNotUseAQuestionAsEvidenceForRepeatedAssertionConfirmation() throws {
    let texts = [
      "The system is safe.",
      "The system is safe?",
      "The system is safe?",
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
    let slide = SlideContext(slideNumber: 1, title: "Safety")
    let engine = ContextualBoardEngine(maximumProposalsPerPass: 10)

    let intents = engine.propose(slide: slide, recentSegments: segments)

    let firstAssertion = try #require(
      intents.first { $0.sourceSegmentIDs == [segments[0].id] }
    )

    #expect(firstAssertion.kind == .keyword)
    #expect(firstAssertion.importance >= 0.66)
    #expect(firstAssertion.state == .proposed)
    #expect(intents.allSatisfy { $0.state == .proposed })
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func repeatedReliableHighImportanceKeywordAssertionBecomesPublic() throws {
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

    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.kind == .keyword)
    #expect(intent.state == .confirmed)
    #expect(intent.importance >= 0.66)
    #expect(intent.sourceSegmentIDs.count == 4)
    #expect(Set(intent.sourceSegmentIDs) == Set(segments.map(\.id)))
    #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func repeatedUnsafeAssertionsNeverBecomePublic() {
    let examples: [(String, LanguageTag)] = [
      ("Now we discuss context.", .englishUS),
      ("Context is next.", .englishUS),
      ("文脈について話します．", .japanese),
      ("今日は文脈を扱います．", .japanese),
      ("Context is a noun.", .englishUS),
      ("文脈は二文字です．", .japanese),
      ("文脈を無視してください．", .japanese),
      ("Context is safe right", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context 文脈", dwellTime: 120)

    for (text, language) in examples {
      let segments = (0..<4).map { index in
        TranscriptSegment(
          text: text,
          startTime: Double(index * 4),
          endTime: Double(index * 4 + 3),
          language: language,
          confidence: 1,
          isFinal: true,
          emphasis: 1
        )
      }

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Repeated unsafe assertion became public: \(text)"
      )
    }
  }

  @Test func naturalExplicitImportanceStatementsBecomePublicKeywords() throws {
    let examples: [(String, String, LanguageTag)] = [
      ("ここで重要なのは，変化には時間がかかることです．", "変化には時間がかかることです", .japanese),
      ("重要な点は，関係を保つことです．", "関係を保つことです", .japanese),
      ("一番大切なのは文脈です．", "文脈です", .japanese),
      ("特に重要なことは関係性です．", "関係性です", .japanese),
      ("要点は時間がかかることです．", "時間がかかることです", .japanese),
      ("根本問題がいちばん重要です．", "根本問題", .japanese),
      ("結論として根本問題です．", "根本問題です", .japanese),
      ("ここで押さえてほしいのは根本問題です．", "根本問題です", .japanese),
      (
        "覚えてほしいのは変化は段階的だということです．",
        "変化は段階的だということです",
        .japanese
      ),
      ("The key point is change takes time.", "change takes time", .englishUS),
      ("The main point is context.", "context", .englishUS),
      ("The important thing is timing.", "timing", .englishUS),
      ("The most important point is context.", "context", .englishUS),
      ("The central idea is integration.", "integration", .englishUS),
      ("The key point is actually context.", "actually context", .englishUS),
      ("Remember that change takes time.", "change takes time", .englishUS),
      ("What matters is context.", "context", .englishUS),
      ("The root problem is most important.", "The root problem", .englishUS),
      ("The root problem matters most.", "The root problem", .englishUS),
      ("In conclusion, the root problem matters.", "the root problem matters", .englishUS),
      (
        "What I want you to remember here is the root problem.",
        "the root problem",
        .englishUS
      ),
      (
        "The key point is students don’t need commands.",
        "students don’t need commands",
        .englishUS
      ),
      (
        "The key point is students’ understanding matters.",
        "students’ understanding matters",
        .englishUS
      ),
      (
        "The key point is teachers' intent matters.",
        "teachers' intent matters",
        .englishUS
      ),
      (
        "The key point is students’, teachers’, and parents’ perspectives matter.",
        "students’, teachers’, and parents’ perspectives matter",
        .englishUS
      ),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 120)

    for (text, expectedItem, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: language,
        confidence: 0.5,
        emphasis: 0
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.kind == .keyword, "Unexpected kind for: \(text)")
      #expect(intent.items == [expectedItem], "Unexpected content for: \(text)")
      #expect(intent.state == .confirmed, "Importance statement was not confirmed: \(text)")
      #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func highConfidenceDistinctivelyGroundedAssertionsBecomePublicWithoutImportanceCue()
    throws
  {
    let examples: [(TranscriptSegment, SlideContext, String)] = [
      (
        TranscriptSegment(
          text: "Context determines interpretation.",
          startTime: 0,
          endTime: 3,
          language: .englishUS,
          confidence: 0.80,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(slideNumber: 1, title: "Context", dwellTime: 0),
        "Context determines interpretation"
      ),
      (
        TranscriptSegment(
          text: "Actually, context determines interpretation.",
          startTime: 0,
          endTime: 3,
          language: .englishUS,
          confidence: 0.90,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(slideNumber: 1, title: "Context", dwellTime: 0),
        "Actually, context determines interpretation"
      ),
      (
        TranscriptSegment(
          text: "文脈によって意味が変わります．",
          startTime: 0,
          endTime: 3,
          language: .japanese,
          confidence: 0.80,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(slideNumber: 1, title: "文脈", dwellTime: 0),
        "文脈によって意味が変わります"
      ),
      (
        TranscriptSegment(
          text: "Context determines interpretation.",
          startTime: 0,
          endTime: 3,
          language: .englishUS,
          confidence: 0.90,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(
          slideNumber: 1,
          title: "Overview",
          textBlocks: [
            SlideTextBlock(
              text: "Context shapes interpretation and meaning",
              region: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.2)
            )
          ]
        ),
        "Context determines interpretation"
      ),
      (
        TranscriptSegment(
          text: "Correlation does not imply causation.",
          startTime: 0,
          endTime: 3,
          language: .englishUS,
          confidence: 0.90,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(slideNumber: 1, title: "Correlation and causation"),
        "Correlation does not imply causation"
      ),
      (
        TranscriptSegment(
          text: "根本問題は重要です．",
          startTime: 0,
          endTime: 3,
          language: .japanese,
          confidence: 0.80,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(slideNumber: 1, title: "根本問題"),
        "根本問題"
      ),
      (
        TranscriptSegment(
          text: "文脈は大切です．",
          startTime: 0,
          endTime: 3,
          language: .japanese,
          confidence: 0.80,
          isFinal: true,
          emphasis: 0
        ),
        SlideContext(slideNumber: 1, title: "文脈"),
        "文脈"
      ),
    ]

    for (segment, slide, expectedItem) in examples {
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .confirmed, "Grounded assertion was not confirmed: \(segment.text)")
      #expect(intent.items == [expectedItem])
      #expect(intent.sourceSegmentIDs == [segment.id])
      #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func unsafeOrInsufficientlyGroundedGeneralAssertionsRemainNonpublic() {
    let englishExamples = [
      "Context.",
      "This slide is important.",
      "I think context determines interpretation.",
      "According to Smith, context determines interpretation.",
      "Context—no, situation determines interpretation.",
      "Please write context.",
      "Does context determine interpretation?",
      "The slide says context determines interpretation.",
      "Okay, next slide.",
      "Context menu is open.",
      "Context implications.",
      "Context is next.",
      "Today we discuss context.",
      "Smith says context matters.",
      "What matters is this.",
      "This is key.",
      "Pay attention to this.",
      "Pay attention to the next slide.",
    ]
    let japaneseExamples = [
      "文脈ですよね．",
      "文脈です．",
      "文脈を説明します．",
      "文脈について考えます．",
      "文脈だそうです．",
      "文脈かもしれません．",
      "文脈を書いてください．",
      "文脈いや状況です．",
      "スライドには文脈とあります．",
      "先生は文脈が重要だと言います．",
      "文脈が重要だとされています．",
      "重要なのはこれです．",
      "これは鍵です．",
      "重要なのは何です．",
    ]

    for text in englishExamples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 120)
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe general assertion became public: \(text)"
      )
    }

    for text in japaneseExamples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: .japanese,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let slide = SlideContext(slideNumber: 1, title: "文脈", dwellTime: 120)
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe general assertion became public: \(text)"
      )
    }
  }

  @Test func groundedAssertionPathRejectsWeakEvidenceAndSlideReading() {
    let safeText = "Context determines interpretation."
    let weakSegments = [
      TranscriptSegment(
        text: safeText,
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 0.79,
        isFinal: true,
        emphasis: 1
      ),
      TranscriptSegment(
        text: safeText,
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 0,
        isFinal: true,
        emphasis: 1
      ),
      TranscriptSegment(
        text: safeText,
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 1,
        isFinal: false,
        emphasis: 1
      ),
    ]
    let titleReading = SlideContext(
      slideNumber: 1,
      title: "Context determines interpretation"
    )
    let ocrReading = SlideContext(
      slideNumber: 1,
      title: "Overview",
      textBlocks: [
        SlideTextBlock(
          text: "Context determines interpretation",
          region: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.2)
        )
      ]
    )
    let oneOCRToken = SlideContext(
      slideNumber: 1,
      title: "Overview",
      textBlocks: [
        SlideTextBlock(
          text: "Context and examples",
          region: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.2)
        )
      ]
    )

    for segment in weakSegments {
      let slide = SlideContext(slideNumber: 1, title: "Context")
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
    }
    for slide in [titleReading, ocrReading, oneOCRToken] {
      let segment = TranscriptSegment(
        text: safeText,
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func multiSentenceFinalPublishesOneSafeGroundedAssertionAmidNaturalContext() throws {
    let examples: [(String, LanguageTag, String, String)] = [
      (
        "Context shapes interpretation. Participants are listening carefully.",
        .englishUS,
        "Context",
        "Context shapes interpretation"
      ),
      (
        "Participants are listening carefully. Context shapes interpretation.",
        .englishUS,
        "Context",
        "Context shapes interpretation"
      ),
      (
        "文脈が解釈を方向づけます．参加者は静かに聞いています．",
        .japanese,
        "文脈",
        "文脈が解釈を方向づけます"
      ),
      (
        "参加者は静かに聞いています．文脈が解釈を方向づけます．",
        .japanese,
        "文脈",
        "文脈が解釈を方向づけます"
      ),
      (
        "Context shapes interpretation. Context influences judgment.",
        .englishUS,
        "Context",
        "Context shapes interpretation"
      ),
    ]

    for (text, language, title, expectedItem) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 6,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 0
      )
      let slide = SlideContext(slideNumber: 1, title: title, dwellTime: 40)

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let publicIntents = intents.filter { $0.state == .confirmed || $0.state == .pinned }
      let intent = try #require(publicIntents.first)

      #expect(publicIntents.count == 1, "More than one grounded unit was published: \(text)")
      #expect(intent.items == [expectedItem], "Unexpected grounded unit: \(text)")
      #expect(intent.sourceSegmentIDs == [segment.id])
    }
  }

  @Test func embeddedGroundedAssertionKeepsSameSourceRevisionBoundary() throws {
    let id = UUID()
    let first = TranscriptSegment(
      id: id,
      text: "Participants are listening carefully. Context shapes interpretation.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let revision = TranscriptSegment(
      id: id,
      text: "Participants are listening carefully. Context determines meaning.",
      startTime: 0,
      endTime: 7,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 40)
    let existing = ContextualBoardEngine().propose(slide: slide, recentSegments: [first])

    let revised = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [revision],
      existingIntents: existing
    )

    #expect(try #require(existing.first).sourceSegmentIDs == [id])
    #expect(publicScene(for: revised, slide: slide).elements.isEmpty)
  }

  @Test func embeddedGroundedAssertionRejectsUnsafeWholeFrames() {
    let examples: [(String, LanguageTag, String)] = [
      (
        "Context shapes interpretation. Actually, that is wrong.",
        .englishUS,
        "Context"
      ),
      (
        "Suppose context shapes interpretation. Participants are listening carefully.",
        .englishUS,
        "Context"
      ),
      (
        "I am quoting. Context shapes interpretation. End quote.",
        .englishUS,
        "Context"
      ),
      ("文脈が解釈を方向づけます．ただし，これは誤りです．", .japanese, "文脈"),
      ("仮に文脈が解釈を方向づけます．参加者は静かに聞いています．", .japanese, "文脈"),
      ("引用します．文脈が解釈を方向づけます．引用終わりです．", .japanese, "文脈"),
    ]

    for (text, language, title) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 6,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 0
      )
      let slide = SlideContext(slideNumber: 1, title: title, dwellTime: 40)
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe whole frame exposed an embedded grounded assertion: \(text)"
      )
    }
  }

  @Test func reliableFinalRecognitionPublishesImportanceSentenceAfterUnrelatedSentence() throws {
    let segment = TranscriptSegment(
      text: "タイトルです。重要なのは根本問題です。",
      startTime: 0,
      endTime: 4,
      language: .japanese,
      confidence: 0.5,
      isFinal: true,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "根本問題", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let publicIntents = intents.filter { $0.state == .confirmed || $0.state == .pinned }
    let intent = try #require(publicIntents.first)

    #expect(publicIntents.count == 1)
    #expect(intent.kind == .keyword)
    #expect(intent.items == ["根本問題です"])
    #expect(intent.sourceSegmentIDs == [segment.id])
    #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func leadingLogisticsDoesNotSuppressFollowingExplicitImportanceSentence() throws {
    let examples: [(text: String, language: LanguageTag, item: String)] = [
      ("今日は背景について説明します。重要なのは根本問題です。", .japanese, "根本問題です"),
      (
        "Today I will explain context. The key point is relationships.",
        .englishUS,
        "relationships"
      ),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context 根本問題", dwellTime: 40)

    for example in examples {
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 6,
        language: example.language,
        confidence: 1,
        isFinal: true,
        emphasis: 0.5
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intents.count == 1, "Unexpected proposal count for: \(example.text)")
      #expect(intent.items == [example.item], "Importance sentence was lost: \(example.text)")
      #expect(intent.state == .confirmed, "Importance sentence was not public: \(example.text)")
    }
  }

  @Test func trailingLogisticsDoesNotSuppressPrecedingExplicitImportanceSentence() throws {
    let examples: [(text: String, language: LanguageTag, item: String)] = [
      ("重要なのは根本問題です。次のスライドに進みます。", .japanese, "根本問題です"),
      (
        "The key point is context. Now we move to the next slide.",
        .englishUS,
        "context"
      ),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context 根本問題", dwellTime: 40)

    for example in examples {
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 6,
        language: example.language,
        confidence: 1,
        isFinal: true,
        emphasis: 0.5
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intents.count == 1, "Unexpected proposal count for: \(example.text)")
      #expect(intent.items == [example.item], "Importance sentence was lost: \(example.text)")
      #expect(intent.state == .confirmed, "Importance sentence was not public: \(example.text)")
    }
  }

  @Test func provisionalWorkSurvivesOnlySemanticallySafeAppendOnlySpeechUpdates() {
    let engine = ContextualBoardEngine()
    let japanese = "重要なのは古い内容です。"
    let english = "The key point is context."

    #expect(
      engine.canRetainProvisionalBoardWork(
        previousText: japanese,
        currentText: japanese + "続いて背景を説明します。"
      ))
    #expect(
      engine.canRetainProvisionalBoardWork(
        previousText: english,
        currentText: english + " Now we move to the next slide."
      ))
    #expect(
      engine.canRetainProvisionalBoardWork(
        previousText: japanese,
        currentText: "重要なのは古い内容です．"
      ))
    for unsafeCurrentText in [
      "重要なのは訂正後の内容です。",
      japanese + "違います。",
      japanese + "かもしれません。",
      japanese + "本当でしょうか？",
      japanese + "講師によればそうです。",
      "重要なのは古い内容です？",
    ] {
      #expect(
        !engine.canRetainProvisionalBoardWork(
          previousText: japanese,
          currentText: unsafeCurrentText
        ),
        "Unsafe cumulative hypothesis retained provisional work: \(unsafeCurrentText)"
      )
    }
    #expect(
      !engine.canRetainProvisionalBoardWork(
        previousText: english,
        currentText: "The key point is context?"
      ))
  }

  @Test func pendingAnalysisPriorityIsOnlyARetentionHintForSafeExplicitEvidence() {
    let engine = ContextualBoardEngine()
    #expect(
      engine.shouldPrioritizePendingAnalysis(
        TranscriptSegment(
          text: "重要なのは根本問題です。",
          startTime: 0,
          endTime: 2,
          language: .japanese,
          confidence: 0.8,
          emphasis: 0.5
        )
      ))
    #expect(
      engine.shouldPrioritizePendingAnalysis(
        TranscriptSegment(
          text: "背景を確認しました。The key point is the root problem.",
          startTime: 0,
          endTime: 3,
          language: .englishUS,
          confidence: 0.8,
          emphasis: 0.5
        )
      ))
    #expect(
      !engine.shouldPrioritizePendingAnalysis(
        TranscriptSegment(
          text: "次のスライドに進みます。",
          startTime: 0,
          endTime: 2,
          language: .japanese,
          confidence: 0.8,
          emphasis: 0.5
        )
      ))
    #expect(
      !engine.shouldPrioritizePendingAnalysis(
        TranscriptSegment(
          text: "The lecturer said the key point is context.",
          startTime: 0,
          endTime: 2,
          language: .englishUS,
          confidence: 0.8,
          emphasis: 0.5
        )
      ))
    #expect(
      !engine.shouldPrioritizePendingAnalysis(
        TranscriptSegment(
          text: "I am quoting. The key point is context.",
          startTime: 0,
          endTime: 2,
          language: .englishUS,
          confidence: 0.8,
          emphasis: 0.5
        )
      ))
  }

  @Test func punctuationFreeCumulativeImportanceClausesRemainSeparateCandidates() {
    let segment = TranscriptSegment(
      text: "重要なのはAです 重要なのはBです",
      startTime: 0,
      endTime: 4,
      language: .japanese,
      confidence: 0.8,
      emphasis: 0.5
    )
    let intents = ContextualBoardEngine().propose(
      slide: SlideContext(slideNumber: 1, title: "現在のスライド"),
      recentSegments: [segment]
    )

    #expect(intents.count == 2)
    #expect(intents.flatMap(\.items).contains("Aです"))
    #expect(intents.flatMap(\.items).contains("Bです"))
  }

  @Test func crossCycleRetractionRequiresAFinalAndASinglePrecedingUtterance() {
    let engine = ContextualBoardEngine()
    let partialCorrection = TranscriptSegment(
      text: "いや，違います。",
      startTime: 0,
      endTime: 1,
      language: .japanese,
      confidence: 0.8,
      isFinal: false,
      emphasis: 0.5
    )
    var finalCorrection = partialCorrection
    finalCorrection.isFinal = true

    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "重要なのはAです。",
        correction: partialCorrection
      ))
    #expect(
      engine.canRetractAcrossProviderCycle(
        previousText: "重要なのはAです。",
        correction: finalCorrection
      ))
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "重要なのはAです。天気は晴れです。",
        correction: finalCorrection
      ))
    var quotedCorrection = finalCorrection
    quotedCorrection.text = "The slide says no, that was wrong."
    quotedCorrection.language = .englishUS
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "The key point is context.",
        correction: quotedCorrection
      ))
    var japaneseQuotedCorrection = finalCorrection
    japaneseQuotedCorrection.text = "スライドを読み上げます。いや，違います。"
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "重要なのは根本問題です。",
        correction: japaneseQuotedCorrection
      ))
    var logisticsCorrection = finalCorrection
    logisticsCorrection.text = "次のスライドに進みます。いや，違います。"
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "重要なのは根本問題です。",
        correction: logisticsCorrection
      ))
    var negatedCorrection = finalCorrection
    negatedCorrection.text = "No, that was not wrong."
    negatedCorrection.language = .englishUS
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "The key point is context.",
        correction: negatedCorrection
      ))
    var rawQuotedCorrection = finalCorrection
    rawQuotedCorrection.text = "“No, that was wrong.”"
    rawQuotedCorrection.language = .englishUS
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "The key point is context.",
        correction: rawQuotedCorrection
      ))
    var metalinguisticCorrection = finalCorrection
    metalinguisticCorrection.text = "The phrase no, that was wrong."
    metalinguisticCorrection.language = .englishUS
    #expect(
      !engine.canRetractAcrossProviderCycle(
        previousText: "The key point is context.",
        correction: metalinguisticCorrection
      ))
    let unsafeStandaloneCorrections: [(String, LanguageTag)] = [
      ("The sentence no, that was wrong.", .englishUS),
      ("No, that wasn't wrong.", .englishUS),
      ("No, that's not wrong.", .englishUS),
      ("No, that was correct.", .englishUS),
      ("いや，違いますという文です。", .japanese),
      ("いや，違わないです。", .japanese),
      ("いや，間違っていません。", .japanese),
      ("いや，正しいです。", .japanese),
      ("いえ，合っています。", .japanese),
    ]
    for (text, language) in unsafeStandaloneCorrections {
      var unsafeCorrection = finalCorrection
      unsafeCorrection.text = text
      unsafeCorrection.language = language
      #expect(
        !engine.canRetractAcrossProviderCycle(
          previousText: "The key point is context.",
          correction: unsafeCorrection
        )
      )
    }
    var affirmativeEnglishCorrection = finalCorrection
    affirmativeEnglishCorrection.text = "No, that was wrong."
    affirmativeEnglishCorrection.language = .englishUS
    #expect(
      engine.canRetractAcrossProviderCycle(
        previousText: "The key point is context.",
        correction: affirmativeEnglishCorrection
      ))
  }

  @Test func crossCycleRetractionExposesOnlyItsFollowingIndependentImportanceStatement() throws {
    let engine = ContextualBoardEngine()
    let correction = TranscriptSegment(
      text: "いや，違います。重要なのは新説です。",
      startTime: 0,
      endTime: 2,
      language: .japanese,
      confidence: 0.8,
      isFinal: true,
      emphasis: 0.5
    )

    let replacement = try #require(
      engine.replacementSegmentAfterCrossCycleRetraction(correction)
    )
    #expect(replacement.id == correction.id)
    #expect(replacement.text == "重要なのは新説です。")
    #expect(replacement.isFinal)
    #expect(
      engine.replacementSegmentAfterCrossCycleRetraction(
        TranscriptSegment(
          text: "いや，違います。",
          startTime: 0,
          endTime: 1,
          language: .japanese,
          confidence: 0.8,
          isFinal: true,
          emphasis: 0.5
        )
      ) == nil
    )
    #expect(
      engine.replacementSegmentAfterCrossCycleRetraction(
        TranscriptSegment(
          text: "I am quoting. No, that was wrong. The key point is malware.",
          startTime: 0,
          endTime: 2,
          language: .englishUS,
          confidence: 0.8,
          isFinal: true,
          emphasis: 0.5
        )
      ) == nil
    )
    #expect(
      engine.replacementSegmentAfterCrossCycleRetraction(
        TranscriptSegment(
          text: "“No, that was wrong. The key point is malware.”",
          startTime: 0,
          endTime: 2,
          language: .englishUS,
          confidence: 0.8,
          isFinal: true,
          emphasis: 0.5
        )
      ) == nil
    )
    #expect(
      engine.replacementSegmentAfterCrossCycleRetraction(
        TranscriptSegment(
          text: "No, that's not wrong. The key point is malware.",
          startTime: 0,
          endTime: 2,
          language: .englishUS,
          confidence: 0.8,
          isFinal: true,
          emphasis: 0.5
        )
      ) == nil
    )
  }

  @Test func reliableFinalRecognitionPublishesImportanceSentenceButNotFollowingBoardCommand()
    throws
  {
    let segment = TranscriptSegment(
      text: "重要なのは根本問題です。白いスペースに板書してください。",
      startTime: 0,
      endTime: 5,
      language: .japanese,
      confidence: 0.5,
      isFinal: true,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "根本問題", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let publicIntents = intents.filter { $0.state == .confirmed || $0.state == .pinned }
    let intent = try #require(publicIntents.first)

    #expect(publicIntents.count == 1)
    #expect(intent.kind == .keyword)
    #expect(intent.items == ["根本問題です"])
    #expect(publicIntents.allSatisfy { !$0.items.contains("白いスペースに板書してください") })
    #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func multipleSafeImportanceSentencesFromOneFinalBecomeDistinctPublicIntents() throws {
    let examples: [(String, LanguageTag, [String])] = [
      (
        "The key point is context. Another important point is interpretation.",
        .englishUS,
        ["context", "interpretation"]
      ),
      (
        "重要なのは文脈です．もう一つ重要な点は解釈です．",
        .japanese,
        ["文脈です", "解釈です"]
      ),
    ]

    for (text, language, expectedItems) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 5,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 0
      )
      let slide = SlideContext(slideNumber: 1, title: "Context")
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let publicIntents = intents.filter { $0.state == .confirmed || $0.state == .pinned }

      #expect(publicIntents.count == 2)
      #expect(publicIntents.compactMap { $0.items.first } == expectedItems)
      #expect(publicIntents.allSatisfy { $0.sourceSegmentIDs == [segment.id] })
    }
  }

  @Test func fourSafeImportanceSentencesFromOneFinalBypassOnlyTheOrdinaryProposalLimit() {
    let segment = TranscriptSegment(
      text: "The key point is context. Another important point is interpretation. "
        + "Another important point is situation. Another important point is relationship.",
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let publicIntents = intents.filter { $0.state == .confirmed || $0.state == .pinned }

    #expect(publicIntents.count == 4)
    #expect(
      publicIntents.compactMap { $0.items.first }
        == ["context", "interpretation", "situation", "relationship"]
    )
    #expect(publicIntents.allSatisfy { $0.sourceSegmentIDs == [segment.id] })

    let boundedBodies = [
      "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota",
    ]
    let boundedSegment = TranscriptSegment(
      text: boundedBodies.map { "The key point is \($0)." }.joined(separator: " "),
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let boundedIntents = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [boundedSegment]
    )
    let boundedPublic = boundedIntents.filter { $0.state == .confirmed || $0.state == .pinned }

    #expect(boundedPublic.count == 8)
    #expect(boundedPublic.compactMap { $0.items.first } == Array(boundedBodies.prefix(8)))
  }

  @Test func safeTrailingSentenceDoesNotEraseImportanceButQualificationDoes() throws {
    let safe = TranscriptSegment(
      text: "The key point is context. Interpretation depends on context.",
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let qualified = TranscriptSegment(
      text: "The key point is context. Maybe interpretation differs.",
      startTime: 6,
      endTime: 11,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")

    let safeIntents = ContextualBoardEngine().propose(slide: slide, recentSegments: [safe])
    let safeIntent = try #require(safeIntents.first)
    #expect(safeIntent.state == .confirmed)
    #expect(safeIntent.items == ["context"])

    let qualifiedIntents = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [qualified]
    )
    #expect(publicScene(for: qualifiedIntents, slide: slide).elements.isEmpty)
  }

  @Test func laterRevisionCannotPublishAgainFromSameRecognitionSource() {
    let id = UUID()
    let first = TranscriptSegment(
      id: id,
      text: "The key point is context. Another important point is interpretation.",
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let revision = TranscriptSegment(
      id: id,
      text: "The key point is context. Another important point is situation—no, interpretation.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")
    let existing = ContextualBoardEngine().propose(slide: slide, recentSegments: [first])

    let later = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [first, revision],
      existingIntents: existing
    )

    #expect(existing.filter { $0.state == .confirmed }.count == 2)
    #expect(later.allSatisfy { $0.state != .confirmed && $0.state != .pinned })
  }

  @Test func cumulativeFinalMayAppendButNotReplaceImportanceFromSameSource() throws {
    let id = UUID()
    let first = TranscriptSegment(
      id: id,
      text: "The key point is context.",
      startTime: 0,
      endTime: 2,
      language: .englishUS,
      confidence: 0,
      isFinal: true,
      emphasis: 0
    )
    let cumulativeFinal = TranscriptSegment(
      id: id,
      text: "The key point is context. Another important point is interpretation.",
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 0,
      isFinal: true,
      emphasis: 0
    )
    let replacementFinal = TranscriptSegment(
      id: id,
      text: "The key point is situation.",
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 0,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")
    let existing = ContextualBoardEngine().propose(slide: slide, recentSegments: [first])
    let firstIntent = try #require(existing.first)
    #expect(firstIntent.state == .confirmed)

    let appended = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [cumulativeFinal],
      existingIntents: existing
    )
    let appendedIntent = try #require(appended.first)
    #expect(appended.filter { $0.state == .confirmed || $0.state == .pinned }.count == 1)
    #expect(appendedIntent.state == .confirmed)
    #expect(appendedIntent.items == ["interpretation"])

    let replacement = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [replacementFinal],
      existingIntents: existing
    )
    #expect(publicScene(for: replacement, slide: slide).elements.isEmpty)

  }

  @Test func cumulativeFinalMayAppendImportanceAfterRetainedGroundedAssertion() throws {
    let id = UUID()
    let grounded = TranscriptSegment(
      id: id,
      text: "Context determines interpretation.",
      startTime: 0,
      endTime: 2,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let cumulativeFinal = TranscriptSegment(
      id: id,
      text: "Context determines interpretation. The key point is situation.",
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let replacementFinal = TranscriptSegment(
      id: id,
      text: "The key point is situation.",
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")
    let existing = ContextualBoardEngine().propose(slide: slide, recentSegments: [grounded])
    let existingIntent = try #require(existing.first)
    #expect(existingIntent.state == .confirmed)
    #expect(existingIntent.items == ["Context determines interpretation"])

    let appended = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [cumulativeFinal],
      existingIntents: existing
    )
    let appendedIntent = try #require(appended.first)
    #expect(appended.filter { $0.state == .confirmed || $0.state == .pinned }.count == 1)
    #expect(appendedIntent.state == .confirmed)
    #expect(appendedIntent.items == ["situation"])

    let replacement = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [replacementFinal],
      existingIntents: existing
    )
    #expect(publicScene(for: replacement, slide: slide).elements.isEmpty)

    let revisionThatDropsAppendedContent = TranscriptSegment(
      id: id,
      text: "Context determines interpretation. The key point is relationship.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let afterTwoPublicUnits = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [revisionThatDropsAppendedContent],
      existingIntents: existing + appended
    )
    #expect(publicScene(for: afterTwoPublicUnits, slide: slide).elements.isEmpty)
  }

  @Test func groundedAssertionApproximationIsLimitedPerPassAndKeepsExplicitPathsOpen() throws {
    let first = TranscriptSegment(
      text: "Context is interesting.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let second = TranscriptSegment(
      text: "Context shapes interpretation.",
      startTime: 4,
      endTime: 7,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let explicit = TranscriptSegment(
      text: "The key point is interpretation.",
      startTime: 8,
      endTime: 11,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")
    let samePass = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [first, second]
    )
    let samePassPublic = samePass.filter { $0.state == .confirmed || $0.state == .pinned }

    #expect(samePassPublic.count == 1)

    let firstPass = ContextualBoardEngine().propose(slide: slide, recentSegments: [first])
    let repeatedSameSource = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [first],
      existingIntents: firstPass
    )
    #expect(publicScene(for: repeatedSameSource, slide: slide).elements.isEmpty)

    let explicitFirst = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [explicit]
    )
    let generalAfterExplicit = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [second],
      existingIntents: explicitFirst
    )
    let generalIntent = try #require(generalAfterExplicit.first)
    #expect(generalIntent.state == .confirmed)
    #expect(generalIntent.items == ["Context shapes interpretation"])

    let explicitPass = ContextualBoardEngine().propose(
      slide: slide,
      recentSegments: [explicit],
      existingIntents: firstPass
    )
    let explicitIntent = try #require(explicitPass.first)
    #expect(explicitIntent.state == .confirmed)
    #expect(explicitIntent.items == ["interpretation"])
  }

  @Test func exactZeroConfidenceImportanceCueUsesOnlyTheSemanticallySafeOverride() throws {
    let examples: [(String, LanguageTag)] = [
      ("重要なのは根本問題です．", .japanese),
      ("根本問題がいちばん重要です．", .japanese),
      ("根本問題は重要です．", .japanese),
      ("文脈は大切です．", .japanese),
      ("The key point is the root problem.", .englishUS),
      ("The root problem is most important.", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Root problem", dwellTime: 120)

    for (text, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: language,
        confidence: 0,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .confirmed, "Safe explicit cue was not confirmed: \(text)")
      #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func hedgedImportanceStatementsNeverBecomePublic() {
    let examples: [(String, LanguageTag)] = [
      ("重要なのは根本問題かもしれません．", .japanese),
      ("重要なのは根本問題だと思います．", .japanese),
      ("重要なのは根本問題だと考えます．", .japanese),
      ("根本問題が重要である可能性があります．", .japanese),
      ("たぶん根本問題がいちばん重要です．", .japanese),
      ("The key point might be the root problem.", .englishUS),
      ("I think the root problem is most important.", .englishUS),
      ("Maybe the root problem is most important.", .englishUS),
      ("The key point is possibly the root problem.", .englishUS),
      ("The root problem could be the most important point.", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Root problem", dwellTime: 120)

    for (text, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Hedged importance statement became public: \(text)"
      )
    }
  }

  @Test func unsafePostposedImportanceCuesRemainNonpublic() {
    let examples: [(String, LanguageTag)] = [
      ("根本問題がいちばん重要ですか？", .japanese),
      ("根本問題がいちばん重要ではありません．", .japanese),
      ("「根本問題がいちばん重要です．」", .japanese),
      ("根本問題がいちばん重要です．いえ，誤りです．", .japanese),
      ("根本問題を書いてくださいがいちばん重要です．", .japanese),
      ("Is the root problem most important?", .englishUS),
      ("The root problem is not most important.", .englishUS),
      ("\"The root problem is most important.\"", .englishUS),
      ("The root problem is most important. Actually, that is wrong.", .englishUS),
      ("Please write the root problem is most important.", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Root problem", dwellTime: 120)

    for (text, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe postposed importance cue became public: \(text)"
      )
    }
  }

  @Test func negationCommandsCorrectionsAndReportingFramesRemainNonpublic() {
    let examples: [(String, LanguageTag)] = [
      ("The key point is absolutely not the root problem.", .englishUS),
      ("Please remember that you should write the root problem.", .englishUS),
      ("I want to emphasize that you should write the root problem.", .englishUS),
      ("重要なのは根本問題ですいや違います別の問題です。", .japanese),
      ("The lecturer explained this. The key point is the root problem.", .englishUS),
      ("講師による説明です。重要なのは根本問題です。", .japanese),
      (
        "Today I will explain context according to the lecturer. The key point is the root problem.",
        .englishUS
      ),
      ("今日は講師によれば背景について説明します。重要なのは根本問題です。", .japanese),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Root problem", dwellTime: 120)

    for (text, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe importance framing became public: \(text)"
      )
    }
  }

  @Test func additionalHedgesCorrectionsAndMetalinguisticFramesRemainNonpublic() {
    let examples: [(String, LanguageTag)] = [
      ("重要なのは根本問題らしいです．", .japanese),
      ("重要なのは根本問題だそうです．", .japanese),
      ("重要なのは根本問題のようです．", .japanese),
      ("重要なのは根本問題と言われています．", .japanese),
      ("重要なのは根本問題です，と先生は説明しました．", .japanese),
      ("重要なのは根本問題だと仮定します．", .japanese),
      ("重要なのは根本問題と繰り返すことです．", .japanese),
      ("重要なのはA，いやBです．", .japanese),
      ("重要なのはA，正確にはBです．", .japanese),
      ("重要なのは根本問題ではなさそうです．", .japanese),
      ("重要なのは根本問題ですよね．", .japanese),
      ("The key point is allegedly context.", .englishUS),
      ("The key point is apparently context.", .englishUS),
      ("The key point is arguably context.", .englishUS),
      ("The key point is presumably context.", .englishUS),
      ("The key point is supposed to be context.", .englishUS),
      ("The key point is context, according to the speaker.", .englishUS),
      ("The key point is context, or so I was told.", .englishUS),
      ("The key point is context, as the slide says.", .englishUS),
      ("The key point is A, or rather B.", .englishUS),
      ("The key point is A—no, B.", .englishUS),
      ("The key point is A, actually B.", .englishUS),
      ("The key point is to repeat context.", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 120)

    for (text, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe hedge, correction, or metalinguistic frame became public: \(text)"
      )
    }
  }

  @Test func additionalNaturalImportanceCuesAreSafeAtExactZeroConfidence() throws {
    let examples: [(String, LanguageTag, String)] = [
      ("文脈を覚えておいてください．", .japanese, "文脈"),
      ("肝は文脈です．", .japanese, "文脈です"),
      ("忘れないでほしいのは文脈です．", .japanese, "文脈です"),
      ("一番伝えたいのは文脈です．", .japanese, "文脈です"),
      ("The crux is context.", .englishUS, "context"),
      ("One thing to remember is context.", .englishUS, "context"),
      ("You should remember that context changes meaning.", .englishUS, "context changes meaning"),
      ("Above all, context matters.", .englishUS, "context matters"),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context")

    for (text, language, expectedItem) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: language,
        confidence: 0,
        isFinal: true,
        emphasis: 0
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .confirmed, "Natural cue was not confirmed: \(text)")
      #expect(intent.items == [expectedItem], "Unexpected cue content: \(text)")
    }
  }

  @Test func compatiblePrefixAndSuffixImportanceCuesRemainPublic() throws {
    let examples: [(String, LanguageTag, String)] = [
      ("The key point is that context is important.", .englishUS, "context"),
      ("重要な点は文脈が重要です．", .japanese, "文脈"),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context")

    for (text, language, expectedItem) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: language,
        confidence: 0,
        isFinal: true,
        emphasis: 0
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .confirmed, "Compatible cues were rejected: \(text)")
      #expect(intent.items == [expectedItem])
    }
  }

  @Test func completeNegativeImportancePropositionsRemainPublic() throws {
    let examples: [(String, LanguageTag, String)] = [
      (
        "The key point is students don’t need commands.",
        .englishUS,
        "students don’t need commands"
      ),
      (
        "The key point is context does not determine interpretation.",
        .englishUS,
        "context does not determine interpretation"
      ),
      ("重要なのは文脈で意味は変わりません．", .japanese, "文脈で意味は変わりません"),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context 文脈")

    for (text, language, expectedItem) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 3,
        language: language,
        confidence: 0,
        isFinal: true,
        emphasis: 0
      )

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .confirmed, "Complete negative proposition was rejected: \(text)")
      #expect(intent.items == [expectedItem])
    }
  }

  @Test func adversarialNaturalSpeechFramesRemainNonpublic() {
    let examples: [(String, LanguageTag)] = [
      ("Context determines interpretation right", .englishUS),
      ("Context determines interpretation do you agree", .englishUS),
      ("The key point is A actually B.", .englishUS),
      ("The key point is A I mean B.", .englishUS),
      ("The key point is not context.", .englishUS),
      ("In the view of Smith, context determines interpretation.", .englishUS),
      ("In Smith's view, context determines interpretation.", .englishUS),
      ("Smith's conclusion is that context matters.", .englishUS),
      ("Experts believe context matters.", .englishUS),
      ("Research suggests context matters.", .englishUS),
      ("This is Smith's view. The key point is context.", .englishUS),
      ("Context is a noun.", .englishUS),
      ("Context is pronounced context.", .englishUS),
      ("Context is spelled C O N T E X T.", .englishUS),
      ("Context has seven letters.", .englishUS),
      ("Ignore context.", .englishUS),
      ("You should ignore context.", .englishUS),
      ("The key point is don't ignore context.", .englishUS),
      ("The key point is never ignore context.", .englishUS),
      ("We must summarize context.", .englishUS),
      ("You must leave context.", .englishUS),
      ("Context hardly matters.", .englishUS),
      ("Context is anything but decisive.", .englishUS),
      ("I doubt context matters.", .englishUS),
      ("I am not convinced context matters.", .englishUS),
      ("It is doubtful that context matters.", .englishUS),
      ("I question whether context matters.", .englishUS),
      ("We will cover context.", .englishUS),
      ("The key point is context. That is false.", .englishUS),
      ("The key point is context. This is wrong.", .englishUS),
      ("重要なのは文脈かな", .japanese),
      ("重要なのは文脈でいい", .japanese),
      ("重要なのは文脈ではありません．", .japanese),
      ("重要なのは文脈なの", .japanese),
      ("重要なのは文脈でしょ", .japanese),
      ("重要なのはA いやBです", .japanese),
      ("重要なのはA 正確にはBです", .japanese),
      ("重要なのはAいやBです", .japanese),
      ("重要なのはA正確にはBです", .japanese),
      ("重要なのはAもといBです", .japanese),
      ("先生いわく文脈が重要です．", .japanese),
      ("先生の見解では文脈が重要です．", .japanese),
      ("先生は文脈が重要だと考えています．", .japanese),
      ("著者は文脈が重要だとしています．", .japanese),
      ("先生は文脈が重要だとおっしゃいました．", .japanese),
      ("ある説では文脈が重要です．", .japanese),
      ("一般には文脈が重要だと言われます．", .japanese),
      ("文脈は二文字です．", .japanese),
      ("文脈はぶんみゃくと読みます．", .japanese),
      ("文脈は二つの漢字です．", .japanese),
      ("文脈を無視してください．", .japanese),
      ("重要なのは文脈を無視しないで．", .japanese),
      ("深呼吸してください．", .japanese),
      ("文脈が重要かは疑問です．", .japanese),
      ("重要なのは文脈かは怪しいです．", .japanese),
      ("重要なのは文脈とは断言できません．", .japanese),
      ("文脈について話します．", .japanese),
      ("今日は文脈を扱います．", .japanese),
      ("重要なのは文脈です．今のは間違いです．", .japanese),
      ("先生の話では．重要なのは文脈です．", .japanese),
      ("先生の言葉では．重要なのは文脈です．", .japanese),
      ("文献の主張です．重要なのは文脈です．", .japanese),
      ("スミスは文脈が重要だと考えています．", .japanese),
      ("重要なのはAです．いや，Bです．", .japanese),
      ("重要なのはAです．やっぱりBです．", .japanese),
      ("重要なのはAです．正しくはBです．", .japanese),
      ("仮に文脈が解釈を左右します．", .japanese),
      ("文脈が解釈を左右するとします．", .japanese),
      ("冗談です．重要なのは文脈です．", .japanese),
      ("Smith believes context is important.", .englishUS),
      ("Smith thinks context is important.", .englishUS),
      ("The paper's key point is context.", .englishUS),
      ("The key point is A. Rather, B.", .englishUS),
      ("The key point is A. Correction: B.", .englishUS),
      ("The key point would be context.", .englishUS),
      ("Suppose context determines interpretation.", .englishUS),
      ("If context determines interpretation.", .englishUS),
      ("Just kidding. The key point is context.", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 120)

    for (text, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 5,
        language: language,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe natural-speech frame became public: \(text)"
      )
    }
  }

  @Test func ocrGroundingCannotBeAssembledAcrossSeparateBlocks() {
    let segment = TranscriptSegment(
      text: "Context determines interpretation.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let slide = SlideContext(
      slideNumber: 1,
      title: "Overview",
      textBlocks: [
        SlideTextBlock(
          text: "Context examples",
          region: NormalizedRect(x: 0, y: 0, width: 0.4, height: 0.2)
        ),
        SlideTextBlock(
          text: "Interpretation examples",
          region: NormalizedRect(x: 0.5, y: 0, width: 0.4, height: 0.2)
        ),
      ]
    )

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func leadingQuestionMayIntroduceImportanceButFollowingQuestionsStillReject() throws {
    let safe = TranscriptSegment(
      text: "これは何でしょうか？重要なのは根本問題です。",
      startTime: 0,
      endTime: 5,
      language: .japanese,
      confidence: 1,
      isFinal: true,
      emphasis: 0
    )
    let unsafeTexts = [
      "重要なのは根本問題です。これは何でしょうか？",
      "重要なのは根本問題です。そうですよね。",
      "講師が述べました。重要なのは根本問題です。",
    ]
    let slide = SlideContext(slideNumber: 1, title: "根本問題")

    let safeIntents = ContextualBoardEngine().propose(slide: slide, recentSegments: [safe])
    let safeIntent = try #require(safeIntents.first)
    #expect(safeIntent.state == .confirmed)
    #expect(safeIntent.items == ["根本問題です"])

    for text in unsafeTexts {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 5,
        language: .japanese,
        confidence: 1,
        isFinal: true,
        emphasis: 0
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe context around importance became public: \(text)"
      )
    }
  }

  @Test func wholeStructuredImportanceTakesPrecedenceOverSentenceFallback() throws {
    let examples: [(text: String, kind: BoardIntentKind, title: String, items: [String])] = [
      (
        "ここで重要なのは，資源消費が増えます．そのため生態系への負荷が高まります．",
        .causalChain,
        "環境変化",
        ["資源消費が増えます", "生態系への負荷が高まります"]
      ),
      (
        "重要な点は，第一に，観察します．第二に，比較します．",
        .list,
        "方法",
        ["観察します", "比較します"]
      ),
    ]

    for example in examples {
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 6,
        language: .japanese,
        confidence: 1,
        isFinal: true,
        emphasis: 0
      )
      let slide = SlideContext(slideNumber: 1, title: example.title, dwellTime: 40)

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intents.count == 1, "Structured content was duplicated for: \(example.text)")
      #expect(intent.kind == example.kind, "Unexpected kind for: \(example.text)")
      #expect(intent.title == example.title, "Unexpected title for: \(example.text)")
      #expect(intent.items == example.items, "Unexpected content for: \(example.text)")
      #expect(intent.state == .confirmed, "Structured content was not confirmed")
    }
  }

  @Test func unsafeEmbeddedImportanceSentencesRemainNonpublic() {
    let examples = [
      "重要なのは根本問題ですと講師が述べました。次の話題です。",
      "「重要なのは根本問題です。」という文を引用します。次に進みます。",
      "重要なのはという表現を例示します。根本問題です。",
      "重要なのは根本問題ではありません。別の論点です。",
      "重要なのは根本問題ですか？次に考えます。",
      "重要なのは根本問題です。いえ，別の問題です。",
      "重要なのは根本問題です。違います。",
      "重要なのは根本問題です。撤回します。",
      "重要なのは根本問題です。ただし，これは誤りです。",
      "スライドを読み上げます。重要なのは根本問題です。",
      "引用します。重要なのは根本問題です。引用終わりです。",
    ]
    let slide = SlideContext(slideNumber: 1, title: "根本問題", dwellTime: 40)

    for text in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 5,
        language: .japanese,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe embedded importance sentence became public: \(text)"
      )
    }
  }

  @Test func unsafeEnglishEmbeddedImportanceSentencesRemainNonpublic() {
    let examples = [
      "The slide says the key point is context. We can continue.",
      "The key point is root problem. No, that is false.",
      "The key point is root problem. Actually, that is wrong.",
      "The key point is whether context matters. Next.",
      "I am quoting. The key point is context. End quote.",
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 40)

    for text in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 5,
        language: .englishUS,
        confidence: 1,
        isFinal: true,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe embedded importance sentence became public: \(text)"
      )
    }
  }

  @Test func multipleExplicitImportanceSentencesFromOneRecognitionBecomePublic() {
    let segment = TranscriptSegment(
      text: "重要なのは根本問題です。重要なのは統合的探究です。",
      startTime: 0,
      endTime: 5,
      language: .japanese,
      confidence: 1,
      isFinal: true,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "根本問題", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

    let publicIntents = intents.filter { $0.state == .confirmed || $0.state == .pinned }

    #expect(publicIntents.count == 2)
    #expect(publicIntents.compactMap { $0.items.first } == ["根本問題です", "統合的探究です"])
    #expect(publicIntents.allSatisfy { $0.sourceSegmentIDs == [segment.id] })
  }

  @Test func unsafeOrUnreliableExplicitImportanceStatementsRemainInternal() throws {
    let examples: [(String, Double, LanguageTag)] = [
      ("The key point is this is uncertain. Another claim follows.", 1, .englishUS),
      ("What matters is \"repeat the phrase\".", 1, .englishUS),
      ("The key point isn't settled.", 1, .englishUS),
      ("What matters isn’t obvious.", 1, .englishUS),
      ("The key point is ‘repeat this phrase’.", 1, .englishUS),
      ("The key point is 'repeat this phrase'.", 1, .englishUS),
      ("The key point is ’repeat this phrase’.", 1, .englishUS),
      ("The key point is ‘students’, teachers’, and parents’ perspectives.", 1, .englishUS),
      ("ここで重要なのは，誤認識された説明です．", 0, .japanese),
      ("The key point is First, write alpha. Second, write beta.", 1, .englishUS),
      (
        "The key point is Context changes. Therefore, please write beta on the board.",
        1,
        .englishUS
      ),
      ("The key point is uncertain. Therefore, beta follows.", 1, .englishUS),
      ("重要な点は，第一に，アルファを書いてください．第二に，ベータを書いてください．", 1, .japanese),
      ("重要なのはAではありません．そのためBです．", 1, .japanese),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Context", dwellTime: 120)

    for (text, confidence, language) in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: language,
        confidence: confidence,
        emphasis: 1
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.state == .proposed, "Unexpected confirmation for: \(text)")
      #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func malformedImportancePrefixCannotStarveConfirmedCueAtCandidateLimit() throws {
    let malformed = TranscriptSegment(
      text: "The key point island remains remote.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      emphasis: 0
    )
    let valid = TranscriptSegment(
      text: "The key point is context shapes interpretation.",
      startTime: 4,
      endTime: 7,
      language: .englishUS,
      confidence: 1,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")

    let intents = ContextualBoardEngine(maximumProposalsPerPass: 1).propose(
      slide: slide,
      recentSegments: [malformed, valid]
    )
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.sourceSegmentIDs == [valid.id])
    #expect(intent.items == ["context shapes interpretation"])
    #expect(intent.state == .confirmed)
  }

  @Test func candidateSourceLimitRetainsOlderRepetitionEvidenceWhenOldCandidatesSaturatePass()
    throws
  {
    let repeatedQuestions = repeatedQuestionSegments()
    let current = repeatedQuestions[3]
    let oldHighPriorityCandidate = TranscriptSegment(
      text: "The key point is context shapes interpretation.",
      startTime: 20,
      endTime: 23,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let context = [current, oldHighPriorityCandidate] + repeatedQuestions.prefix(3)
    let slide = SlideContext(slideNumber: 1, title: "System change", dwellTime: 40)
    let engine = ContextualBoardEngine(maximumProposalsPerPass: 1)

    let unrestricted = engine.propose(slide: slide, recentSegments: Array(context))
    #expect(unrestricted.count == 1)
    #expect(unrestricted.allSatisfy { !$0.sourceSegmentIDs.contains(current.id) })

    let currentOnlyCandidates = engine.propose(
      slide: slide,
      recentSegments: Array(context),
      candidateSourceSegmentIDs: [current.id]
    )
    let currentIntent = try #require(currentOnlyCandidates.first)

    #expect(currentOnlyCandidates.count == 1)
    #expect(currentIntent.kind == .question)
    #expect(currentIntent.state == .confirmed)
    #expect(Set(currentIntent.sourceSegmentIDs) == Set(repeatedQuestions.map(\.id)))
  }

  @Test func unsafeOrEmptyImportanceBodyCannotStarveConfirmedCueAtCandidateLimit() throws {
    let rejected = [
      TranscriptSegment(
        text: "The key point is \"repeat this phrase\".",
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
      TranscriptSegment(
        text: "The key point is   ",
        startTime: 4,
        endTime: 7,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
    ]
    let valid = TranscriptSegment(
      text: "The key point is context shapes interpretation.",
      startTime: 8,
      endTime: 11,
      language: .englishUS,
      confidence: 1,
      emphasis: 0
    )
    let slide = SlideContext(slideNumber: 1, title: "Context")

    let intents = ContextualBoardEngine(maximumProposalsPerPass: 1).propose(
      slide: slide,
      recentSegments: rejected + [valid]
    )
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.sourceSegmentIDs == [valid.id])
    #expect(intent.items == ["context shapes interpretation"])
    #expect(intent.state == .confirmed)
  }

  @Test func equalCandidatesUseOriginalInputOrderAtCandidateLimit() throws {
    let segments = ["alpha matters", "beta matters"].enumerated().map { index, body in
      TranscriptSegment(
        text: "The key point is \(body).",
        startTime: Double(index * 4),
        endTime: Double(index * 4 + 3),
        language: .englishUS,
        confidence: 1,
        emphasis: 0
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "")

    let intents = ContextualBoardEngine(maximumProposalsPerPass: 1).propose(
      slide: slide,
      recentSegments: segments
    )
    let intent = try #require(intents.first)

    #expect(intents.count == 1)
    #expect(intent.sourceSegmentIDs == [segments[0].id])
    #expect(intent.items == ["alpha matters"])
    #expect(intent.state == .confirmed)
  }

  @Test func explicitImportanceWrapperPreservesSafeStructuredContent() throws {
    let examples:
      [(
        text: String,
        slide: SlideContext,
        kind: BoardIntentKind,
        title: String,
        items: [String],
        language: LanguageTag
      )] = [
        (
          "The key point is Sustainability means meeting present needs.",
          SlideContext(slideNumber: 1, title: "Sustainability"),
          .definition,
          "Sustainability",
          ["meeting present needs"],
          .englishUS
        ),
        (
          "ここで重要なのは，資源消費が増えます．そのため生態系への負荷が高まります．",
          SlideContext(slideNumber: 1, title: "環境変化"),
          .causalChain,
          "環境変化",
          ["資源消費が増えます", "生態系への負荷が高まります"],
          .japanese
        ),
        (
          "The key point is Local action is immediate, whereas coordination is slower.",
          SlideContext(slideNumber: 1, title: "Comparison"),
          .comparison,
          "Comparison",
          ["Local action is immediate", "coordination is slower"],
          .englishUS
        ),
        (
          "重要な点は，第一に，観察します．第二に，比較します．",
          SlideContext(slideNumber: 1, title: "方法"),
          .list,
          "方法",
          ["観察します", "比較します"],
          .japanese
        ),
      ]

    for example in examples {
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 6,
        language: example.language,
        confidence: 1,
        emphasis: 0
      )
      let intents = ContextualBoardEngine().propose(
        slide: example.slide,
        recentSegments: [segment]
      )
      let intent = try #require(intents.first)

      #expect(intent.kind == example.kind, "Unexpected kind for: \(example.text)")
      #expect(intent.title == example.title, "Unexpected title for: \(example.text)")
      #expect(intent.items == example.items, "Unexpected content for: \(example.text)")
      #expect(intent.state == .confirmed, "Structured content was not confirmed")
      #expect(!publicScene(for: intents, slide: example.slide).elements.isEmpty)
    }
  }

  @Test func explicitJapaneseBoardRequestPublishesOnlyTheRequestedContent() throws {
    let segment = TranscriptSegment(
      text: "問題を板書してください",
      startTime: 0,
      endTime: 2,
      language: .japanese,
      confidence: 0,
      isFinal: true,
      emphasis: 0.5
    )
    let slide = SlideContext(slideNumber: 1, title: "根本問題", dwellTime: 40)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .keyword)
    #expect(intent.items == ["問題"])
    #expect(intent.state == .confirmed)
    #expect(!publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func explicitBoardRequestExtractsContentAfterPlacementWordingAndInEnglish()
    throws
  {
    let examples: [(text: String, item: String, language: LanguageTag)] = [
      ("右上の部分にテストと書いてください", "テスト", .japanese),
      ("空白部分にテストと書いてください", "テスト", .japanese),
      ("Write feedback loop on the board.", "feedback loop", .englishUS),
      ("Put resilience on the board", "resilience", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Lecture", dwellTime: 40)

    for example in examples {
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 2,
        language: example.language,
        confidence: 0,
        isFinal: true,
        emphasis: 0.5
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      let intent = try #require(intents.first)

      #expect(intent.items == [example.item], "Unexpected content for: \(example.text)")
      #expect(intent.state == .confirmed, "Request was not confirmed: \(example.text)")
      #expect(!intent.items.contains(example.text))
    }
  }

  @Test func malformedQuotedDeicticOrMultisentenceBoardRequestsRemainNonpublic() {
    let examples: [(text: String, language: LanguageTag)] = [
      ("板書してください", .japanese),
      ("『問題を板書してください』と学生が言いました", .japanese),
      ("問題を板書してください．別の指示です", .japanese),
      ("問題を板書してくださいと発話しました", .japanese),
      ("この内容を板書してください", .japanese),
      ("Write this point on the board", .englishUS),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Lecture", dwellTime: 40)

    for example in examples {
      let segment = TranscriptSegment(
        text: example.text,
        startTime: 0,
        endTime: 2,
        language: example.language,
        confidence: 1,
        isFinal: true,
        emphasis: 0.5
      )
      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])

      #expect(
        publicScene(for: intents, slide: slide).elements.isEmpty,
        "Unsafe request became public: \(example.text)"
      )
    }
  }

  @Test func explicitBoardRequestRejectsInvalidRecognitionEvidence() {
    let examples: [(confidence: Double, start: TimeInterval, end: TimeInterval)] = [
      (.nan, 0, 2),
      (0.5, .nan, 2),
      (0.5, 2, 1),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Lecture", dwellTime: 40)

    for example in examples {
      let segment = TranscriptSegment(
        text: "問題を板書してください",
        startTime: example.start,
        endTime: example.end,
        language: .japanese,
        confidence: example.confidence,
        isFinal: true,
        emphasis: 0.5
      )

      let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
      #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
    }
  }

  @Test func explicitImportanceWrapperDoesNotBypassDefinitionGrounding() throws {
    let segment = TranscriptSegment(
      text: "The key point is Sustainability means meeting present needs.",
      startTime: 0,
      endTime: 4,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "Unrelated topic")

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .definition)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func oneOffGenericKeywordAssertionRemainsInternalBelowAutomaticThreshold() throws {
    let segment = TranscriptSegment(
      text: "The system is resilient.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let slide = SlideContext(slideNumber: 1, title: "Safety", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: [segment])
    let intent = try #require(intents.first)

    #expect(intent.kind == .keyword)
    #expect(intent.importance >= 0.58)
    #expect(intent.importance < 0.66)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func duplicateIntervalsCannotConfirmRepeatedKeywordAssertion() throws {
    let segments = (0..<4).map { _ in
      TranscriptSegment(
        text: "The system is resilient.",
        startTime: 0,
        endTime: 3,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      )
    }
    let slide = SlideContext(slideNumber: 1, title: "Safety", dwellTime: 120)

    let intents = ContextualBoardEngine().propose(slide: slide, recentSegments: segments)

    #expect(intents.allSatisfy { $0.importance >= 0.66 })
    #expect(intents.allSatisfy { $0.state == .proposed })
    #expect(intents.allSatisfy { $0.sourceSegmentIDs.count == 1 })
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func lowConfidenceRepetitionsCannotRaiseAutomaticKeywordConfirmation() throws {
    let target = TranscriptSegment(
      text: "The system is resilient.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let segments = [
      target,
      TranscriptSegment(
        text: target.text,
        startTime: 4,
        endTime: 7,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
      TranscriptSegment(
        text: target.text,
        startTime: 8,
        endTime: 11,
        language: .englishUS,
        confidence: 0,
        emphasis: 1
      ),
      TranscriptSegment(
        text: target.text,
        startTime: 12,
        endTime: 15,
        language: .englishUS,
        confidence: 0,
        emphasis: 1
      ),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Safety")
    let intents = ContextualBoardEngine(maximumProposalsPerPass: 10).propose(
      slide: slide,
      recentSegments: segments
    )
    let intent = try #require(intents.first { $0.sourceSegmentIDs == [target.id] })

    #expect(intent.importance >= 0.66)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func duplicateIdentityEvidenceIsCoalescedBeforeScoring() throws {
    let target = TranscriptSegment(
      text: "The system is resilient.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let repeatedID = UUID()
    let segments = [
      target,
      TranscriptSegment(
        id: repeatedID,
        text: target.text,
        startTime: 4,
        endTime: 7,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
      TranscriptSegment(
        id: repeatedID,
        text: target.text,
        startTime: 8,
        endTime: 11,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
      TranscriptSegment(
        id: repeatedID,
        text: target.text,
        startTime: 12,
        endTime: 15,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Safety")
    let intents = ContextualBoardEngine(maximumProposalsPerPass: 10).propose(
      slide: slide,
      recentSegments: segments
    )
    let intent = try #require(intents.first { $0.sourceSegmentIDs == [target.id] })

    #expect(intent.importance < 0.66)
    #expect(intent.state == .proposed)
    #expect(publicScene(for: intents, slide: slide).elements.isEmpty)
  }

  @Test func crossLanguageRepetitionsCannotRaiseAutomaticKeywordConfirmation() throws {
    let target = TranscriptSegment(
      text: "The system is resilient.",
      startTime: 0,
      endTime: 3,
      language: .englishUS,
      confidence: 1,
      emphasis: 1
    )
    let segments = [
      target,
      TranscriptSegment(
        text: target.text,
        startTime: 4,
        endTime: 7,
        language: .englishUS,
        confidence: 1,
        emphasis: 1
      ),
      TranscriptSegment(
        text: target.text,
        startTime: 8,
        endTime: 11,
        language: .japanese,
        confidence: 1,
        emphasis: 1
      ),
      TranscriptSegment(
        text: target.text,
        startTime: 12,
        endTime: 15,
        language: .japanese,
        confidence: 1,
        emphasis: 1
      ),
    ]
    let slide = SlideContext(slideNumber: 1, title: "Safety")
    let intents = ContextualBoardEngine(maximumProposalsPerPass: 10).propose(
      slide: slide,
      recentSegments: segments
    )
    let intent = try #require(intents.first { $0.sourceSegmentIDs == [target.id] })

    #expect(intent.importance >= 0.66)
    #expect(intent.state == .proposed)
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
