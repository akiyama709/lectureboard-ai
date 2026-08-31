import AVFoundation
import AppKit
import Combine
import CoreGraphics
import Darwin
import LectureBoardCore
import Speech

protocol PowerPointWindowScanning: Sendable {
  func scan() async throws -> [PowerPointWindowDescriptor]
}

extension PowerPointWindowScanner: PowerPointWindowScanning {}

enum SlideIdentityTranscriptBoundary {
  static func accepts(sourceMachTime: UInt64, after minimumMachTime: UInt64?) -> Bool {
    guard sourceMachTime > 0 else { return false }
    guard let minimumMachTime else { return true }
    return minimumMachTime > 0 && sourceMachTime > minimumMachTime
  }
}

protocol SlideIdentityFrameTimeoutWaiting: Sendable {
  func wait(for duration: Duration) async
}

struct TaskSlideIdentityFrameTimeoutWaiter: SlideIdentityFrameTimeoutWaiting {
  func wait(for duration: Duration) async {
    try? await Task.sleep(for: duration)
  }
}

private struct BoardCandidateContext {
  var transcriptSegments: [TranscriptSegment] = []
  var intents: [BoardIntent] = []

  mutating func reset() {
    transcriptSegments.removeAll(keepingCapacity: true)
    intents.removeAll(keepingCapacity: true)
  }
}

private struct RenderedProductionOverlayState: Equatable {
  let captureOperationID: CaptureOperationID
  let windowID: CGWindowID
  let scene: BoardScene
  let style: DigitalInkStyle
  let appKitTargetFrame: CGRect
}

@MainActor
final class AppModel: ObservableObject {
  enum Status: Equatable {
    case ready
    case scanning
    case listening
    case overlayVisible
    case error(String)
  }

  enum CaptureStatus: Equatable {
    case stopped
    case starting
    case capturing
    case error(String)
  }

  enum SlideAnalysisStatus: Equatable {
    case idle
    case analyzing
    case ready
    case error(String)
  }

  @Published var status: Status = .ready
  @Published var powerPointWindows: [PowerPointWindowDescriptor] = []
  @Published var selectedPowerPointWindowID: CGWindowID?
  @Published var selectedLanguage: LanguageTag = .japanese
  @Published var liveTranscript = ""
  @Published var boardScene = BoardScene(slideNumber: 1)
  @Published var digitalInkStyle = DigitalInkStyle.clean
  @Published private(set) var captureStatus: CaptureStatus = .stopped
  @Published private(set) var capturedFrameCount = 0
  @Published private(set) var newCapturedFrameCount = 0
  @Published private(set) var repeatedCapturedFrameCount = 0
  @Published private(set) var lastNewFrameAt: Date?
  @Published private(set) var latestDifferenceFromStableFrame: Double?
  @Published private(set) var stableFrameCount = 0
  /// Reserved for transitions confirmed by an independent slide-identity signal.
  @Published private(set) var slideChangeCount = 0
  @Published private(set) var slideIdentityState = SlideIdentityState.unavailable
  @Published private(set) var slideIdentityFrameSyncState =
    SlideIdentityFrameSyncState.notRequired
  @Published private(set) var slideIdentitySampleCount = 0
  @Published private(set) var slideIdentityContinuityBreakCount = 0
  @Published private(set) var contentRevisionCount = 0
  @Published private(set) var slideCanvasStatus = SlideCanvasStatus.unavailable
  @Published private(set) var slideCanvasOverlayMappingState =
    SlideCanvasOverlayMappingState.unavailable
  @Published private(set) var slideCanvasInvalidationReason: SlideCanvasInvalidationReason?
  @Published private(set) var latestCapturedWindowFrame: CGImage?
  @Published private(set) var slideCanvasCalibrationFrame: CGImage?
  @Published private(set) var confirmedSlideCanvasRegion: SlideCanvasRegion?
  @Published private(set) var slideCanvasCalibrationRevision = 0
  @Published private(set) var latestStableFrame: CGImage?
  @Published private(set) var slideAnalysisStatus: SlideAnalysisStatus = .idle
  @Published private(set) var latestSlideAnalysis: SlideVisualAnalysis?
  @Published private var inFlightCaptureStopCount = 0

  let permissionService: PermissionService
  private let scanner: any PowerPointWindowScanning
  private let overlayController: any OverlayWindowControlling
  private let displayCoordinateSnapshotProvider: any DisplayCoordinateSnapshotProviding
  private let productionOverlayEligibilityProvider: any ProductionOverlayEligibilityProviding
  private let productionOverlayLeaseScheduler: any ProductionOverlayLeaseScheduling
  private let productionOverlayLeaseDuration: Duration
  private let productionOverlaySafetyEventProvider: any ProductionOverlaySafetyEventProviding
  private let speechProvider: any TranscriptionProvider
  private let windowCapture: any PowerPointWindowCapturing
  private let slideIdentityProvider: any PowerPointSlideIdentityProviding
  private let slideVisionAnalyzer: any SlideVisualAnalyzing
  private let slideCanvasConfirmationMode: SlideCanvasConfirmationMode
  private let slideIdentityFrameTimeout: Duration
  private let slideIdentityFrameTimeoutWaiter: any SlideIdentityFrameTimeoutWaiting
  private let boardEngine = ContextualBoardEngine()
  private let sceneComposer = BoardSceneComposer()
  private var stableFrameDetector = StableFrameDetector()
  private var stableContentChangeDetector = StableContentChangeDetector()
  private var captureDeliveryMetrics = CaptureDeliveryMetrics()
  private var refreshGeneration: UInt64 = 0
  private var nextCaptureOperationRawValue: UInt64 = 0
  private var activeCaptureSessionID: CaptureOperationID?
  private var activeCaptureWindowID: CGWindowID?
  private var activeCaptureIdentity: PowerPointWindowIdentity?
  private var lastAcceptedCaptureSequenceNumber: UInt64?
  private var captureContentRequiresNewFrame = false
  private var slideIdentityTracker = SlideIdentityTracker()
  private var slideIdentityFrameGate = PostIdentityBoundaryFrameGate()
  private var lastAcceptedSlideIdentitySequenceNumber: UInt64?
  private var slideIdentityGeneration = 0
  private var slideIdentityQuarantineActive = false
  private var latestSlideIdentityBoundaryMachTime: UInt64?
  private var latestSlideIdentityFrameSynchronizationMachTime: UInt64?
  private var latestVisualFreshnessBoundaryMachTime: UInt64?
  private var slideIdentityFrameTimeoutTask: Task<Void, Never>?
  private var analysisGeneration = 0
  private var slideCanvasGeneration = 0
  private var confirmedSlideCanvasSelection: ConfirmedSlideCanvasSelection?
  private var slideCanvasCalibrationSource: SlideCanvasCalibrationSource?
  private var latestEligibleWindowFrame: CapturedPowerPointFrame?
  private var slideAnalysisTask: Task<Void, Never>?
  private var slideAnalysisNeedsRefresh = true
  private var latestCompletedAnalysisGeneration: Int?
  private var boardCandidateContext = BoardCandidateContext()
  private var boardSceneAnalysisGeneration: Int?
  private var transcriptionOperationGate = TranscriptionOperationGate()
  private var overlayDemoSceneIsLoaded = false
  private var productionOverlayIsManuallySuppressed = false
  private var latestOverlayPlacement: SlideCanvasOverlayPlacement?
  private var renderedProductionOverlayState: RenderedProductionOverlayState?
  private var productionOverlayLeaseGeneration: UInt64 = 0
  private var productionOverlayLeaseIsValid = false

