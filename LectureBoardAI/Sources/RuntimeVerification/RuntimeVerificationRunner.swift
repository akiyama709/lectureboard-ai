import AppKit
import Foundation
import LectureBoardCore

struct RuntimeVerificationTiming: Equatable, Sendable {
  static let production = RuntimeVerificationTiming(
    sampleIntervalSeconds: 0.25,
    windowDiscoveryTimeoutSeconds: 15,
    canvasConfirmationTimeoutSeconds: 15
  )

  let sampleIntervalSeconds: TimeInterval
  let windowDiscoveryTimeoutSeconds: TimeInterval
  let canvasConfirmationTimeoutSeconds: TimeInterval

  init(
    sampleIntervalSeconds: TimeInterval,
    windowDiscoveryTimeoutSeconds: TimeInterval,
    canvasConfirmationTimeoutSeconds: TimeInterval
  ) {
    self.sampleIntervalSeconds = Self.normalized(sampleIntervalSeconds)
    self.windowDiscoveryTimeoutSeconds = Self.normalized(windowDiscoveryTimeoutSeconds)
    self.canvasConfirmationTimeoutSeconds = Self.normalized(
      canvasConfirmationTimeoutSeconds
    )
  }

  private static func normalized(_ value: TimeInterval) -> TimeInterval {
    value.isFinite ? max(value, 0.001) : 0.001
  }
}

@MainActor
final class RuntimeVerificationRunner: ObservableObject {
  enum State: Equatable {
    case idle
    case preparing
    case observing
    case finished(String)
    case failed(String)
  }

  private struct Failure: Error {
    let code: RuntimeVerificationFailureCode
    let message: String
    let slideCanvasFailureReason: RuntimeSlideCanvasInvalidationReason?
    let captureFailureSource: RuntimeCaptureFailureSource?
    let captureSCStreamErrorCode: RuntimeSCStreamErrorCode?

    init(
      code: RuntimeVerificationFailureCode,
      message: String,
      slideCanvasFailureReason: RuntimeSlideCanvasInvalidationReason? = nil,
      captureFailureSource: RuntimeCaptureFailureSource? = nil,
      captureSCStreamErrorCode: RuntimeSCStreamErrorCode? = nil
    ) {
      self.code = code
      self.message = message
      self.slideCanvasFailureReason = slideCanvasFailureReason
      self.captureFailureSource = captureFailureSource
      self.captureSCStreamErrorCode = captureSCStreamErrorCode
    }
  }

  private struct RunContext {
    var permissionWasRequested = false
    var permissionRequestReturned: Bool?
    var preflightBefore = ScreenRecordingPermissionState.unknown
    var preflightAfter = ScreenRecordingPermissionState.unknown
    var matchedWindowCount = 0
    var selectedWindowID: UInt32?
    var selectedBundleIdentifier: String?
    var snapshots: [RuntimeVerificationSnapshot] = []
  }

  @Published private(set) var state = State.idle

  private var hasStarted = false
  private let timing: RuntimeVerificationTiming
  private let reportWriter: RuntimeVerificationReportWriter
  private let terminateApplication: @MainActor @Sendable () -> Void

  init(
    timing: RuntimeVerificationTiming = .production,
    reportWriter: RuntimeVerificationReportWriter = RuntimeVerificationReportWriter(),
    terminateApplication: @escaping @MainActor @Sendable () -> Void = {
      NSApplication.shared.terminate(nil)
    }
  ) {
    self.timing = timing
    self.reportWriter = reportWriter
    self.terminateApplication = terminateApplication
  }

  func run(
    configuration: RuntimeVerificationConfiguration,
    model: AppModel
  ) async {
    guard !hasStarted else { return }
    hasStarted = true
    state = .preparing

    let startedAt = Date()
    let startedUptime = ProcessInfo.processInfo.systemUptime
    var context = RunContext()
    var runStatus = RuntimeVerificationRunStatus.completed
    var failureCode: RuntimeVerificationFailureCode?
    var failureMessage: String?
    var slideCanvasFailureReason: RuntimeSlideCanvasInvalidationReason?
    var captureFailureSource: RuntimeCaptureFailureSource?
    var captureSCStreamErrorCode: RuntimeSCStreamErrorCode?

    do {
      try await execute(
        configuration: configuration,
        model: model,
        startedUptime: startedUptime,
        context: &context
      )
    } catch let failure as Failure {
      runStatus = .failed
      failureCode = failure.code
      failureMessage = failure.message
      slideCanvasFailureReason = failure.slideCanvasFailureReason
      captureFailureSource = failure.captureFailureSource
      captureSCStreamErrorCode = failure.captureSCStreamErrorCode
    } catch is CancellationError {
      runStatus = .failed
      failureCode = .internalFailure
      failureMessage = "The runtime verification task was cancelled."
    } catch {
      runStatus = .failed
      failureCode = .internalFailure
      failureMessage = error.localizedDescription
    }

    await model.stopWindowCapture()

    let report = RuntimeVerificationReport(
      startedAt: startedAt,
      finishedAt: Date(),
      requestedDurationSeconds: configuration.observationDurationSeconds,
      permissionWasRequested: context.permissionWasRequested,
      permissionRequestReturned: context.permissionRequestReturned,
      preflightBefore: context.preflightBefore,
      preflightAfter: context.preflightAfter,
      matchedWindowCount: context.matchedWindowCount,
      selectedWindowID: context.selectedWindowID,
      selectedBundleIdentifier: context.selectedBundleIdentifier,
      slideCanvasConfirmationMode: RuntimeVerificationCanvasConfirmationPolicy.reportMode(
        for: configuration.canvasSelection
      ),
      runStatus: runStatus,
      failureCode: failureCode,
      captureFailureSource: captureFailureSource,
      captureSCStreamErrorCode: captureSCStreamErrorCode,
      slideCanvasFailureReason: slideCanvasFailureReason,
      untrustedFailureDetail: failureMessage,
      snapshots: context.snapshots
    )

    do {
      try reportWriter.write(report, toPath: configuration.outputPath)
      if runStatus == .completed {
        state = .finished(configuration.outputPath)
      } else {
        state = .failed(failureMessage ?? "Runtime verification failed.")
      }
    } catch {
      state = .failed(
        "The runtime verification report could not be written: \(error.localizedDescription)"
      )
    }

    terminateApplication()
  }

