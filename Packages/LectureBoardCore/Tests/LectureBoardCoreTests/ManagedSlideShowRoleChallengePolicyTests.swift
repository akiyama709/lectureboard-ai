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

  @Test func exactGeometryAllowsOnlyAConsistentlyMirroredAuxiliary() {
    let geometry = ManagedSlideShowWindowGeometry(left: 100, top: 340, width: 1_600, height: 900)
    let auxiliaryGeometry = ManagedSlideShowWindowGeometry(
      left: 100, top: 340, width: 66, height: 20)
    let phases: [(ManagedSlideShowRoleChallengePhase, UInt64, UInt8)] = [
      (.baseline, 40, 0),
      (.pixelBlack, 41, 0),
      (.pixelWhite, 42, 255),
      (.pixelRunningRestored, 43, 0),
    ]
    let evidence = phases.flatMap { phase, nonce, auxiliaryLuminance in
      [0, 1].map {
        observation(
          method: .pixelNonce,
          phase: phase,
          nonce: nonce,
          repeatIndex: $0,
          commandReplyTime: UInt64(Int(nonce - 39) * 100),
          candidateLuminance: phase == .pixelRunningRestored ? 100 : nil,
          otherLuminance: auxiliaryLuminance,
          semanticGeometry: geometry,
          candidateGeometry: geometry,
          otherGeometry: auxiliaryGeometry
        )
      }
    }
    #expect(
      run(method: .pixelNonce, observations: evidence)
        == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
    )

    let legacyEvidence = phases.flatMap { phase, nonce, auxiliaryLuminance in
      [0, 1].map {
        observation(
          method: .pixelNonce,
          phase: phase,
          nonce: nonce,
          repeatIndex: $0,
          commandReplyTime: UInt64(Int(nonce - 39) * 100),
          candidateLuminance: phase == .pixelRunningRestored ? 100 : nil,
          otherLuminance: auxiliaryLuminance
        )
      }
    }
    #expect(
      run(method: .pixelNonce, observations: legacyEvidence)
        == .rejected(.otherWindowChanged)
    )
  }

  @Test func geometryMustBeCompleteUniqueCandidateBoundAndStable() {
    let geometry = ManagedSlideShowWindowGeometry(left: 100, top: 340, width: 1_600, height: 900)
    let auxiliaryGeometry = ManagedSlideShowWindowGeometry(left: 10, top: 20, width: 66, height: 20)
    let invalidGeometry = ManagedSlideShowWindowGeometry(left: 100, top: 340, width: 0, height: 900)

    let cases:
      [([ManagedSlideShowRoleChallengeObservation], ManagedSlideShowRoleChallengeRejection)] = [
        ([observation(method: .pixelNonce, semanticGeometry: geometry)], .windowGeometryMalformed),
        (
          [
            observation(
              method: .pixelNonce,
              semanticGeometry: invalidGeometry,
              candidateGeometry: invalidGeometry,
              otherGeometry: auxiliaryGeometry)
          ], .windowGeometryMalformed
        ),
        (
          [
            observation(
              method: .pixelNonce,
              semanticGeometry: geometry,
              candidateGeometry: auxiliaryGeometry,
              otherGeometry: geometry)
          ], .candidateGeometryMismatch
        ),
        (
          [
            observation(
              method: .pixelNonce,
              semanticGeometry: geometry,
              candidateGeometry: geometry,
              otherGeometry: geometry)
          ], .candidateGeometryMismatch
        ),
      ]
    for (evidence, expected) in cases {
      #expect(run(method: .pixelNonce, observations: evidence) == .rejected(expected))
    }

    var drift = transcript(
      method: .pixelNonce,
      semanticGeometry: geometry,
      candidateGeometry: geometry,
      otherGeometry: auxiliaryGeometry
    )
    drift[2] = observation(
      method: .pixelNonce,
      phase: .pixelBlack,
      nonce: 41,
      repeatIndex: 0,
      semanticGeometry: geometry,
      candidateGeometry: ManagedSlideShowWindowGeometry(
        left: 101, top: 340, width: 1_600, height: 900),
      otherGeometry: auxiliaryGeometry
    )
    #expect(run(method: .pixelNonce, observations: drift) == .rejected(.windowGeometryChanged))
  }

  @Test func mirroredAuxiliaryMustMatchBothTonesAndRestoreItsOwnBaseline() {
    let geometry = ManagedSlideShowWindowGeometry(left: 100, top: 340, width: 1_600, height: 900)
    let auxiliaryGeometry = ManagedSlideShowWindowGeometry(left: 10, top: 20, width: 66, height: 20)
    var wrongWhite = transcript(
      method: .pixelNonce,
      semanticGeometry: geometry,
      candidateGeometry: geometry,
      otherGeometry: auxiliaryGeometry,
      mirroredOther: true
    )
    wrongWhite[4] = observation(
      method: .pixelNonce,
      phase: .pixelWhite,
      nonce: 42,
      repeatIndex: 0,
      otherLuminance: 80,
      semanticGeometry: geometry,
      candidateGeometry: geometry,
      otherGeometry: auxiliaryGeometry
    )
    #expect(run(method: .pixelNonce, observations: wrongWhite) == .rejected(.otherWindowChanged))

    var notRestored = transcript(
      method: .pixelNonce,
      semanticGeometry: geometry,
      candidateGeometry: geometry,
      otherGeometry: auxiliaryGeometry,
      mirroredOther: true
    )
    notRestored[6] = observation(
      method: .pixelNonce,
      phase: .pixelRunningRestored,
      nonce: 43,
      repeatIndex: 0,
      otherLuminance: 0,
      semanticGeometry: geometry,
      candidateGeometry: geometry,
      otherGeometry: auxiliaryGeometry
    )
    #expect(run(method: .pixelNonce, observations: notRestored) == .rejected(.restorationFailed))
  }

  @Test func geometryPixelNonceUsesPairedCausalSignatureInBothNonceOrders() {
    for nonce in [UInt64(40), 41] {
      #expect(
        run(
          method: .pixelNonce,
          observations: causalGeometryTranscript(challengeNonce: nonce),
          challengeNonce: nonce
        )
          == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
      )
    }

    let legacy = causalGeometryTranscript(challengeNonce: 40, includesGeometry: false)
    #expect(run(method: .pixelNonce, observations: legacy) == .rejected(.otherWindowChanged))
  }

  @Test func geometryPixelNonceAcceptsOneStrongEndpointWithBroadForwardResponse() {
    let strongBlack =
      Array(repeating: UInt8(0), count: 60)
      + Array(repeating: UInt8(100), count: 40)
    let letterboxedWhite =
      Array(repeating: UInt8(255), count: 40)
      + Array(repeating: UInt8(200), count: 20)
      + Array(repeating: UInt8(100), count: 40)

    for nonce in [UInt64(40), 41] {
      var evidence = causalGeometryTranscript(challengeNonce: nonce)
      replacePhaseFingerprint(&evidence, phase: .pixelBlack, luminance: strongBlack)
      replacePhaseFingerprint(&evidence, phase: .pixelWhite, luminance: letterboxedWhite)
      replacePhaseFingerprint(
        &evidence,
        phase: .pixelBlack,
        luminance: strongBlack,
        windowID: 10
      )
      replacePhaseFingerprint(
        &evidence,
        phase: .pixelWhite,
        luminance: letterboxedWhite,
        windowID: 10
      )
      #expect(
        run(method: .pixelNonce, observations: evidence, challengeNonce: nonce)
          == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
      )
    }
  }

  @Test func geometryPixelNonceAcceptsStrongAntialiasedMirrorsWithBroadForwardResponse() {
    let strongBlack =
      Array(repeating: UInt8(0), count: 94)
      + Array(repeating: UInt8(100), count: 6)
    let shiftedAntialiasedWhite =
      Array(repeating: UInt8(32), count: 4)
      + Array(repeating: UInt8(255), count: 96)

    for nonce in [UInt64(40), 41] {
      var evidence = causalGeometryTranscript(challengeNonce: nonce)
      for windowID in [20, 10] {
        replacePhaseFingerprint(
          &evidence,
          phase: .pixelBlack,
          luminance: strongBlack,
          windowID: windowID
        )
        replacePhaseFingerprint(
          &evidence,
          phase: .pixelWhite,
          luminance: shiftedAntialiasedWhite,
          windowID: windowID
        )
      }
      #expect(
        run(method: .pixelNonce, observations: evidence, challengeNonce: nonce)
          == .succeeded(freshnessBoundaryMachAbsoluteTime: 420)
      )
    }
  }

  @Test func geometryPixelNonceRejectsWeakOrIncoherentAsymmetricEndpoint() {
    let strongBlack =
      Array(repeating: UInt8(0), count: 60)
      + Array(repeating: UInt8(100), count: 40)
    let tooLittleWhite =
      Array(repeating: UInt8(255), count: 24)
      + Array(repeating: UInt8(200), count: 36)
      + Array(repeating: UInt8(100), count: 40)
    let incoherentBlack =
      Array(repeating: UInt8(0), count: 58)
      + Array(repeating: UInt8(255), count: 2)
      + Array(repeating: UInt8(100), count: 40)
    let incoherentWhite =
      Array(repeating: UInt8(255), count: 40)
      + Array(repeating: UInt8(200), count: 18)
      + Array(repeating: UInt8(0), count: 2)
      + Array(repeating: UInt8(100), count: 40)

    var weakCandidate = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(&weakCandidate, phase: .pixelBlack, luminance: strongBlack)
    replacePhaseFingerprint(&weakCandidate, phase: .pixelWhite, luminance: tooLittleWhite)
    #expect(
      run(method: .pixelNonce, observations: weakCandidate)
        == .rejected(.wrongVisualSignature)
    )

    var incoherentCandidate = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(&incoherentCandidate, phase: .pixelBlack, luminance: incoherentBlack)
    replacePhaseFingerprint(&incoherentCandidate, phase: .pixelWhite, luminance: incoherentWhite)
    #expect(
      run(method: .pixelNonce, observations: incoherentCandidate)
        == .rejected(.wrongVisualSignature)
    )

    var weakAuxiliary = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(
      &weakAuxiliary,
      phase: .pixelBlack,
      luminance: strongBlack,
      windowID: 10
    )
    replacePhaseFingerprint(
      &weakAuxiliary,
      phase: .pixelWhite,
      luminance: tooLittleWhite,
      windowID: 10
    )
    #expect(
      run(method: .pixelNonce, observations: weakAuxiliary)
        == .rejected(.otherWindowChanged)
    )

    var incoherentAuxiliary = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(
      &incoherentAuxiliary,
      phase: .pixelBlack,
      luminance: incoherentBlack,
      windowID: 10
    )
    replacePhaseFingerprint(
      &incoherentAuxiliary,
      phase: .pixelWhite,
      luminance: incoherentWhite,
      windowID: 10
    )
    #expect(
      run(method: .pixelNonce, observations: incoherentAuxiliary)
        == .rejected(.otherWindowChanged)
    )
  }

  @Test func geometryPixelNonceRejectsStrongButReversedMirrors() {
    let strongBlack =
      Array(repeating: UInt8(0), count: 94)
      + Array(repeating: UInt8(100), count: 6)
    let partlyReversedWhite =
      Array(repeating: UInt8(32), count: 4)
      + Array(repeating: UInt8(255), count: 93)
      + Array(repeating: UInt8(0), count: 3)

    for nonce in [UInt64(40), 41] {
      var candidate = causalGeometryTranscript(challengeNonce: nonce)
      replacePhaseFingerprint(&candidate, phase: .pixelBlack, luminance: strongBlack)
      replacePhaseFingerprint(&candidate, phase: .pixelWhite, luminance: partlyReversedWhite)
      #expect(
        run(method: .pixelNonce, observations: candidate, challengeNonce: nonce)
          == .rejected(.wrongVisualSignature)
      )

      var auxiliary = causalGeometryTranscript(challengeNonce: nonce)
      replacePhaseFingerprint(
        &auxiliary,
        phase: .pixelBlack,
        luminance: strongBlack,
        windowID: 10
      )
      replacePhaseFingerprint(
        &auxiliary,
        phase: .pixelWhite,
        luminance: partlyReversedWhite,
        windowID: 10
      )
      #expect(
        run(method: .pixelNonce, observations: auxiliary, challengeNonce: nonce)
          == .rejected(.otherWindowChanged)
      )
    }
  }

  @Test func geometryPixelNonceRejectsSmallInconsistentReversedAndUnrestoredChanges() {
    let smallBlack =
      Array(repeating: UInt8(0), count: 24)
      + Array(repeating: UInt8(100), count: 76)
    let inconsistentWhite =
      Array(repeating: UInt8(255), count: 58)
      + Array(repeating: UInt8(200), count: 2)
      + Array(repeating: UInt8(100), count: 40)
    let reversedBlack =
      Array(repeating: UInt8(255), count: 60)
      + Array(repeating: UInt8(100), count: 40)
    let narrowChangeBlack =
      Array(repeating: UInt8(0), count: 75)
      + Array(repeating: UInt8(255), count: 25)
    let narrowChangeWhite =
      Array(repeating: UInt8(255), count: 49)
      + Array(repeating: UInt8(0), count: 26)
      + Array(repeating: UInt8(255), count: 25)

    var small = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(&small, phase: .pixelBlack, luminance: smallBlack)
    #expect(run(method: .pixelNonce, observations: small) == .rejected(.wrongVisualSignature))

    var inconsistent = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(&inconsistent, phase: .pixelWhite, luminance: inconsistentWhite)
    #expect(
      run(method: .pixelNonce, observations: inconsistent) == .rejected(.wrongVisualSignature)
    )

    var reversed = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(&reversed, phase: .pixelBlack, luminance: reversedBlack)
    #expect(run(method: .pixelNonce, observations: reversed) == .rejected(.wrongVisualSignature))

    var narrowChange = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(&narrowChange, phase: .pixelBlack, luminance: narrowChangeBlack)
    replacePhaseFingerprint(&narrowChange, phase: .pixelWhite, luminance: narrowChangeWhite)
    #expect(
      run(method: .pixelNonce, observations: narrowChange) == .rejected(.wrongVisualSignature)
    )

    var inconsistentAuxiliary = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(
      &inconsistentAuxiliary,
      phase: .pixelWhite,
      luminance: inconsistentWhite,
      windowID: 10
    )
    #expect(
      run(method: .pixelNonce, observations: inconsistentAuxiliary)
        == .rejected(.otherWindowChanged)
    )

    var unrestored = causalGeometryTranscript(challengeNonce: 40)
    replacePhaseFingerprint(
      &unrestored,
      phase: .pixelRunningRestored,
      luminance: Array(repeating: 99, count: 100)
    )
    #expect(run(method: .pixelNonce, observations: unrestored) == .rejected(.restorationFailed))

    let partial = Array(causalGeometryTranscript(challengeNonce: 40).dropLast())
    #expect(run(method: .pixelNonce, observations: partial) == .rejected(.incompleteChallenge))
  }

  private func run(
    method: ManagedSlideShowRoleChallengeMethod,
    observations: [ManagedSlideShowRoleChallengeObservation],
    challengeNonce: UInt64 = 40
  ) -> ManagedSlideShowRoleChallengeEvent {
    var policy = ManagedSlideShowRoleChallengePolicy()
    #expect(
      policy.begin(target: target(challengeNonce: challengeNonce), method: method) == .started
    )
    for evidence in observations {
      let event = policy.ingest(evidence)
      if case .rejected = event { return event }
    }
    return policy.finish()
  }

  private func transcript(
    method: ManagedSlideShowRoleChallengeMethod,
    challengeNonce: UInt64 = 40,
    semanticGeometry: ManagedSlideShowWindowGeometry? = nil,
    candidateGeometry: ManagedSlideShowWindowGeometry? = nil,
    otherGeometry: ManagedSlideShowWindowGeometry? = nil,
    mirroredOther: Bool = false
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
          commandReplyTime: UInt64((phaseIndex + 1) * 100),
          otherLuminance: mirroredOther
            ? (phase == .pixelBlack ? 0 : phase == .pixelWhite ? 255 : 80)
            : 80,
          semanticGeometry: semanticGeometry,
          candidateGeometry: candidateGeometry,
          otherGeometry: otherGeometry
        )
      }
    }
  }

  private func causalGeometryTranscript(
    challengeNonce: UInt64,
    includesGeometry: Bool = true
  ) -> [ManagedSlideShowRoleChallengeObservation] {
    let geometry = ManagedSlideShowWindowGeometry(left: 100, top: 340, width: 1_600, height: 900)
    let auxiliaryGeometry = ManagedSlideShowWindowGeometry(left: 10, top: 20, width: 66, height: 20)
    let baseline = Array(repeating: UInt8(100), count: 100)
    let black =
      Array(repeating: UInt8(0), count: 60)
      + Array(repeating: UInt8(100), count: 40)
    let white =
      Array(repeating: UInt8(255), count: 60)
      + Array(repeating: UInt8(100), count: 40)
    let phases: [ManagedSlideShowRoleChallengePhase] =
      challengeNonce.isMultiple(of: 2)
      ? [.baseline, .pixelBlack, .pixelWhite, .pixelRunningRestored]
      : [.baseline, .pixelWhite, .pixelBlack, .pixelRunningRestored]
    return phases.enumerated().flatMap { phaseIndex, phase in
      let luminance = phase == .pixelBlack ? black : phase == .pixelWhite ? white : baseline
      return [0, 1].map {
        observation(
          method: .pixelNonce,
          phase: phase,
          nonce: challengeNonce + UInt64(phaseIndex),
          repeatIndex: $0,
          commandReplyTime: UInt64((phaseIndex + 1) * 100),
          candidateFingerprint: luminance,
          otherFingerprint: luminance,
          semanticGeometry: includesGeometry ? geometry : nil,
          candidateGeometry: includesGeometry ? geometry : nil,
          otherGeometry: includesGeometry ? auxiliaryGeometry : nil
        )
      }
    }
  }

  private func replacePhaseFingerprint(
    _ evidence: inout [ManagedSlideShowRoleChallengeObservation],
    phase: ManagedSlideShowRoleChallengePhase,
    luminance: [UInt8],
    windowID: Int = 20
  ) {
    for index in evidence.indices where evidence[index].phase == phase {
      let prior = evidence[index]
      evidence[index] = observation(
        method: .pixelNonce,
        phase: prior.phase,
        nonce: prior.nonce,
        repeatIndex: index.isMultiple(of: 2) ? 0 : 1,
        commandReplyTime: prior.commandReplyMachAbsoluteTime,
        candidateFingerprint: windowID == 20
          ? luminance
          : prior.windows.first(where: { $0.identity.windowID == 20 })?.fingerprint?.luminance,
        otherFingerprint: windowID == 10
          ? luminance
          : prior.windows.first(where: { $0.identity.windowID == 10 })?.fingerprint?.luminance,
        semanticGeometry: prior.semanticState.windowGeometry,
        candidateGeometry: prior.windows.first(where: { $0.identity.windowID == 20 })?
          .windowGeometry,
        otherGeometry: prior.windows.first(where: { $0.identity.windowID == 10 })?.windowGeometry
      )
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
    candidateFingerprint: [UInt8]? = nil,
    candidateAbsent: Bool = false,
    otherLuminance: UInt8 = 80,
    otherFingerprint: [UInt8]? = nil,
    otherDisplayTime: UInt64? = nil,
    presentationSaved: Bool = true,
    inventoryIsComplete: Bool = true,
    deliverySequence: UInt64? = nil,
    callbackMachAbsoluteTime: UInt64? = nil,
    candidateDeliveryStatus: ManagedSlideShowRoleWindowDeliveryStatus = .generated,
    otherDeliveryStatus: ManagedSlideShowRoleWindowDeliveryStatus = .generated,
    candidateStreamMemberToken: String? = "candidate-member",
    candidateContinuityToken: String? = "candidate-continuity",
    omitCandidateDeliveryProvenance: Bool = false,
    semanticGeometry: ManagedSlideShowWindowGeometry? = nil,
    candidateGeometry: ManagedSlideShowWindowGeometry? = nil,
    otherGeometry: ManagedSlideShowWindowGeometry? = nil
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
        ? candidateFingerprint.map(fingerprint)
          ?? fingerprint(candidateLuminance ?? defaults.luminance)
        : nil,
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
        ),
      windowGeometry: candidateGeometry
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
        presentationSaved: presentationSaved,
        windowGeometry: semanticGeometry
      ),
      windows: [
        ManagedSlideShowRoleWindowEvidence(
          identity: identity(10),
          fingerprint: otherFingerprint.map(fingerprint) ?? fingerprint(otherLuminance),
          isOnScreen: true,
          displayTime: otherDisplayTime ?? observed,
          deliveryProvenance: provenance(
            status: otherDeliveryStatus,
            streamMemberToken: "other-member",
            continuityToken: "other-continuity",
            sequence: deliverySequence ?? UInt64(nonce * 2) + UInt64(repeatIndex),
            callbackTime: callbackMachAbsoluteTime ?? observed
          ),
          windowGeometry: otherGeometry
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

  private func fingerprint(_ luminance: [UInt8]) -> FrameFingerprint {
    FrameFingerprint(sampleColumns: 10, sampleRows: 10, luminance: luminance)
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
