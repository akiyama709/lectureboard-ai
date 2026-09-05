import Testing

@testable import LectureBoardCore

struct ManagedSlideShowRoleChallengePolicyTests {
  @Test func visibilityChallengeSucceedsOnlyAfterStableHideAndRestoration() throws {
    let result = run(method: .visibility, observations: transcript(method: .visibility))
    #expect(result == .succeeded(freshnessBoundaryMachAbsoluteTime: 320))
  }

  @Test func visibilityHiddenMayRemoveOnlyTheCandidateFromOnScreenInventory() {
    var evidence = transcript(method: .visibility)
    evidence[2] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 41,
      repeatIndex: 0,
      candidateAbsent: true
    )
    evidence[3] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 41,
      repeatIndex: 1,
      candidateAbsent: true
    )
    #expect(
      run(method: .visibility, observations: evidence)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 320)
    )
  }

  @Test func pixelNonceChallengeSucceedsInBlackWhiteRunningOrder() throws {
    let result = run(method: .pixelNonce, observations: transcript(method: .pixelNonce))
    #expect(result == .succeeded(freshnessBoundaryMachAbsoluteTime: 420))
  }

  @Test func successUsesTheLatestRestoredObservationOrFrameTime() {
    var evidence = transcript(method: .visibility)
    evidence[5] = observation(
      method: .visibility,
      phase: .visibilityRestored,
      nonce: 42,
      repeatIndex: 1,
      evidenceObservedTime: 330,
      candidateDisplayTime: 330,
      callbackMachAbsoluteTime: 330
    )
    #expect(
      run(method: .visibility, observations: evidence)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 330)
    )
  }

  @Test func initiallyBlackSlideIsAllowedWhenWhiteStillRespondsAndBlackRestores() {
    var evidence = transcript(method: .pixelNonce)
    for index in [0, 1, 6, 7] {
      let phase: ManagedSlideShowRoleChallengePhase =
        index < 2
        ? .baseline
        : .pixelRunningRestored
      let nonce: UInt64 = index < 2 ? 40 : 43
      evidence[index] = observation(
        method: .pixelNonce,
        phase: phase,
        nonce: nonce,
        repeatIndex: index.isMultiple(of: 2) ? 0 : 1,
        candidateLuminance: 0
      )
    }
    #expect(
      run(method: .pixelNonce, observations: evidence)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
    )
  }

  @Test func rawLuminanceThresholdAndPresentationSavedStateFailClosed() {
    var notBlack = transcript(method: .pixelNonce)
    notBlack[2] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 0,
      candidateLuminance: 30
    )
    #expect(
      run(method: .pixelNonce, observations: notBlack)
        == .rejected(.wrongVisualSignature)
    )

    var savedChanged = transcript(method: .visibility)
    savedChanged[2] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 41,
      repeatIndex: 0,
      presentationSaved: false
    )
    #expect(
      run(method: .visibility, observations: savedChanged)
        == .rejected(.semanticStateChanged)
    )
  }

  @Test func oddNonceReversesThePixelOrderToWhiteThenBlack() {
    let oddTarget = target(challengeNonce: 41)
    let evidence = transcript(method: .pixelNonce, challengeNonce: 41)
    var policy = ManagedSlideShowRoleChallengePolicy()
    #expect(policy.begin(target: oddTarget, method: .pixelNonce) == .started)
    for observation in evidence {
      #expect(policy.ingest(observation) != .rejected(.phaseOutOfOrder))
    }
    #expect(policy.finish() == .succeeded(freshnessBoundaryMachAbsoluteTime: 420))
    #expect(evidence[2].phase == .pixelWhite)
    #expect(evidence[4].phase == .pixelBlack)
  }

  @Test func missingAndStaleEvidenceFailClosed() {
    var missing = ManagedSlideShowRoleChallengePolicy()
    #expect(missing.begin(target: target(), method: .visibility) == .started)
    for observation in transcript(method: .visibility).dropLast() {
      _ = missing.ingest(observation)
    }
    #expect(missing.finish() == .rejected(.incompleteChallenge))

    var stale = ManagedSlideShowRoleChallengePolicy()
    #expect(stale.begin(target: target(), method: .visibility) == .started)
    let baseline = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 0,
      evidenceObservedTime: 100
    )
    #expect(stale.ingest(baseline) == .rejected(.staleEvidenceObservationTime))
  }

  @Test func targetBindingAndCaptureMismatchesAreBounded() {
    let cases:
      [(ManagedSlideShowRoleChallengeObservation, ManagedSlideShowRoleChallengeRejection)] = [
        (observation(session: "wrong", method: .visibility), .sessionMismatch),
        (observation(objectToken: "wrong", method: .visibility), .objectTokenMismatch),
        (observation(processIdentifier: 999, method: .visibility), .processIdentifierMismatch),
        (observation(bundleIdentifier: "wrong", method: .visibility), .bundleIdentifierMismatch),
        (observation(candidateWindowID: 21, method: .visibility), .candidateIdentityMismatch),
        (observation(captureOperationID: 8, method: .visibility), .captureOperationMismatch),
        (observation(captureGeneration: 10, method: .visibility), .captureGenerationMismatch),
      ]

    for (evidence, expected) in cases {
      var policy = ManagedSlideShowRoleChallengePolicy()
      #expect(policy.begin(target: target(), method: .visibility) == .started)
      #expect(policy.ingest(evidence) == .rejected(expected))
    }
  }

  @Test func restorationAndOtherWindowChangesAreRejected() {
    var restoration = transcript(method: .visibility)
    restoration[4] = observation(
      method: .visibility,
      phase: .visibilityRestored,
      nonce: 42,
      repeatIndex: 0,
      candidateLuminance: 99
    )
    #expect(
      run(method: .visibility, observations: restoration)
        == .rejected(.restorationFailed)
    )

    var otherChanged = transcript(method: .pixelNonce)
    otherChanged[2] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 0,
      otherLuminance: 99
    )
    #expect(
      run(method: .pixelNonce, observations: otherChanged)
        == .rejected(.otherWindowChanged)
    )
  }

  @Test func wrongResponderAndUnstableRepeatsAreRejected() {
    var noCandidateResponse = transcript(method: .visibility)
    noCandidateResponse[2] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 41,
      repeatIndex: 0,
      candidateOnScreen: true,
      candidateLuminance: 100
    )
    #expect(
      run(method: .visibility, observations: noCandidateResponse)
        == .rejected(.candidateDidNotRespond)
    )

    var unstable = transcript(method: .pixelNonce)
    unstable[3] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 1,
      candidateLuminance: 5
    )
    #expect(
      run(method: .pixelNonce, observations: unstable)
        == .rejected(.phaseEvidenceNotRepeatStable)
    )
  }

  @Test func noncePhaseAndCommandReplyOrderAreRejected() {
    var wrongNonce = transcript(method: .visibility)
    wrongNonce[2] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 42,
      repeatIndex: 0
    )
    #expect(run(method: .visibility, observations: wrongNonce) == .rejected(.nonceOutOfOrder))

    var wrongPhase = transcript(method: .visibility)
    wrongPhase[2] = observation(
      method: .visibility,
      phase: .visibilityRestored,
      nonce: 41,
      repeatIndex: 0
    )
    #expect(run(method: .visibility, observations: wrongPhase) == .rejected(.phaseOutOfOrder))

    var oldReply = transcript(method: .visibility)
    oldReply[2] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 41,
      repeatIndex: 0,
      commandReplyTime: 100,
      evidenceObservedTime: 130
    )
    #expect(
      run(method: .visibility, observations: oldReply)
        == .rejected(.commandReplyTimeNotIncreasing)
    )
  }

  @Test func firstFailureIsLatchedUntilReset() {
    var policy = ManagedSlideShowRoleChallengePolicy()
    #expect(policy.begin(target: target(), method: .visibility) == .started)
    let wrong = observation(session: "wrong", method: .visibility)
    #expect(policy.ingest(wrong) == .rejected(.sessionMismatch))
    #expect(policy.ingest(observation(method: .visibility)) == .rejected(.sessionMismatch))
    #expect(policy.finish() == .rejected(.sessionMismatch))
    #expect(
      policy.begin(target: target(), method: .pixelNonce) == .rejected(.sessionMismatch)
    )

    policy.reset()
    #expect(policy.begin(target: target(), method: .pixelNonce) == .started)
  }

  @Test func completeFreshInventoryAndRealCandidateFrameTimesAreRequired() {
    var incomplete = transcript(method: .visibility)
    incomplete[0] = observation(method: .visibility, inventoryIsComplete: false)
    #expect(
      run(method: .visibility, observations: incomplete) == .rejected(.incompleteInventory)
    )

    var inventedHiddenFrame = transcript(method: .visibility)
    inventedHiddenFrame[2] = observation(
      method: .visibility,
      phase: .visibilityHidden,
      nonce: 41,
      repeatIndex: 0,
      candidateDisplayTime: 130,
      candidateAbsent: true
    )
    #expect(
      run(method: .visibility, observations: inventedHiddenFrame)
        == .rejected(.unexpectedCandidateDisplayTime)
    )

    var staleOtherWindow = transcript(method: .pixelNonce)
    staleOtherWindow[2] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 0,
      otherDisplayTime: 100
    )
    #expect(
      run(method: .pixelNonce, observations: staleOtherWindow)
        == .rejected(.windowEvidenceStale)
    )

    var staleCandidateFrame = transcript(method: .pixelNonce)
    staleCandidateFrame[2] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 0,
      candidateDisplayTime: 100
    )
    #expect(
      run(method: .pixelNonce, observations: staleCandidateFrame)
        == .rejected(.staleCandidateDisplayTime)
    )

    var repeatedCandidateFrame = transcript(method: .visibility)
    repeatedCandidateFrame[1] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 1,
      candidateDisplayTime: 110
    )
    #expect(
      run(method: .visibility, observations: repeatedCandidateFrame)
        == .rejected(.candidateDisplayTimeNotIncreasing)
    )

    var repeatedWindowTime = transcript(method: .visibility)
    repeatedWindowTime[1] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 1,
      otherDisplayTime: 110
    )
    #expect(
      run(method: .visibility, observations: repeatedWindowTime)
        == .rejected(.windowDisplayTimeNotIncreasing)
    )
  }

  @Test func unchangedWindowsMayUseSameDisplayTimeOnFreshContinuousIdleCallbacks() {
    var evidence = transcript(method: .pixelNonce)
    for index in evidence.indices where index > 0 {
      evidence[index] = observation(
        method: .pixelNonce,
        phase: evidence[index].phase,
        nonce: evidence[index].nonce,
        repeatIndex: index.isMultiple(of: 2) ? 0 : 1,
        otherDisplayTime: 110,
        otherDeliveryStatus: .idle
      )
    }

    #expect(
      run(method: .pixelNonce, observations: evidence)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
    )
  }

  @Test func anchoredBaselineIdleAndMutationSecondIdleAreAccepted() {
    var baselineIdle = transcript(method: .visibility)
    baselineIdle[0] = observation(
      method: .visibility,
      candidateDisplayTime: 80,
      candidateDeliveryStatus: .idle
    )
    #expect(
      run(method: .visibility, observations: baselineIdle)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 320)
    )

    var mutationRepeatIdle = transcript(method: .pixelNonce)
    mutationRepeatIdle[3] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 1,
      candidateDisplayTime: 210,
      candidateDeliveryStatus: .idle
    )
    #expect(
      run(method: .pixelNonce, observations: mutationRepeatIdle)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
    )
  }

  @Test func firstCandidateDeliveryAfterMutationMustBeGenerated() {
    var evidence = transcript(method: .pixelNonce)
    evidence[2] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 0,
      candidateDisplayTime: 120,
      candidateDeliveryStatus: .idle
    )

    #expect(
      run(method: .pixelNonce, observations: evidence)
        == .rejected(.candidateMutationRequiresGeneratedPayload)
    )
  }

  @Test func deliveryGapTokenDriftAndNonIncreasingCallbackFailClosed() {
    var sequenceGap = transcript(method: .visibility)
    sequenceGap[1] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 1,
      candidateDisplayTime: 110,
      otherDisplayTime: 110,
      deliverySequence: 1,
      candidateDeliveryStatus: .idle,
      otherDeliveryStatus: .idle
    )
    #expect(
      run(method: .visibility, observations: sequenceGap)
        == .rejected(.windowDeliverySequenceNotIncreasing)
    )

    var streamDrift = transcript(method: .visibility)
    streamDrift[1] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 1,
      candidateDisplayTime: 110,
      otherDisplayTime: 110,
      candidateDeliveryStatus: .idle,
      otherDeliveryStatus: .idle,
      candidateStreamMemberToken: "drifted-candidate-member"
    )
    #expect(
      run(method: .visibility, observations: streamDrift)
        == .rejected(.windowStreamMemberMismatch)
    )

    var continuityDrift = transcript(method: .visibility)
    continuityDrift[1] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 1,
      candidateDisplayTime: 110,
      otherDisplayTime: 110,
      candidateDeliveryStatus: .idle,
      otherDeliveryStatus: .idle,
      candidateContinuityToken: "other-continuity"
    )
    #expect(
      run(method: .visibility, observations: continuityDrift)
        == .rejected(.windowContinuityMismatch)
    )

    var callbackNotIncreasing = transcript(method: .visibility)
    callbackNotIncreasing[1] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 1,
      candidateDisplayTime: 110,
      otherDisplayTime: 110,
      callbackMachAbsoluteTime: 110,
      candidateDeliveryStatus: .idle,
      otherDeliveryStatus: .idle
    )
    #expect(
      run(method: .visibility, observations: callbackNotIncreasing)
        == .rejected(.windowCallbackTimeNotIncreasing)
    )
  }

  @Test func unavailableMissingAndPartialDeliveryProvenanceFailClosed() {
    for status in [
      ManagedSlideShowRoleWindowDeliveryStatus.blank,
      .suspended,
      .stopped,
    ] {
      var unavailable = transcript(method: .visibility)
      unavailable[0] = observation(
        method: .visibility,
        candidateDeliveryStatus: status
      )
      #expect(
        run(method: .visibility, observations: unavailable)
          == .rejected(.unsupportedWindowDeliveryStatus)
      )
    }

    var missing = transcript(method: .visibility)
    missing[0] = observation(
      method: .visibility,
      omitCandidateDeliveryProvenance: true
    )
    #expect(
      run(method: .visibility, observations: missing)
        == .rejected(.windowDeliveryProvenanceMalformed)
    )

    var partial = transcript(method: .visibility)
    partial[0] = observation(
      method: .visibility,
      candidateContinuityToken: nil
    )
    #expect(
      run(method: .visibility, observations: partial)
        == .rejected(.windowDeliveryProvenanceMalformed)
    )
  }

  private func run(
    method: ManagedSlideShowRoleChallengeMethod,
    observations: [ManagedSlideShowRoleChallengeObservation]
  ) -> ManagedSlideShowRoleChallengeEvent {
    var policy = ManagedSlideShowRoleChallengePolicy()
    #expect(policy.begin(target: target(), method: method) == .started)
    for evidence in observations {
      let event = policy.ingest(evidence)
      if case .rejected = event { return event }
    }
    return policy.finish()
  }

  private func transcript(
    method: ManagedSlideShowRoleChallengeMethod,
    challengeNonce: UInt64 = 40
  ) -> [ManagedSlideShowRoleChallengeObservation] {
    let phases: [ManagedSlideShowRoleChallengePhase] =
      method == .visibility
      ? [.baseline, .visibilityHidden, .visibilityRestored]
      : challengeNonce.isMultiple(of: 2)
        ? [.baseline, .pixelBlack, .pixelWhite, .pixelRunningRestored]
        : [.baseline, .pixelWhite, .pixelBlack, .pixelRunningRestored]
    return phases.enumerated().flatMap { phaseIndex, phase in
      [0, 1].map {
        observation(
          method: method,
          phase: phase,
          nonce: challengeNonce + UInt64(phaseIndex),
          repeatIndex: $0,
          commandReplyTime: UInt64((phaseIndex + 1) * 100)
        )
      }
    }
  }

  private func target(challengeNonce: UInt64 = 40) -> ManagedSlideShowRoleChallengeTarget {
    ManagedSlideShowRoleChallengeTarget(
      bindingSessionToken: "session",
      slideShowObjectToken: "object",
      processIdentifier: 700,
      bundleIdentifier: "com.microsoft.Powerpoint",
      candidateWindowIdentity: identity(20),
      captureOperationID: 7,
      captureGeneration: 9,
      candidateStreamMemberToken: "candidate-member",
      candidateContinuityToken: "candidate-continuity",
      minimumCandidateDeliverySequenceExclusive: 79,
      challengeNonce: challengeNonce
    )
  }

  private func observation(
    session: String = "session",
    objectToken: String = "object",
    processIdentifier: Int = 700,
    bundleIdentifier: String = "com.microsoft.Powerpoint",
    candidateWindowID: Int = 20,
    captureOperationID: UInt64 = 7,
    captureGeneration: UInt64 = 9,
    method: ManagedSlideShowRoleChallengeMethod,
    phase: ManagedSlideShowRoleChallengePhase = .baseline,
    nonce: UInt64 = 40,
    repeatIndex: Int = 0,
    commandReplyTime: UInt64? = nil,
    evidenceObservedTime: UInt64? = nil,
    candidateDisplayTime: UInt64? = nil,
    candidateOnScreen: Bool? = nil,
    candidateLuminance: UInt8? = nil,
    candidateAbsent: Bool = false,
    otherLuminance: UInt8 = 80,
    otherDisplayTime: UInt64? = nil,
    presentationSaved: Bool = true,
    inventoryIsComplete: Bool = true,
    deliverySequence: UInt64? = nil,
    callbackMachAbsoluteTime: UInt64? = nil,
    candidateDeliveryStatus: ManagedSlideShowRoleWindowDeliveryStatus = .generated,
    otherDeliveryStatus: ManagedSlideShowRoleWindowDeliveryStatus = .generated,
    candidateStreamMemberToken: String? = "candidate-member",
    candidateContinuityToken: String? = "candidate-continuity",
    omitCandidateDeliveryProvenance: Bool = false
  ) -> ManagedSlideShowRoleChallengeObservation {
    let phaseIndex = nonce - 40
    let reply = commandReplyTime ?? (phaseIndex + 1) * 100
    let observed = evidenceObservedTime ?? reply + UInt64((repeatIndex + 1) * 10)
    let defaults = phaseDefaults(method: method, phase: phase)
    let candidateIsOnScreen = candidateOnScreen ?? defaults.onScreen
    let resolvedCandidateDisplayTime =
      candidateDisplayTime ?? (candidateAbsent || !candidateIsOnScreen ? nil : observed)
    let candidate = ManagedSlideShowRoleWindowEvidence(
      identity: identity(candidateWindowID),
      fingerprint: candidateIsOnScreen
        ? fingerprint(candidateLuminance ?? defaults.luminance) : nil,
      isOnScreen: candidateIsOnScreen,
      displayTime: candidateIsOnScreen ? resolvedCandidateDisplayTime : nil,
      deliveryProvenance: !candidateIsOnScreen || omitCandidateDeliveryProvenance
        ? nil
        : provenance(
          status: candidateDeliveryStatus,
          streamMemberToken: candidateStreamMemberToken,
          continuityToken: candidateContinuityToken,
          sequence: deliverySequence ?? UInt64(nonce * 2) + UInt64(repeatIndex),
          callbackTime: callbackMachAbsoluteTime ?? observed
        )
    )
    return ManagedSlideShowRoleChallengeObservation(
      bindingSessionToken: session,
      slideShowObjectToken: objectToken,
      processIdentifier: processIdentifier,
      bundleIdentifier: bundleIdentifier,
      candidateWindowIdentity: identity(candidateWindowID),
      captureOperationID: captureOperationID,
      captureGeneration: captureGeneration,
      phase: phase,
      nonce: nonce,
      commandReplyMachAbsoluteTime: reply,
      evidenceObservedMachAbsoluteTime: observed,
      candidateDisplayTime: resolvedCandidateDisplayTime,
      inventoryIsComplete: inventoryIsComplete,
      semanticState: ManagedSlideShowRoleSemanticState(
        slideID: 50,
        slideIndex: 3,
        currentViewState: defaults.state,
        presentationSaved: presentationSaved
      ),
      windows: [
        ManagedSlideShowRoleWindowEvidence(
          identity: identity(10),
          fingerprint: fingerprint(otherLuminance),
          isOnScreen: true,
          displayTime: otherDisplayTime ?? observed,
          deliveryProvenance: provenance(
            status: otherDeliveryStatus,
            streamMemberToken: "other-member",
            continuityToken: "other-continuity",
            sequence: deliverySequence ?? UInt64(nonce * 2) + UInt64(repeatIndex),
            callbackTime: callbackMachAbsoluteTime ?? observed
          )
        )
      ] + (candidateAbsent ? [] : [candidate])
    )
  }

  private func phaseDefaults(
    method: ManagedSlideShowRoleChallengeMethod,
    phase: ManagedSlideShowRoleChallengePhase
  ) -> (
    luminance: UInt8,
    onScreen: Bool,
    state: ManagedSlideShowRoleCurrentViewState
  ) {
    switch (method, phase) {
    case (.visibility, .visibilityHidden): (100, false, .running)
    case (.pixelNonce, .pixelBlack): (0, true, .blackScreen)
    case (.pixelNonce, .pixelWhite): (255, true, .whiteScreen)
    case (.pixelNonce, .baseline), (.pixelNonce, .pixelRunningRestored):
      (100, true, .running)
    default: (100, true, .running)
    }
  }

  private func fingerprint(_ luminance: UInt8) -> FrameFingerprint {
    FrameFingerprint(
      sampleColumns: 2, sampleRows: 2, luminance: Array(repeating: luminance, count: 4))
  }

  private func provenance(
    status: ManagedSlideShowRoleWindowDeliveryStatus,
    streamMemberToken: String?,
    continuityToken: String?,
    sequence: UInt64,
    callbackTime: UInt64
  ) -> ManagedSlideShowRoleWindowDeliveryProvenance {
    ManagedSlideShowRoleWindowDeliveryProvenance(
      status: status,
      captureOperationID: 7,
      captureGeneration: 9,
      streamMemberToken: streamMemberToken,
      continuityToken: continuityToken,
      deliverySequence: sequence,
      callbackMachAbsoluteTime: callbackTime
    )
  }

  private func identity(_ windowID: Int) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: 700,
      bundleIdentifier: "com.microsoft.Powerpoint"
    )
  }
}