  init(
    permissionService: PermissionService = PermissionService(),
    windowCapture: any PowerPointWindowCapturing = PowerPointWindowCapture(),
    scanner: any PowerPointWindowScanning = PowerPointWindowScanner(),
    transcriptionProvider: any TranscriptionProvider = AppleSpeechRecognizerProvider(),
    slideIdentityProvider: any PowerPointSlideIdentityProviding =
      UnavailablePowerPointSlideIdentityProvider(),
    slideVisionAnalyzer: any SlideVisualAnalyzing = SlideVisionAnalyzer(),
    slideCanvasConfirmationMode: SlideCanvasConfirmationMode = .userConfirmed,
    slideIdentityFrameTimeout: Duration = .seconds(2),
    slideIdentityFrameTimeoutWaiter: any SlideIdentityFrameTimeoutWaiting =
      TaskSlideIdentityFrameTimeoutWaiter(),
    overlayController: any OverlayWindowControlling = OverlayWindowController(),
    displayCoordinateSnapshotProvider: any DisplayCoordinateSnapshotProviding =
      SystemDisplayCoordinateSnapshotProvider(),
    productionOverlayEligibilityProvider: any ProductionOverlayEligibilityProviding =
      SystemProductionOverlayEligibilityProvider(),
    productionOverlayLeaseScheduler: any ProductionOverlayLeaseScheduling =
      TaskProductionOverlayLeaseScheduler(),
    productionOverlayLeaseDuration: Duration = .seconds(1),
    productionOverlaySafetyEventProvider: any ProductionOverlaySafetyEventProviding =
      SystemProductionOverlaySafetyEventProvider()
  ) {
    self.permissionService = permissionService
    self.windowCapture = windowCapture
    self.scanner = scanner
    self.speechProvider = transcriptionProvider
    self.slideIdentityProvider = slideIdentityProvider
    self.slideVisionAnalyzer = slideVisionAnalyzer
    self.slideCanvasConfirmationMode = slideCanvasConfirmationMode
    self.slideIdentityFrameTimeout = max(slideIdentityFrameTimeout, .zero)
    self.slideIdentityFrameTimeoutWaiter = slideIdentityFrameTimeoutWaiter
    self.overlayController = overlayController
    self.displayCoordinateSnapshotProvider = displayCoordinateSnapshotProvider
    self.productionOverlayEligibilityProvider = productionOverlayEligibilityProvider
    self.productionOverlayLeaseScheduler = productionOverlayLeaseScheduler
    self.productionOverlayLeaseDuration = max(productionOverlayLeaseDuration, .zero)
    self.productionOverlaySafetyEventProvider = productionOverlaySafetyEventProvider
    productionOverlaySafetyEventProvider.start { [weak self] in
      self?.handleProductionOverlayUnsafeEvent()
    }
  }

  deinit {
    let leaseScheduler = productionOverlayLeaseScheduler
    let safetyEventProvider = productionOverlaySafetyEventProvider
    Task { @MainActor in
      leaseScheduler.cancel()
      safetyEventProvider.stop()
    }
  }

  var selectedWindow: PowerPointWindowDescriptor? {
    guard let selectedPowerPointWindowID else { return nil }
    return PowerPointWindowIdentityResolver.uniqueDescriptor(
      windowID: selectedPowerPointWindowID,
      in: powerPointWindows
    )
  }

  var slideCanvasPreviewFrame: CGImage? {
    slideCanvasCalibrationFrame ?? latestCapturedWindowFrame
  }

  var canShowOverlayDemo: Bool {
    captureStatus == .stopped && inFlightCaptureStopCount == 0
  }

  func beginSlideCanvasSelection() {
    guard
      let activeCaptureSessionID,
      let activeCaptureWindowID,
      let latestEligibleWindowFrame,
      latestEligibleWindowFrame.windowID == activeCaptureWindowID,
      let captureSurfaceGeometry = latestEligibleWindowFrame.captureSurfaceGeometry,
      let source = SlideCanvasCalibrationSource(
        captureOperationID: activeCaptureSessionID,
        windowID: activeCaptureWindowID,
        sequenceNumber: latestEligibleWindowFrame.sequenceNumber,
        captureSurfaceGeometry: captureSurfaceGeometry,
        image: latestEligibleWindowFrame.image
      )
    else {
      return
    }

    invalidateTranscriptionContext()
    clearConfirmedSlideCanvas(resetVisualPipeline: true)
    slideCanvasCalibrationSource = source
    slideCanvasCalibrationFrame = source.image
    slideCanvasCalibrationRevision &+= 1
    slideCanvasStatus = .selecting
  }

  @discardableResult
  func confirmSlideCanvasSelection(_ region: SlideCanvasRegion) -> Bool {
    guard
      slideCanvasStatus == .selecting,
      let activeCaptureSessionID,
      let activeCaptureWindowID,
      let source = slideCanvasCalibrationSource,
      source.captureOperationID == activeCaptureSessionID,
      source.windowID == activeCaptureWindowID,
      SlideCanvasSelectionPolicy.accepts(
        region,
        sourcePixelWidth: source.pixelWidth,
        sourcePixelHeight: source.pixelHeight
      ),
      let selection = ConfirmedSlideCanvasSelection(
        captureOperationID: activeCaptureSessionID,
        windowID: activeCaptureWindowID,
        captureSurfaceGeometry: source.captureSurfaceGeometry,
        region: region
      )
    else {
      return false
    }

    invalidateTranscriptionContext()
    slideCanvasGeneration &+= 1
    confirmedSlideCanvasSelection = selection
    confirmedSlideCanvasRegion = region
    slideCanvasCalibrationSource = nil
    slideCanvasCalibrationFrame = nil
    slideCanvasCalibrationRevision &+= 1
    slideCanvasStatus = .confirmed
    slideCanvasInvalidationReason = nil
    resetCanvasVisualPipeline()

    if let latestEligibleWindowFrame {
      refreshOverlayPlacement(
        using: latestEligibleWindowFrame,
        sessionID: activeCaptureSessionID
      )
      switch SlideCanvasFramePreparer.evaluate(
        latestEligibleWindowFrame,
        captureOperationID: activeCaptureSessionID,
        selection: selection
      ) {
      case .rejected(let reason):
        invalidateConfirmedSlideCanvas(reason: reason)
        return false
      case .prepared(let canvasFrame):
        processVisualFrame(canvasFrame, sessionID: activeCaptureSessionID)
      }
    }
    return true
  }

