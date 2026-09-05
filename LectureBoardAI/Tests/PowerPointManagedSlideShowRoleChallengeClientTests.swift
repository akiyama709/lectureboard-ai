import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

/// Fake-boundary tests only. These tests send no Apple Event, query no permission, request no
/// ScreenCaptureKit frame, and do not launch or control PowerPoint.
@MainActor
struct PowerPointManagedSlideShowRoleChallengeClientTests {
  private let operationID = CaptureOperationID(rawValue: 7)
  private let captureGeneration: UInt64 = 9
  private let challengeNonce: UInt64 = 40

  @Test func visibilityChallengeUsesExactObjectAndTwoFreshObservationsPerPhase() async throws {
    let object = ScriptedRoleObjectController()
    let evidence = ScriptedRoleEvidenceReader()
    let client = try makeClient(object: object, evidence: evidence)

    let result = try await client.runVisibilityChallenge(request())
    let observations = try #require(result.observations)

    #expect(
      observations.map(\.phase) == [
        .baseline, .baseline,
        .visibilityHidden, .visibilityHidden,
        .visibilityRestored, .visibilityRestored,
      ]
    )
    #expect(observations.map(\.nonce) == [40, 40, 41, 41, 42, 42])
    #expect(
      await object.calls == [
        .capability(.visibility),
        .command(.establishBaseline),
        .command(.setVisibility(false)),
        .command(.setVisibility(true)),
      ]
    )
    #expect(await evidence.requests.count == 6)
    #expect(Set(await object.freshRequestTokens).count == 4)
    #expect(Set(await evidence.freshRequestTokens).count == 6)
    #expect(
      await evidence.requests.allSatisfy {
        $0.bindingSessionToken == "session"
          && $0.slideShowObjectToken == "object"
          && $0.processIdentifier == 700
          && $0.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier
          && $0.candidateWindowIdentity == managedIdentity(windowID: 20)
          && $0.captureOperationID == operationID.rawValue
          && $0.captureGeneration == captureGeneration
      }
    )
  }

  @Test func unavailableVisibilityFallsBackOnceToEvenPixelNonceOrder() async throws {
    let object = ScriptedRoleObjectController(visibility: .unavailable)
    let evidence = ScriptedRoleEvidenceReader()
    let client = try makeClient(object: object, evidence: evidence)
    let challengeRequest = request()

    #expect(try await client.runVisibilityChallenge(challengeRequest) == .unavailable)
    let result = try await client.runPixelNonceChallenge(challengeRequest)
    let observations = try #require(result.observations)

    #expect(
      observations.map(\.phase) == [
        .baseline, .baseline,
        .pixelBlack, .pixelBlack,
        .pixelWhite, .pixelWhite,
        .pixelRunningRestored, .pixelRunningRestored,
      ]
    )
    #expect(
      await object.calls == [
        .capability(.visibility),
        .capability(.pixelNonce),
        .command(.establishBaseline),
        .command(.setViewState(.blackScreen)),
        .command(.setViewState(.whiteScreen)),
        .command(.setViewState(.running)),
      ]
    )
  }

  @Test func oddPixelNonceReversesOnlyTheBlackWhiteChallengeOrder() async throws {
    let object = ScriptedRoleObjectController(visibility: .unavailable)
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )
    let challengeRequest = request(challengeNonce: 41)

    #expect(try await client.runVisibilityChallenge(challengeRequest) == .unavailable)
    let result = try await client.runPixelNonceChallenge(challengeRequest)
    #expect(
      result.observations?.map(\.phase) == [
        .baseline, .baseline,
        .pixelWhite, .pixelWhite,
        .pixelBlack, .pixelBlack,
        .pixelRunningRestored, .pixelRunningRestored,
      ]
    )
    #expect(
      await object.calls == [
        .capability(.visibility),
        .capability(.pixelNonce),
        .command(.establishBaseline),
        .command(.setViewState(.whiteScreen)),
        .command(.setViewState(.blackScreen)),
        .command(.setViewState(.running)),
      ]
    )
  }

  @Test func unavailablePixelCapabilityStopsWithoutCommandsOrEvidence() async throws {
    let object = ScriptedRoleObjectController(
      visibility: .unavailable,
      pixelNonce: .unavailable
    )
    let evidence = ScriptedRoleEvidenceReader()
    let client = try makeClient(object: object, evidence: evidence)
    let challengeRequest = request()

    #expect(try await client.runVisibilityChallenge(challengeRequest) == .unavailable)
    #expect(try await client.runPixelNonceChallenge(challengeRequest) == .unavailable)
    #expect(
      await object.calls == [
        .capability(.visibility), .capability(.pixelNonce),
      ]
    )
    #expect(await evidence.requests.isEmpty)
  }

  @Test func pixelFallbackRequiresTheExactVisibilityRequest() async throws {
    let object = ScriptedRoleObjectController(visibility: .unavailable)
    let evidence = ScriptedRoleEvidenceReader()
    let client = try makeClient(object: object, evidence: evidence)
    let permitted = request()

    #expect(
      await capturedRoleClientFailure {
        try await client.runPixelNonceChallenge(permitted)
      } == .pixelFallbackNotAuthorized
    )
    #expect(try await client.runVisibilityChallenge(permitted) == .unavailable)
    #expect(
      await capturedRoleClientFailure {
        try await client.runPixelNonceChallenge(
          self.request(challengeNonce: self.challengeNonce + 1)
        )
      } == .pixelFallbackRequestMismatch
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runPixelNonceChallenge(permitted)
      } == .pixelFallbackNotAuthorized
    )
  }

  @Test func successfulChallengeCannotIssueAnySecondChallenge() async throws {
    let object = ScriptedRoleObjectController()
    let evidence = ScriptedRoleEvidenceReader()
    let client = try makeClient(object: object, evidence: evidence)
    let challengeRequest = request()

    _ = try await client.runVisibilityChallenge(challengeRequest)
    let callCount = await object.calls.count
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .challengeAlreadyConsumed
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runPixelNonceChallenge(challengeRequest)
      } == .pixelFallbackNotAuthorized
    )
    #expect(await object.calls.count == callCount)
  }

  @Test func capabilityFailureIsClosedAndDoesNotAuthorizePixelFallback() async throws {
    let object = ScriptedRoleObjectController(capabilityFailureAt: 0)
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )
    let challengeRequest = request()

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .capabilityCheckFailed
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .challengeAlreadyConsumed
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runPixelNonceChallenge(challengeRequest)
      } == .pixelFallbackNotAuthorized
    )
    #expect(await object.calls == [.capability(.visibility)])
  }

  @Test func capabilityReceiptMustEchoTheEntireFreshRequest() async throws {
    let object = ScriptedRoleObjectController(capabilityReceiptMismatchAt: 0)
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .capabilityReceiptMismatch
    )
    #expect(await object.calls == [.capability(.visibility)])
  }

  @Test(arguments: RoleRequestMismatch.allCases)
  fileprivate func requestProvenanceMismatchFailsBeforeAnyInjectedExternalBoundary(
    mismatch: RoleRequestMismatch
  ) async throws {
    let object = ScriptedRoleObjectController()
    let evidence = ScriptedRoleEvidenceReader()
    let expected = try candidate()
    let client = makeClient(
      expectedCandidate: expected,
      object: object,
      evidence: evidence
    )
    let badRequest = mismatchedRequest(mismatch, expectedCandidate: expected)

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(badRequest)
      } == mismatch.expectedFailure
    )
    #expect(await object.calls.isEmpty)
    #expect(await evidence.requests.isEmpty)
  }

  @Test(arguments: [UInt64(0), UInt64.max - 2, UInt64.max - 1, UInt64.max])
  func malformedNonceFailsBeforeAnyInjectedExternalBoundary(nonce: UInt64) async throws {
    let object = ScriptedRoleObjectController()
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request(challengeNonce: nonce))
      } == .malformedRequest
    )
    #expect(await object.calls.isEmpty)
  }

  @Test func malformedExpectedConfigurationFailsBeforeRequestValidationOrCalls() async throws {
    let expected = ManagedSlideShowRuntimeCandidate(
      candidateWindowIdentity: try #require(
        PowerPointWindowIdentity(
          windowID: 20,
          ownerProcessID: 700,
          bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
        )
      ),
      bindingSessionToken: " \n",
      slideShowObjectToken: "object"
    )
    let object = ScriptedRoleObjectController()
    let client = makeClient(
      expectedCandidate: expected,
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )
    let malformed = ManagedSlideShowRoleChallengeRequest(
      candidate: expected,
      captureOperationID: operationID,
      captureGeneration: captureGeneration,
      captureAnchor: captureAnchor(),
      challengeNonce: challengeNonce
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(malformed)
      } == .malformedConfiguration
    )
    #expect(await object.calls.isEmpty)
  }

  @Test func commandReceiptMismatchTriggersRestorationAfterMutationMayHaveOccurred() async throws {
    let object = ScriptedRoleObjectController(
      commandReceiptMismatchAt: 1,
      commandReplyTimes: [100, 190, 220]
    )
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .commandReceiptMismatch
    )
    #expect(
      await object.calls == [
        .capability(.visibility),
        .command(.establishBaseline),
        .command(.setVisibility(false)),
        .command(.setVisibility(true)),
      ]
    )
  }

  @Test func nonIncreasingCommandReplyTriggersRestorationAndKeepsOriginalFailure() async throws {
    let object = ScriptedRoleObjectController(commandReplyTimes: [100, 160, 220])
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .commandReplyTimeInvalid
    )
    #expect(
      await object.calls.suffix(2) == [
        .command(.setVisibility(false)), .command(.setVisibility(true)),
      ]
    )
  }

  @Test func commandReceiptCannotClaimATimeOutsideTheIndependentClockBracket() async throws {
    let object = ScriptedRoleObjectController(commandReplyTimes: [120])
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader()
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .commandReplyTimeInvalid
    )
    #expect(
      await object.calls == [
        .capability(.visibility), .command(.establishBaseline),
      ]
    )
  }

  @Test func nonIncreasingIndependentClockFailsClosedBeforeEvidence() async throws {
    let object = ScriptedRoleObjectController()
    let clock = ScriptedRoleMachClock(values: [90, 90])
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader(),
      machClock: clock
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .localClockInvalid
    )
    #expect(await object.calls.count == 2)
  }

  @Test func blankOrReusedCommandTokensFailClosed() async throws {
    let blankFactory = LockedRoleTokenSequence([" \n"])
    let blankObject = ScriptedRoleObjectController()
    let blankClient = try makeClient(
      object: blankObject,
      evidence: ScriptedRoleEvidenceReader(),
      commandTokens: blankFactory
    )
    #expect(
      await capturedRoleClientFailure {
        try await blankClient.runVisibilityChallenge(self.request())
      } == .freshCommandRequestTokenUnavailable
    )
    #expect(await blankObject.calls.isEmpty)

    let duplicateFactory = LockedRoleTokenSequence(["same", "same", "restored"])
    let duplicateObject = ScriptedRoleObjectController()
    let duplicateClient = try makeClient(
      object: duplicateObject,
      evidence: ScriptedRoleEvidenceReader(),
      commandTokens: duplicateFactory
    )
    #expect(
      await capturedRoleClientFailure {
        try await duplicateClient.runVisibilityChallenge(self.request())
      } == .freshCommandRequestTokenUnavailable
    )
    #expect(
      await duplicateObject.calls == [
        .capability(.visibility)
      ]
    )
  }

  @Test func blankOrReusedEvidenceTokensFailClosedAndRestoreIfNeeded() async throws {
    let blankFactory = LockedRoleTokenSequence([" \n"])
    let blankObject = ScriptedRoleObjectController()
    let blankClient = try makeClient(
      object: blankObject,
      evidence: ScriptedRoleEvidenceReader(),
      evidenceTokens: blankFactory
    )
    #expect(
      await capturedRoleClientFailure {
        try await blankClient.runVisibilityChallenge(self.request())
      } == .freshEvidenceRequestTokenUnavailable
    )
    #expect(
      await blankObject.calls == [
        .capability(.visibility), .command(.establishBaseline),
      ]
    )

    let duplicateFactory = LockedRoleTokenSequence(["same", "same"])
    let duplicateObject = ScriptedRoleObjectController()
    let duplicateClient = try makeClient(
      object: duplicateObject,
      evidence: ScriptedRoleEvidenceReader(),
      evidenceTokens: duplicateFactory
    )
    #expect(
      await capturedRoleClientFailure {
        try await duplicateClient.runVisibilityChallenge(self.request())
      } == .freshEvidenceRequestTokenUnavailable
    )
    #expect(await duplicateObject.calls.count == 2)
  }

  @Test(arguments: EvidenceProvenanceMutation.allCases)
  fileprivate func freshEvidenceMustEchoEveryProvenanceField(
    mutation: EvidenceProvenanceMutation
  ) async throws {
    let evidence = ScriptedRoleEvidenceReader(mutationAt: 0, mutation: mutation.mutation)
    let client = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: evidence
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .freshEvidenceReceiptMismatch
    )
    #expect(await evidence.requests.count == 1)
  }

  @Test(arguments: EvidenceValidationCase.allCases)
  fileprivate func malformedOrStaleInventoriesFailClosedAtTheClientBoundary(
    validationCase: EvidenceValidationCase
  ) async throws {
    let evidence = ScriptedRoleEvidenceReader(
      mutationAt: validationCase.mutationCallIndex,
      mutation: validationCase.mutation
    )
    let client = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: evidence
    )

    let failure = await capturedRoleClientFailure {
      try await client.runVisibilityChallenge(self.request())
    }
    #expect(failure == validationCase.expectedFailure)
  }

  @Test func repeatVisualMismatchIsRejectedByTheCorePolicyBeforeBinding() async throws {
    let client = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 1,
        mutation: .repeatCandidateFingerprint
      )
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .evidenceRejected(.phaseEvidenceNotRepeatStable)
    )
  }

  @Test func repeatSemanticMismatchIsRejectedByTheCorePolicyBeforeBinding() async throws {
    let client = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 1,
        mutation: .repeatSemanticState
      )
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .evidenceRejected(.phaseEvidenceNotRepeatStable)
    )
  }

  @Test func anchoredBaselineIdleAndSubsequentCandidateIdleAreAccepted() async throws {
    let baselineIdleClient = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 0,
        mutation: .anchoredBaselineCandidateIdle
      )
    )
    #expect(
      try await baselineIdleClient.runVisibilityChallenge(request()).observations?.count == 6
    )

    let repeatIdleObject = ScriptedRoleObjectController(visibility: .unavailable)
    let repeatIdleClient = try makeClient(
      object: repeatIdleObject,
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 3,
        mutation: .candidateIdle
      )
    )
    let challengeRequest = request()
    #expect(try await repeatIdleClient.runVisibilityChallenge(challengeRequest) == .unavailable)
    #expect(
      try await repeatIdleClient.runPixelNonceChallenge(challengeRequest).observations?.count == 8
    )
  }

  @Test func unchangedOtherWindowMayReuseDisplayTimeOnAFreshIdleCallback() async throws {
    let client = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 1,
        mutation: .otherIdle
      )
    )

    #expect(try await client.runVisibilityChallenge(request()).observations?.count == 6)
  }

  @Test func candidateMutationFirstDeliveryCannotBeIdle() async throws {
    let object = ScriptedRoleObjectController(
      visibility: .unavailable,
      commandReplyTimes: [100, 190, 250]
    )
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 2,
        mutation: .candidateIdle
      )
    )
    let challengeRequest = request()
    #expect(try await client.runVisibilityChallenge(challengeRequest) == .unavailable)
    let failure = await capturedRoleClientFailure {
      try await client.runPixelNonceChallenge(challengeRequest)
    }
    #expect(failure == .candidateMutationRequiresGeneratedPayload)
  }

  @Test(arguments: DeliveryProvenanceValidationCase.allCases)
  fileprivate func deliveryProvenanceMismatchFailsClosedAtClientBoundary(
    validationCase: DeliveryProvenanceValidationCase
  ) async throws {
    let client = try makeClient(
      object: ScriptedRoleObjectController(),
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: validationCase.mutationCallIndex,
        mutation: validationCase.mutation
      )
    )

    let failure = await capturedRoleClientFailure {
      try await client.runVisibilityChallenge(self.request())
    }
    #expect(failure == validationCase.expectedFailure)
  }

  @Test func rejectedFinalRestorationEvidenceTriggersOneMoreRestoreCommand() async throws {
    let object = ScriptedRoleObjectController()
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader(
        mutationAt: 5,
        mutation: .repeatCandidateFingerprint
      )
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .evidenceRejected(.phaseEvidenceNotRepeatStable)
    )
    #expect(
      await object.calls.suffix(2) == [
        .command(.setVisibility(true)), .command(.setVisibility(true)),
      ]
    )
  }

  @Test func evidenceFailureAfterVisibilityMutationRestoresTheSameObjectExactlyOnce() async throws {
    let object = ScriptedRoleObjectController(commandReplyTimes: [100, 190, 250])
    let evidence = ScriptedRoleEvidenceReader(failureAt: 2)
    let client = try makeClient(object: object, evidence: evidence)

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .freshEvidenceReadFailed
    )
    #expect(
      await object.calls == [
        .capability(.visibility),
        .command(.establishBaseline),
        .command(.setVisibility(false)),
        .command(.setVisibility(true)),
      ]
    )
    let requests = await object.commandRequests
    #expect(requests[1].bindingSessionToken == requests[2].bindingSessionToken)
    #expect(requests[1].slideShowObjectToken == requests[2].slideShowObjectToken)
    #expect(requests[1].challengeNonce == requests[2].challengeNonce)
  }

  @Test func evidenceFailureAfterPixelMutationRestoresRunningStateExactlyOnce() async throws {
    let object = ScriptedRoleObjectController(
      visibility: .unavailable,
      commandReplyTimes: [100, 190, 250]
    )
    let evidence = ScriptedRoleEvidenceReader(failureAt: 2)
    let client = try makeClient(object: object, evidence: evidence)
    let challengeRequest = request()

    #expect(try await client.runVisibilityChallenge(challengeRequest) == .unavailable)
    #expect(
      await capturedRoleClientFailure {
        try await client.runPixelNonceChallenge(challengeRequest)
      } == .freshEvidenceReadFailed
    )
    #expect(
      await object.calls.suffix(3) == [
        .command(.establishBaseline),
        .command(.setViewState(.blackScreen)),
        .command(.setViewState(.running)),
      ]
    )
  }

  @Test func restorationFailureOverridesTheEarlierFailureAndRemainsClosed() async throws {
    let object = ScriptedRoleObjectController(commandFailureAt: 2)
    let client = try makeClient(
      object: object,
      evidence: ScriptedRoleEvidenceReader(failureAt: 2)
    )

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .restorationFailed
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .challengeAlreadyConsumed
    )
  }

  @Test func restorationFreshEvidenceMustMatchTheBaseline() async throws {
    let object = ScriptedRoleObjectController(commandReplyTimes: [100, 190, 250])
    let evidence = ScriptedRoleEvidenceReader(
      failureAt: 2,
      mutationAt: 3,
      mutation: .repeatCandidateFingerprint
    )
    let client = try makeClient(object: object, evidence: evidence)

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(self.request())
      } == .restorationFailed
    )
    #expect(await evidence.requests.count == 5)
  }

  @Test func cancelledNoncooperativeCapabilityMustDrainBeforeAnyReplacement() async throws {
    let object = ScriptedRoleObjectController(blockCapabilityAt: 0)
    let evidence = ScriptedRoleEvidenceReader()
    let client = try makeClient(object: object, evidence: evidence)
    let challengeRequest = request()
    let task = Task {
      try await client.runVisibilityChallenge(challengeRequest)
    }
    try await waitForRoleClientState { await object.blockedCapabilityCount == 1 }
    task.cancel()

    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .priorOperationStillDraining
    )
    await object.resumeBlockedCapability()
    #expect(await capturedRoleClientFailure { try await task.value } == .cancelled)
    #expect(await evidence.requests.isEmpty)
  }

  @Test func callerDeadlineCancellationAfterMutationRestoresBeforeDraining() async throws {
    let object = ScriptedRoleObjectController(
      commandReplyTimes: [100, 190, 250],
      failCommandsWhenTaskCancelled: true
    )
    let evidence = ScriptedRoleEvidenceReader(
      blockAt: 2,
      failReadsWhenTaskCancelled: true
    )
    let client = try makeClient(object: object, evidence: evidence)
    let challengeRequest = request()
    let task = Task {
      try await client.runVisibilityChallenge(challengeRequest)
    }
    try await waitForRoleClientState { await evidence.blockedReadCount == 1 }

    // The production coordinator's deadline owner cancels the retained task. The fake deliberately
    // ignores cancellation until resumed, proving that a replacement cannot form a task chain.
    task.cancel()
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .priorOperationStillDraining
    )
    await evidence.resumeBlockedRead()
    #expect(await capturedRoleClientFailure { try await task.value } == .cancelled)
    #expect(
      await object.calls.suffix(2) == [
        .command(.setVisibility(false)), .command(.setVisibility(true)),
      ]
    )
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .challengeAlreadyConsumed
    )
  }

  @Test func coordinatorCancellationAlsoWaitsForClientRestorationToDrain() async throws {
    let object = ScriptedRoleObjectController(commandReplyTimes: [100, 190, 250])
    let evidence = ScriptedRoleEvidenceReader(blockAt: 2)
    let client = try makeClient(object: object, evidence: evidence)
    let coordinator = ManagedSlideShowRoleChallengeCoordinator(
      client: client,
      nonceGenerator: { 40 }
    )
    let candidate = try candidate()
    let task = Task {
      await coordinator.challenge(
        candidate: candidate,
        captureOperationID: self.operationID,
        captureGeneration: self.captureGeneration,
        captureAnchor: self.captureAnchor()
      )
    }
    try await waitForRoleClientState { await evidence.blockedReadCount == 1 }
    await coordinator.cancelCurrentAttempt()

    #expect(
      await coordinator.challenge(
        candidate: candidate,
        captureOperationID: operationID,
        captureGeneration: captureGeneration,
        captureAnchor: captureAnchor()
      ).challengeFailure == .priorAttemptStillDraining
    )
    await evidence.resumeBlockedRead()
    #expect(await task.value.challengeFailure == .cancelled)
    #expect(
      await object.calls.suffix(2) == [
        .command(.setVisibility(false)), .command(.setVisibility(true)),
      ]
    )
  }

  @Test func cleanupCommandDeadlineReturnsButRetainsOwnershipUntilLateDrain() async throws {
    let deadline = ControllableRoleCleanupDeadline()
    let object = ScriptedRoleObjectController(
      commandReplyTimes: [100, 190, 250],
      blockCommandAt: 2
    )
    let evidence = ScriptedRoleEvidenceReader(failureAt: 2)
    let client = try makeClient(
      object: object,
      evidence: evidence,
      cleanupDeadline: deadline
    )
    let challengeRequest = request()
    let task = Task { try await client.runVisibilityChallenge(challengeRequest) }
    try await waitForRoleClientState {
      let blockedCommandCount = await object.blockedCommandCount
      let deadlineWaitCount = await deadline.waitCount
      return blockedCommandCount == 1 && deadlineWaitCount == 1
    }
    await deadline.reachDeadline()

    #expect(await capturedRoleClientFailure { try await task.value } == .restorationTimedOut)
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .priorOperationStillDraining
    )
    await object.resumeBlockedCommand()
    try await waitForRoleClientState { await evidence.requests.count == 5 }
    try await waitForRoleClientState {
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .challengeAlreadyConsumed
    }
  }

  @Test func cleanupEvidenceDeadlineCannotPromoteLateRestorationToSuccess() async throws {
    let deadline = ControllableRoleCleanupDeadline()
    let evidence = ScriptedRoleEvidenceReader(failureAt: 2, blockAt: 3)
    let client = try makeClient(
      object: ScriptedRoleObjectController(commandReplyTimes: [100, 190, 250]),
      evidence: evidence,
      cleanupDeadline: deadline
    )
    let challengeRequest = request()
    let task = Task { try await client.runVisibilityChallenge(challengeRequest) }
    try await waitForRoleClientState {
      let blockedReadCount = await evidence.blockedReadCount
      let deadlineWaitCount = await deadline.waitCount
      return blockedReadCount == 1 && deadlineWaitCount == 1
    }
    await deadline.reachDeadline()

    #expect(await capturedRoleClientFailure { try await task.value } == .restorationTimedOut)
    #expect(
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .priorOperationStillDraining
    )
    await evidence.resumeBlockedRead()
    try await waitForRoleClientState { await evidence.requests.count == 5 }
    try await waitForRoleClientState {
      await capturedRoleClientFailure {
        try await client.runVisibilityChallenge(challengeRequest)
      } == .challengeAlreadyConsumed
    }
  }

  private func makeClient(
    expectedCandidate: ManagedSlideShowRuntimeCandidate? = nil,
    object: ScriptedRoleObjectController,
    evidence: ScriptedRoleEvidenceReader,
    machClock: any ManagedSlideShowBindingMachClock = ScriptedRoleMachClock(),
    commandTokens: LockedRoleTokenSequence = LockedRoleTokenSequence(
      (0..<32).map { "command-\($0)" }
    ),
    evidenceTokens: LockedRoleTokenSequence = LockedRoleTokenSequence(
      (0..<32).map { "evidence-\($0)" }
    ),
    cleanupDeadline: any PowerPointManagedSlideShowRoleCleanupDeadlineWaiting =
      SystemPowerPointManagedSlideShowRoleCleanupDeadline()
  ) throws -> PowerPointManagedSlideShowRoleChallengeClient {
    PowerPointManagedSlideShowRoleChallengeClient(
      expectedCandidate: try expectedCandidate ?? candidate(),
      captureOperationID: operationID,
      captureGeneration: captureGeneration,
      captureAnchor: captureAnchor(),
      objectController: object,
      evidenceReader: evidence,
      machClock: machClock,
      commandRequestTokenFactory: { commandTokens.next() },
      evidenceRequestTokenFactory: { evidenceTokens.next() },
      cleanupDeadline: cleanupDeadline
    )
  }

  private func makeClient(
    expectedCandidate: ManagedSlideShowRuntimeCandidate,
    object: ScriptedRoleObjectController,
    evidence: ScriptedRoleEvidenceReader
  ) -> PowerPointManagedSlideShowRoleChallengeClient {
    let commandTokens = LockedRoleTokenSequence(
      (0..<32).map { "command-\($0)" }
    )
    let evidenceTokens = LockedRoleTokenSequence(
      (0..<32).map { "evidence-\($0)" }
    )
    return PowerPointManagedSlideShowRoleChallengeClient(
      expectedCandidate: expectedCandidate,
      captureOperationID: operationID,
      captureGeneration: captureGeneration,
      captureAnchor: captureAnchor(),
      objectController: object,
      evidenceReader: evidence,
      machClock: ScriptedRoleMachClock(),
      commandRequestTokenFactory: { commandTokens.next() },
      evidenceRequestTokenFactory: { evidenceTokens.next() }
    )
  }

  private func candidate(
    session: String = "session",
    object: String = "object",
    windowID: CGWindowID = 20,
    processIdentifier: pid_t = 700
  ) throws -> ManagedSlideShowRuntimeCandidate {
    ManagedSlideShowRuntimeCandidate(
      candidateWindowIdentity: try #require(
        PowerPointWindowIdentity(
          windowID: windowID,
          ownerProcessID: processIdentifier,
          bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
        )
      ),
      bindingSessionToken: session,
      slideShowObjectToken: object
    )
  }

  private func request(
    candidate: ManagedSlideShowRuntimeCandidate? = nil,
    operationID: CaptureOperationID? = nil,
    captureGeneration: UInt64? = nil,
    captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor? = nil,
    challengeNonce: UInt64? = nil
  ) -> ManagedSlideShowRoleChallengeRequest {
    ManagedSlideShowRoleChallengeRequest(
      candidate: candidate ?? (try! self.candidate()),
      captureOperationID: operationID ?? self.operationID,
      captureGeneration: captureGeneration ?? self.captureGeneration,
      captureAnchor: captureAnchor ?? self.captureAnchor(),
      challengeNonce: challengeNonce ?? self.challengeNonce
    )
  }

  private func mismatchedRequest(
    _ mismatch: RoleRequestMismatch,
    expectedCandidate: ManagedSlideShowRuntimeCandidate
  ) -> ManagedSlideShowRoleChallengeRequest {
    let badCandidate: ManagedSlideShowRuntimeCandidate
    switch mismatch {
    case .session:
      badCandidate = try! candidate(session: "stale-session")
    case .object:
      badCandidate = try! candidate(object: "other-object")
    case .target:
      badCandidate = try! candidate(windowID: 21)
    case .captureOperation, .captureGeneration:
      badCandidate = expectedCandidate
    case .captureAnchor:
      badCandidate = expectedCandidate
    }
    return request(
      candidate: badCandidate,
      operationID: mismatch == .captureOperation ? CaptureOperationID(rawValue: 8) : nil,
      captureGeneration: mismatch == .captureGeneration ? 10 : nil,
      captureAnchor: mismatch == .captureAnchor
        ? ManagedSlideShowRoleChallengeCaptureAnchor(
          candidateStreamMemberToken: "other-member",
          candidateContinuityToken: "candidate-continuity",
          minimumCandidateDeliverySequenceExclusive: 79
        )
        : nil
    )
  }

  private func managedIdentity(windowID: Int) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }

  private func captureAnchor() -> ManagedSlideShowRoleChallengeCaptureAnchor {
    ManagedSlideShowRoleChallengeCaptureAnchor(
      candidateStreamMemberToken: "candidate-member",
      candidateContinuityToken: "candidate-continuity",
      minimumCandidateDeliverySequenceExclusive: 79
    )
  }
}

