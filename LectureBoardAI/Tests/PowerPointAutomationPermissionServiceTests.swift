import ApplicationServices
import Foundation
import Testing

@testable import LectureBoard_AI

struct PowerPointAutomationPermissionServiceTests {
  @Test @MainActor func passivePreflightUsesExactPIDWildcardsAndNeverPrompts() async {
    let client = RecordingAutomationPermissionClient(status: noErr)
    let result = await service(client: client).passivePreflight(target: target())

    #expect(result == .authorized)
    let query = await client.queries.first
    #expect(query?.processIdentifier == 700)
    #expect(query?.expectedBundleIdentifier == PowerPointWindowIdentity.expectedBundleIdentifier)
    #expect(query?.eventClass == UInt32(typeWildCard))
    #expect(query?.eventID == UInt32(typeWildCard))
    #expect(query?.askUserIfNeeded == false)
    #expect(query?.wasMainThread == false)
  }

  @Test func onlyExplicitRequestAsksUserIfNeeded() async {
    let client = RecordingAutomationPermissionClient(
      status: OSStatus(errAEEventWouldRequireUserConsent)
    )
    let result = await service(client: client).requestFromExplicitUserAction(target: target())

    #expect(result == .requiresUserConsent)
    #expect(await client.queries.map(\.askUserIfNeeded) == [true])
  }

  @Test(
    arguments: [
      (noErr, PowerPointAutomationPermissionState.authorized),
      (
        OSStatus(errAEEventWouldRequireUserConsent),
        PowerPointAutomationPermissionState.requiresUserConsent
      ),
      (OSStatus(errAEEventNotPermitted), PowerPointAutomationPermissionState.denied),
      (OSStatus(procNotFound), PowerPointAutomationPermissionState.targetNotRunning),
      (OSStatus(-12_345), PowerPointAutomationPermissionState.unavailable),
    ]
  )
  func rawStatusesAreReducedToBoundedStates(
    status: OSStatus,
    expected: PowerPointAutomationPermissionState
  ) async {
    let result = await service(
      client: RecordingAutomationPermissionClient(status: status)
    ).passivePreflight(target: target())
    #expect(result == expected)
  }

  @Test func malformedAndStaleTargetsNeverReachTheClient() async {
    let client = RecordingAutomationPermissionClient(status: noErr)
    let service = service(client: client)

    #expect(
      await service.passivePreflight(target: target(processIdentifier: 0)) == .malformedTarget
    )
    #expect(
      await service.passivePreflight(target: target(bundleIdentifier: "wrong"))
        == .malformedTarget
    )
    #expect(
      await service.passivePreflight(target: target(session: "old")) == .staleSession
    )
    #expect(await client.queries.isEmpty)
  }

  @Test func systemClientRejectsChangedCurrentBundleBeforePermissionQuery() async {
    let mismatchCalls = LockedPermissionCallRecorder()
    let mismatchClient = PowerPointAutomationPermissionSystemClient(
      currentBundleIdentifier: { _ in "com.example.Impostor" },
      permissionQuery: mismatchCalls.call
    )
    let mismatchResult = await mismatchClient.determinePermission(
      processIdentifier: 700,
      expectedBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
      eventClass: UInt32(typeWildCard),
      eventID: UInt32(typeWildCard),
      askUserIfNeeded: false
    )

    #expect(mismatchResult == .targetIdentityMismatch)
    #expect(mismatchCalls.callCount == 0)

    let missingCalls = LockedPermissionCallRecorder()
    let missingClient = PowerPointAutomationPermissionSystemClient(
      currentBundleIdentifier: { _ in nil },
      permissionQuery: missingCalls.call
    )
    let missingResult = await missingClient.determinePermission(
      processIdentifier: 700,
      expectedBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
      eventClass: UInt32(typeWildCard),
      eventID: UInt32(typeWildCard),
      askUserIfNeeded: false
    )

    #expect(missingResult == .targetNotRunning)
    #expect(missingCalls.callCount == 0)
  }

  @Test func preCancelledExplicitRequestNeverReachesTheClient() async {
    let client = RecordingAutomationPermissionClient(status: noErr)
    let service = service(client: client)
    let result = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await service.requestFromExplicitUserAction(target: target())
    }.value

    #expect(result == .cancelled)
    #expect(await client.queries.isEmpty)
  }

  @Test func callerCancellationPreventsReplacementUntilNoncooperativeWorkDrains() async throws {
    let client = ControllableAutomationPermissionClient()
    let service = service(client: client)
    let first = Task { await service.passivePreflight(target: target()) }
    try await waitForAutomationPermission { await client.callCount == 1 }

    #expect(
      await service.requestFromExplicitUserAction(target: target()) == .priorCheckStillDraining
    )
    first.cancel()
    #expect(await service.passivePreflight(target: target()) == .priorCheckStillDraining)

    await client.resume(status: noErr)
    #expect(await first.value == .cancelled)
    #expect(await client.callCount == 1)

    #expect(await service.passivePreflight(target: target()) == .authorized)
    #expect(await client.callCount == 2)
  }

  @Test func acceptedPermissionStatusIsNotOverwrittenByLaterCancellation() async {
    let service = service(
      client: RecordingAutomationPermissionClient(status: OSStatus(errAEEventNotPermitted))
    )
    let result = await service.passivePreflight(target: target())
    await service.cancelCurrentCheck()
    #expect(result == .denied)

    let terminalGate = PowerPointAutomationPermissionTerminalGate()
    terminalGate.accept(.status(OSStatus(errAEEventNotPermitted)))
    #expect(terminalGate.cancel() == false)
    guard case .clientResult(.status(let status)) = terminalGate.terminalResult() else {
      Issue.record("The first terminal permission status was overwritten")
      return
    }
    #expect(status == OSStatus(errAEEventNotPermitted))
  }

  private func service(
    client: any PowerPointAutomationPermissionClient
  ) -> PowerPointAutomationPermissionService {
    PowerPointAutomationPermissionService(bindingSessionToken: "session", client: client)
  }

  private func target(
    processIdentifier: Int32 = 700,
    bundleIdentifier: String = PowerPointWindowIdentity.expectedBundleIdentifier,
    session: String = "session"
  ) -> PowerPointAutomationPermissionTarget {
    PowerPointAutomationPermissionTarget(
      processIdentifier: processIdentifier,
      bundleIdentifier: bundleIdentifier,
      bindingSessionToken: session
    )
  }
}