  func cancelSlideCanvasSelection() {
    guard slideCanvasStatus == .selecting else { return }
    invalidateTranscriptionContext()
    slideCanvasCalibrationSource = nil
    slideCanvasCalibrationFrame = nil
    slideCanvasCalibrationRevision &+= 1
    slideCanvasStatus = latestCapturedWindowFrame == nil ? .waitingForFrame : .needsConfirmation
  }

  @discardableResult
  func requestScreenCapturePermission() -> Bool {
    permissionService.requestScreenCaptureAccess()
  }

  func refreshPowerPointWindows() async {
    guard
      CaptureControlPolicy.canRefreshPowerPointWindows(
        screenCaptureAccessGranted: permissionService.screenCaptureAccessGranted
      )
    else {
      return
    }

    status = .scanning
    precondition(refreshGeneration < UInt64.max, "Window refresh generation exhausted.")
    refreshGeneration += 1
    let generation = refreshGeneration
    do {
      let windows = try await scanner.scan()
      guard generation == refreshGeneration else { return }
      let previousSelection = selectedPowerPointWindowID
      powerPointWindows = windows

      if let previousSelection,
        let refreshedSelection = PowerPointWindowIdentityResolver.uniqueDescriptor(
          windowID: previousSelection,
          in: windows
        ),
        activeCaptureIdentity == nil || refreshedSelection.identity == activeCaptureIdentity
      {
        selectedPowerPointWindowID = previousSelection
      } else {
        let stopOperationID = await stopWindowCaptureForOperation()
        guard generation == refreshGeneration else { return }
        guard isLatestCaptureOperation(stopOperationID) else {
          status = .ready
          return
        }
        selectedPowerPointWindowID =
          windows.first { window in
            PowerPointWindowIdentityResolver.uniqueDescriptor(
              windowID: window.id,
              in: windows
            ) != nil
          }?.id
      }
      status = .ready
    } catch {
      guard generation == refreshGeneration else { return }
      status = .error(error.localizedDescription)
    }
  }

  func startWindowCapture() async {
    guard let selectedWindow, let selectedIdentity = selectedWindow.identity else {
      captureStatus = .error(
        NSLocalizedString("error.captureWindowUnavailable", comment: "")
      )
      return
    }
    let selectedPowerPointWindowID = selectedIdentity.windowID
    guard
      CaptureControlPolicy.canStart(
        screenCaptureAccessGranted: permissionService.screenCaptureAccessGranted,
        hasSelectedWindow: true,
        captureStatus: captureStatus
      )
    else {
      return
    }

    let operationID = nextCaptureOperationID()
    productionOverlayIsManuallySuppressed = false
    activeCaptureSessionID = operationID
    activeCaptureWindowID = selectedPowerPointWindowID
    activeCaptureIdentity = selectedIdentity
    captureStatus = .starting
    capturedFrameCount = 0
    captureDeliveryMetrics.reset()
    newCapturedFrameCount = 0
    repeatedCapturedFrameCount = 0
    lastNewFrameAt = nil
    latestDifferenceFromStableFrame = nil
    stableFrameCount = 0
    slideChangeCount = 0
    contentRevisionCount = 0
    latestStableFrame = nil
    prepareSlideCanvasForNewCapture()
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    lastAcceptedCaptureSequenceNumber = nil
    captureContentRequiresNewFrame = false
    latestVisualFreshnessBoundaryMachTime = nil
    prepareSlideIdentityForNewCapture()
    resetSlideAnalysis()

    do {
      try await windowCapture.start(
        operationID: operationID,
        identity: selectedIdentity,
        onFrame: { [weak self] frame in
          Task { @MainActor [weak self] in
            self?.receive(frame, sessionID: operationID)
          }
        },
        onContentUnavailable: { [weak self] sequenceNumber in
          Task { @MainActor [weak self] in
            self?.receiveCaptureContentUnavailable(
              sequenceNumber: sequenceNumber,
              sessionID: operationID
            )
          }
        },
        onError: { [weak self] message in
          Task { @MainActor [weak self] in
            await self?.handleCaptureError(message, sessionID: operationID)
          }
        }
      )
      guard activeCaptureSessionID == operationID else { return }
      guard selectedIdentity == self.selectedWindow?.identity else {
        let stopOperationID = nextCaptureOperationID()
        activeCaptureSessionID = nil
        activeCaptureWindowID = nil
        activeCaptureIdentity = nil
        invalidateSlideIdentityAfterCaptureEnd(state: .unavailable)
        stableFrameDetector.reset()
        stableContentChangeDetector.reset()
        lastAcceptedCaptureSequenceNumber = nil
        invalidateSlideCanvasAfterCaptureEnd()
        resetSlideAnalysis()
        captureStatus = .stopped
        await stopCaptureProviders(operationID: stopOperationID)
        return
      }
      captureStatus = .capturing
      await slideIdentityProvider.start(
        operationID: operationID,
        identity: selectedIdentity,
        onObservation: { [weak self] observation in
          Task { @MainActor [weak self] in
            self?.receive(observation, sessionID: operationID)
          }
        }
      )
    } catch {
      guard activeCaptureSessionID == operationID else { return }
      let failedIdentityState = slideIdentityStateAfterCaptureFailure
      activeCaptureSessionID = nil
      activeCaptureWindowID = nil
      activeCaptureIdentity = nil
      invalidateSlideIdentityAfterCaptureEnd(state: failedIdentityState)
      captureStatus = .error(error.localizedDescription)
      stableFrameDetector.reset()
      stableContentChangeDetector.reset()
      lastAcceptedCaptureSequenceNumber = nil
      invalidateSlideCanvasAfterCaptureEnd()
      resetSlideAnalysis()
      let stopOperationID = nextCaptureOperationID()
      await stopCaptureProviders(operationID: stopOperationID)
    }
  }

