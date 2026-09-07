import CoreGraphics
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

/// Transaction tests use injected actors only.  They do not create a PowerPoint process, send an
/// Apple Event, request an Automation permission, start ScreenCaptureKit, or access the network.
struct ManagedSlideShowTransactionCoordinatorTests {
  @Test func successfulStartAndStopOwnTheSameReceipt() async throws {
    let rig = try Rig(stageB: .succeeds, identityResult: .started)
    let result = await rig.coordinator.start(
      operationID: CaptureOperationID(rawValue: 7),
      onFrame: { _ in }, onContentUnavailable: { _ in }, onFailure: { _ in },
      activateBinding: { binding in
        await rig.activation.activate(binding)
      },
      onIdentityObservation: { _ in }
    )
    #expect(result.binding != nil)
    #expect(await rig.capture.started == 1)
    #expect(await rig.identity.started == 1)
    #expect(await rig.identity.bindingWasActiveAtStart == true)
    await rig.coordinator.stop()
    #expect(await rig.capture.stopped == 1)
    #expect(await rig.identity.stopped == 1)
    #expect(await rig.exact.exited == [rig.receipt])
    #expect(await rig.exact.released == [rig.receipt])
    #expect(await rig.coordinator.currentState == .idle)
    #expect(await rig.coordinator.stop())
    #expect(await rig.exact.exited == [rig.receipt])
  }

  @Test func failedExitRetainsTheExactReceiptForAnExplicitRetry() async throws {
    let exact = TransactionExactObjectFake(exitMode: .failsOnce)
    let rig = try Rig(stageB: .succeeds, exact: exact)
    #expect((await rig.start()).binding != nil)

    #expect(await rig.coordinator.stop() == false)
    #expect(await exact.exitAttempts == [rig.receipt])
    #expect(await exact.released.isEmpty)
    #expect(await rig.coordinator.currentState == .draining)
    #expect((await rig.start()).failure == .alreadyActiveOrDraining)

    #expect(await rig.coordinator.stop() == true)
    #expect(await exact.exitAttempts == [rig.receipt, rig.receipt])
    #expect(await exact.released == [rig.receipt])
    #expect(await rig.coordinator.currentState == .idle)
    #expect(await rig.coordinator.waitUntilReplacementIsSafe())
  }

  @Test func concurrentRepeatedStopsShareOneExactObjectExit() async throws {
    let exact = TransactionExactObjectFake(exitMode: .suspends)
    let rig = try Rig(stageB: .succeeds, exact: exact)
    #expect((await rig.start()).binding != nil)

    let first = Task { await rig.coordinator.stop() }
    try await waitUntil { await exact.exitAttempts.count == 1 }
    let second = Task { await rig.coordinator.stop() }
    try await waitUntil { await rig.coordinator.currentStopWaiterCount == 2 }
    #expect(await rig.capture.stopped == 1)
    #expect(await exact.exitAttempts == [rig.receipt])

    await exact.resumeExit()
    #expect(await first.value)
    #expect(await second.value)
    #expect(await exact.exitAttempts == [rig.receipt])
    #expect(await exact.released == [rig.receipt])
    #expect(await rig.coordinator.currentState == .idle)
  }

  @Test func staleSharedStopFailureCannotRevertALaterSuccessfulRetry() async throws {
    let exact = TransactionExactObjectFake(exitMode: .suspendsThenFailsOnce)
    let rig = try Rig(stageB: .succeeds, exact: exact)
    #expect((await rig.start()).binding != nil)

    let first = Task { await rig.coordinator.stop() }
    try await waitUntil { await exact.exitAttempts.count == 1 }
    let olderWaiter = Task { await rig.coordinator.stop() }
    try await waitUntil { await rig.coordinator.currentStopWaiterCount == 2 }
    await exact.resumeExit(failing: true)
    #expect(await first.value == false)

    #expect(await rig.coordinator.stop())
    #expect(await rig.coordinator.currentState == .idle)
    #expect(await olderWaiter.value == false)
    #expect(await rig.coordinator.currentState == .idle)
    #expect(await exact.exitAttempts == [rig.receipt, rig.receipt])
    #expect((await rig.start()).binding != nil)
    #expect(await rig.coordinator.stop())
  }

