import CoreGraphics
import Darwin
import Foundation
import LectureBoardCore

/// One externally created runtime context shared by the Stage A client and its coordinator.
///
/// The factory or transaction that owns a managed-start attempt creates this value before either
/// component. Keeping the exact frozen identity beside the opaque session token prevents the
/// coordinator from silently minting a different session and prevents a caller from substituting
/// another PowerPoint window after the two components have been assembled.
struct ManagedSlideShowSessionContext: Equatable, Sendable {
  let bindingSessionToken: String
  let frozenWindowIdentity: PowerPointWindowIdentity

  init(
    bindingSessionToken: String,
    frozenWindowIdentity: PowerPointWindowIdentity
  ) {
    self.bindingSessionToken = bindingSessionToken
    self.frozenWindowIdentity = frozenWindowIdentity
  }

  var isWellFormed: Bool {
    let trimmedToken = bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmedToken.isEmpty && trimmedToken == bindingSessionToken
  }
}

/// One coordinator-owned request for a fresh composite observation.
enum ManagedSlideShowCompositeObservationPhase: Equatable, Sendable {
  case baseline
  case postStart
}

struct ManagedSlideShowCompositeObservationRequest: Equatable, Sendable {
  let bindingSessionToken: String
  let processIdentifier: pid_t
  let bundleIdentifier: String
  let freshObservationToken: String
  let requestStartedMachAbsoluteTime: UInt64
  let phase: ManagedSlideShowCompositeObservationPhase
}

/// Reads one independently bracketed PowerPoint/ScreenCaptureKit observation.
///
/// A live implementation must obtain the scripting evidence and exact window inventory as one
/// stable composite observation for the frozen process and bundle. The coordinator does not
/// supplement missing evidence with title, order, focus, Accessibility, or approximate geometry.
protocol ManagedSlideShowCompositeObservationReading: Sendable {
  func readCompositeObservation(
    _ request: ManagedSlideShowCompositeObservationRequest
  ) async throws -> ManagedSlideShowInventoryObservation
}

/// Preconditions that must be rechecked immediately before one managed start command.
///
/// A starter must use one externally serialized operation to verify the frozen process and bundle,
/// the opaque binding session, exactly one active presentation, and zero existing slide-show
/// windows immediately before sending the command. It must throw without sending if any check
/// fails. This value is runtime-only and does not prove the role of a subsequently observed
/// `CGWindowID`.
struct ManagedSlideShowStartRequest: Equatable, Sendable {
  let frozenWindowIdentity: PowerPointWindowIdentity
  let bindingSessionToken: String
  let requiredActivePresentationCount: Int
  let requiredPreexistingSlideShowWindowCount: Int
}

/// Runtime-only receipt for the object returned by the managed `run slide show` operation.
///
/// A live starter keeps the actual scripting object specifier actor-isolated and exposes only a
/// fresh opaque token. The token lets a later role-challenge boundary address that same returned
/// object instead of accepting a newly enumerated sole slide-show object.
struct ManagedSlideShowStartReceipt: Equatable, Sendable {
  let bindingSessionToken: String
  let processIdentifier: pid_t
  let bundleIdentifier: String
  let slideShowObjectToken: String
}

/// Sends the single managed PowerPoint slide-show start requested by the coordinator.
///
/// This boundary intentionally contains no production Apple Event implementation. Its contract is
/// narrower than a generic start command so a future implementation cannot omit the immediate
/// pre-send checks carried by ``ManagedSlideShowStartRequest``.
protocol ManagedSlideShowStarting: Sendable {
  func startManagedSlideShow(
    _ request: ManagedSlideShowStartRequest
  ) async throws -> ManagedSlideShowStartReceipt
}

protocol ManagedSlideShowBindingPollWaiting: Sendable {
  func waitUntilNextObservation() async throws
}

protocol ManagedSlideShowBindingMachClock: Sendable {
  func now() async -> UInt64
}

struct SystemManagedSlideShowBindingMachClock: ManagedSlideShowBindingMachClock {
  func now() async -> UInt64 {
    mach_absolute_time()
  }
}

struct TaskManagedSlideShowBindingPollWaiter: ManagedSlideShowBindingPollWaiting {
  private let interval: Duration

  init(interval: Duration = .milliseconds(100)) {
    self.interval = min(max(interval, .milliseconds(50)), .seconds(2))
  }

  func waitUntilNextObservation() async throws {
    try await Task.sleep(for: interval)
  }
}

/// The only external error classification retained across the injected boundaries.
enum ManagedSlideShowBindingClientError: Error, Equatable, Sendable {
  case permissionDenied
}

