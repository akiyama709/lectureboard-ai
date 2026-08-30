import CoreGraphics
import Darwin
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppSlideIdentityIntegrationTests {
  @Test func establishedBaselineRebasesWithoutCountingAChange() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let seventhSlide = try sample(slideID: 707, slideIndex: 7)
    model.boardScene = markerScene(slideNumber: 1)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(seventhSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    #expect(model.boardScene.slideNumber == 1)
    #expect(model.boardScene.elements.count == 1)

    await provider.emit(sequenceNumber: 2, signal: .available(seventhSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 7)
    #expect(model.boardScene.elements.isEmpty)

    model.boardScene = markerScene(slideNumber: 7)
    let reorderedSameSlide = try sample(slideID: 707, slideIndex: 8)
    await provider.emit(sequenceNumber: 3, signal: .available(reorderedSameSlide))
    try await waitUntil { model.boardScene.slideNumber == 8 }
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.elements.count == 1)

    await model.stopWindowCapture()
  }

  @Test func confirmedSemanticTransitionCountsAndClearsThePreviousBoard() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    #expect(model.captureStatus == .capturing)

    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }
    #expect(model.slideChangeCount == 0)

    model.boardScene = BoardScene(
      slideNumber: 1,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
          text: "Previous slide"
        )
      ]
    )

    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }

    #expect(model.slideIdentityState == .identified)
    #expect(model.slideIdentitySampleCount == 4)
    #expect(model.slideIdentityContinuityBreakCount == 0)
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    let snapshot = RuntimeVerificationSnapshotProjector.makeSnapshot(
      from: model,
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: 1_000,
      screenRecordingPermission: .authorized
    )
    #expect(snapshot.slideChangeCount == 1)
    #expect(snapshot.slideIdentityState == .identified)
    #expect(snapshot.slideIdentitySampleCount == 4)
    #expect(snapshot.slideIdentityContinuityBreakCount == 0)

    await model.stopWindowCapture()
  }

  @Test func rejectsDuplicateOutOfOrderAndWrongTargetObservations() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let candidateSlide = try sample(slideID: 202, slideIndex: 2)
    let wrongIdentity = try #require(
      PowerPointWindowIdentity(
        windowID: 43,
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    await provider.emit(sequenceNumber: 4, signal: .available(candidateSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    await provider.emit(sequenceNumber: 4, signal: .available(candidateSlide))
    await provider.emit(sequenceNumber: 3, signal: .available(candidateSlide))
    await provider.emit(
      sequenceNumber: 5,
      signal: .available(candidateSlide),
      targetIdentity: wrongIdentity
    )
    await drainMainActorQueue()

    #expect(model.slideIdentityState == .establishing)
    #expect(model.slideIdentitySampleCount == 3)
    #expect(model.slideChangeCount == 0)

    await provider.emit(sequenceNumber: 5, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }
    #expect(model.slideIdentitySampleCount == 4)
    #expect(model.slideChangeCount == 0)

    await model.stopWindowCapture()
  }

  @Test func unavailableGapRequiresANewBaselineWithoutInferringAChange() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    await provider.emit(sequenceNumber: 3, signal: .unavailable)
    try await waitUntil { model.slideIdentityState == .interrupted }
    #expect(model.slideIdentityContinuityBreakCount == 1)

    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 5, signal: .available(secondSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    #expect(model.slideIdentitySampleCount == 5)
    #expect(model.slideIdentityContinuityBreakCount == 1)
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func candidateIdentityQuarantinesAnalysisAndBoardUpdatesUntilConfirmed() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer()
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 100, count: 32 * 18)
    )
    let contentFingerprint = ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )
    let definitionSegment = TranscriptSegment(
      text:
        "Sustainability means meeting present needs without undermining future possibilities.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0.8
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(await analyzer.analysisCount == 1)

    model.boardScene = markerScene(slideNumber: 1)
    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)

    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    model.receive(definitionSegment)
    await drainMainActorQueue()

    #expect(await analyzer.analysisCount == 1)
    #expect(model.boardScene.slideNumber == 1)
    #expect(model.boardScene.elements.count == 1)

    let preConfirmationTranscriptMachTime = mach_absolute_time()
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    model.receive(definitionSegment)
    #expect(model.boardScene.elements.isEmpty)

    for sequenceNumber in 7...8 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    await drainMainActorQueue()
    #expect(await analyzer.analysisCount == 1)
    #expect(model.slideAnalysisStatus == .idle)

    await capture.emit(
      frame(
        sequenceNumber: 9,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    for sequenceNumber in 10...11 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(await analyzer.analysisCount == 2)

    model.receive(
      TranscriptionObservation(
        segment: definitionSegment,
        sourceMachTime: preConfirmationTranscriptMachTime
      )
    )
    #expect(model.boardScene.elements.isEmpty)
    #expect(!SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 0, after: nil))
    #expect(SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 1, after: nil))
    #expect(!SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 99, after: 100))
    #expect(!SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 100, after: 100))
    #expect(SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 101, after: 100))

    model.receive(definitionSegment)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func currentSelectionMustStillMatchBeforeAcceptingAnIdentity() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    model.selectedPowerPointWindowID = 43
    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    await drainMainActorQueue()

    #expect(model.slideIdentitySampleCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 1)

    await model.stopWindowCapture()
  }

  @Test func observationsFromAStoppedSessionCannotEnterTheRestartedSession() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let staleSlide = try sample(slideID: 999, slideIndex: 9)

    await model.startWindowCapture()
    await model.stopWindowCapture()
    #expect(model.slideIdentityState == .unavailable)
    await model.startWindowCapture()

    #expect(await provider.startCount == 2)
    await provider.emit(
      startIndex: 0,
      sequenceNumber: 100,
      signal: .available(staleSlide)
    )
    await provider.emit(
      startIndex: 0,
      sequenceNumber: 101,
      signal: .available(staleSlide)
    )
    await drainMainActorQueue()
    #expect(model.slideIdentitySampleCount == 0)

    await provider.emit(startIndex: 1, sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(startIndex: 1, sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    #expect(model.slideIdentitySampleCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 1)

    await model.stopWindowCapture()
  }

  @Test func captureFailuresInterruptOnlyEstablishedIdentityContinuity() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    await capture.emitError("controlled capture failure")
    try await waitUntil {
      model.captureStatus == .error("controlled capture failure")
    }

    #expect(model.slideIdentityState == .interrupted)
    #expect(model.slideIdentitySampleCount == 2)
    #expect(model.slideChangeCount == 0)

    let unavailableCapture = SlideIdentityFrameCapture()
    let unavailableProvider = ControllableSlideIdentityProvider()
    let unavailableModel = makeModel(
      capture: unavailableCapture,
      provider: unavailableProvider
    )
    await unavailableModel.startWindowCapture()
    await unavailableCapture.emitError("failure without identity continuity")
    try await waitUntil {
      unavailableModel.captureStatus == .error("failure without identity continuity")
    }
    #expect(unavailableModel.slideIdentityState == .unavailable)
    #expect(unavailableModel.slideIdentitySampleCount == 0)

    let failingProvider = ControllableSlideIdentityProvider()
    let failingModel = makeModel(
      capture: FailingSlideIdentityFrameCapture(),
      provider: failingProvider
    )
    await failingModel.startWindowCapture()
    guard case .error = failingModel.captureStatus else {
      Issue.record("A controlled capture-start failure must be visible.")
      return
    }
    #expect(failingModel.slideIdentityState == .unavailable)
    #expect(failingModel.slideIdentitySampleCount == 0)
  }

  @Test func preConfirmationFramesCannotEstablishTheNewSlideAfterATransition() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer()
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 100, count: 32 * 18)
    )
    let contentFingerprint = ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    let preConfirmationDisplayTime = mach_absolute_time()
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }

    await capture.emit(
      CapturedPowerPointFrame(
        windowID: 42,
        sequenceNumber: 1,
        capturedAt: Date(),
        displayTime: nil,
        deliveryKind: .new,
        image: image,
        fingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 2,
        displayTime: 0,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 3,
        displayTime: preConfirmationDisplayTime,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 4,
        deliveryKind: .idleRepeat,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await drainMainActorQueue()
    #expect(model.capturedFrameCount == 4)
    #expect(model.stableFrameCount == 0)
    #expect(await analyzer.analysisCount == 0)
    #expect(!SlideIdentityFrameBoundary.accepts(displayTime: nil, after: 100))
    #expect(!SlideIdentityFrameBoundary.accepts(displayTime: 0, after: 100))
    #expect(!SlideIdentityFrameBoundary.accepts(displayTime: 99, after: 100))
    #expect(!SlideIdentityFrameBoundary.accepts(displayTime: 100, after: 100))
    #expect(SlideIdentityFrameBoundary.accepts(displayTime: 101, after: 100))

    await capture.emit(
      frame(
        sequenceNumber: 5,
        deliveryKind: .new,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    for sequenceNumber in 6...7 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(model.stableFrameCount == 1)
    #expect(await analyzer.analysisCount == 1)

    await model.stopWindowCapture()
  }

  @Test func confirmedTransitionRejectsAnInFlightAnalysisFromThePreviousSlide() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = SuspendedSlideIdentityAnalyzer()
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 100, count: 32 * 18)
    )
    let contentFingerprint = ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    for sequenceNumber in 1...3 {
      await capture.emit(
        CapturedPowerPointFrame(
          windowID: 42,
          sequenceNumber: UInt64(sequenceNumber),
          capturedAt: Date().addingTimeInterval(TimeInterval(sequenceNumber)),
          displayTime: mach_absolute_time() + UInt64(sequenceNumber),
          deliveryKind: .new,
          image: image,
          fingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 3)
    #expect(model.slideAnalysisStatus == .analyzing)

    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)

    try await analyzer.succeed(sequenceNumber: 3, title: "Stale slide")
    await drainMainActorQueue()

    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.boardScene.slideNumber == 2)

    await model.stopWindowCapture()
  }

  private func makeModel(
    capture: any PowerPointWindowCapturing,
    provider: ControllableSlideIdentityProvider,
    analyzer: any SlideVisualAnalyzing = ImmediateSlideIdentityAnalyzer()
  ) -> AppModel {
    let model = AppModel(
      permissionService: PermissionService(
        screenCaptureClient: SlideIdentityAuthorizedPermissionClient()
      ),
      windowCapture: capture,
      scanner: EmptySlideIdentityWindowScanner(),
      slideIdentityProvider: provider,
      slideVisionAnalyzer: analyzer
    )
    model.powerPointWindows = [
      PowerPointWindowDescriptor(
        id: 42,
        title: "Synthetic slide identity window",
        applicationName: "Microsoft PowerPoint",
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        frame: .zero
      )
    ]
    model.selectedPowerPointWindowID = 42
    return model
  }

  private func sample(slideID: Int, slideIndex: Int) throws -> SlideIdentitySample {
    try #require(
      SlideIdentitySample(
        presentationSessionToken: "ephemeral-test-session",
        slideID: slideID,
        slideIndex: slideIndex
      )
    )
  }

  private func makeImage() -> CGImage? {
    CGContext(
      data: nil,
      width: 2,
      height: 2,
      bitsPerComponent: 8,
      bytesPerRow: 8,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()
  }

  private func frame(
    sequenceNumber: UInt64,
    deliveryKind: CapturedFrameDeliveryKind = .new,
    displayTime: UInt64? = nil,
    image: CGImage,
    coarseFingerprint: FrameFingerprint,
    contentFingerprint: ContentFingerprint
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date().addingTimeInterval(TimeInterval(sequenceNumber)),
      displayTime: displayTime ?? mach_absolute_time() + sequenceNumber,
      deliveryKind: deliveryKind,
      image: image,
      fingerprint: coarseFingerprint,
      contentFingerprint: contentFingerprint
    )
  }

  private func markerScene(slideNumber: Int) -> BoardScene {
    BoardScene(
      slideNumber: slideNumber,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
          text: "Existing board content"
        )
      ]
    )
  }

  private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    throw AppSlideIdentityIntegrationTestError.timedOut
  }

  private func drainMainActorQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }
}