  @Test func stopDuringSuspendedPermissionPreventsStageAAfterAuthorization() async throws {
    let permission = ControllableTransactionPermission()
    let stageA = TransactionStageAFake(result: .success(try Rig.candidate()))
    let rig = try Rig(
      permissionRequester: permission,
      stageA: stageA,
      stageB: .succeeds
    )

    let start = Task { await rig.start() }
    try await waitUntil { await permission.calls == 1 }
    #expect(await rig.coordinator.currentState == .starting)
    #expect(await rig.coordinator.stop() == false)
    let safetyProbe = TransactionSafetyProbe()
    let safety = Task {
      await safetyProbe.markStarted()
      let result = await rig.coordinator.waitUntilReplacementIsSafe()
      await safetyProbe.complete(with: result)
    }
    try await waitUntil { await safetyProbe.started }
    #expect(await rig.coordinator.currentState == .draining)
    #expect(await safetyProbe.result == nil)

    await permission.resume(.authorized)

    #expect((await start.value).failure == .cancelled)
    await safety.value
    #expect(await safetyProbe.result == true)
    #expect(await stageA.calls == 0)
    #expect(await rig.capture.started == 0)
    #expect(await rig.coordinator.currentState == .idle)
  }

  @Test func stopBetweenSuccessfulWorkAndFinishCleansTheEntireTransaction() async throws {
    let finishBarrier = ControllableTransactionFinishBarrier()
    let rig = try Rig(
      stageB: .succeeds,
      beforeFinishingStart: { await finishBarrier.wait() }
    )

    let start = Task { await rig.start() }
    try await waitUntil { await finishBarrier.calls == 1 }
    #expect(await rig.capture.started == 1)
    #expect(await rig.identity.started == 1)

    // The retained work has already returned success, so cancellation alone cannot change its
    // value.  The coordinator's stop tombstone must prevent that value becoming active.
    #expect(await rig.coordinator.stop() == false)
    await finishBarrier.resume()

    #expect((await start.value).failure == .cancelled)
    #expect(await rig.coordinator.waitUntilReplacementIsSafe())
    #expect(await rig.capture.stopped == 1)
    #expect(await rig.identity.stopped == 1)
    #expect(await rig.exact.exitAttempts == [rig.receipt])
    #expect(await rig.exact.released == [rig.receipt])
    #expect(await rig.coordinator.currentState == .idle)
  }

  @Test func stopDuringSuspendedAnchorNeverBeginsStageB() async throws {
    let anchorBarrier = ControllableTransactionAnchor()
    let stageB = TransactionStageBInvocationFake()
    let rig = try Rig(
      anchorBarrier: anchorBarrier,
      stageB: .tracked(stageB)
    )

    let start = Task { await rig.start() }
    try await waitUntil { await anchorBarrier.calls == 1 }
    #expect(await rig.coordinator.stop() == false)
    await anchorBarrier.resume()

    #expect((await start.value).failure == .cancelled)
    #expect(await rig.coordinator.waitUntilReplacementIsSafe())
    #expect(await stageB.calls == 0)
    #expect(await rig.capture.stopped == 1)
    #expect(await rig.identity.stopped == 1)
    #expect(await rig.exact.exitAttempts == [rig.receipt])
    #expect(await rig.exact.released == [rig.receipt])
    #expect(await rig.coordinator.currentState == .idle)
  }

  @Test func firstTimePermissionDenialStopsBeforeStageA() async throws {
    let rig = try Rig(permission: .denied, stageB: .succeeds)
    let result = await rig.start()
    #expect(result.failure == .automationPermissionDenied)
    #expect(await rig.capture.started == 0)
  }

