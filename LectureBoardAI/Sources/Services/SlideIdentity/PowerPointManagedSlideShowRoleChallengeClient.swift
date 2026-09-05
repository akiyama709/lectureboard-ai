import Foundation
import LectureBoardCore

enum PowerPointManagedSlideShowRoleCapability: Equatable, Sendable {
  case visibility
  case pixelNonce
}

enum PowerPointManagedSlideShowRoleCapabilityState: Equatable, Sendable {
  case available
  case unavailable
}

enum PowerPointManagedSlideShowRoleCommand: Equatable, Sendable {
  /// Establishes a post-reply boundary without changing the slide show.
  case establishBaseline
  case setVisibility(Bool)
  case setViewState(ManagedSlideShowRoleCurrentViewState)
}

/// Exact actor-owned PowerPoint object capability request.
///
/// A production bridge must resolve `slideShowObjectToken` to the object specifier retained by the
/// managed-start actor. Enumerating a new or sole slide-show object is not permitted.
struct PowerPointManagedSlideShowRoleCapabilityRequest: Equatable, Sendable {
  let bindingSessionToken: String
  let slideShowObjectToken: String
  let processIdentifier: Int
  let bundleIdentifier: String
  let challengeNonce: UInt64
  let capability: PowerPointManagedSlideShowRoleCapability
  let freshRequestToken: String
}

struct PowerPointManagedSlideShowRoleCapabilityReceipt: Equatable, Sendable {
  let request: PowerPointManagedSlideShowRoleCapabilityRequest
  let state: PowerPointManagedSlideShowRoleCapabilityState
}

struct PowerPointManagedSlideShowRoleCommandRequest: Equatable, Sendable {
  let bindingSessionToken: String
  let slideShowObjectToken: String
  let processIdentifier: Int
  let bundleIdentifier: String
  let challengeNonce: UInt64
  let phaseNonce: UInt64
  let command: PowerPointManagedSlideShowRoleCommand
  let freshRequestToken: String
}

struct PowerPointManagedSlideShowRoleCommandReceipt: Equatable, Sendable {
  let request: PowerPointManagedSlideShowRoleCommandRequest
  let repliedMachAbsoluteTime: UInt64
}

/// Narrow bridge to the actor that owns the managed-start object descriptor.
///
/// The Stage A actor supplies the system implementation and addresses only its retained exact
/// returned object. This protocol remains injected so role-challenge policy tests perform no
/// Apple Event. Keeping this boundary explicit prevents a later integration from reconstructing
/// the object by title, index, window order, or global enumeration.
protocol PowerPointManagedSlideShowRoleObjectCommanding: Sendable {
  func readCapability(
    _ request: PowerPointManagedSlideShowRoleCapabilityRequest
  ) async throws -> PowerPointManagedSlideShowRoleCapabilityReceipt

  func perform(
    _ request: PowerPointManagedSlideShowRoleCommandRequest
  ) async throws -> PowerPointManagedSlideShowRoleCommandReceipt
}

/// One request for a new composite inventory after an exact PowerPoint command reply.
///
/// A production implementation must subscribe to the already-owned ScreenCaptureKit operation;
/// it must not create a replacement stream. `minimumDisplayTimeExclusive` applies to newly
/// generated payloads. A verified idle callback may reuse an older display time only when its
/// anchored stream membership, continuity lineage, delivery sequence, and callback time pass.
struct PowerPointManagedSlideShowRoleFreshEvidenceRequest: Equatable, Sendable {
  let bindingSessionToken: String
  let slideShowObjectToken: String
  let processIdentifier: Int
  let bundleIdentifier: String
  let candidateWindowIdentity: ManagedSlideShowWindowIdentity
  let captureOperationID: UInt64
  let captureGeneration: UInt64
  let captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor
  let phase: ManagedSlideShowRoleChallengePhase
  let nonce: UInt64
  let minimumDisplayTimeExclusive: UInt64
  let requestStartedMachAbsoluteTime: UInt64
  let freshRequestToken: String
}

struct PowerPointManagedSlideShowRoleFreshEvidence: Equatable, Sendable {
  let freshRequestToken: String
  let observation: ManagedSlideShowRoleChallengeObservation
}

/// Composite exact-object semantic state and exact-stream frame inventory boundary.
///
/// This protocol is intentionally not conformed to by the current capture provider. The provider
/// does not yet publish a generation-bound, complete multi-window inventory to a role challenge.
/// Tests use fakes and therefore send no screen input, Apple Event, or ScreenCaptureKit request.
protocol PowerPointManagedSlideShowRoleFreshEvidenceReading: Sendable {
  func readFreshEvidence(
    _ request: PowerPointManagedSlideShowRoleFreshEvidenceRequest
  ) async throws -> PowerPointManagedSlideShowRoleFreshEvidence
}

protocol PowerPointManagedSlideShowRoleCleanupDeadlineWaiting: Sendable {
  func waitForDeadline() async
}

struct SystemPowerPointManagedSlideShowRoleCleanupDeadline:
  PowerPointManagedSlideShowRoleCleanupDeadlineWaiting
{
  func waitForDeadline() async {
    try? await Task.sleep(for: .seconds(3))
  }
}

private enum PowerPointManagedSlideShowRoleCleanupRaceOutcome: Sendable {
  case completed(Bool)
  case deadlineReached
}

