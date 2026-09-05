import AppKit
import ApplicationServices
import Foundation

struct PowerPointAutomationPermissionTarget: Equatable, Sendable {
  let processIdentifier: Int32
  let bundleIdentifier: String
  let bindingSessionToken: String
}

enum PowerPointAutomationPermissionState: Equatable, Sendable {
  case authorized
  case requiresUserConsent
  case denied
  case targetNotRunning
  case unavailable
  case malformedTarget
  case staleSession
  case priorCheckStillDraining
  case cancelled
  case staleCompletion
}

protocol PowerPointAutomationPermissionClient: Sendable {
  func determinePermission(
    processIdentifier: Int32,
    expectedBundleIdentifier: String,
    eventClass: UInt32,
    eventID: UInt32,
    askUserIfNeeded: Bool
  ) async -> PowerPointAutomationPermissionClientResult
}

enum PowerPointAutomationPermissionClientResult: Equatable, Sendable {
  case status(OSStatus)
  case targetNotRunning
  case targetIdentityMismatch
}

/// The only client in this boundary that calls the blocking Apple Event permission API.
///
/// The call always runs in a detached task. Its address descriptor contains only the exact kernel
/// process identifier supplied by the frozen PowerPoint target and is disposed on every path after
/// successful creation.
struct PowerPointAutomationPermissionSystemClient: PowerPointAutomationPermissionClient {
  typealias CurrentBundleIdentifier = @Sendable (Int32) -> String?
  typealias PermissionQuery =
    @Sendable (Int32, UInt32, UInt32, Bool) -> OSStatus

  private let currentBundleIdentifier: CurrentBundleIdentifier
  private let permissionQuery: PermissionQuery

  init(
    currentBundleIdentifier: @escaping CurrentBundleIdentifier = { processIdentifier in
      NSRunningApplication(processIdentifier: pid_t(processIdentifier))?.bundleIdentifier
    },
    permissionQuery: @escaping PermissionQuery = { processIdentifier, eventClass, eventID, ask in
      Self.determinePermissionSynchronously(
        processIdentifier: processIdentifier,
        eventClass: eventClass,
        eventID: eventID,
        askUserIfNeeded: ask
      )
    }
  ) {
    self.currentBundleIdentifier = currentBundleIdentifier
    self.permissionQuery = permissionQuery
  }

  func determinePermission(
    processIdentifier: Int32,
    expectedBundleIdentifier: String,
    eventClass: UInt32,
    eventID: UInt32,
    askUserIfNeeded: Bool
  ) async -> PowerPointAutomationPermissionClientResult {
    await Task.detached(priority: .userInitiated) {
      guard
        let currentBundleIdentifier = self.currentBundleIdentifier(processIdentifier)
      else { return .targetNotRunning }
      guard currentBundleIdentifier == expectedBundleIdentifier,
        expectedBundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier
      else { return .targetIdentityMismatch }
      return .status(
        self.permissionQuery(
          processIdentifier,
          eventClass,
          eventID,
          askUserIfNeeded
        )
      )
    }.value
  }

  private static func determinePermissionSynchronously(
    processIdentifier: Int32,
    eventClass: UInt32,
    eventID: UInt32,
    askUserIfNeeded: Bool
  ) -> OSStatus {
    var processIdentifier = processIdentifier
    var target = AEAddressDesc()
    let descriptorStatus = withUnsafeBytes(of: &processIdentifier) { bytes in
      AECreateDesc(typeKernelProcessID, bytes.baseAddress, bytes.count, &target)
    }
    guard descriptorStatus == noErr else { return OSStatus(descriptorStatus) }
    defer { _ = AEDisposeDesc(&target) }
    return AEDeterminePermissionToAutomateTarget(
      &target,
      AEEventClass(eventClass),
      AEEventID(eventID),
      askUserIfNeeded
    )
  }
}