  private func execute(
    configuration: RuntimeVerificationConfiguration,
    model: AppModel,
    startedUptime: TimeInterval,
    context: inout RunContext
  ) async throws {
    let preflightBefore = model.permissionService.screenCaptureAccessGranted
    context.preflightBefore = RuntimeVerificationPermissionPolicy.state(
      isAuthorized: preflightBefore
    )

    if RuntimeVerificationPermissionPolicy.shouldRequestAccess(
      isAuthorized: preflightBefore,
      requestFlagIsPresent: configuration.requestsScreenRecordingPermission
    ) {
      context.permissionWasRequested = true
      context.permissionRequestReturned = model.requestScreenCapturePermission()
    }

    let preflightAfter = model.permissionService.screenCaptureAccessGranted
    context.preflightAfter = RuntimeVerificationPermissionPolicy.state(
      isAuthorized: preflightAfter,
      requestWasAttempted: context.permissionWasRequested,
      requestReturned: context.permissionRequestReturned
    )
    guard preflightAfter else {
      throw Failure(
        code: .screenRecordingUnavailable,
        message: "Screen Recording access is unavailable."
      )
    }

    let selectedWindow = try await findWindow(
      matching: configuration.targetWindow,
      model: model,
      matchedWindowCount: &context.matchedWindowCount
    )
    context.selectedWindowID = selectedWindow.id
    context.selectedBundleIdentifier = selectedWindow.bundleIdentifier
    model.selectedPowerPointWindowID = selectedWindow.id

    await model.startWindowCapture()
    switch model.captureStatus {
    case .capturing:
      break
    case .error(let message):
      appendSnapshot(
        from: model,
        startedUptime: startedUptime,
        to: &context
      )
      throw captureFailure(for: model, message: message)
    case .starting, .stopped:
      appendSnapshot(
        from: model,
        startedUptime: startedUptime,
        to: &context
      )
      throw captureFailure(
        for: model,
        message: "The selected PowerPoint window did not enter the capturing state."
      )
    }

    try await confirmRequestedCanvas(
      configuration.canvasSelection,
      model: model,
      startedUptime: startedUptime,
      context: &context
    )

    state = .observing
    let observationStartedUptime = ProcessInfo.processInfo.systemUptime
    while true {
      let timestamp = Date()
      let currentUptime = ProcessInfo.processInfo.systemUptime
      context.snapshots.append(
        RuntimeVerificationSnapshotProjector.makeSnapshot(
          from: model,
          timestamp: timestamp,
          elapsedMilliseconds: RuntimeVerificationSnapshotProjector.elapsedMilliseconds(
            from: startedUptime,
            to: currentUptime
          ),
          screenRecordingPermission: context.preflightAfter
        )
      )

      if case .error(let message) = model.captureStatus {
        throw captureFailure(for: model, message: message)
      }

      let elapsed = currentUptime - observationStartedUptime
      let remaining = configuration.observationDurationSeconds - elapsed
      guard remaining > 0 else { break }
      try await Task.sleep(
        nanoseconds: UInt64(
          min(timing.sampleIntervalSeconds, remaining) * 1_000_000_000
        )
      )
    }

    if configuration.canvasSelection == .confirmFullFrame,
      model.slideCanvasStatus != .confirmed
    {
      appendSnapshot(from: model, startedUptime: startedUptime, to: &context)
      throw canvasConfirmationFailure(
        for: model,
        fallbackReason: .confirmationLostDuringObservation
      )
    }
  }

