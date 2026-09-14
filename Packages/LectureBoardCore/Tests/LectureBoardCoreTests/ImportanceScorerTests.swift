import Foundation
import Testing

@testable import LectureBoardCore

struct ImportanceScorerTests {
  @Test func definitionNotOnSlideReceivesHighScore() {
    let slide = SlideContext(
      slideNumber: 1,
      title: "統合知",
      textBlocks: [
        SlideTextBlock(
          text: "科学知　実践知　価値",
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        )
      ],
      dwellTime: 45
    )
    let segment = TranscriptSegment(
      text: "統合知とは，知識を並べることではなく，認識，価値，実践を結び直すことです．",
      startTime: 3,
      endTime: 9,
      language: .japanese,
      emphasis: 0.8
    )

    let score = ImportanceScorer().score(segment: segment, slide: slide, recentSegments: [])
    #expect(score.total >= 0.58)
    #expect(score.discourseStructure == 1)
  }

  @Test func nearVerbatimSlideReadingIsPenalizedAsRedundant() {
    let slideText = "持続可能性は環境，社会，経済の均衡を考える"
    let slide = SlideContext(
      slideNumber: 2,
      title: "持続可能性",
      textBlocks: [
        SlideTextBlock(
          text: slideText,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.5)
        )
      ]
    )
    let segment = TranscriptSegment(
      text: slideText,
      startTime: 1,
      endTime: 5,
      language: .japanese,
      emphasis: 0.2
    )

