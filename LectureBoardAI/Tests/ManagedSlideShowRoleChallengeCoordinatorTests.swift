import CoreGraphics
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct ManagedSlideShowRoleChallengeCoordinatorTests {
  @Test func visibilityEvidenceProducesTheOnlySemanticBinding() async throws {
    let candidate = try candidate()
    let client = ScriptedRoleChallengeClient(
      visibility: .evidence(transcript(method: .visibility)),
      pixel: .unavailable
    )
    let result = await ManagedSlideShowRoleChallengeCoordinator(
      client: client,
      nonceGenerator: { 40 }
    ).challenge(
      candidate: candidate,
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: anchor()
    )
    let binding = try #require(result.roleBinding)

    #expect(binding.windowIdentity == candidate.candidateWindowIdentity)
    #expect(binding.bindingSessionToken == candidate.bindingSessionToken)
    #expect(binding.slideShowObjectToken == candidate.slideShowObjectToken)
    #expect(binding.captureOperationID == CaptureOperationID(rawValue: 7))
    #expect(binding.captureGeneration == 9)
    #expect(binding.freshnessBoundaryMachAbsoluteTime == 320)
    #expect(await client.calls == [.visibility])
    #expect(await client.challengeNonces == [40])
  }

  @Test func pixelNonceIsUsedOnlyWhenVisibilityIsUnavailable() async throws {
    let client = ScriptedRoleChallengeClient(
      visibility: .unavailable,
      pixel: .evidence(transcript(method: .pixelNonce))
    )
    let result = await ManagedSlideShowRoleChallengeCoordinator(
      client: client,
      nonceGenerator: { 40 }
    ).challenge(
      candidate: try candidate(),
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: anchor()
    )

    #expect(result.roleBinding?.freshnessBoundaryMachAbsoluteTime == 420)
    #expect(await client.calls == [.visibility, .pixelNonce])
  }

  @Test func contradictoryVisibilityEvidenceDoesNotFallBackToPixels() async throws {
    var evidence = transcript(method: .visibility)
    evidence.removeLast()
    let client = ScriptedRoleChallengeClient(
      visibility: .evidence(evidence),
      pixel: .evidence(transcript(method: .pixelNonce))
    )
    let result = await ManagedSlideShowRoleChallengeCoordinator(
      client: client,
      nonceGenerator: { 40 }
    ).challenge(
      candidate: try candidate(),
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: anchor()
    )

    #expect(result.roleFailure == .unexpectedEvidenceCount)
    #expect(await client.calls == [.visibility])
  }

  @Test func oversizedClientEvidenceIsRejectedBeforePolicyEvaluation() async throws {
    var evidence = transcript(method: .visibility)
    evidence.append(evidence[0])
    let result = await ManagedSlideShowRoleChallengeCoordinator(
      client: ScriptedRoleChallengeClient(
        visibility: .evidence(evidence),
        pixel: .unavailable
      ),
      nonceGenerator: { 40 }
    ).challenge(
      candidate: try candidate(),
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: anchor()
    )
    #expect(result.roleFailure == .unexpectedEvidenceCount)
  }

  @Test func staleAndMismatchedEvidenceCannotConstructABinding() async throws {
    var stale = transcript(method: .visibility)
    stale[0] = observation(
      method: .visibility,
      phase: .baseline,
      nonce: 40,
      repeatIndex: 0,
      commandReplyTime: 100,
      evidenceObservedTime: 100
    )
    let staleResult = await ManagedSlideShowRoleChallengeCoordinator(
      client: ScriptedRoleChallengeClient(visibility: .evidence(stale), pixel: .unavailable),
      nonceGenerator: { 40 }
    ).challenge(
      candidate: try candidate(),
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: anchor()
    )
    #expect(staleResult.roleFailure == .policyRejected(.staleEvidenceObservationTime))

    var mismatch = transcript(method: .visibility)
    mismatch[0] = observation(method: .visibility, session: "wrong")
    let mismatchResult = await ManagedSlideShowRoleChallengeCoordinator(
      client: ScriptedRoleChallengeClient(visibility: .evidence(mismatch), pixel: .unavailable),
      nonceGenerator: { 40 }
    ).challenge(
      candidate: try candidate(),
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: anchor()
    )
    #expect(mismatchResult.roleFailure == .policyRejected(.sessionMismatch))
  }

  @Test func noncooperativeClientBlocksReplacementUntilCancelledWorkDrains() async throws {
    let client = ControllableRoleChallengeClient()
    let coordinator = ManagedSlideShowRoleChallengeCoordinator(
      client: client,
      nonceGenerator: { 40 }
    )
    let candidate = try candidate()
    let first = Task {
      await coordinator.challenge(
        candidate: candidate,
        captureOperationID: CaptureOperationID(rawValue: 7),
        captureGeneration: 9,
        captureAnchor: anchor()
      )
    }
    try await waitForRoleChallenge { await client.callCount == 1 }

    #expect(
      await coordinator.challenge(
        candidate: candidate,
        captureOperationID: CaptureOperationID(rawValue: 7),
        captureGeneration: 9,
        captureAnchor: anchor()
      ).roleFailure == .priorAttemptStillDraining
    )
    await coordinator.cancelCurrentAttempt()
    #expect(
      await coordinator.challenge(
        candidate: candidate,
        captureOperationID: CaptureOperationID(rawValue: 7),
        captureGeneration: 9,
        captureAnchor: anchor()
      ).roleFailure == .priorAttemptStillDraining
    )

    await client.resumeVisibility(with: .unavailable)
    #expect(await first.value.roleFailure == .cancelled)
    #expect(await client.callCount == 1)
  }

  private func candidate() throws -> ManagedSlideShowRuntimeCandidate {
    let identity = try #require(
      PowerPointWindowIdentity(
        windowID: CGWindowID(20),
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    )
    return ManagedSlideShowRuntimeCandidate(
      candidateWindowIdentity: identity,
      bindingSessionToken: "session",
      slideShowObjectToken: "object"
    )
  }

  private func anchor() -> ManagedSlideShowRoleChallengeCaptureAnchor {
    ManagedSlideShowRoleChallengeCaptureAnchor(
      candidateStreamMemberToken: "candidate-member",
      candidateContinuityToken: "candidate-continuity",
      minimumCandidateDeliverySequenceExclusive: 79
    )
  }

  private func transcript(
    method: ManagedSlideShowRoleChallengeMethod
  ) -> [ManagedSlideShowRoleChallengeObservation] {
    let phases: [ManagedSlideShowRoleChallengePhase] =
      method == .visibility
      ? [.baseline, .visibilityHidden, .visibilityRestored]
      : [.baseline, .pixelBlack, .pixelWhite, .pixelRunningRestored]
    return phases.enumerated().flatMap { phaseIndex, phase in
      [0, 1].map {
        observation(
          method: method,
          phase: phase,
          nonce: 40 + UInt64(phaseIndex),
          repeatIndex: $0,
          commandReplyTime: UInt64((phaseIndex + 1) * 100)
        )
      }
    }
  }

  private func observation(
    method: ManagedSlideShowRoleChallengeMethod,
    session: String = "session",
    phase: ManagedSlideShowRoleChallengePhase = .baseline,
    nonce: UInt64 = 40,
    repeatIndex: Int = 0,
    commandReplyTime: UInt64? = nil,
    evidenceObservedTime: UInt64? = nil
  ) -> ManagedSlideShowRoleChallengeObservation {
    let reply = commandReplyTime ?? (nonce - 39) * 100
    let observed = evidenceObservedTime ?? reply + UInt64((repeatIndex + 1) * 10)
    let phaseValues = values(method: method, phase: phase)
    let candidateFingerprint = phaseValues.onScreen ? fingerprint(phaseValues.luminance) : nil
    return ManagedSlideShowRoleChallengeObservation(
      bindingSessionToken: session,
      slideShowObjectToken: "object",
      processIdentifier: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
      candidateWindowIdentity: managedIdentity(20),
      captureOperationID: 7,
      captureGeneration: 9,
      phase: phase,
      nonce: nonce,
      commandReplyMachAbsoluteTime: reply,
      evidenceObservedMachAbsoluteTime: observed,
      candidateDisplayTime: phaseValues.onScreen ? observed : nil,
      inventoryIsComplete: true,
      semanticState: ManagedSlideShowRoleSemanticState(
        slideID: 50,
        slideIndex: 3,
        currentViewState: phaseValues.state,
        presentationSaved: true
      ),
      windows: [
        ManagedSlideShowRoleWindowEvidence(
          identity: managedIdentity(10),
          fingerprint: fingerprint(80),
          isOnScreen: true,
          displayTime: observed,
          deliveryProvenance: provenance(
            streamMemberToken: "control-member",
            continuityToken: "control-continuity",
            sequence: nonce * 2 + UInt64(repeatIndex),
            callbackTime: observed
          )
        ),
        ManagedSlideShowRoleWindowEvidence(
          identity: managedIdentity(20),
          fingerprint: candidateFingerprint,
          isOnScreen: phaseValues.onScreen,
          displayTime: phaseValues.onScreen ? observed : nil,
          deliveryProvenance: phaseValues.onScreen
            ? provenance(
              streamMemberToken: "candidate-member",
              continuityToken: "candidate-continuity",
              sequence: nonce * 2 + UInt64(repeatIndex),
              callbackTime: observed
            )
            : nil
        ),
      ]
    )
  }

  private func values(
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
    streamMemberToken: String,
    continuityToken: String,
    sequence: UInt64,
    callbackTime: UInt64
  ) -> ManagedSlideShowRoleWindowDeliveryProvenance {
    ManagedSlideShowRoleWindowDeliveryProvenance(
      status: .generated,
      captureOperationID: 7,
      captureGeneration: 9,
      streamMemberToken: streamMemberToken,
      continuityToken: continuityToken,
      deliverySequence: sequence,
      callbackMachAbsoluteTime: callbackTime
    )
  }

  private func managedIdentity(_ windowID: Int) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }
}

