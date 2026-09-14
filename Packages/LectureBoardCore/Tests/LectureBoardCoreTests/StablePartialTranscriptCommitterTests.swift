import Foundation
import Testing

@testable import LectureBoardCore

struct StablePartialTranscriptCommitterTests {
  @Test func shortLeadingUnitDoesNotBlockStableImportantUnit() throws {
    let id = UUID()
    let text = "タイトルです。重要なのは根本問題です。"
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(segment(id: id, text: text, endTime: 1)) == nil)
    let committedObservation = committer.observe(segment(id: id, text: text, endTime: 2))
    let committed = try #require(committedObservation)

    #expect(committed.id == id)
    #expect(committed.text == text)
    #expect(committed.isFinal)
  }

  @Test func appendedStableCompleteUnitRetainsCumulativeProviderEvidence() throws {
    let id = UUID()
    let first = "持続可能性とは，将来世代の選択肢を守ることです．"
    let second = "重要なのは変化には時間がかかることです．"
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(segment(id: id, text: first + " 次の論点", endTime: 1)) == nil
    )
    let firstCommitObservation = committer.observe(
      segment(id: id, text: first + " 次の論点を説明します", endTime: 2)
    )
    let firstCommit = try #require(firstCommitObservation)
    #expect(firstCommit.text == first + " 次の論点を説明します")

    #expect(committer.observe(segment(id: id, text: first + second, endTime: 3)) == nil)
    let secondCommitObservation = committer.observe(
      segment(id: id, text: first + second, endTime: 4)
    )
    let secondCommit = try #require(secondCommitObservation)
    #expect(secondCommit.id == id)
    #expect(secondCommit.text == first + second)
    #expect(committer.observe(segment(id: id, text: first + second, endTime: 5)) == nil)
  }

  @Test func revisionOfCommittedOrConsumedPrefixQuarantinesSegmentUntilFinal() throws {
    let id = UUID()
    let committedPrefix = "持続可能性とは，将来世代の選択肢を守ることです．"
    let revisedPrefix = "持続可能性とは，現在世代の選択肢を守ることです．"
    let laterUnit = "重要なのは変化には時間がかかることです．"
    var afterCommit = StablePartialTranscriptCommitter()

    #expect(afterCommit.observe(segment(id: id, text: committedPrefix, endTime: 1)) == nil)
    let initialCommit = afterCommit.observe(
      segment(id: id, text: committedPrefix, endTime: 2)
    )
    _ = try #require(initialCommit)
    #expect(
      afterCommit.observe(segment(id: id, text: revisedPrefix + laterUnit, endTime: 3)) == nil
    )
    #expect(
      afterCommit.observe(segment(id: id, text: revisedPrefix + laterUnit, endTime: 4)) == nil
    )

    var afterConsumption = StablePartialTranscriptCommitter()
    #expect(
      afterConsumption.observe(segment(id: id, text: "タイトルです。続き", endTime: 1))
        == nil
    )
    #expect(
      afterConsumption.observe(segment(id: id, text: "タイトルです。まだ続き", endTime: 2))
        == nil
    )
    let contradictory = "訂正後の説明は十分に長い別の内容になりました．重要なのは根本問題です。"
    #expect(afterConsumption.observe(segment(id: id, text: contradictory, endTime: 3)) == nil)
    #expect(afterConsumption.observe(segment(id: id, text: contradictory, endTime: 4)) == nil)

    #expect(
      afterConsumption.observe(
        segment(id: id, text: contradictory, endTime: 5, isFinal: true)
      ) == nil
    )
    #expect(afterConsumption.observe(segment(id: id, text: laterUnit, endTime: 6)) == nil)
    #expect(afterConsumption.observe(segment(id: id, text: laterUnit, endTime: 7)) != nil)
  }

  @Test func completeQuestionIsConsumedWithoutBlockingFollowingDeclarativeUnit() throws {
    let id = UUID()
    let text = "これは何でしょうか？重要なのは根本問題です。"
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(segment(id: id, text: text, endTime: 1)) == nil)
    let committedObservation = committer.observe(segment(id: id, text: text, endTime: 2))
    let committed = try #require(committedObservation)

    #expect(committed.text == text)
    #expect(committer.observe(segment(id: id, text: text, endTime: 3)) == nil)
  }

  @Test func pausedPunctuatedZeroConfidenceImportancePrefixCommitsExactlyOnce() throws {
    let id = UUID()
    let partial = segment(
      id: id,
      text: "タイトルです。重要なのは根本問題です。",
      endTime: 1,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let committedObservation = committer.commitAfterPause(partial)
    let committed = try #require(committedObservation)
    #expect(committed.text == partial.text)
    #expect(committed.confidence == 0)
    #expect(committed.isFinal)
    #expect(committer.commitAfterPause(partial) == nil)
  }

  @Test func stableExactZeroImportancePrefixCommitsWhileTheHypothesisKeepsGrowing() throws {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(
        segment(
          id: id,
          text: "ここで重要なのは根本問題です。続いて",
          endTime: 1,
          confidence: 0
        )
      ) == nil
    )
    let committedObservation = committer.observe(
      segment(
        id: id,
        text: "ここで重要なのは根本問題です。続いて背景を",
        endTime: 2,
        confidence: 0
      )
    )
    let committed = try #require(committedObservation)

    #expect(committed.id == id)
    #expect(committed.text == "ここで重要なのは根本問題です。続いて背景を")
    #expect(committed.confidence == 0)
    #expect(committed.isFinal)
  }

  @Test func stableExactZeroShortImportanceUnitIsForwardedForSemanticReview() throws {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(
        segment(id: id, text: "要点は文脈です。続いて", endTime: 1, confidence: 0)
      ) == nil
    )
    let committedObservation = committer.observe(
      segment(id: id, text: "要点は文脈です。続いて説明", endTime: 2, confidence: 0)
    )
    let committed = try #require(committedObservation)

    #expect(committed.text == "要点は文脈です。続いて説明")
    #expect(committed.confidence == 0)
  }

  @Test func laterStableUnitRetainsProviderIdentityAndCumulativeEvidence() throws {
    let id = UUID()
    let first = "重要なのは根本問題です。"
    let second = "大切な点は文脈です。"
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(segment(id: id, text: first, endTime: 1)) == nil)
    let firstCommitObservation = committer.observe(
      segment(id: id, text: first + "続いて", endTime: 2)
    )
    let firstCommit = try #require(firstCommitObservation)
    #expect(firstCommit.id == id)
    #expect(firstCommit.text == first + "続いて")

    #expect(
      committer.observe(segment(id: id, text: first + second, endTime: 3)) == nil
    )
    let secondCommitObservation = committer.observe(
      segment(id: id, text: first + second, endTime: 4)
    )
    let secondCommit = try #require(secondCommitObservation)

    #expect(secondCommit.id == id)
    #expect(secondCommit.id == firstCommit.id)
    #expect(secondCommit.text == first + second)
  }

  @Test func pausedPunctuatedEnglishImportancePrefixCommitsExactlyOnce() throws {
    let id = UUID()
    let partial = segment(
      id: id,
      text: "The key point is the root problem.",
      endTime: 1,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let committedObservation = committer.commitAfterPause(partial)
    let committed = try #require(committedObservation)
    #expect(committed.text == partial.text)
    #expect(committed.confidence == 0)
    #expect(committed.isFinal)
    #expect(committer.commitAfterPause(partial) == nil)
  }

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
    #expect(committed.text == "Sustainability means meeting present needs. Future possibilities")
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

  @Test func pauseFallbackPreservesEveryFiniteBoundedConfidenceWithoutInflation() throws {
    for confidence in [0, 0.01, 0.49, 0.5, 1] {
      for text in ["ここで重要なのはテストです", "ここで重要なのはテストです．"] {
        let partial = segment(
          id: UUID(),
          text: text,
          endTime: 1,
          confidence: confidence
        )
        var committer = StablePartialTranscriptCommitter()
        #expect(committer.observe(partial) == nil)
        let committedObservation = committer.commitAfterPause(partial)
        let committed = try #require(committedObservation)
        #expect(committed.confidence == confidence)
      }
    }

    let id = UUID()
    let text = "ここで重要なのはテストです"
    var ordinary = StablePartialTranscriptCommitter()
    let punctuated = segment(id: id, text: text + "．", endTime: 1, confidence: 0)
    #expect(ordinary.observe(punctuated) == nil)
    #expect(
      ordinary.observe(
        segment(id: id, text: punctuated.text, endTime: 2, confidence: 0)
      ) != nil
    )
  }

  @Test func punctuatedPauseFallbackPreservesMultipleImportanceUnits() throws {
    let id = UUID()
    let partial = segment(
      id: id,
      text: "重要なのは根本問題です。最も重要なのは文脈です。",
      endTime: 1,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let committedObservation = committer.commitAfterPause(partial)
    let committed = try #require(committedObservation)
    #expect(committed.text == partial.text)
    #expect(committer.commitAfterPause(partial) == nil)
  }

  @Test func stableExactZeroPrefixPreservesFollowingCorrectionForSemanticReview() throws {
    let id = UUID()
    let text = "重要なのは根本問題です。いや，違います。"
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(segment(id: id, text: text, endTime: 1, confidence: 0)) == nil
    )
    let committedObservation = committer.observe(
      segment(id: id, text: text, endTime: 2, confidence: 0)
    )
    let committed = try #require(committedObservation)

    #expect(committed.text == text)
    #expect(committed.confidence == 0)
  }

  @Test func pausePrefixPreservesFollowingCorrectionForSemanticReview() throws {
    let id = UUID()
    let partial = segment(
      id: id,
      text: "重要なのは根本問題です。いや，違います。",
      endTime: 1,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let committedObservation = committer.commitAfterPause(partial)
    let committed = try #require(committedObservation)

    #expect(committed.text == partial.text)
  }

  @Test func exactZeroPrefixPreservesTwoImportanceUnitsWithoutConsumingThemSilently() throws {
    let id = UUID()
    let first = "重要なのは根本問題です。大切な点は文脈です。"
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(
        segment(id: id, text: first + "続いて", endTime: 1, confidence: 0)
      ) == nil
    )
    let committedObservation = committer.observe(
      segment(id: id, text: first + "続いて説明", endTime: 2, confidence: 0)
    )
    let committed = try #require(committedObservation)

    #expect(committed.text == first + "続いて説明")
    #expect(committed.confidence == 0)
  }

  @Test func newlyAppendedUnsafeTailIsIncludedInOrdinarySemanticReview() throws {
    let stableImportance = "重要なのはAです。"

    for tail in ["いや", "違います", "本当でしょうか"] {
      let id = UUID()
      var committer = StablePartialTranscriptCommitter()
      #expect(
        committer.observe(segment(id: id, text: stableImportance, endTime: 1)) == nil
      )
      let latestText = stableImportance + tail
      let committedObservation = committer.observe(
        segment(id: id, text: latestText, endTime: 2)
      )
      let committed = try #require(committedObservation)

      #expect(committed.text == latestText)
      #expect(committed.id == id)
      #expect(committed.isFinal)
    }
  }

  @Test func pauseFallbackFindsUnpunctuatedImportanceAfterACompletedLeadingUnit() throws {
    let id = UUID()
    let partial = segment(
      id: id,
      text: "タイトルです。重要なのは根本問題です",
      endTime: 1,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let committedObservation = committer.commitAfterPause(partial)
    let committed = try #require(committedObservation)

    #expect(committed.text == partial.text)
    #expect(committed.confidence == 0)
    #expect(committed.isFinal)
    #expect(committer.commitAfterPause(partial) == nil)
  }

  @Test func stablePrefixPreservesAnUnpunctuatedCorrectionForSemanticReview() throws {
    let id = UUID()
    let text = "重要なのは根本問題です。いや違います"
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(segment(id: id, text: text, endTime: 1, confidence: 0)) == nil
    )
    let committedObservation = committer.observe(
      segment(id: id, text: text, endTime: 2, confidence: 0)
    )
    let committed = try #require(committedObservation)

    #expect(committed.text == text)
    #expect(committed.confidence == 0)
  }

  @Test func pausePrefixPreservesAnUnpunctuatedCorrectionForSemanticReview() throws {
    let id = UUID()
    let partial = segment(
      id: id,
      text: "重要なのは根本問題です。いや違います",
      endTime: 1,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(partial) == nil)
    let committedObservation = committer.commitAfterPause(partial)
    let committed = try #require(committedObservation)

    #expect(committed.text == partial.text)
  }

  @Test func stablePrefixPreservesAnUnpunctuatedQuestionForSemanticReview() throws {
    let id = UUID()
    let text = "重要なのは根本問題です。本当でしょうか"
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(segment(id: id, text: text, endTime: 1, confidence: 0)) == nil
    )
    let committedObservation = committer.observe(
      segment(id: id, text: text, endTime: 2, confidence: 0)
    )
    let committed = try #require(committedObservation)

    #expect(committed.text == text)
  }

  @Test func stablePrefixPreservesAnUnpunctuatedQualificationForSemanticReview() throws {
    let id = UUID()
    let text = "重要なのは根本問題です。ただし仮説かもしれません"
    var committer = StablePartialTranscriptCommitter()

    #expect(
      committer.observe(segment(id: id, text: text, endTime: 1, confidence: 0)) == nil
    )
    let committedObservation = committer.observe(
      segment(id: id, text: text, endTime: 2, confidence: 0)
    )
    let committed = try #require(committedObservation)

    #expect(committed.text == text)
  }

  @Test func correctionOfPauseCommittedPrefixQuarantinesSegmentUntilFinal() throws {
    let id = UUID()
    let original = segment(
      id: id,
      text: "タイトルです。重要なのは根本問題です。",
      endTime: 1,
      confidence: 0
    )
    let corrected = segment(
      id: id,
      text: "タイトルです。重要なのは別の問題です。",
      endTime: 2,
      confidence: 0
    )
    var committer = StablePartialTranscriptCommitter()

    #expect(committer.observe(original) == nil)
    let originalCommit = committer.commitAfterPause(original)
    _ = try #require(originalCommit)
    #expect(committer.observe(corrected) == nil)
    #expect(committer.commitAfterPause(corrected) == nil)

    #expect(
      committer.observe(
        segment(id: id, text: corrected.text, endTime: 3, confidence: 0, isFinal: true)
      ) == nil
    )
    #expect(committer.observe(corrected) == nil)
    #expect(committer.commitAfterPause(corrected) != nil)
  }

  @Test func pauseFallbackPublishesSafeWholeUtteranceBoardRequests() throws {
    let examples: [(text: String, confidence: Double)] = [
      ("問題を板書してください", 0),
      ("空白部分にテストと書いてください", 0.25),
      ("Please write context on the board", 0.49),
      ("Please write context on the board.", 1),
    ]

    for example in examples {
      let partial = segment(
        id: UUID(),
        text: example.text,
        endTime: 1,
        confidence: example.confidence
      )
      var committer = StablePartialTranscriptCommitter()

      #expect(committer.observe(partial) == nil)
      let committedObservation = committer.commitAfterPause(partial)
      let committed = try #require(committedObservation)
      #expect(committed.id == partial.id)
      #expect(committed.text == example.text)
      #expect(committed.confidence == example.confidence)
      #expect(committed.isFinal)
      #expect(committer.commitAfterPause(partial) == nil)
    }
  }

  @Test func pauseFallbackRejectsUnsafeOrIncompleteBoardRequests() {
    let examples = [
      "問題を板書して",
      "『問題を板書してください』と学生が言いました",
      "学生が問題を板書してくださいと言いました",
      "問題を板書してください。文脈を板書してください",
      "この内容を板書してください",
      "Please write context on the",
      "“Please write context on the board.”",
      "The student said please write context on the board.",
    ]

    for text in examples {
      let partial = segment(id: UUID(), text: text, endTime: 1, confidence: 0)
      var committer = StablePartialTranscriptCommitter()
      #expect(committer.observe(partial) == nil)
      #expect(committer.commitAfterPause(partial) == nil)
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
    #expect(isRejected(segment(id: id, text: "The key point is the", endTime: 1)))
  }

  @Test func pauseFallbackRequiresAPriorObservationAndAcceptsSafePunctuatedPrefix() {
    let id = UUID()
    var committer = StablePartialTranscriptCommitter()
    let unpunctuated = segment(id: id, text: "ここで重要なのはテストです", endTime: 1)
    #expect(committer.commitAfterPause(unpunctuated) == nil)

    let punctuated = segment(id: id, text: "ここで重要なのはテストです．", endTime: 2)
    #expect(committer.observe(punctuated) == nil)
    #expect(committer.commitAfterPause(punctuated) != nil)
    #expect(committer.commitAfterPause(punctuated) == nil)
  }

  @Test func addedNaturalCuesReachTheExactZeroStablePath() throws {
    let examples = [
      "肝は文脈です．続いて",
      "根本問題は重要です．続いて",
      "The crux is context. Next",
      "Above all, context matters. Next",
    ]

    for text in examples {
      let id = UUID()
      var committer = StablePartialTranscriptCommitter()
      #expect(
        committer.observe(segment(id: id, text: text, endTime: 1, confidence: 0)) == nil
      )
      let committedObservation = committer.observe(
        segment(id: id, text: text + " topic", endTime: 2, confidence: 0)
      )
      let committed = try #require(committedObservation)
      #expect(committed.id == id)
      #expect(committed.confidence == 0)
      #expect(committed.isFinal)
    }
  }

  @Test func shortUnpunctuatedNaturalJapaneseCuesReachThePausePath() throws {
    let examples = [
      "重要なのはテストです",
      "肝は文脈です",
      "根本問題は重要です",
      "文脈を覚えておいてください",
    ]

    for text in examples {
      let id = UUID()
      let partial = segment(id: id, text: text, endTime: 1, confidence: 0)
      var committer = StablePartialTranscriptCommitter()
      #expect(committer.observe(partial) == nil)
      let committedObservation = committer.commitAfterPause(partial)
      let committed = try #require(committedObservation)
      #expect(committed.id == id)
      #expect(committed.text == text)
      #expect(committed.confidence == 0)
      #expect(committer.commitAfterPause(partial) == nil)
    }
  }

  @Test func unpunctuatedEnglishImportanceReachesThePausePath() throws {
    for text in [
      "The key point is context",
      "The crux is feedback",
    ] {
      let partial = segment(id: UUID(), text: text, endTime: 1, confidence: 0.2)
      var committer = StablePartialTranscriptCommitter()
      #expect(committer.observe(partial) == nil)
      let committedObservation = committer.commitAfterPause(partial)
      let committed = try #require(committedObservation)
      #expect(committed.text == text)
      #expect(committed.confidence == 0.2)
      #expect(committed.isFinal)
      #expect(committer.commitAfterPause(partial) == nil)
    }
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
