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

protocol FreshContentSampleWaiting: Sendable {
  func wait(for duration: Duration) async
}

struct TaskFreshContentSampleWaiter: FreshContentSampleWaiting {
  func wait(for duration: Duration) async {
    try? await Task.sleep(for: duration)
  }
}

private enum FreshContentSampleCandidateToken: Equatable, Sendable {
  case coarse(StableFrameCandidateToken)
  case dense(StableContentChangeCandidateToken)
}

private struct FreshContentSampleEpisode {
  let candidateToken: FreshContentSampleCandidateToken
  var attemptsStarted: Int
  var providerBusyDeferrals: Int
  var isExhausted: Bool
}

private struct CoarseRevisionEvidence {
  let candidateToken: StableFrameCandidateToken
  let evidenceStartedMachAbsoluteTime: UInt64?
}

private struct DenseRevisionEvidence {
  let candidateToken: StableContentChangeCandidateToken
  let evidenceStartedMachAbsoluteTime: UInt64?
}

private struct FreshContentSampleRequest {
  let requestID: FreshSampleRequestID
  let candidateToken: FreshContentSampleCandidateToken
  let captureOperationID: CaptureOperationID
  let captureIdentity: PowerPointWindowIdentity
  let anchoredStreamSequenceNumber: UInt64
  let anchoredCoarseFingerprint: FrameFingerprint
  let coarseDetectorFingerprint: FrameFingerprint?
  let evidenceStartedMachAbsoluteTime: UInt64
  let slideCanvasGeneration: Int
  let canvasSelection: ConfirmedSlideCanvasSelection
  let slideIdentityGeneration: Int
  let slideIdentityState: SlideIdentityState
  let slideIdentityFrameSyncState: SlideIdentityFrameSyncState
}

private enum SlideAnalysisOrigin: Equatable {
  case continuousStream
  case boundedFreshSample
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
  private static let maximumFreshContentSampleProviderBusyDeferrals = 10

  enum Status: Equatable {
    case ready
    case scanning
    case listening
    case finalizingTranscription
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

  enum LiveTranscriptPhase: Equatable {
    case empty
    case partial
    case final
  }

  enum TranscriptionLifecycleState: Equatable {
    case idle
    case starting
    case waitingForContext
    case listening
    case finalizing
    case failed(String)
  }

  enum ProductionOverlayEligibilityState: Equatable {
    case notEvaluated
    case allowed
    case blocked
  }

  enum ProductionOverlayPresentationState: Equatable {
    case hidden
    case renderRequested
  }

  @Published var status: Status = .ready
  @Published var powerPointWindows: [PowerPointWindowDescriptor] = []
  @Published var selectedPowerPointWindowID: CGWindowID?
  @Published var selectedLanguage: LanguageTag = .japanese
  @Published private(set) var liveTranscript = ""
  @Published private(set) var liveTranscriptPhase = LiveTranscriptPhase.empty
  @Published private(set) var transcriptionLifecycleState =
    TranscriptionLifecycleState.idle
  @Published var boardScene = BoardScene(slideNumber: 1) {
    didSet { recordPublicBoardScene(boardScene) }
  }
  @Published private(set) var lectureSessionScenes: [BoardScene] = []
  @Published var digitalInkStyle = DigitalInkStyle.clean
  @Published private(set) var captureStatus: CaptureStatus = .stopped
  @Published private(set) var captureFailureSource: RuntimeCaptureFailureSource?
  @Published private(set) var captureSCStreamErrorCode: RuntimeSCStreamErrorCode?
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
  @Published private(set) var latestContentRevisionEvent: RuntimeContentRevisionEvent?
  @Published private(set) var slideCanvasStatus = SlideCanvasStatus.unavailable
  @Published private(set) var slideCanvasOverlayMappingState =
    SlideCanvasOverlayMappingState.unavailable
  @Published private(set) var productionOverlayEligibilityState =
    ProductionOverlayEligibilityState.notEvaluated
  @Published private(set) var productionOverlayPresentationState =
    ProductionOverlayPresentationState.hidden
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
  private let freshContentSampleDelay: Duration
  private let freshContentSampleWaiter: any FreshContentSampleWaiting
  private let boardEngine = ContextualBoardEngine()
  private let sceneComposer = BoardSceneComposer()
  private var stableFrameDetector = StableFrameDetector()
  private var stableContentChangeDetector = StableContentChangeDetector()
  private var coarseRevisionEvidence: CoarseRevisionEvidence?
  private var denseRevisionEvidence: DenseRevisionEvidence?
  private var captureDeliveryMetrics = CaptureDeliveryMetrics()
  private var refreshGeneration: UInt64 = 0
  private var nextCaptureOperationRawValue: UInt64 = 0
  private var activeCaptureSessionID: CaptureOperationID?
  private var activeCaptureWindowID: CGWindowID?
  private var activeCaptureIdentity: PowerPointWindowIdentity?
  private var activeCaptureUsesManagedSlideShow = false
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
  private var freshContentSampleTask: Task<Void, Never>?
  private var freshContentSampleEpisode: FreshContentSampleEpisode?
  private var currentFreshContentSampleRequest: FreshContentSampleRequest?
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
  private var transcriptionRequestedByUser = false
  private var automaticTranscriptionResumeTask: Task<Void, Never>?
  private var overlayDemoSceneIsLoaded = false
  private var productionOverlayIsManuallySuppressed = false
  private var latestOverlayPlacement: SlideCanvasOverlayPlacement?
  private var renderedProductionOverlayState: RenderedProductionOverlayState?
  private var productionOverlayLeaseGeneration: UInt64 = 0
  private var productionOverlayLeaseIsValid = false
  private var managedSlideShowTransaction: ManagedSlideShowTransactionCoordinator?
  private var managedSlideShowTransactionReleaseTask: Task<Void, Never>?
  private var sessionSceneRecordingEnabled = false

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
    freshContentSampleDelay: Duration = .milliseconds(100),
    freshContentSampleWaiter: any FreshContentSampleWaiting =
      TaskFreshContentSampleWaiter(),
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
    self.freshContentSampleDelay = max(freshContentSampleDelay, .zero)
    self.freshContentSampleWaiter = freshContentSampleWaiter
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
    freshContentSampleTask?.cancel()
    managedSlideShowTransactionReleaseTask?.cancel()
    automaticTranscriptionResumeTask?.cancel()
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

  var canExportLectureSession: Bool {
    guard !lectureSessionScenes.isEmpty, inFlightCaptureStopCount == 0 else { return false }
    switch captureStatus {
    case .stopped, .error:
      return true
    case .starting, .capturing:
      return false
    }
  }

  var publicBoardElementCount: Int {
    boardScene.elements.count
  }

  var productionConfirmedBoardElementCount: Int {
    guard
      captureStatus == .capturing,
      sessionSceneRecordingEnabled,
      !overlayDemoSceneIsLoaded,
      boardSceneAnalysisGeneration != nil
    else {
      return 0
    }
    return boardScene.elements.count
  }