private enum RoleRequestMismatch: CaseIterable, Sendable {
  case session
  case object
  case target
  case captureOperation
  case captureGeneration
  case captureAnchor

  var expectedFailure: PowerPointManagedSlideShowRoleChallengeClientFailure {
    switch self {
    case .session: .staleSession
    case .object: .objectTokenMismatch
    case .target: .targetIdentityMismatch
    case .captureOperation: .captureOperationMismatch
    case .captureGeneration: .captureGenerationMismatch
    case .captureAnchor: .captureAnchorMismatch
    }
  }
}

private enum EvidenceProvenanceMutation: CaseIterable, Sendable {
  case resultToken
  case session
  case object
  case process
  case bundle
  case candidate
  case captureOperation
  case captureGeneration
  case phase
  case nonce
  case commandReply
  case candidateDisplayReceipt

  var mutation: RoleEvidenceMutation {
    switch self {
    case .resultToken: .resultToken
    case .session: .session
    case .object: .object
    case .process: .process
    case .bundle: .bundle
    case .candidate: .candidate
    case .captureOperation: .captureOperation
    case .captureGeneration: .captureGeneration
    case .phase: .phase
    case .nonce: .nonce
    case .commandReply: .commandReply
    case .candidateDisplayReceipt: .candidateDisplayReceipt
    }
  }
}