private enum RoleChallengeClientCall: Equatable, Sendable {
  case visibility
  case pixelNonce
}

private actor ScriptedRoleChallengeClient: ManagedSlideShowRoleChallengeClient {
  private let visibility: ManagedSlideShowRoleChallengeClientResult
  private let pixel: ManagedSlideShowRoleChallengeClientResult
  private(set) var calls: [RoleChallengeClientCall] = []
  private(set) var challengeNonces: [UInt64] = []

  init(
    visibility: ManagedSlideShowRoleChallengeClientResult,
    pixel: ManagedSlideShowRoleChallengeClientResult
  ) {
    self.visibility = visibility
    self.pixel = pixel
  }

  func runVisibilityChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    calls.append(.visibility)
    challengeNonces.append(request.challengeNonce)
    return visibility
  }

  func runPixelNonceChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    calls.append(.pixelNonce)
    challengeNonces.append(request.challengeNonce)
    return pixel
  }
}

private actor ControllableRoleChallengeClient: ManagedSlideShowRoleChallengeClient {
  private var continuation:
    CheckedContinuation<ManagedSlideShowRoleChallengeClientResult, any Error>?
  private(set) var callCount = 0

  func runVisibilityChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    callCount += 1
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func runPixelNonceChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    callCount += 1
    return .unavailable
  }

  func resumeVisibility(with result: ManagedSlideShowRoleChallengeClientResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

extension Result where Failure == ManagedSlideShowRoleChallengeCoordinatorFailure {
  fileprivate var roleBinding: Success? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  fileprivate var roleFailure: Failure? {
    guard case .failure(let value) = self else { return nil }
    return value
  }
}

private func waitForRoleChallenge(
  maxYields: Int = 10_000,
  _ predicate: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<maxYields {
    if await predicate() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for deterministic role-challenge state")
}
