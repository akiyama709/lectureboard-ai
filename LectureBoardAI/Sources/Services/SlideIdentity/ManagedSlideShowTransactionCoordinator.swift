import Foundation
import LectureBoardCore

/// The capture boundary used by the managed start transaction.  Its production implementation
/// starts one stream and returns the lease created from that stream's retained `SCWindow`; it
/// never performs a second ID-based selection after Stage A has produced its candidate.
protocol ManagedSlideShowTransactionCaptureLease: Sendable {
  var captureOperationID: CaptureOperationID { get }
  var captureGeneration: UInt64 { get }
  func captureAnchor() async throws -> ManagedSlideShowRoleChallengeCaptureAnchor
}

extension PowerPointManagedSlideShowRoleCaptureEvidenceLease:
  ManagedSlideShowTransactionCaptureLease
{}

protocol ManagedSlideShowTransactionCapturing: Sendable {
  func startCapture(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws -> any ManagedSlideShowTransactionCaptureLease

  func stopCapture(operationID: CaptureOperationID) async
}

/// Adapter intentionally keeps the lease lookup beside the capture start.  The lease is made
/// from the exact `SCWindow` retained by `PowerPointWindowCapture.start`; callers receive no
/// numeric-ID lookup surface.
actor PowerPointManagedSlideShowTransactionCapture:
  ManagedSlideShowTransactionCapturing
{
  private let capture: any PowerPointWindowCapturing

  init(capture: any PowerPointWindowCapturing = PowerPointWindowCapture()) {
    self.capture = capture
  }

  func startCapture(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws -> any ManagedSlideShowTransactionCaptureLease {
    do {
      try await capture.start(
        operationID: operationID,
        identity: identity,
        onFrame: onFrame,
        onContentUnavailable: onContentUnavailable,
        onFailure: onFailure
      )
      return try await capture.managedSlideShowRoleCaptureEvidenceLease(
        operationID: operationID
      )
    } catch {
      await capture.stop(operationID: operationID)
      throw error
    }
  }

  func stopCapture(operationID: CaptureOperationID) async {
    await capture.stop(operationID: operationID)
  }
}

protocol ManagedSlideShowTransactionIdentityProviding: Sendable {
  func startIdentity(
    operationID: CaptureOperationID,
    captureGeneration: UInt64,
    binding: ManagedSlideShowRuntimeBinding,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async -> ExactPowerPointSlideIdentityProviderStartResult
  func stopIdentity(operationID: CaptureOperationID) async
}

protocol ManagedSlideShowTransactionCandidateCorrelating: Sendable {
  func correlateCandidate(
    for frozenWindowIdentity: PowerPointWindowIdentity
  ) async -> ManagedSlideShowBindingCoordinator.CandidateResult
  func cancelCurrentAttempt() async
}

extension ManagedSlideShowBindingCoordinator:
  ManagedSlideShowTransactionCandidateCorrelating
{}

protocol ManagedSlideShowTransactionRoleChallenging: Sendable {
  func challenge(
    candidate: ManagedSlideShowRuntimeCandidate,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ManagedSlideShowRoleChallengeCoordinator.ChallengeResult
  func requestCancellation() async
  func waitForDrain() async
  var isDrained: Bool { get async }
}

extension ManagedSlideShowRoleChallengeCoordinator: ManagedSlideShowTransactionRoleChallenging {
  func requestCancellation() async {
    cancelCurrentAttempt()
  }
}

/// Converts the transaction's deliberately narrow capture lease into the concrete production
/// evidence lease without allowing a mismatched adapter to crash the application.  Tests can
/// inject a different lease type; production assembly must fail closed if that ever happens.
enum ManagedSlideShowTransactionRoleChallengeAssembly {
  static func make(
    lease: any ManagedSlideShowTransactionCaptureLease,
    builder:
      @Sendable (
        PowerPointManagedSlideShowRoleCaptureEvidenceLease
      ) -> any ManagedSlideShowTransactionRoleChallenging
  ) -> any ManagedSlideShowTransactionRoleChallenging {
    guard let evidenceLease = lease as? PowerPointManagedSlideShowRoleCaptureEvidenceLease else {
      return RejectedManagedSlideShowTransactionRoleChallenge()
    }
    return builder(evidenceLease)
  }
}

private actor RejectedManagedSlideShowTransactionRoleChallenge:
  ManagedSlideShowTransactionRoleChallenging
{
  func challenge(
    candidate _: ManagedSlideShowRuntimeCandidate,
    captureOperationID _: CaptureOperationID,
    captureGeneration _: UInt64,
    captureAnchor _: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ManagedSlideShowRoleChallengeCoordinator.ChallengeResult {
    .failure(.clientFailed)
  }

  func requestCancellation() async {}
  func waitForDrain() async {}
  var isDrained: Bool { true }
}

extension ExactPowerPointSlideIdentityProvider: ManagedSlideShowTransactionIdentityProviding {
  func startIdentity(
    operationID: CaptureOperationID,
    captureGeneration: UInt64,
    binding: ManagedSlideShowRuntimeBinding,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async -> ExactPowerPointSlideIdentityProviderStartResult {
    await start(
      operationID: operationID,
      currentCaptureGeneration: captureGeneration,
      binding: binding,
      onObservation: onObservation
    )
  }

  func stopIdentity(operationID: CaptureOperationID) async {
    await stop(operationID: operationID)
  }
}

protocol ManagedSlideShowTransactionExactObjectRecovering: Sendable {
  func exitRetainedSlideShowObject(_ receipt: ManagedSlideShowStartReceipt) async throws
  func releaseRetainedSlideShowObject(_ receipt: ManagedSlideShowStartReceipt) async -> Bool
  func cancelCurrentOperation()
}

protocol ManagedSlideShowTransactionPermissionRequesting: Sendable {
  func requestFromExplicitUserAction(
    target: PowerPointAutomationPermissionTarget
  ) async -> PowerPointAutomationPermissionState
}

extension PowerPointAutomationPermissionService:
  ManagedSlideShowTransactionPermissionRequesting
{}

extension PowerPointManagedSlideShowAppleEventClient:
  ManagedSlideShowTransactionExactObjectRecovering
{}

enum ManagedSlideShowTransactionFailure: Error, Equatable, Sendable {
  case alreadyActiveOrDraining
  case automationPermissionDenied
  case cancelled
  case stageAFailed
  case captureStartFailed
  case captureAnchorFailed
  case stageBFailed
  case bindingActivationRejected
  case identityProviderRejected
  case staleCompletion
}

enum ManagedSlideShowTransactionState: Equatable, Sendable {
  case idle
  case starting
  case active
  case draining
  case failed(ManagedSlideShowTransactionFailure)
}

/// Owns the one explicit managed-start action from candidate creation through semantic polling.
/// All unsuccessful paths stop the retained stream, stop semantic polling, then address only the
/// exact descriptor returned by the single Stage-A start command.  It intentionally has no
/// passive launch, refresh, or permission request API.
actor ManagedSlideShowTransactionCoordinator {
  typealias Result = Swift.Result<
    ManagedSlideShowRuntimeBinding, ManagedSlideShowTransactionFailure
  >

  private let sessionContext: ManagedSlideShowSessionContext
  private let stageA: any ManagedSlideShowTransactionCandidateCorrelating
  private let makeStageB:
    @Sendable (
      ManagedSlideShowRuntimeCandidate,
      any ManagedSlideShowTransactionCaptureLease,
      ManagedSlideShowRoleChallengeCaptureAnchor
    ) -> any ManagedSlideShowTransactionRoleChallenging
  private let capture: any ManagedSlideShowTransactionCapturing
  private let identityProvider: any ManagedSlideShowTransactionIdentityProviding
  private let exactObject: any ManagedSlideShowTransactionExactObjectRecovering
  private let permissionRequester: any ManagedSlideShowTransactionPermissionRequesting
  private let beforeFinishingStart: @Sendable () async -> Void

  private var state: ManagedSlideShowTransactionState = .idle
  private var task: Task<Result, Never>?
  private var token: UUID?
  private var stopTask: Task<Bool, Never>?
  private var stopAttempt: UUID?
  private var stopWaiterCount = 0
  private var stopRequestedAttempt: UUID?
  private var activeOperationID: CaptureOperationID?
  private var acceptedReceipt: ManagedSlideShowStartReceipt?
  private var activeRoleChallenge: (any ManagedSlideShowTransactionRoleChallenging)?
  // A bounded Stage-B restoration failure is not permission to release this receipt.  These
  // retained values deliberately form a temporary ownership cycle which is broken only after
  // the Stage-B client reports its detached restoration has actually drained.
  private var pendingExactObjectDrain: Task<Void, Never>?
  private var pendingDrainAttempt: UUID?
  private var pendingDrainFailure: ManagedSlideShowTransactionFailure?
  // Every exact-object exit is single-flight.  An uncertain/failed exit keeps both the receipt
  // and its concrete client alive so a later explicit stop (including a repeated application
  // termination request) can retry the same descriptor instead of silently abandoning it.
  private var exactObjectCleanupTask: Task<Bool, Never>?
  private var exactObjectCleanupAttempt: UUID?

  init(
    sessionContext: ManagedSlideShowSessionContext,
    stageA: any ManagedSlideShowTransactionCandidateCorrelating,
    makeStageB:
      @escaping @Sendable (
        ManagedSlideShowRuntimeCandidate,
        any ManagedSlideShowTransactionCaptureLease,
        ManagedSlideShowRoleChallengeCaptureAnchor
      ) -> any ManagedSlideShowTransactionRoleChallenging,
    capture: any ManagedSlideShowTransactionCapturing,
    identityProvider: any ManagedSlideShowTransactionIdentityProviding,
    exactObject: any ManagedSlideShowTransactionExactObjectRecovering,
    permissionRequester: any ManagedSlideShowTransactionPermissionRequesting,
    beforeFinishingStart: @escaping @Sendable () async -> Void = {}
  ) {
    self.sessionContext = sessionContext
    self.stageA = stageA
    self.makeStageB = makeStageB
    self.capture = capture
    self.identityProvider = identityProvider
    self.exactObject = exactObject
    self.permissionRequester = permissionRequester
    self.beforeFinishingStart = beforeFinishingStart
  }

  var currentState: ManagedSlideShowTransactionState { state }
  var currentStopWaiterCount: Int { stopWaiterCount }

  func start(
    operationID: CaptureOperationID,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler,
    activateBinding: @escaping @Sendable (ManagedSlideShowRuntimeBinding) async -> Bool,
    onIdentityObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async -> Result {
    guard task == nil, stopTask == nil, pendingExactObjectDrain == nil,
      state == .idle || isTerminal(state)
    else {
      return .failure(.alreadyActiveOrDraining)
    }
    guard sessionContext.isWellFormed, operationID.rawValue > 0 else {
      state = .failed(.stageAFailed)
      return .failure(.stageAFailed)
    }
    state = .starting
    let attempt = UUID()
    token = attempt
    activeOperationID = operationID
    let permissionRequester = self.permissionRequester
    let stageA = self.stageA
    let capture = self.capture
    let identityProvider = self.identityProvider
    let exactObject = self.exactObject
    let context = self.sessionContext
    let work = Task<Result, Never> {
      let permission = await permissionRequester.requestFromExplicitUserAction(
        target: PowerPointAutomationPermissionTarget(
          processIdentifier: Int32(context.frozenWindowIdentity.ownerProcessID),
          bundleIdentifier: context.frozenWindowIdentity.bundleIdentifier,
          bindingSessionToken: context.bindingSessionToken
        )
      )
      guard
        !Task.isCancelled,
        self.token == attempt,
        self.activeOperationID == operationID
      else {
        return .failure(.cancelled)
      }
      guard permission == .authorized else {
        return .failure(.automationPermissionDenied)
      }
      let candidateResult = await stageA.correlateCandidate(for: context.frozenWindowIdentity)
      guard case .success(let candidate) = candidateResult else {
        if case .failure(let failure) = candidateResult,
          let receipt = failure.recoveryReceipt
        {
          self.retainReceiptForCleanup(receipt)
          _ = await self.cleanupExactObject(receipt)
        }
        return .failure(.stageAFailed)
      }
      let receipt = ManagedSlideShowStartReceipt(
        bindingSessionToken: candidate.bindingSessionToken,
        processIdentifier: candidate.candidateWindowIdentity.ownerProcessID,
        bundleIdentifier: candidate.candidateWindowIdentity.bundleIdentifier,
        slideShowObjectToken: candidate.slideShowObjectToken
      )
      self.retainReceiptForCleanup(receipt)
      guard !Task.isCancelled else {
        _ = await self.cleanupExactObject(receipt)
        return .failure(.cancelled)
      }
      do {
        let lease: any ManagedSlideShowTransactionCaptureLease
        do {
          lease = try await capture.startCapture(
            operationID: operationID,
            identity: candidate.candidateWindowIdentity,
            onFrame: onFrame,
            onContentUnavailable: onContentUnavailable,
            onFailure: onFailure
          )
        } catch {
          _ = await self.cleanupExactObject(receipt)
          return .failure(.captureStartFailed)
        }
        guard !Task.isCancelled else {
          await self.cleanup(operationID: operationID, receipt: receipt)
          return .failure(.cancelled)
        }
        let anchor = try await lease.captureAnchor()
        guard
          !Task.isCancelled,
          self.token == attempt,
          self.activeOperationID == operationID
        else {
          await self.cleanup(operationID: operationID, receipt: receipt)
          return .failure(.cancelled)
        }
        let stageB = self.makeStageB(candidate, lease, anchor)
        self.setActiveRoleChallenge(stageB)
        let challenge = await stageB.challenge(
          candidate: candidate,
          captureOperationID: operationID,
          captureGeneration: lease.captureGeneration,
          captureAnchor: anchor
        )
        guard case .success(let binding) = challenge else {
          await stageB.requestCancellation()
          if await stageB.isDrained {
            self.clearActiveRoleChallenge()
            await self.cleanup(operationID: operationID, receipt: receipt)
          } else {
            // Stage B can return restorationTimedOut while its exact-object cleanup continues.
            // Stop local consumers now, but retain the Stage-A receipt and the coordinator until
            // the real drain before sending exit/release to the exact object.
            await identityProvider.stopIdentity(operationID: operationID)
            await capture.stopCapture(operationID: operationID)
            self.deferExactObjectCleanupAfterStageBDrain(
              stageB,
              operationID: operationID,
              receipt: receipt,
              exactObject: exactObject,
              failure: .stageBFailed
            )
          }
          return .failure(.stageBFailed)
        }
        self.clearActiveRoleChallenge()
        guard await activateBinding(binding), !Task.isCancelled else {
          await self.cleanup(operationID: operationID, receipt: receipt)
          return .failure(.bindingActivationRejected)
        }
        let started = await identityProvider.startIdentity(
          operationID: operationID,
          captureGeneration: lease.captureGeneration,
          binding: binding,
          onObservation: onIdentityObservation
        )
        guard started == .started else {
          await self.cleanup(operationID: operationID, receipt: receipt)
          return .failure(.identityProviderRejected)
        }
        return .success(binding)
      } catch {
        await self.cleanup(operationID: operationID, receipt: receipt)
        return .failure(.captureAnchorFailed)
      }
    }
    task = work
    let result = await withTaskCancellationHandler {
      await work.value
    } onCancel: {
      // The transaction task is intentionally retained until an injected noncooperative Stage A
      // or Stage B call returns, but cancellation must still reach the currently owned boundary.
      // `stop()` supplies the bounded public-return path; this handler prevents a caller task's
      // cancellation from being silently lost while it awaits `start`.
      work.cancel()
      exactObject.cancelCurrentOperation()
      Task { await stageA.cancelCurrentAttempt() }
    }
    await beforeFinishingStart()
    return await finish(result, attempt: attempt)
  }

  @discardableResult
  func stop() async -> Bool {
    stopWaiterCount += 1
    defer { stopWaiterCount -= 1 }
    if let stopTask {
      return await stopTask.value
    }

    let attempt = UUID()
    let coordinator = self
    let work = Task<Bool, Never> {
      await coordinator.performStop()
    }
    stopAttempt = attempt
    stopTask = work
    let result = await work.value
    if stopAttempt == attempt {
      stopAttempt = nil
      stopTask = nil
    }
    return result
  }

  private func performStop() async -> Bool {
    guard let operationID = activeOperationID else {
      return task == nil && pendingExactObjectDrain == nil && acceptedReceipt == nil
    }
    state = .draining
    stopRequestedAttempt = token
    task?.cancel()
    exactObject.cancelCurrentOperation()
    await stageA.cancelCurrentAttempt()
    if let activeRoleChallenge { await activeRoleChallenge.requestCancellation() }

    // A start task (and, in particular, a noncooperative Stage-B restoration) is permitted to
    // outlive this bounded caller stop.  Its finish/deferred-drain path owns the receipt.  Do
    // not await it here and do not release the exact object out from underneath it.
    guard task == nil else { return false }
    guard pendingExactObjectDrain == nil else { return false }
    await identityProvider.stopIdentity(operationID: operationID)
    await capture.stopCapture(operationID: operationID)
    if let receipt = acceptedReceipt {
      guard await cleanupExactObject(receipt) else {
        state = .draining
        return false
      }
    }
    activeOperationID = nil
    state = .idle
    return true
  }

  /// Waits without weakening the bounded public `stop()` path.  App ownership may use this only
  /// from a detached bookkeeping task so a replacement transaction cannot start until every
  /// retained Stage-A/Stage-B operation and exact-object cleanup has actually completed.
  func waitUntilReplacementIsSafe() async -> Bool {
    while task != nil || stopTask != nil || pendingExactObjectDrain != nil {
      if let stopTask {
        _ = await stopTask.value
        await Task.yield()
      } else if let pendingExactObjectDrain {
        await pendingExactObjectDrain.value
      } else if let task {
        _ = await task.value
        await Task.yield()
      }
    }
    return acceptedReceipt == nil && exactObjectCleanupTask == nil
  }

  private func finish(_ result: Result, attempt: UUID) async -> Result {
    guard token == attempt else { return .failure(.staleCompletion) }
    let wasStopped = stopRequestedAttempt == attempt

    // `stop()` can arrive after the retained work task has produced a successful binding but
    // before this outer continuation has committed it as active.  Task cancellation cannot
    // change an already-produced value, so the stop tombstone is authoritative: close every
    // consumer and the exact retained object before publishing any terminal state.
    if wasStopped, case .success(let binding) = result {
      let receipt = ManagedSlideShowStartReceipt(
        bindingSessionToken: binding.bindingSessionToken,
        processIdentifier: binding.windowIdentity.ownerProcessID,
        bundleIdentifier: binding.windowIdentity.bundleIdentifier,
        slideShowObjectToken: binding.slideShowObjectToken
      )
      retainReceiptForCleanup(receipt)
      if let operationID = activeOperationID {
        await cleanup(operationID: operationID, receipt: receipt)
      }
    }

    task = nil
    token = nil
    if wasStopped { stopRequestedAttempt = nil }
    if pendingExactObjectDrain != nil {
      // The result is already available to the caller, but a transaction replacement remains
      // rejected and exact-object ownership remains retained until deferredCleanupDidDrain.
      state = .draining
      return wasStopped ? .failure(.cancelled) : result
    }
    if wasStopped {
      if acceptedReceipt == nil {
        activeOperationID = nil
        state = .idle
      } else {
        state = .draining
      }
      return .failure(.cancelled)
    }
    switch result {
    case .success(let binding):
      let receipt = ManagedSlideShowStartReceipt(
        bindingSessionToken: binding.bindingSessionToken,
        processIdentifier: binding.windowIdentity.ownerProcessID,
        bundleIdentifier: binding.windowIdentity.bundleIdentifier,
        slideShowObjectToken: binding.slideShowObjectToken
      )
      retainReceiptForCleanup(receipt)
      state = .active
    case .failure(let failure):
      if acceptedReceipt == nil {
        activeOperationID = nil
        state = failure == .cancelled ? .idle : .failed(failure)
      } else {
        // The local consumers are closed, but exact PowerPoint ownership is not.  Keeping the
        // operation in draining state makes replacement fail closed and leaves `stop()` as the
        // only explicit retry surface.
        state = .draining
      }
    }
    return result
  }

  private func setActiveRoleChallenge(
    _ challenge: any ManagedSlideShowTransactionRoleChallenging
  ) {
    activeRoleChallenge = challenge
  }

  private func clearActiveRoleChallenge() {
    activeRoleChallenge = nil
  }

  private func deferExactObjectCleanupAfterStageBDrain(
    _ stageB: any ManagedSlideShowTransactionRoleChallenging,
    operationID: CaptureOperationID,
    receipt: ManagedSlideShowStartReceipt,
    exactObject: any ManagedSlideShowTransactionExactObjectRecovering,
    failure: ManagedSlideShowTransactionFailure
  ) {
    guard pendingExactObjectDrain == nil else { return }
    let attempt = UUID()
    pendingDrainAttempt = attempt
    pendingDrainFailure = failure
    let coordinator = self
    pendingExactObjectDrain = Task {
      await stageB.waitForDrain()
      let cleaned = await coordinator.cleanupExactObject(receipt)
      await coordinator.deferredCleanupDidDrain(attempt: attempt, cleaned: cleaned)
    }
  }

  private func deferredCleanupDidDrain(attempt: UUID, cleaned: Bool) {
    guard pendingDrainAttempt == attempt else { return }
    let failure = pendingDrainFailure ?? .stageBFailed
    pendingExactObjectDrain = nil
    pendingDrainAttempt = nil
    pendingDrainFailure = nil
    activeRoleChallenge = nil
    if cleaned {
      activeOperationID = nil
      state = .failed(failure)
    } else {
      state = .draining
    }
  }

  private func cleanup(
    operationID: CaptureOperationID,
    receipt: ManagedSlideShowStartReceipt
  ) async {
    await identityProvider.stopIdentity(operationID: operationID)
    await capture.stopCapture(operationID: operationID)
    _ = await cleanupExactObject(receipt)
  }

  private func retainReceiptForCleanup(_ receipt: ManagedSlideShowStartReceipt) {
    guard acceptedReceipt == nil || acceptedReceipt == receipt else { return }
    acceptedReceipt = receipt
  }

  private func cleanupExactObject(_ receipt: ManagedSlideShowStartReceipt) async -> Bool {
    guard acceptedReceipt == receipt else { return false }
    if let exactObjectCleanupTask {
      return await exactObjectCleanupTask.value
    }

    let attempt = UUID()
    let exactObject = self.exactObject
    let cleanup = Task<Bool, Never> {
      do {
        try await exactObject.exitRetainedSlideShowObject(receipt)
        _ = await exactObject.releaseRetainedSlideShowObject(receipt)
        return true
      } catch {
        return false
      }
    }
    exactObjectCleanupAttempt = attempt
    exactObjectCleanupTask = cleanup
    let succeeded = await cleanup.value
    guard exactObjectCleanupAttempt == attempt else { return succeeded }
    exactObjectCleanupTask = nil
    exactObjectCleanupAttempt = nil
    if succeeded, acceptedReceipt == receipt {
      acceptedReceipt = nil
    }
    return succeeded
  }

  private func isTerminal(_ state: ManagedSlideShowTransactionState) -> Bool {
    if case .failed = state { return true }
    return false
  }
}

/// Production assembly point.  It mints the context once, then shares one Apple-event client for
/// Stage A, exact-object role commands, semantic reads, and exact-object cleanup.
enum ManagedSlideShowTransactionFactory {
  static func make(
    frozenWindowIdentity: PowerPointWindowIdentity,
    capture: any PowerPointWindowCapturing = PowerPointWindowCapture()
  ) -> ManagedSlideShowTransactionCoordinator {
    let context = ManagedSlideShowSessionContext(
      bindingSessionToken: UUID().uuidString,
      frozenWindowIdentity: frozenWindowIdentity
    )
    let permission = PowerPointAutomationPermissionService(
      bindingSessionToken: context.bindingSessionToken
    )
    let client = PowerPointManagedSlideShowAppleEventClient(
      sessionContext: context,
      permissionChecker: permission
    )
    let stageA = ManagedSlideShowBindingCoordinator(
      sessionContext: context,
      observationReader: client,
      slideShowStarter: client
    )
    return ManagedSlideShowTransactionCoordinator(
      sessionContext: context,
      stageA: stageA,
      makeStageB: { candidate, lease, anchor in
        ManagedSlideShowTransactionRoleChallengeAssembly.make(lease: lease) { evidenceLease in
          ManagedSlideShowRoleChallengeCoordinator(
            client: PowerPointManagedSlideShowRoleChallengeClient(
              expectedCandidate: candidate,
              captureOperationID: lease.captureOperationID,
              captureGeneration: lease.captureGeneration,
              captureAnchor: anchor,
              objectController: client,
              evidenceReader: PowerPointManagedSlideShowRoleCaptureEvidenceBroker(
                lease: evidenceLease,
                semanticReader: client
              )
            )
          )
        }
      },
      capture: PowerPointManagedSlideShowTransactionCapture(capture: capture),
      identityProvider: ExactPowerPointSlideIdentityProvider(reader: client),
      exactObject: client,
      permissionRequester: permission
    )
  }
}