  /// Writes the retained public scenes to JSON and its sibling SVG.  The view owns the
  /// explicit save-panel choice; this method remains GUI-free for deterministic tests.
  @discardableResult
  func exportLectureSession(to jsonURL: URL) throws -> LectureSessionExportURLs {
    try LectureSessionExporter(scenes: lectureSessionScenes).write(to: jsonURL)
  }

  private func resetLectureSessionScenesForCapture() {
    lectureSessionScenes.removeAll(keepingCapacity: true)
    sessionSceneRecordingEnabled = true
  }

  private func recordPublicBoardScene(_ scene: BoardScene) {
    guard sessionSceneRecordingEnabled,
      captureStatus != .stopped,
      !overlayDemoSceneIsLoaded,
      !scene.elements.isEmpty
    else { return }

    if lectureSessionScenes.last?.slideNumber == scene.slideNumber {
      lectureSessionScenes[lectureSessionScenes.count - 1] = scene
    } else {
      lectureSessionScenes.append(scene)
    }
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

  func recheckScreenCapturePermission() {
    objectWillChange.send()
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
      let event = CaptureFailureEventFactory.unclassified(
        message: NSLocalizedString("error.captureWindowUnavailable", comment: "")
      )
      captureFailureSource = event.source
      captureSCStreamErrorCode = event.scStreamErrorCode
      captureStatus = .error(event.message)
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
    resetLectureSessionScenesForCapture()
    captureFailureSource = nil
    captureSCStreamErrorCode = nil
    productionOverlayIsManuallySuppressed = false
    activeCaptureSessionID = operationID
    activeCaptureWindowID = selectedPowerPointWindowID
    activeCaptureIdentity = selectedIdentity
    activeCaptureUsesManagedSlideShow = false
    captureStatus = .starting
    capturedFrameCount = 0
    captureDeliveryMetrics.reset()
    newCapturedFrameCount = 0
    repeatedCapturedFrameCount = 0
    lastNewFrameAt = nil
    latestDifferenceFromStableFrame = nil
    stableFrameCount = 0
    slideChangeCount = 0
    resetContentRevisions()
    latestStableFrame = nil
    prepareSlideCanvasForNewCapture()
    resetVisualDetectors()
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
        onFailure: { [weak self] event in
          Task { @MainActor [weak self] in
            await self?.handleCaptureFailure(event, sessionID: operationID)
          }
        }
      )
      guard activeCaptureSessionID == operationID else { return }
      guard selectedIdentity == self.selectedWindow?.identity else {
        let stopOperationID = nextCaptureOperationID()
        sessionSceneRecordingEnabled = false
        activeCaptureSessionID = nil
        activeCaptureWindowID = nil
        activeCaptureIdentity = nil
        activeCaptureUsesManagedSlideShow = false
        invalidateSlideIdentityAfterCaptureEnd(state: .unavailable)
        resetVisualDetectors()
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
      let event = CaptureFailureEventFactory.startFailed(error: error)
      let failedIdentityState = slideIdentityStateAfterCaptureFailure
      activeCaptureSessionID = nil
      activeCaptureWindowID = nil
      activeCaptureIdentity = nil
      activeCaptureUsesManagedSlideShow = false
      sessionSceneRecordingEnabled = false
      invalidateSlideIdentityAfterCaptureEnd(state: failedIdentityState)
      captureFailureSource = event.source
      captureSCStreamErrorCode = event.scStreamErrorCode
      captureStatus = .error(event.message)
      resetVisualDetectors()
      lastAcceptedCaptureSequenceNumber = nil
      invalidateSlideCanvasAfterCaptureEnd()
      resetSlideAnalysis()
      let stopOperationID = nextCaptureOperationID()
      await stopCaptureProviders(operationID: stopOperationID)
    }
  }

