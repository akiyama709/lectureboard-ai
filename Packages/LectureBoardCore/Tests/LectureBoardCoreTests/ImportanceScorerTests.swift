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
}