  @Test func stageARecoverableFailureReturnsReceiptToItsExactOwner() async throws {
    let rig = try Rig(
      stageAResult: .failure(
        ManagedSlideShowBindingFailure(
          reason: .startCommandReplyMissingPossiblyDelivered,
          recoveryReceipt: try Rig.receipt())
      ),
      stageB: .succeeds
    )
    #expect((await rig.start()).failure == .stageAFailed)
    #expect(await rig.exact.exited == [rig.receipt])
    #expect(await rig.exact.released == [rig.receipt])
    #expect(await rig.capture.started == 0)
  }

  @Test func captureStartAndAnchorFailuresAreClosedAndRestoreReceipt() async throws {
    let startRig = try Rig(captureMode: .startFails, stageB: .succeeds)
    #expect((await startRig.start()).failure == .captureStartFailed)
    #expect(await startRig.exact.exited == [startRig.receipt])

    let anchorRig = try Rig(captureMode: .anchorFails, stageB: .succeeds)
    #expect((await anchorRig.start()).failure == .captureAnchorFailed)
    #expect(await anchorRig.capture.stopped == 1)
    #expect(await anchorRig.exact.released == [anchorRig.receipt])
  }

  @Test func stageBFailureAndIdentityRejectionBothRestoreTheExactReceipt() async throws {
    let failedChallenge = try Rig(stageB: .failsImmediately)
    #expect((await failedChallenge.start()).failure == .stageBFailed)
    #expect(await failedChallenge.exact.exited == [failedChallenge.receipt])

    let rejectedIdentity = try Rig(stageB: .succeeds, identityResult: .rejectedStaleOperation)
    #expect((await rejectedIdentity.start()).failure == .identityProviderRejected)
    #expect(await rejectedIdentity.identity.started == 1)
    #expect(await rejectedIdentity.exact.released == [rejectedIdentity.receipt])
  }

  @Test func rejectedAppBindingActivationStopsBeforeIdentityPollingAndRestoresReceipt() async throws
  {
    let rig = try Rig(stageB: .succeeds)
    let result = await rig.coordinator.start(
      operationID: CaptureOperationID(rawValue: 7),
      onFrame: { _ in }, onContentUnavailable: { _ in }, onFailure: { _ in },
      activateBinding: { _ in false },
      onIdentityObservation: { _ in }
    )
    #expect(result.failure == .bindingActivationRejected)
    #expect(await rig.identity.started == 0)
    #expect(await rig.capture.stopped == 1)
    #expect(await rig.exact.exited == [rig.receipt])
    #expect(await rig.exact.released == [rig.receipt])
  }

  @Test func cancellationDuringStartingReturnsWithoutAReplacementChain() async throws {
    let stageA = ControllableTransactionStageA()
    let rig = try Rig(stageA: stageA, stageB: .succeeds)
    let first = Task { await rig.start() }
    try await waitUntil { await stageA.calls == 1 }
    first.cancel()
    #expect((await rig.start()).failure == .alreadyActiveOrDraining)
    await stageA.resume(with: .success(rig.candidate))
    #expect((await first.value).failure == .cancelled)
    #expect(await rig.exact.exited == [rig.receipt])
  }

  @Test func restorationDeadlineRetainsCoordinatorClientAndReceiptUntilActualDrain() async throws {
    let drainingStageB = DrainingTransactionStageB()
    let rig = try Rig(stageB: .draining(drainingStageB))
    #expect((await rig.start()).failure == .stageBFailed)
    #expect(await rig.coordinator.currentState == .draining)
    #expect(await rig.exact.exited.isEmpty)
    #expect((await rig.start()).failure == .alreadyActiveOrDraining)
    await rig.coordinator.stop()
    #expect(await rig.coordinator.currentState == .draining)
    #expect(await rig.exact.exited.isEmpty)
    await drainingStageB.drain()
    await rig.coordinator.waitUntilReplacementIsSafe()
    try await waitUntil { await rig.exact.exited == [rig.receipt] }
    #expect(await rig.exact.released == [rig.receipt])
    #expect(await rig.coordinator.currentState == .failed(.stageBFailed))
  }