private struct SlideIdentityProviderStart: Sendable {
  let operationID: CaptureOperationID
  let identity: PowerPointWindowIdentity
  let handler: PowerPointSlideIdentityObservationHandler
}

private actor ControllableSlideIdentityProvider: PowerPointSlideIdentityProviding {
  private var starts: [SlideIdentityProviderStart] = []
  private var stops: [CaptureOperationID] = []

  var startCount: Int { starts.count }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async {
    starts.append(
      SlideIdentityProviderStart(
        operationID: operationID,
        identity: identity,
        handler: onObservation
      )
    )
  }

  func stop(operationID: CaptureOperationID) async {
    stops.append(operationID)
  }

  func emit(
    startIndex: Int? = nil,
    sequenceNumber: UInt64,
    signal: SlideIdentitySignal,
    targetIdentity: PowerPointWindowIdentity? = nil
  ) {
    guard !starts.isEmpty else { return }
    let index = startIndex ?? starts.index(before: starts.endIndex)
    guard starts.indices.contains(index) else { return }
    let start = starts[index]
    start.handler(
      PowerPointSlideIdentityObservation(
        sequenceNumber: sequenceNumber,
        observedAt: Date(),
        targetIdentity: targetIdentity ?? start.identity,
        signal: signal
      )
    )
  }
}

