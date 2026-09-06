import AppKit
import ApplicationServices
import Darwin
import Foundation
import LectureBoardCore

struct PowerPointManagedSlideShowProcessIdentity: Equatable, Sendable {
  let processIdentifier: pid_t
  let bundleIdentifier: String
}

protocol PowerPointManagedSlideShowProcessIdentityReading: Sendable {
  func currentIdentity(
    for processIdentifier: pid_t
  ) async -> PowerPointManagedSlideShowProcessIdentity?
}

struct SystemPowerPointManagedSlideShowProcessIdentityReader:
  PowerPointManagedSlideShowProcessIdentityReading
{
  func currentIdentity(
    for processIdentifier: pid_t
  ) async -> PowerPointManagedSlideShowProcessIdentity? {
    guard
      let application = NSRunningApplication(processIdentifier: processIdentifier),
      let bundleIdentifier = application.bundleIdentifier
    else { return nil }
    return PowerPointManagedSlideShowProcessIdentity(
      processIdentifier: application.processIdentifier,
      bundleIdentifier: bundleIdentifier
    )
  }
}

protocol PowerPointManagedSlideShowWindowInventoryReading: Sendable {
  func readExactWindowInventory(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [ManagedSlideShowWindowIdentity]
}

struct SystemPowerPointManagedSlideShowWindowInventoryReader:
  PowerPointManagedSlideShowWindowInventoryReading
{
  private let scanner = PowerPointWindowScanner()

  func readExactWindowInventory(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [ManagedSlideShowWindowIdentity] {
    try await scanner.scan()
      .filter {
        $0.ownerProcessID == processIdentifier
          && $0.bundleIdentifier == bundleIdentifier
      }
      .map {
        ManagedSlideShowWindowIdentity(
          windowID: Int($0.id),
          processIdentifier: Int($0.ownerProcessID),
          bundleIdentifier: $0.bundleIdentifier
        )
      }
  }
}

protocol PowerPointManagedSlideShowPermissionChecking: Sendable {
  func passivePreflight(
    target: PowerPointAutomationPermissionTarget
  ) async -> PowerPointAutomationPermissionState
}

extension PowerPointAutomationPermissionService:
  PowerPointManagedSlideShowPermissionChecking
{}

/// Synchronous, actor-owned Apple Event transport.
///
/// `NSAppleEventDescriptor` deliberately never crosses an actor boundary. The system transport is
/// the only implementation that calls `sendEvent`; tests inject a descriptor-only fake.
protocol PowerPointManagedSlideShowAppleEventSending: AnyObject, Sendable {
  func send(
    _ event: NSAppleEventDescriptor,
    options: NSAppleEventDescriptor.SendOptions,
    timeout: TimeInterval
  ) throws -> NSAppleEventDescriptor?
}

final class SystemPowerPointManagedSlideShowAppleEventSender:
  PowerPointManagedSlideShowAppleEventSending, @unchecked Sendable
{
  func send(
    _ event: NSAppleEventDescriptor,
    options: NSAppleEventDescriptor.SendOptions,
    timeout: TimeInterval
  ) throws -> NSAppleEventDescriptor? {
    try event.sendEvent(options: options, timeout: timeout)
  }
}

/// Thread-safe cancellation latch used only to make explicit cancellation observable while the
/// actor is synchronously waiting for an Apple Event reply. It never owns a descriptor.
private final class PowerPointManagedSlideShowOperationCancellationLatch:
  @unchecked Sendable
{
  private let lock = NSLock()
  private var activeToken: UUID?
  private var cancelledToken: UUID?
  private var sessionInvalidated = false

  func begin(_ token: UUID) -> Bool {
    lock.withLock {
      guard activeToken == nil, !sessionInvalidated else { return false }
      activeToken = token
      cancelledToken = nil
      return true
    }
  }

  /// Recovery is permitted after invalidation, but never while an older operation still drains.
  func beginRecovery(_ token: UUID) -> Bool {
    lock.withLock {
      guard activeToken == nil else { return false }
      activeToken = token
      cancelledToken = nil
      return true
    }
  }

  func cancelCurrent() {
    lock.withLock {
      cancelledToken = activeToken
    }
  }

  func invalidateSession() {
    lock.withLock {
      sessionInvalidated = true
      cancelledToken = activeToken
    }
  }

  var isSessionInvalidated: Bool {
    lock.withLock { sessionInvalidated }
  }

  func isCancelled(_ token: UUID) -> Bool {
    lock.withLock { activeToken == token && cancelledToken == token }
  }

  func beginPossiblyDeliveringSend(_ token: UUID) -> Bool {
    lock.withLock {
      activeToken == token && cancelledToken != token
    }
  }

  func beginPossiblyDeliveringRecoverySend(_ token: UUID) -> Bool {
    lock.withLock { activeToken == token }
  }

  func finish(_ token: UUID) {
    lock.withLock {
      guard activeToken == token else { return }
      activeToken = nil
      cancelledToken = nil
    }
  }
}

/// Process-local reservation boundary for opaque object tokens.
///
/// A shared registry can be injected by the outer transaction when several Stage A actors may be
/// created in one process. Reservation happens before `run slide show` is sent.
protocol PowerPointManagedSlideShowOpaqueObjectTokenReserving: Sendable {
  func reserveStart(
    bindingSessionToken: String,
    objectToken: String
  ) -> PowerPointManagedSlideShowStartReservationResult

  func releaseObjectToken(
    bindingSessionToken: String,
    objectToken: String
  )
}

enum PowerPointManagedSlideShowStartReservationResult: Equatable, Sendable {
  case reserved
  case sessionAlreadyConsumed
  case objectTokenUnavailable
}

/// Exact-object semantic request used by the Stage B capture-evidence broker.
///
/// The request has no title, ordering, geometry, or collection index. Its opaque object token must
/// resolve to the descriptor retained from this session's single `run slide show` reply.
struct PowerPointManagedSlideShowRoleSemanticStateRequest: Equatable, Sendable {
  let bindingSessionToken: String
  let slideShowObjectToken: String
  let processIdentifier: Int
  let bundleIdentifier: String
  let freshRequestToken: String
  let requestStartedMachAbsoluteTime: UInt64
}

struct PowerPointManagedSlideShowRoleSemanticStateReading: Equatable, Sendable {
  let request: PowerPointManagedSlideShowRoleSemanticStateRequest
  let acquiredMachAbsoluteTime: UInt64
  let semanticState: ManagedSlideShowRoleSemanticState
}

protocol PowerPointManagedSlideShowRoleSemanticStateReadingClient: Sendable {
  func readExactRoleSemanticState(
    _ request: PowerPointManagedSlideShowRoleSemanticStateRequest
  ) async throws -> PowerPointManagedSlideShowRoleSemanticStateReading
}

final class PowerPointManagedSlideShowOpaqueObjectTokenRegistry:
  PowerPointManagedSlideShowOpaqueObjectTokenReserving, @unchecked Sendable
{
  /// The production default. Consumed session tokens deliberately remain tombstoned for this
  /// process lifetime, so constructing another client cannot replay a managed start for the same
  /// session. Object-token reservations are released explicitly after rollback/teardown.
  static let processShared = PowerPointManagedSlideShowOpaqueObjectTokenRegistry()

  private let lock = NSLock()
  private var consumedSessionTokens: Set<String> = []
  private var reservedTokens: Set<String> = []

  func reserveStart(
    bindingSessionToken: String,
    objectToken: String
  ) -> PowerPointManagedSlideShowStartReservationResult {
    lock.withLock {
      guard !consumedSessionTokens.contains(bindingSessionToken) else {
        return .sessionAlreadyConsumed
      }
      consumedSessionTokens.insert(bindingSessionToken)
      let trimmedObjectToken = objectToken.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !trimmedObjectToken.isEmpty,
        trimmedObjectToken == objectToken,
        !reservedTokens.contains(objectToken)
      else {
        return .objectTokenUnavailable
      }
      reservedTokens.insert(objectToken)
      return .reserved
    }
  }

  func releaseObjectToken(
    bindingSessionToken: String,
    objectToken: String
  ) {
    lock.withLock {
      guard consumedSessionTokens.contains(bindingSessionToken) else { return }
      reservedTokens.remove(objectToken)
    }
  }
}

enum PowerPointManagedSlideShowAppleEventClientFailure:
  Error, Equatable, Sendable
{
  case malformedConfiguration
  case malformedRequest
  case staleSession
  case targetIdentityMismatch
  case permissionDenied
  case permissionRequiresExplicitUserAction
  case targetNotRunning
  case permissionUnavailable
  case priorOperationStillDraining
  case cancelled
  case staleCompletion
  case descriptorConstructionFailed
  case appleEventTransportFailed
  case malformedReply
  case countOutOfBounds
  case unstableCompositeObservation
  case windowInventoryReadFailed
  case malformedWindowInventory
  case frozenWindowUnavailable
  case startAttemptAlreadyConsumed
  case startPreconditionMismatch
  case unsupportedSlideShowType
  case slideShowTypeUnavailable
  case opaqueObjectTokenUnavailable
  case startCommandDeliveryUnknown
  case startCommandReplyMissingPossiblyDelivered
  case startCommandReplyMalformedPossiblyDelivered
  case objectTokenMismatch
  case requestAlreadyConsumed
  case exactObjectUnavailable
  case semanticStateUnstable
  case semanticValueOutOfBounds
  case invalidMachAbsoluteTime
  case recoveryCommandDeliveryUnknown
  case recoveryCommandReplyMalformedPossiblyDelivered
}

/// A valid returned object was retained before cancellation or invalidation won the race.
///
/// The caller must preserve this receipt and use the same client actor for exact-object rollback.
/// The underlying failure remains bounded and is not collapsed into an ordinary pre-start error.
struct PowerPointManagedSlideShowRecoverableStartFailure:
  Error, Equatable, Sendable
{
  let reason: PowerPointManagedSlideShowAppleEventClientFailure
  let recoveryReceipt: ManagedSlideShowStartReceipt
}

/// Session-bound Stage A PowerPoint adapter for managed slide-show correlation.
///
/// The actor implements only the causal baseline/start/post-start inventory boundary. It does not
/// establish the role of a Core Graphics window, create or own a ScreenCaptureKit stream, perform
/// the reversible role challenge, or construct a semantic slide binding. A successful start keeps
/// PowerPoint's returned slide-show object specifier actor-isolated and returns only a fresh opaque
/// token. Any call that may have sent `run slide show` consumes the session's single start attempt,
/// even when its reply is missing or malformed.
actor PowerPointManagedSlideShowAppleEventClient:
  ManagedSlideShowCompositeObservationReading,
  ManagedSlideShowStarting,
  PowerPointManagedSlideShowRoleObjectCommanding,
  PowerPointManagedSlideShowRoleSemanticStateReadingClient,
  ExactPowerPointSlideIdentityReadingClient
{
  private static let maximumScriptingCount: Int32 = 4_096

  private let sessionContext: ManagedSlideShowSessionContext
  private let permissionChecker: any PowerPointManagedSlideShowPermissionChecking
  private let identityReader: any PowerPointManagedSlideShowProcessIdentityReading
  private let windowInventoryReader: any PowerPointManagedSlideShowWindowInventoryReading
  private let eventSender: any PowerPointManagedSlideShowAppleEventSending
  private let machClock: any ManagedSlideShowBindingMachClock
  private let opaqueObjectTokenFactory: @Sendable () -> String
  private let opaqueObjectTokenRegistry: any PowerPointManagedSlideShowOpaqueObjectTokenReserving
  private let eventTimeout: TimeInterval
  private let eventTimeoutIsValid: Bool
  private let codec = PowerPointAppleEventDescriptorCodec()
  nonisolated private let operationCancellationLatch =
    PowerPointManagedSlideShowOperationCancellationLatch()

  private var activeOperationToken: UUID?
  private var startAttemptConsumed = false
  private var retainedSlideShowObject:
    (token: String, object: PowerPointAppleEventRuntimeObjectSpecifier)?
  private var issuedObjectTokens: Set<String> = []
  private var issuedObjectOperationRequestTokens: Set<String> = []
  private var issuedIdentityPollTokens: Set<UUID> = []
  private var lastObjectMachAbsoluteTime: UInt64 = 0

  init(
    sessionContext: ManagedSlideShowSessionContext,
    permissionChecker: (any PowerPointManagedSlideShowPermissionChecking)? = nil,
    identityReader: any PowerPointManagedSlideShowProcessIdentityReading =
      SystemPowerPointManagedSlideShowProcessIdentityReader(),
    windowInventoryReader: any PowerPointManagedSlideShowWindowInventoryReading =
      SystemPowerPointManagedSlideShowWindowInventoryReader(),
    eventSender: any PowerPointManagedSlideShowAppleEventSending =
      SystemPowerPointManagedSlideShowAppleEventSender(),
    machClock: any ManagedSlideShowBindingMachClock =
      SystemManagedSlideShowBindingMachClock(),
    opaqueObjectTokenFactory: @escaping @Sendable () -> String = {
      UUID().uuidString
    },
    opaqueObjectTokenRegistry:
      (any PowerPointManagedSlideShowOpaqueObjectTokenReserving)? = nil,
    eventTimeout: TimeInterval = 2
  ) {
    self.sessionContext = sessionContext
    self.permissionChecker =
      permissionChecker
      ?? PowerPointAutomationPermissionService(
        bindingSessionToken: sessionContext.bindingSessionToken
      )
    self.identityReader = identityReader
    self.windowInventoryReader = windowInventoryReader
    self.eventSender = eventSender
    self.machClock = machClock
    self.opaqueObjectTokenFactory = opaqueObjectTokenFactory
    self.opaqueObjectTokenRegistry =
      opaqueObjectTokenRegistry
      ?? PowerPointManagedSlideShowOpaqueObjectTokenRegistry.processShared
    self.eventTimeoutIsValid = eventTimeout.isFinite
    self.eventTimeout =
      eventTimeout.isFinite
      ? min(max(eventTimeout, 0.1), 10)
      : eventTimeout
  }

  private var bindingSessionToken: String {
    sessionContext.bindingSessionToken
  }

  private var processIdentifier: pid_t {
    sessionContext.frozenWindowIdentity.ownerProcessID
  }

  private var bundleIdentifier: String {
    sessionContext.frozenWindowIdentity.bundleIdentifier
  }

  func readCompositeObservation(
    _ request: ManagedSlideShowCompositeObservationRequest
  ) async throws -> ManagedSlideShowInventoryObservation {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    try validateObservationRequest(request)
    try checkOperation(operationToken)

    let permitsFrozenWindowAbsence =
      request.phase == .postStart && retainedSlideShowObject != nil
    if request.phase == .postStart, !permitsFrozenWindowAbsence {
      throw PowerPointManagedSlideShowAppleEventClientFailure.exactObjectUnavailable
    }
    try await requireAuthorizedTarget(
      operationToken: operationToken,
      requireFrozenWindow: !permitsFrozenWindowAbsence
    )

    let firstActivePresentationCount = try readCount(
      .presentation,
      operationToken: operationToken
    )
    let firstSlideShowWindowCount = try readCount(
      .slideShowWindow,
      operationToken: operationToken
    )

    let windows = try await readValidatedWindowInventory(
      operationToken: operationToken,
      requireFrozenWindow: !permitsFrozenWindowAbsence
    )

    let secondActivePresentationCount = try readCount(
      .presentation,
      operationToken: operationToken
    )
    let secondSlideShowWindowCount = try readCount(
      .slideShowWindow,
      operationToken: operationToken
    )
    guard firstActivePresentationCount == secondActivePresentationCount,
      firstSlideShowWindowCount == secondSlideShowWindowCount
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .unstableCompositeObservation
    }
    try await requireExactTargetIdentity(operationToken: operationToken)

    let observedMachAbsoluteTime = await machClock.now()
    try checkOperation(operationToken)
    guard observedMachAbsoluteTime >= request.requestStartedMachAbsoluteTime,
      observedMachAbsoluteTime > 0
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .unstableCompositeObservation
    }

    return ManagedSlideShowInventoryObservation(
      bindingSessionToken: bindingSessionToken,
      freshObservationToken: request.freshObservationToken,
      observedMachAbsoluteTime: observedMachAbsoluteTime,
      scriptingEvidence: ManagedSlideShowScriptingEvidence(
        processIdentifier: Int(processIdentifier),
        activePresentationCount: Int(firstActivePresentationCount),
        slideShowWindowCount: Int(firstSlideShowWindowCount)
      ),
      windows: windows
    )
  }