  @Test func productionAssemblyRejectsAnUnexpectedCaptureLeaseWithoutCrashing() async throws {
    let lease = TransactionLease(
      operationID: CaptureOperationID(rawValue: 7),
      anchorFails: false
    )
    let challenge = ManagedSlideShowTransactionRoleChallengeAssembly.make(lease: lease) { _ in
      Issue.record("A mismatched transaction lease reached the production builder")
      return TransactionSuccessfulStageB()
    }
    let result = await challenge.challenge(
      candidate: try Rig.candidate(),
      captureOperationID: CaptureOperationID(rawValue: 7),
      captureGeneration: 9,
      captureAnchor: try await lease.captureAnchor()
    )
    #expect(result == .failure(.clientFailed))
    #expect(await challenge.isDrained)
  }
}

extension ManagedSlideShowTransactionCoordinatorTests {
  fileprivate enum StageBMode {
    case succeeds, failsImmediately
    case draining(DrainingTransactionStageB)
    case tracked(TransactionStageBInvocationFake)
  }
  fileprivate enum CaptureMode { case succeeds, startFails, anchorFails }

  fileprivate struct Rig {
    let coordinator: ManagedSlideShowTransactionCoordinator
    let capture: TransactionCaptureFake
    let identity: TransactionIdentityFake
    let activation: TransactionBindingActivation
    let exact: TransactionExactObjectFake
    let candidate: ManagedSlideShowRuntimeCandidate
    let receipt: ManagedSlideShowStartReceipt

    init(
      permission: PowerPointAutomationPermissionState = .authorized,
      permissionRequester injectedPermissionRequester:
        (any ManagedSlideShowTransactionPermissionRequesting)? = nil,
      stageAResult: ManagedSlideShowBindingCoordinator.CandidateResult? = nil,
      stageA: (any ManagedSlideShowTransactionCandidateCorrelating)? = nil,
      captureMode: CaptureMode = .succeeds,
      anchorBarrier: ControllableTransactionAnchor? = nil,
      stageB: StageBMode,
      identityResult: ExactPowerPointSlideIdentityProviderStartResult = .started,
      exact injectedExact: TransactionExactObjectFake? = nil,
      beforeFinishingStart: @escaping @Sendable () async -> Void = {}
    ) throws {
      let candidate = try Self.candidate()
      let receipt = try Self.receipt()
      let candidateStageA =
        stageA ?? TransactionStageAFake(result: stageAResult ?? .success(candidate))
      let capture = TransactionCaptureFake(mode: captureMode, anchorBarrier: anchorBarrier)
      let activation = TransactionBindingActivation()
      let identity = TransactionIdentityFake(result: identityResult, activation: activation)
      let exact = injectedExact ?? TransactionExactObjectFake()
      let frozen = try #require(
        PowerPointWindowIdentity(
          windowID: 10, ownerProcessID: 700,
          bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
        ))
      self.coordinator = ManagedSlideShowTransactionCoordinator(
        sessionContext: ManagedSlideShowSessionContext(
          bindingSessionToken: "session", frozenWindowIdentity: frozen),
        stageA: candidateStageA,
        makeStageB: { candidate, _, _ in
          switch stageB {
          case .failsImmediately: TransactionStageBFailureFake()
          case .draining(let value): value
          case .tracked(let value): value
          case .succeeds:
            TransactionSuccessfulStageB()
          }
        },
        capture: capture, identityProvider: identity, exactObject: exact,
        permissionRequester: injectedPermissionRequester
          ?? TransactionPermissionFake(result: permission),
        beforeFinishingStart: beforeFinishingStart
      )
      self.capture = capture
      self.identity = identity
      self.activation = activation
      self.exact = exact
      self.candidate = candidate
      self.receipt = receipt
    }