private struct AutomationPermissionQuery: Equatable, Sendable {
  let processIdentifier: Int32
  let expectedBundleIdentifier: String
  let eventClass: UInt32
  let eventID: UInt32
  let askUserIfNeeded: Bool
  let wasMainThread: Bool
}

private actor RecordingAutomationPermissionClient: PowerPointAutomationPermissionClient {
  let status: OSStatus
  private(set) var queries: [AutomationPermissionQuery] = []

  init(status: OSStatus) {
    self.status = status
  }

  func determinePermission(
    processIdentifier: Int32,
    expectedBundleIdentifier: String,
    eventClass: UInt32,
    eventID: UInt32,
    askUserIfNeeded: Bool
  ) async -> PowerPointAutomationPermissionClientResult {
    queries.append(
      AutomationPermissionQuery(
        processIdentifier: processIdentifier,
        expectedBundleIdentifier: expectedBundleIdentifier,
        eventClass: eventClass,
        eventID: eventID,
        askUserIfNeeded: askUserIfNeeded,
        wasMainThread: currentThreadIsMain()
      )
    )
    return .status(status)
  }
}

private actor ControllableAutomationPermissionClient: PowerPointAutomationPermissionClient {
  private var continuation: CheckedContinuation<PowerPointAutomationPermissionClientResult, Never>?
  private(set) var callCount = 0

  func determinePermission(
    processIdentifier: Int32,
    expectedBundleIdentifier: String,
    eventClass: UInt32,
    eventID: UInt32,
    askUserIfNeeded: Bool
  ) async -> PowerPointAutomationPermissionClientResult {
    callCount += 1
    if callCount > 1 { return .status(noErr) }
    return await withCheckedContinuation { continuation = $0 }
  }

  func resume(status: OSStatus) {
    continuation?.resume(returning: .status(status))
    continuation = nil
  }
}

private func waitForAutomationPermission(
  maxYields: Int = 10_000,
  _ predicate: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<maxYields {
    if await predicate() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for deterministic Automation permission state")
}

private func currentThreadIsMain() -> Bool {
  Thread.isMainThread
}

private final class LockedPermissionCallRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedCallCount = 0

  var callCount: Int {
    lock.withLock { storedCallCount }
  }

  func call(
    processIdentifier: Int32,
    eventClass: UInt32,
    eventID: UInt32,
    askUserIfNeeded: Bool
  ) -> OSStatus {
    lock.withLock { storedCallCount += 1 }
    return noErr
  }
}