private enum EvidenceValidationCase: CaseIterable, Sendable {
  case incomplete
  case observationStale
  case observationTimeNotIncreasing
  case frameStale
  case frameTimeNotIncreasing
  case observationFuture
  case frameBeforeRequest
  case duplicateWindow
  case wrongWindowProcess
  case invalidFingerprint
  case malformedPixelTimePair
  case missingBaselineCandidate

  var mutationCallIndex: Int {
    switch self {
    case .observationTimeNotIncreasing, .frameTimeNotIncreasing: 1
    default: 0
    }
  }

  var mutation: RoleEvidenceMutation {
    switch self {
    case .incomplete: .incomplete
    case .observationStale: .observationStale
    case .observationTimeNotIncreasing: .observationTimeNotIncreasing
    case .frameStale: .frameStale
    case .frameTimeNotIncreasing: .frameTimeNotIncreasing
    case .observationFuture: .observationFuture
    case .frameBeforeRequest: .frameBeforeRequest
    case .duplicateWindow: .duplicateWindow
    case .wrongWindowProcess: .wrongWindowProcess
    case .invalidFingerprint: .invalidFingerprint
    case .malformedPixelTimePair: .malformedPixelTimePair
    case .missingBaselineCandidate: .missingBaselineCandidate
    }
  }