  func startManagedSlideShow(
    _ request: ManagedSlideShowStartRequest
  ) async throws -> ManagedSlideShowStartReceipt {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    try validateStartRequest(request)
    try checkOperation(operationToken)
    guard !startAttemptConsumed else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .startAttemptAlreadyConsumed
    }
    // A fresh binding session is required after any valid start attempt. This is latched before
    // permission or transport work so cancellation and uncertain delivery can never cause retry.
    startAttemptConsumed = true

    // Reserve and validate the only public handle before any possibly delivering send. An invalid
    // or process-local duplicate token must never allow `run slide show` to leave this actor.
    let opaqueToken = try reserveOpaqueObjectToken(operationToken: operationToken)
    var keepObjectTokenReservation = false
    defer {
      if !keepObjectTokenReservation {
        releaseObjectTokenReservation(opaqueToken)
      }
    }

    try await requireAuthorizedTarget(operationToken: operationToken)
    try await verifyStartPreconditions(request, operationToken: operationToken)

    let activePresentation = try readActivePresentation(
      operationToken: operationToken
    )
    try readRequiredWindowedSlideShowType(
      activePresentation: activePresentation,
      operationToken: operationToken
    )
    try await verifyStartPreconditions(request, operationToken: operationToken)

    guard
      let settings = codec.preStartPresentationPropertySpecifier(
        [.slideShowSettings],
        of: activePresentation
      ),
      let runEvent = codec.runSlideShowEvent(
        processIdentifier: Int32(processIdentifier),
        settings: settings
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    try checkOperation(operationToken)
    guard operationCancellationLatch.beginPossiblyDeliveringSend(operationToken),
      !Task.isCancelled
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.cancelled
    }

