import CoreGraphics
import Foundation
import Testing

@testable import LectureBoard_AI

struct CaptureSessionLifecycleTests {
  @Test func rejectsAStartThatArrivesAfterANewerStop() {
    var lifecycle = CaptureSessionLifecycle()

    let acceptedStop = lifecycle.acceptStop(CaptureOperationID(rawValue: 2))
    let acceptedOldStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 1))
    #expect(acceptedStop)
    #expect(acceptedOldStart == false)
    #expect(lifecycle.activeSessionID == nil)
    #expect(lifecycle.latestOperationID == CaptureOperationID(rawValue: 2))
  }

  @Test func rejectsAnOldStopThatArrivesAfterANewerStart() {
    var lifecycle = CaptureSessionLifecycle()

    let acceptedFirstStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 1))
    let acceptedStop = lifecycle.acceptStop(CaptureOperationID(rawValue: 2))
    let acceptedSecondStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 3))
    let acceptedOldStop = lifecycle.acceptStop(CaptureOperationID(rawValue: 2))
    #expect(acceptedFirstStart)
    #expect(acceptedStop)
    #expect(acceptedSecondStart)
    #expect(acceptedOldStop == false)
    #expect(lifecycle.activeSessionID == CaptureOperationID(rawValue: 3))
  }

  @Test func anOldStartFailureCannotClearTheNewSession() {
    var lifecycle = CaptureSessionLifecycle()

    let acceptedFirstStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 1))
    let acceptedSecondStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 2))
    lifecycle.finishFailedStart(CaptureOperationID(rawValue: 1))

    #expect(acceptedFirstStart)
    #expect(acceptedSecondStart)
    #expect(lifecycle.activeSessionID == CaptureOperationID(rawValue: 2))
  }
}

@MainActor
struct AppModelCaptureLifecycleTests {
  @Test func supersededStartCannotStopOrOverwriteTheNewCapture() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let firstStartTask = Task { await model.startWindowCapture() }
    let firstStart = try await capture.startInvocation(at: 0)

    await model.stopWindowCapture()
    #expect(model.captureStatus == .stopped)

    let secondStartTask = Task { await model.startWindowCapture() }
    let secondStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(secondStart.operationID)
    await secondStartTask.value
    #expect(model.captureStatus == .capturing)

    await capture.resumeStart(firstStart.operationID)
    await firstStartTask.value

    #expect(model.captureStatus == .capturing)
    let stopInvocationCount = await capture.stopInvocationCount
    #expect(stopInvocationCount == 1)
    #expect(firstStart.operationID < secondStart.operationID)

