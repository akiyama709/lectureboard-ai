import Testing

@testable import LectureBoardCore

struct ManagedSlideShowBindingPolicyTests {
  @Test func confirmsOnlyACandidateAfterAStableZeroToOneTransition() {
    var policy = ManagedSlideShowBindingPolicy()
    let baseline = observation(count: 0, windows: [window(10)])
    let baselineRepeat = observation(
      count: 0,
      freshnessSequence: 2,
      windows: [window(10)]
    )
    let postStart = observation(
      count: 1,
      freshnessSequence: 3,
      windows: [window(10), window(20)]
    )
    let repeatedPostStart = observation(
      count: 1,
      freshnessSequence: 4,
      windows: [window(10), window(20)]
    )
    let stablePostStart = observation(
      count: 1,
      freshnessSequence: 5,
      windows: [window(10), window(20)]
    )

    #expect(policy.begin(target: target(), baseline: baseline) == .baselineAccepted)
    #expect(policy.state == .awaitingSlideShowStart)
    #expect(policy.ingest(baselineRepeat) == .awaitingSlideShowStart)
    #expect(policy.ingest(postStart) == .candidateAccepted(window(20)))
    #expect(policy.state == .confirmingCandidate)
    #expect(policy.candidateWindowIdentity == window(20))
    #expect(policy.confirmedCandidateWindowIdentity == nil)

    #expect(policy.ingest(repeatedPostStart) == .candidateConfirmed(window(20)))
    #expect(policy.state == .candidateConfirmed)
    #expect(policy.candidateWindowIdentity == nil)
    #expect(policy.confirmedCandidateWindowIdentity == window(20))
    #expect(policy.ingest(stablePostStart) == .stable(window(20)))
  }

  @Test func acceptsInventoryOrderingChangesWhenTheExactIdentitiesAreStable() {
    var policy = ManagedSlideShowBindingPolicy()
    let baseline = observation(count: 0, windows: [window(10), window(11)])
    let first = observation(count: 1, windows: [window(20), window(10), window(11)])
    let repeated = observation(
      count: 1,
      freshnessSequence: 3,
      windows: [window(11), window(20), window(10)]
    )

    #expect(policy.begin(target: target(), baseline: baseline) == .baselineAccepted)
    #expect(policy.ingest(first) == .candidateAccepted(window(20)))
    #expect(policy.ingest(repeated) == .candidateConfirmed(window(20)))
  }