    // The latch check above is the atomic cancellation/send boundary. From that boundary onward
    // the command is considered possibly delivered. No code path is permitted to clear
    // `startAttemptConsumed` or resend it in this session.
    let reply: NSAppleEventDescriptor?
    do {
      // Cancellation after this synchronous send begins cannot prove whether PowerPoint acted.
      // Therefore the returned descriptor is always drained below before cancellation is surfaced.
      reply = try eventSender.send(
        runEvent,
        options: PowerPointAppleEventDescriptorCodec.sendOptions,
        timeout: eventTimeout
      )
    } catch {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .startCommandDeliveryUnknown
    }
    let returnedObject: PowerPointAppleEventRuntimeObjectSpecifier
    switch codec.parseReturnedSlideShowObjectSpecifierReply(reply) {
    case .failure(let failure):
      throw classifyPossiblyDeliveredStartReplyFailure(failure)
    case .value(let object):
      returnedObject = object
    }

    // The actual returned object is retained actor-locally even when cancellation was requested
    // while the synchronous transport was waiting. Only after retention may cancellation win.
    retainedSlideShowObject = (token: opaqueToken, object: returnedObject)
    keepObjectTokenReservation = true
    let receipt = ManagedSlideShowStartReceipt(
      bindingSessionToken: bindingSessionToken,
      processIdentifier: processIdentifier,
      bundleIdentifier: bundleIdentifier,
      slideShowObjectToken: opaqueToken
    )
    do {
      try checkOperation(operationToken)
    } catch let failure as PowerPointManagedSlideShowAppleEventClientFailure {
      throw PowerPointManagedSlideShowRecoverableStartFailure(
        reason: failure,
        recoveryReceipt: receipt
      )
    }
    return receipt
  }

  func readCapability(
    _ request: PowerPointManagedSlideShowRoleCapabilityRequest
  ) async throws -> PowerPointManagedSlideShowRoleCapabilityReceipt {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    let object = try validateRoleCapabilityRequest(request)
    try acceptObjectOperationRequestToken(request.freshRequestToken)
    try await requireAuthorizedObjectTarget(operationToken: operationToken)

    let state: PowerPointManagedSlideShowRoleCapabilityState
    switch request.capability {
    case .visibility:
      state = try await readVisibilityCapability(
        object: object,
        operationToken: operationToken
      )
    case .pixelNonce:
      state = try await readViewStateCapability(
        object: object,
        operationToken: operationToken
      )
    }
    return PowerPointManagedSlideShowRoleCapabilityReceipt(
      request: request,
      state: state
    )
  }

  func perform(
    _ request: PowerPointManagedSlideShowRoleCommandRequest
  ) async throws -> PowerPointManagedSlideShowRoleCommandReceipt {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    let object = try validateRoleCommandRequest(request)
    try acceptObjectOperationRequestToken(request.freshRequestToken)
    try await requireAuthorizedObjectTarget(operationToken: operationToken)

    switch request.command {
    case .establishBaseline:
      _ = try await readExactViewState(
        object: object,
        operationToken: operationToken
      )
    case .setVisibility(let visible):
      try await setExactVisibility(
        visible,
        object: object,
        operationToken: operationToken
      )
    case .setViewState(let state):
      try await setExactViewState(
        state,
        object: object,
        operationToken: operationToken
      )
    }

    let repliedMachAbsoluteTime = try await acceptObjectMachAbsoluteTime(
      minimum: 1,
      operationToken: operationToken
    )
    return PowerPointManagedSlideShowRoleCommandReceipt(
      request: request,
      repliedMachAbsoluteTime: repliedMachAbsoluteTime
    )
  }

  func readExactRoleSemanticState(
    _ request: PowerPointManagedSlideShowRoleSemanticStateRequest
  ) async throws -> PowerPointManagedSlideShowRoleSemanticStateReading {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    let object = try validateSemanticStateRequest(request)
    try acceptObjectOperationRequestToken(request.freshRequestToken)
    try await requireAuthorizedObjectTarget(operationToken: operationToken)
    let semanticState = try await readStableSemanticState(
      object: object,
      operationToken: operationToken
    )
    let acquiredMachAbsoluteTime = try await acceptObjectMachAbsoluteTime(
      minimum: request.requestStartedMachAbsoluteTime,
      strictlyAfterMinimum: true,
      operationToken: operationToken
    )
    return PowerPointManagedSlideShowRoleSemanticStateReading(
      request: request,
      acquiredMachAbsoluteTime: acquiredMachAbsoluteTime,
      semanticState: semanticState
    )
  }

  func readExactSlideIdentity(
    for request: ExactPowerPointSlideIdentityReadRequest
  ) async throws -> ExactPowerPointSlideIdentityReading? {
    let operationToken = try beginOperation()
    defer { finishOperation(operationToken) }

    try validateConfiguration()
    let object = try validateExactIdentityRequest(request)
    guard issuedIdentityPollTokens.insert(request.pollToken).inserted else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.requestAlreadyConsumed
    }
    try await requireAuthorizedObjectTarget(operationToken: operationToken)
    let semanticState = try await readStableSemanticState(
      object: object,
      operationToken: operationToken
    )
    let acquiredMachAbsoluteTime = try await acceptObjectMachAbsoluteTime(
      minimum: request.requestStartedMachAbsoluteTime,
      strictlyAfterMinimum: true,
      operationToken: operationToken
    )
    let binding = request.runtimeBinding
    guard
      let reading = ExactPowerPointSlideIdentityReading(
        windowIdentity: binding.windowIdentity,
        bindingSessionToken: binding.bindingSessionToken,
        slideShowObjectToken: binding.slideShowObjectToken,
        captureOperationID: binding.captureOperationID,
        captureGeneration: binding.captureGeneration,
        pollToken: request.pollToken,
        acquiredMachAbsoluteTime: acquiredMachAbsoluteTime,
        slideID: semanticState.slideID,
        slideIndex: semanticState.slideIndex
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.semanticValueOutOfBounds
    }
    return reading
  }

  /// Exits only the exact slide-show view retained for this receipt.
  ///
  /// This is the recovery boundary for a failed setup transaction. It remains callable after
  /// session invalidation, never inherits task cancellation, and keeps the descriptor and receipt
  /// when delivery or reply status is uncertain. A successful exit releases only the object-token
  /// reservation; the session's one-start tombstone remains process-wide.
  func exitRetainedSlideShowObject(
    _ receipt: ManagedSlideShowStartReceipt
  ) async throws {
    let operationToken = try beginRecoveryOperation()
    defer { finishOperation(operationToken) }

    try validateConfigurationForRecovery()
    let object = try retainedObject(for: receipt)
    let targetExists = try await requireRecoveryTarget(
      operationToken: operationToken
    )
    guard targetExists else {
      releaseRetainedObject(receipt.slideShowObjectToken)
      return
    }
    guard
      let event = codec.exitSlideShowEvent(
        processIdentifier: Int32(processIdentifier),
        slideShowWindow: object
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    guard operationCancellationLatch.beginPossiblyDeliveringRecoverySend(operationToken) else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .priorOperationStillDraining
    }
    let reply: NSAppleEventDescriptor?
    do {
      reply = try eventSender.send(
        event,
        options: PowerPointAppleEventDescriptorCodec.sendOptions,
        timeout: eventTimeout
      )
    } catch {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .recoveryCommandDeliveryUnknown
    }
    try checkRecoveryOperation(operationToken)
    switch codec.parseCommandReply(reply) {
    case .value:
      releaseRetainedObject(receipt.slideShowObjectToken)
    case .failure(let failure):
      throw classifyRecoveryReplyFailure(failure)
    }
  }

  /// Marks the current operation cancelled without allowing a replacement operation to overtake
  /// a non-cooperative dependency. The operation remains owned until that dependency returns.
  nonisolated func cancelCurrentOperation() {
    operationCancellationLatch.cancelCurrent()
  }

  /// Permanently closes this runtime-only session, including while synchronous transport blocks.
  ///
  /// Invalidation is a nonisolated latch so it cannot wait behind `sendEvent`. An exact returned
  /// object remains retained for rollback; the transaction must explicitly release it afterward.
  nonisolated func invalidateSession() {
    operationCancellationLatch.invalidateSession()
  }

  func ownsRetainedSlideShowObject(
    bindingSessionToken candidateSessionToken: String,
    slideShowObjectToken candidateObjectToken: String
  ) -> Bool {
    guard candidateSessionToken == bindingSessionToken,
      let retainedSlideShowObject
    else { return false }
    return retainedSlideShowObject.token == candidateObjectToken
  }

  /// Releases the retained exact object only after its owning transaction has completed rollback.
  /// The session-start tombstone remains process-local and cannot be replayed.
  func releaseRetainedSlideShowObject(
    _ receipt: ManagedSlideShowStartReceipt
  ) -> Bool {
    guard receipt.bindingSessionToken == bindingSessionToken,
      receipt.processIdentifier == processIdentifier,
      receipt.bundleIdentifier == bundleIdentifier,
      let retainedSlideShowObject,
      retainedSlideShowObject.token == receipt.slideShowObjectToken
    else { return false }
    releaseRetainedObject(receipt.slideShowObjectToken)
    return true
  }

  private func releaseRetainedObject(_ objectToken: String) {
    retainedSlideShowObject = nil
    releaseObjectTokenReservation(objectToken)
  }

  private func beginOperation() throws -> UUID {
    guard !operationCancellationLatch.isSessionInvalidated else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    }
    guard activeOperationToken == nil else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .priorOperationStillDraining
    }
    guard !Task.isCancelled else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.cancelled
    }
    let token = UUID()
    guard operationCancellationLatch.begin(token) else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .priorOperationStillDraining
    }
    activeOperationToken = token
    return token
  }

  private func beginRecoveryOperation() throws -> UUID {
    guard activeOperationToken == nil else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .priorOperationStillDraining
    }
    let token = UUID()
    guard operationCancellationLatch.beginRecovery(token) else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .priorOperationStillDraining
    }
    activeOperationToken = token
    return token
  }

  private func finishOperation(_ token: UUID) {
    guard activeOperationToken == token else { return }
    activeOperationToken = nil
    operationCancellationLatch.finish(token)
  }

  private func checkOperation(_ token: UUID) throws {
    guard activeOperationToken == token else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleCompletion
    }
    guard !operationCancellationLatch.isSessionInvalidated else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    }
    guard !operationCancellationLatch.isCancelled(token), !Task.isCancelled else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.cancelled
    }
  }

  private func checkRecoveryOperation(_ token: UUID) throws {
    guard activeOperationToken == token else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleCompletion
    }
  }

  private func validateConfiguration() throws {
    guard sessionContext.isWellFormed,
      processIdentifier > 0,
      bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier,
      !bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      eventTimeoutIsValid
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .malformedConfiguration
    }
  }

  private func validateConfigurationForRecovery() throws {
    guard sessionContext.isWellFormed,
      processIdentifier > 0,
      bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier,
      !bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      eventTimeoutIsValid
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .malformedConfiguration
    }
  }

  private func validateObservationRequest(
    _ request: ManagedSlideShowCompositeObservationRequest
  ) throws {
    guard request.processIdentifier > 0,
      request.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier,
      !request.bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !request.freshObservationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      request.requestStartedMachAbsoluteTime > 0
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    guard request.bindingSessionToken == bindingSessionToken else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    }
    guard request.processIdentifier == processIdentifier,
      request.bundleIdentifier == bundleIdentifier
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetIdentityMismatch
    }
  }

  private func validateStartRequest(
    _ request: ManagedSlideShowStartRequest
  ) throws {
    guard
      !request.bindingSessionToken
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      request.requiredActivePresentationCount == 1,
      request.requiredPreexistingSlideShowWindowCount == 0
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    guard request.bindingSessionToken == bindingSessionToken else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    }
    guard request.frozenWindowIdentity == sessionContext.frozenWindowIdentity
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetIdentityMismatch
    }
  }

  private func validateRoleCapabilityRequest(
    _ request: PowerPointManagedSlideShowRoleCapabilityRequest
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    guard request.challengeNonce > 0, isExactOpaqueToken(request.freshRequestToken) else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    return try retainedObject(
      bindingSessionToken: request.bindingSessionToken,
      objectToken: request.slideShowObjectToken,
      requestProcessIdentifier: request.processIdentifier,
      requestBundleIdentifier: request.bundleIdentifier
    )
  }

  private func validateRoleCommandRequest(
    _ request: PowerPointManagedSlideShowRoleCommandRequest
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    guard request.challengeNonce > 0,
      request.challengeNonce <= UInt64.max - 3,
      request.phaseNonce >= request.challengeNonce,
      request.phaseNonce <= request.challengeNonce + 3,
      isExactOpaqueToken(request.freshRequestToken)
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    switch request.command {
    case .establishBaseline:
      guard request.phaseNonce == request.challengeNonce else {
        throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
      }
    case .setVisibility, .setViewState:
      guard request.phaseNonce > request.challengeNonce else {
        throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
      }
    }
    return try retainedObject(
      bindingSessionToken: request.bindingSessionToken,
      objectToken: request.slideShowObjectToken,
      requestProcessIdentifier: request.processIdentifier,
      requestBundleIdentifier: request.bundleIdentifier
    )
  }

  private func validateSemanticStateRequest(
    _ request: PowerPointManagedSlideShowRoleSemanticStateRequest
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    guard isExactOpaqueToken(request.freshRequestToken),
      request.requestStartedMachAbsoluteTime > 0
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    return try retainedObject(
      bindingSessionToken: request.bindingSessionToken,
      objectToken: request.slideShowObjectToken,
      requestProcessIdentifier: request.processIdentifier,
      requestBundleIdentifier: request.bundleIdentifier
    )
  }

  private func validateExactIdentityRequest(
    _ request: ExactPowerPointSlideIdentityReadRequest
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    let binding = request.runtimeBinding
    guard request.requestStartedMachAbsoluteTime > 0,
      request.requestStartedMachAbsoluteTime
        > binding.freshnessBoundaryMachAbsoluteTime,
      binding.captureOperationID.rawValue > 0,
      binding.captureGeneration > 0,
      binding.windowIdentity.ownerProcessID == processIdentifier,
      binding.windowIdentity.bundleIdentifier == bundleIdentifier
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    return try retainedObject(
      bindingSessionToken: binding.bindingSessionToken,
      objectToken: binding.slideShowObjectToken,
      requestProcessIdentifier: Int(binding.windowIdentity.ownerProcessID),
      requestBundleIdentifier: binding.windowIdentity.bundleIdentifier
    )
  }

  private func retainedObject(
    bindingSessionToken candidateSessionToken: String,
    objectToken candidateObjectToken: String,
    requestProcessIdentifier: Int,
    requestBundleIdentifier: String
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    guard isExactOpaqueToken(candidateSessionToken),
      isExactOpaqueToken(candidateObjectToken),
      requestProcessIdentifier > 0,
      requestBundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.malformedRequest
    }
    guard candidateSessionToken == bindingSessionToken else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    }
    guard requestProcessIdentifier == Int(processIdentifier),
      requestBundleIdentifier == bundleIdentifier
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetIdentityMismatch
    }
    guard let retainedSlideShowObject else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.exactObjectUnavailable
    }
    guard retainedSlideShowObject.token == candidateObjectToken else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.objectTokenMismatch
    }
    return retainedSlideShowObject.object
  }

  private func retainedObject(
    for receipt: ManagedSlideShowStartReceipt
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    try retainedObject(
      bindingSessionToken: receipt.bindingSessionToken,
      objectToken: receipt.slideShowObjectToken,
      requestProcessIdentifier: Int(receipt.processIdentifier),
      requestBundleIdentifier: receipt.bundleIdentifier
    )
  }

  private func isExactOpaqueToken(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed == value
  }

  private func acceptObjectOperationRequestToken(_ token: String) throws {
    guard issuedObjectOperationRequestTokens.insert(token).inserted else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.requestAlreadyConsumed
    }
  }

  private func requireAuthorizedTarget(
    operationToken: UUID,
    requireFrozenWindow: Bool = true
  ) async throws {
    try await requireExactTargetIdentity(operationToken: operationToken)
    _ = try await readValidatedWindowInventory(
      operationToken: operationToken,
      requireFrozenWindow: requireFrozenWindow
    )
    let state = await permissionChecker.passivePreflight(
      target: PowerPointAutomationPermissionTarget(
        processIdentifier: Int32(processIdentifier),
        bundleIdentifier: bundleIdentifier,
        bindingSessionToken: bindingSessionToken
      )
    )
    try checkOperation(operationToken)
    switch state {
    case .authorized:
      break
    case .requiresUserConsent:
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .permissionRequiresExplicitUserAction
    case .denied:
      throw PowerPointManagedSlideShowAppleEventClientFailure.permissionDenied
    case .targetNotRunning:
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetNotRunning
    case .cancelled:
      throw PowerPointManagedSlideShowAppleEventClientFailure.cancelled
    case .staleSession:
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    case .priorCheckStillDraining, .staleCompletion, .unavailable, .malformedTarget:
      throw PowerPointManagedSlideShowAppleEventClientFailure.permissionUnavailable
    }
  }

  /// Authorizes operations on the retained returned object without reselecting any window.
  private func requireAuthorizedObjectTarget(operationToken: UUID) async throws {
    try await requireExactTargetIdentity(operationToken: operationToken)
    let state = await permissionChecker.passivePreflight(
      target: PowerPointAutomationPermissionTarget(
        processIdentifier: Int32(processIdentifier),
        bundleIdentifier: bundleIdentifier,
        bindingSessionToken: bindingSessionToken
      )
    )
    try checkOperation(operationToken)
    try throwForPermissionState(state)
  }

  /// Returns `false` only when the original PowerPoint process no longer exists, in which case the
  /// retained runtime descriptor cannot address a live slide show and may be released locally.
  private func requireRecoveryTarget(operationToken: UUID) async throws -> Bool {
    let identity = await identityReader.currentIdentity(for: processIdentifier)
    try checkRecoveryOperation(operationToken)
    guard let identity else { return false }
    guard identity.processIdentifier == processIdentifier,
      identity.bundleIdentifier == bundleIdentifier,
      identity.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetIdentityMismatch
    }
    let state = await permissionChecker.passivePreflight(
      target: PowerPointAutomationPermissionTarget(
        processIdentifier: Int32(processIdentifier),
        bundleIdentifier: bundleIdentifier,
        bindingSessionToken: bindingSessionToken
      )
    )
    try checkRecoveryOperation(operationToken)
    if state == .targetNotRunning { return false }
    try throwForPermissionState(state)
    return true
  }

  private func throwForPermissionState(
    _ state: PowerPointAutomationPermissionState
  ) throws {
    switch state {
    case .authorized:
      break
    case .requiresUserConsent:
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .permissionRequiresExplicitUserAction
    case .denied:
      throw PowerPointManagedSlideShowAppleEventClientFailure.permissionDenied
    case .targetNotRunning:
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetNotRunning
    case .cancelled:
      throw PowerPointManagedSlideShowAppleEventClientFailure.cancelled
    case .staleSession:
      throw PowerPointManagedSlideShowAppleEventClientFailure.staleSession
    case .priorCheckStillDraining, .staleCompletion, .unavailable, .malformedTarget:
      throw PowerPointManagedSlideShowAppleEventClientFailure.permissionUnavailable
    }
  }

  private func requireExactTargetIdentity(operationToken: UUID) async throws {
    let identity = await identityReader.currentIdentity(for: processIdentifier)
    try checkOperation(operationToken)
    guard let identity else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetNotRunning
    }
    guard identity.processIdentifier == processIdentifier,
      identity.bundleIdentifier == bundleIdentifier,
      identity.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.targetIdentityMismatch
    }
  }

  private func verifyStartPreconditions(
    _ request: ManagedSlideShowStartRequest,
    operationToken: UUID
  ) async throws {
    try await requireExactTargetIdentity(operationToken: operationToken)
    _ = try await readValidatedWindowInventory(
      operationToken: operationToken,
      requireFrozenWindow: true
    )
    let activePresentationCount = try readCount(
      .presentation,
      operationToken: operationToken
    )
    let slideShowWindowCount = try readCount(
      .slideShowWindow,
      operationToken: operationToken
    )
    guard activePresentationCount == Int32(request.requiredActivePresentationCount),
      slideShowWindowCount
        == Int32(request.requiredPreexistingSlideShowWindowCount)
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .startPreconditionMismatch
    }
    // PID reuse or bundle replacement after either count invalidates the attempt before the
    // command. The second caller-side pass therefore ends with the last external pre-send check.
    try await requireExactTargetIdentity(operationToken: operationToken)
    _ = try await readValidatedWindowInventory(
      operationToken: operationToken,
      requireFrozenWindow: true
    )
  }

  private func readVisibilityCapability(
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> PowerPointManagedSlideShowRoleCapabilityState {
    let reply = try await getExactObjectProperty(
      [.visible],
      object: object,
      operationToken: operationToken
    )
    switch codec.parseBooleanReply(reply) {
    case .value:
      return .available
    case .failure(.appleEventError(.unsupportedOperation)):
      return .unavailable
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    }
  }

  /// Read-only preflight for the active presentation.  This runs before the one potentially
  /// delivering `run slide show` command, so unsupported fullscreen, kiosk, or presenter modes
  /// cannot create a show which the exact editing-window capture boundary may no longer bind.
  private func readRequiredWindowedSlideShowType(
    activePresentation: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) throws {
    guard
      let showType = codec.preStartPresentationPropertySpecifier(
        [.slideShowSettings, .slideShowType], of: activePresentation
      ),
      let event = codec.getEvent(processIdentifier: Int32(processIdentifier), object: showType)
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.descriptorConstructionFailed
    }
    let reply = try send(event, operationToken: operationToken)
    switch codec.parseSlideShowTypeReply(reply) {
    case .value(.window):
      return
    case .value:
      throw PowerPointManagedSlideShowAppleEventClientFailure.unsupportedSlideShowType
    case .failure:
      throw PowerPointManagedSlideShowAppleEventClientFailure.slideShowTypeUnavailable
    }
  }

  private func readViewStateCapability(
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> PowerPointManagedSlideShowRoleCapabilityState {
    let reply = try await getExactObjectProperty(
      [.slideShowView, .slideState],
      object: object,
      operationToken: operationToken
    )
    switch codec.parseSlideShowStateReply(reply) {
    case .value:
      return .available
    case .failure(.appleEventError(.unsupportedOperation)),
      .failure(.unsupportedSlideShowState):
      return .unavailable
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    }
  }

  private func readStableSemanticState(
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> ManagedSlideShowRoleSemanticState {
    let first = try await readSemanticState(
      object: object,
      operationToken: operationToken
    )
    let second = try await readSemanticState(
      object: object,
      operationToken: operationToken
    )
    guard first == second else {
      throw PowerPointManagedSlideShowAppleEventClientFailure.semanticStateUnstable
    }
    return second
  }

  private func readSemanticState(
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> ManagedSlideShowRoleSemanticState {
    let viewState = try await readExactViewState(
      object: object,
      operationToken: operationToken
    )
    let slideID = try await readExactPositiveInteger(
      [.slideShowView, .slide, .slideID],
      object: object,
      operationToken: operationToken
    )
    let slideIndex = try await readExactPositiveInteger(
      [.slideShowView, .slide, .slideIndex],
      object: object,
      operationToken: operationToken
    )
    let presentationSaved = try await readExactBoolean(
      [.presentation, .presentationSaved],
      object: object,
      operationToken: operationToken
    )
    return ManagedSlideShowRoleSemanticState(
      slideID: slideID,
      slideIndex: slideIndex,
      currentViewState: viewState,
      presentationSaved: presentationSaved
    )
  }

  private func readExactViewState(
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> ManagedSlideShowRoleCurrentViewState {
    let reply = try await getExactObjectProperty(
      [.slideShowView, .slideState],
      object: object,
      operationToken: operationToken
    )
    switch codec.parseSlideShowStateReply(reply) {
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    case .value(let state):
      switch state {
      case .running:
        return .running
      case .black:
        return .blackScreen
      case .white:
        return .whiteScreen
      }
    }
  }

  private func readExactPositiveInteger(
    _ properties: [PowerPointAppleEventProperty],
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> Int {
    let reply = try await getExactObjectProperty(
      properties,
      object: object,
      operationToken: operationToken
    )
    switch codec.parseInt32Reply(reply) {
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    case .value(let value):
      guard value > 0 else {
        throw PowerPointManagedSlideShowAppleEventClientFailure
          .semanticValueOutOfBounds
      }
      return Int(value)
    }
  }

  private func readExactBoolean(
    _ properties: [PowerPointAppleEventProperty],
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> Bool {
    let reply = try await getExactObjectProperty(
      properties,
      object: object,
      operationToken: operationToken
    )
    switch codec.parseBooleanReply(reply) {
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    case .value(let value):
      return value
    }
  }

  private func setExactVisibility(
    _ visible: Bool,
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws {
    guard
      let property = codec.nestedPropertySpecifier([.visible], of: object),
      let event = codec.setBooleanEvent(
        processIdentifier: Int32(processIdentifier),
        object: property,
        value: visible
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    let reply = try await sendExactObjectEvent(
      event,
      operationToken: operationToken
    )
    try requireSuccessfulCommandReply(reply)
  }

  private func setExactViewState(
    _ state: ManagedSlideShowRoleCurrentViewState,
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws {
    let powerPointState: PowerPointSlideShowState =
      switch state {
      case .running: .running
      case .blackScreen: .black
      case .whiteScreen: .white
      }
    guard
      let property = codec.nestedPropertySpecifier(
        [.slideShowView, .slideState],
        of: object
      ),
      let event = codec.setSlideShowStateEvent(
        processIdentifier: Int32(processIdentifier),
        object: property,
        value: powerPointState
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    let reply = try await sendExactObjectEvent(
      event,
      operationToken: operationToken
    )
    try requireSuccessfulCommandReply(reply)
  }

  private func getExactObjectProperty(
    _ properties: [PowerPointAppleEventProperty],
    object: PowerPointAppleEventRuntimeObjectSpecifier,
    operationToken: UUID
  ) async throws -> NSAppleEventDescriptor? {
    guard
      let property = codec.nestedPropertySpecifier(properties, of: object),
      let event = codec.getEvent(
        processIdentifier: Int32(processIdentifier),
        object: property
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    return try await sendExactObjectEvent(
      event,
      operationToken: operationToken
    )
  }

  private func sendExactObjectEvent(
    _ event: NSAppleEventDescriptor,
    operationToken: UUID
  ) async throws -> NSAppleEventDescriptor? {
    // Revalidate the exact process immediately before every Apple Event. No window enumeration or
    // identity reconstruction is used here; the direct object remains rooted in the retained reply.
    try await requireExactTargetIdentity(operationToken: operationToken)
    return try send(event, operationToken: operationToken)
  }

  private func requireSuccessfulCommandReply(
    _ reply: NSAppleEventDescriptor?
  ) throws {
    switch codec.parseCommandReply(reply) {
    case .value:
      break
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    }
  }

  private func acceptObjectMachAbsoluteTime(
    minimum: UInt64,
    strictlyAfterMinimum: Bool = false,
    operationToken: UUID
  ) async throws -> UInt64 {
    let time = await machClock.now()
    try checkOperation(operationToken)
    let passesMinimum = strictlyAfterMinimum ? time > minimum : time >= minimum
    guard time > 0, passesMinimum, time > lastObjectMachAbsoluteTime else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .invalidMachAbsoluteTime
    }
    lastObjectMachAbsoluteTime = time
    return time
  }

  private func readCount(
    _ objectClass: PowerPointAppleEventObjectClass,
    operationToken: UUID
  ) throws -> Int32 {
    guard
      let event = codec.countEvent(
        processIdentifier: Int32(processIdentifier),
        objectClass: objectClass,
        in: NSAppleEventDescriptor.null()
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    let reply = try send(event, operationToken: operationToken)
    switch codec.parseInt32Reply(reply) {
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    case .value(let count):
      guard (0...Self.maximumScriptingCount).contains(count) else {
        throw PowerPointManagedSlideShowAppleEventClientFailure.countOutOfBounds
      }
      return count
    }
  }

  private func readActivePresentation(
    operationToken: UUID
  ) throws -> PowerPointAppleEventRuntimeObjectSpecifier {
    guard
      let property = codec.rootPropertySpecifier(.activePresentation),
      let event = codec.getEvent(
        processIdentifier: Int32(processIdentifier),
        object: property
      )
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .descriptorConstructionFailed
    }
    let reply = try send(event, operationToken: operationToken)
    switch codec.parseObjectSpecifierReply(reply, expectedClass: .presentation) {
    case .failure(let failure):
      throw classifyReplyFailure(failure)
    case .value(let object):
      return object
    }
  }

  private func send(
    _ event: NSAppleEventDescriptor,
    operationToken: UUID
  ) throws -> NSAppleEventDescriptor? {
    try checkOperation(operationToken)
    do {
      let reply = try eventSender.send(
        event,
        options: PowerPointAppleEventDescriptorCodec.sendOptions,
        timeout: eventTimeout
      )
      try checkOperation(operationToken)
      return reply
    } catch let failure as PowerPointManagedSlideShowAppleEventClientFailure {
      throw failure
    } catch {
      try checkOperation(operationToken)
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .appleEventTransportFailed
    }
  }

  private func reserveOpaqueObjectToken(
    operationToken: UUID
  ) throws -> String {
    try checkOperation(operationToken)
    let rawOpaqueToken = opaqueObjectTokenFactory()
    guard retainedSlideShowObject == nil,
      !issuedObjectTokens.contains(rawOpaqueToken)
    else {
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .opaqueObjectTokenUnavailable
    }
    switch opaqueObjectTokenRegistry.reserveStart(
      bindingSessionToken: bindingSessionToken,
      objectToken: rawOpaqueToken
    ) {
    case .reserved:
      break
    case .sessionAlreadyConsumed:
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .startAttemptAlreadyConsumed
    case .objectTokenUnavailable:
      throw PowerPointManagedSlideShowAppleEventClientFailure
        .opaqueObjectTokenUnavailable
    }
    issuedObjectTokens.insert(rawOpaqueToken)
    return rawOpaqueToken
  }

  private func releaseObjectTokenReservation(_ objectToken: String) {
    opaqueObjectTokenRegistry.releaseObjectToken(
      bindingSessionToken: bindingSessionToken,
      objectToken: objectToken
    )
    issuedObjectTokens.remove(objectToken)
  }

  private func readValidatedWindowInventory(
    operationToken: UUID,
    requireFrozenWindow: Bool
  ) async throws -> [ManagedSlideShowWindowIdentity] {
    let windows: [ManagedSlideShowWindowIdentity]
    do {
      windows = try await windowInventoryReader.readExactWindowInventory(
        processIdentifier: processIdentifier,
        bundleIdentifier: bundleIdentifier
      )
    } catch {
      try checkOperation(operationToken)
      throw PowerPointManagedSlideShowAppleEventClientFailure.windowInventoryReadFailed
    }
    try checkOperation(operationToken)
    try validateWindowInventory(windows)
    if requireFrozenWindow {
      let frozen = ManagedSlideShowWindowIdentity(
        windowID: Int(sessionContext.frozenWindowIdentity.windowID),
        processIdentifier: Int(processIdentifier),
        bundleIdentifier: bundleIdentifier
      )
      guard windows.contains(frozen) else {
        throw PowerPointManagedSlideShowAppleEventClientFailure.frozenWindowUnavailable
      }
    }
    return windows
  }

  private func validateWindowInventory(
    _ windows: [ManagedSlideShowWindowIdentity]
  ) throws {
    var identifiers: Set<Int> = []
    for window in windows {
      guard window.windowID > 0,
        window.processIdentifier == Int(processIdentifier),
        window.bundleIdentifier == bundleIdentifier,
        identifiers.insert(window.windowID).inserted
      else {
        throw PowerPointManagedSlideShowAppleEventClientFailure
          .malformedWindowInventory
      }
    }
  }

  private func classifyReplyFailure(
    _ failure: PowerPointAppleEventReplyFailure
  ) -> PowerPointManagedSlideShowAppleEventClientFailure {
    switch failure {
    case .appleEventError(.wouldRequireUserConsent):
      return .permissionRequiresExplicitUserAction
    case .appleEventError(.notPermitted):
      return .permissionDenied
    case .appleEventError(.targetNotRunning):
      return .targetNotRunning
    case .appleEventError(.timedOut), .appleEventError(.unsupportedOperation),
      .appleEventError(.other):
      return .appleEventTransportFailed
    case .missingReply, .malformedReply, .missingDirectParameter,
      .unexpectedDirectParameterType, .unsupportedSlideShowState, .unsupportedSlideShowType,
      .malformedObjectSpecifier:
      return .malformedReply
    }
  }

  private func classifyPossiblyDeliveredStartReplyFailure(
    _ failure: PowerPointAppleEventReplyFailure
  ) -> PowerPointManagedSlideShowAppleEventClientFailure {
    switch failure {
    case .missingReply:
      return .startCommandReplyMissingPossiblyDelivered
    case .appleEventError(.timedOut), .appleEventError(.unsupportedOperation),
      .appleEventError(.other):
      return .startCommandDeliveryUnknown
    case .malformedReply, .missingDirectParameter,
      .unexpectedDirectParameterType, .unsupportedSlideShowState, .unsupportedSlideShowType,
      .malformedObjectSpecifier:
      return .startCommandReplyMalformedPossiblyDelivered
    case .appleEventError(.wouldRequireUserConsent):
      return .permissionRequiresExplicitUserAction
    case .appleEventError(.notPermitted):
      return .permissionDenied
    case .appleEventError(.targetNotRunning):
      return .targetNotRunning
    }
  }

  private func classifyRecoveryReplyFailure(
    _ failure: PowerPointAppleEventReplyFailure
  ) -> PowerPointManagedSlideShowAppleEventClientFailure {
    switch failure {
    case .appleEventError(.wouldRequireUserConsent):
      return .permissionRequiresExplicitUserAction
    case .appleEventError(.notPermitted):
      return .permissionDenied
    case .appleEventError(.targetNotRunning):
      return .targetNotRunning
    case .appleEventError(.timedOut), .appleEventError(.other):
      return .recoveryCommandDeliveryUnknown
    case .appleEventError(.unsupportedOperation), .missingReply, .malformedReply,
      .missingDirectParameter, .unexpectedDirectParameterType,
      .unsupportedSlideShowState, .unsupportedSlideShowType, .malformedObjectSpecifier:
      return .recoveryCommandReplyMalformedPossiblyDelivered
    }
  }
}