  func stopWindowCapture() async {
    _ = await stopWindowCaptureForOperation()
  }

  func activeCaptureSessionID(for windowID: CGWindowID?) -> CaptureOperationID? {
    guard windowID == activeCaptureWindowID else { return nil }
    return activeCaptureSessionID
  }

  func stopWindowCapture(ifCurrentSessionID sessionID: CaptureOperationID) async {
    guard activeCaptureSessionID == sessionID else { return }
    _ = await stopWindowCaptureForOperation()
  }

  private func stopWindowCaptureForOperation() async -> CaptureOperationID {
    let operationID = nextCaptureOperationID()
    activeCaptureSessionID = nil
    activeCaptureWindowID = nil
    activeCaptureIdentity = nil
    invalidateSlideIdentityAfterCaptureEnd(state: .unavailable)
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    lastAcceptedCaptureSequenceNumber = nil
    captureContentRequiresNewFrame = false
    invalidateSlideCanvasAfterCaptureEnd()
    resetSlideAnalysis()
    captureStatus = .stopped
    await stopCaptureProviders(operationID: operationID)
    return operationID
  }

  func showOverlayDemo() {
    guard canShowOverlayDemo else { return }
    productionOverlayIsManuallySuppressed = false
    invalidateProductionOverlayLease(hidePanel: false)
    renderedProductionOverlayState = nil
    boardScene = DemoBoardSceneFactory.make(language: selectedLanguage)
    boardSceneAnalysisGeneration = nil
    overlayController.showDemo(scene: boardScene, style: digitalInkStyle, on: NSScreen.main)
    overlayDemoSceneIsLoaded = true
    status = .overlayVisible
  }

  func hideOverlay() {
    productionOverlayIsManuallySuppressed = true
    invalidateProductionOverlayLease()
    status = .ready
  }

  func startTranscription() async {
    invalidateTranscriptionContext()
    let operationID = transcriptionOperationGate.begin()
    liveTranscript = ""
    do {
      try await speechProvider.start(language: selectedLanguage) { [weak self] observation in
        guard let self else { return }
        self.receive(observation, transcriptionOperationID: operationID)
      }
      guard transcriptionOperationGate.accepts(operationID) else {
        if !transcriptionOperationGate.hasActiveOperation {
          speechProvider.stop()
        }
        return
      }
      status = .listening
    } catch {
      guard transcriptionOperationGate.invalidate(ifCurrent: operationID) else { return }
      speechProvider.stop()
      liveTranscript = ""
      status = .error(error.localizedDescription)
    }
  }

  func stopTranscription() {
    invalidateTranscriptionContext(forceReadyStatus: true)
  }

  func receive(_ segment: TranscriptSegment) {
    receive(
      TranscriptionObservation(
        segment: segment,
        sourceMachTime: mach_absolute_time()
      )
    )
  }

  func receive(_ observation: TranscriptionObservation) {
    receiveAcceptedTranscriptionObservation(observation)
  }

  private func receive(
    _ observation: TranscriptionObservation,
    transcriptionOperationID: TranscriptionOperationID
  ) {
    guard transcriptionOperationGate.accepts(transcriptionOperationID) else { return }
    receiveAcceptedTranscriptionObservation(observation)
  }

  private func receiveAcceptedTranscriptionObservation(
    _ observation: TranscriptionObservation
  ) {
    let segment = observation.segment
    liveTranscript = segment.text
    guard segment.isFinal else { return }
    guard
      slideCanvasStatus == .confirmed,
      slideAnalysisStatus == .ready,
      !slideAnalysisNeedsRefresh,
      latestCompletedAnalysisGeneration == analysisGeneration
    else { return }
    guard !isSlideIdentityQuarantined, !slideIdentityFrameGate.requiresFreshFrame else {
      return
    }
    guard
      SlideIdentityTranscriptBoundary.accepts(
        sourceMachTime: observation.sourceMachTime,
        after: latestSlideIdentityBoundaryMachTime
      ),
      SlideIdentityTranscriptBoundary.accepts(
        sourceMachTime: observation.sourceMachTime,
        after: latestSlideIdentityFrameSynchronizationMachTime
      ),
      SlideIdentityTranscriptBoundary.accepts(
        sourceMachTime: observation.sourceMachTime,
        after: latestVisualFreshnessBoundaryMachTime
      )
    else { return }

    guard
      let slideAnalysis = latestSlideAnalysis,
      !slideAnalysis.occupiedRegions.isEmpty
    else {
      return
    }

    boardCandidateContext.transcriptSegments.append(segment)
    let fallbackTitle =
      selectedLanguage.rawValue.hasPrefix("ja") ? "現在のスライド" : "Current slide"
    let analysisTitle = slideAnalysis.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = analysisTitle.isEmpty ? fallbackTitle : analysisTitle
    let slide = SlideContext(
      slideNumber: boardScene.slideNumber,
      title: title,
      textBlocks: slideAnalysis.textBlocks,
      speakerNotes: "",
      occupiedRegions: slideAnalysis.occupiedRegions,
      dwellTime: 40,
      languages: [selectedLanguage]
    )

    let proposals = boardEngine.propose(
      slide: slide,
      recentSegments: Array(boardCandidateContext.transcriptSegments.suffix(8)),
      existingIntents: boardCandidateContext.intents
    )
    guard !proposals.isEmpty else { return }

    boardCandidateContext.intents.append(contentsOf: proposals)
    boardScene = sceneComposer.append(
      intents: proposals,
      to: boardScene,
      slideOccupied: slide.occupiedRegions
    )
    boardSceneAnalysisGeneration = analysisGeneration
    renderAlignedOverlayIfPossible()
  }