private actor PowerPointManagedSlideShowRoleCleanupRace {
  private var outcome: PowerPointManagedSlideShowRoleCleanupRaceOutcome?
  private var continuation:
    CheckedContinuation<PowerPointManagedSlideShowRoleCleanupRaceOutcome, Never>?

  func wait() async -> PowerPointManagedSlideShowRoleCleanupRaceOutcome {
    if let outcome { return outcome }
    return await withCheckedContinuation { continuation = $0 }
  }

  func publish(_ newOutcome: PowerPointManagedSlideShowRoleCleanupRaceOutcome) {
    guard outcome == nil else { return }
    outcome = newOutcome
    continuation?.resume(returning: newOutcome)
    continuation = nil
  }
}

enum PowerPointManagedSlideShowRoleChallengeClientFailure:
  Error, Equatable, Sendable
{
  case malformedConfiguration
  case malformedRequest
  case staleSession
  case objectTokenMismatch
  case targetIdentityMismatch
  case captureOperationMismatch
  case captureGenerationMismatch
  case captureAnchorMismatch
  case challengeAlreadyConsumed
  case pixelFallbackNotAuthorized
  case pixelFallbackRequestMismatch
  case priorOperationStillDraining
  case cancelled
  case staleCompletion
  case capabilityCheckFailed
  case capabilityReceiptMismatch
  case commandFailed
  case commandReceiptMismatch
  case commandReplyTimeInvalid
  case localClockInvalid
  case freshCommandRequestTokenUnavailable
  case freshEvidenceRequestTokenUnavailable
  case freshEvidenceReadFailed
  case freshEvidenceReceiptMismatch
  case staleFreshEvidence
  case evidenceAcquisitionTimeOutOfBounds
  case evidenceTimeNotIncreasing
  case incompleteWindowInventory
  case malformedWindowInventory
  case windowFrameNotFresh
  case windowFrameTimeOutOfBounds
  case windowFrameTimeNotIncreasing
  case windowDeliveryProvenanceMalformed
  case unsupportedWindowDeliveryStatus
  case windowStreamMemberMismatch
  case windowContinuityMismatch
  case windowDeliverySequenceNotIncreasing
  case windowCallbackTimeStale
  case windowCallbackTimeNotIncreasing
  case windowCallbackTimeOutOfBounds
  case idleWindowPayloadChanged
  case candidateMutationRequiresGeneratedPayload
  case evidenceRejected(ManagedSlideShowRoleChallengeRejection)
  case restorationFailed
  case restorationTimedOut
}

