import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct RuntimeVerificationRunnerIntegrationTests {
  @Test func timingRejectsZeroAndNegativeBusyLoops() {
    let timing = RuntimeVerificationTiming(
      sampleIntervalSeconds: .nan,
      windowDiscoveryTimeoutSeconds: .infinity,
      canvasConfirmationTimeoutSeconds: -.infinity
    )

    #expect(timing.sampleIntervalSeconds == 0.001)
    #expect(timing.windowDiscoveryTimeoutSeconds == 0.001)
    #expect(timing.canvasConfirmationTimeoutSeconds == 0.001)
  }

  @Test func confirmsDiagnosticCanvasAndRecordsItsProvenance() async throws {
    let capture = RuntimeRunnerCapture()
    let model = makeModel(capture: capture)
    let outputPath = uniqueReportPath()
    defer { try? FileManager.default.removeItem(atPath: outputPath) }
    let runner = makeRunner()

    let runTask = Task {
      await runner.run(configuration: configuration(outputPath: outputPath), model: model)
    }
    try await capture.waitUntilStarted()
    await capture.emit(makeFrame(sequenceNumber: 1))
    await runTask.value

    let report = try decodeReport(atPath: outputPath)
    #expect(report.runStatus == .completed)
    #expect(report.failureCode == nil)
    #expect(report.slideCanvasConfirmationMode == .diagnosticFullFrame)
    #expect(report.snapshots.contains { $0.slideCanvasState == .confirmed })
  }

  @Test func noFrameTimeoutWritesFailClosedReport() async throws {
    let capture = RuntimeRunnerCapture()
    let model = makeModel(capture: capture)
    let outputPath = uniqueReportPath()
    defer { try? FileManager.default.removeItem(atPath: outputPath) }
    let runner = makeRunner()

    await runner.run(configuration: configuration(outputPath: outputPath), model: model)

    let report = try decodeReport(atPath: outputPath)
    #expect(report.runStatus == .failed)
    #expect(report.failureCode == .captureFrameUnavailable)
    #expect(
      report.failureMessage
        == RuntimeVerificationFailureCode.captureFrameUnavailable.safeReportMessage
    )
    #expect(report.slideCanvasConfirmationMode == .diagnosticFullFrame)
    #expect(
      report.snapshots.contains { snapshot in
        snapshot.frameCount == 0 && snapshot.slideCanvasState == .waitingForFrame
      })
  }

  @Test func invalidationAfterDiagnosticConfirmationFailsTheRun() async throws {
    let capture = RuntimeRunnerCapture()
    let model = makeModel(capture: capture)
    let outputPath = uniqueReportPath()
    defer { try? FileManager.default.removeItem(atPath: outputPath) }
    let runner = makeRunner()

    let runTask = Task {
      await runner.run(
        configuration: configuration(
          outputPath: outputPath,
          observationDurationSeconds: 0.08
        ),
        model: model
      )
    }
    try await capture.waitUntilStarted()
    await capture.emit(makeFrame(sequenceNumber: 1))
    try await waitUntil { model.slideCanvasStatus == .confirmed }
    await capture.emit(makeFrame(sequenceNumber: 2, changesSurfaceGeometry: true))
    await runTask.value

    let report = try decodeReport(atPath: outputPath)
    #expect(report.runStatus == .failed)
    #expect(report.failureCode == .slideCanvasConfirmationFailed)
    #expect(report.slideCanvasConfirmationMode == .diagnosticFullFrame)
    #expect(report.snapshots.contains { $0.slideCanvasState == .invalidated })
  }

  @Test func captureErrorDuringCanvasWaitWritesCaptureFailure() async throws {
    let capture = RuntimeRunnerCapture()
    let model = makeModel(capture: capture)
    let outputPath = uniqueReportPath()
    defer { try? FileManager.default.removeItem(atPath: outputPath) }
    let runner = makeRunner()

    let runTask = Task {
      await runner.run(configuration: configuration(outputPath: outputPath), model: model)
    }
    try await capture.waitUntilStarted()
    await capture.emitError("private provider detail")
    await runTask.value

    let report = try decodeReport(atPath: outputPath)
    #expect(report.runStatus == .failed)
    #expect(report.failureCode == .captureFailed)
    #expect(
      report.failureMessage == RuntimeVerificationFailureCode.captureFailed.safeReportMessage
    )
    #expect(report.slideCanvasConfirmationMode == .diagnosticFullFrame)
    let encoded = try String(contentsOfFile: outputPath, encoding: .utf8)
    #expect(!encoded.contains("private provider detail"))
  }

  private func makeRunner() -> RuntimeVerificationRunner {
    RuntimeVerificationRunner(
      timing: RuntimeVerificationTiming(
        sampleIntervalSeconds: 0.002,
        windowDiscoveryTimeoutSeconds: 0.05,
        canvasConfirmationTimeoutSeconds: 0.05
      ),
      terminateApplication: {}
    )
  }

  private func configuration(
    outputPath: String,
    observationDurationSeconds: TimeInterval = 0.04
  ) -> RuntimeVerificationConfiguration {
    RuntimeVerificationConfiguration(
      targetWindow: .windowID(42),
      observationDurationSeconds: observationDurationSeconds,
      outputPath: outputPath,
      requestsScreenRecordingPermission: false,
      canvasSelection: .confirmFullFrame
    )
  }

  private func makeModel(capture: RuntimeRunnerCapture) -> AppModel {
    let window = PowerPointWindowDescriptor(
      id: 42,
      title: "Synthetic runtime verifier window",
      applicationName: "Microsoft PowerPoint",
      ownerProcessID: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
      frame: .zero
    )
    return AppModel(
      permissionService: PermissionService(
        screenCaptureClient: RuntimeRunnerAuthorizedPermissionClient()
      ),
      windowCapture: capture,
      scanner: RuntimeRunnerWindowScanner(windows: [window]),
      slideVisionAnalyzer: RuntimeRunnerAnalyzer()
    )
  }

  private func makeFrame(
    sequenceNumber: UInt64,
    changesSurfaceGeometry: Bool = false
  ) -> CapturedPowerPointFrame {
    let image = makeImage(width: 64, height: 48)
    let contentRect =
      changesSurfaceGeometry
      ? CGRect(x: 1, y: 0, width: 63, height: 48)
      : CGRect(x: 0, y: 0, width: 64, height: 48)
    let surface = CaptureSurfaceGeometry(
      contentRect: contentRect,
      scaleFactor: 1,
      contentScale: 1,
      outputPixelWidth: 64,
      outputPixelHeight: 48
    )!
    return CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(),
      displayTime: UInt64.max,
      deliveryKind: .new,
      captureSurfaceGeometry: surface,
      captureScreenGeometry: nil,
      image: image,
      fingerprint: FrameFingerprint(
        sampleColumns: 32,
        sampleRows: 18,
        luminance: Array(repeating: 128, count: 32 * 18)
      ),
      contentFingerprint: ContentFingerprint(
        sampleColumns: 160,
        sampleRows: 90,
        cells: Array(
          repeating: RGBContentCell(red: 255, green: 255, blue: 255),
          count: 160 * 90
        )
      )
    )
  }

  private func makeImage(width: Int, height: Int) -> CGImage {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
  }

  private func uniqueReportPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("lectureboard-runner-\(UUID().uuidString).json")
      .path
  }

  private func decodeReport(atPath path: String) throws -> RuntimeVerificationReport {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RuntimeVerificationReport.self, from: data)
  }

  private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    throw RuntimeRunnerTestError.timedOut
  }
}

