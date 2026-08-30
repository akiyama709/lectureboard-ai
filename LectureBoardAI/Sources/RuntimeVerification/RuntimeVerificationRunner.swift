import AppKit
import Foundation
import LectureBoardCore

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

  private static let sampleIntervalSeconds: TimeInterval = 0.25
  private static let windowDiscoveryTimeoutSeconds: TimeInterval = 15
  private var hasStarted = false
  private let reportWriter = RuntimeVerificationReportWriter()

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
      runStatus: runStatus,
      failureCode: failureCode,
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

    NSApplication.shared.terminate(nil)
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
      throw Failure(code: .captureFailed, message: message)
    case .starting, .stopped:
      appendSnapshot(
        from: model,
        startedUptime: startedUptime,
        to: &context
      )
      throw Failure(
        code: .captureFailed,
        message: "The selected PowerPoint window did not enter the capturing state."
      )
    }

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
        throw Failure(code: .captureFailed, message: message)
      }

      let elapsed = currentUptime - observationStartedUptime
      let remaining = configuration.observationDurationSeconds - elapsed
      guard remaining > 0 else { break }
      try await Task.sleep(
        nanoseconds: UInt64(
          min(Self.sampleIntervalSeconds, remaining) * 1_000_000_000
        )
      )
    }
  }

  private func findWindow(
    matching target: RuntimeVerificationWindowTarget,
    model: AppModel,
    matchedWindowCount: inout Int
  ) async throws -> PowerPointWindowDescriptor {
    let deadline = Date().addingTimeInterval(Self.windowDiscoveryTimeoutSeconds)
    var lastResolution = RuntimeVerificationWindowSelection.Resolution.notFound

    repeat {
      await model.refreshPowerPointWindows()
      let selection = RuntimeVerificationWindowSelector.select(
        from: model.powerPointWindows,
        target: target
      )
      matchedWindowCount = selection.matchedWindowCount
      lastResolution = selection.resolution

      if case .selected(let windowID) = selection.resolution {
        let matchingDescriptors = model.powerPointWindows.filter { $0.id == windowID }
        switch matchingDescriptors.count {
        case 0:
          lastResolution = .notFound
        case 1:
          if let window = matchingDescriptors.first {
            return window
          }
        default:
          lastResolution = .ambiguous
        }
        matchedWindowCount = matchingDescriptors.count
      }

      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0 else { break }
      try await Task.sleep(
        nanoseconds: UInt64(
          min(Self.sampleIntervalSeconds, remaining) * 1_000_000_000
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
