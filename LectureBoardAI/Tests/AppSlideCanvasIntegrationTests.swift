import AppKit
import CoreGraphics
import Darwin
import Foundation
import LectureBoardCore
import ScreenCaptureKit
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppSlideCanvasIntegrationTests {
  @Test func captureStartHidesAVisibleDemoPanel() async {
    let capture = ManualCanvasCapture()
    let overlay = RecordingCanvasOverlayController()
    let model = makeModel(
      capture: capture,
      analyzer: RecordingCanvasAnalyzer(),
      overlay: overlay
    )

    model.showOverlayDemo()
    #expect(overlay.showCallCount == 1)
    #expect(overlay.hideCallCount == 0)

    await model.startWindowCapture()

    #expect(model.captureStatus == .capturing)
    #expect(overlay.hideCallCount > 0)
    #expect(!overlay.isVisible)

    await model.stopWindowCapture()
  }

  @Test func confirmedCanvasOverlayMovesOnlyWithCurrentFrameScreenGeometry() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let display = try #require(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
      )
    )
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [display]
    )
    let image = try #require(makeImage(width: 200, height: 120))
    let surface = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 10, y: 10, width: 80, height: 40),
        scaleFactor: 2,
        contentScale: 0.5,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let initialScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 100, y: 200, width: 160, height: 80)
      )
    )
    let movedScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 300, y: 250, width: 160, height: 80)
      )
    )
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )

    await model.startWindowCapture()
    try await waitUntil { model.slideIdentityState == .identified }
    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        captureSurfaceGeometry: surface,
        captureScreenGeometry: initialScreen
      )
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(region))
    #expect(model.slideCanvasOverlayMappingState == .mapped)

    for sequenceNumber in 2...4 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          captureSurfaceGeometry: surface,
          captureScreenGeometry: initialScreen
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: image,
        captureSurfaceGeometry: surface,
        captureScreenGeometry: initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 5 }
    receiveConfirmedBoardProposal(
      "Sustainability means preserving options.",
      on: model
    )

    #expect(!model.boardScene.elements.isEmpty)
    #expect(overlay.isVisible)
    #expect(
      rect(
        overlay.renderedFrames.last,
        isApproximately: CGRect(x: 140, y: 630, width: 80, height: 60)
      )
    )

    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: image,
        captureSurfaceGeometry: surface,
        captureScreenGeometry: movedScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 6 }
    #expect(model.slideCanvasStatus == .confirmed)
    #expect(overlay.isVisible)
    #expect(
      rect(
        overlay.renderedFrames.last,
        isApproximately: CGRect(x: 340, y: 580, width: 80, height: 60)
      )
    )

    let hidesBeforeMissingPosition = overlay.hideCallCount
    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: image,
        captureSurfaceGeometry: surface,
        captureScreenGeometry: nil
      )
    )
    try await waitUntil { model.capturedFrameCount == 7 }
    #expect(model.slideCanvasStatus == .confirmed)
    #expect(
      model.slideCanvasOverlayMappingState == .rejected(.screenGeometryUnavailable)
    )
    #expect(!overlay.isVisible)
    #expect(overlay.hideCallCount > hidesBeforeMissingPosition)

    await capture.emit(
      frame(
        sequenceNumber: 8,
        image: image,
        captureSurfaceGeometry: surface,
        captureScreenGeometry: movedScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 8 }
    #expect(model.slideCanvasOverlayMappingState == .mapped)
    #expect(overlay.isVisible)
    #expect(
      rect(
        overlay.renderedFrames.last,
        isApproximately: CGRect(x: 340, y: 580, width: 80, height: 60)
      )
    )

    await model.stopWindowCapture()
    #expect(model.slideCanvasOverlayMappingState == .unavailable)
    #expect(!overlay.isVisible)
  }

  @Test func explicitHideSuppressesProductionOverlayUntilANewCaptureStarts() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let eligibility = MutableCanvasProductionOverlayEligibilityProvider()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      productionOverlayEligibilityProvider: eligibility
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.renderCallCount == 1)

    model.hideOverlay()
    #expect(!overlay.isVisible)
    model.showOverlayDemo()
    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 6 }
    receiveConfirmedBoardProposal("Resilience means retaining function.", on: model)
    #expect(overlay.renderCallCount == 1)
    #expect(!overlay.isVisible)

    await model.stopWindowCapture()
    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.renderCallCount == 2)
    #expect(overlay.isVisible)
    await model.stopWindowCapture()
  }

  @Test func productionOverlayRechecksEligibilityButDeduplicatesPhysicalRendering() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let eligibility = MutableCanvasProductionOverlayEligibilityProvider()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      productionOverlayEligibilityProvider: eligibility
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.renderCallCount == 1)
    let eligibilityCallsBeforeRepeat = eligibility.callCount

    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 6 }
    #expect(eligibility.callCount > eligibilityCallsBeforeRepeat)
    #expect(overlay.renderCallCount == 1)

    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.movedScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 7 }
    #expect(overlay.renderCallCount == 2)

    model.digitalInkStyle = .handwritten
    await capture.emit(
      frame(
        sequenceNumber: 8,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.movedScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 8 }
    #expect(overlay.renderCallCount == 3)

    receiveConfirmedBoardProposal("Resilience means retaining function.", on: model)
    #expect(overlay.renderCallCount == 4)
    await model.stopWindowCapture()
  }

  @Test func proposedIntentRemainsInternalUntilRepeatedEvidenceConfirmsIt() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let eligibility = MutableCanvasProductionOverlayEligibilityProvider()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      productionOverlayEligibilityProvider: eligibility
    )

    try await establishAnalyzedProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    let eligibilityCallsBeforeProposal = eligibility.callCount
    let renderCallsBeforeProposal = overlay.renderCallCount
    let hideCallsBeforeProposal = overlay.hideCallCount
    let repeatedDefinition = "Sustainability means preserving options."

    model.receive(boardProposalDefinition(text: repeatedDefinition))

    #expect(model.boardScene.elements.isEmpty)
    #expect(eligibility.callCount == eligibilityCallsBeforeProposal)
    #expect(overlay.renderCallCount == renderCallsBeforeProposal)
    #expect(overlay.hideCallCount == hideCallsBeforeProposal)

    model.receive(boardProposalDefinition(text: repeatedDefinition))

    #expect(!model.boardScene.elements.isEmpty)
    #expect(eligibility.callCount == eligibilityCallsBeforeProposal + 1)
    #expect(overlay.renderCallCount == renderCallsBeforeProposal + 1)
    #expect(overlay.isVisible)

    await model.stopWindowCapture()
  }

  @Test func productionOverlayLeaseExpiresAndFocusEventsRequireANewEligibleFrame() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let scheduler = ManualCanvasProductionOverlayLeaseScheduler()
    let safetyEvents = ManualCanvasProductionOverlaySafetyEventProvider()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      productionOverlayLeaseScheduler: scheduler,
      productionOverlaySafetyEventProvider: safetyEvents
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.isVisible)
    #expect(scheduler.hasActiveAction)
    let expiredActionIndex = scheduler.scheduledActionCount - 1
    let rendersBeforeExpiry = overlay.renderCallCount

    scheduler.fireActive()
    #expect(!overlay.isVisible)
    receiveConfirmedBoardProposal("Resilience means retaining function.", on: model)
    #expect(!overlay.isVisible)
    #expect(overlay.renderCallCount == rendersBeforeExpiry)

    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { overlay.isVisible }
    #expect(overlay.renderCallCount == rendersBeforeExpiry + 1)

    scheduler.fireRetained(at: expiredActionIndex)
    #expect(overlay.isVisible)

    safetyEvents.emitUnsafeEvent()
    #expect(!overlay.isVisible)
    receiveConfirmedBoardProposal(
      "Adaptation means changing strategy under uncertainty.",
      on: model
    )
    #expect(!overlay.isVisible)

    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { overlay.isVisible }

    await model.stopWindowCapture()
    model.showOverlayDemo()
    #expect(overlay.isVisible)
    safetyEvents.emitUnsafeEvent()
    #expect(overlay.isVisible)
    model.hideOverlay()
  }

  @Test func visualContentChangeImmediatelyInvalidatesGroundingAndNeedsFreshFrameLease()
    async throws
  {
    let capture = ManualCanvasCapture()
    let analyzer = SecondAnalysisSuspendingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let scheduler = ManualCanvasProductionOverlayLeaseScheduler()
    let transcription = RetainingCanvasTranscriptionProvider()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      productionOverlayLeaseScheduler: scheduler,
      transcriptionProvider: transcription
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.isVisible)
    #expect(!model.boardScene.elements.isEmpty)
    await model.startTranscription()
    #expect(transcription.retainedObservationCount == 1)
    let stopCallsBeforeVisualChange = transcription.stopCallCount
    let staleObservation = TranscriptionObservation(
      segment: boardProposalDefinition(text: "Stale visual evidence must be rejected."),
      sourceMachTime: mach_absolute_time()
    )
    let oldLeaseActionIndex = scheduler.scheduledActionCount - 1
    let rendersBeforeChange = overlay.renderCallCount
    let changedImage = try #require(
      makeSolidImage(width: 200, height: 120, red: 0, green: 0, blue: 0)
    )

    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: changedImage,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 6 }
    #expect(!overlay.isVisible)
    #expect(model.boardScene.elements.isEmpty)
    #expect(model.latestSlideAnalysis == nil)
    #expect(overlay.renderCallCount == rendersBeforeChange)
    #expect(transcription.stopCallCount == stopCallsBeforeVisualChange)

    for sequenceNumber in 7...8 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: changedImage,
          captureSurfaceGeometry: geometry.surface,
          captureScreenGeometry: geometry.initialScreen
        )
      )
    }
    try await analyzer.waitForInvocationCount(2)
    #expect(model.slideAnalysisStatus == .analyzing)
    #expect(!overlay.isVisible)

    scheduler.fireRetained(at: oldLeaseActionIndex)
    #expect(!overlay.isVisible)
    await analyzer.succeedSecondAnalysis()
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(model.boardScene.elements.isEmpty)
    #expect(!overlay.isVisible)

    transcription.emitRetained(staleObservation, startIndex: 0)
    #expect(model.boardScene.elements.isEmpty)
    #expect(transcription.stopCallCount == stopCallsBeforeVisualChange)
    transcription.emitRetained(
      TranscriptionObservation(
        segment: boardProposalDefinition(text: "Sustainability means preserving options."),
        sourceMachTime: UInt64.max
      ),
      startIndex: 0
    )
    transcription.emitRetained(
      TranscriptionObservation(
        segment: boardProposalDefinition(text: "Sustainability means preserving options."),
        sourceMachTime: UInt64.max
      ),
      startIndex: 0
    )
    #expect(!model.boardScene.elements.isEmpty)
    #expect(!overlay.isVisible)
    #expect(overlay.renderCallCount == rendersBeforeChange)

    await capture.emit(
      frame(
        sequenceNumber: 9,
        image: changedImage,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { overlay.isVisible }
    #expect(overlay.renderCallCount == rendersBeforeChange + 1)
    await model.stopWindowCapture()
  }

  @Test func productionOverlayRequiresConfirmedSlideIdentity() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      slideIdentityProvider: UnavailablePowerPointSlideIdentityProvider()
    )

    await model.startWindowCapture()
    try await waitUntil { model.slideIdentitySampleCount == 1 }
    #expect(model.slideIdentityState == .unavailable)
    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(geometry.region))
    for sequenceNumber in 2...4 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: geometry.image,
          captureSurfaceGeometry: geometry.surface,
          captureScreenGeometry: geometry.initialScreen
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    receiveConfirmedBoardProposal("Sustainability means preserving options.", on: model)
    #expect(!model.boardScene.elements.isEmpty)
    #expect(overlay.renderCallCount == 0)
    #expect(!overlay.isVisible)
    await model.stopWindowCapture()
  }

  @Test func productionOverlayRequiresCurrentFrontmostExactWindowEligibility() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let eligibility = MutableCanvasProductionOverlayEligibilityProvider(
      state: .notFrontmost
    )
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      productionOverlayEligibilityProvider: eligibility
    )

    try await establishAnalyzedProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    receiveConfirmedBoardProposal("Sustainability means preserving options.", on: model)
    #expect(!model.boardScene.elements.isEmpty)
    #expect(overlay.renderCallCount == 0)
    #expect(!overlay.isVisible)

    eligibility.state = .eligible
    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 6 }
    #expect(overlay.renderCallCount == 1)
    #expect(overlay.isVisible)

    eligibility.state = .windowMissing
    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 7 }
    #expect(!overlay.isVisible)

    eligibility.state = .eligible
    await capture.emit(
      frame(
        sequenceNumber: 8,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 8 }
    #expect(overlay.renderCallCount == 2)
    #expect(overlay.isVisible)
    await model.stopWindowCapture()
  }

  @Test func unavailableCaptureContentHidesOverlayAndStaleSessionNoticeIsIgnored() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let transcription = RetainingCanvasTranscriptionProvider()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display],
      transcriptionProvider: transcription
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.isVisible)
    await model.startTranscription()
    #expect(transcription.retainedObservationCount == 1)
    await capture.emitContentUnavailable(sequenceNumber: 6)
    try await waitUntil { !overlay.isVisible }
    #expect(model.captureStatus == .capturing)
    #expect(model.slideCanvasStatus == .confirmed)
    #expect(model.latestStableFrame == nil)
    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.boardScene.elements.isEmpty)
    #expect(transcription.stopCallCount > 0)

    model.receive(boardProposalDefinition(text: "Stale evidence must not return."))
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    await drainMainActorQueue()
    #expect(!overlay.isVisible)
    #expect(model.capturedFrameCount == 5)

    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen,
        deliveryKind: .idleRepeat
      )
    )
    await drainMainActorQueue()
    #expect(!overlay.isVisible)
    #expect(model.latestStableFrame == nil)
    #expect(model.latestSlideAnalysis == nil)

    for sequenceNumber in 8...11 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: geometry.image,
          captureSurfaceGeometry: geometry.surface,
          captureScreenGeometry: geometry.initialScreen
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(!overlay.isVisible)
    transcription.emitRetained(
      TranscriptionObservation(
        segment: boardProposalDefinition(text: "Stale callback must be rejected."),
        sourceMachTime: UInt64.max
      ),
      startIndex: 0
    )
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 12,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 11 }

    await model.startTranscription()
    transcription.emitRetained(
      TranscriptionObservation(
        segment: boardProposalDefinition(text: "Resilience means retaining function."),
        sourceMachTime: UInt64.max
      ),
      startIndex: 1
    )
    transcription.emitRetained(
      TranscriptionObservation(
        segment: boardProposalDefinition(text: "Resilience means retaining function."),
        sourceMachTime: UInt64.max
      ),
      startIndex: 1
    )
    try await waitUntil { overlay.isVisible }
    #expect(overlay.renderCallCount == 2)

    await model.stopWindowCapture()
    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.renderCallCount == 3)
    await capture.emitRetainedContentUnavailable(
      sequenceNumber: 100,
      startIndex: 0
    )
    await drainMainActorQueue()
    #expect(overlay.isVisible)
    #expect(overlay.renderCallCount == 3)
    await model.stopWindowCapture()
  }

  @Test func terminalCaptureErrorClearsVisibleOverlayAndRejectsRetainedFrame() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display]
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(overlay.isVisible)

    await capture.emitError("terminal capture failure")
    try await waitUntil { model.captureStatus == .error("terminal capture failure") }
    #expect(!overlay.isVisible)
    #expect(model.slideCanvasStatus == .unavailable)
    #expect(model.boardScene.elements.isEmpty)

    await capture.emitRetainedFrame(
      frame(
        sequenceNumber: 100,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      ),
      startIndex: 0
    )
    await drainMainActorQueue()
    #expect(!overlay.isVisible)
    #expect(model.captureStatus == .error("terminal capture failure"))
  }

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

  @Test func hiddenDemoSceneCannotRenderIntoLaterProductionCanvas() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let overlay = RecordingCanvasOverlayController()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display]
    )

    model.showOverlayDemo()
    #expect(!model.boardScene.elements.isEmpty)
    model.hideOverlay()
    #expect(!overlay.isVisible)

    try await establishAnalyzedProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(model.boardScene.elements.isEmpty)
    #expect(overlay.renderCallCount == 0)
    #expect(!overlay.isVisible)
    await model.stopWindowCapture()
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

    for sequenceNumber in 2...4 {
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
    for sequenceNumber in 2...4 {
      await capture.emit(frame(sequenceNumber: UInt64(sequenceNumber), image: image))
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    receiveConfirmedBoardProposal("Sustainability means preserving options.", on: model)
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
    receiveConfirmedBoardProposal("Resilience means retaining function.", on: model)
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
    #expect(
      model.slideCanvasInvalidationReason
        == .newFrameSurfaceGeometryUnavailableOrMismatched
    )

    model.beginSlideCanvasSelection()
    #expect(model.slideCanvasStatus == .invalidated)
    #expect(!model.confirmSlideCanvasSelection(region))
    #expect(model.confirmedSlideCanvasRegion == nil)
    #expect(model.stableFrameCount == 0)
    #expect(await analyzer.invocationCount == 0)

    await capture.emit(frame(sequenceNumber: 2, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    #expect(
      model.slideCanvasInvalidationReason
        == .newFrameSurfaceGeometryUnavailableOrMismatched
    )

    await model.stopWindowCapture()
    #expect(model.slideCanvasInvalidationReason == nil)
  }

  @Test func idleRepeatWithoutCurrentGeometryRecordsDeliverySpecificInvalidation() async throws {
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
    #expect(model.slideCanvasInvalidationReason == nil)

    await capture.emit(
      frame(
        sequenceNumber: 2,
        image: image,
        captureSurfaceGeometry: nil,
        deliveryKind: .idleRepeat
      )
    )
    try await waitUntil { model.slideCanvasStatus == .invalidated }
    #expect(
      model.slideCanvasInvalidationReason
        == .idleRepeatSurfaceGeometryUnavailableOrMismatched
    )
    #expect(model.confirmedSlideCanvasRegion == nil)

    await capture.emit(frame(sequenceNumber: 3, image: image))
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    #expect(
      model.slideCanvasInvalidationReason
        == .idleRepeatSurfaceGeometryUnavailableOrMismatched
    )

    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(fullFrame))
    #expect(model.slideCanvasStatus == .confirmed)
    #expect(model.slideCanvasInvalidationReason == nil)

    await model.stopWindowCapture()
    #expect(model.slideCanvasInvalidationReason == nil)
  }

  @Test func metadataEmptyVerifiedIdleRepeatKeepsCanvasButHidesMappedOverlay()
    async throws
  {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let overlay = RecordingCanvasOverlayController()
    let geometry = try makeProductionOverlayTestGeometry()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      displays: [geometry.display]
    )

    try await establishVisibleProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    #expect(model.slideCanvasOverlayMappingState == .mapped)
    #expect(!model.boardScene.elements.isEmpty)
    #expect(overlay.isVisible)

    let lastNewFrame = frame(
      sequenceNumber: 5,
      image: geometry.image,
      captureSurfaceGeometry: geometry.surface,
      captureScreenGeometry: geometry.initialScreen
    )
    let hidesBeforeIdle = overlay.hideCallCount

    let repeatedFrame = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: lastNewFrame,
      sequenceNumber: 6,
      capturedAt: Date(),
      currentAttachments: [.status: SCFrameStatus.idle.rawValue]
    )
    await capture.emit(repeatedFrame)
    try await waitUntil { model.repeatedCapturedFrameCount == 1 }

    #expect(repeatedFrame.captureSurfaceGeometry == lastNewFrame.captureSurfaceGeometry)
    #expect(repeatedFrame.captureScreenGeometry == nil)
    #expect(model.slideCanvasStatus == .confirmed)
    #expect(model.slideCanvasInvalidationReason == nil)
    #expect(
      model.slideCanvasOverlayMappingState == .rejected(.screenGeometryUnavailable)
    )
    #expect(!model.boardScene.elements.isEmpty)
    #expect(!overlay.isVisible)
    #expect(overlay.hideCallCount > hidesBeforeIdle)

    await model.stopWindowCapture()
  }

  @Test func confirmedFramePayloadRejectionRecordsBoundedReason() async throws {
    let capture = ManualCanvasCapture()
    let analyzer = RecordingCanvasAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage(width: 80, height: 40))
    let fullFrame = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      )
    )
    let invalidFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: [128]
    )

    await model.startWindowCapture()
    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        captureSurfaceGeometry: captureGeometry(for: image),
        fingerprint: invalidFingerprint
      )
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()

    #expect(!model.confirmSlideCanvasSelection(fullFrame))
    #expect(model.slideCanvasStatus == .invalidated)
    #expect(model.slideCanvasInvalidationReason == .confirmedFrameRejected)
    #expect(model.confirmedSlideCanvasRegion == nil)

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
    #expect(
      model.slideCanvasInvalidationReason
        == .newFrameSurfaceGeometryUnavailableOrMismatched
    )
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
    analyzer: any SlideVisualAnalyzing,
    overlay: any OverlayWindowControlling = RecordingCanvasOverlayController(),
    displays: [DisplayCoordinateSnapshot] = [],
    productionOverlayEligibilityProvider: any ProductionOverlayEligibilityProviding =
      MutableCanvasProductionOverlayEligibilityProvider(),
    productionOverlayLeaseScheduler: any ProductionOverlayLeaseScheduling =
      ManualCanvasProductionOverlayLeaseScheduler(),
    productionOverlaySafetyEventProvider: any ProductionOverlaySafetyEventProviding =
      ManualCanvasProductionOverlaySafetyEventProvider(),
    transcriptionProvider: any TranscriptionProvider =
      RetainingCanvasTranscriptionProvider(),
    slideIdentityProvider: any PowerPointSlideIdentityProviding =
      IdentifiedCanvasSlideIdentityProvider()
  ) -> AppModel {
    let model = AppModel(
      permissionService: PermissionService(
        screenCaptureClient: ManualCanvasAuthorizedPermissionClient()
      ),
      windowCapture: capture,
      scanner: ManualCanvasWindowScanner(),
      transcriptionProvider: transcriptionProvider,
      slideIdentityProvider: slideIdentityProvider,
      slideVisionAnalyzer: analyzer,
      slideIdentityFrameTimeout: .seconds(3_600),
      overlayController: overlay,
      displayCoordinateSnapshotProvider: FixedCanvasDisplayProvider(
        snapshots: displays
      ),
      productionOverlayEligibilityProvider: productionOverlayEligibilityProvider,
      productionOverlayLeaseScheduler: productionOverlayLeaseScheduler,
      productionOverlayLeaseDuration: .seconds(1),
      productionOverlaySafetyEventProvider: productionOverlaySafetyEventProvider
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

  private func makeProductionOverlayTestGeometry() throws
    -> ProductionOverlayTestGeometry
  {
    let image = try #require(makeImage(width: 200, height: 120))
    let surface = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 10, y: 10, width: 80, height: 40),
        scaleFactor: 2,
        contentScale: 0.5,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let initialScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 100, y: 200, width: 160, height: 80)
      )
    )
    let movedScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 300, y: 250, width: 160, height: 80)
      )
    )
    let region = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let display = try #require(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
      )
    )
    return ProductionOverlayTestGeometry(
      image: image,
      surface: surface,
      initialScreen: initialScreen,
      movedScreen: movedScreen,
      region: region,
      display: display
    )
  }

  private func establishAnalyzedProductionOverlay(
    model: AppModel,
    capture: ManualCanvasCapture,
    geometry: ProductionOverlayTestGeometry
  ) async throws {
    await model.startWindowCapture()
    try await waitUntil { model.slideIdentityState == .identified }
    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }
    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(geometry.region))
    for sequenceNumber in 2...4 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: geometry.image,
          captureSurfaceGeometry: geometry.surface,
          captureScreenGeometry: geometry.initialScreen
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: geometry.image,
        captureSurfaceGeometry: geometry.surface,
        captureScreenGeometry: geometry.initialScreen
      )
    )
    try await waitUntil { model.capturedFrameCount == 5 }
  }

  private func establishVisibleProductionOverlay(
    model: AppModel,
    capture: ManualCanvasCapture,
    geometry: ProductionOverlayTestGeometry
  ) async throws {
    try await establishAnalyzedProductionOverlay(
      model: model,
      capture: capture,
      geometry: geometry
    )
    receiveConfirmedBoardProposal("Sustainability means preserving options.", on: model)
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
    captureSurfaceGeometry: CaptureSurfaceGeometry?,
    captureScreenGeometry: CaptureScreenGeometry? = nil,
    deliveryKind: CapturedFrameDeliveryKind = .new,
    contentCell: RGBContentCell = RGBContentCell(red: 255, green: 255, blue: 255),
    fingerprint: FrameFingerprint? = nil
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(timeIntervalSince1970: TimeInterval(sequenceNumber)),
      displayTime: UInt64.max,
      deliveryKind: deliveryKind,
      captureSurfaceGeometry: captureSurfaceGeometry,
      captureScreenGeometry: captureScreenGeometry,
      image: image,
      fingerprint: fingerprint
        ?? FrameFingerprint(
          sampleColumns: 32,
          sampleRows: 18,
          luminance: Array(repeating: 128, count: 32 * 18)
        ),
      contentFingerprint: ContentFingerprint(
        sampleColumns: 160,
        sampleRows: 90,
        cells: Array(
          repeating: contentCell,
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

  private func makeSolidImage(
    width: Int,
    height: Int,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) -> CGImage? {
    let pixel = [red, green, blue, UInt8.max]
    let data = Data(Array(repeating: pixel, count: width * height).flatMap { $0 })
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
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

  private func rect(
    _ actual: CGRect?,
    isApproximately expected: CGRect,
    tolerance: CGFloat = 1e-9
  ) -> Bool {
    guard let actual else { return false }
    return abs(actual.origin.x - expected.origin.x) <= tolerance
      && abs(actual.origin.y - expected.origin.y) <= tolerance
      && abs(actual.size.width - expected.size.width) <= tolerance
      && abs(actual.size.height - expected.size.height) <= tolerance
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

  private func receiveConfirmedBoardProposal(_ text: String, on model: AppModel) {
    model.receive(boardProposalDefinition(text: text))
    model.receive(boardProposalDefinition(text: text))
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

private struct ProductionOverlayTestGeometry {
  let image: CGImage
  let surface: CaptureSurfaceGeometry
  let initialScreen: CaptureScreenGeometry
  let movedScreen: CaptureScreenGeometry
  let region: SlideCanvasRegion
  let display: DisplayCoordinateSnapshot
}

@MainActor
private final class RecordingCanvasOverlayController: OverlayWindowControlling {
  private(set) var showCallCount = 0
  private(set) var renderCallCount = 0
  private(set) var hideCallCount = 0
  private(set) var isVisible = false
  private(set) var renderedFrames: [CGRect] = []

  func showDemo(scene: BoardScene, style: DigitalInkStyle, on screen: NSScreen?) {
    showCallCount += 1
    isVisible = true
  }

  func render(scene: BoardScene, style: DigitalInkStyle, in frame: CGRect) {
    renderCallCount += 1
    renderedFrames.append(frame)
    isVisible = true
  }

  func hide() {
    hideCallCount += 1
    isVisible = false
  }
}

@MainActor
private final class MutableCanvasProductionOverlayEligibilityProvider:
  ProductionOverlayEligibilityProviding
{
  enum State: Equatable {
    case eligible
    case notFrontmost
    case windowMissing
  }

  var state: State
  private(set) var callCount = 0

  init(state: State = .eligible) {
    self.state = state
  }

  func allowsProductionOverlay(
    for identity: PowerPointWindowIdentity,
    screenGeometry: CaptureScreenGeometry
  ) -> Bool {
    callCount += 1
    return state == .eligible
  }
}

@MainActor
private final class ManualCanvasProductionOverlayLeaseScheduler:
  ProductionOverlayLeaseScheduling
{
  private var actions: [@MainActor @Sendable () -> Void] = []
  private var activeActionIndex: Int?

  var scheduledActionCount: Int { actions.count }
  var hasActiveAction: Bool { activeActionIndex != nil }

  func schedule(
    after duration: Duration,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    activeActionIndex = actions.count
    actions.append(action)
  }

  func cancel() {
    activeActionIndex = nil
  }

  func fireActive() {
    guard let activeActionIndex else { return }
    self.activeActionIndex = nil
    actions[activeActionIndex]()
  }

  func fireRetained(at index: Int) {
    guard actions.indices.contains(index) else { return }
    actions[index]()
  }
}

@MainActor
private final class ManualCanvasProductionOverlaySafetyEventProvider:
  ProductionOverlaySafetyEventProviding
{
  private var handler: ProductionOverlayUnsafeEventHandler?

  func start(onUnsafeEvent: @escaping ProductionOverlayUnsafeEventHandler) {
    handler = onUnsafeEvent
  }

  func stop() {
    handler = nil
  }

  func emitUnsafeEvent() {
    handler?()
  }
}

private actor IdentifiedCanvasSlideIdentityProvider: PowerPointSlideIdentityProviding {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async {
    guard
      let sample = SlideIdentitySample(
        presentationSessionToken: "synthetic-canvas-session-\(operationID.rawValue)",
        slideID: 1,
        slideIndex: 1
      )
    else {
      return
    }
    onObservation(
      PowerPointSlideIdentityObservation(
        sequenceNumber: 1,
        observedAt: Date(),
        targetIdentity: identity,
        signal: .available(sample)
      )
    )
    onObservation(
      PowerPointSlideIdentityObservation(
        sequenceNumber: 2,
        observedAt: Date(),
        targetIdentity: identity,
        signal: .available(sample)
      )
    )
  }

  func stop(operationID: CaptureOperationID) async {}
}

@MainActor
private final class RetainingCanvasTranscriptionProvider: TranscriptionProvider {
  private var observationHandlers: [@MainActor (TranscriptionObservation) -> Void] = []
  private(set) var stopCallCount = 0

  var retainedObservationCount: Int {
    observationHandlers.count
  }

  func start(
    language: LanguageTag,
    onObservation: @escaping @MainActor (TranscriptionObservation) -> Void
  ) async throws {
    observationHandlers.append(onObservation)
  }

  func stop() {
    stopCallCount += 1
  }

  func emitRetained(_ observation: TranscriptionObservation, startIndex: Int) {
    guard observationHandlers.indices.contains(startIndex) else { return }
    observationHandlers[startIndex](observation)
  }
}

@MainActor
private struct FixedCanvasDisplayProvider: DisplayCoordinateSnapshotProviding {
  let snapshots: [DisplayCoordinateSnapshot]

  func currentSnapshots() -> [DisplayCoordinateSnapshot] {
    snapshots
  }
}

private enum AppSlideCanvasIntegrationTestError: Error {
  case timedOut
}

private actor ManualCanvasCapture: PowerPointWindowCapturing {
  private var frameHandler: CaptureFrameHandler?
  private var contentUnavailableHandler: CaptureContentUnavailableHandler?
  private var errorHandler: CaptureErrorHandler?
  private var retainedContentUnavailableHandlers: [CaptureContentUnavailableHandler] = []
  private var retainedFrameHandlers: [CaptureFrameHandler] = []
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
    contentUnavailableHandler = nil
    errorHandler = onError
    retainedFrameHandlers.append(onFrame)
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    frameHandler = onFrame
    contentUnavailableHandler = onContentUnavailable
    errorHandler = onError
    retainedFrameHandlers.append(onFrame)
    retainedContentUnavailableHandlers.append(onContentUnavailable)
  }

  func stop(operationID: CaptureOperationID) async {
    frameHandler = nil
    contentUnavailableHandler = nil
    errorHandler = nil
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

  func emitContentUnavailable(sequenceNumber: UInt64) {
    contentUnavailableHandler?(sequenceNumber)
  }

  func emitRetainedContentUnavailable(sequenceNumber: UInt64, startIndex: Int) {
    guard retainedContentUnavailableHandlers.indices.contains(startIndex) else { return }
    retainedContentUnavailableHandlers[startIndex](sequenceNumber)
  }

  func emitRetainedFrame(_ frame: CapturedPowerPointFrame, startIndex: Int) {
    guard retainedFrameHandlers.indices.contains(startIndex) else { return }
    retainedFrameHandlers[startIndex](frame)
  }

  func emitError(_ message: String) {
    errorHandler?(message)
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

private actor SecondAnalysisSuspendingCanvasAnalyzer: SlideVisualAnalyzing {
  private let occupiedRegions: [NormalizedRect]
  private var invocationCount = 0
  private var secondContinuation: CheckedContinuation<SlideVisualAnalysis, any Error>?

  init(occupiedRegions: [NormalizedRect]) {
    self.occupiedRegions = occupiedRegions
  }

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    invocationCount += 1
    guard invocationCount > 1 else {
      return SlideVisualAnalysis(
        title: "initial grounded analysis",
        occupiedRegions: occupiedRegions
      )
    }
    return try await withCheckedThrowingContinuation { continuation in
      secondContinuation = continuation
    }
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if invocationCount >= expectedCount { return }
      await Task.yield()
    }
    throw AppSlideCanvasIntegrationTestError.timedOut
  }

  func succeedSecondAnalysis() {
    secondContinuation?.resume(
      returning: SlideVisualAnalysis(
        title: "fresh grounded analysis",
        occupiedRegions: occupiedRegions
      )
    )
    secondContinuation = nil
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
