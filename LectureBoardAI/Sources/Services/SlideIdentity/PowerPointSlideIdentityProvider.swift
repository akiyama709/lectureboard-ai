import Darwin
import Foundation
import LectureBoardCore

struct PowerPointSlideIdentityObservation: Equatable, Sendable {
  let sequenceNumber: UInt64
  let observedAt: Date
  let targetIdentity: PowerPointWindowIdentity
  let signal: SlideIdentitySignal
}

typealias PowerPointSlideIdentityObservationHandler =
  @Sendable (PowerPointSlideIdentityObservation) -> Void

protocol PowerPointSlideIdentityProviding: Sendable {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async

  func stop(operationID: CaptureOperationID) async
}

/// One independently read PowerPoint slide identity, bound to the exact native
/// window identity selected for capture.
///
/// This runtime-only value deliberately carries the complete window identity. A
/// reader cannot return slide metadata alone and ask the provider to infer the
/// corresponding PowerPoint window from title, order, focus, or geometry.
struct ExactPowerPointSlideIdentityReading: Equatable, Sendable {
  let windowIdentity: PowerPointWindowIdentity
  let bindingSessionToken: String
  let slideShowObjectToken: String
  let captureOperationID: CaptureOperationID
  let captureGeneration: UInt64
  let pollToken: UUID
  let acquiredMachAbsoluteTime: UInt64
  let slideID: Int
  let slideIndex: Int
  private let validatedSample: SlideIdentitySample

  init?(
    windowIdentity: PowerPointWindowIdentity,
    bindingSessionToken: String,
    slideShowObjectToken: String,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    pollToken: UUID,
    acquiredMachAbsoluteTime: UInt64,
    slideID: Int,
    slideIndex: Int
  ) {
    guard
      !slideShowObjectToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      captureOperationID.rawValue > 0,
      captureGeneration > 0,
      acquiredMachAbsoluteTime > 0,
      let sample = SlideIdentitySample(
        presentationSessionToken: bindingSessionToken,
        slideID: slideID,
        slideIndex: slideIndex
      )
    else {
      return nil
    }

    self.windowIdentity = windowIdentity
    self.bindingSessionToken = bindingSessionToken
    self.slideShowObjectToken = slideShowObjectToken
    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.pollToken = pollToken
    self.acquiredMachAbsoluteTime = acquiredMachAbsoluteTime
    self.slideID = slideID
    self.slideIndex = slideIndex
    validatedSample = sample
  }

  var sample: SlideIdentitySample {
    validatedSample
  }
}

/// One exact-reader request. The per-poll token prevents a cached response from
/// being accepted for a later request even when every capture field is unchanged.
struct ExactPowerPointSlideIdentityReadRequest: Equatable, Sendable {
  let runtimeBinding: ManagedSlideShowRuntimeBinding
  let pollToken: UUID
  let requestStartedMachAbsoluteTime: UInt64
}

/// A future live adapter must independently obtain both exact-window identity
/// and semantic slide metadata. The request carries the exact
/// window, app-owned session token, and opaque object token from the exact
/// `run slide show` reply plus a fresh poll token that the reader must
/// independently return. Returning `nil` or throwing means unavailable; the
/// provider never fills missing identity, session, or time metadata from its request.
protocol ExactPowerPointSlideIdentityReadingClient: Sendable {
  func readExactSlideIdentity(
    for request: ExactPowerPointSlideIdentityReadRequest
  ) async throws -> ExactPowerPointSlideIdentityReading?
}

protocol PowerPointSlideIdentityPollWaiting: Sendable {
  func waitUntilNextPoll() async throws
}

protocol PowerPointSlideIdentityMachClock: Sendable {
  func now() async -> UInt64
}

struct SystemPowerPointSlideIdentityMachClock: PowerPointSlideIdentityMachClock {
  func now() async -> UInt64 {
    mach_absolute_time()
  }
}

protocol PowerPointSlideIdentityPollTokenGenerating: Sendable {
  func nextToken() async -> UUID
}

struct SystemPowerPointSlideIdentityPollTokenGenerator:
  PowerPointSlideIdentityPollTokenGenerating
{
  func nextToken() async -> UUID {
    UUID()
  }
}