  /// Explicitly starts a new managed slide show.  Unlike ordinary observation capture, this is
  /// allowed to use Automation and briefly performs a reversible role challenge on the exact
  /// object returned by PowerPoint.  Passive refresh and the existing diagnostic start remain
  /// Automation-free.
  func startManagedSlideShowCapture() async {
    guard let selectedIdentity = selectedWindow?.identity else { return }
    guard
      CaptureControlPolicy.canStart(
        screenCaptureAccessGranted: permissionService.screenCaptureAccessGranted,
        hasSelectedWindow: true,
        captureStatus: captureStatus
      ),
      managedSlideShowTransaction == nil
    else { return }

    let operationID = nextCaptureOperationID()
    resetLectureSessionScenesForCapture()
    captureFailureSource = nil
    captureSCStreamErrorCode = nil
    productionOverlayIsManuallySuppressed = false
    activeCaptureSessionID = operationID
    activeCaptureWindowID = nil
    activeCaptureIdentity = nil
    activeCaptureUsesManagedSlideShow = true
    captureStatus = .starting
    capturedFrameCount = 0
    captureDeliveryMetrics.reset()
    newCapturedFrameCount = 0
    repeatedCapturedFrameCount = 0
    lastNewFrameAt = nil
    latestDifferenceFromStableFrame = nil
    stableFrameCount = 0
    slideChangeCount = 0
    resetContentRevisions()
    latestStableFrame = nil
    prepareSlideCanvasForNewCapture()
    resetVisualDetectors()
    lastAcceptedCaptureSequenceNumber = nil
    captureContentRequiresNewFrame = false
    latestVisualFreshnessBoundaryMachTime = nil
    prepareSlideIdentityForNewCapture()
    resetSlideAnalysis()

    let transaction = ManagedSlideShowTransactionFactory.make(
      frozenWindowIdentity: selectedIdentity,
      capture: windowCapture
    )
    managedSlideShowTransaction = transaction
    let result = await transaction.start(
      operationID: operationID,
      onFrame: { [weak self] frame in
        Task { @MainActor [weak self] in self?.receive(frame, sessionID: operationID) }
      },
      onContentUnavailable: { [weak self] sequenceNumber in
        Task { @MainActor [weak self] in
          self?.receiveCaptureContentUnavailable(
            sequenceNumber: sequenceNumber, sessionID: operationID)
        }
      },
      onFailure: { [weak self] event in
        Task { @MainActor [weak self] in
          await self?.handleCaptureFailure(event, sessionID: operationID)
        }
      },
      activateBinding: { [weak self] binding in
        await MainActor.run {
          guard let self, self.activeCaptureSessionID == operationID,
            self.activeCaptureUsesManagedSlideShow
          else { return false }
          self.activeCaptureWindowID = binding.windowIdentity.windowID
          self.activeCaptureIdentity = binding.windowIdentity
          return true
        }
      },
      onIdentityObservation: { [weak self] observation in
        Task { @MainActor [weak self] in self?.receive(observation, sessionID: operationID) }
      }
    )
    guard activeCaptureSessionID == operationID else { return }
    switch result {
    case .success:
      captureStatus = .capturing
    case .failure:
      releaseManagedSlideShowTransactionWhenSafe(transaction)
      activeCaptureSessionID = nil
      activeCaptureWindowID = nil
      activeCaptureIdentity = nil
      activeCaptureUsesManagedSlideShow = false
      sessionSceneRecordingEnabled = false
      invalidateSlideIdentityAfterCaptureEnd(state: .unavailable)
      resetVisualDetectors()
      lastAcceptedCaptureSequenceNumber = nil
      invalidateSlideCanvasAfterCaptureEnd()
      resetSlideAnalysis()
      captureStatus = .error(NSLocalizedString("error.managedStartFailed", comment: ""))
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
    sessionSceneRecordingEnabled = false
    activeCaptureSessionID = nil
    activeCaptureWindowID = nil
    activeCaptureIdentity = nil
    activeCaptureUsesManagedSlideShow = false
    invalidateSlideIdentityAfterCaptureEnd(state: .unavailable)
    resetVisualDetectors()
    lastAcceptedCaptureSequenceNumber = nil
    captureContentRequiresNewFrame = false
    captureFailureSource = nil
    captureSCStreamErrorCode = nil
    invalidateSlideCanvasAfterCaptureEnd()
    resetSlideAnalysis()
    captureStatus = .stopped
    await stopCaptureProviders(operationID: operationID)
    return operationID
  }

  func showOverlayDemo() {
    guard canShowOverlayDemo else { return }
    overlayDemoSceneIsLoaded = true
    productionOverlayIsManuallySuppressed = false
    invalidateProductionOverlayLease(hidePanel: false)
    renderedProductionOverlayState = nil
    boardScene = DemoBoardSceneFactory.make(language: selectedLanguage)
    boardSceneAnalysisGeneration = nil
    overlayController.showDemo(scene: boardScene, style: digitalInkStyle, on: NSScreen.main)
    status = .overlayVisible
  }

  func hideOverlay() {
    productionOverlayIsManuallySuppressed = true
    invalidateProductionOverlayLease()
    status = .ready
  }

  var canRequestTranscriptionStart: Bool {
    switch transcriptionLifecycleState {
    case .idle, .failed:
      return true
    case .starting, .waitingForContext, .listening, .finalizing:
      return false
    }
  }

  var canRequestTranscriptionStop: Bool {
    switch transcriptionLifecycleState {
    case .starting, .waitingForContext, .listening:
      return true
    case .idle, .finalizing, .failed:
      return false
    }
  }

  // Keep user actions single-flight without changing explicit internal restart semantics.
  func requestTranscriptionStart() async {
    guard canRequestTranscriptionStart else { return }
    await startTranscription()
  }

  func requestTranscriptionStop() {
    guard canRequestTranscriptionStop else { return }
    stopTranscription()
  }

  func startTranscription() async {
    transcriptionRequestedByUser = true
    await startTranscriptionOperation()
  }

  private func startTranscriptionOperation() async {
    guard transcriptionRequestedByUser else { return }
    invalidateTranscriptionContext(preserveUserRequest: true)
    let operationID = transcriptionOperationGate.begin()
    transcriptionLifecycleState = .starting
    clearLiveTranscript()
    do {
      try await speechProvider.start(
        operationID: operationID,
        language: selectedLanguage,
        onObservation: { [weak self] observation in
          guard let self else { return }
          self.receive(observation, transcriptionOperationID: operationID)
        },
        onTerminalEvent: { [weak self] event in
          guard let self else { return }
          self.receive(
            event,
            transcriptionOperationID: operationID
          )
        }
      )
      guard transcriptionOperationGate.accepts(operationID) else {
        if !transcriptionOperationGate.hasActiveOperation {
          speechProvider.stop(operationID: operationID)
        }
        return
      }
      status = .listening
      transcriptionLifecycleState = .listening
    } catch {
      guard transcriptionOperationGate.invalidate(ifCurrent: operationID) else { return }
      transcriptionRequestedByUser = false
      speechProvider.stop(operationID: operationID)
      clearLiveTranscript()
      status = .error(error.localizedDescription)
      transcriptionLifecycleState = .failed(error.localizedDescription)
    }
  }

  func stopTranscription() {
    transcriptionRequestedByUser = false
    automaticTranscriptionResumeTask?.cancel()
    automaticTranscriptionResumeTask = nil
    guard let operationID = transcriptionOperationGate.activeOperationID else {
      status = .ready
      transcriptionLifecycleState = .idle
      return
    }
    status = .finalizingTranscription
    transcriptionLifecycleState = .finalizing
    speechProvider.finishCurrentSegment(operationID: operationID)
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

  private func receive(
    _ event: TranscriptionTerminalEvent,
    transcriptionOperationID: TranscriptionOperationID
  ) {
    guard event.operationID == transcriptionOperationID else { return }
    guard transcriptionOperationGate.invalidate(ifCurrent: transcriptionOperationID) else {
      return
    }
    transcriptionRequestedByUser = false
    switch event.outcome {
    case .gracefulStopCompleted:
      if liveTranscriptPhase != .final {
        clearLiveTranscript()
      }
      status = .ready
      transcriptionLifecycleState = .idle
    case .failure(let error):
      clearLiveTranscript()
      status = .error(error.localizedDescription)
      transcriptionLifecycleState = .failed(error.localizedDescription)
    }
  }

  private func receiveAcceptedTranscriptionObservation(
    _ observation: TranscriptionObservation
  ) {
    let segment = observation.segment
    liveTranscript = segment.text
    if segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      liveTranscriptPhase = .empty
    } else {
      liveTranscriptPhase = segment.isFinal ? .final : .partial
    }
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
    let nextBoardScene = sceneComposer.append(
      intents: proposals,
      to: boardScene,
      slideOccupied: slide.occupiedRegions
    )
    guard nextBoardScene != boardScene else { return }

    boardScene = nextBoardScene
    boardSceneAnalysisGeneration = analysisGeneration
    renderAlignedOverlayIfPossible()
  }

  private func receive(_ frame: CapturedPowerPointFrame, sessionID: CaptureOperationID) {
    guard sessionID == activeCaptureSessionID,
      frame.windowID == activeCaptureWindowID,
      activeCaptureSelectionIsConsistent
    else {
      return
    }
    if let lastAcceptedCaptureSequenceNumber,
      frame.sequenceNumber <= lastAcceptedCaptureSequenceNumber
    {
      return
    }
    lastAcceptedCaptureSequenceNumber = frame.sequenceNumber
    cancelFreshContentSampling(resetEpisode: false)
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
    cancelFreshContentSampling(resetEpisode: true)
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
    cancelFreshContentSampling(resetEpisode: true)
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

  private func resetContentRevisions() {
    contentRevisionCount = 0
    latestContentRevisionEvent = nil
  }

  private func recordContentRevision(
    source: RuntimeContentRevisionSource,
    evidenceStartedMachAbsoluteTime: UInt64?,
    confirmedMachAbsoluteTime: UInt64?
  ) {
    contentRevisionCount += 1
    guard
      let evidenceStartedMachAbsoluteTime,
      evidenceStartedMachAbsoluteTime > 0,
      let confirmedMachAbsoluteTime,
      confirmedMachAbsoluteTime >= evidenceStartedMachAbsoluteTime
    else {
      // Never carry an older event forward under a newer counter. Runtime
      // projection then fails closed instead of inventing temporal evidence.
      latestContentRevisionEvent = nil
      return
    }
    latestContentRevisionEvent = RuntimeContentRevisionEvent(
      ordinal: contentRevisionCount,
      evidenceStartedMachAbsoluteTime: evidenceStartedMachAbsoluteTime,
      confirmedMachAbsoluteTime: confirmedMachAbsoluteTime,
      source: source
    )
  }

  private func resetVisualDetectors() {
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    coarseRevisionEvidence = nil
    denseRevisionEvidence = nil
  }

  private func resetDenseContentChangeDetector() {
    stableContentChangeDetector.reset()
    denseRevisionEvidence = nil
  }

  private func discardDenseContentChangeCandidate() {
    stableContentChangeDetector.discardPendingChange()
    denseRevisionEvidence = nil
  }

  private func sourceMachAbsoluteTime(
    for frame: CapturedSlideCanvasFrame
  ) -> UInt64? {
    guard let displayTime = frame.displayTime, displayTime > 0 else { return nil }
    return displayTime
  }

  private func updateCoarseRevisionEvidence(
    for observation: StableFrameObservation,
    frame: CapturedSlideCanvasFrame
  ) -> UInt64? {
    guard let candidateToken = observation.candidateToken else {
      coarseRevisionEvidence = nil
      return nil
    }
    if coarseRevisionEvidence?.candidateToken != candidateToken {
      coarseRevisionEvidence = CoarseRevisionEvidence(
        candidateToken: candidateToken,
        evidenceStartedMachAbsoluteTime: sourceMachAbsoluteTime(for: frame)
      )
    }
    let evidenceStartedMachAbsoluteTime =
      coarseRevisionEvidence?.evidenceStartedMachAbsoluteTime
    switch observation.stability {
    case .stable, .significantVisualChange:
      coarseRevisionEvidence = nil
    case .invalid, .collecting, .unchanged, .transitioning:
      break
    }
    return evidenceStartedMachAbsoluteTime
  }

  private func updateDenseRevisionEvidence(
    for observation: StableContentChangeObservation,
    frame: CapturedSlideCanvasFrame
  ) -> UInt64? {
    switch observation.state {
    case .contentChangePending:
      guard let candidateToken = observation.pendingChangeToken else {
        denseRevisionEvidence = nil
        return nil
      }
      if denseRevisionEvidence?.candidateToken != candidateToken {
        denseRevisionEvidence = DenseRevisionEvidence(
          candidateToken: candidateToken,
          evidenceStartedMachAbsoluteTime: sourceMachAbsoluteTime(for: frame)
        )
      }
      return denseRevisionEvidence?.evidenceStartedMachAbsoluteTime
    case .contentChanged:
      let evidenceStartedMachAbsoluteTime =
        denseRevisionEvidence?.evidenceStartedMachAbsoluteTime
      denseRevisionEvidence = nil
      return evidenceStartedMachAbsoluteTime
    case .invalid, .collectingBaseline, .baselineEstablished, .unchanged:
      denseRevisionEvidence = nil
      return nil
    }
  }

  private func evidenceStartedMachAbsoluteTime(
    for candidateToken: FreshContentSampleCandidateToken
  ) -> UInt64? {
    switch candidateToken {
    case .coarse(let token):
      guard coarseRevisionEvidence?.candidateToken == token else { return nil }
      return coarseRevisionEvidence?.evidenceStartedMachAbsoluteTime
    case .dense(let token):
      guard denseRevisionEvidence?.candidateToken == token else { return nil }
      return denseRevisionEvidence?.evidenceStartedMachAbsoluteTime
    }
  }

  private func resetCanvasVisualPipeline() {
    cancelFreshContentSampling(resetEpisode: true)
    invalidateTranscriptionContext()
    resetVisualDetectors()
    latestDifferenceFromStableFrame = nil
    stableFrameCount = 0
    resetContentRevisions()
    latestStableFrame = nil
    resetSlideAnalysis()
    resetBoardCandidateContext()
    boardScene = BoardScene(slideNumber: boardScene.slideNumber)
    boardSceneAnalysisGeneration = nil
    invalidateProductionOverlayLease()
  }

  private func continuousDenseRevisionSource(
    for frame: CapturedSlideCanvasFrame
  ) -> RuntimeContentRevisionSource? {
    switch frame.deliveryKind {
    case .new:
      return .continuousDenseNew
    case .idleRepeat:
      return .continuousDenseIdleRepeat
    case nil:
      return nil
    }
  }

  private func processVisualFrame(
    _ frame: CapturedSlideCanvasFrame,
    sessionID: CaptureOperationID
  ) {
    let observation = stableFrameDetector.ingest(frame.fingerprint)
    let coarseEvidenceStartedMachAbsoluteTime = updateCoarseRevisionEvidence(
      for: observation,
      frame: frame
    )
    latestDifferenceFromStableFrame = observation.differenceFromStableFrame

    switch observation.stability {
    case .stable:
      cancelFreshContentSampling(resetEpisode: true)
      stableFrameCount += 1
      if observation.differenceFromStableFrame != nil {
        recordContentRevision(
          source: .coarseStable,
          evidenceStartedMachAbsoluteTime: coarseEvidenceStartedMachAbsoluteTime,
          confirmedMachAbsoluteTime: sourceMachAbsoluteTime(for: frame)
        )
      }
      guard rebaseDenseFingerprintForConfirmedCoarseFrame(frame.contentFingerprint) else { return }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: sessionID)
    case .significantVisualChange:
      cancelFreshContentSampling(resetEpisode: true)
      stableFrameCount += 1
      recordContentRevision(
        source: .coarseSignificantVisualChange,
        evidenceStartedMachAbsoluteTime: coarseEvidenceStartedMachAbsoluteTime,
        confirmedMachAbsoluteTime: sourceMachAbsoluteTime(for: frame)
      )
      guard rebaseDenseFingerprintForConfirmedCoarseFrame(frame.contentFingerprint) else { return }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: sessionID)
    case .unchanged:
      receiveContentFingerprintIfAvailable(frame, captureSessionID: sessionID)
    case .invalid:
      cancelFreshContentSampling(resetEpisode: true)
      discardDenseContentChangeCandidate()
      invalidateSlideAnalysisForVisualFreshness()
    case .collecting, .transitioning:
      discardDenseContentChangeCandidate()
      invalidateSlideAnalysisForVisualFreshness()
      // Initial baseline collection has no prior coarse frame to revise. Only
      // an exact post-baseline candidate receives bounded fresh confirmation.
      guard
        observation.differenceFromStableFrame != nil,
        let candidateToken = observation.candidateToken,
        let comparableCoarseFingerprint = CGImageRasterizer.makeFrameFingerprint(
          from: frame.image
        )
      else {
        cancelFreshContentSampling(resetEpisode: true)
        return
      }
      scheduleFreshContentSample(
        candidateToken: .coarse(candidateToken),
        anchoredStreamSequenceNumber: frame.sequenceNumber,
        anchoredCoarseFingerprint: comparableCoarseFingerprint,
        coarseDetectorFingerprint: frame.fingerprint
      )
    }
  }