enum ManagedSlideShowBindingCoordinatorFailure: Error, Equatable, Sendable {
  case malformedSessionContext
  case sessionContextMismatch
  case permissionDenied
  case baselineReadFailed
  case startCommandFailed
  case startCommandDeliveryUnknown
  case startCommandReplyMissingPossiblyDelivered
  case startCommandReplyMalformedPossiblyDelivered
  case postStartReadFailed
  case pollWaitFailed
  case timedOut
  case cancelled
  case priorAttemptStillDraining
  case staleCompletion
  case frozenWindowUnavailable
  case windowIdentifierOutOfRange
  case malformedStartReceipt
  case startReceiptMismatch
  case observationClockInvalid
  case observationRequestTokenMismatch
  case observationAcquisitionTimeOutOfBounds
  case policyRejected(ManagedSlideShowBindingRejection)
}

/// One fail-closed Stage A result, with exact-object recovery ownership when start succeeded.
///
/// `recoveryReceipt` is present only after a well-formed receipt for the exact frozen target was
/// accepted. The transaction that injected the starter remains responsible for using that same
/// starter/client to restore or exit the returned PowerPoint object, then explicitly releasing its
/// retained descriptor. A post-start failure therefore cannot silently discard rollback ownership.
struct ManagedSlideShowBindingFailure: Error, Equatable, Sendable {
  let reason: ManagedSlideShowBindingCoordinatorFailure
  let recoveryReceipt: ManagedSlideShowStartReceipt?
}

/// Runtime-only candidate correlated with a managed start.
///
/// Neither this value nor its opaque session token is serializable evidence. The token is freshly
/// generated for one attempt and exists only to prevent observations from crossing attempts. This
/// value is intentionally distinct from a semantic runtime binding: it does not prove that the
/// candidate has PowerPoint's slide-show role and it does not detect `CGWindowID` lifecycle reuse.
/// A future exact-capture role challenge and restoration check must succeed before another boundary
/// may construct a semantic binding.
struct ManagedSlideShowRuntimeCandidate: Equatable, Sendable {
  let candidateWindowIdentity: PowerPointWindowIdentity
  let bindingSessionToken: String
  let slideShowObjectToken: String
}