/// Fail-closed, session-bound Automation permission boundary for one PowerPoint process.
///
/// Passive preflight never prompts. Only `requestFromExplicitUserAction` can pass `true` to the
/// system client. The result contains no PID, bundle identifier, session token, or raw status.
/// This service is not wired into normal launch or window refresh and is not live verification.
/// Once the blocking OS call has begun, cancellation cannot physically retract a displayed system
/// prompt; cancellation still invalidates its callback and public result after the call drains.
actor PowerPointAutomationPermissionService {
  private let client: any PowerPointAutomationPermissionClient
  private let bindingSessionToken: String
  private var activeTask: Task<Void, Never>?
  private var activeTerminalGate: PowerPointAutomationPermissionTerminalGate?
  private var activeAttemptToken: UUID?

  init(
    bindingSessionToken: String,
    client: any PowerPointAutomationPermissionClient =
      PowerPointAutomationPermissionSystemClient()
  ) {
    self.bindingSessionToken = bindingSessionToken
    self.client = client
  }

  func passivePreflight(
    target: PowerPointAutomationPermissionTarget
  ) async -> PowerPointAutomationPermissionState {
    await determinePermission(target: target, askUserIfNeeded: false)
  }

  /// This entry point must be invoked only in direct response to an explicit user action.
  func requestFromExplicitUserAction(
    target: PowerPointAutomationPermissionTarget
  ) async -> PowerPointAutomationPermissionState {
    await determinePermission(target: target, askUserIfNeeded: true)
  }

  func cancelCurrentCheck() {
    guard let activeTask, let activeTerminalGate else { return }
    if activeTerminalGate.cancel() { activeTask.cancel() }
  }

  private func determinePermission(
    target: PowerPointAutomationPermissionTarget,
    askUserIfNeeded: Bool
  ) async -> PowerPointAutomationPermissionState {
    guard activeTask == nil else { return .priorCheckStillDraining }
    guard !Task.isCancelled else { return .cancelled }
    guard Self.isValid(target) else { return .malformedTarget }
    guard target.bindingSessionToken == bindingSessionToken else { return .staleSession }

    let client = self.client
    let processIdentifier = target.processIdentifier
    let expectedBundleIdentifier = target.bundleIdentifier
    let attemptToken = UUID()
    let terminalGate = PowerPointAutomationPermissionTerminalGate()
    activeAttemptToken = attemptToken
    activeTerminalGate = terminalGate
    let task = Task.detached(priority: .userInitiated) {
      let result = await client.determinePermission(
        processIdentifier: processIdentifier,
        expectedBundleIdentifier: expectedBundleIdentifier,
        eventClass: UInt32(typeWildCard),
        eventID: UInt32(typeWildCard),
        askUserIfNeeded: askUserIfNeeded
      )
      terminalGate.accept(result)
    }
    activeTask = task

    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      if terminalGate.cancel() { task.cancel() }
    }
    let isCurrent = activeAttemptToken == attemptToken
    activeTask = nil
    activeTerminalGate = nil
    activeAttemptToken = nil
    guard isCurrent else { return .staleCompletion }
    switch terminalGate.terminalResult() {
    case .cancelled:
      return .cancelled
    case .clientResult(let result):
      return Self.classify(result)
    case .pending:
      return .unavailable
    }
  }

  private static func isValid(_ target: PowerPointAutomationPermissionTarget) -> Bool {
    target.processIdentifier > 0
      && target.bundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier
      && !target.bindingSessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func classify(
    _ result: PowerPointAutomationPermissionClientResult
  ) -> PowerPointAutomationPermissionState {
    switch result {
    case .targetNotRunning:
      return .targetNotRunning
    case .targetIdentityMismatch:
      return .unavailable
    case .status(let status):
      return switch status {
      case noErr:
        .authorized
      case OSStatus(errAEEventWouldRequireUserConsent):
        .requiresUserConsent
      case OSStatus(errAEEventNotPermitted):
        .denied
      case OSStatus(procNotFound):
        .targetNotRunning
      default:
        .unavailable
      }
    }
  }
}

final class PowerPointAutomationPermissionTerminalGate: @unchecked Sendable {
  enum TerminalResult: Sendable {
    case pending
    case clientResult(PowerPointAutomationPermissionClientResult)
    case cancelled
  }

  private let lock = NSLock()
  private var result: TerminalResult = .pending

  func accept(_ result: PowerPointAutomationPermissionClientResult) {
    lock.withLock {
      guard case .pending = self.result else { return }
      self.result = .clientResult(result)
    }
  }

  @discardableResult
  func cancel() -> Bool {
    lock.withLock {
      guard case .pending = result else { return false }
      result = .cancelled
      return true
    }
  }

  func terminalResult() -> TerminalResult {
    lock.withLock { result }
  }
}