  var expectedFailure: PowerPointManagedSlideShowRoleChallengeClientFailure {
    switch self {
    case .incomplete: .incompleteWindowInventory
    case .observationStale: .staleFreshEvidence
    case .observationTimeNotIncreasing: .evidenceTimeNotIncreasing
    case .frameStale: .windowFrameNotFresh
    case .frameTimeNotIncreasing: .windowFrameTimeNotIncreasing
    case .observationFuture: .evidenceAcquisitionTimeOutOfBounds
    case .frameBeforeRequest: .windowFrameTimeOutOfBounds
    case .duplicateWindow, .wrongWindowProcess, .invalidFingerprint,
      .malformedPixelTimePair, .missingBaselineCandidate:
      .malformedWindowInventory
    }
  }
}

private enum DeliveryProvenanceValidationCase: CaseIterable, Sendable {
  case missing
  case partial
  case blank
  case suspended
  case stopped
  case operationMismatch
  case generationMismatch
  case streamDrift
  case continuityDrift
  case sequenceReplay
  case callbackReplay
  case callbackStale
  case callbackFuture
  case idleFingerprintChanged
  case idleDisplayTimeChanged
  case duplicateStreamMember

  var mutationCallIndex: Int {
    switch self {
    case .streamDrift, .continuityDrift, .sequenceReplay, .callbackReplay,
      .idleFingerprintChanged, .idleDisplayTimeChanged:
      1
    default:
      0
    }
  }