    await model.stopWindowCapture()
  }

  @Test func completedStartStopsWhenItsSelectedWindowChanged() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    model.selectedPowerPointWindowID = 43
    await capture.resumeStart(start.operationID)
    await startTask.value

    #expect(model.captureStatus == .stopped)
    let stopOperationID = try await capture.stopInvocation(at: 0)
    #expect(start.operationID < stopOperationID)
  }

  @Test func startRejectsAnIDMissingFromTheLatestWindowList() async {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)
    model.powerPointWindows = []

    await model.startWindowCapture()

    guard case .error = model.captureStatus else {
      Issue.record("Expected a missing selected window to produce a capture error.")
      return
    }
    let startInvocationCount = await capture.startInvocationCount
    #expect(startInvocationCount == 0)
  }

  @Test func anOldStopCompletionCannotOverwriteTheNewCapture() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let model = makeModel(capture: capture)

    let firstStartTask = Task { await model.startWindowCapture() }
    let firstStart = try await capture.startInvocation(at: 0)
    await capture.resumeStart(firstStart.operationID)
    await firstStartTask.value
    #expect(model.captureStatus == .capturing)
    let delayedSelectionStopSessionID = model.activeCaptureSessionID(for: 42)

    let firstStopTask = Task { await model.stopWindowCapture() }
    let firstStop = try await capture.stopInvocation(at: 0)
    #expect(model.captureStatus == .stopped)

    let secondStartTask = Task { await model.startWindowCapture() }
    let secondStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(secondStart.operationID)
    await secondStartTask.value
    #expect(model.captureStatus == .capturing)

    if let delayedSelectionStopSessionID {
      await model.stopWindowCapture(ifCurrentSessionID: delayedSelectionStopSessionID)
    }
    let stopInvocationCount = await capture.stopInvocationCount
    #expect(stopInvocationCount == 1)
    #expect(model.captureStatus == .capturing)

    await capture.resumeStop(firstStop)
    await firstStopTask.value
    #expect(model.captureStatus == .capturing)
    #expect(firstStart.operationID < firstStop)
    #expect(firstStop < secondStart.operationID)

    let cleanupTask = Task { await model.stopWindowCapture() }
    let cleanupStop = try await capture.stopInvocation(at: 1)
    await capture.resumeStop(cleanupStop)
    await cleanupTask.value
  }

  @Test func olderRefreshCannotOverwriteANewerWindowListAndSelection() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let scanner = ControllableWindowScanner()
    let model = makeModel(capture: capture, scanner: scanner)

    let firstRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(1)
    await scanner.resumeScan(at: 0, with: [makeWindow(id: 43)])
    let firstRefreshStop = try await capture.stopInvocation(at: 0)

    let secondRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(2)
    await scanner.resumeScan(
      at: 1,
      with: [makeWindow(id: 42), makeWindow(id: 44)]
    )
    await secondRefreshTask.value

    await capture.resumeStop(firstRefreshStop)
    await firstRefreshTask.value

    #expect(model.powerPointWindows.map(\.id) == [42, 44])
    #expect(model.selectedPowerPointWindowID == 42)
    #expect(model.status == .ready)
  }

  @Test func olderRefreshErrorCannotOverwriteANewerSuccess() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let scanner = ControllableWindowScanner()
    let model = makeModel(capture: capture, scanner: scanner)

    let firstRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(1)
    let secondRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(2)

    await scanner.resumeScan(at: 1, with: [makeWindow(id: 42)])
    await secondRefreshTask.value
    await scanner.failScan(at: 0)
    await firstRefreshTask.value

    #expect(model.powerPointWindows.map(\.id) == [42])
    #expect(model.selectedPowerPointWindowID == 42)
    #expect(model.status == .ready)
  }

  @Test func captureErrorIsVisibleBeforeAsynchronousStopCompletes() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value
    #expect(model.captureStatus == .capturing)

    await capture.emitError("controlled capture failure", for: start.operationID)
    let errorStop = try await capture.stopInvocation(at: 0)

    #expect(model.captureStatus == .error("controlled capture failure"))

    let recoveryTask = Task { await model.startWindowCapture() }
    let recoveryStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(recoveryStart.operationID)
    await recoveryTask.value
    #expect(model.captureStatus == .capturing)

    await capture.resumeStop(errorStop)
    #expect(model.captureStatus == .capturing)

    let cleanupTask = Task { await model.stopWindowCapture() }
    let cleanupStop = try await capture.stopInvocation(at: 1)
    await capture.resumeStop(cleanupStop)
    await cleanupTask.value
  }

  @Test func refreshCannotChangeSelectionAfterANewerCaptureStarts() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let replacementWindows = [makeWindow(id: 43), makeWindow(id: 44)]
    let model = makeModel(
      capture: capture,
      scanner: FixedWindowScanner(windows: replacementWindows)
    )

    let firstStartTask = Task { await model.startWindowCapture() }
    let firstStart = try await capture.startInvocation(at: 0)
    await capture.resumeStart(firstStart.operationID)
    await firstStartTask.value

    let refreshTask = Task { await model.refreshPowerPointWindows() }
    let refreshStop = try await capture.stopInvocation(at: 0)
    #expect(model.captureStatus == .stopped)

    model.selectedPowerPointWindowID = 44
    let secondStartTask = Task { await model.startWindowCapture() }
    let secondStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(secondStart.operationID)
    await secondStartTask.value
    #expect(model.captureStatus == .capturing)

    await capture.resumeStop(refreshStop)
    await refreshTask.value

    #expect(model.captureStatus == .capturing)
    #expect(model.selectedPowerPointWindowID == 44)

    let cleanupTask = Task { await model.stopWindowCapture() }
    let cleanupStop = try await capture.stopInvocation(at: 1)
    await capture.resumeStop(cleanupStop)
    await cleanupTask.value
  }

  private func makeModel(
    capture: ControllableWindowCapture,
    scanner: any PowerPointWindowScanning = FixedWindowScanner(windows: [])
  ) -> AppModel {
    let permissionService = PermissionService(
      screenCaptureClient: AuthorizedScreenCapturePermissionClient()
    )
    let model = AppModel(
      permissionService: permissionService,
      windowCapture: capture,
      scanner: scanner
    )
    model.selectedPowerPointWindowID = 42
    model.powerPointWindows = [makeWindow(id: 42)]
    return model
  }

  private func makeWindow(id: CGWindowID) -> PowerPointWindowDescriptor {
    PowerPointWindowDescriptor(
      id: id,
      title: "Controlled window",
      applicationName: "Microsoft PowerPoint",
      bundleIdentifier: "com.microsoft.Powerpoint",
      frame: .zero
    )
  }
}

