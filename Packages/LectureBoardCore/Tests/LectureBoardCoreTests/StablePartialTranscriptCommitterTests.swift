import Foundation
import Testing

@testable import LectureBoardCore

struct StablePartialTranscriptCommitterTests {
  @Test func growingHypothesisCommitsItsFirstStableCompleteUnitBeforeFinal() throws {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(
        segment(
          id: id,
          text: "Sustainability means meeting present needs. Future",
          endTime: 1
        )
      ) == nil
    )
    let committedObservation = committer.observe(
      segment(
        id: id,
        text: "Sustainability means meeting present needs. Future possibilities",
        endTime: 2,
        confidence: 0.8,
        emphasis: 0.7
      )
    )
    let committed = try #require(committedObservation)

    #expect(committed.id == id)
    #expect(committed.text == "Sustainability means meeting present needs.")
    #expect(committed.isFinal)
    #expect(committed.confidence == 0.8)
    #expect(committed.emphasis == 0.7)
    #expect(committed.endTime == 2)
  }

  @Test func incompleteQuestionShortAndDifferentSegmentHypothesesRemainUncommitted() {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()
    #expect(committer.observe(segment(id: id, text: "まだ説明の途中です", endTime: 1)) == nil)
    #expect(committer.observe(segment(id: id, text: "まだ説明の途中です", endTime: 2)) == nil)

    committer.reset()
    #expect(committer.observe(segment(id: id, text: "これは何でしょうか？", endTime: 1)) == nil)
    #expect(committer.observe(segment(id: id, text: "これは何でしょうか？", endTime: 2)) == nil)

    committer.reset()
    #expect(committer.observe(segment(id: id, text: "短いです．", endTime: 1)) == nil)
    #expect(committer.observe(segment(id: id, text: "短いです．", endTime: 2)) == nil)

    committer.reset()
    #expect(
      committer.observe(
        segment(id: id, text: "十分に長い説明単位がここで完了します．", endTime: 1)
      ) == nil
    )
    #expect(
      committer.observe(
        segment(id: UUID(), text: "十分に長い説明単位がここで完了します．", endTime: 2)
      ) == nil
    )
  }

  @Test func unreliableOrOutOfOrderHypothesesRemainUncommitted() {
    let id = UUID()
    var lowConfidence = StablePartialTranscriptCommitter()
    #expect(
      lowConfidence.observe(
        segment(id: id, text: "十分に長い説明単位がここで完了します．", endTime: 1)
      ) == nil
    )
    #expect(
      lowConfidence.observe(
        segment(
          id: id,
          text: "十分に長い説明単位がここで完了します．",
          endTime: 2,
          confidence: 0.49
        )
      ) == nil
    )

    var outOfOrder = StablePartialTranscriptCommitter()
    #expect(
      outOfOrder.observe(
        segment(id: id, text: "十分に長い説明単位がここで完了します．", endTime: 2)
      ) == nil
    )
    #expect(
      outOfOrder.observe(
        segment(id: id, text: "十分に長い説明単位がここで完了します．", endTime: 1)
      ) == nil
    )
  }

  @Test func oneSegmentCommitsOnlyOnceAndFinalStartsANewBoundary() throws {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()
    let completed = "持続可能性とは，将来世代の可能性を損なわないことです．"

    #expect(committer.observe(segment(id: id, text: completed, endTime: 1)) == nil)
    let committed = committer.observe(segment(id: id, text: completed, endTime: 2))
    _ = try #require(committed)
    #expect(committer.observe(segment(id: id, text: completed + " 次", endTime: 3)) == nil)
    #expect(
      committer.observe(
        segment(id: id, text: completed, endTime: 4, isFinal: true)
      ) == nil
    )
    #expect(committer.observe(segment(id: id, text: completed, endTime: 5)) == nil)
    #expect(committer.observe(segment(id: id, text: completed, endTime: 6)) != nil)
  }

  private func segment(
    id: UUID,
    text: String,
    endTime: TimeInterval,
    confidence: Double = 0.95,
    isFinal: Bool = false,
    emphasis: Double = 0.8
  ) -> TranscriptSegment {
    TranscriptSegment(
      id: id,
      text: text,
      startTime: 0,
      endTime: endTime,
      language: text.first?.isASCII == true ? .englishUS : .japanese,
      confidence: confidence,
      isFinal: isFinal,
      emphasis: emphasis
    )
  }
}