  private func receive(_ frame: CapturedPowerPointFrame, sessionID: CaptureOperationID) {
    guard sessionID == activeCaptureSessionID,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    if let lastAcceptedCaptureSequenceNumber,
      frame.sequenceNumber <= lastAcceptedCaptureSequenceNumber
    {
      return
    }
    lastAcceptedCaptureSequenceNumber = frame.sequenceNumber
    captureDeliveryMetrics.record(frame.deliveryKind, capturedAt: frame.capturedAt)
    newCapturedFrameCount = captureDeliveryMetrics.newFrameCount
    repeatedCapturedFrameCount = captureDeliveryMetrics.repeatedFrameCount
    capturedFrameCount = newCapturedFrameCount + repeatedCapturedFrameCount
    lastNewFrameAt = captureDeliveryMetrics.lastNewFrameAt
    if captureContentRequiresNewFrame {
      guard frame.deliveryKind == .new else { return }
      captureContentRequiresNewFrame = false
    }
    if slideIdentityQuarantineActive {
      return
    }
    if slideIdentityFrameGate.requiresFreshFrame {
      guard
        slideIdentityFrameGate.acceptFrame(
          isNewDelivery: frame.deliveryKind == .new,
          displayTime: frame.displayTime
        )
      else { return }
      latestSlideIdentityFrameSynchronizationMachTime = mach_absolute_time()
      publishSlideIdentityFrameSyncState()
      slideIdentityFrameTimeoutTask?.cancel()
      slideIdentityFrameTimeoutTask = nil
    }
    latestEligibleWindowFrame = frame
    observeWindowFrameForSlideCanvas(frame, sessionID: sessionID)
    guard let confirmedSlideCanvasSelection else {
      invalidateOverlayPlacement()
      return
    }
    let canvasFrame: CapturedSlideCanvasFrame
    switch SlideCanvasFramePreparer.evaluate(
      frame,
      captureOperationID: sessionID,
      selection: confirmedSlideCanvasSelection
    ) {
    case .prepared(let preparedFrame):
      canvasFrame = preparedFrame
    case .rejected(let reason):
      invalidateConfirmedSlideCanvas(reason: reason)
      return
    }
    processVisualFrame(canvasFrame, sessionID: sessionID)
    refreshOverlayPlacement(using: frame, sessionID: sessionID)
    renderAlignedOverlayIfPossible(renewLeaseFromCurrentFrame: true)
  }

  private func observeWindowFrameForSlideCanvas(
    _ frame: CapturedPowerPointFrame,
    sessionID: CaptureOperationID
  ) {
    latestCapturedWindowFrame = frame.image

    guard confirmedSlideCanvasSelection == nil else { return }
    switch slideCanvasConfirmationMode {
    case .userConfirmed:
      guard
        let captureSurfaceGeometry = frame.captureSurfaceGeometry,
        captureSurfaceGeometry.outputPixelWidth == frame.image.width,
        captureSurfaceGeometry.outputPixelHeight == frame.image.height
      else {
        invalidateConfirmedSlideCanvas(
          reason: .surfaceGeometryUnavailableOrMismatched(for: frame.deliveryKind)
        )
        return
      }
      if slideCanvasStatus == .selecting {
        guard
          let source = slideCanvasCalibrationSource,
          source.captureOperationID == sessionID,
          source.windowID == frame.windowID
        else {
          invalidateConfirmedSlideCanvas(reason: .selectionContextMismatch)
          return
        }
        guard source.captureSurfaceGeometry == captureSurfaceGeometry else {
          invalidateConfirmedSlideCanvas(
            reason: .surfaceGeometryUnavailableOrMismatched(for: frame.deliveryKind)
          )
          return
        }
      } else if slideCanvasStatus == .waitingForFrame
        || slideCanvasStatus == .unavailable
        || slideCanvasStatus == .invalidated
      {
        slideCanvasStatus = .needsConfirmation
      }
    case .testOnlyUseFullCapturedFrame:
      guard
        let fullFrameRegion = SlideCanvasRegion(
          NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        ),
        let selection = ConfirmedSlideCanvasSelection.testOnlyFullFrame(
          captureOperationID: sessionID,
          windowID: frame.windowID,
          sourcePixelWidth: frame.image.width,
          sourcePixelHeight: frame.image.height
        )
      else {
        slideCanvasStatus = .invalidated
        slideCanvasInvalidationReason = .confirmedFrameRejected
        return
      }
      slideCanvasGeneration &+= 1
      confirmedSlideCanvasSelection = selection
      confirmedSlideCanvasRegion = fullFrameRegion
      slideCanvasStatus = .confirmed
      slideCanvasInvalidationReason = nil
      resetCanvasVisualPipeline()
    }
  }

  private func prepareSlideCanvasForNewCapture() {
    invalidateTranscriptionContext()
    resetBoardCandidateContext()
    clearOverlayDemoForCaptureStart()
    invalidateOverlayPlacement()
    slideCanvasGeneration &+= 1
    confirmedSlideCanvasSelection = nil
    confirmedSlideCanvasRegion = nil
    slideCanvasCalibrationSource = nil
    slideCanvasCalibrationFrame = nil
    latestCapturedWindowFrame = nil
    latestEligibleWindowFrame = nil
    slideCanvasCalibrationRevision &+= 1
    slideCanvasStatus = .waitingForFrame
    slideCanvasInvalidationReason = nil
  }

  private func invalidateSlideCanvasAfterCaptureEnd() {
    invalidateTranscriptionContext()
    resetBoardCandidateContext()
    overlayDemoSceneIsLoaded = false
    slideCanvasGeneration &+= 1
    confirmedSlideCanvasSelection = nil
    confirmedSlideCanvasRegion = nil
    slideCanvasCalibrationSource = nil
    slideCanvasCalibrationFrame = nil
    latestCapturedWindowFrame = nil
    latestEligibleWindowFrame = nil
    latestStableFrame = nil
    slideCanvasCalibrationRevision &+= 1
    slideCanvasStatus = .unavailable
    slideCanvasInvalidationReason = nil
    boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    boardSceneAnalysisGeneration = nil
    invalidateOverlayPlacement()
  }

  private func clearConfirmedSlideCanvas(resetVisualPipeline: Bool) {
    invalidateTranscriptionContext()
    slideCanvasGeneration &+= 1
    confirmedSlideCanvasSelection = nil
    confirmedSlideCanvasRegion = nil
    invalidateOverlayPlacement()
    if resetVisualPipeline {
      resetCanvasVisualPipeline()
    }
  }

  private func invalidateConfirmedSlideCanvas(reason: SlideCanvasInvalidationReason) {
    clearConfirmedSlideCanvas(resetVisualPipeline: true)
    slideCanvasCalibrationSource = nil
    slideCanvasCalibrationFrame = nil
    slideCanvasCalibrationRevision &+= 1
    slideCanvasStatus = activeCaptureSessionID == nil ? .unavailable : .invalidated
    slideCanvasInvalidationReason = activeCaptureSessionID == nil ? nil : reason
  }

  private func resetCanvasVisualPipeline() {
    invalidateTranscriptionContext()
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    latestDifferenceFromStableFrame = nil
    stableFrameCount = 0
    contentRevisionCount = 0
    latestStableFrame = nil
    resetSlideAnalysis()
    resetBoardCandidateContext()
    boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    boardSceneAnalysisGeneration = nil
    invalidateProductionOverlayLease()
  }