private actor SlideIdentityFrameCapture: PowerPointWindowCapturing {
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

  func emit(_ frame: CapturedPowerPointFrame) {
    frameHandler?(frame)
  }

  func emitError(_ message: String) {
    errorHandler?(message)
  }
}

private struct FailingSlideIdentityFrameCapture: PowerPointWindowCapturing {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    throw AppSlideIdentityIntegrationTestError.controlledCaptureStartFailure
  }

  func stop(operationID: CaptureOperationID) async {}
}

private struct ImmediateSlideIdentityAnalyzer: SlideVisualAnalyzing {
  func analyze(_ frame: CapturedPowerPointFrame) async throws -> SlideVisualAnalysis {
    SlideVisualAnalysis()
  }
}

private actor CountingSlideIdentityAnalyzer: SlideVisualAnalyzing {
  private(set) var analysisCount = 0

  func analyze(_ frame: CapturedPowerPointFrame) async throws -> SlideVisualAnalysis {
    analysisCount += 1
    return SlideVisualAnalysis(title: "Current analysis")
  }
}

private enum AppSlideIdentityIntegrationTestError: Error {
  case controlledCaptureStartFailure
  case timedOut
  case missingAnalysis(UInt64)
}

private actor SuspendedSlideIdentityAnalyzer: SlideVisualAnalyzing {
  private var invocations: Set<UInt64> = []
  private var continuations: [UInt64: CheckedContinuation<SlideVisualAnalysis, any Error>] = [:]

  func analyze(_ frame: CapturedPowerPointFrame) async throws -> SlideVisualAnalysis {
    invocations.insert(frame.sequenceNumber)
    return try await withCheckedThrowingContinuation { continuation in
      continuations[frame.sequenceNumber] = continuation
    }
  }

  func waitForInvocation(sequenceNumber: UInt64) async throws {
    for _ in 0..<10_000 {
      if invocations.contains(sequenceNumber) { return }
      await Task.yield()
    }
    throw AppSlideIdentityIntegrationTestError.timedOut
  }

  func succeed(sequenceNumber: UInt64, title: String) throws {
    guard let continuation = continuations.removeValue(forKey: sequenceNumber) else {
      throw AppSlideIdentityIntegrationTestError.missingAnalysis(sequenceNumber)
    }
    continuation.resume(returning: SlideVisualAnalysis(title: title))
  }
}

private struct EmptySlideIdentityWindowScanner: PowerPointWindowScanning {
  func scan() async throws -> [PowerPointWindowDescriptor] { [] }
}

@MainActor
private struct SlideIdentityAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }

  func requestAccess() -> Bool { true }
}
