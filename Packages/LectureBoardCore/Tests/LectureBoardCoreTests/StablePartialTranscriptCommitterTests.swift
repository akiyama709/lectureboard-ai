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

  @Test func pausedUnpunctuatedJapaneseImportanceStatementCommitsExactlyOnce() throws {
    let id = UUID()
    let partial = segment(id: id, text: "ここで重要なのはテストです", endTime: 1)
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let pausedCommit = committer.commitAfterPause(partial)
    let committed = try #require(pausedCommit)

    #expect(committed.id == id)
    #expect(committed.text == "ここで重要なのはテストです")
    #expect(committed.isFinal)
    #expect(committed.confidence == partial.confidence)
    #expect(committed.emphasis == partial.emphasis)
    #expect(committer.commitAfterPause(partial) == nil)
  }

  @Test func pauseFallbackPromotesFiniteLowConfidenceWithoutWeakeningOrdinaryPath() throws {
    let id = UUID()
    let text = "ここで重要なのはテストです"

    for confidence in [0.0, 0.49] {
      var committer = StablePartialTranscriptCommitter()
      let partial = segment(id: id, text: text, endTime: 1, confidence: confidence)
      #expect(committer.observe(partial) == nil)
      let pausedObservation = committer.commitAfterPause(partial)
      let pausedCommit = try #require(pausedObservation)
      #expect(pausedCommit.confidence == 0.5)

      var ordinary = StablePartialTranscriptCommitter()
      let punctuated = segment(id: id, text: text + "．", endTime: 1, confidence: confidence)
      #expect(ordinary.observe(punctuated) == nil)
      #expect(
        ordinary.observe(
          segment(id: id, text: punctuated.text, endTime: 2, confidence: confidence)
        ) == nil
      )
    }
  }

  @Test func pauseFallbackRejectsStaleUnsafeOrUnreliablePartials() {
    let id = UUID()

    func isRejected(
      _ observed: TranscriptSegment,
      candidate: TranscriptSegment? = nil
    ) -> Bool {
      var committer = StablePartialTranscriptCommitter()
      _ = committer.observe(observed)
      return committer.commitAfterPause(candidate ?? observed) == nil
    }

    let complete = segment(id: id, text: "ここで重要なのはテストです", endTime: 1)
    #expect(isRejected(complete, candidate: segment(id: id, text: complete.text, endTime: 2)))
    #expect(isRejected(segment(id: id, text: "ここで重要なのはテストですか", endTime: 1)))
    #expect(isRejected(segment(id: id, text: "ここで重要なのはテストですが", endTime: 1)))
    #expect(isRejected(segment(id: id, text: "重要なのはテストです", endTime: 1)))
    #expect(isRejected(segment(id: id, text: "ここで重要なのはまだ", endTime: 1)))
    #expect(
      isRejected(
        segment(
          id: id,
          text: "ここで重要なのはテストです",
          endTime: 1,
          emphasis: .nan
        )
      )
    )
    #expect(
      isRejected(
        segment(id: id, text: "ここで重要なのはテストです", endTime: 1, confidence: .nan)
      )
    )
    #expect(
      isRejected(
        segment(id: id, text: "ここで重要なのはテストです", endTime: 1, confidence: -0.01)
      )
    )
    #expect(
      isRejected(
        segment(id: id, text: "ここで重要なのはテストです", endTime: 1, confidence: 1.01)
      )
    )
    #expect(
      isRejected(
        segment(id: id, text: "ここで重要なのはテストです", endTime: 1, emphasis: 1.01)
      )
    )
    #expect(
      isRejected(
        TranscriptSegment(
          id: id,
          text: "ここで重要なのはテストです",
          startTime: .nan,
          endTime: 1,
          language: .japanese,
          confidence: 0,
          isFinal: false,
          emphasis: 0.8
        )
      )
    )
    #expect(
      isRejected(
        TranscriptSegment(
          id: id,
          text: "ここで重要なのはテストです",
          startTime: 2,
          endTime: 1,
          language: .japanese,
          confidence: 0,
          isFinal: false,
          emphasis: 0.8
        )
      )
    )
    #expect(
      isRejected(
        TranscriptSegment(
          id: id,
          text: "The key point is that this is a complete test",
          startTime: 0,
          endTime: 1,
          language: .englishUS,
          confidence: 0.95,
          isFinal: false,
          emphasis: 0.8
        )
      )
    )
  }

  @Test func pauseFallbackRequiresAPriorObservationAndRejectsPunctuatedSingleRevision() {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()
    let unpunctuated = segment(id: id, text: "ここで重要なのはテストです", endTime: 1)
    #expect(committer.commitAfterPause(unpunctuated) == nil)

    let punctuated = segment(id: id, text: "ここで重要なのはテストです．", endTime: 2)
    #expect(committer.observe(punctuated) == nil)
    #expect(committer.commitAfterPause(punctuated) == nil)
    #expect(committer.observe(segment(id: id, text: punctuated.text, endTime: 3)) != nil)
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