  @Test func rejectsMalformedTarget() {
    for malformed in [
      target(session: ""),
      target(processIdentifier: 0),
      target(processIdentifier: -1),
      target(bundleIdentifier: ""),
    ] {
      var policy = ManagedSlideShowBindingPolicy()
      #expect(
        policy.begin(target: malformed, baseline: observation(count: 0, windows: []))
          == .rejected(.malformedTarget)
      )
      #expect(policy.state == .rejected)
    }
  }

  @Test func rejectsMalformedAndMismatchedBaselineSessions() {
    var malformedPolicy = ManagedSlideShowBindingPolicy()
    #expect(
      malformedPolicy.begin(
        target: target(),
        baseline: observation(session: "", count: 0, windows: [])
      ) == .rejected(.malformedObservationSession)
    )

    var mismatchPolicy = ManagedSlideShowBindingPolicy()
    #expect(
      mismatchPolicy.begin(
        target: target(),
        baseline: observation(session: "other-session", count: 0, windows: [])
      ) == .rejected(.observationSessionMismatch)
    )
  }

  @Test func rejectsMalformedFreshnessEvidenceAtBaselineAndAfterStart() {
    for malformedToken in ["", "  \n"] {
      var baselinePolicy = ManagedSlideShowBindingPolicy()
      #expect(
        baselinePolicy.begin(
          target: target(),
          baseline: observation(
            count: 0,
            freshObservationToken: malformedToken,
            windows: [window(10)]
          )
        ) == .rejected(.malformedFreshObservationToken)
      )

      var postPolicy = startedPolicy()
      #expect(
        postPolicy.ingest(
          observation(
            count: 1,
            freshObservationToken: malformedToken,
            observedMachAbsoluteTime: 2,
            windows: [window(10), window(20)]
          )
        ) == .rejected(.malformedFreshObservationToken)
      )
    }

    var baselineTimePolicy = ManagedSlideShowBindingPolicy()
    #expect(
      baselineTimePolicy.begin(
        target: target(),
        baseline: observation(
          count: 0,
          freshObservationToken: "fresh-baseline",
          observedMachAbsoluteTime: 0,
          windows: [window(10)]
        )
      ) == .rejected(.malformedObservedMachAbsoluteTime)
    )

    var postTimePolicy = startedPolicy()
    #expect(
      postTimePolicy.ingest(
        observation(
          count: 1,
          freshObservationToken: "fresh-post",
          observedMachAbsoluteTime: 0,
          windows: [window(10), window(20)]
        )
      ) == .rejected(.malformedObservedMachAbsoluteTime)
    )
  }

  @Test func aCachedPostStartObservationCannotConfirmItsOwnCandidate() {
    var policy = startedPolicy()
    let cached = observation(count: 1, windows: [window(10), window(20)])

    #expect(policy.ingest(cached) == .candidateAccepted(window(20)))
    #expect(policy.ingest(cached) == .rejected(.reusedFreshObservationToken))
    #expect(policy.state == .rejected)
    #expect(policy.confirmedCandidateWindowIdentity == nil)
    #expect(
      policy.ingest(
        observation(
          count: 1,
          freshnessSequence: 3,
          windows: [window(10), window(20)]
        )
      ) == .rejected(.reusedFreshObservationToken)
    )
  }

  @Test func observationMachTimeMustStrictlyIncreaseAndLatchesItsFirstFailure() {
    var equalTimePolicy = startedPolicy()
    let equalTime = observation(
      count: 1,
      freshObservationToken: "different-token",
      observedMachAbsoluteTime: 1,
      windows: [window(10), window(20)]
    )
    #expect(
      equalTimePolicy.ingest(equalTime)
        == .rejected(.nonIncreasingObservedMachAbsoluteTime)
    )

    var decreasingTimePolicy = ManagedSlideShowBindingPolicy()
    #expect(
      decreasingTimePolicy.begin(
        target: target(),
        baseline: observation(
          count: 0,
          freshObservationToken: "later-baseline",
          observedMachAbsoluteTime: 3,
          windows: [window(10)]
        )
      ) == .baselineAccepted
    )
    #expect(
      decreasingTimePolicy.ingest(
        observation(
          count: 1,
          freshObservationToken: "earlier-post",
          observedMachAbsoluteTime: 2,
          windows: [window(10), window(20)]
        )
      ) == .rejected(.nonIncreasingObservedMachAbsoluteTime)
    )
    #expect(
      decreasingTimePolicy.ingest(
        observation(
          count: 1,
          freshObservationToken: "otherwise-fresh",
          observedMachAbsoluteTime: 4,
          windows: [window(10), window(20)]
        )
      ) == .rejected(.nonIncreasingObservedMachAbsoluteTime)
    )
  }

  @Test func rejectsMalformedScriptingEvidence() {
    for evidence in [
      ManagedSlideShowScriptingEvidence(
        processIdentifier: 0,
        activePresentationCount: 1,
        slideShowWindowCount: 0
      ),
      ManagedSlideShowScriptingEvidence(
        processIdentifier: 501,
        activePresentationCount: -1,
        slideShowWindowCount: 0
      ),
      ManagedSlideShowScriptingEvidence(
        processIdentifier: 501,
        activePresentationCount: 1,
        slideShowWindowCount: -1
      ),
    ] {
      var policy = ManagedSlideShowBindingPolicy()
      let baseline = ManagedSlideShowInventoryObservation(
        bindingSessionToken: "session-a",
        freshObservationToken: "observation-1",
        observedMachAbsoluteTime: 1,
        scriptingEvidence: evidence,
        windows: []
      )
      #expect(
        policy.begin(target: target(), baseline: baseline)
          == .rejected(.malformedScriptingEvidence)
      )
    }

    var postPolicy = startedPolicy()
    let malformedPost = ManagedSlideShowInventoryObservation(
      bindingSessionToken: "session-a",
      freshObservationToken: "observation-2",
      observedMachAbsoluteTime: 2,
      scriptingEvidence: ManagedSlideShowScriptingEvidence(
        processIdentifier: 501,
        activePresentationCount: 1,
        slideShowWindowCount: -1
      ),
      windows: [window(10)]
    )
    #expect(
      postPolicy.ingest(malformedPost) == .rejected(.malformedScriptingEvidence)
    )
  }

  @Test func rejectsBaselineFromAReplacementProcess() {
    var policy = ManagedSlideShowBindingPolicy()
    let baseline = observation(processIdentifier: 777, count: 0, windows: [])

    #expect(
      policy.begin(target: target(), baseline: baseline)
        == .rejected(.scriptingProcessIdentifierMismatch)
    )
  }

  @Test func requiresExactlyOneActivePresentationAtBaselineAndAfterStart() {
    for activePresentationCount in [0, 2] {
      var baselinePolicy = ManagedSlideShowBindingPolicy()
      #expect(
        baselinePolicy.begin(
          target: target(),
          baseline: observation(
            activePresentationCount: activePresentationCount,
            count: 0,
            windows: [window(10)]
          )
        ) == .rejected(.baselineActivePresentationCountNotOne)
      )

      var postPolicy = startedPolicy()
      #expect(
        postPolicy.ingest(
          observation(
            activePresentationCount: activePresentationCount,
            count: 1,
            windows: [window(10), window(20)]
          )
        ) == .rejected(.activePresentationCountNotOne)
      )
    }
  }

  @Test func rejectsAnAlreadyActiveOrMultipleBaselineSlideShow() {
    for count in [1, 2] {
      var policy = ManagedSlideShowBindingPolicy()
      #expect(
        policy.begin(target: target(), baseline: observation(count: count, windows: []))
          == .rejected(.baselineSlideShowAlreadyActive)
      )
    }
  }

  @Test func rejectsMalformedWindowIdentitiesAtBaselineAndPostStart() {
    for malformed in [
      window(0),
      window(-1),
      window(10, processIdentifier: 0),
      window(10, bundleIdentifier: ""),
    ] {
      var baselinePolicy = ManagedSlideShowBindingPolicy()
      #expect(
        baselinePolicy.begin(
          target: target(),
          baseline: observation(count: 0, windows: [malformed])
        ) == .rejected(.malformedWindowIdentity)
      )

      var postPolicy = startedPolicy()
      #expect(
        postPolicy.ingest(observation(count: 1, windows: [window(10), malformed]))
          == .rejected(.malformedWindowIdentity)
      )
    }
  }

  @Test func rejectsDuplicateWindowIDsAtBaselineAndPostStart() {
    var baselinePolicy = ManagedSlideShowBindingPolicy()
    #expect(
      baselinePolicy.begin(
        target: target(),
        baseline: observation(count: 0, windows: [window(10), window(10)])
      ) == .rejected(.duplicateWindowID)
    )

    var postPolicy = startedPolicy()
    #expect(
      postPolicy.ingest(
        observation(count: 1, windows: [window(10), window(20), window(20)])
      ) == .rejected(.duplicateWindowID)
    )
  }

  @Test func rejectsWrongWindowProcessAndBundleAtBaselineAndPostStart() {
    var baselineProcessPolicy = ManagedSlideShowBindingPolicy()
    #expect(
      baselineProcessPolicy.begin(
        target: target(),
        baseline: observation(count: 0, windows: [window(10, processIdentifier: 777)])
      ) == .rejected(.wrongWindowProcessIdentifier)
    )

    var baselineBundlePolicy = ManagedSlideShowBindingPolicy()
    #expect(
      baselineBundlePolicy.begin(
        target: target(),
        baseline: observation(count: 0, windows: [window(10, bundleIdentifier: "wrong")])
      ) == .rejected(.wrongWindowBundleIdentifier)
    )

    var postProcessPolicy = startedPolicy()
    #expect(
      postProcessPolicy.ingest(
        observation(count: 1, windows: [window(10), window(20, processIdentifier: 777)])
      ) == .rejected(.wrongWindowProcessIdentifier)
    )

    var postBundlePolicy = startedPolicy()
    #expect(
      postBundlePolicy.ingest(
        observation(count: 1, windows: [window(10), window(20, bundleIdentifier: "wrong")])
      ) == .rejected(.wrongWindowBundleIdentifier)
    )
  }

  @Test func rejectsPreTransitionInventoryDrift() {
    var policy = startedPolicy()

    #expect(
      policy.ingest(
        observation(
          count: 0,
          freshnessSequence: 2,
          windows: [window(10), window(20)]
        )
      )
        == .rejected(.preTransitionInventoryChanged)
    )
  }

  @Test func rejectsAReplacementScriptingProcessAfterStart() {
    var policy = startedPolicy()

    #expect(
      policy.ingest(observation(processIdentifier: 777, count: 1, windows: [window(10)]))
        == .rejected(.scriptingProcessIdentifierMismatch)
    )
  }

  @Test func rejectsMalformedAndMismatchedPostStartSessions() {
    var malformedPolicy = startedPolicy()
    #expect(
      malformedPolicy.ingest(
        observation(session: "", count: 1, windows: [window(10), window(20)])
      ) == .rejected(.malformedObservationSession)
    )

    var mismatchPolicy = startedPolicy()
    #expect(
      mismatchPolicy.ingest(
        observation(session: "other-session", count: 1, windows: [window(10), window(20)])
      ) == .rejected(.observationSessionMismatch)
    )
  }

  @Test func rejectsMultipleScriptingWindowsAfterStart() {
    var policy = startedPolicy()

    #expect(
      policy.ingest(observation(count: 2, windows: [window(10), window(20)]))
        == .rejected(.multipleScriptingSlideShowWindows)
    )
  }

  @Test func rejectsBaselineDisappearance() {
    var policy = ManagedSlideShowBindingPolicy()
    let baseline = observation(count: 0, windows: [window(10), window(11)])
    #expect(policy.begin(target: target(), baseline: baseline) == .baselineAccepted)

    #expect(
      policy.ingest(observation(count: 1, windows: [window(11), window(20)]))
        == .rejected(.baselineWindowMissing)
    )
  }

  @Test func rejectsWindowIDReuseWithoutAPreviouslyAbsentID() {
    var policy = startedPolicy()

    #expect(
      policy.ingest(observation(count: 1, windows: [window(10)]))
        == .rejected(.noPreviouslyAbsentWindowID)
    )
  }

  @Test func rejectsMultiplePreviouslyAbsentWindowIDs() {
    var policy = startedPolicy()

    #expect(
      policy.ingest(observation(count: 1, windows: [window(10), window(20), window(21)]))
        == .rejected(.multiplePreviouslyAbsentWindowIDs)
    )
  }

  @Test func rejectsConcurrentDriftBetweenCandidateObservations() {
    var policy = startedPolicy()
    let candidate = observation(count: 1, windows: [window(10), window(20)])
    #expect(policy.ingest(candidate) == .candidateAccepted(window(20)))

    #expect(
      policy.ingest(
        observation(count: 1, freshnessSequence: 3, windows: [window(10), window(21)])
      )
        == .rejected(.candidateEvidenceChanged)
    )
  }

  @Test func rejectsCandidateReversalAndBaselineLossDuringConfirmation() {
    var reversalPolicy = startedPolicy()
    let candidate = observation(count: 1, windows: [window(10), window(20)])
    _ = reversalPolicy.ingest(candidate)
    #expect(
      reversalPolicy.ingest(
        observation(count: 0, freshnessSequence: 3, windows: [window(10)])
      )
        == .rejected(.candidateEvidenceChanged)
    )

    var lossPolicy = ManagedSlideShowBindingPolicy()
    let baseline = observation(count: 0, windows: [window(10), window(11)])
    _ = lossPolicy.begin(target: target(), baseline: baseline)
    _ = lossPolicy.ingest(
      observation(count: 1, windows: [window(10), window(11), window(20)])
    )
    #expect(
      lossPolicy.ingest(
        observation(count: 1, freshnessSequence: 3, windows: [window(11), window(20)])
      )
        == .rejected(.candidateEvidenceChanged)
    )
  }

  @Test func rejectsDriftAfterCandidateConfirmation() {
    var policy = confirmedCandidatePolicy()

    #expect(
      policy.ingest(
        observation(
          count: 1,
          freshnessSequence: 4,
          windows: [window(10), window(20), window(21)]
        )
      )
        == .rejected(.confirmedCandidateEvidenceChanged)
    )
    #expect(policy.confirmedCandidateWindowIdentity == nil)
  }

  @Test func rejectionIsLatchedUntilReset() {
    var policy = startedPolicy()
    let rejected = policy.ingest(observation(count: 1, windows: [window(10)]))
    #expect(rejected == .rejected(.noPreviouslyAbsentWindowID))

    let otherwiseValid = observation(count: 1, windows: [window(10), window(20)])
    #expect(policy.ingest(otherwiseValid) == rejected)
    #expect(
      policy.begin(
        target: target(),
        baseline: observation(count: 0, windows: [window(10)])
      ) == rejected
    )
    #expect(policy.state == .rejected)

    policy.reset()
    #expect(policy == ManagedSlideShowBindingPolicy())
    #expect(
      policy.begin(
        target: target(),
        baseline: observation(count: 0, windows: [window(10)])
      ) == .baselineAccepted
    )
  }

  @Test func rejectsStaleSessionEvidenceAfterResetAndANewBegin() {
    var policy = startedPolicy()
    policy.reset()
    let newTarget = target(session: "session-b")
    let newBaseline = observation(session: "session-b", count: 0, windows: [window(10)])
    #expect(policy.begin(target: newTarget, baseline: newBaseline) == .baselineAccepted)

    #expect(
      policy.ingest(observation(session: "session-a", count: 1, windows: [window(10), window(20)]))
        == .rejected(.observationSessionMismatch)
    )
  }

  @Test func ingestAfterResetIsClosedButDoesNotPreventANewBegin() {
    var policy = startedPolicy()
    policy.reset()

    #expect(
      policy.ingest(observation(count: 1, windows: [window(10), window(20)]))
        == .rejected(.notStarted)
    )
    #expect(policy.state == .idle)
    #expect(
      policy.begin(target: target(), baseline: observation(count: 0, windows: [window(10)]))
        == .baselineAccepted
    )
  }

  @Test func aSecondBeginRequiresAnExplicitReset() {
    var policy = startedPolicy()

    #expect(
      policy.begin(target: target(), baseline: observation(count: 0, windows: [window(10)]))
        == .rejected(.startRequiresReset)
    )
    #expect(policy.state == .rejected)
  }

  private func startedPolicy() -> ManagedSlideShowBindingPolicy {
    var policy = ManagedSlideShowBindingPolicy()
    let event = policy.begin(
      target: target(),
      baseline: observation(count: 0, windows: [window(10)])
    )
    #expect(event == .baselineAccepted)
    return policy
  }

  private func confirmedCandidatePolicy() -> ManagedSlideShowBindingPolicy {
    var policy = startedPolicy()
    let postStart = observation(count: 1, windows: [window(10), window(20)])
    let repeatedPostStart = observation(
      count: 1,
      freshnessSequence: 3,
      windows: [window(10), window(20)]
    )
    #expect(policy.ingest(postStart) == .candidateAccepted(window(20)))
    #expect(policy.ingest(repeatedPostStart) == .candidateConfirmed(window(20)))
    return policy
  }

  private func target(
    session: String = "session-a",
    processIdentifier: Int = 501,
    bundleIdentifier: String = "com.microsoft.Powerpoint"
  ) -> ManagedSlideShowBindingTarget {
    ManagedSlideShowBindingTarget(
      bindingSessionToken: session,
      processIdentifier: processIdentifier,
      bundleIdentifier: bundleIdentifier
    )
  }

  private func observation(
    session: String = "session-a",
    processIdentifier: Int = 501,
    activePresentationCount: Int = 1,
    count: Int,
    freshnessSequence: UInt64? = nil,
    freshObservationToken: String? = nil,
    observedMachAbsoluteTime: UInt64? = nil,
    windows: [ManagedSlideShowWindowIdentity]
  ) -> ManagedSlideShowInventoryObservation {
    let resolvedSequence = freshnessSequence ?? (count == 0 ? 1 : 2)
    return ManagedSlideShowInventoryObservation(
      bindingSessionToken: session,
      freshObservationToken: freshObservationToken ?? "observation-\(resolvedSequence)",
      observedMachAbsoluteTime: observedMachAbsoluteTime ?? resolvedSequence,
      scriptingEvidence: ManagedSlideShowScriptingEvidence(
        processIdentifier: processIdentifier,
        activePresentationCount: activePresentationCount,
        slideShowWindowCount: count
      ),
      windows: windows
    )
  }

  private func window(
    _ windowID: Int,
    processIdentifier: Int = 501,
    bundleIdentifier: String = "com.microsoft.Powerpoint"
  ) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: processIdentifier,
      bundleIdentifier: bundleIdentifier
    )
  }
}