struct TaskPowerPointSlideIdentityPollWaiter: PowerPointSlideIdentityPollWaiting {
  private let interval: Duration

  init(interval: Duration = .milliseconds(500)) {
    self.interval = min(
      max(interval, .milliseconds(100)),
      .seconds(5)
    )
  }

  func waitUntilNextPoll() async throws {
    try await Task.sleep(for: interval)
  }
}

enum ExactPowerPointSlideIdentityProviderStartResult: Equatable, Sendable {
  case started
  case rejectedPriorReadStillDraining
  case rejectedBindingOperationMismatch
  case rejectedBindingCaptureGenerationMismatch
  case rejectedStaleOperation
}

/// Bounded first-failure metadata. No raw token, identifier, time, or reader error is retained.
enum ExactPowerPointSlideIdentityProviderTerminalReason: Equatable, Sendable {
  case duplicatePollToken
  case invalidRequestClock
  case invalidCompletionClock
  case windowIdentityMismatch
  case bindingSessionTokenMismatch
  case slideShowObjectTokenMismatch
  case captureOperationIDMismatch
  case captureGenerationMismatch
  case pollTokenMismatch
  case invalidAcquisitionClock
  case sequenceExhausted
  case pollWaitFailed
}

/// Fail-closed polling shell for an exact PowerPoint semantic-identity reader.
///
/// No production reader is installed yet. In particular, this type performs no
/// Apple Event or Accessibility lookup and has no title/order/geometry fallback.
/// This actor deliberately does not conform to ``PowerPointSlideIdentityProviding``:
/// it cannot be installed as the app's general provider and started with a window
/// identity alone. Its start boundary accepts only a role-challenge-validated
/// ``ManagedSlideShowRuntimeBinding``. Each accepted start owns a fresh sequence
/// beginning at one. Reads are issued serially. A start attempted while prior
/// work has not drained is rejected immediately, so a noncooperative reader can
/// hold at most one provider task and cannot cause an unbounded replacement-task
/// chain. Stop invalidates callbacks immediately and does not await a reader that
/// may be blocked in an external API; its task reference remains retained until
/// that reader actually returns, and only then can a later start succeed.
actor ExactPowerPointSlideIdentityProvider {
  private let reader: any ExactPowerPointSlideIdentityReadingClient
  private let pollWaiter: any PowerPointSlideIdentityPollWaiting
  private let machClock: any PowerPointSlideIdentityMachClock
  private let pollTokenGenerator: any PowerPointSlideIdentityPollTokenGenerating
  private let terminalSequenceNumber: UInt64

  private var lifecycle = CaptureSessionLifecycle()
  private var pollingTask: Task<Void, Never>?
  private var pollingTaskToken: UUID?
  private var activePollingToken: UUID?
  private var runtimeBinding: ManagedSlideShowRuntimeBinding?
  private var observationHandler: PowerPointSlideIdentityObservationHandler?
  private var nextSequenceNumber: UInt64 = 1
  private var lastRequestStartedMachAbsoluteTime: UInt64?
  private var lastAcquiredMachAbsoluteTime: UInt64?
  private var lastRequestCompletedMachAbsoluteTime: UInt64?
  private var issuedPollTokens: Set<UUID> = []
  private(set) var firstTerminalReason: ExactPowerPointSlideIdentityProviderTerminalReason?

  init(
    reader: any ExactPowerPointSlideIdentityReadingClient,
    pollWaiter: any PowerPointSlideIdentityPollWaiting =
      TaskPowerPointSlideIdentityPollWaiter(),
    machClock: any PowerPointSlideIdentityMachClock =
      SystemPowerPointSlideIdentityMachClock(),
    pollTokenGenerator: any PowerPointSlideIdentityPollTokenGenerating =
      SystemPowerPointSlideIdentityPollTokenGenerator(),
    terminalSequenceNumber: UInt64 = .max
  ) {
    precondition(terminalSequenceNumber > 0)
    self.reader = reader
    self.pollWaiter = pollWaiter
    self.machClock = machClock
    self.pollTokenGenerator = pollTokenGenerator
    self.terminalSequenceNumber = terminalSequenceNumber
  }

  var latestOperationID: CaptureOperationID? {
    lifecycle.latestOperationID
  }

  var activeOperationID: CaptureOperationID? {
    lifecycle.activeSessionID
  }

  var hasUndrainedPollingTask: Bool {
    pollingTask != nil
  }

  func start(
    operationID: CaptureOperationID,
    currentCaptureGeneration: UInt64,
    binding: ManagedSlideShowRuntimeBinding,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async -> ExactPowerPointSlideIdentityProviderStartResult {
    guard lifecycle.acceptStart(operationID) else {
      return .rejectedStaleOperation
    }

    // A newer operation invalidates callbacks immediately, even when its own start
    // is rejected. The old task remains retained until every noncooperative await drains.
    invalidateActivePolling()
    firstTerminalReason = nil

    guard pollingTask == nil else {
      lifecycle.finishFailedStart(operationID)
      return .rejectedPriorReadStillDraining
    }
    guard binding.captureOperationID == operationID else {
      lifecycle.finishFailedStart(operationID)
      return .rejectedBindingOperationMismatch
    }
    guard
      currentCaptureGeneration > 0,
      binding.captureGeneration == currentCaptureGeneration
    else {
      lifecycle.finishFailedStart(operationID)
      return .rejectedBindingCaptureGenerationMismatch
    }

    let token = UUID()
    pollingTaskToken = token
    activePollingToken = token
    runtimeBinding = binding
    observationHandler = onObservation
    nextSequenceNumber = 1
    lastRequestStartedMachAbsoluteTime = nil
    lastAcquiredMachAbsoluteTime = nil
    lastRequestCompletedMachAbsoluteTime = nil
    issuedPollTokens = []

    pollingTask = Task { [weak self] in
      await self?.poll(
        operationID: operationID,
        pollingToken: token
      )
    }
    return .started
  }

  func stop(operationID: CaptureOperationID) async {
    guard lifecycle.acceptStop(operationID) else { return }
    invalidateActivePolling()
    firstTerminalReason = nil
  }

  private func poll(
    operationID: CaptureOperationID,
    pollingToken: UUID
  ) async {
    defer {
      finishPollingIfOwned(
        operationID: operationID,
        pollingToken: pollingToken
      )
    }

    while isCurrent(operationID: operationID, pollingToken: pollingToken) {
      guard
        let requestedBinding = runtimeBinding,
        let observationHandler
      else {
        return
      }
      guard nextSequenceNumber < terminalSequenceNumber else {
        emitTerminalUnavailable(
          .sequenceExhausted,
          binding: requestedBinding,
          handler: observationHandler
        )
        return
      }

      let pollToken = await pollTokenGenerator.nextToken()
      guard
        !Task.isCancelled,
        isCurrent(operationID: operationID, pollingToken: pollingToken),
        runtimeBinding == requestedBinding
      else {
        return
      }
      guard issuedPollTokens.insert(pollToken).inserted else {
        emitTerminalUnavailable(
          .duplicatePollToken,
          binding: requestedBinding,
          handler: observationHandler
        )
        return
      }

      let requestStartedMachAbsoluteTime = await machClock.now()
      guard
        !Task.isCancelled,
        isCurrent(operationID: operationID, pollingToken: pollingToken),
        runtimeBinding == requestedBinding
      else {
        return
      }
      guard
        requestTimeIsValid(
          requestStartedMachAbsoluteTime,
          freshnessBoundaryMachAbsoluteTime:
            requestedBinding.freshnessBoundaryMachAbsoluteTime
        )
      else {
        emitTerminalUnavailable(
          .invalidRequestClock,
          binding: requestedBinding,
          handler: observationHandler
        )
        return
      }
      let request = ExactPowerPointSlideIdentityReadRequest(
        runtimeBinding: requestedBinding,
        pollToken: pollToken,
        requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime
      )

      let reading: ExactPowerPointSlideIdentityReading?
      do {
        reading = try await reader.readExactSlideIdentity(for: request)
      } catch {
        reading = nil
      }

      guard
        !Task.isCancelled,
        isCurrent(operationID: operationID, pollingToken: pollingToken),
        let runtimeBinding,
        runtimeBinding == requestedBinding,
        self.observationHandler != nil
      else {
        return
      }

      let requestCompletedMachAbsoluteTime = await machClock.now()
      guard
        !Task.isCancelled,
        isCurrent(operationID: operationID, pollingToken: pollingToken),
        self.runtimeBinding == requestedBinding,
        self.observationHandler != nil
      else {
        return
      }
      guard
        completionTimeIsValid(
          requestCompletedMachAbsoluteTime,
          requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime
        )
      else {
        emitTerminalUnavailable(
          .invalidCompletionClock,
          binding: requestedBinding,
          handler: observationHandler
        )
        return
      }

      let signal: SlideIdentitySignal
      if let reading {
        if let reason = terminalReason(
          for: reading,
          request: request,
          requestCompletedMachAbsoluteTime: requestCompletedMachAbsoluteTime
        ) {
          emitTerminalUnavailable(
            reason,
            binding: requestedBinding,
            handler: observationHandler
          )
          return
        }
        lastAcquiredMachAbsoluteTime = reading.acquiredMachAbsoluteTime
        signal = .available(reading.sample)
      } else {
        signal = .unavailable
      }
      lastRequestStartedMachAbsoluteTime = requestStartedMachAbsoluteTime
      lastRequestCompletedMachAbsoluteTime = requestCompletedMachAbsoluteTime

      let sequenceNumber = emit(
        signal,
        binding: runtimeBinding,
        handler: observationHandler
      )

      nextSequenceNumber = sequenceNumber + 1

      do {
        try await pollWaiter.waitUntilNextPoll()
      } catch {
        if !Task.isCancelled,
          isCurrent(operationID: operationID, pollingToken: pollingToken),
          runtimeBinding == requestedBinding,
          self.observationHandler != nil
        {
          emitTerminalUnavailable(
            .pollWaitFailed,
            binding: requestedBinding,
            handler: observationHandler
          )
        }
        return
      }
      guard !Task.isCancelled else { return }
    }
  }

  private func isCurrent(
    operationID: CaptureOperationID,
    pollingToken: UUID
  ) -> Bool {
    lifecycle.isCurrent(operationID) && activePollingToken == pollingToken
  }

  private func requestTimeIsValid(
    _ requestStartedMachAbsoluteTime: UInt64,
    freshnessBoundaryMachAbsoluteTime: UInt64
  ) -> Bool {
    guard
      requestStartedMachAbsoluteTime > 0,
      requestStartedMachAbsoluteTime > freshnessBoundaryMachAbsoluteTime,
      lastRequestStartedMachAbsoluteTime.map({ requestStartedMachAbsoluteTime > $0 }) ?? true,
      lastAcquiredMachAbsoluteTime.map({ requestStartedMachAbsoluteTime > $0 }) ?? true,
      lastRequestCompletedMachAbsoluteTime.map({ requestStartedMachAbsoluteTime > $0 }) ?? true
    else {
      return false
    }
    return true
  }

  private func completionTimeIsValid(
    _ requestCompletedMachAbsoluteTime: UInt64,
    requestStartedMachAbsoluteTime: UInt64
  ) -> Bool {
    guard
      requestCompletedMachAbsoluteTime > requestStartedMachAbsoluteTime,
      lastRequestStartedMachAbsoluteTime.map({ requestCompletedMachAbsoluteTime > $0 }) ?? true,
      lastAcquiredMachAbsoluteTime.map({ requestCompletedMachAbsoluteTime > $0 }) ?? true,
      lastRequestCompletedMachAbsoluteTime.map({ requestCompletedMachAbsoluteTime > $0 }) ?? true
    else {
      return false
    }
    return true
  }

  private func terminalReason(
    for reading: ExactPowerPointSlideIdentityReading,
    request: ExactPowerPointSlideIdentityReadRequest,
    requestCompletedMachAbsoluteTime: UInt64
  ) -> ExactPowerPointSlideIdentityProviderTerminalReason? {
    let binding = request.runtimeBinding
    guard reading.windowIdentity == binding.windowIdentity else {
      return .windowIdentityMismatch
    }
    guard reading.bindingSessionToken == binding.bindingSessionToken else {
      return .bindingSessionTokenMismatch
    }
    guard reading.slideShowObjectToken == binding.slideShowObjectToken else {
      return .slideShowObjectTokenMismatch
    }
    guard reading.captureOperationID == binding.captureOperationID else {
      return .captureOperationIDMismatch
    }
    guard reading.captureGeneration == binding.captureGeneration else {
      return .captureGenerationMismatch
    }
    guard reading.pollToken == request.pollToken else {
      return .pollTokenMismatch
    }
    guard
      reading.acquiredMachAbsoluteTime > binding.freshnessBoundaryMachAbsoluteTime,
      reading.acquiredMachAbsoluteTime > request.requestStartedMachAbsoluteTime,
      reading.acquiredMachAbsoluteTime <= requestCompletedMachAbsoluteTime,
      lastAcquiredMachAbsoluteTime.map({ reading.acquiredMachAbsoluteTime > $0 }) ?? true,
      lastRequestCompletedMachAbsoluteTime.map({ reading.acquiredMachAbsoluteTime > $0 }) ?? true
    else {
      return .invalidAcquisitionClock
    }
    return nil
  }

  @discardableResult
  private func emit(
    _ signal: SlideIdentitySignal,
    binding: ManagedSlideShowRuntimeBinding,
    handler: PowerPointSlideIdentityObservationHandler
  ) -> UInt64 {
    let sequenceNumber = nextSequenceNumber
    handler(
      PowerPointSlideIdentityObservation(
        sequenceNumber: sequenceNumber,
        observedAt: Date(),
        targetIdentity: binding.windowIdentity,
        signal: signal
      )
    )
    return sequenceNumber
  }

  private func emitTerminalUnavailable(
    _ reason: ExactPowerPointSlideIdentityProviderTerminalReason,
    binding: ManagedSlideShowRuntimeBinding,
    handler: PowerPointSlideIdentityObservationHandler
  ) {
    latchTerminalReason(reason)
    _ = emit(.unavailable, binding: binding, handler: handler)
  }

  private func latchTerminalReason(
    _ reason: ExactPowerPointSlideIdentityProviderTerminalReason
  ) {
    if firstTerminalReason == nil {
      firstTerminalReason = reason
    }
  }

  private func invalidateActivePolling() {
    pollingTask?.cancel()
    activePollingToken = nil
    runtimeBinding = nil
    observationHandler = nil
    nextSequenceNumber = 1
    lastRequestStartedMachAbsoluteTime = nil
    lastAcquiredMachAbsoluteTime = nil
    lastRequestCompletedMachAbsoluteTime = nil
    issuedPollTokens = []
  }

  private func finishPollingIfOwned(
    operationID: CaptureOperationID,
    pollingToken: UUID
  ) {
    guard pollingTaskToken == pollingToken else {
      return
    }
    pollingTask = nil
    pollingTaskToken = nil
    if activePollingToken == pollingToken {
      lifecycle.finishFailedStart(operationID)
    }
    activePollingToken = nil
    runtimeBinding = nil
    observationHandler = nil
    nextSequenceNumber = 1
    lastRequestStartedMachAbsoluteTime = nil
    lastAcquiredMachAbsoluteTime = nil
    lastRequestCompletedMachAbsoluteTime = nil
    issuedPollTokens = []
  }
}

/// The fail-closed default used until an exact, independently verified PowerPoint
/// slide-identity adapter is available.
///
/// It sends one metadata-only `.unavailable` observation for each accepted start.
/// It never requests Automation permission, sends Apple events, or retains a
/// presentation path, title, identity, or callback after `start` returns.
actor UnavailablePowerPointSlideIdentityProvider: PowerPointSlideIdentityProviding {
  private var lifecycle = CaptureSessionLifecycle()

  var latestOperationID: CaptureOperationID? {
    lifecycle.latestOperationID
  }

  var activeOperationID: CaptureOperationID? {
    lifecycle.activeSessionID
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async {
    guard lifecycle.acceptStart(operationID) else { return }

    onObservation(
      PowerPointSlideIdentityObservation(
        sequenceNumber: 1,
        observedAt: Date(),
        targetIdentity: identity,
        signal: .unavailable
      )
    )
  }

  func stop(operationID: CaptureOperationID) async {
    _ = lifecycle.acceptStop(operationID)
  }
}
