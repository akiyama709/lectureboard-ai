import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppSlideCanvasIntegrationTests {
  @Test func captureStartClearsDemoSceneAndBlocksDemoUntilCaptureStops() async {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)

    #expect(model.canShowOverlayDemo)
    model.showOverlayDemo()
    #expect(!model.boardScene.elements.isEmpty)
    #expect(model.status == .overlayVisible)
    model.hideOverlay()
    #expect(!model.boardScene.elements.isEmpty)
    #expect(model.status == .ready)

    await model.startWindowCapture()

    #expect(model.captureStatus == .capturing)
    #expect(!model.canShowOverlayDemo)
    #expect(model.boardScene.elements.isEmpty)
    #expect(model.status == .ready)

    model.showOverlayDemo()
    #expect(model.boardScene.elements.isEmpty)
    #expect(model.status == .ready)

    await model.stopWindowCapture()
    #expect(model.canShowOverlayDemo)

    model.showOverlayDemo()
    #expect(!model.boardScene.elements.isEmpty)
    model.hideOverlay()
  }

  @Test func overlayDemoRemainsBlockedUntilCaptureProviderFinishesStopping() async {
    let capture = ManualCanvasCapture()
    let model = makeModel(capture: capture, analyzer: RecordingCanvasAnalyzer())

    await model.startWindowCapture()
    await capture.suspendNextStop()
    let stopTask = Task { await model.stopWindowCapture() }
    for _ in 0..<10_000 {
      if await capture.stopIsSuspended { break }
      await Task.yield()
    }

    #expect(await capture.stopIsSuspended)
    #expect(model.captureStatus == .stopped)
    #expect(!model.canShowOverlayDemo)
    model.showOverlayDemo()
    #expect(model.boardScene.elements.isEmpty)

    await capture.resumeStop()
    await stopTask.value
    #expect(model.captureStatus == .stopped)
    #expect(model.canShowOverlayDemo)
  }

  @Test func captureMetricsContinueWhileUnconfirmedCanvasKeepsAnalysisOff() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))

    await model.startWindowCapture()
    for sequenceNumber in 1...4 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.capturedFrameCount == 4 }

    #expect(model.captureStatus == .capturing)
    #expect(model.slideCanvasStatus == .needsConfirmation)
    #expect(model.latestCapturedWindowFrame != nil)
    #expect(model.stableFrameCount == 0)
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestStableFrame == nil)
    #expect(model.latestSlideAnalysis == nil)
    #expect(await analyzer.invocationCount == 0)

    await model.stopWindowCapture()
  }

  @Test func explicitCanvasConfirmationStartsCanvasOnlyStableAnalysis() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }

    model.beginSlideCanvasSelection()
    #expect(model.slideCanvasStatus == .selecting)
    #expect(model.confirmSlideCanvasSelection(region))
    #expect(model.slideCanvasStatus == .confirmed)
    #expect(model.confirmedSlideCanvasRegion == region)

    for sequenceNumber in 2...5 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    let analyzedSize = try #require(await analyzer.lastImageSize)
    #expect(analyzedSize.width == 40)
    #expect(analyzedSize.height == 40)
    #expect(model.latestStableFrame?.width == 40)
    #expect(model.latestStableFrame?.height == 40)
    #expect(model.stableFrameCount == 1)
    #expect(await analyzer.invocationCount == 1)

    await model.stopWindowCapture()
    #expect(model.slideCanvasStatus == .unavailable)
    #expect(model.confirmedSlideCanvasRegion == nil)
  }

  @Test func tinyCanvasConfirmationIsRejectedWithoutLeavingSelection() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let tinyRegion = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.2)
      )
    )
    let fullFrame = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()

    #expect(!model.confirmSlideCanvasSelection(tinyRegion))
    #expect(model.slideCanvasStatus == .selecting)
    #expect(model.slideCanvasCalibrationFrame != nil)
    #expect(model.confirmedSlideCanvasRegion == nil)
    #expect(await analyzer.invocationCount == 0)

    #expect(model.confirmSlideCanvasSelection(fullFrame))
    #expect(model.slideCanvasStatus == .confirmed)

    await model.stopWindowCapture()
  }

  @Test func reselectionAndCaptureRestartDoNotReplayEarlierTranscriptEvidence() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let fullFrame = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(fullFrame))
    for sequenceNumber in 2...5 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    model.receive(boardProposalDefinition(text: "Sustainability means preserving options."))
    #expect(!model.boardScene.elements.isEmpty)

    model.beginSlideCanvasSelection()
    #expect(model.slideCanvasStatus == .selecting)
    #expect(model.boardScene.elements.isEmpty)
    #expect(model.confirmSlideCanvasSelection(fullFrame))
    for sequenceNumber in 6...9 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    model.receive(lowImportanceAside(startTime: 10))
    #expect(model.boardScene.elements.isEmpty)
    model.receive(boardProposalDefinition(text: "Resilience means retaining function."))
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(fullFrame))
    for sequenceNumber in 2...5 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    model.receive(lowImportanceAside(startTime: 20))
    #expect(model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func captureEndClearsCanvasDependentAnalysisImageAndBoardScene() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let fullFrame = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(fullFrame))
    for sequenceNumber in 2...5 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    model.boardScene = BoardScene(
      slideNumber: 1,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
          text: "canvas-dependent content"
        )
      ]
    )
    #expect(model.latestStableFrame != nil)
    #expect(model.latestSlideAnalysis != nil)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()

    #expect(model.slideCanvasStatus == .unavailable)
    #expect(model.latestStableFrame == nil)
    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.boardScene.elements.isEmpty)
  }

  @Test func missingCaptureGeometryCannotEnterUserConfirmedPipeline() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(
      frameWithoutCaptureGeometry(sequenceNumber: 1, image: image)
    )
    try await waitUntil { model.slideCanvasStatus == .invalidated }

    model.beginSlideCanvasSelection()
    #expect(model.slideCanvasStatus == .invalidated)
    #expect(!model.confirmSlideCanvasSelection(region))
    #expect(model.confirmedSlideCanvasRegion == nil)
    #expect(model.stableFrameCount == 0)
    #expect(await analyzer.invocationCount == 0)

    await capture.emit(frame(sequenceNumber: 2, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }

    await model.stopWindowCapture()
  }

  @Test func sourceDimensionChangeInvalidatesCanvasAndRejectsOldAnalysis() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = SuspendedCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let originalImage = try #require(makeImage(width: 80, height: 40))
    let resizedImage = try #require(makeImage(width: 100, height: 40))
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: originalImage))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(region))

    for sequenceNumber in 2...5 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: originalImage))
    }
    try await analyzer.waitForInvocation()
    #expect(model.slideAnalysisStatus == .analyzing)
    model.boardScene = BoardScene(
      slideNumber: 1,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1),
          text: "old canvas content"
        )
      ]
    )

    await capture.emit(frame(sequenceNumber: 6, image: resizedImage))
    try await waitUntil { model.slideCanvasStatus == .invalidated }
    #expect(model.stableFrameCount == 0)
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestStableFrame == nil)
    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.boardScene.elements.isEmpty)

    await analyzer.succeed(title: "stale canvas result")
    await drainMainActorQueue()
    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)

    await model.stopWindowCapture()
  }

  @Test func surfaceGeometryChangeInvalidatesCanvasAtTheSameImageSize() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = SuspendedCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let originalGeometry = captureGeometry(for: image)
    let changedGeometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 2, y: 0, width: 78, height: 40),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: 80,
        outputPixelHeight: 40
      )
    )
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(
      frame(sequenceNumber: 1, image: image, captureSurfaceGeometry: originalGeometry)
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(region))

    for sequenceNumber in 2...5 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          captureSurfaceGeometry: originalGeometry
        )
      )
    }
    try await analyzer.waitForInvocation()
    #expect(model.slideAnalysisStatus == .analyzing)

    await capture.emit(
      frame(sequenceNumber: 6, image: image, captureSurfaceGeometry: changedGeometry)
    )
    try await waitUntil { model.slideCanvasStatus == .invalidated }
    #expect(model.confirmedSlideCanvasRegion == nil)
    #expect(model.stableFrameCount == 0)
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestStableFrame == nil)
    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)

    await analyzer.succeed(title: "stale geometry result")
    await drainMainActorQueue()
    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)

    await model.stopWindowCapture()
  }

  @Test func geometryChangeWhileSelectingRejectsTheFrozenCalibrationFrame() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let originalGeometry = captureGeometry(for: image)
    let changedGeometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 0, y: 1, width: 80, height: 39),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: 80,
        outputPixelHeight: 40
      )
    )
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(
      frame(sequenceNumber: 1, image: image, captureSurfaceGeometry: originalGeometry)
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.slideCanvasStatus == .selecting)

    await capture.emit(
      frame(sequenceNumber: 2, image: image, captureSurfaceGeometry: changedGeometry)
    )
    try await waitUntil { model.slideCanvasStatus == .invalidated }
    #expect(!model.confirmSlideCanvasSelection(region))
    #expect(model.slideCanvasCalibrationFrame == nil)
    #expect(model.confirmedSlideCanvasRegion == nil)
    #expect(await analyzer.invocationCount == 0)

    await model.stopWindowCapture()
  }

  @Test func changesOutsideConfirmedCanvasDoNotTriggerContentUpdatesOrReanalysis() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let initialImage = try #require(
      makeSplitImage(outsideRGB: (220, 20, 20), canvasRGB: (20, 20, 220))
    )
    let outsideOnlyChange = try #require(
      makeSplitImage(outsideRGB: (20, 220, 20), canvasRGB: (20, 20, 220))
    )
    let insideChange = try #require(
      makeSplitImage(outsideRGB: (20, 220, 20), canvasRGB: (20, 20, 20))
    )
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(frame(sequenceNumber: 1, image: initialImage))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(region))

    for sequenceNumber in 2...5 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: initialImage))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(await analyzer.invocationCount == 1)

    for sequenceNumber in 6...10 {
      await capture.emit(
        frame(sequenceNumber: UInt64(sequenceNumber), image: outsideOnlyChange)
      )
    }
    try await waitUntil { model.capturedFrameCount == 10 }
    #expect(model.contentRevisionCount == 0)
    #expect(model.stableFrameCount == 1)
    #expect(await analyzer.invocationCount == 1)

    for sequenceNumber in 11...15 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: insideChange))
    }
    try await waitUntil { model.contentRevisionCount == 1 }
    try await analyzer.waitForInvocationCount(2)
    #expect(await analyzer.invocationCount == 2)

    await model.stopWindowCapture()
  }

  private func makeModel(
    capture: ManualCanvasCapture,
    analyzer: any SlideVisualAnalyzing
  ) -> AppModel {
    let model = AppModel(
      permissionService: PermissionService(
        screenCaptureClient: ManualCanvasAuthorizedPermissionClient()
      ),
      windowCapture: capture,
      scanner: ManualCanvasWindowScanner(),
      slideVisionAnalyzer: analyzer
    )
    model.powerPointWindows = [
      PowerPointWindowDescriptor(
        id: 42,
        title: "Synthetic manual canvas window",
        applicationName: "Microsoft PowerPoint",
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        frame: .zero
      )
    ]
    model.selectedPowerPointWindowID = 42
    return model
  }

  private func frame(sequenceNumber: UInt64, image: CGImage) -> CapturedPowerPointFrame {
    frame(
      sequenceNumber: sequenceNumber,
      image: image,
      captureSurfaceGeometry: captureGeometry(for: image)
    )
  }

  private func frameWithoutCaptureGeometry(
    sequenceNumber: UInt64,
    image: CGImage
  ) -> CapturedPowerPointFrame {
    frame(
      sequenceNumber: sequenceNumber,
      image: image,
      captureSurfaceGeometry: nil
    )
  }

  private func frame(
    sequenceNumber: UInt64,
    image: CGImage,
    captureSurfaceGeometry: CaptureSurfaceGeometry?
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(timeIntervalSince1970: TimeInterval(sequenceNumber)),
      displayTime: sequenceNumber,
      deliveryKind: .new,
      captureSurfaceGeometry: captureSurfaceGeometry,
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

  private func captureGeometry(for image: CGImage) -> CaptureSurfaceGeometry {
    guard
      let geometry = CaptureSurfaceGeometry(
        contentRect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: image.width,
        outputPixelHeight: image.height
      )
    else {
      preconditionFailure("Synthetic geometry must be valid.")
    }
    return geometry
  }

  private func makeImage(width: Int, height: Int) -> CGImage? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()
  }

  private func makeSplitImage(
    outsideRGB: (UInt8, UInt8, UInt8),
    canvasRGB: (UInt8, UInt8, UInt8)
  ) -> CGImage? {
    let width = 80
    let height = 40
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for _ in 0..<height {
      for column in 0..<width {
        let rgb = column < width / 2 ? outsideRGB : canvasRGB
        bytes.append(contentsOf: [rgb.0, rgb.1, rgb.2, 255])
      }
    }
    guard
      let provider = CGDataProvider(data: Data(bytes) as CFData)
    else {
      return nil
    }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue:
          CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private func boardProposalOccupiedRegions() -> [NormalizedRect] {
    [NormalizedRect(x: 0.05, y: 0.05, width: 0.2, height: 0.15)]
  }

  private func boardProposalDefinition(text: String) -> TranscriptSegment {
    TranscriptSegment(
      text: text,
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0.9
    )
  }

  private func lowImportanceAside(startTime: TimeInterval) -> TranscriptSegment {
    TranscriptSegment(
      text: "This is a brief aside.",
      startTime: startTime,
      endTime: startTime + 1,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0
    )
  }

  private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    throw AppSlideCanvasIntegrationTestError.timedOut
  }

  private func drainMainActorQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }
}