    func start() async -> ManagedSlideShowTransactionCoordinator.Result {
      await coordinator.start(
        operationID: CaptureOperationID(rawValue: 7), onFrame: { _ in },
        onContentUnavailable: { _ in }, onFailure: { _ in },
        activateBinding: { binding in
          await activation.activate(binding)
        },
        onIdentityObservation: { _ in })
    }

    static func candidate() throws -> ManagedSlideShowRuntimeCandidate {
      ManagedSlideShowRuntimeCandidate(
        candidateWindowIdentity: try #require(
          PowerPointWindowIdentity(
            windowID: 20, ownerProcessID: 700,
            bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
          )), bindingSessionToken: "session", slideShowObjectToken: "object"
      )
    }

    static func receipt() throws -> ManagedSlideShowStartReceipt {
      ManagedSlideShowStartReceipt(
        bindingSessionToken: "session", processIdentifier: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        slideShowObjectToken: "object")
    }
  }

  fileprivate func waitUntil(
    _ predicate: @escaping @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<2_000 {
      if await predicate() { return }
      try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for fake boundary")
    throw CancellationError()
  }
}

private actor TransactionPermissionFake: ManagedSlideShowTransactionPermissionRequesting {
  let result: PowerPointAutomationPermissionState
  init(result: PowerPointAutomationPermissionState) { self.result = result }
  func requestFromExplicitUserAction(target _: PowerPointAutomationPermissionTarget) async
    -> PowerPointAutomationPermissionState
  { result }
}