    let score = ImportanceScorer().score(segment: segment, slide: slide, recentSegments: [])
    #expect(score.novelty < 0.2)
    #expect(score.total < 0.58)
  }

  @Test func explicitImportanceCuesClearTheProductionThresholdWithoutOtherSignals() {
    let examples: [(String, LanguageTag)] = [
      ("ここで重要なのは，変化には時間がかかることです．", .japanese),
      ("重要な点は，変化には時間がかかることです．", .japanese),
      ("一番大切なのは文脈です．", .japanese),
      ("特に重要なことは関係性です．", .japanese),
      ("大事なのは文脈です．", .japanese),
      ("大事なことは文脈です．", .japanese),
      ("大切な点は文脈です．", .japanese),
      ("肝心なのは変化を追うことです．", .japanese),
      ("要点は時間がかかることです．", .japanese),
      ("今日のポイントは文脈です．", .japanese),
      ("強調したいのは文脈です．", .japanese),
      ("覚えてほしいのは変化は段階的だということです．", .japanese),
      ("押さえるべき点は関係性です．", .japanese),
      ("注目してほしいのは時間の変化です．", .japanese),
      ("要するに文脈が意味を決めます．", .japanese),
      ("まとめると根本問題です．", .japanese),
      ("この核心は相互作用です．", .japanese),
      ("根本問題がいちばん重要です．", .japanese),
      ("文脈が鍵です．", .japanese),
      ("相互作用こそ核心です．", .japanese),
      ("結論として根本問題です．", .japanese),
      ("ここで押さえてほしいのは根本問題です．", .japanese),
      ("The key point is change takes time.", .englishUS),
      ("The point is context changes interpretation.", .englishUS),
      ("The bottom line is context matters.", .englishUS),
      ("The take-home message is change takes time.", .englishUS),
      ("The main point is context.", .englishUS),
      ("The important thing is timing.", .englishUS),
      ("The important point here is context.", .englishUS),
      ("A key point is context.", .englishUS),
      ("Our key point is context.", .englishUS),
      ("The most important point is context.", .englishUS),
      ("The central idea is integration.", .englishUS),
      ("Pay attention to how context changes meaning.", .englishUS),
      ("I want to emphasize that context changes meaning.", .englishUS),
      ("In summary, context changes meaning.", .englishUS),
      ("What matters is change takes time.", .englishUS),
      ("Remember that change takes time.", .englishUS),
      ("The takeaway here is context.", .englishUS),
      ("Keep in mind that context matters.", .englishUS),
      ("The root problem is most important.", .englishUS),
      ("Context is key.", .englishUS),
      ("Integration is central.", .englishUS),
      ("Context is the bottom line.", .englishUS),
      ("Change is worth remembering.", .englishUS),
      ("The root problem matters most.", .englishUS),
      ("In conclusion, the root problem matters.", .englishUS),
      ("What I want you to remember here is the root problem.", .englishUS),
    ]

    for (text, language) in examples {
      let slide = SlideContext(
        slideNumber: 1,
        title: "",
        textBlocks: [
          SlideTextBlock(
            text: text,
            region: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
          )
        ]
      )
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: language,
        emphasis: 0
      )

      let score = ImportanceScorer().score(
        segment: segment,
        slide: slide,
        recentSegments: []
      )

      #expect(score.discourseStructure == 1, "Missing importance cue for: \(text)")
      #expect(score.total >= 0.58, "Importance cue did not clear threshold: \(text)")
    }
  }

  @Test func malformedEnglishImportancePrefixesReceiveNoLexicalBonus() {
    let examples = [
      "The key point isn't settled.",
      "What matters isn’t obvious.",
      "The key point island remains remote.",
      "We will discuss whether the bottom line is unclear.",
      "This is key to opening the archive.",
      "Pay attention tomorrow.",
      "A key point cloud appeared.",
      "Remember tomorrow.",
      "Keep in mind tomorrow.",
    ]
    let slide = SlideContext(slideNumber: 1, title: "")

    for text in examples {
      let segment = TranscriptSegment(
        text: text,
        startTime: 0,
        endTime: 4,
        language: .englishUS,
        emphasis: 0
      )
      let score = ImportanceScorer().score(
        segment: segment,
        slide: slide,
        recentSegments: []
      )

      #expect(score.discourseStructure == 0.35, "Malformed cue received structure: \(text)")
      #expect(score.total < 0.58, "Malformed cue received lexical importance: \(text)")
    }
  }

  @Test func importanceCuePatternsYieldOneNonemptyExtractableBody() throws {
    let prefixExamples = [
      ("大事なのは文脈です．", "文脈です．"),
      ("大事なことは文脈です．", "文脈です．"),
      ("大切な点は文脈です．", "文脈です．"),
      ("押さえるべき点は関係性です．", "関係性です．"),
      ("注目してほしいのは時間の変化です．", "時間の変化です．"),
      ("今日のポイントは文脈です．", "文脈です．"),
      ("強調したいのは文脈です．", "文脈です．"),
      ("要するに，文脈が意味を決めます．", "文脈が意味を決めます．"),
      ("まとめると根本問題です．", "根本問題です．"),
      ("The point is context matters.", "context matters."),
      ("The bottom line is context matters.", "context matters."),
      ("The take-home message is change takes time.", "change takes time."),
      ("The important point here is context.", "context."),
      ("A key point is context.", "context."),
      ("Our key point is context.", "context."),
      ("The takeaway here is context.", "context."),
      ("Keep in mind that context matters.", "context matters."),
      ("Pay attention to how context changes meaning.", "how context changes meaning."),
      ("I want to emphasize that context changes meaning.", "context changes meaning."),
      ("In summary, context changes meaning.", "context changes meaning."),
    ]
    let suffixExamples = [
      ("文脈が鍵です．", "文脈"),
      ("相互作用こそ核心です．", "相互作用"),
      ("Context is key.", "Context"),
      ("Integration is central.", "Integration"),
      ("Context is the bottom line.", "Context"),
      ("Change is worth remembering.", "Change"),
    ]

    for (text, expectedBody) in prefixExamples {
      let ranges = ImportanceScorer.importancePrefixCuePatterns.compactMap { pattern in
        firstMatchRange(for: pattern, in: text)
      }
      #expect(ranges.count == 1, "Expected one prefix cue for: \(text)")
      let range = try #require(ranges.first)
      let body = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
      #expect(body == expectedBody, "Unexpected prefix body for: \(text)")
    }

    for (text, expectedBody) in suffixExamples {
      let ranges = ImportanceScorer.importanceSuffixCuePatterns.compactMap { pattern in
        firstMatchRange(for: pattern, in: text)
      }
      #expect(ranges.count == 1, "Expected one suffix cue for: \(text)")
      let range = try #require(ranges.first)
      let body = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
      #expect(body == expectedBody, "Unexpected suffix body for: \(text)")
    }
  }

  private func firstMatchRange(for pattern: String, in text: String) -> Range<String.Index>? {
    guard
      let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else {
      return nil
    }
    let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, range: searchRange) else { return nil }
    return Range(match.range, in: text)
  }
}