private enum AppSlideCanvasIntegrationTestError: Error {
  case timedOut
}

private actor ManualCanvasCapture: PowerPointWindowCapturing {
  private var frameHandler: CaptureFrameHandler?
  private var shouldSuspendNextStop = false
  private var suspendedStopContinuation: CheckedContinuation<Void, Never>?

  var stopIsSuspended: Bool {
    suspendedStopContinuation != nil
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    frameHandler = onFrame
  }

  func stop(operationID: CaptureOperationID) async {
    frameHandler = nil
    guard shouldSuspendNextStop else { return }
    shouldSuspendNextStop = false
    await withCheckedContinuation { continuation in
      suspendedStopContinuation = continuation
    }
  }

  func suspendNextStop() {
    shouldSuspendNextStop = true
  }

  func resumeStop() {
    suspendedStopContinuation?.resume()
    suspendedStopContinuation = nil
  }

  func emit(_ frame: CapturedPowerPointFrame) {
    frameHandler?(frame)
  }
}

private struct ManualCanvasWindowScanner: PowerPointWindowScanning {
  func scan() async throws -> [PowerPointWindowDescriptor] { [] }
}

private struct ManualCanvasAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }
  func requestAccess() -> Bool { true }
}

private actor RecordingCanvasAnalyzer: SlideVisualAnalyzing {
  private(set) var invocationCount = 0
  private(set) var lastImageSize: (width: Int, height: Int)?
  private let occupiedRegions: [NormalizedRect]

  init(occupiedRegions: [NormalizedRect] = []) {
    self.occupiedRegions = occupiedRegions
  }

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    invocationCount += 1
    lastImageSize = (frame.image.width, frame.image.height)
    return SlideVisualAnalysis(
      title: "confirmed canvas",
      occupiedRegions: occupiedRegions
    )
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if invocationCount >= expectedCount { return }
      await Task.yield()
    }
    throw AppSlideCanvasIntegrationTestError.timedOut
  }
}

private actor SuspendedCanvasAnalyzer: SlideVisualAnalyzing {
  private var continuation: CheckedContinuation<SlideVisualAnalysis, any Error>?
  private var wasInvoked = false

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    wasInvoked = true
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitForInvocation() async throws {
    for _ in 0..<10_000 {
      if wasInvoked { return }
      await Task.yield()
    }
    throw AppSlideCanvasIntegrationTestError.timedOut
  }

  func succeed(title: String) {
    continuation?.resume(returning: SlideVisualAnalysis(title: title))
    continuation = nil
  }
}