private enum RuntimeRunnerTestError: Error {
  case timedOut
}

private actor RuntimeRunnerCapture: PowerPointWindowCapturing {
  private var frameHandler: CaptureFrameHandler?
  private var errorHandler: CaptureErrorHandler?

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    frameHandler = onFrame
    errorHandler = onError
  }

  func stop(operationID: CaptureOperationID) async {
    frameHandler = nil
    errorHandler = nil
  }

  func waitUntilStarted() async throws {
    for _ in 0..<10_000 {
      if frameHandler != nil { return }
      await Task.yield()
    }
    throw RuntimeRunnerTestError.timedOut
  }

  func emit(_ frame: CapturedPowerPointFrame) {
    frameHandler?(frame)
  }

  func emitError(_ message: String) {
    errorHandler?(message)
  }
}

private struct RuntimeRunnerWindowScanner: PowerPointWindowScanning {
  let windows: [PowerPointWindowDescriptor]

  func scan() async throws -> [PowerPointWindowDescriptor] {
    windows
  }
}

@MainActor
private struct RuntimeRunnerAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }
  func requestAccess() -> Bool { true }
}

private actor RuntimeRunnerAnalyzer: SlideVisualAnalyzing {
  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    SlideVisualAnalysis(title: "synthetic")
  }
}