  var mutation: RoleEvidenceMutation {
    switch self {
    case .missing: .missingDeliveryProvenance
    case .partial: .partialDeliveryProvenance
    case .blank: .blankDelivery
    case .suspended: .suspendedDelivery
    case .stopped: .stoppedDelivery
    case .operationMismatch: .deliveryOperationMismatch
    case .generationMismatch: .deliveryGenerationMismatch
    case .streamDrift: .candidateStreamDrift
    case .continuityDrift: .candidateContinuityDrift
    case .sequenceReplay: .deliverySequenceReplay
    case .callbackReplay: .callbackTimeReplay
    case .callbackStale: .callbackTimeStale
    case .callbackFuture: .callbackTimeFuture
    case .idleFingerprintChanged: .idleFingerprintChanged
    case .idleDisplayTimeChanged: .idleDisplayTimeChanged
    case .duplicateStreamMember: .duplicateStreamMember
    }
  }

  var expectedFailure: PowerPointManagedSlideShowRoleChallengeClientFailure {
    switch self {
    case .missing, .partial, .operationMismatch, .generationMismatch,
      .duplicateStreamMember:
      .windowDeliveryProvenanceMalformed
    case .blank, .suspended, .stopped:
      .unsupportedWindowDeliveryStatus
    case .streamDrift: .windowStreamMemberMismatch
    case .continuityDrift: .windowContinuityMismatch
    case .sequenceReplay: .windowDeliverySequenceNotIncreasing
    case .callbackReplay: .windowCallbackTimeNotIncreasing
    case .callbackStale: .windowCallbackTimeStale
    case .callbackFuture: .windowCallbackTimeOutOfBounds
    case .idleFingerprintChanged, .idleDisplayTimeChanged:
      .idleWindowPayloadChanged
    }
  }
}

private enum RoleObjectCall: Equatable, Sendable {
  case capability(PowerPointManagedSlideShowRoleCapability)
  case command(PowerPointManagedSlideShowRoleCommand)
}

private enum InjectedRoleBoundaryFailure: Error {
  case injected
}