/// Coordinates at most one fail-closed candidate-window correlation attempt at a time.
///
/// Calling ``correlateCandidate(for:)`` with the exact identity frozen in the injected session
/// context is the explicit act that permits one start command. A
/// second call while
/// prior work has not drained is rejected immediately and never creates a replacement task chain.
/// Cancellation invalidates and cancels the active work, but no new attempt is allowed until that
/// work actually returns. Injected async clients can still fail to cooperate with cancellation, so
/// this coordinator promises bounded task ownership rather than a finite completion time.
actor ManagedSlideShowBindingCoordinator {
  typealias CandidateResult = Result<
    ManagedSlideShowRuntimeCandidate,
    ManagedSlideShowBindingFailure
  >

  private let sessionContext: ManagedSlideShowSessionContext
  private let observationReader: any ManagedSlideShowCompositeObservationReading
  private let slideShowStarter: any ManagedSlideShowStarting
  private let pollWaiter: any ManagedSlideShowBindingPollWaiting
  private let machClock: any ManagedSlideShowBindingMachClock
  private let maximumPostStartObservationCount: Int

  private var currentAttemptToken: UUID?
  private var activeWork: Task<CandidateResult, Never>?
  private var activeInvalidation: ManagedSlideShowBindingCoordinatorFailure?

  init(
    sessionContext: ManagedSlideShowSessionContext,
    observationReader: any ManagedSlideShowCompositeObservationReading,
    slideShowStarter: any ManagedSlideShowStarting,
    pollWaiter: any ManagedSlideShowBindingPollWaiting =
      TaskManagedSlideShowBindingPollWaiter(),
    machClock: any ManagedSlideShowBindingMachClock =
      SystemManagedSlideShowBindingMachClock(),
    maximumPostStartObservationCount: Int = 20
  ) {
    self.sessionContext = sessionContext
    self.observationReader = observationReader
    self.slideShowStarter = slideShowStarter
    self.pollWaiter = pollWaiter
    self.machClock = machClock
    self.maximumPostStartObservationCount = Self.boundedPostStartObservationCount(
      maximumPostStartObservationCount
    )
  }

  static func boundedPostStartObservationCount(_ requestedCount: Int) -> Int {
    min(max(requestedCount, 2), 1_000)
  }

  func correlateCandidate(
    for frozenIdentity: PowerPointWindowIdentity
  ) async -> CandidateResult {
    guard sessionContext.isWellFormed else {
      return Self.failed(.malformedSessionContext)
    }
    guard frozenIdentity == sessionContext.frozenWindowIdentity else {
      return Self.failed(.sessionContextMismatch)
    }
    guard activeWork == nil else {
      return Self.failed(.priorAttemptStillDraining)
    }

    let attemptToken = UUID()
    let bindingSessionToken = sessionContext.bindingSessionToken
    currentAttemptToken = attemptToken

    let observationReader = self.observationReader
    let slideShowStarter = self.slideShowStarter
    let pollWaiter = self.pollWaiter
    let machClock = self.machClock
    let maximumPostStartObservationCount = self.maximumPostStartObservationCount

    let work = Task<CandidateResult, Never> {
      guard !Task.isCancelled else { return Self.failed(.cancelled) }
      return await Self.performBinding(
        frozenIdentity: frozenIdentity,
        bindingSessionToken: bindingSessionToken,
        observationReader: observationReader,
        slideShowStarter: slideShowStarter,
        pollWaiter: pollWaiter,
        machClock: machClock,
        maximumPostStartObservationCount: maximumPostStartObservationCount
      )
    }
    activeWork = work
    activeInvalidation = nil

    let result = await withTaskCancellationHandler {
      await work.value
    } onCancel: {
      // `Task {}` is deliberately retained so a non-cooperative external client cannot create a
      // replacement chain. Propagate caller cancellation synchronously to that retained task;
      // the task remains owned until it actually drains.
      work.cancel()
    }
    let callbackSafeResult: CandidateResult
    if Task.isCancelled, case .success = result {
      callbackSafeResult = Self.failed(.cancelled)
    } else {
      callbackSafeResult = result
    }
    return finish(callbackSafeResult, attemptToken: attemptToken)
  }

  func cancelCurrentAttempt() {
    guard activeWork != nil else { return }
    if activeInvalidation == nil {
      activeInvalidation = .cancelled
    }
    activeWork?.cancel()
  }

  private func finish(
    _ result: CandidateResult,
    attemptToken: UUID
  ) -> CandidateResult {
    let invalidation = activeInvalidation
    let isCurrent = currentAttemptToken == attemptToken

    if isCurrent {
      currentAttemptToken = nil
    }
    activeWork = nil
    activeInvalidation = nil

    if let invalidation {
      // A concrete external or policy failure that completed before actor-side invalidation is
      // more specific than cancellation and remains the first terminal reason.
      if case .failure(let failure) = result, failure.reason != .cancelled {
        return result
      }
      return Self.failed(
        invalidation,
        recoveryReceipt: result.failureRecoveryReceipt
      )
    }
    guard isCurrent else {
      return Self.failed(
        .staleCompletion,
        recoveryReceipt: result.failureRecoveryReceipt
      )
    }
    return result
  }

  private static func performBinding(
    frozenIdentity: PowerPointWindowIdentity,
    bindingSessionToken: String,
    observationReader: any ManagedSlideShowCompositeObservationReading,
    slideShowStarter: any ManagedSlideShowStarting,
    pollWaiter: any ManagedSlideShowBindingPollWaiting,
    machClock: any ManagedSlideShowBindingMachClock,
    maximumPostStartObservationCount: Int
  ) async -> CandidateResult {
    guard !Task.isCancelled else { return failed(.cancelled) }

    var lastClockMachAbsoluteTime: UInt64?
    let baseline: ManagedSlideShowInventoryObservation
    switch await readBracketedObservation(
      bindingSessionToken: bindingSessionToken,
      frozenIdentity: frozenIdentity,
      observationReader: observationReader,
      machClock: machClock,
      previousClockMachAbsoluteTime: lastClockMachAbsoluteTime,
      baseline: true
    ) {
    case .failure(let failure):
      return failed(failure)
    case .success(let bracketed):
      baseline = bracketed.observation
      lastClockMachAbsoluteTime = bracketed.completionMachAbsoluteTime
    }

    let frozenManagedIdentity = ManagedSlideShowWindowIdentity(
      windowID: Int(frozenIdentity.windowID),
      processIdentifier: Int(frozenIdentity.ownerProcessID),
      bundleIdentifier: frozenIdentity.bundleIdentifier
    )
    guard baseline.windows.contains(frozenManagedIdentity) else {
      return failed(.frozenWindowUnavailable)
    }
    let target = ManagedSlideShowBindingTarget(
      bindingSessionToken: bindingSessionToken,
      processIdentifier: Int(frozenIdentity.ownerProcessID),
      bundleIdentifier: frozenIdentity.bundleIdentifier,
      frozenWindowIdentity: frozenManagedIdentity
    )
    var policy = ManagedSlideShowBindingPolicy()
    switch policy.begin(target: target, baseline: baseline) {
    case .baselineAccepted:
      break
    case .rejected(let rejection):
      return failed(.policyRejected(rejection))
    default:
      return failed(.policyRejected(.notStarted))
    }
    guard !Task.isCancelled else { return failed(.cancelled) }

    let startReceipt: ManagedSlideShowStartReceipt
    do {
      startReceipt = try await slideShowStarter.startManagedSlideShow(
        ManagedSlideShowStartRequest(
          frozenWindowIdentity: frozenIdentity,
          bindingSessionToken: bindingSessionToken,
          requiredActivePresentationCount: 1,
          requiredPreexistingSlideShowWindowCount: 0
        )
      )
    } catch {
      if let recoverable = error as? PowerPointManagedSlideShowRecoverableStartFailure {
        return failed(
          startFailureReason(for: recoverable.reason),
          recoveryReceipt: recoverable.recoveryReceipt
        )
      }
      if error is PowerPointManagedSlideShowAppleEventClientFailure {
        return failed(startFailureReason(for: error))
      }
      if error as? ManagedSlideShowBindingClientError == .permissionDenied {
        return failed(.permissionDenied)
      }
      if error is CancellationError || Task.isCancelled {
        return failed(.cancelled)
      }
      return failed(.startCommandFailed)
    }
    guard startReceipt.processIdentifier > 0,
      !startReceipt.bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !startReceipt.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !startReceipt.slideShowObjectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return failed(.malformedStartReceipt)
    }
    guard startReceipt.bindingSessionToken == bindingSessionToken,
      startReceipt.processIdentifier == frozenIdentity.ownerProcessID,
      startReceipt.bundleIdentifier == frozenIdentity.bundleIdentifier
    else {
      return failed(.startReceiptMismatch)
    }

    guard !Task.isCancelled else {
      return failed(.cancelled, recoveryReceipt: startReceipt)
    }

    for observationIndex in 0..<maximumPostStartObservationCount {
      let observation: ManagedSlideShowInventoryObservation
      switch await readBracketedObservation(
        bindingSessionToken: bindingSessionToken,
        frozenIdentity: frozenIdentity,
        observationReader: observationReader,
        machClock: machClock,
        previousClockMachAbsoluteTime: lastClockMachAbsoluteTime,
        baseline: false
      ) {
      case .failure(let failure):
        return failed(failure, recoveryReceipt: startReceipt)
      case .success(let bracketed):
        observation = bracketed.observation
        lastClockMachAbsoluteTime = bracketed.completionMachAbsoluteTime
      }

      let event = policy.ingest(observation)
      if case .rejected(let rejection) = event {
        return failed(.policyRejected(rejection), recoveryReceipt: startReceipt)
      }
      guard !Task.isCancelled else {
        return failed(.cancelled, recoveryReceipt: startReceipt)
      }

      switch event {
      case .candidateConfirmed(let confirmedCandidate):
        guard confirmedCandidate.windowID <= Int(CGWindowID.max),
          let exactIdentity = PowerPointWindowIdentity(
            windowID: CGWindowID(confirmedCandidate.windowID),
            ownerProcessID: frozenIdentity.ownerProcessID,
            bundleIdentifier: confirmedCandidate.bundleIdentifier
          ),
          exactIdentity.ownerProcessID == pid_t(confirmedCandidate.processIdentifier)
        else {
          return failed(.windowIdentifierOutOfRange, recoveryReceipt: startReceipt)
        }
        return .success(
          ManagedSlideShowRuntimeCandidate(
            candidateWindowIdentity: exactIdentity,
            bindingSessionToken: bindingSessionToken,
            slideShowObjectToken: startReceipt.slideShowObjectToken
          )
        )
      case .rejected:
        return failed(
          .policyRejected(.confirmedCandidateEvidenceChanged),
          recoveryReceipt: startReceipt
        )
      case .awaitingSlideShowStart, .candidateAccepted:
        break
      case .baselineAccepted, .stable:
        return failed(
          .policyRejected(.confirmedCandidateEvidenceChanged),
          recoveryReceipt: startReceipt
        )
      }

      guard observationIndex + 1 < maximumPostStartObservationCount else { continue }
      do {
        try await pollWaiter.waitUntilNextObservation()
      } catch {
        if error as? ManagedSlideShowBindingClientError == .permissionDenied {
          return failed(.permissionDenied, recoveryReceipt: startReceipt)
        }
        if error is CancellationError || Task.isCancelled {
          return failed(.cancelled, recoveryReceipt: startReceipt)
        }
        return failed(.pollWaitFailed, recoveryReceipt: startReceipt)
      }
      guard !Task.isCancelled else {
        return failed(.cancelled, recoveryReceipt: startReceipt)
      }
    }

    return failed(.timedOut, recoveryReceipt: startReceipt)
  }

  private static func failed(
    _ reason: ManagedSlideShowBindingCoordinatorFailure,
    recoveryReceipt: ManagedSlideShowStartReceipt? = nil
  ) -> CandidateResult {
    .failure(
      ManagedSlideShowBindingFailure(
        reason: reason,
        recoveryReceipt: recoveryReceipt
      )
    )
  }

  private static func startFailureReason(
    for error: any Error
  ) -> ManagedSlideShowBindingCoordinatorFailure {
    guard let failure = error as? PowerPointManagedSlideShowAppleEventClientFailure else {
      return .startCommandFailed
    }
    switch failure {
    case .permissionDenied:
      return .permissionDenied
    case .cancelled:
      return .cancelled
    case .startCommandDeliveryUnknown:
      return .startCommandDeliveryUnknown
    case .startCommandReplyMissingPossiblyDelivered:
      return .startCommandReplyMissingPossiblyDelivered
    case .startCommandReplyMalformedPossiblyDelivered:
      return .startCommandReplyMalformedPossiblyDelivered
    default:
      return .startCommandFailed
    }
  }

  private struct BracketedObservation: Sendable {
    let observation: ManagedSlideShowInventoryObservation
    let completionMachAbsoluteTime: UInt64
  }

  private static func readBracketedObservation(
    bindingSessionToken: String,
    frozenIdentity: PowerPointWindowIdentity,
    observationReader: any ManagedSlideShowCompositeObservationReading,
    machClock: any ManagedSlideShowBindingMachClock,
    previousClockMachAbsoluteTime: UInt64?,
    baseline: Bool
  ) async -> Result<BracketedObservation, ManagedSlideShowBindingCoordinatorFailure> {
    let requestStartedMachAbsoluteTime = await machClock.now()
    guard !Task.isCancelled else { return .failure(.cancelled) }
    guard requestStartedMachAbsoluteTime > 0,
      previousClockMachAbsoluteTime.map({ requestStartedMachAbsoluteTime > $0 }) ?? true
    else {
      return .failure(.observationClockInvalid)
    }

    let request = ManagedSlideShowCompositeObservationRequest(
      bindingSessionToken: bindingSessionToken,
      processIdentifier: frozenIdentity.ownerProcessID,
      bundleIdentifier: frozenIdentity.bundleIdentifier,
      freshObservationToken: UUID().uuidString,
      requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime,
      phase: baseline ? .baseline : .postStart
    )
    let observation: ManagedSlideShowInventoryObservation
    do {
      observation = try await observationReader.readCompositeObservation(request)
    } catch {
      return .failure(readFailure(for: error, baseline: baseline))
    }

    let completionMachAbsoluteTime = await machClock.now()
    guard completionMachAbsoluteTime > requestStartedMachAbsoluteTime else {
      return .failure(.observationClockInvalid)
    }
    guard observation.freshObservationToken == request.freshObservationToken else {
      return .failure(.observationRequestTokenMismatch)
    }
    guard observation.observedMachAbsoluteTime >= requestStartedMachAbsoluteTime,
      observation.observedMachAbsoluteTime <= completionMachAbsoluteTime
    else {
      return .failure(.observationAcquisitionTimeOutOfBounds)
    }

    return .success(
      BracketedObservation(
        observation: observation,
        completionMachAbsoluteTime: completionMachAbsoluteTime
      )
    )
  }

  private static func readFailure(
    for error: any Error,
    baseline: Bool
  ) -> ManagedSlideShowBindingCoordinatorFailure {
    if error as? ManagedSlideShowBindingClientError == .permissionDenied {
      return .permissionDenied
    }
    if error is CancellationError || Task.isCancelled {
      return .cancelled
    }
    return baseline ? .baselineReadFailed : .postStartReadFailed
  }
}

extension Result where Failure == ManagedSlideShowBindingFailure {
  fileprivate var failureRecoveryReceipt: ManagedSlideShowStartReceipt? {
    guard case .failure(let failure) = self else { return nil }
    return failure.recoveryReceipt
  }
}