  private func processVisualFrame(
    _ frame: CapturedSlideCanvasFrame,
    sessionID: CaptureOperationID
  ) {
    let observation = stableFrameDetector.ingest(frame.fingerprint)
    latestDifferenceFromStableFrame = observation.differenceFromStableFrame

    switch observation.stability {
    case .stable:
      stableFrameCount += 1
      if observation.differenceFromStableFrame != nil {
        contentRevisionCount += 1
      }
      guard rebaseDenseFingerprintForConfirmedCoarseFrame(frame.contentFingerprint) else { return }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: sessionID)
    case .significantVisualChange:
      stableFrameCount += 1
      contentRevisionCount += 1
      guard rebaseDenseFingerprintForConfirmedCoarseFrame(frame.contentFingerprint) else { return }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: sessionID)
    case .unchanged:
      receiveContentFingerprintIfAvailable(frame, captureSessionID: sessionID)
    case .invalid, .collecting, .transitioning:
      stableContentChangeDetector.discardPendingChange()
      invalidateSlideAnalysisForVisualFreshness()
    }
  }

  private func handleCaptureError(
    _ message: String,
    sessionID: CaptureOperationID
  ) async {
    guard sessionID == activeCaptureSessionID else { return }
    let stopOperationID = nextCaptureOperationID()
    let failedIdentityState = slideIdentityStateAfterCaptureFailure
    activeCaptureSessionID = nil
    activeCaptureWindowID = nil
    activeCaptureIdentity = nil
    invalidateSlideIdentityAfterCaptureEnd(state: failedIdentityState)
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    lastAcceptedCaptureSequenceNumber = nil
    invalidateSlideCanvasAfterCaptureEnd()
    resetSlideAnalysis()
    captureStatus = .error(message)
    await stopCaptureProviders(operationID: stopOperationID)
  }

  private func receiveCaptureContentUnavailable(
    sequenceNumber: UInt64,
    sessionID: CaptureOperationID
  ) {
    guard sessionID == activeCaptureSessionID else { return }
    if let lastAcceptedCaptureSequenceNumber,
      sequenceNumber <= lastAcceptedCaptureSequenceNumber
    {
      return
    }
    lastAcceptedCaptureSequenceNumber = sequenceNumber
    captureContentRequiresNewFrame = true
    invalidateTranscriptionContext()
    latestEligibleWindowFrame = nil
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    latestDifferenceFromStableFrame = nil
    latestStableFrame = nil
    resetSlideAnalysis()
    resetBoardCandidateContext()
    boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    boardSceneAnalysisGeneration = nil
    invalidateOverlayPlacement()
  }

  private func startSlideAnalysis(
    _ frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID
  ) {
    invalidateProductionSceneForVisualFreshness()
    slideAnalysisNeedsRefresh = true
    analysisGeneration += 1
    let requestGeneration = analysisGeneration
    let requestSlideIdentityGeneration = slideIdentityGeneration
    let requestSlideCanvasGeneration = slideCanvasGeneration
    slideAnalysisStatus = .analyzing
    latestSlideAnalysis = nil
    let analyzer = slideVisionAnalyzer

    slideAnalysisTask?.cancel()
    slideAnalysisTask = Task { [weak self] in
      do {
        let analysis = try await analyzer.analyze(frame)
        guard !Task.isCancelled else { return }
        guard let self else { return }
        receive(
          analysis,
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration,
          requestSlideIdentityGeneration: requestSlideIdentityGeneration,
          requestSlideCanvasGeneration: requestSlideCanvasGeneration
        )
      } catch is CancellationError {
        guard let self else { return }
        handleSlideAnalysisCancellation(
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration,
          requestSlideIdentityGeneration: requestSlideIdentityGeneration,
          requestSlideCanvasGeneration: requestSlideCanvasGeneration
        )
      } catch {
        guard let self else { return }
        handleSlideAnalysisError(
          error.localizedDescription,
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration,
          requestSlideIdentityGeneration: requestSlideIdentityGeneration,
          requestSlideCanvasGeneration: requestSlideCanvasGeneration
        )
      }
    }
  }

  private func receiveContentFingerprintIfAvailable(
    _ frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID
  ) {
    guard let contentFingerprint = frame.contentFingerprint else {
      stableContentChangeDetector.discardPendingChange()
      invalidateSlideAnalysisForVisualFreshness()
      return
    }
    let observation = stableContentChangeDetector.ingest(contentFingerprint)
    switch observation.state {
    case .baselineEstablished:
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: captureSessionID)
    case .contentChanged:
      contentRevisionCount += 1
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: captureSessionID)
    case .unchanged:
      guard slideAnalysisNeedsRefresh, slideAnalysisStatus != .analyzing else { return }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: captureSessionID)
    case .invalid, .collectingBaseline, .contentChangePending:
      invalidateSlideAnalysisForVisualFreshness()
    }
  }

  private func rebaseDenseFingerprintForConfirmedCoarseFrame(
    _ contentFingerprint: ContentFingerprint?
  ) -> Bool {
    guard
      let contentFingerprint,
      stableContentChangeDetector.rebase(to: contentFingerprint)
    else {
      stableContentChangeDetector.reset()
      invalidateSlideAnalysisForVisualFreshness()
      return false
    }
    return true
  }

  private func stopCaptureProviders(operationID: CaptureOperationID) async {
    inFlightCaptureStopCount += 1
    await windowCapture.stop(operationID: operationID)
    await slideIdentityProvider.stop(operationID: operationID)
    inFlightCaptureStopCount -= 1
  }

  private func receive(
    _ analysis: SlideVisualAnalysis,
    frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int,
    requestSlideIdentityGeneration: Int,
    requestSlideCanvasGeneration: Int
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      requestSlideIdentityGeneration == slideIdentityGeneration,
      requestSlideCanvasGeneration == slideCanvasGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    latestSlideAnalysis = analysis
    slideAnalysisStatus = .ready
    slideAnalysisNeedsRefresh = false
    latestCompletedAnalysisGeneration = requestGeneration
    slideAnalysisTask = nil
    renderAlignedOverlayIfPossible()
  }

  private func handleSlideAnalysisError(
    _ message: String,
    frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int,
    requestSlideIdentityGeneration: Int,
    requestSlideCanvasGeneration: Int
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      requestSlideIdentityGeneration == slideIdentityGeneration,
      requestSlideCanvasGeneration == slideCanvasGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    slideAnalysisStatus = .error(message)
    latestCompletedAnalysisGeneration = nil
    slideAnalysisTask = nil
    invalidateProductionOverlayLease()
  }

  private func handleSlideAnalysisCancellation(
    frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int,
    requestSlideIdentityGeneration: Int,
    requestSlideCanvasGeneration: Int
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      requestSlideIdentityGeneration == slideIdentityGeneration,
      requestSlideCanvasGeneration == slideCanvasGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    slideAnalysisStatus = .idle
    latestCompletedAnalysisGeneration = nil
    slideAnalysisTask = nil
    invalidateProductionOverlayLease()
  }

  private func resetSlideAnalysis() {
    slideAnalysisNeedsRefresh = true
    analysisGeneration += 1
    slideAnalysisTask?.cancel()
    slideAnalysisTask = nil
    latestSlideAnalysis = nil
    latestCompletedAnalysisGeneration = nil
    slideAnalysisStatus = .idle
  }

  private func invalidateSlideAnalysisForVisualFreshness() {
    invalidateProductionSceneForVisualFreshness()
    guard
      !slideAnalysisNeedsRefresh
        || slideAnalysisTask != nil
        || latestSlideAnalysis != nil
        || slideAnalysisStatus != .idle
    else {
      return
    }
    resetSlideAnalysis()
  }

  private func invalidateProductionSceneForVisualFreshness() {
    latestVisualFreshnessBoundaryMachTime = mach_absolute_time()
    resetBoardCandidateContext()
    boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    boardSceneAnalysisGeneration = nil
    invalidateProductionOverlayLease()
  }

  private func refreshOverlayPlacement(
    using frame: CapturedPowerPointFrame,
    sessionID: CaptureOperationID
  ) {
    guard let confirmedSlideCanvasSelection else {
      invalidateOverlayPlacement()
      return
    }

    switch SlideCanvasOverlayMapper.evaluatePlacement(
      selection: confirmedSlideCanvasSelection,
      frame: frame,
      captureOperationID: sessionID,
      displays: displayCoordinateSnapshotProvider.currentSnapshots()
    ) {
    case .mapped(let placement):
      latestOverlayPlacement = placement
      slideCanvasOverlayMappingState = .mapped
    case .rejected(let reason):
      invalidateOverlayPlacement(mappingState: .rejected(reason))
    }
  }

  private func renderAlignedOverlayIfPossible(
    renewLeaseFromCurrentFrame: Bool = false
  ) {
    guard
      !overlayDemoSceneIsLoaded,
      !productionOverlayIsManuallySuppressed,
      captureStatus == .capturing,
      slideCanvasStatus == .confirmed,
      slideIdentityState == .identified,
      !slideIdentityQuarantineActive,
      !slideIdentityFrameGate.requiresFreshFrame,
      slideAnalysisStatus == .ready,
      !slideAnalysisNeedsRefresh,
      latestCompletedAnalysisGeneration == analysisGeneration,
      let activeCaptureSessionID,
      let activeCaptureWindowID,
      let activeCaptureIdentity,
      let latestEligibleWindowFrame,
      let captureScreenGeometry = latestEligibleWindowFrame.captureScreenGeometry,
      let latestOverlayPlacement,
      latestOverlayPlacement.captureOperationID == activeCaptureSessionID,
      latestOverlayPlacement.windowID == activeCaptureWindowID,
      latestOverlayPlacement.frameSequenceNumber == latestEligibleWindowFrame.sequenceNumber
    else {
      invalidateProductionOverlayLease()
      return
    }

    guard
      productionOverlayEligibilityProvider.allowsProductionOverlay(
        for: activeCaptureIdentity,
        screenGeometry: captureScreenGeometry
      )
    else {
      invalidateProductionOverlayLease()
      return
    }

    if renewLeaseFromCurrentFrame {
      renewProductionOverlayLease()
    }

    guard
      productionOverlayLeaseIsValid,
      !boardScene.elements.isEmpty,
      boardSceneAnalysisGeneration == analysisGeneration
    else {
      hideProductionOverlayPanel()
      return
    }

    let renderState = RenderedProductionOverlayState(
      captureOperationID: activeCaptureSessionID,
      windowID: activeCaptureWindowID,
      scene: boardScene,
      style: digitalInkStyle,
      appKitTargetFrame: latestOverlayPlacement.appKitTargetFrame
    )
    guard renderState != renderedProductionOverlayState else { return }

    overlayController.render(
      scene: boardScene,
      style: digitalInkStyle,
      in: latestOverlayPlacement.appKitTargetFrame
    )
    renderedProductionOverlayState = renderState
  }

  private func invalidateOverlayPlacement(
    mappingState: SlideCanvasOverlayMappingState = .unavailable
  ) {
    latestOverlayPlacement = nil
    slideCanvasOverlayMappingState = mappingState
    invalidateProductionOverlayLease()
  }

  private func hideProductionOverlayPanel() {
    renderedProductionOverlayState = nil
    overlayController.hide()
  }

  private func renewProductionOverlayLease() {
    productionOverlayLeaseGeneration &+= 1
    let generation = productionOverlayLeaseGeneration
    productionOverlayLeaseIsValid = true
    productionOverlayLeaseScheduler.schedule(after: productionOverlayLeaseDuration) {
      [weak self] in
      self?.expireProductionOverlayLease(expectedGeneration: generation)
    }
  }

  private func expireProductionOverlayLease(expectedGeneration: UInt64) {
    guard
      productionOverlayLeaseIsValid,
      productionOverlayLeaseGeneration == expectedGeneration
    else {
      return
    }
    invalidateProductionOverlayLease()
  }

  private func invalidateProductionOverlayLease(hidePanel: Bool = true) {
    productionOverlayLeaseGeneration &+= 1
    productionOverlayLeaseIsValid = false
    productionOverlayLeaseScheduler.cancel()
    if hidePanel {
      hideProductionOverlayPanel()
    }
  }

  private func handleProductionOverlayUnsafeEvent() {
    guard !overlayDemoSceneIsLoaded else { return }
    invalidateProductionOverlayLease()
  }

  private func clearOverlayDemoForCaptureStart() {
    guard overlayDemoSceneIsLoaded else { return }
    overlayDemoSceneIsLoaded = false
    invalidateProductionOverlayLease()
    boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    boardSceneAnalysisGeneration = nil
    if status == .overlayVisible {
      status = .ready
    }
  }

  private func receive(
    _ observation: PowerPointSlideIdentityObservation,
    sessionID: CaptureOperationID
  ) {
    guard sessionID == activeCaptureSessionID,
      observation.targetIdentity == activeCaptureIdentity,
      activeCaptureIdentity == selectedWindow?.identity
    else {
      return
    }
    if let lastAcceptedSlideIdentitySequenceNumber,
      observation.sequenceNumber <= lastAcceptedSlideIdentitySequenceNumber
    {
      return
    }
    lastAcceptedSlideIdentitySequenceNumber = observation.sequenceNumber
    let acceptedMachTime = mach_absolute_time()

    let previousState = slideIdentityTracker.state
    let event = slideIdentityTracker.ingest(observation.signal)
    publishSlideIdentityMetrics()

    switch event {
    case .baselineEstablished:
      guard case .available(let sample) = observation.signal else { return }
      rebaseBoardContext(to: sample, acceptedMachTime: acceptedMachTime)
    case .metadataUpdated:
      guard case .available(let sample) = observation.signal else { return }
      updateBoardSlideNumber(to: sample.slideIndex)
    case .slideChanged:
      guard case .available(let sample) = observation.signal else { return }
      rebaseBoardContext(to: sample, acceptedMachTime: acceptedMachTime)
    case .none:
      if slideIdentityState == .establishing {
        enterSlideIdentityQuarantine()
      } else if previousState == .establishing && slideIdentityState == .identified {
        abandonSlideIdentityCandidate(acceptedMachTime: acceptedMachTime)
      }
    case .continuityBroken:
      enterSlideIdentityQuarantine()
    }
  }

  private var isSlideIdentityQuarantined: Bool {
    slideIdentityQuarantineActive
  }

  private func prepareSlideIdentityForNewCapture() {
    slideIdentityTracker.reset()
    cancelSlideIdentityFrameWait()
    lastAcceptedSlideIdentitySequenceNumber = nil
    slideIdentityGeneration += 1
    slideIdentityQuarantineActive = false
    latestSlideIdentityBoundaryMachTime = nil
    latestSlideIdentityFrameSynchronizationMachTime = nil
    publishSlideIdentityMetrics()
  }

  private func publishSlideIdentityMetrics() {
    slideIdentityState = slideIdentityTracker.state
    slideIdentitySampleCount = slideIdentityTracker.sampleCount
    slideIdentityContinuityBreakCount = slideIdentityTracker.continuityBreakCount
    slideChangeCount = slideIdentityTracker.slideChangeCount
  }

  private func enterSlideIdentityQuarantine() {
    slideIdentityQuarantineActive = true
    cancelSlideIdentityFrameWait()
    resetVisualStateForSlideIdentityBoundary(clearBoardScene: false)
  }

  private func resetVisualStateForSlideIdentityBoundary(clearBoardScene: Bool) {
    invalidateTranscriptionContext()
    slideIdentityGeneration += 1
    latestEligibleWindowFrame = nil
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    latestDifferenceFromStableFrame = nil
    latestStableFrame = nil
    invalidateOverlayPlacement()
    resetSlideAnalysis()
    resetBoardCandidateContext()
    boardSceneAnalysisGeneration = nil
    if clearBoardScene {
      boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    }
  }

  private func rebaseBoardContext(to sample: SlideIdentitySample, acceptedMachTime: UInt64) {
    slideIdentityQuarantineActive = false
    latestSlideIdentityBoundaryMachTime = acceptedMachTime
    resetVisualStateForSlideIdentityBoundary(clearBoardScene: true)
    beginSlideIdentityFrameWait(after: acceptedMachTime)
    boardScene = BoardScene(slideNumber: sample.slideIndex)
    boardSceneAnalysisGeneration = nil
    renderAlignedOverlayIfPossible()
  }

  private func updateBoardSlideNumber(to slideNumber: Int) {
    boardScene.slideNumber = slideNumber
    renderAlignedOverlayIfPossible()
  }

  private func resetBoardCandidateContext() {
    boardCandidateContext.reset()
  }

  private func abandonSlideIdentityCandidate(acceptedMachTime: UInt64) {
    slideIdentityQuarantineActive = false
    latestSlideIdentityBoundaryMachTime = acceptedMachTime
    resetVisualStateForSlideIdentityBoundary(clearBoardScene: false)
    beginSlideIdentityFrameWait(after: acceptedMachTime)
  }

  private func invalidateSlideIdentityAfterCaptureEnd(state: SlideIdentityState) {
    invalidateTranscriptionContext()
    slideIdentityGeneration += 1
    lastAcceptedSlideIdentitySequenceNumber = nil
    slideIdentityTracker.reset()
    slideIdentityQuarantineActive = false
    cancelSlideIdentityFrameWait()
    latestSlideIdentityBoundaryMachTime = nil
    slideIdentityState = state
  }

  private func beginSlideIdentityFrameWait(after minimumDisplayTime: UInt64) {
    slideIdentityFrameTimeoutTask?.cancel()
    latestSlideIdentityFrameSynchronizationMachTime = nil
    let token = slideIdentityFrameGate.beginWaiting(after: minimumDisplayTime)
    publishSlideIdentityFrameSyncState()

    let timeout = slideIdentityFrameTimeout
    let waiter = slideIdentityFrameTimeoutWaiter
    slideIdentityFrameTimeoutTask = Task { @MainActor [weak self] in
      await waiter.wait(for: timeout)
      guard !Task.isCancelled, let self else { return }
      guard self.slideIdentityFrameGate.markTimedOut(for: token) else { return }
      self.publishSlideIdentityFrameSyncState()
      self.slideIdentityFrameTimeoutTask = nil
    }
  }

  private func cancelSlideIdentityFrameWait() {
    slideIdentityFrameTimeoutTask?.cancel()
    slideIdentityFrameTimeoutTask = nil
    slideIdentityFrameGate.reset()
    latestSlideIdentityFrameSynchronizationMachTime = nil
    publishSlideIdentityFrameSyncState()
  }

  private func publishSlideIdentityFrameSyncState() {
    slideIdentityFrameSyncState = slideIdentityFrameGate.state
  }

  private var slideIdentityStateAfterCaptureFailure: SlideIdentityState {
    switch slideIdentityTracker.state {
    case .establishing, .identified:
      .interrupted
    case .unavailable, .interrupted:
      .unavailable
    }
  }

  private func nextCaptureOperationID() -> CaptureOperationID {
    precondition(
      nextCaptureOperationRawValue < UInt64.max,
      "Capture operation identifier exhausted."
    )
    nextCaptureOperationRawValue += 1
    return CaptureOperationID(rawValue: nextCaptureOperationRawValue)
  }

  private func isLatestCaptureOperation(_ operationID: CaptureOperationID) -> Bool {
    operationID.rawValue == nextCaptureOperationRawValue
  }

  private func invalidateTranscriptionContext(forceReadyStatus: Bool = false) {
    let hadActiveOperation = transcriptionOperationGate.hasActiveOperation
    transcriptionOperationGate.invalidate()
    if hadActiveOperation {
      speechProvider.stop()
    }
    liveTranscript = ""
    if forceReadyStatus || status == .listening {
      status = .ready
    }
  }
}