  private func handleCaptureFailure(
    _ event: CaptureFailureEvent,
    sessionID: CaptureOperationID
  ) async {
    guard sessionID == activeCaptureSessionID else { return }
    let stopOperationID = nextCaptureOperationID()
    let failedIdentityState = slideIdentityStateAfterCaptureFailure
    activeCaptureSessionID = nil
    activeCaptureWindowID = nil
    activeCaptureIdentity = nil
    activeCaptureUsesManagedSlideShow = false
    sessionSceneRecordingEnabled = false
    invalidateSlideIdentityAfterCaptureEnd(state: failedIdentityState)
    resetVisualDetectors()
    lastAcceptedCaptureSequenceNumber = nil
    invalidateSlideCanvasAfterCaptureEnd()
    resetSlideAnalysis()
    captureFailureSource = event.source
    captureSCStreamErrorCode = event.scStreamErrorCode
    captureStatus = .error(event.message)
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
    cancelFreshContentSampling(resetEpisode: true)
    captureContentRequiresNewFrame = true
    invalidateTranscriptionContext(preserveUserRequest: true)
    latestEligibleWindowFrame = nil
    resetVisualDetectors()
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
    captureSessionID: CaptureOperationID,
    origin: SlideAnalysisOrigin = .continuousStream
  ) {
    if origin == .continuousStream {
      invalidateProductionSceneForVisualFreshness()
    }
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
          requestSlideCanvasGeneration: requestSlideCanvasGeneration,
          origin: origin
        )
      } catch is CancellationError {
        guard let self else { return }
        handleSlideAnalysisCancellation(
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration,
          requestSlideIdentityGeneration: requestSlideIdentityGeneration,
          requestSlideCanvasGeneration: requestSlideCanvasGeneration,
          origin: origin
        )
      } catch {
        guard let self else { return }
        handleSlideAnalysisError(
          error.localizedDescription,
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration,
          requestSlideIdentityGeneration: requestSlideIdentityGeneration,
          requestSlideCanvasGeneration: requestSlideCanvasGeneration,
          origin: origin
        )
      }
    }
  }

  private func receiveContentFingerprintIfAvailable(
    _ frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID
  ) {
    guard let contentFingerprint = frame.contentFingerprint else {
      cancelFreshContentSampling(resetEpisode: true)
      discardDenseContentChangeCandidate()
      invalidateSlideAnalysisForVisualFreshness()
      return
    }
    let observation = stableContentChangeDetector.ingest(contentFingerprint)
    let denseEvidenceStartedMachAbsoluteTime = updateDenseRevisionEvidence(
      for: observation,
      frame: frame
    )
    switch observation.state {
    case .baselineEstablished:
      cancelFreshContentSampling(resetEpisode: true)
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: captureSessionID)
    case .contentChanged:
      cancelFreshContentSampling(resetEpisode: true)
      guard let source = continuousDenseRevisionSource(for: frame) else {
        invalidateSlideAnalysisForVisualFreshness()
        return
      }
      recordContentRevision(
        source: source,
        evidenceStartedMachAbsoluteTime: denseEvidenceStartedMachAbsoluteTime,
        confirmedMachAbsoluteTime: sourceMachAbsoluteTime(for: frame)
      )
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: captureSessionID)
    case .unchanged:
      cancelFreshContentSampling(resetEpisode: true)
      guard slideAnalysisNeedsRefresh, slideAnalysisStatus != .analyzing else { return }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: captureSessionID)
    case .contentChangePending:
      invalidateSlideAnalysisForVisualFreshness()
      // Continuous full-frame capture fingerprints are sampled directly from the
      // pixel buffer, while a bounded screenshot is represented as a CGImage.
      // Re-rasterize the accepted canvas image so the fresh-sample guard compares
      // fingerprints produced by the same deterministic image path.
      guard
        let candidateToken = observation.pendingChangeToken,
        let comparableCoarseFingerprint = CGImageRasterizer.makeFrameFingerprint(
          from: frame.image
        )
      else {
        cancelFreshContentSampling(resetEpisode: true)
        discardDenseContentChangeCandidate()
        return
      }
      scheduleFreshContentSample(
        candidateToken: .dense(candidateToken),
        anchoredStreamSequenceNumber: frame.sequenceNumber,
        anchoredCoarseFingerprint: comparableCoarseFingerprint,
        coarseDetectorFingerprint: nil
      )
    case .invalid:
      cancelFreshContentSampling(resetEpisode: true)
      discardDenseContentChangeCandidate()
      invalidateSlideAnalysisForVisualFreshness()
    case .collectingBaseline:
      cancelFreshContentSampling(resetEpisode: true)
      invalidateSlideAnalysisForVisualFreshness()
    }
  }

  private func scheduleFreshContentSample(
    candidateToken: FreshContentSampleCandidateToken,
    anchoredStreamSequenceNumber: UInt64,
    anchoredCoarseFingerprint: FrameFingerprint,
    coarseDetectorFingerprint: FrameFingerprint?
  ) {
    if freshContentSampleEpisode?.candidateToken != candidateToken {
      cancelFreshContentSampling(resetEpisode: true)
      freshContentSampleEpisode = FreshContentSampleEpisode(
        candidateToken: candidateToken,
        attemptsStarted: 0,
        providerBusyDeferrals: 0,
        isExhausted: false
      )
    }

    guard
      currentFreshContentSampleRequest == nil,
      let episode = freshContentSampleEpisode,
      episode.candidateToken == candidateToken,
      let evidenceStartedMachAbsoluteTime =
        evidenceStartedMachAbsoluteTime(for: candidateToken),
      evidenceStartedMachAbsoluteTime > 0,
      freshContentSampleCandidateIsStructurallyValid(
        candidateToken,
        coarseDetectorFingerprint: coarseDetectorFingerprint
      ),
      !episode.isExhausted,
      episode.attemptsStarted < 2,
      captureStatus == .capturing,
      let activeCaptureSessionID,
      let activeCaptureIdentity,
      activeCaptureSelectionIsConsistent,
      let lastAcceptedCaptureSequenceNumber,
      lastAcceptedCaptureSequenceNumber == anchoredStreamSequenceNumber,
      !captureContentRequiresNewFrame,
      slideCanvasStatus == .confirmed,
      let confirmedSlideCanvasSelection,
      confirmedSlideCanvasSelection.captureOperationID == activeCaptureSessionID,
      let latestEligibleWindowFrame,
      latestEligibleWindowFrame.windowID == activeCaptureIdentity.windowID,
      latestEligibleWindowFrame.sequenceNumber == anchoredStreamSequenceNumber,
      !slideIdentityQuarantineActive,
      !slideIdentityFrameGate.requiresFreshFrame
    else {
      return
    }

    let request = FreshContentSampleRequest(
      requestID: FreshSampleRequestID(),
      candidateToken: candidateToken,
      captureOperationID: activeCaptureSessionID,
      captureIdentity: activeCaptureIdentity,
      anchoredStreamSequenceNumber: anchoredStreamSequenceNumber,
      anchoredCoarseFingerprint: anchoredCoarseFingerprint,
      coarseDetectorFingerprint: coarseDetectorFingerprint,
      evidenceStartedMachAbsoluteTime: evidenceStartedMachAbsoluteTime,
      slideCanvasGeneration: slideCanvasGeneration,
      canvasSelection: confirmedSlideCanvasSelection,
      slideIdentityGeneration: slideIdentityGeneration,
      slideIdentityState: slideIdentityState,
      slideIdentityFrameSyncState: slideIdentityFrameSyncState
    )
    currentFreshContentSampleRequest = request

    let delay = freshContentSampleDelay
    let waiter = freshContentSampleWaiter
    let capture = windowCapture
    freshContentSampleTask = Task { @MainActor [weak self] in
      await waiter.wait(for: delay)
      guard
        !Task.isCancelled,
        self?.beginFreshContentSample(request) == true
      else {
        return
      }

      do {
        let sample = try await capture.captureFreshSample(
          operationID: request.captureOperationID,
          identity: request.captureIdentity,
          requestID: request.requestID
        )
        guard !Task.isCancelled, let self else { return }
        self.receiveFreshContentSample(sample, request: request)
      } catch FreshPowerPointWindowSampleError.requestAlreadyInFlight {
        guard !Task.isCancelled, let self else { return }
        self.deferFreshContentSampleAfterProviderBusy(request)
      } catch {
        guard !Task.isCancelled, let self else { return }
        self.exhaustFreshContentSampleEpisode(for: request)
      }
    }
  }

  private func freshContentSampleCandidateIsStructurallyValid(
    _ candidateToken: FreshContentSampleCandidateToken,
    coarseDetectorFingerprint: FrameFingerprint?
  ) -> Bool {
    switch (candidateToken, coarseDetectorFingerprint) {
    case (.coarse, .some(let fingerprint)):
      return fingerprint.isValid
    case (.dense, .none):
      return true
    case (.coarse, .none), (.dense, .some):
      return false
    }
  }

  private func beginFreshContentSample(
    _ request: FreshContentSampleRequest
  ) -> Bool {
    guard freshContentSampleRequestIsCurrent(request),
      var episode = freshContentSampleEpisode,
      episode.candidateToken == request.candidateToken,
      !episode.isExhausted,
      episode.attemptsStarted < 2
    else {
      finishFreshContentSampleRequest(request.requestID, resetEpisode: false)
      return false
    }

    episode.attemptsStarted += 1
    freshContentSampleEpisode = episode
    return true
  }

  private func deferFreshContentSampleAfterProviderBusy(
    _ request: FreshContentSampleRequest
  ) {
    guard freshContentSampleRequestIsCurrent(request),
      var episode = freshContentSampleEpisode,
      episode.candidateToken == request.candidateToken,
      episode.attemptsStarted > 0
    else {
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    // The provider rejected this call before starting another OS screenshot, so
    // it must not consume either of the candidate's two capture attempts. Keep
    // the retry itself bounded in case an older system callback never returns.
    episode.attemptsStarted -= 1
    episode.providerBusyDeferrals += 1
    freshContentSampleEpisode = episode
    guard
      episode.providerBusyDeferrals
        <= Self.maximumFreshContentSampleProviderBusyDeferrals
    else {
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    finishFreshContentSampleRequest(request.requestID, resetEpisode: false)
    scheduleFreshContentSample(
      candidateToken: request.candidateToken,
      anchoredStreamSequenceNumber: request.anchoredStreamSequenceNumber,
      anchoredCoarseFingerprint: request.anchoredCoarseFingerprint,
      coarseDetectorFingerprint: request.coarseDetectorFingerprint
    )
  }

  private func receiveFreshContentSample(
    _ sample: FreshPowerPointWindowSample,
    request: FreshContentSampleRequest
  ) {
    guard freshContentSampleRequestIsCurrent(request),
      sample.requestID == request.requestID,
      sample.captureOperationID == request.captureOperationID,
      sample.identity == request.captureIdentity
    else {
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    let freshFrame: CapturedSlideCanvasFrame
    switch FreshSlideCanvasSamplePreparer.evaluate(
      sample,
      expectedIdentity: request.captureIdentity,
      anchorSequenceNumber: request.anchoredStreamSequenceNumber,
      selection: request.canvasSelection
    ) {
    case .prepared(let preparedFrame):
      freshFrame = preparedFrame
    case .rejected:
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    let beforeConfirmationMachAbsoluteTime = mach_absolute_time()
    guard
      request.evidenceStartedMachAbsoluteTime > 0,
      sample.requestStartedMachAbsoluteTime >= request.evidenceStartedMachAbsoluteTime,
      sample.requestStartedMachAbsoluteTime <= beforeConfirmationMachAbsoluteTime,
      freshFrame.fingerprint.normalizedDifference(
        from: request.anchoredCoarseFingerprint
      ) <= stableFrameDetector.configuration.stableDifferenceThreshold
    else {
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    switch request.candidateToken {
    case .coarse(let candidateToken):
      receiveFreshCoarseCandidateConfirmation(
        freshFrame,
        candidateToken: candidateToken,
        request: request
      )
    case .dense(let candidateToken):
      receiveFreshDenseCandidateConfirmation(
        freshFrame,
        candidateToken: candidateToken,
        request: request
      )
    }
  }

  private func receiveFreshCoarseCandidateConfirmation(
    _ freshFrame: CapturedSlideCanvasFrame,
    candidateToken: StableFrameCandidateToken,
    request: FreshContentSampleRequest
  ) {
    guard
      let coarseDetectorFingerprint = request.coarseDetectorFingerprint,
      let observation = stableFrameDetector.confirmPendingFrame(
        coarseDetectorFingerprint,
        token: candidateToken
      ),
      observation.candidateToken == candidateToken
    else {
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    switch observation.stability {
    case .collecting, .transitioning:
      finishFreshContentSampleRequest(request.requestID, resetEpisode: false)
      scheduleFreshContentSample(
        candidateToken: request.candidateToken,
        anchoredStreamSequenceNumber: request.anchoredStreamSequenceNumber,
        anchoredCoarseFingerprint: request.anchoredCoarseFingerprint,
        coarseDetectorFingerprint: coarseDetectorFingerprint
      )
    case .stable, .significantVisualChange:
      let confirmedMachAbsoluteTime = mach_absolute_time()
      coarseRevisionEvidence = nil
      finishFreshContentSampleRequest(request.requestID, resetEpisode: true)
      recordContentRevision(
        source: .boundedFreshSample,
        evidenceStartedMachAbsoluteTime: request.evidenceStartedMachAbsoluteTime,
        confirmedMachAbsoluteTime: confirmedMachAbsoluteTime
      )
      guard rebaseDenseFingerprintForConfirmedCoarseFrame(freshFrame.contentFingerprint) else {
        return
      }
      latestStableFrame = freshFrame.image
      startSlideAnalysis(
        freshFrame,
        captureSessionID: request.captureOperationID,
        origin: .boundedFreshSample
      )
    case .invalid, .unchanged:
      exhaustFreshContentSampleEpisode(for: request)
    }
  }

  private func receiveFreshDenseCandidateConfirmation(
    _ freshFrame: CapturedSlideCanvasFrame,
    candidateToken: StableContentChangeCandidateToken,
    request: FreshContentSampleRequest
  ) {
    guard
      request.coarseDetectorFingerprint == nil,
      let contentFingerprint = freshFrame.contentFingerprint,
      let observation = stableContentChangeDetector.confirmPendingChange(
        contentFingerprint,
        token: candidateToken
      )
    else {
      exhaustFreshContentSampleEpisode(for: request)
      return
    }

    switch observation.state {
    case .contentChangePending:
      finishFreshContentSampleRequest(request.requestID, resetEpisode: false)
      scheduleFreshContentSample(
        candidateToken: request.candidateToken,
        anchoredStreamSequenceNumber: request.anchoredStreamSequenceNumber,
        anchoredCoarseFingerprint: request.anchoredCoarseFingerprint,
        coarseDetectorFingerprint: nil
      )
    case .contentChanged:
      finishFreshContentSampleRequest(request.requestID, resetEpisode: true)
      denseRevisionEvidence = nil
      recordContentRevision(
        source: .boundedFreshSample,
        evidenceStartedMachAbsoluteTime: request.evidenceStartedMachAbsoluteTime,
        confirmedMachAbsoluteTime: mach_absolute_time()
      )
      latestStableFrame = freshFrame.image
      startSlideAnalysis(
        freshFrame,
        captureSessionID: request.captureOperationID,
        origin: .boundedFreshSample
      )
    case .invalid, .collectingBaseline, .baselineEstablished, .unchanged:
      exhaustFreshContentSampleEpisode(for: request)
    }
  }

  private func freshContentSampleRequestIsCurrent(
    _ request: FreshContentSampleRequest
  ) -> Bool {
    guard
      currentFreshContentSampleRequest?.requestID == request.requestID,
      evidenceStartedMachAbsoluteTime(for: request.candidateToken)
        == request.evidenceStartedMachAbsoluteTime,
      freshContentSampleCandidateIsStructurallyValid(
        request.candidateToken,
        coarseDetectorFingerprint: request.coarseDetectorFingerprint
      ),
      captureStatus == .capturing,
      activeCaptureSessionID == request.captureOperationID,
      activeCaptureIdentity == request.captureIdentity,
      activeCaptureWindowID == request.captureIdentity.windowID,
      activeCaptureSelectionIsConsistent,
      lastAcceptedCaptureSequenceNumber == request.anchoredStreamSequenceNumber,
      !captureContentRequiresNewFrame,
      latestEligibleWindowFrame?.sequenceNumber == request.anchoredStreamSequenceNumber,
      latestEligibleWindowFrame?.windowID == request.captureIdentity.windowID,
      slideCanvasStatus == .confirmed,
      slideCanvasGeneration == request.slideCanvasGeneration,
      confirmedSlideCanvasSelection == request.canvasSelection,
      slideIdentityGeneration == request.slideIdentityGeneration,
      slideIdentityState == request.slideIdentityState,
      slideIdentityFrameSyncState == request.slideIdentityFrameSyncState,
      !slideIdentityQuarantineActive,
      !slideIdentityFrameGate.requiresFreshFrame,
      freshContentSampleEpisode?.candidateToken == request.candidateToken
    else {
      return false
    }
    return true
  }

  private func finishFreshContentSampleRequest(
    _ requestID: FreshSampleRequestID,
    resetEpisode: Bool
  ) {
    guard currentFreshContentSampleRequest?.requestID == requestID else { return }
    currentFreshContentSampleRequest = nil
    freshContentSampleTask = nil
    if resetEpisode {
      freshContentSampleEpisode = nil
    }
  }

  private func exhaustFreshContentSampleEpisode(
    for request: FreshContentSampleRequest
  ) {
    guard currentFreshContentSampleRequest?.requestID == request.requestID else { return }
    currentFreshContentSampleRequest = nil
    freshContentSampleTask = nil
    guard var episode = freshContentSampleEpisode,
      episode.candidateToken == request.candidateToken
    else {
      return
    }
    episode.isExhausted = true
    freshContentSampleEpisode = episode
  }

  private func cancelFreshContentSampling(resetEpisode: Bool) {
    freshContentSampleTask?.cancel()
    freshContentSampleTask = nil
    currentFreshContentSampleRequest = nil
    if resetEpisode {
      freshContentSampleEpisode = nil
    }
  }

  private func rebaseDenseFingerprintForConfirmedCoarseFrame(
    _ contentFingerprint: ContentFingerprint?
  ) -> Bool {
    cancelFreshContentSampling(resetEpisode: true)
    guard
      let contentFingerprint,
      stableContentChangeDetector.rebase(to: contentFingerprint)
    else {
      resetDenseContentChangeDetector()
      invalidateSlideAnalysisForVisualFreshness()
      return false
    }
    denseRevisionEvidence = nil
    return true
  }

  private func stopCaptureProviders(operationID: CaptureOperationID) async {
    inFlightCaptureStopCount += 1
    if let managedSlideShowTransaction {
      await managedSlideShowTransaction.stop()
      releaseManagedSlideShowTransactionWhenSafe(managedSlideShowTransaction)
    } else {
      await windowCapture.stop(operationID: operationID)
    }
    await slideIdentityProvider.stop(operationID: operationID)
    inFlightCaptureStopCount -= 1
  }

  private func releaseManagedSlideShowTransactionWhenSafe(
    _ transaction: ManagedSlideShowTransactionCoordinator
  ) {
    managedSlideShowTransactionReleaseTask?.cancel()
    managedSlideShowTransactionReleaseTask = Task { @MainActor [weak self] in
      await transaction.waitUntilReplacementIsSafe()
      guard !Task.isCancelled, let self,
        self.managedSlideShowTransaction === transaction
      else { return }
      self.managedSlideShowTransaction = nil
      self.managedSlideShowTransactionReleaseTask = nil
    }
  }

  private func receive(
    _ analysis: SlideVisualAnalysis,
    frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int,
    requestSlideIdentityGeneration: Int,
    requestSlideCanvasGeneration: Int,
    origin: SlideAnalysisOrigin
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      requestSlideIdentityGeneration == slideIdentityGeneration,
      requestSlideCanvasGeneration == slideCanvasGeneration,
      frame.windowID == activeCaptureWindowID,
      activeCaptureSelectionIsConsistent
    else {
      return
    }
    latestSlideAnalysis = analysis
    slideAnalysisStatus = .ready
    slideAnalysisNeedsRefresh = false
    latestCompletedAnalysisGeneration = requestGeneration
    slideAnalysisTask = nil
    scheduleAutomaticTranscriptionResumeIfReady()
    if origin == .continuousStream {
      renderAlignedOverlayIfPossible()
    }
  }

  private func handleSlideAnalysisError(
    _ message: String,
    frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int,
    requestSlideIdentityGeneration: Int,
    requestSlideCanvasGeneration: Int,
    origin: SlideAnalysisOrigin
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      requestSlideIdentityGeneration == slideIdentityGeneration,
      requestSlideCanvasGeneration == slideCanvasGeneration,
      frame.windowID == activeCaptureWindowID,
      activeCaptureSelectionIsConsistent
    else {
      return
    }
    slideAnalysisStatus = .error(message)
    latestCompletedAnalysisGeneration = nil
    slideAnalysisTask = nil
    if origin == .continuousStream {
      invalidateProductionOverlayLease()
    }
  }

  private func handleSlideAnalysisCancellation(
    frame: CapturedSlideCanvasFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int,
    requestSlideIdentityGeneration: Int,
    requestSlideCanvasGeneration: Int,
    origin: SlideAnalysisOrigin
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      requestSlideIdentityGeneration == slideIdentityGeneration,
      requestSlideCanvasGeneration == slideCanvasGeneration,
      frame.windowID == activeCaptureWindowID,
      activeCaptureSelectionIsConsistent
    else {
      return
    }
    slideAnalysisStatus = .idle
    latestCompletedAnalysisGeneration = nil
    slideAnalysisTask = nil
    if origin == .continuousStream {
      invalidateProductionOverlayLease()
    }
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

    let productionOverlayIsEligible =
      productionOverlayEligibilityProvider.allowsProductionOverlay(
        for: activeCaptureIdentity,
        screenGeometry: captureScreenGeometry
      )
    productionOverlayEligibilityState =
      productionOverlayIsEligible ? .allowed : .blocked
    guard productionOverlayIsEligible else {
      invalidateProductionOverlayLease(resetEligibility: false)
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
    productionOverlayPresentationState = .renderRequested
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
    productionOverlayPresentationState = .hidden
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

  private func invalidateProductionOverlayLease(
    hidePanel: Bool = true,
    resetEligibility: Bool = true
  ) {
    productionOverlayLeaseGeneration &+= 1
    productionOverlayLeaseIsValid = false
    productionOverlayLeaseScheduler.cancel()
    if resetEligibility {
      productionOverlayEligibilityState = .notEvaluated
    }
    productionOverlayPresentationState = .hidden
    if hidePanel {
      hideProductionOverlayPanel()
    }
  }

  private func handleProductionOverlayUnsafeEvent() {
    guard
      !overlayDemoSceneIsLoaded,
      captureStatus == .capturing,
      productionOverlayEligibilityState != .notEvaluated
        || productionOverlayLeaseIsValid
        || productionOverlayPresentationState == .renderRequested
        || renderedProductionOverlayState != nil
    else {
      return
    }
    productionOverlayEligibilityState = .blocked
    invalidateProductionOverlayLease(resetEligibility: false)
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
      activeCaptureSelectionIsConsistent
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
    cancelFreshContentSampling(resetEpisode: true)
    invalidateTranscriptionContext(preserveUserRequest: true)
    slideIdentityGeneration += 1
    latestEligibleWindowFrame = nil
    resetVisualDetectors()
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

  private var activeCaptureSelectionIsConsistent: Bool {
    activeCaptureUsesManagedSlideShow || activeCaptureIdentity == selectedWindow?.identity
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

  private func scheduleAutomaticTranscriptionResumeIfReady() {
    guard
      transcriptionRequestedByUser,
      !transcriptionOperationGate.hasActiveOperation,
      automaticTranscriptionResumeTask == nil,
      captureStatus == .capturing,
      slideCanvasStatus == .confirmed,
      slideIdentityState == .identified,
      !slideIdentityQuarantineActive,
      !slideIdentityFrameGate.requiresFreshFrame,
      slideAnalysisStatus == .ready,
      !slideAnalysisNeedsRefresh,
      latestCompletedAnalysisGeneration == analysisGeneration
    else { return }

    automaticTranscriptionResumeTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.automaticTranscriptionResumeTask = nil }
      guard
        self.transcriptionRequestedByUser,
        !self.transcriptionOperationGate.hasActiveOperation,
        self.captureStatus == .capturing,
        self.slideCanvasStatus == .confirmed,
        self.slideIdentityState == .identified,
        !self.slideIdentityQuarantineActive,
        !self.slideIdentityFrameGate.requiresFreshFrame,
        self.slideAnalysisStatus == .ready,
        !self.slideAnalysisNeedsRefresh,
        self.latestCompletedAnalysisGeneration == self.analysisGeneration
      else { return }
      await self.startTranscriptionOperation()
    }
  }

  private func invalidateTranscriptionContext(
    forceReadyStatus: Bool = false,
    preserveUserRequest: Bool = false
  ) {
    automaticTranscriptionResumeTask?.cancel()
    automaticTranscriptionResumeTask = nil
    if !preserveUserRequest {
      transcriptionRequestedByUser = false
    }
    let activeOperationID = transcriptionOperationGate.activeOperationID
    transcriptionOperationGate.invalidate()
    if let activeOperationID {
      speechProvider.stop(operationID: activeOperationID)
    }
    clearLiveTranscript()
    transcriptionLifecycleState =
      preserveUserRequest && transcriptionRequestedByUser ? .waitingForContext : .idle
    if forceReadyStatus || status == .listening || status == .finalizingTranscription {
      status = .ready
    }
  }

  private func clearLiveTranscript() {
    liveTranscript = ""
    liveTranscriptPhase = .empty
  }
}
