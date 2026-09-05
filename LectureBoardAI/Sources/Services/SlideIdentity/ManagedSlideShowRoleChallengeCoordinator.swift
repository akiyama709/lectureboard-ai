import Foundation
import LectureBoardCore

/// Runtime-only semantic binding minted only after this file's role challenge succeeds.
///
/// Keeping the initializer file-private makes it impossible for a reader, provider, or
/// unrelated module code to promote a window candidate directly. The immutable value can
/// be inspected after promotion but can be created only by the coordinator below.
struct ManagedSlideShowRuntimeBinding: Equatable, Sendable {
  let windowIdentity: PowerPointWindowIdentity
  let bindingSessionToken: String
  let slideShowObjectToken: String
  let captureOperationID: CaptureOperationID
  let captureGeneration: UInt64
  let freshnessBoundaryMachAbsoluteTime: UInt64

  fileprivate init?(
    windowIdentity: PowerPointWindowIdentity,
    bindingSessionToken: String,
    slideShowObjectToken: String,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    freshnessBoundaryMachAbsoluteTime: UInt64
  ) {
    guard
      !bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !slideShowObjectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      captureOperationID.rawValue > 0,
      captureGeneration > 0,
      freshnessBoundaryMachAbsoluteTime > 0
    else {
      return nil
    }

    self.windowIdentity = windowIdentity
    self.bindingSessionToken = bindingSessionToken
    self.slideShowObjectToken = slideShowObjectToken
    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.freshnessBoundaryMachAbsoluteTime = freshnessBoundaryMachAbsoluteTime
  }
}

struct ManagedSlideShowRoleChallengeRequest: Equatable, Sendable {
  let candidate: ManagedSlideShowRuntimeCandidate
  let captureOperationID: CaptureOperationID
  let captureGeneration: UInt64
  let captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor
  let challengeNonce: UInt64
}

/// Capture-actor-minted state owned before a role challenge starts.
///
/// This prevents the evidence reader from satisfying a baseline idle observation by latching an
/// arbitrary replacement stream only after the PowerPoint command has been sent.
struct ManagedSlideShowRoleChallengeCaptureAnchor: Equatable, Sendable {
  let candidateStreamMemberToken: String
  let candidateContinuityToken: String
  let minimumCandidateDeliverySequenceExclusive: UInt64
}

enum ManagedSlideShowRoleChallengeClientResult: Equatable, Sendable {
  case unavailable
  case evidence([ManagedSlideShowRoleChallengeObservation])
}

/// Injected boundary for a future actor-isolated PowerPoint and ScreenCaptureKit adapter.
///
/// The live client must address the object retained under the candidate's opaque object token.
/// Visibility hide/show is attempted first. Pixel nonce commands are requested only when that
/// capability reports `.unavailable`; a failed or contradictory visibility attempt is not retried
/// through the pixel path. This protocol itself performs no external operation.
protocol ManagedSlideShowRoleChallengeClient: Sendable {
  func runVisibilityChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult

  func runPixelNonceChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult
}

/// Optional lifecycle surface implemented by clients which can return from a bounded
/// restoration deadline while an exact-object cleanup is still in flight.  A caller must not
/// replace the client or release the exact Stage-A object until this drain has completed.
protocol ManagedSlideShowRoleChallengeDrainMonitoring: Sendable {
  var hasUndrainedOperation: Bool { get async }
  func waitForCurrentOperationDrain() async
}

enum ManagedSlideShowRoleChallengeCoordinatorFailure: Error, Equatable, Sendable {
  case malformedRequest
  case clientFailed
  case visibilityUnavailableAndPixelUnavailable
  case cancelled
  case priorAttemptStillDraining
  case staleCompletion
  case bindingConstructionFailed
  case unexpectedEvidenceCount
  case policyRejected(ManagedSlideShowRoleChallengeRejection)
}