private struct CaptureInvocation: Sendable {
  let operationID: CaptureOperationID
  let windowID: CGWindowID
}

private enum CaptureLifecycleTestError: Error {
  case timedOutWaitingForStart(Int)
  case timedOutWaitingForStop(Int)
  case timedOutWaitingForScan(Int)
  case controlledScanFailure
}

private actor ControllableWindowCapture: PowerPointWindowCapturing {
  private let suspendsStops: Bool
  private var startInvocations: [CaptureInvocation] = []
  private var stopInvocations: [CaptureOperationID] = []
  private var pendingStarts: [CaptureOperationID: CheckedContinuation<Void, any Error>] = [:]
  private var pendingStops: [CaptureOperationID: CheckedContinuation<Void, Never>] = [:]
  private var errorHandlers: [CaptureOperationID: CaptureErrorHandler] = [:]

  init(suspendsStops: Bool) {
    self.suspendsStops = suspendsStops
  }

  var stopInvocationCount: Int {
    stopInvocations.count
  }

  var startInvocationCount: Int {
    startInvocations.count
  }

  func start(
    operationID: CaptureOperationID,
    windowID: CGWindowID,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    errorHandlers[operationID] = onError
    startInvocations.append(
      CaptureInvocation(operationID: operationID, windowID: windowID)
    )
    try await withCheckedThrowingContinuation { continuation in
      pendingStarts[operationID] = continuation
    }
  }

  func stop(operationID: CaptureOperationID) async {
    stopInvocations.append(operationID)
    guard suspendsStops else { return }
    await withCheckedContinuation { continuation in
      pendingStops[operationID] = continuation
    }
  }

  func startInvocation(at index: Int) async throws -> CaptureInvocation {
    for _ in 0..<10_000 {
      if startInvocations.indices.contains(index) {
        return startInvocations[index]
      }
      await Task.yield()
    }
    throw CaptureLifecycleTestError.timedOutWaitingForStart(index)
  }

  func stopInvocation(at index: Int) async throws -> CaptureOperationID {
    for _ in 0..<10_000 {
      if stopInvocations.indices.contains(index) {
        return stopInvocations[index]
      }
      await Task.yield()
    }
    throw CaptureLifecycleTestError.timedOutWaitingForStop(index)
  }

  func resumeStart(_ operationID: CaptureOperationID) {
    pendingStarts.removeValue(forKey: operationID)?.resume(returning: ())
  }

  func resumeStop(_ operationID: CaptureOperationID) {
    pendingStops.removeValue(forKey: operationID)?.resume()
  }

  func emitError(_ message: String, for operationID: CaptureOperationID) {
    errorHandlers[operationID]?(message)
  }
}

private struct FixedWindowScanner: PowerPointWindowScanning {
  let windows: [PowerPointWindowDescriptor]

  func scan() async throws -> [PowerPointWindowDescriptor] {
    windows
  }
}

private actor ControllableWindowScanner: PowerPointWindowScanning {
  private var pendingScans: [CheckedContinuation<[PowerPointWindowDescriptor], any Error>] = []

  func scan() async throws -> [PowerPointWindowDescriptor] {
    try await withCheckedThrowingContinuation { continuation in
      pendingScans.append(continuation)
    }
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if pendingScans.count >= expectedCount { return }
      await Task.yield()
    }
    throw CaptureLifecycleTestError.timedOutWaitingForScan(expectedCount)
  }

  func resumeScan(
    at index: Int,
    with windows: [PowerPointWindowDescriptor]
  ) {
    pendingScans[index].resume(returning: windows)
  }

  func failScan(at index: Int) {
    pendingScans[index].resume(throwing: CaptureLifecycleTestError.controlledScanFailure)
  }
}

@MainActor
private struct AuthorizedScreenCapturePermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }

  func requestAccess() -> Bool { true }
}
