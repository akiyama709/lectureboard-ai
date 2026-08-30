import Testing

@testable import LectureBoardCore

struct SlideIdentityTrackerTests {
  @Test func requiresTwoConsecutiveSamplesToEstablishBaselineAndSlideChange() throws {
    var tracker = SlideIdentityTracker()
    let first = try sample(session: "presentation-a", slideID: 101, index: 1)
    let second = try sample(session: "presentation-a", slideID: 202, index: 2)

    #expect(tracker.ingest(.available(first)) == .none)
    #expect(tracker.state == .establishing)
    #expect(tracker.slideChangeCount == 0)

    #expect(tracker.ingest(.available(first)) == .baselineEstablished)
    #expect(tracker.state == .identified)
    #expect(tracker.slideChangeCount == 0)

    #expect(tracker.ingest(.available(second)) == .none)
    #expect(tracker.state == .establishing)
    #expect(tracker.slideChangeCount == 0)

    #expect(tracker.ingest(.available(second)) == .slideChanged)
    #expect(tracker.state == .identified)
    #expect(tracker.slideChangeCount == 1)
    #expect(tracker.sampleCount == 4)
  }

  @Test func candidateMustBeConsecutive() throws {
    var tracker = SlideIdentityTracker()
    let first = try sample(session: "presentation-a", slideID: 101, index: 1)
    let second = try sample(session: "presentation-a", slideID: 202, index: 2)

    tracker.ingest(.available(first))
    tracker.ingest(.available(first))
    tracker.ingest(.available(second))

    #expect(tracker.ingest(.available(first)) == .none)
    #expect(tracker.state == .identified)
    #expect(tracker.slideChangeCount == 0)

    #expect(tracker.ingest(.available(second)) == .none)
    #expect(tracker.ingest(.available(second)) == .slideChanged)
    #expect(tracker.slideChangeCount == 1)
  }

  @Test func unavailableGapDiscardsContinuityAndRecoveryEstablishesANewBaseline() throws {
    var tracker = SlideIdentityTracker()
    let first = try sample(session: "presentation-a", slideID: 101, index: 1)
    let second = try sample(session: "presentation-a", slideID: 202, index: 2)

    tracker.ingest(.available(first))
    tracker.ingest(.available(first))

    #expect(tracker.ingest(.unavailable) == .continuityBroken)
    #expect(tracker.state == .interrupted)
    #expect(tracker.continuityBreakCount == 1)
    #expect(tracker.ingest(.unavailable) == .none)
    #expect(tracker.continuityBreakCount == 1)

    #expect(tracker.ingest(.available(second)) == .none)
    #expect(tracker.state == .establishing)
    #expect(tracker.ingest(.available(second)) == .baselineEstablished)
    #expect(tracker.state == .identified)
    #expect(tracker.slideChangeCount == 0)
  }

  @Test func unavailableBeforeAnyIdentityRemainsUnavailable() {
    var tracker = SlideIdentityTracker()

    #expect(tracker.ingest(.unavailable) == .none)
    #expect(tracker.state == .unavailable)
    #expect(tracker.sampleCount == 1)
    #expect(tracker.continuityBreakCount == 0)
  }

  @Test func presentationSessionChangeReestablishesBaselineWithoutCountingSlideChange() throws {
    var tracker = SlideIdentityTracker()
    let first = try sample(session: "presentation-a", slideID: 101, index: 1)
    let reopened = try sample(session: "presentation-b", slideID: 202, index: 2)

    tracker.ingest(.available(first))
    tracker.ingest(.available(first))

    #expect(tracker.ingest(.available(reopened)) == .continuityBroken)
    #expect(tracker.state == .establishing)
    #expect(tracker.continuityBreakCount == 1)
    #expect(tracker.slideChangeCount == 0)

    #expect(tracker.ingest(.available(reopened)) == .baselineEstablished)
    #expect(tracker.state == .identified)
    #expect(tracker.slideChangeCount == 0)
  }

  @Test func presentationSessionChangeAlsoBreaksAnUnconfirmedSequence() throws {
    var tracker = SlideIdentityTracker()
    let first = try sample(session: "presentation-a", slideID: 101, index: 1)
    let reopened = try sample(session: "presentation-b", slideID: 202, index: 2)

    #expect(tracker.ingest(.available(first)) == .none)
    #expect(tracker.ingest(.available(reopened)) == .continuityBroken)
    #expect(tracker.continuityBreakCount == 1)
    #expect(tracker.slideChangeCount == 0)
    #expect(tracker.ingest(.available(reopened)) == .baselineEstablished)
    #expect(tracker.slideChangeCount == 0)
  }

  @Test func indexUpdateForTheSameSlideIDDoesNotCountAsAChange() throws {
    var tracker = SlideIdentityTracker()
    let firstIndex = try sample(session: "presentation-a", slideID: 101, index: 1)
    let updatedIndex = try sample(session: "presentation-a", slideID: 101, index: 3)

    tracker.ingest(.available(firstIndex))
    tracker.ingest(.available(firstIndex))

    #expect(tracker.ingest(.available(updatedIndex)) == .metadataUpdated)
    #expect(tracker.state == .identified)
    #expect(tracker.slideChangeCount == 0)
  }

  @Test func rejectsInvalidIdentitySamples() {
    #expect(
      SlideIdentitySample(
        presentationSessionToken: "presentation-a",
        slideID: 0,
        slideIndex: 1
      ) == nil
    )
    #expect(
      SlideIdentitySample(
        presentationSessionToken: "presentation-a",
        slideID: -1,
        slideIndex: 1
      ) == nil
    )
    #expect(
      SlideIdentitySample(
        presentationSessionToken: "presentation-a",
        slideID: 1,
        slideIndex: 0
      ) == nil
    )
    #expect(
      SlideIdentitySample(
        presentationSessionToken: "presentation-a",
        slideID: 1,
        slideIndex: -1
      ) == nil
    )
    #expect(
      SlideIdentitySample(
        presentationSessionToken: "",
        slideID: 1,
        slideIndex: 1
      ) == nil
    )
  }

  @Test func resetClearsStateAndCounters() throws {
    var tracker = SlideIdentityTracker()
    let first = try sample(session: "presentation-a", slideID: 101, index: 1)

    tracker.ingest(.available(first))
    tracker.ingest(.available(first))
    tracker.ingest(.unavailable)
    tracker.reset()

    #expect(tracker == SlideIdentityTracker())
    #expect(tracker.state == .unavailable)
    #expect(tracker.sampleCount == 0)
    #expect(tracker.continuityBreakCount == 0)
    #expect(tracker.slideChangeCount == 0)
  }

  private func sample(
    session: String,
    slideID: Int,
    index: Int
  ) throws -> SlideIdentitySample {
    try #require(
      SlideIdentitySample(
        presentationSessionToken: session,
        slideID: slideID,
        slideIndex: index
      )
    )
  }
}