private actor ScriptedRoleObjectController:
  PowerPointManagedSlideShowRoleObjectCommanding
{
  private let visibility: PowerPointManagedSlideShowRoleCapabilityState
  private let pixelNonce: PowerPointManagedSlideShowRoleCapabilityState
  private let capabilityFailureAt: Int?
  private let capabilityReceiptMismatchAt: Int?
  private let commandFailureAt: Int?
  private let commandReceiptMismatchAt: Int?
  private var commandReplyTimes: [UInt64]
  private let blockCapabilityAt: Int?
  private let blockCommandAt: Int?
  private let failCommandsWhenTaskCancelled: Bool
  private var capabilityContinuation: CheckedContinuation<Void, Never>?
  private var commandContinuation: CheckedContinuation<Void, Never>?

  private(set) var calls: [RoleObjectCall] = []
  private(set) var capabilityRequests: [PowerPointManagedSlideShowRoleCapabilityRequest] = []
  private(set) var commandRequests: [PowerPointManagedSlideShowRoleCommandRequest] = []
  private(set) var blockedCapabilityCount = 0
  private(set) var blockedCommandCount = 0

  init(
    visibility: PowerPointManagedSlideShowRoleCapabilityState = .available,
    pixelNonce: PowerPointManagedSlideShowRoleCapabilityState = .available,
    capabilityFailureAt: Int? = nil,
    capabilityReceiptMismatchAt: Int? = nil,
    commandFailureAt: Int? = nil,
    commandReceiptMismatchAt: Int? = nil,
    commandReplyTimes: [UInt64] = [100, 190, 280, 370, 460],
    blockCapabilityAt: Int? = nil,
    blockCommandAt: Int? = nil,
    failCommandsWhenTaskCancelled: Bool = false
  ) {
    self.visibility = visibility
    self.pixelNonce = pixelNonce
    self.capabilityFailureAt = capabilityFailureAt
    self.capabilityReceiptMismatchAt = capabilityReceiptMismatchAt
    self.commandFailureAt = commandFailureAt
    self.commandReceiptMismatchAt = commandReceiptMismatchAt
    self.commandReplyTimes = commandReplyTimes
    self.blockCapabilityAt = blockCapabilityAt
    self.blockCommandAt = blockCommandAt
    self.failCommandsWhenTaskCancelled = failCommandsWhenTaskCancelled
  }

  func readCapability(
    _ request: PowerPointManagedSlideShowRoleCapabilityRequest
  ) async throws -> PowerPointManagedSlideShowRoleCapabilityReceipt {
    let index = capabilityRequests.count
    capabilityRequests.append(request)
    calls.append(.capability(request.capability))
    if blockCapabilityAt == index {
      blockedCapabilityCount += 1
      await withCheckedContinuation { continuation in
        capabilityContinuation = continuation
      }
    }
    if capabilityFailureAt == index { throw InjectedRoleBoundaryFailure.injected }
    var receiptRequest = request
    if capabilityReceiptMismatchAt == index {
      receiptRequest = PowerPointManagedSlideShowRoleCapabilityRequest(
        bindingSessionToken: request.bindingSessionToken,
        slideShowObjectToken: request.slideShowObjectToken,
        processIdentifier: request.processIdentifier,
        bundleIdentifier: request.bundleIdentifier,
        challengeNonce: request.challengeNonce,
        capability: request.capability,
        freshRequestToken: "wrong-capability-token"
      )
    }
    return PowerPointManagedSlideShowRoleCapabilityReceipt(
      request: receiptRequest,
      state: request.capability == .visibility ? visibility : pixelNonce
    )
  }

  func perform(
    _ request: PowerPointManagedSlideShowRoleCommandRequest
  ) async throws -> PowerPointManagedSlideShowRoleCommandReceipt {
    let index = commandRequests.count
    commandRequests.append(request)
    calls.append(.command(request.command))
    if blockCommandAt == index {
      blockedCommandCount += 1
      await withCheckedContinuation { continuation in
        commandContinuation = continuation
      }
    }
    if failCommandsWhenTaskCancelled, Task.isCancelled {
      throw CancellationError()
    }
    if commandFailureAt == index { throw InjectedRoleBoundaryFailure.injected }
    let time =
      commandReplyTimes.isEmpty
      ? 0
      : commandReplyTimes.removeFirst()
    var receiptRequest = request
    if commandReceiptMismatchAt == index {
      receiptRequest = PowerPointManagedSlideShowRoleCommandRequest(
        bindingSessionToken: request.bindingSessionToken,
        slideShowObjectToken: request.slideShowObjectToken,
        processIdentifier: request.processIdentifier,
        bundleIdentifier: request.bundleIdentifier,
        challengeNonce: request.challengeNonce,
        phaseNonce: request.phaseNonce,
        command: request.command,
        freshRequestToken: "wrong-command-token"
      )
    }
    return PowerPointManagedSlideShowRoleCommandReceipt(
      request: receiptRequest,
      repliedMachAbsoluteTime: time
    )
  }

  var freshRequestTokens: [String] {
    capabilityRequests.map(\.freshRequestToken)
      + commandRequests.map(\.freshRequestToken)
  }

  func resumeBlockedCapability() {
    capabilityContinuation?.resume()
    capabilityContinuation = nil
  }

  func resumeBlockedCommand() {
    commandContinuation?.resume()
    commandContinuation = nil
  }
}

private enum RoleEvidenceMutation: Sendable {
  case resultToken
  case session
  case object
  case process
  case bundle
  case candidate
  case captureOperation
  case captureGeneration
  case phase
  case nonce
  case commandReply
  case candidateDisplayReceipt
  case incomplete
  case observationStale
  case observationTimeNotIncreasing
  case frameStale
  case frameTimeNotIncreasing
  case observationFuture
  case frameBeforeRequest
  case duplicateWindow
  case wrongWindowProcess
  case invalidFingerprint
  case malformedPixelTimePair
  case missingBaselineCandidate
  case repeatCandidateFingerprint
  case repeatSemanticState
  case anchoredBaselineCandidateIdle
  case candidateIdle
  case otherIdle
  case missingDeliveryProvenance
  case partialDeliveryProvenance
  case blankDelivery
  case suspendedDelivery
  case stoppedDelivery
  case deliveryOperationMismatch
  case deliveryGenerationMismatch
  case candidateStreamDrift
  case candidateContinuityDrift
  case deliverySequenceReplay
  case callbackTimeReplay
  case callbackTimeStale
  case callbackTimeFuture
  case idleFingerprintChanged
  case idleDisplayTimeChanged
  case duplicateStreamMember
}