/// Stage B production orchestration for a reversible exact-window role challenge.
///
/// This actor owns ordering, one-shot fallback, cancellation draining, restoration, and strict
/// provenance validation. External PowerPoint commands and capture inventories remain injected so
/// this adapter can be tested without sending Apple Events, requesting permission, or touching a
/// live ScreenCaptureKit stream.
actor PowerPointManagedSlideShowRoleChallengeClient:
  ManagedSlideShowRoleChallengeClient,
  ManagedSlideShowRoleChallengeDrainMonitoring
{
  private let expectedCandidate: ManagedSlideShowRuntimeCandidate
  private let expectedCaptureOperationID: CaptureOperationID
  private let expectedCaptureGeneration: UInt64
  private let expectedCaptureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor
  private let objectController: any PowerPointManagedSlideShowRoleObjectCommanding
  private let evidenceReader: any PowerPointManagedSlideShowRoleFreshEvidenceReading
  private let machClock: any ManagedSlideShowBindingMachClock
  private let commandRequestTokenFactory: @Sendable () -> String
  private let evidenceRequestTokenFactory: @Sendable () -> String
  private let cleanupDeadline: any PowerPointManagedSlideShowRoleCleanupDeadlineWaiting

  private var activeOperationToken: UUID?
  private var retainedCleanupOperationToken: UUID?
  private var retainedCleanupTask: Task<Void, Never>?
  private var drainContinuations: [CheckedContinuation<Void, Never>] = []
  private var visibilityAttempted = false
  private var challengeClosed = false
  private var pixelFallbackRequest: ManagedSlideShowRoleChallengeRequest?
  private var issuedCommandRequestTokens: Set<String> = []
  private var issuedEvidenceRequestTokens: Set<String> = []
  private var lastCommandReplyMachAbsoluteTime: UInt64 = 0
  private var lastEvidenceObservedMachAbsoluteTime: UInt64 = 0
  private var lastLocalClockMachAbsoluteTime: UInt64 = 0
  private var lastWindowEvidence: [Int: ManagedSlideShowRoleWindowEvidence] = [:]

  init(
    expectedCandidate: ManagedSlideShowRuntimeCandidate,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor,
    objectController: any PowerPointManagedSlideShowRoleObjectCommanding,
    evidenceReader: any PowerPointManagedSlideShowRoleFreshEvidenceReading,
    machClock: any ManagedSlideShowBindingMachClock =
      SystemManagedSlideShowBindingMachClock(),
    commandRequestTokenFactory: @escaping @Sendable () -> String = {
      UUID().uuidString
    },
    evidenceRequestTokenFactory: @escaping @Sendable () -> String = {
      UUID().uuidString
    },
    cleanupDeadline: any PowerPointManagedSlideShowRoleCleanupDeadlineWaiting =
      SystemPowerPointManagedSlideShowRoleCleanupDeadline()
  ) {
    self.expectedCandidate = expectedCandidate
    self.expectedCaptureOperationID = captureOperationID
    self.expectedCaptureGeneration = captureGeneration
    self.expectedCaptureAnchor = captureAnchor
    self.objectController = objectController
    self.evidenceReader = evidenceReader
    self.machClock = machClock
    self.commandRequestTokenFactory = commandRequestTokenFactory
    self.evidenceRequestTokenFactory = evidenceRequestTokenFactory
    self.cleanupDeadline = cleanupDeadline
  }

  func runVisibilityChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    try validate(request)
    guard !visibilityAttempted, !challengeClosed, pixelFallbackRequest == nil else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.challengeAlreadyConsumed
    }
    visibilityAttempted = true

    let capability = try await readCapability(
      .visibility,
      request: request,
      operationToken: operationToken
    )
    guard capability == .available else {
      pixelFallbackRequest = request
      return .unavailable
    }
    challengeClosed = true
    return .evidence(
      try await performVisibilityChallenge(request, operationToken: operationToken)
    )
  }

  func runPixelNonceChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    try validate(request)
    guard visibilityAttempted, !challengeClosed, let permitted = pixelFallbackRequest else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .pixelFallbackNotAuthorized
    }
    guard permitted == request else {
      pixelFallbackRequest = nil
      challengeClosed = true
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .pixelFallbackRequestMismatch
    }
    pixelFallbackRequest = nil
    challengeClosed = true

    let capability = try await readCapability(
      .pixelNonce,
      request: request,
      operationToken: operationToken
    )
    guard capability == .available else { return .unavailable }
    return .evidence(
      try await performPixelNonceChallenge(request, operationToken: operationToken)
    )
  }

  var hasUndrainedOperation: Bool { activeOperationToken != nil }

  func waitForCurrentOperationDrain() async {
    guard activeOperationToken != nil else { return }
    await withCheckedContinuation { drainContinuations.append($0) }
  }

  private func performVisibilityChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async throws -> [ManagedSlideShowRoleChallengeObservation] {
    var evidence: [ManagedSlideShowRoleChallengeObservation] = []
    var policy = try makeEvidencePolicy(request: request, method: .visibility)
    var visibilityMayNeedRestoration = false
    var baselineObservation: ManagedSlideShowRoleChallengeObservation?
    do {
      let baselineReply = try await performCommand(
        .establishBaseline,
        phaseNonce: request.challengeNonce,
        request: request,
        operationToken: operationToken
      )
      let baselineEvidence = try await readRepeatedEvidence(
        phase: .baseline,
        nonce: request.challengeNonce,
        commandReplyMachAbsoluteTime: baselineReply,
        request: request,
        operationToken: operationToken
      )
      try ingest(baselineEvidence, into: &policy)
      evidence += baselineEvidence
      baselineObservation = baselineEvidence.first

      visibilityMayNeedRestoration = true
      let hiddenNonce = request.challengeNonce + 1
      let hiddenReply = try await performCommand(
        .setVisibility(false),
        phaseNonce: hiddenNonce,
        request: request,
        operationToken: operationToken
      )
      let hiddenEvidence = try await readRepeatedEvidence(
        phase: .visibilityHidden,
        nonce: hiddenNonce,
        commandReplyMachAbsoluteTime: hiddenReply,
        request: request,
        operationToken: operationToken
      )
      try ingest(hiddenEvidence, into: &policy)
      evidence += hiddenEvidence

      let restoredNonce = request.challengeNonce + 2
      let restoredReply = try await performCommand(
        .setVisibility(true),
        phaseNonce: restoredNonce,
        request: request,
        operationToken: operationToken
      )
      let restoredEvidence = try await readRepeatedEvidence(
        phase: .visibilityRestored,
        nonce: restoredNonce,
        commandReplyMachAbsoluteTime: restoredReply,
        request: request,
        operationToken: operationToken
      )
      try ingest(restoredEvidence, into: &policy)
      try finish(policy: &policy)
      evidence += restoredEvidence
      visibilityMayNeedRestoration = false
      return evidence
    } catch {
      if visibilityMayNeedRestoration {
        guard let baselineObservation else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .restorationFailed
        }
        try await restore(
          .setVisibility(true),
          phaseNonce: request.challengeNonce + 2,
          evidencePhase: .visibilityRestored,
          baselineObservation: baselineObservation,
          request: request,
          operationToken: operationToken
        )
      }
      throw error
    }
  }

  private func performPixelNonceChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async throws -> [ManagedSlideShowRoleChallengeObservation] {
    var evidence: [ManagedSlideShowRoleChallengeObservation] = []
    var policy = try makeEvidencePolicy(request: request, method: .pixelNonce)
    var viewMayNeedRestoration = false
    var baselineObservation: ManagedSlideShowRoleChallengeObservation?
    do {
      let baselineReply = try await performCommand(
        .establishBaseline,
        phaseNonce: request.challengeNonce,
        request: request,
        operationToken: operationToken
      )
      let baselineEvidence = try await readRepeatedEvidence(
        phase: .baseline,
        nonce: request.challengeNonce,
        commandReplyMachAbsoluteTime: baselineReply,
        request: request,
        operationToken: operationToken
      )
      try ingest(baselineEvidence, into: &policy)
      evidence += baselineEvidence
      baselineObservation = baselineEvidence.first

      let challengePhases:
        [(
          phase: ManagedSlideShowRoleChallengePhase,
          state: ManagedSlideShowRoleCurrentViewState
        )] =
          request.challengeNonce.isMultiple(of: 2)
          ? [(.pixelBlack, .blackScreen), (.pixelWhite, .whiteScreen)]
          : [(.pixelWhite, .whiteScreen), (.pixelBlack, .blackScreen)]

      for (offset, challenge) in challengePhases.enumerated() {
        viewMayNeedRestoration = true
        let phaseNonce = request.challengeNonce + UInt64(offset + 1)
        let reply = try await performCommand(
          .setViewState(challenge.state),
          phaseNonce: phaseNonce,
          request: request,
          operationToken: operationToken
        )
        let phaseEvidence = try await readRepeatedEvidence(
          phase: challenge.phase,
          nonce: phaseNonce,
          commandReplyMachAbsoluteTime: reply,
          request: request,
          operationToken: operationToken
        )
        try ingest(phaseEvidence, into: &policy)
        evidence += phaseEvidence
      }

      let restoredNonce = request.challengeNonce + 3
      let restoredReply = try await performCommand(
        .setViewState(.running),
        phaseNonce: restoredNonce,
        request: request,
        operationToken: operationToken
      )
      let restoredEvidence = try await readRepeatedEvidence(
        phase: .pixelRunningRestored,
        nonce: restoredNonce,
        commandReplyMachAbsoluteTime: restoredReply,
        request: request,
        operationToken: operationToken
      )
      try ingest(restoredEvidence, into: &policy)
      try finish(policy: &policy)
      evidence += restoredEvidence
      viewMayNeedRestoration = false
      return evidence
    } catch {
      if viewMayNeedRestoration {
        guard let baselineObservation else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .restorationFailed
        }
        try await restore(
          .setViewState(.running),
          phaseNonce: request.challengeNonce + 3,
          evidencePhase: .pixelRunningRestored,
          baselineObservation: baselineObservation,
          request: request,
          operationToken: operationToken
        )
      }
      throw error
    }
  }

  private func readCapability(
    _ capability: PowerPointManagedSlideShowRoleCapability,
    request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async throws -> PowerPointManagedSlideShowRoleCapabilityState {
    let capabilityRequest = PowerPointManagedSlideShowRoleCapabilityRequest(
      bindingSessionToken: request.candidate.bindingSessionToken,
      slideShowObjectToken: request.candidate.slideShowObjectToken,
      processIdentifier: Int(request.candidate.candidateWindowIdentity.ownerProcessID),
      bundleIdentifier: request.candidate.candidateWindowIdentity.bundleIdentifier,
      challengeNonce: request.challengeNonce,
      capability: capability,
      freshRequestToken: try makeCommandRequestToken()
    )
    let receipt: PowerPointManagedSlideShowRoleCapabilityReceipt
    do {
      try checkOperation(operationToken)
      receipt = try await objectController.readCapability(capabilityRequest)
    } catch {
      try checkOperation(operationToken)
      if error is CancellationError {
        throw PowerPointManagedSlideShowRoleChallengeClientFailure.cancelled
      }
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.capabilityCheckFailed
    }
    try checkOperation(operationToken)
    guard receipt.request == capabilityRequest else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .capabilityReceiptMismatch
    }
    return receipt.state
  }

  private func performCommand(
    _ command: PowerPointManagedSlideShowRoleCommand,
    phaseNonce: UInt64,
    request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async throws -> UInt64 {
    let commandRequest = try makeCommandRequest(
      command,
      phaseNonce: phaseNonce,
      request: request
    )
    let requestStartedMachAbsoluteTime = try await beginClockBracket()
    try checkOperation(operationToken)
    let receipt: PowerPointManagedSlideShowRoleCommandReceipt
    do {
      receipt = try await objectController.perform(commandRequest)
    } catch {
      _ = try await finishClockBracket(
        startedAt: requestStartedMachAbsoluteTime
      )
      try checkOperation(operationToken)
      if error is CancellationError {
        throw PowerPointManagedSlideShowRoleChallengeClientFailure.cancelled
      }
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.commandFailed
    }
    let completionMachAbsoluteTime = try await finishClockBracket(
      startedAt: requestStartedMachAbsoluteTime
    )
    try checkOperation(operationToken)
    return try acceptCommandReceipt(
      receipt,
      expectedRequest: commandRequest,
      requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime,
      completionMachAbsoluteTime: completionMachAbsoluteTime
    )
  }

  /// Restoration deliberately does not inherit task cancellation. Once a mutation may have been
  /// delivered, cleanup must address the same opaque object and confirm two fresh restored
  /// observations. This actor returns a bounded failure at its own deadline but retains both the
  /// unstructured cleanup task and exact-object ownership until the underlying work really drains.
  /// The deadline cannot stop a noncooperative Apple Event or capture call, so production bridges
  /// must still impose their own finite I/O timeouts. Task groups are intentionally not used here:
  /// scope exit would wait forever for a noncooperative child.
  private func restore(
    _ command: PowerPointManagedSlideShowRoleCommand,
    phaseNonce: UInt64,
    evidencePhase: ManagedSlideShowRoleChallengePhase,
    baselineObservation: ManagedSlideShowRoleChallengeObservation,
    request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async throws {
    guard activeOperationToken == operationToken else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.restorationFailed
    }
    do {
      let commandRequest = try makeCommandRequest(
        command,
        phaseNonce: phaseNonce,
        request: request
      )
      let requestStartedMachAbsoluteTime = try await beginClockBracket()
      let race = PowerPointManagedSlideShowRoleCleanupRace()
      let client = self
      let cleanupTask = Task.detached {
        let succeeded = await client.performRetainedRestoration(
          commandRequest: commandRequest,
          requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime,
          evidencePhase: evidencePhase,
          phaseNonce: phaseNonce,
          baselineObservation: baselineObservation,
          request: request,
          operationToken: operationToken
        )
        await race.publish(.completed(succeeded))
        await client.cleanupDidDrain(operationToken: operationToken)
      }
      retainedCleanupOperationToken = operationToken
      retainedCleanupTask = cleanupTask
      let cleanupDeadline = self.cleanupDeadline
      let deadlineTask = Task.detached {
        await cleanupDeadline.waitForDeadline()
        await race.publish(.deadlineReached)
      }
      let outcome = await race.wait()
      deadlineTask.cancel()
      switch outcome {
      case .completed(true):
        return
      case .completed(false):
        throw PowerPointManagedSlideShowRoleChallengeClientFailure.restorationFailed
      case .deadlineReached:
        throw PowerPointManagedSlideShowRoleChallengeClientFailure.restorationTimedOut
      }
    } catch let failure as PowerPointManagedSlideShowRoleChallengeClientFailure {
      throw failure
    } catch {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.restorationFailed
    }
  }

  private func performRetainedRestoration(
    commandRequest: PowerPointManagedSlideShowRoleCommandRequest,
    requestStartedMachAbsoluteTime: UInt64,
    evidencePhase: ManagedSlideShowRoleChallengePhase,
    phaseNonce: UInt64,
    baselineObservation: ManagedSlideShowRoleChallengeObservation,
    request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async -> Bool {
    do {
      let receipt = try await objectController.perform(commandRequest)
      guard activeOperationToken == operationToken else { return false }
      let completionMachAbsoluteTime = try await finishClockBracket(
        startedAt: requestStartedMachAbsoluteTime
      )
      _ = try acceptCommandReceipt(
        receipt,
        expectedRequest: commandRequest,
        requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime,
        completionMachAbsoluteTime: completionMachAbsoluteTime
      )
      let restoredEvidence = try await readRepeatedEvidence(
        phase: evidencePhase,
        nonce: phaseNonce,
        commandReplyMachAbsoluteTime: receipt.repliedMachAbsoluteTime,
        request: request,
        operationToken: operationToken
      )
      return activeOperationToken == operationToken
        && restorationEvidence(restoredEvidence, matches: baselineObservation)
    } catch {
      return false
    }
  }

  private func cleanupDidDrain(operationToken: UUID) {
    guard retainedCleanupOperationToken == operationToken else { return }
    retainedCleanupOperationToken = nil
    retainedCleanupTask = nil
    guard activeOperationToken == operationToken else { return }
    activeOperationToken = nil
    resumeDrainContinuations()
  }

  private func makeCommandRequest(
    _ command: PowerPointManagedSlideShowRoleCommand,
    phaseNonce: UInt64,
    request: ManagedSlideShowRoleChallengeRequest
  ) throws -> PowerPointManagedSlideShowRoleCommandRequest {
    PowerPointManagedSlideShowRoleCommandRequest(
      bindingSessionToken: request.candidate.bindingSessionToken,
      slideShowObjectToken: request.candidate.slideShowObjectToken,
      processIdentifier: Int(request.candidate.candidateWindowIdentity.ownerProcessID),
      bundleIdentifier: request.candidate.candidateWindowIdentity.bundleIdentifier,
      challengeNonce: request.challengeNonce,
      phaseNonce: phaseNonce,
      command: command,
      freshRequestToken: try makeCommandRequestToken()
    )
  }

  private func acceptCommandReceipt(
    _ receipt: PowerPointManagedSlideShowRoleCommandReceipt,
    expectedRequest: PowerPointManagedSlideShowRoleCommandRequest,
    requestStartedMachAbsoluteTime: UInt64,
    completionMachAbsoluteTime: UInt64
  ) throws -> UInt64 {
    guard receipt.request == expectedRequest else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .commandReceiptMismatch
    }
    guard receipt.repliedMachAbsoluteTime > lastCommandReplyMachAbsoluteTime,
      receipt.repliedMachAbsoluteTime > lastEvidenceObservedMachAbsoluteTime,
      receipt.repliedMachAbsoluteTime >= requestStartedMachAbsoluteTime,
      receipt.repliedMachAbsoluteTime <= completionMachAbsoluteTime,
      receipt.repliedMachAbsoluteTime > 0
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .commandReplyTimeInvalid
    }
    lastCommandReplyMachAbsoluteTime = receipt.repliedMachAbsoluteTime
    return receipt.repliedMachAbsoluteTime
  }

  private func readRepeatedEvidence(
    phase: ManagedSlideShowRoleChallengePhase,
    nonce: UInt64,
    commandReplyMachAbsoluteTime: UInt64,
    request: ManagedSlideShowRoleChallengeRequest,
    operationToken: UUID
  ) async throws -> [ManagedSlideShowRoleChallengeObservation] {
    var observations: [ManagedSlideShowRoleChallengeObservation] = []
    for repeatIndex in 0..<2 {
      let requestStartedMachAbsoluteTime = try await beginClockBracket()
      guard requestStartedMachAbsoluteTime > commandReplyMachAbsoluteTime else {
        throw PowerPointManagedSlideShowRoleChallengeClientFailure
          .localClockInvalid
      }
      let freshRequest = PowerPointManagedSlideShowRoleFreshEvidenceRequest(
        bindingSessionToken: request.candidate.bindingSessionToken,
        slideShowObjectToken: request.candidate.slideShowObjectToken,
        processIdentifier: Int(request.candidate.candidateWindowIdentity.ownerProcessID),
        bundleIdentifier: request.candidate.candidateWindowIdentity.bundleIdentifier,
        candidateWindowIdentity: managedIdentity(for: request.candidate),
        captureOperationID: request.captureOperationID.rawValue,
        captureGeneration: request.captureGeneration,
        captureAnchor: request.captureAnchor,
        phase: phase,
        nonce: nonce,
        minimumDisplayTimeExclusive: commandReplyMachAbsoluteTime,
        requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime,
        freshRequestToken: try makeEvidenceRequestToken()
      )
      try checkOperation(operationToken)
      let result: PowerPointManagedSlideShowRoleFreshEvidence
      do {
        result = try await evidenceReader.readFreshEvidence(freshRequest)
      } catch {
        _ = try await finishClockBracket(
          startedAt: requestStartedMachAbsoluteTime
        )
        try checkOperation(operationToken)
        if error is CancellationError {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure.cancelled
        }
        throw PowerPointManagedSlideShowRoleChallengeClientFailure
          .freshEvidenceReadFailed
      }
      let completionMachAbsoluteTime = try await finishClockBracket(
        startedAt: requestStartedMachAbsoluteTime
      )
      try checkOperation(operationToken)
      observations.append(
        try acceptFreshEvidence(
          result,
          expectedRequest: freshRequest,
          completionMachAbsoluteTime: completionMachAbsoluteTime,
          isFirstObservationInPhase: repeatIndex == 0
        )
      )
    }
    return observations
  }

  private func acceptFreshEvidence(
    _ result: PowerPointManagedSlideShowRoleFreshEvidence,
    expectedRequest: PowerPointManagedSlideShowRoleFreshEvidenceRequest,
    completionMachAbsoluteTime: UInt64,
    isFirstObservationInPhase: Bool
  ) throws -> ManagedSlideShowRoleChallengeObservation {
    let observation = result.observation
    guard result.freshRequestToken == expectedRequest.freshRequestToken,
      observation.bindingSessionToken == expectedRequest.bindingSessionToken,
      observation.slideShowObjectToken == expectedRequest.slideShowObjectToken,
      observation.processIdentifier == expectedRequest.processIdentifier,
      observation.bundleIdentifier == expectedRequest.bundleIdentifier,
      observation.candidateWindowIdentity == expectedRequest.candidateWindowIdentity,
      observation.captureOperationID == expectedRequest.captureOperationID,
      observation.captureGeneration == expectedRequest.captureGeneration,
      observation.phase == expectedRequest.phase,
      observation.nonce == expectedRequest.nonce,
      observation.commandReplyMachAbsoluteTime
        == expectedRequest.minimumDisplayTimeExclusive
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .freshEvidenceReceiptMismatch
    }
    guard observation.inventoryIsComplete else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .incompleteWindowInventory
    }
    guard
      observation.evidenceObservedMachAbsoluteTime
        > expectedRequest.minimumDisplayTimeExclusive
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.staleFreshEvidence
    }
    guard
      observation.evidenceObservedMachAbsoluteTime
        > lastEvidenceObservedMachAbsoluteTime
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .evidenceTimeNotIncreasing
    }
    guard
      observation.evidenceObservedMachAbsoluteTime
        >= expectedRequest.requestStartedMachAbsoluteTime,
      observation.evidenceObservedMachAbsoluteTime <= completionMachAbsoluteTime
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .evidenceAcquisitionTimeOutOfBounds
    }

    let candidateMayBeAbsent = expectedRequest.phase == .visibilityHidden
    var seenWindowIDs: Set<Int> = []
    var seenStreamMemberTokens: Set<String> = []
    var currentWindowEvidence: [Int: ManagedSlideShowRoleWindowEvidence] = [:]
    var candidate: ManagedSlideShowRoleWindowEvidence?
    for window in observation.windows {
      let identity = window.identity
      guard identity.windowID > 0,
        identity.processIdentifier == expectedRequest.processIdentifier,
        identity.bundleIdentifier == expectedRequest.bundleIdentifier,
        seenWindowIDs.insert(identity.windowID).inserted
      else {
        throw PowerPointManagedSlideShowRoleChallengeClientFailure
          .malformedWindowInventory
      }
      if identity.windowID == expectedRequest.candidateWindowIdentity.windowID {
        guard identity == expectedRequest.candidateWindowIdentity else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .malformedWindowInventory
        }
        candidate = window
      }
      switch (window.fingerprint, window.displayTime, window.isOnScreen) {
      case (.some(let fingerprint), .some(let displayTime), true):
        guard fingerprint.isValid else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .malformedWindowInventory
        }
        guard let provenance = window.deliveryProvenance,
          let status = provenance.status,
          let captureOperationID = provenance.captureOperationID,
          let captureGeneration = provenance.captureGeneration,
          let streamMemberToken = provenance.streamMemberToken,
          let continuityToken = provenance.continuityToken,
          let deliverySequence = provenance.deliverySequence,
          let callbackMachAbsoluteTime = provenance.callbackMachAbsoluteTime,
          captureOperationID == expectedRequest.captureOperationID,
          captureGeneration == expectedRequest.captureGeneration,
          streamMemberToken == streamMemberToken.trimmingCharacters(in: .whitespacesAndNewlines),
          !streamMemberToken.isEmpty,
          continuityToken == continuityToken.trimmingCharacters(in: .whitespacesAndNewlines),
          !continuityToken.isEmpty,
          deliverySequence > 0,
          callbackMachAbsoluteTime > 0,
          displayTime > 0,
          displayTime <= callbackMachAbsoluteTime,
          seenStreamMemberTokens.insert(streamMemberToken).inserted
        else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .windowDeliveryProvenanceMalformed
        }
        guard status == .generated || status == .idle else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .unsupportedWindowDeliveryStatus
        }
        guard callbackMachAbsoluteTime > expectedRequest.minimumDisplayTimeExclusive else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .windowCallbackTimeStale
        }
        let previous = lastWindowEvidence[identity.windowID]
        if let previous {
          guard previous.deliveryProvenance?.streamMemberToken == streamMemberToken else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowStreamMemberMismatch
          }
          guard previous.deliveryProvenance?.continuityToken == continuityToken else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowContinuityMismatch
          }
          guard let previousSequence = previous.deliveryProvenance?.deliverySequence,
            deliverySequence > previousSequence
          else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowDeliverySequenceNotIncreasing
          }
          guard let previousCallback = previous.deliveryProvenance?.callbackMachAbsoluteTime,
            callbackMachAbsoluteTime > previousCallback
          else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowCallbackTimeNotIncreasing
          }
        } else if expectedRequest.phase != .baseline {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .windowContinuityMismatch
        }
        guard callbackMachAbsoluteTime >= expectedRequest.requestStartedMachAbsoluteTime,
          callbackMachAbsoluteTime <= completionMachAbsoluteTime,
          callbackMachAbsoluteTime <= observation.evidenceObservedMachAbsoluteTime
        else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .windowCallbackTimeOutOfBounds
        }

        let isCandidate = identity == expectedRequest.candidateWindowIdentity
        if isCandidate {
          guard streamMemberToken == expectedRequest.captureAnchor.candidateStreamMemberToken else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowStreamMemberMismatch
          }
          guard continuityToken == expectedRequest.captureAnchor.candidateContinuityToken else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowContinuityMismatch
          }
          guard
            deliverySequence
              > expectedRequest.captureAnchor.minimumCandidateDeliverySequenceExclusive
          else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowDeliverySequenceNotIncreasing
          }
          if isFirstObservationInPhase, expectedRequest.phase != .baseline,
            status != .generated
          {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .candidateMutationRequiresGeneratedPayload
          }
        }

        switch status {
        case .generated:
          guard displayTime > expectedRequest.minimumDisplayTimeExclusive else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowFrameNotFresh
          }
          if let previousDisplayTime = previous?.displayTime,
            displayTime <= previousDisplayTime
          {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowFrameTimeNotIncreasing
          }
          guard displayTime >= expectedRequest.requestStartedMachAbsoluteTime,
            displayTime <= completionMachAbsoluteTime
          else {
            throw PowerPointManagedSlideShowRoleChallengeClientFailure
              .windowFrameTimeOutOfBounds
          }
        case .idle:
          if let previous {
            guard previous.fingerprint == fingerprint,
              previous.displayTime == displayTime,
              previous.isOnScreen == window.isOnScreen
            else {
              throw PowerPointManagedSlideShowRoleChallengeClientFailure
                .idleWindowPayloadChanged
            }
          }
        case .blank, .suspended, .stopped:
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .unsupportedWindowDeliveryStatus
        }
        currentWindowEvidence[identity.windowID] = window
      case (.none, .none, false):
        guard window.deliveryProvenance == nil else {
          throw PowerPointManagedSlideShowRoleChallengeClientFailure
            .windowDeliveryProvenanceMalformed
        }
        break
      default:
        throw PowerPointManagedSlideShowRoleChallengeClientFailure
          .malformedWindowInventory
      }
    }
    guard candidate != nil || candidateMayBeAbsent else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .malformedWindowInventory
    }
    guard observation.candidateDisplayTime == candidate?.displayTime else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .freshEvidenceReceiptMismatch
    }

    lastEvidenceObservedMachAbsoluteTime = observation.evidenceObservedMachAbsoluteTime
    lastWindowEvidence.merge(currentWindowEvidence) { _, current in current }
    return observation
  }

  private func makeEvidencePolicy(
    request: ManagedSlideShowRoleChallengeRequest,
    method: ManagedSlideShowRoleChallengeMethod
  ) throws -> ManagedSlideShowRoleChallengePolicy {
    let identity = request.candidate.candidateWindowIdentity
    let target = ManagedSlideShowRoleChallengeTarget(
      bindingSessionToken: request.candidate.bindingSessionToken,
      slideShowObjectToken: request.candidate.slideShowObjectToken,
      processIdentifier: Int(identity.ownerProcessID),
      bundleIdentifier: identity.bundleIdentifier,
      candidateWindowIdentity: managedIdentity(for: request.candidate),
      captureOperationID: request.captureOperationID.rawValue,
      captureGeneration: request.captureGeneration,
      candidateStreamMemberToken: request.captureAnchor.candidateStreamMemberToken,
      candidateContinuityToken: request.captureAnchor.candidateContinuityToken,
      minimumCandidateDeliverySequenceExclusive:
        request.captureAnchor.minimumCandidateDeliverySequenceExclusive,
      challengeNonce: request.challengeNonce
    )
    var policy = ManagedSlideShowRoleChallengePolicy()
    guard case .started = policy.begin(target: target, method: method) else {
      throw
        PowerPointManagedSlideShowRoleChallengeClientFailure
        .evidenceRejected(.malformedTarget)
    }
    return policy
  }

  private func ingest(
    _ observations: [ManagedSlideShowRoleChallengeObservation],
    into policy: inout ManagedSlideShowRoleChallengePolicy
  ) throws {
    for observation in observations {
      if case .rejected(let rejection) = policy.ingest(observation) {
        throw
          PowerPointManagedSlideShowRoleChallengeClientFailure
          .evidenceRejected(rejection)
      }
    }
  }

  private func finish(policy: inout ManagedSlideShowRoleChallengePolicy) throws {
    switch policy.finish() {
    case .succeeded:
      return
    case .rejected(let rejection):
      throw
        PowerPointManagedSlideShowRoleChallengeClientFailure
        .evidenceRejected(rejection)
    default:
      throw
        PowerPointManagedSlideShowRoleChallengeClientFailure
        .evidenceRejected(.incompleteChallenge)
    }
  }

  private func restorationEvidence(
    _ observations: [ManagedSlideShowRoleChallengeObservation],
    matches baseline: ManagedSlideShowRoleChallengeObservation
  ) -> Bool {
    guard observations.count == 2,
      let first = observations.first,
      first.semanticState == baseline.semanticState,
      observations.allSatisfy({ $0.semanticState == baseline.semanticState }),
      restorationInventory(first.windows, matches: baseline.windows),
      observations.allSatisfy({ restorationInventory($0.windows, matches: first.windows) })
    else {
      return false
    }
    return true
  }

  private func restorationInventory(
    _ candidate: [ManagedSlideShowRoleWindowEvidence],
    matches reference: [ManagedSlideShowRoleWindowEvidence]
  ) -> Bool {
    guard candidate.count == reference.count else { return false }
    return reference.allSatisfy { expected in
      candidate.first(where: { $0.identity == expected.identity }).map {
        $0.fingerprint == expected.fingerprint
          && $0.isOnScreen == expected.isOnScreen
      } == true
    }
  }

  private func beginClockBracket() async throws -> UInt64 {
    let value = await machClock.now()
    guard value > 0, value > lastLocalClockMachAbsoluteTime else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.localClockInvalid
    }
    return value
  }

  private func finishClockBracket(startedAt: UInt64) async throws -> UInt64 {
    let value = await machClock.now()
    guard value > startedAt, value > lastLocalClockMachAbsoluteTime else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.localClockInvalid
    }
    lastLocalClockMachAbsoluteTime = value
    return value
  }

  private func validateConfiguration() throws {
    let identity = expectedCandidate.candidateWindowIdentity
    guard identity.windowID > 0, identity.ownerProcessID > 0,
      identity.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier,
      !expectedCandidate.bindingSessionToken
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !expectedCandidate.slideShowObjectToken
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      expectedCaptureOperationID.rawValue > 0, expectedCaptureGeneration > 0,
      expectedCaptureAnchor.candidateStreamMemberToken
        == expectedCaptureAnchor.candidateStreamMemberToken
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !expectedCaptureAnchor.candidateStreamMemberToken.isEmpty,
      expectedCaptureAnchor.candidateContinuityToken
        == expectedCaptureAnchor.candidateContinuityToken
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !expectedCaptureAnchor.candidateContinuityToken.isEmpty,
      expectedCaptureAnchor.minimumCandidateDeliverySequenceExclusive > 0,
      expectedCaptureAnchor.minimumCandidateDeliverySequenceExclusive < UInt64.max
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .malformedConfiguration
    }
  }

  private func validate(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) throws {
    let identity = request.candidate.candidateWindowIdentity
    guard identity.windowID > 0, identity.ownerProcessID > 0,
      identity.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier,
      !request.candidate.bindingSessionToken
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !request.candidate.slideShowObjectToken
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      request.captureOperationID.rawValue > 0, request.captureGeneration > 0,
      request.challengeNonce > 0, request.challengeNonce <= UInt64.max - 3
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.malformedRequest
    }
    guard
      request.candidate.bindingSessionToken
        == expectedCandidate.bindingSessionToken
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.staleSession
    }
    guard
      request.candidate.slideShowObjectToken
        == expectedCandidate.slideShowObjectToken
    else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .objectTokenMismatch
    }
    guard identity == expectedCandidate.candidateWindowIdentity else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .targetIdentityMismatch
    }
    guard request.captureOperationID == expectedCaptureOperationID else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .captureOperationMismatch
    }
    guard request.captureGeneration == expectedCaptureGeneration else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .captureGenerationMismatch
    }
    guard request.captureAnchor == expectedCaptureAnchor else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .captureAnchorMismatch
    }
  }

  private func managedIdentity(
    for candidate: ManagedSlideShowRuntimeCandidate
  ) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: Int(candidate.candidateWindowIdentity.windowID),
      processIdentifier: Int(candidate.candidateWindowIdentity.ownerProcessID),
      bundleIdentifier: candidate.candidateWindowIdentity.bundleIdentifier
    )
  }

  private func makeCommandRequestToken() throws -> String {
    let token = commandRequestTokenFactory()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, issuedCommandRequestTokens.insert(token).inserted else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .freshCommandRequestTokenUnavailable
    }
    return token
  }

  private func makeEvidenceRequestToken() throws -> String {
    let token = evidenceRequestTokenFactory()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, issuedEvidenceRequestTokens.insert(token).inserted else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .freshEvidenceRequestTokenUnavailable
    }
    return token
  }

  private func beginOperation() throws -> UUID {
    guard activeOperationToken == nil else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure
        .priorOperationStillDraining
    }
    guard !Task.isCancelled else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.cancelled
    }
    let token = UUID()
    activeOperationToken = token
    return token
  }

  private func checkOperation(_ token: UUID) throws {
    guard activeOperationToken == token else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.staleCompletion
    }
    guard !Task.isCancelled else {
      throw PowerPointManagedSlideShowRoleChallengeClientFailure.cancelled
    }
  }

  private func finishOperation(_ token: UUID) {
    guard activeOperationToken == token else { return }
    guard retainedCleanupOperationToken != token else { return }
    activeOperationToken = nil
    resumeDrainContinuations()
  }

  private func resumeDrainContinuations() {
    let continuations = drainContinuations
    drainContinuations.removeAll()
    for continuation in continuations { continuation.resume() }
  }
}