  private func confirmRequestedCanvas(
    _ selection: RuntimeVerificationCanvasSelection,
    model: AppModel,
    startedUptime: TimeInterval,
    context: inout RunContext
  ) async throws {
    guard selection == .confirmFullFrame else { return }

    let deadline = Date().addingTimeInterval(timing.canvasConfirmationTimeoutSeconds)
    while true {
      if case .error(let message) = model.captureStatus {
        appendSnapshot(from: model, startedUptime: startedUptime, to: &context)
        throw captureFailure(for: model, message: message)
      }

      switch RuntimeVerificationCanvasConfirmationPolicy.action(
        for: selection,
        status: model.slideCanvasStatus
      ) {
      case .leaveUnchanged, .complete:
        return
      case .waitForFrame:
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
          appendSnapshot(from: model, startedUptime: startedUptime, to: &context)
          throw canvasConfirmationFailure(
            for: model,
            fallbackReason: .unclassifiedInvalidation
          )
        }
        try await Task.sleep(
          nanoseconds: UInt64(
            min(timing.sampleIntervalSeconds, remaining) * 1_000_000_000
          )
        )
      case .beginSelection:
        model.beginSlideCanvasSelection()
        guard model.slideCanvasStatus == .selecting else {
          appendSnapshot(from: model, startedUptime: startedUptime, to: &context)
          throw canvasConfirmationFailure(
            for: model,
            fallbackReason: .selectionStartRejected
          )
        }
      case .confirmFullFrame:
        guard
          let region = SlideCanvasRegion(
            NormalizedRect(x: 0, y: 0, width: 1, height: 1)
          ),
          model.confirmSlideCanvasSelection(region),
          model.slideCanvasStatus == .confirmed
        else {
          appendSnapshot(from: model, startedUptime: startedUptime, to: &context)
          throw canvasConfirmationFailure(
            for: model,
            fallbackReason: .selectionConfirmationRejected
          )
        }
      case .failClosed:
        appendSnapshot(from: model, startedUptime: startedUptime, to: &context)
        throw canvasConfirmationFailure(
          for: model,
          fallbackReason: .unclassifiedInvalidation
        )
      }
    }
  }

  private func canvasConfirmationFailure(
    for model: AppModel,
    fallbackReason: RuntimeSlideCanvasInvalidationReason
  ) -> Failure {
    let code = RuntimeVerificationCanvasConfirmationPolicy.failureCode(
      for: model.slideCanvasStatus,
      capturedFrameCount: model.capturedFrameCount
    )
    let reason =
      code == .slideCanvasConfirmationFailed
      ? RuntimeVerificationSnapshotProjector.slideCanvasInvalidationReason(
        for: model.slideCanvasInvalidationReason
      ) ?? fallbackReason
      : nil
    return Failure(
      code: code,
      message: code.safeReportMessage,
      slideCanvasFailureReason: reason
    )
  }

  private func captureFailure(for model: AppModel, message: String) -> Failure {
    Failure(
      code: .captureFailed,
      message: message,
      captureFailureSource: model.captureFailureSource ?? .unclassifiedCaptureFailure,
      captureSCStreamErrorCode: model.captureSCStreamErrorCode
    )
  }

  private func findWindow(
    matching target: RuntimeVerificationWindowTarget,
    model: AppModel,
    matchedWindowCount: inout Int
  ) async throws -> PowerPointWindowDescriptor {
    let deadline = Date().addingTimeInterval(timing.windowDiscoveryTimeoutSeconds)
    var lastResolution = RuntimeVerificationWindowSelection.Resolution.notFound

    repeat {
      await model.refreshPowerPointWindows()
      let selection = RuntimeVerificationWindowSelector.select(
        from: model.powerPointWindows,
        target: target
      )
      matchedWindowCount = selection.matchedWindowCount
      lastResolution = selection.resolution

      if case .selected(let identity) = selection.resolution {
        if let window = PowerPointWindowIdentityResolver.uniqueDescriptor(
          identity: identity,
          in: model.powerPointWindows
        ) {
          return window
        }
        let identifierMatchCount = model.powerPointWindows.filter {
          $0.id == identity.windowID
        }.count
        matchedWindowCount = identifierMatchCount
        lastResolution = identifierMatchCount > 1 ? .ambiguous : .notFound
      }

      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else { break }
      try await Task.sleep(
        nanoseconds: UInt64(
          min(timing.sampleIntervalSeconds, remaining) * 1_000_000_000
        )
      )
    } while true

    switch lastResolution {
    case .ambiguous:
      throw Failure(
        code: .ambiguousWindow,
        message: "More than one PowerPoint window matched the requested selection."
      )
    case .notFound, .selected:
      throw Failure(
        code: .windowNotFound,
        message: "No PowerPoint window matched the requested selection."
      )
    }
  }

  private func appendSnapshot(
    from model: AppModel,
    startedUptime: TimeInterval,
    to context: inout RunContext
  ) {
    let timestamp = Date()
    context.snapshots.append(
      RuntimeVerificationSnapshotProjector.makeSnapshot(
        from: model,
        timestamp: timestamp,
        elapsedMilliseconds: RuntimeVerificationSnapshotProjector.elapsedMilliseconds(
          from: startedUptime,
          to: ProcessInfo.processInfo.systemUptime
        ),
        screenRecordingPermission: context.preflightAfter
      )
    )
  }
}