private actor ScriptedRoleEvidenceReader:
  PowerPointManagedSlideShowRoleFreshEvidenceReading
{
  private let failureAt: Int?
  private let mutationAt: Int?
  private let mutation: RoleEvidenceMutation?
  private let blockAt: Int?
  private let failReadsWhenTaskCancelled: Bool
  private var continuation: CheckedContinuation<Void, Never>?

  private(set) var requests: [PowerPointManagedSlideShowRoleFreshEvidenceRequest] = []
  private(set) var blockedReadCount = 0
  private var lastCandidateWindow: ManagedSlideShowRoleWindowEvidence?
  private var lastOtherWindow: ManagedSlideShowRoleWindowEvidence?

  init(
    failureAt: Int? = nil,
    mutationAt: Int? = nil,
    mutation: RoleEvidenceMutation? = nil,
    blockAt: Int? = nil,
    failReadsWhenTaskCancelled: Bool = false
  ) {
    self.failureAt = failureAt
    self.mutationAt = mutationAt
    self.mutation = mutation
    self.blockAt = blockAt
    self.failReadsWhenTaskCancelled = failReadsWhenTaskCancelled
  }

  func readFreshEvidence(
    _ request: PowerPointManagedSlideShowRoleFreshEvidenceRequest
  ) async throws -> PowerPointManagedSlideShowRoleFreshEvidence {
    let index = requests.count
    requests.append(request)
    if blockAt == index {
      blockedReadCount += 1
      await withCheckedContinuation { continuation in
        self.continuation = continuation
      }
    }
    if failReadsWhenTaskCancelled, Task.isCancelled {
      throw CancellationError()
    }
    if failureAt == index { throw InjectedRoleBoundaryFailure.injected }
    return makeEvidence(
      request: request,
      index: index,
      mutation: mutationAt == index ? mutation : nil
    )
  }

  var freshRequestTokens: [String] {
    requests.map(\.freshRequestToken)
  }

  func resumeBlockedRead() {
    continuation?.resume()
    continuation = nil
  }

  private func makeEvidence(
    request: PowerPointManagedSlideShowRoleFreshEvidenceRequest,
    index: Int,
    mutation: RoleEvidenceMutation?
  ) -> PowerPointManagedSlideShowRoleFreshEvidence {
    let normalTime = request.requestStartedMachAbsoluteTime + 10
    var resultToken = request.freshRequestToken
    var session = request.bindingSessionToken
    var object = request.slideShowObjectToken
    var process = request.processIdentifier
    var bundle = request.bundleIdentifier
    var candidateIdentity = request.candidateWindowIdentity
    var captureOperation = request.captureOperationID
    var captureGeneration = request.captureGeneration
    var phase = request.phase
    var nonce = request.nonce
    var commandReply = request.minimumDisplayTimeExclusive
    var observedTime = normalTime
    var inventoryIsComplete = true
    var semanticState = semanticState(for: request.phase)
    let candidateOnScreen = request.phase != .visibilityHidden
    var candidateLuminance = luminance(for: request.phase)
    var candidateDisplayTime: UInt64? = candidateOnScreen ? normalTime : nil
    var candidateFrameDisplayTime = candidateDisplayTime
    var candidateFingerprint: FrameFingerprint? =
      candidateOnScreen
      ? fingerprint(candidateLuminance)
      : nil
    var otherDisplayTime = normalTime
    var otherIdentity = managedIdentity(windowID: 10)
    var candidateDeliveryStatus: ManagedSlideShowRoleWindowDeliveryStatus? = .generated
    var otherDeliveryStatus: ManagedSlideShowRoleWindowDeliveryStatus? = .generated
    var candidateCaptureOperation: UInt64? = request.captureOperationID
    var candidateCaptureGeneration: UInt64? = request.captureGeneration
    var candidateStreamMemberToken: String? = request.captureAnchor.candidateStreamMemberToken
    var candidateContinuityToken: String? = request.captureAnchor.candidateContinuityToken
    var otherStreamMemberToken: String? = "other-member"
    let otherContinuityToken: String? = "other-continuity"
    var candidateDeliverySequence: UInt64? =
      request.captureAnchor.minimumCandidateDeliverySequenceExclusive + 1 + UInt64(index)
    let otherDeliverySequence = candidateDeliverySequence
    var candidateCallbackMachAbsoluteTime: UInt64? = normalTime
    let otherCallbackMachAbsoluteTime = candidateCallbackMachAbsoluteTime
    var omitCandidateDeliveryProvenance = false
    var malformedPixelTimePair = false
    var omitCandidate = !candidateOnScreen
    var duplicateWindow = false

    switch mutation {
    case .resultToken: resultToken = "wrong-evidence-token"
    case .session: session = "wrong-session"
    case .object: object = "wrong-object"
    case .process: process += 1
    case .bundle: bundle = "wrong.bundle"
    case .candidate: candidateIdentity = managedIdentity(windowID: 99)
    case .captureOperation: captureOperation += 1
    case .captureGeneration: captureGeneration += 1
    case .phase: phase = .pixelWhite
    case .nonce: nonce += 1
    case .commandReply: commandReply += 1
    case .candidateDisplayReceipt: candidateDisplayTime = normalTime + 1
    case .incomplete: inventoryIsComplete = false
    case .observationStale: observedTime = request.minimumDisplayTimeExclusive
    case .observationTimeNotIncreasing:
      observedTime = request.minimumDisplayTimeExclusive + 30
    case .frameStale:
      candidateDisplayTime = request.minimumDisplayTimeExclusive
      candidateFrameDisplayTime = candidateDisplayTime
      otherDisplayTime = request.minimumDisplayTimeExclusive
    case .frameTimeNotIncreasing:
      candidateDisplayTime = request.minimumDisplayTimeExclusive + 30
      candidateFrameDisplayTime = candidateDisplayTime
      otherDisplayTime = request.minimumDisplayTimeExclusive + 30
    case .observationFuture:
      observedTime = request.requestStartedMachAbsoluteTime + 30
    case .frameBeforeRequest:
      candidateDisplayTime = request.requestStartedMachAbsoluteTime - 1
      candidateFrameDisplayTime = candidateDisplayTime
      otherDisplayTime = request.requestStartedMachAbsoluteTime - 1
    case .duplicateWindow: duplicateWindow = true
    case .wrongWindowProcess:
      otherIdentity = ManagedSlideShowWindowIdentity(
        windowID: 10,
        processIdentifier: request.processIdentifier + 1,
        bundleIdentifier: request.bundleIdentifier
      )
    case .invalidFingerprint:
      candidateFingerprint = FrameFingerprint(
        sampleColumns: 2,
        sampleRows: 2,
        luminance: [1, 2, 3]
      )
    case .malformedPixelTimePair: malformedPixelTimePair = true
    case .missingBaselineCandidate: omitCandidate = true
    case .repeatCandidateFingerprint:
      candidateLuminance += 1
      candidateFingerprint = fingerprint(candidateLuminance)
    case .repeatSemanticState:
      semanticState = ManagedSlideShowRoleSemanticState(
        slideID: 51,
        slideIndex: 3,
        currentViewState: semanticState.currentViewState,
        presentationSaved: true
      )
    case .anchoredBaselineCandidateIdle:
      candidateDeliveryStatus = .idle
      candidateDisplayTime = request.minimumDisplayTimeExclusive - 1
      candidateFrameDisplayTime = candidateDisplayTime
    case .candidateIdle:
      candidateDeliveryStatus = .idle
      candidateDisplayTime = lastCandidateWindow?.displayTime
      candidateFrameDisplayTime = candidateDisplayTime
      candidateFingerprint = lastCandidateWindow?.fingerprint
    case .otherIdle:
      otherDeliveryStatus = .idle
      otherDisplayTime = lastOtherWindow?.displayTime ?? otherDisplayTime
    case .missingDeliveryProvenance:
      omitCandidateDeliveryProvenance = true
    case .partialDeliveryProvenance:
      candidateContinuityToken = nil
    case .blankDelivery:
      candidateDeliveryStatus = .blank
    case .suspendedDelivery:
      candidateDeliveryStatus = .suspended
    case .stoppedDelivery:
      candidateDeliveryStatus = .stopped
    case .deliveryOperationMismatch:
      candidateCaptureOperation = request.captureOperationID + 1
    case .deliveryGenerationMismatch:
      candidateCaptureGeneration = request.captureGeneration + 1
    case .candidateStreamDrift:
      candidateStreamMemberToken = "drifted-member"
    case .candidateContinuityDrift:
      candidateContinuityToken = "drifted-continuity"
    case .deliverySequenceReplay:
      candidateDeliverySequence = lastCandidateWindow?.deliveryProvenance?.deliverySequence
    case .callbackTimeReplay:
      candidateDeliveryStatus = .idle
      candidateDisplayTime = lastCandidateWindow?.displayTime
      candidateFrameDisplayTime = candidateDisplayTime
      candidateFingerprint = lastCandidateWindow?.fingerprint
      candidateCallbackMachAbsoluteTime =
        lastCandidateWindow?.deliveryProvenance?.callbackMachAbsoluteTime
    case .callbackTimeStale:
      candidateDeliveryStatus = .idle
      candidateDisplayTime = request.minimumDisplayTimeExclusive - 1
      candidateFrameDisplayTime = candidateDisplayTime
      candidateCallbackMachAbsoluteTime = request.minimumDisplayTimeExclusive
    case .callbackTimeFuture:
      candidateCallbackMachAbsoluteTime = request.requestStartedMachAbsoluteTime + 30
    case .idleFingerprintChanged:
      candidateDeliveryStatus = .idle
      candidateDisplayTime = lastCandidateWindow?.displayTime
      candidateFrameDisplayTime = candidateDisplayTime
      candidateFingerprint = fingerprint(candidateLuminance + 1)
    case .idleDisplayTimeChanged:
      candidateDeliveryStatus = .idle
      candidateDisplayTime = (lastCandidateWindow?.displayTime ?? normalTime) + 1
      candidateFrameDisplayTime = candidateDisplayTime
      candidateFingerprint = lastCandidateWindow?.fingerprint
    case .duplicateStreamMember:
      otherStreamMemberToken = candidateStreamMemberToken
    case nil:
      break
    }

    var windows = [
      ManagedSlideShowRoleWindowEvidence(
        identity: otherIdentity,
        fingerprint: fingerprint(80),
        isOnScreen: true,
        displayTime: otherDisplayTime,
        deliveryProvenance: ManagedSlideShowRoleWindowDeliveryProvenance(
          status: otherDeliveryStatus,
          captureOperationID: request.captureOperationID,
          captureGeneration: request.captureGeneration,
          streamMemberToken: otherStreamMemberToken,
          continuityToken: otherContinuityToken,
          deliverySequence: otherDeliverySequence,
          callbackMachAbsoluteTime: otherCallbackMachAbsoluteTime
        )
      )
    ]
    if duplicateWindow { windows.append(windows[0]) }
    if !omitCandidate {
      windows.append(
        ManagedSlideShowRoleWindowEvidence(
          identity: request.candidateWindowIdentity,
          fingerprint: candidateFingerprint,
          isOnScreen: candidateOnScreen,
          displayTime: malformedPixelTimePair ? nil : candidateFrameDisplayTime,
          deliveryProvenance: !candidateOnScreen || omitCandidateDeliveryProvenance
            ? nil
            : ManagedSlideShowRoleWindowDeliveryProvenance(
              status: candidateDeliveryStatus,
              captureOperationID: candidateCaptureOperation,
              captureGeneration: candidateCaptureGeneration,
              streamMemberToken: candidateStreamMemberToken,
              continuityToken: candidateContinuityToken,
              deliverySequence: candidateDeliverySequence,
              callbackMachAbsoluteTime: candidateCallbackMachAbsoluteTime
            )
        )
      )
    }

    lastOtherWindow = windows.first
    if let candidateWindow = windows.first(where: {
      $0.identity == request.candidateWindowIdentity && $0.fingerprint != nil
    }) {
      lastCandidateWindow = candidateWindow
    }

    return PowerPointManagedSlideShowRoleFreshEvidence(
      freshRequestToken: resultToken,
      observation: ManagedSlideShowRoleChallengeObservation(
        bindingSessionToken: session,
        slideShowObjectToken: object,
        processIdentifier: process,
        bundleIdentifier: bundle,
        candidateWindowIdentity: candidateIdentity,
        captureOperationID: captureOperation,
        captureGeneration: captureGeneration,
        phase: phase,
        nonce: nonce,
        commandReplyMachAbsoluteTime: commandReply,
        evidenceObservedMachAbsoluteTime: observedTime,
        candidateDisplayTime: candidateDisplayTime,
        inventoryIsComplete: inventoryIsComplete,
        semanticState: semanticState,
        windows: windows
      )
    )
  }

  private func semanticState(
    for phase: ManagedSlideShowRoleChallengePhase
  ) -> ManagedSlideShowRoleSemanticState {
    let state: ManagedSlideShowRoleCurrentViewState
    switch phase {
    case .pixelBlack: state = .blackScreen
    case .pixelWhite: state = .whiteScreen
    default: state = .running
    }
    return ManagedSlideShowRoleSemanticState(
      slideID: 50,
      slideIndex: 3,
      currentViewState: state,
      presentationSaved: true
    )
  }

  private func luminance(
    for phase: ManagedSlideShowRoleChallengePhase
  ) -> UInt8 {
    switch phase {
    case .pixelBlack: 0
    case .pixelWhite: 255
    default: 100
    }
  }

  private func fingerprint(_ luminance: UInt8) -> FrameFingerprint {
    FrameFingerprint(
      sampleColumns: 2,
      sampleRows: 2,
      luminance: Array(repeating: luminance, count: 4)
    )
  }

  private func managedIdentity(windowID: Int) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }
}