/// Promotes a runtime candidate only after one injected role challenge passes the Core policy.
///
/// At most one client task is retained. A second request is rejected while prior work is blocked,
/// including after cancellation, so a noncooperative client cannot create a replacement chain.
/// Passing deterministic injected evidence is not a live PowerPoint or capture verification claim.
actor ManagedSlideShowRoleChallengeCoordinator {
  typealias ChallengeResult = Result<
    ManagedSlideShowRuntimeBinding,
    ManagedSlideShowRoleChallengeCoordinatorFailure
  >

  private let client: any ManagedSlideShowRoleChallengeClient
  private let nonceGenerator: @Sendable () -> UInt64
  private var activeTask: Task<ChallengeResult, Never>?
  private var activeAttemptToken: UUID?
  private var activeInvalidation: ManagedSlideShowRoleChallengeCoordinatorFailure?
  private var retainedClientDrainTask: Task<Void, Never>?

  init(
    client: any ManagedSlideShowRoleChallengeClient,
    nonceGenerator: @escaping @Sendable () -> UInt64 = {
      let uuidDerived = UInt64(bitPattern: Int64(UUID().hashValue))
      return uuidDerived == 0 ? 1 : uuidDerived
    }
  ) {
    self.client = client
    self.nonceGenerator = nonceGenerator
  }

  func challenge(
    candidate: ManagedSlideShowRuntimeCandidate,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ChallengeResult {
    guard activeTask == nil else { return .failure(.priorAttemptStillDraining) }
    guard captureOperationID.rawValue > 0, captureGeneration > 0,
      !candidate.bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !candidate.slideShowObjectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      captureAnchor.candidateStreamMemberToken
        == captureAnchor.candidateStreamMemberToken
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !captureAnchor.candidateStreamMemberToken.isEmpty,
      captureAnchor.candidateContinuityToken
        == captureAnchor.candidateContinuityToken
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !captureAnchor.candidateContinuityToken.isEmpty,
      captureAnchor.minimumCandidateDeliverySequenceExclusive > 0,
      captureAnchor.minimumCandidateDeliverySequenceExclusive < UInt64.max
    else {
      return .failure(.malformedRequest)
    }

    let challengeNonce = nonceGenerator()
    guard challengeNonce > 0, challengeNonce <= UInt64.max - 3 else {
      return .failure(.malformedRequest)
    }
    let request = ManagedSlideShowRoleChallengeRequest(
      candidate: candidate,
      captureOperationID: captureOperationID,
      captureGeneration: captureGeneration,
      captureAnchor: captureAnchor,
      challengeNonce: challengeNonce
    )
    let attemptToken = UUID()
    activeAttemptToken = attemptToken
    activeInvalidation = nil
    let client = self.client
    let task = Task<ChallengeResult, Never> {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      return await Self.perform(request: request, client: client)
    }
    activeTask = task

    let result = await task.value
    return await finish(result, attemptToken: attemptToken)
  }

  func cancelCurrentAttempt() {
    guard activeTask != nil else { return }
    if activeInvalidation == nil { activeInvalidation = .cancelled }
    activeTask?.cancel()
  }

  /// This is deliberately separate from cancellation.  Cancellation is bounded, whereas this
  /// await is used only by owners which have elected to retain the transaction until the exact
  /// object's restoration has actually drained.
  func waitForDrain() async {
    if let activeTask { _ = await activeTask.value }
    if let retainedClientDrainTask { await retainedClientDrainTask.value }
  }

  var isDrained: Bool {
    get async { activeTask == nil && retainedClientDrainTask == nil }
  }

  private func finish(
    _ result: ChallengeResult,
    attemptToken: UUID
  ) async -> ChallengeResult {
    let invalidation = activeInvalidation
    let isCurrent = activeAttemptToken == attemptToken
    guard isCurrent else {
      activeTask = nil
      activeAttemptToken = nil
      activeInvalidation = nil
      return .failure(.staleCompletion)
    }
    if let drainMonitor = client as? any ManagedSlideShowRoleChallengeDrainMonitoring,
      await drainMonitor.hasUndrainedOperation
    {
      // Retaining the completed task is intentional: it rejects replacement challenges until
      // the client reports that its detached exact-object restoration has actually drained.
      let coordinator = self
      retainedClientDrainTask = Task {
        await drainMonitor.waitForCurrentOperationDrain()
        await coordinator.clientDrainDidComplete(attemptToken: attemptToken)
      }
      if let invalidation { return .failure(invalidation) }
      return result
    }
    activeTask = nil
    activeAttemptToken = nil
    activeInvalidation = nil
    if let invalidation { return .failure(invalidation) }
    return result
  }

  private func clientDrainDidComplete(attemptToken: UUID) {
    guard activeAttemptToken == attemptToken else { return }
    retainedClientDrainTask = nil
    activeTask = nil
    activeAttemptToken = nil
    activeInvalidation = nil
  }

  private static func perform(
    request: ManagedSlideShowRoleChallengeRequest,
    client: any ManagedSlideShowRoleChallengeClient
  ) async -> ChallengeResult {
    let method: ManagedSlideShowRoleChallengeMethod
    let observations: [ManagedSlideShowRoleChallengeObservation]
    do {
      switch try await client.runVisibilityChallenge(request) {
      case .evidence(let evidence):
        method = .visibility
        observations = evidence
      case .unavailable:
        guard !Task.isCancelled else { return .failure(.cancelled) }
        switch try await client.runPixelNonceChallenge(request) {
        case .evidence(let evidence):
          method = .pixelNonce
          observations = evidence
        case .unavailable:
          return .failure(.visibilityUnavailableAndPixelUnavailable)
        }
      }
    } catch {
      if error is CancellationError || Task.isCancelled { return .failure(.cancelled) }
      return .failure(.clientFailed)
    }
    guard !Task.isCancelled else { return .failure(.cancelled) }
    let expectedCount = method == .visibility ? 6 : 8
    guard observations.count == expectedCount else {
      return .failure(.unexpectedEvidenceCount)
    }

    let identity = request.candidate.candidateWindowIdentity
    let target = ManagedSlideShowRoleChallengeTarget(
      bindingSessionToken: request.candidate.bindingSessionToken,
      slideShowObjectToken: request.candidate.slideShowObjectToken,
      processIdentifier: Int(identity.ownerProcessID),
      bundleIdentifier: identity.bundleIdentifier,
      candidateWindowIdentity: ManagedSlideShowWindowIdentity(
        windowID: Int(identity.windowID),
        processIdentifier: Int(identity.ownerProcessID),
        bundleIdentifier: identity.bundleIdentifier
      ),
      captureOperationID: request.captureOperationID.rawValue,
      captureGeneration: request.captureGeneration,
      candidateStreamMemberToken: request.captureAnchor.candidateStreamMemberToken,
      candidateContinuityToken: request.captureAnchor.candidateContinuityToken,
      minimumCandidateDeliverySequenceExclusive:
        request.captureAnchor.minimumCandidateDeliverySequenceExclusive,
      challengeNonce: request.challengeNonce
    )
    var policy = ManagedSlideShowRoleChallengePolicy()
    switch policy.begin(target: target, method: method) {
    case .started:
      break
    case .rejected(let rejection):
      return .failure(.policyRejected(rejection))
    default:
      return .failure(.policyRejected(.notStarted))
    }
    for observation in observations {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      if case .rejected(let rejection) = policy.ingest(observation) {
        return .failure(.policyRejected(rejection))
      }
    }
    let freshnessBoundary: UInt64
    switch policy.finish() {
    case .succeeded(let time):
      freshnessBoundary = time
    case .rejected(let rejection):
      return .failure(.policyRejected(rejection))
    default:
      return .failure(.policyRejected(.incompleteChallenge))
    }

    guard
      let binding = ManagedSlideShowRuntimeBinding(
        windowIdentity: identity,
        bindingSessionToken: request.candidate.bindingSessionToken,
        slideShowObjectToken: request.candidate.slideShowObjectToken,
        captureOperationID: request.captureOperationID,
        captureGeneration: request.captureGeneration,
        freshnessBoundaryMachAbsoluteTime: freshnessBoundary
      )
    else {
      return .failure(.bindingConstructionFailed)
    }
    return .success(binding)
  }
}