private actor ControllableTransactionPermission:
  ManagedSlideShowTransactionPermissionRequesting
{
  private var continuation: CheckedContinuation<PowerPointAutomationPermissionState, Never>?
  private(set) var calls = 0

  func requestFromExplicitUserAction(target _: PowerPointAutomationPermissionTarget) async
    -> PowerPointAutomationPermissionState
  {
    calls += 1
    return await withCheckedContinuation { continuation = $0 }
  }

  func resume(_ result: PowerPointAutomationPermissionState) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

private actor TransactionSafetyProbe {
  private(set) var started = false
  private(set) var result: Bool?

  func markStarted() { started = true }
  func complete(with result: Bool) { self.result = result }
}

private actor ControllableTransactionFinishBarrier {
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var calls = 0

  func wait() async {
    calls += 1
    await withCheckedContinuation { continuation = $0 }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private actor TransactionStageAFake: ManagedSlideShowTransactionCandidateCorrelating {
  let result: ManagedSlideShowBindingCoordinator.CandidateResult
  private(set) var calls = 0
  init(result: ManagedSlideShowBindingCoordinator.CandidateResult) { self.result = result }
  func correlateCandidate(for _: PowerPointWindowIdentity) async
    -> ManagedSlideShowBindingCoordinator.CandidateResult
  {
    calls += 1
    return result
  }
  func cancelCurrentAttempt() async {}
}

private actor ControllableTransactionStageA: ManagedSlideShowTransactionCandidateCorrelating {
  private var continuation:
    CheckedContinuation<ManagedSlideShowBindingCoordinator.CandidateResult, Never>?
  private(set) var calls = 0
  func correlateCandidate(for _: PowerPointWindowIdentity) async
    -> ManagedSlideShowBindingCoordinator.CandidateResult
  {
    calls += 1
    return await withCheckedContinuation { continuation = $0 }
  }
  func cancelCurrentAttempt() async {}
  func resume(with value: ManagedSlideShowBindingCoordinator.CandidateResult) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}

private actor TransactionCaptureFake: ManagedSlideShowTransactionCapturing {
  let mode: ManagedSlideShowTransactionCoordinatorTests.CaptureMode
  let anchorBarrier: ControllableTransactionAnchor?
  private(set) var started = 0
  private(set) var stopped = 0
  init(
    mode: ManagedSlideShowTransactionCoordinatorTests.CaptureMode,
    anchorBarrier: ControllableTransactionAnchor? = nil
  ) {
    self.mode = mode
    self.anchorBarrier = anchorBarrier
  }
  func startCapture(
    operationID: CaptureOperationID, identity _: PowerPointWindowIdentity,
    onFrame _: @escaping CaptureFrameHandler,
    onContentUnavailable _: @escaping CaptureContentUnavailableHandler,
    onFailure _: @escaping CaptureFailureHandler
  ) async throws -> any ManagedSlideShowTransactionCaptureLease {
    started += 1
    if mode == .startFails { throw CancellationError() }
    return TransactionLease(
      operationID: operationID,
      anchorFails: mode == .anchorFails,
      anchorBarrier: anchorBarrier
    )
  }
  func stopCapture(operationID _: CaptureOperationID) async { stopped += 1 }
}

private actor TransactionLease: ManagedSlideShowTransactionCaptureLease {
  let captureOperationID: CaptureOperationID
  let captureGeneration: UInt64 = 9
  let anchorFails: Bool
  let anchorBarrier: ControllableTransactionAnchor?
  init(
    operationID: CaptureOperationID,
    anchorFails: Bool,
    anchorBarrier: ControllableTransactionAnchor? = nil
  ) {
    captureOperationID = operationID
    self.anchorFails = anchorFails
    self.anchorBarrier = anchorBarrier
  }
  func captureAnchor() async throws -> ManagedSlideShowRoleChallengeCaptureAnchor {
    if anchorFails { throw CancellationError() }
    if let anchorBarrier { await anchorBarrier.wait() }
    return ManagedSlideShowRoleChallengeCaptureAnchor(
      candidateStreamMemberToken: "candidate-member",
      candidateContinuityToken: "candidate-continuity",
      minimumCandidateDeliverySequenceExclusive: 79)
  }
}

private actor ControllableTransactionAnchor {
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var calls = 0

  func wait() async {
    calls += 1
    await withCheckedContinuation { continuation = $0 }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private actor TransactionStageBInvocationFake:
  ManagedSlideShowTransactionRoleChallenging
{
  private(set) var calls = 0

  func challenge(
    candidate _: ManagedSlideShowRuntimeCandidate,
    captureOperationID _: CaptureOperationID,
    captureGeneration _: UInt64,
    captureAnchor _: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ManagedSlideShowRoleChallengeCoordinator.ChallengeResult {
    calls += 1
    return .failure(.clientFailed)
  }

  func requestCancellation() async {}
  func waitForDrain() async {}
  var isDrained: Bool { true }
}

private actor TransactionBindingActivation {
  private(set) var binding: ManagedSlideShowRuntimeBinding?

  func activate(_ binding: ManagedSlideShowRuntimeBinding) -> Bool {
    self.binding = binding
    return true
  }

  var isActive: Bool { binding != nil }
}

private actor TransactionIdentityFake: ManagedSlideShowTransactionIdentityProviding {
  let result: ExactPowerPointSlideIdentityProviderStartResult
  let activation: TransactionBindingActivation
  private(set) var started = 0
  private(set) var stopped = 0
  private(set) var bindingWasActiveAtStart: Bool?
  init(
    result: ExactPowerPointSlideIdentityProviderStartResult,
    activation: TransactionBindingActivation
  ) {
    self.result = result
    self.activation = activation
  }
  func startIdentity(
    operationID _: CaptureOperationID, captureGeneration _: UInt64,
    binding _: ManagedSlideShowRuntimeBinding,
    onObservation _: @escaping PowerPointSlideIdentityObservationHandler
  ) async -> ExactPowerPointSlideIdentityProviderStartResult {
    started += 1
    bindingWasActiveAtStart = await activation.isActive
    return result
  }
  func stopIdentity(operationID _: CaptureOperationID) async { stopped += 1 }
}

private actor TransactionExactObjectFake: ManagedSlideShowTransactionExactObjectRecovering {
  enum ExitMode { case succeeds, failsOnce, suspends, suspendsThenFailsOnce }
  private let exitMode: ExitMode
  private var hasFailed = false
  private var exitContinuation:
    CheckedContinuation<Result<Void, TransactionExactObjectFailure>, Never>?
  private(set) var exitAttempts: [ManagedSlideShowStartReceipt] = []
  private(set) var released: [ManagedSlideShowStartReceipt] = []
  init(exitMode: ExitMode = .succeeds) { self.exitMode = exitMode }
  func exitRetainedSlideShowObject(_ receipt: ManagedSlideShowStartReceipt) async throws {
    exitAttempts.append(receipt)
    switch exitMode {
    case .succeeds:
      return
    case .failsOnce where !hasFailed:
      hasFailed = true
      throw TransactionExactObjectFailure.controlled
    case .failsOnce:
      return
    case .suspends:
      try await withCheckedContinuation { exitContinuation = $0 }.get()
    case .suspendsThenFailsOnce where !hasFailed:
      hasFailed = true
      try await withCheckedContinuation { exitContinuation = $0 }.get()
    case .suspendsThenFailsOnce:
      return
    }
  }
  func releaseRetainedSlideShowObject(_ receipt: ManagedSlideShowStartReceipt) async -> Bool {
    released.append(receipt)
    return true
  }
  var exited: [ManagedSlideShowStartReceipt] { exitAttempts }
  func resumeExit(failing: Bool = false) {
    exitContinuation?.resume(
      returning: failing ? .failure(.controlled) : .success(())
    )
    exitContinuation = nil
  }
  nonisolated func cancelCurrentOperation() {}
}

private enum TransactionExactObjectFailure: Error { case controlled }

private actor TransactionStageBFailureFake: ManagedSlideShowTransactionRoleChallenging {
  func challenge(
    candidate _: ManagedSlideShowRuntimeCandidate, captureOperationID _: CaptureOperationID,
    captureGeneration _: UInt64, captureAnchor _: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ManagedSlideShowRoleChallengeCoordinator.ChallengeResult { .failure(.clientFailed) }
  func requestCancellation() async {}
  func waitForDrain() async {}
  var isDrained: Bool { true }
}

private actor DrainingTransactionStageB: ManagedSlideShowTransactionRoleChallenging {
  private var drained = false
  private var continuation: CheckedContinuation<Void, Never>?
  func challenge(
    candidate _: ManagedSlideShowRuntimeCandidate, captureOperationID _: CaptureOperationID,
    captureGeneration _: UInt64, captureAnchor _: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ManagedSlideShowRoleChallengeCoordinator.ChallengeResult { .failure(.clientFailed) }
  func requestCancellation() async {}
  func waitForDrain() async { if !drained { await withCheckedContinuation { continuation = $0 } } }
  var isDrained: Bool { drained }
  func drain() {
    drained = true
    continuation?.resume()
    continuation = nil
  }
}

private actor TransactionSuccessfulStageB: ManagedSlideShowTransactionRoleChallenging {
  private let coordinator = ManagedSlideShowRoleChallengeCoordinator(
    client: TransactionSuccessfulRoleClient(), nonceGenerator: { 40 }
  )
  func challenge(
    candidate: ManagedSlideShowRuntimeCandidate, captureOperationID: CaptureOperationID,
    captureGeneration: UInt64, captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor
  ) async -> ManagedSlideShowRoleChallengeCoordinator.ChallengeResult {
    let result = await coordinator.challenge(
      candidate: candidate, captureOperationID: captureOperationID,
      captureGeneration: captureGeneration, captureAnchor: captureAnchor)
    return result
  }
  func requestCancellation() async { await coordinator.cancelCurrentAttempt() }
  func waitForDrain() async { await coordinator.waitForDrain() }
  var isDrained: Bool { get async { await coordinator.isDrained } }
}

private actor TransactionSuccessfulRoleClient: ManagedSlideShowRoleChallengeClient {
  func runVisibilityChallenge(_ request: ManagedSlideShowRoleChallengeRequest) async throws
    -> ManagedSlideShowRoleChallengeClientResult
  {
    .evidence(transactionTranscript(request: request))
  }
  func runPixelNonceChallenge(_: ManagedSlideShowRoleChallengeRequest) async throws
    -> ManagedSlideShowRoleChallengeClientResult
  { .unavailable }
}

private func transactionTranscript(request: ManagedSlideShowRoleChallengeRequest)
  -> [ManagedSlideShowRoleChallengeObservation]
{
  let phases: [ManagedSlideShowRoleChallengePhase] = [
    .baseline, .visibilityHidden, .visibilityRestored,
  ]
  return phases.enumerated().flatMap { index, phase in
    [0, 1].map { repeatIndex in
      let reply = UInt64(index + 1) * 100
      let offset: UInt64 = repeatIndex == 0 ? 10 : 20
      let observed = reply + offset
      let onScreen = phase != .visibilityHidden
      let candidate = ManagedSlideShowWindowIdentity(
        windowID: 20, processIdentifier: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier)
      let control = ManagedSlideShowWindowIdentity(
        windowID: 10, processIdentifier: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier)
      let provenance = ManagedSlideShowRoleWindowDeliveryProvenance(
        status: .generated, captureOperationID: 7, captureGeneration: 9,
        streamMemberToken: "candidate-member", continuityToken: "candidate-continuity",
        deliverySequence: (request.challengeNonce + UInt64(index)) * 2 + UInt64(repeatIndex),
        callbackMachAbsoluteTime: observed)
      let controlProvenance = ManagedSlideShowRoleWindowDeliveryProvenance(
        status: .generated, captureOperationID: 7, captureGeneration: 9,
        streamMemberToken: "control-member", continuityToken: "control-continuity",
        deliverySequence: (request.challengeNonce + UInt64(index)) * 2 + UInt64(repeatIndex),
        callbackMachAbsoluteTime: observed)
      return ManagedSlideShowRoleChallengeObservation(
        bindingSessionToken: "session", slideShowObjectToken: "object",
        processIdentifier: 700, bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        candidateWindowIdentity: candidate, captureOperationID: 7, captureGeneration: 9,
        phase: phase,
        nonce: request.challengeNonce + UInt64(index), commandReplyMachAbsoluteTime: reply,
        evidenceObservedMachAbsoluteTime: observed, candidateDisplayTime: onScreen ? observed : nil,
        inventoryIsComplete: true,
        semanticState: ManagedSlideShowRoleSemanticState(
          slideID: 50, slideIndex: 3,
          currentViewState: .running, presentationSaved: true),
        windows: [
          ManagedSlideShowRoleWindowEvidence(
            identity: control,
            fingerprint: FrameFingerprint(
              sampleColumns: 2, sampleRows: 2, luminance: [80, 80, 80, 80]),
            isOnScreen: true, displayTime: observed, deliveryProvenance: controlProvenance),
          ManagedSlideShowRoleWindowEvidence(
            identity: candidate,
            fingerprint: onScreen
              ? FrameFingerprint(sampleColumns: 2, sampleRows: 2, luminance: [100, 100, 100, 100])
              : nil,
            isOnScreen: onScreen, displayTime: onScreen ? observed : nil,
            deliveryProvenance: onScreen ? provenance : nil),
        ])
    }
  }
}

extension Result where Failure == ManagedSlideShowTransactionFailure {
  fileprivate var binding: Success? {
    guard case .success(let value) = self else { return nil }
    return value
  }
  fileprivate var failure: Failure? {
    guard case .failure(let value) = self else { return nil }
    return value
  }
}