private final class LockedRoleTokenSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String]

  init(_ values: [String]) {
    self.values = values
  }

  func next() -> String {
    lock.withLock {
      guard !values.isEmpty else { return "" }
      return values.removeFirst()
    }
  }
}

private actor ScriptedRoleMachClock: ManagedSlideShowBindingMachClock {
  private var values: [UInt64]
  private var fallback: UInt64

  init(values: [UInt64]? = nil) {
    let generated = (0..<40).flatMap { index -> [UInt64] in
      let start = UInt64(90 + (index * 30))
      return [start, start + 20]
    }
    self.values = values ?? generated
    self.fallback = (values ?? generated).last ?? 0
  }

  func now() -> UInt64 {
    guard !values.isEmpty else { return fallback }
    let value = values.removeFirst()
    fallback = value
    return value
  }
}

private actor ControllableRoleCleanupDeadline:
  PowerPointManagedSlideShowRoleCleanupDeadlineWaiting
{
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var waitCount = 0

  func waitForDeadline() async {
    waitCount += 1
    await withCheckedContinuation { continuation = $0 }
  }

  func reachDeadline() {
    continuation?.resume()
    continuation = nil
  }
}

extension ManagedSlideShowRoleChallengeClientResult {
  fileprivate var observations: [ManagedSlideShowRoleChallengeObservation]? {
    guard case .evidence(let observations) = self else { return nil }
    return observations
  }
}

extension Result where Failure == ManagedSlideShowRoleChallengeCoordinatorFailure {
  fileprivate var challengeFailure: Failure? {
    guard case .failure(let failure) = self else { return nil }
    return failure
  }
}

@MainActor
private func capturedRoleClientFailure<Value>(
  _ operation: () async throws -> Value
) async -> PowerPointManagedSlideShowRoleChallengeClientFailure? {
  do {
    _ = try await operation()
    return nil
  } catch let failure as PowerPointManagedSlideShowRoleChallengeClientFailure {
    return failure
  } catch {
    Issue.record("Unexpected role-client error type: \(error)")
    return nil
  }
}

private func waitForRoleClientState(
  attempts: Int = 400,
  _ predicate: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await predicate() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Timed out waiting for deterministic role-client fake state")
  throw PowerPointManagedSlideShowRoleChallengeClientFailure.staleCompletion
}
