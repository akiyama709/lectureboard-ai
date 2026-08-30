import AVFoundation
import AppKit
import Combine
import CoreGraphics
import LectureBoardCore
import Speech

protocol PowerPointWindowScanning: Sendable {
  func scan() async throws -> [PowerPointWindowDescriptor]
}

extension PowerPointWindowScanner: PowerPointWindowScanning {}

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
  @Published private(set) var contentRevisionCount = 0
  @Published private(set) var latestStableFrame: CGImage?
  @Published private(set) var slideAnalysisStatus: SlideAnalysisStatus = .idle
  @Published private(set) var latestSlideAnalysis: SlideVisualAnalysis?

  let permissionService: PermissionService
  private let scanner: any PowerPointWindowScanning
  private let overlayController = OverlayWindowController()
  private let speechProvider = AppleSpeechRecognizerProvider()
  private let windowCapture: any PowerPointWindowCapturing
  private let slideVisionAnalyzer: any SlideVisualAnalyzing
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
  private var analysisGeneration = 0
  private var slideAnalysisTask: Task<Void, Never>?
  private var transcriptSegments: [TranscriptSegment] = []
  private var boardIntents: [BoardIntent] = []

  init(
    permissionService: PermissionService = PermissionService(),
    windowCapture: any PowerPointWindowCapturing = PowerPointWindowCapture(),
    scanner: any PowerPointWindowScanning = PowerPointWindowScanner(),
    slideVisionAnalyzer: any SlideVisualAnalyzing = SlideVisionAnalyzer()
  ) {
    self.permissionService = permissionService
    self.windowCapture = windowCapture
    self.scanner = scanner
    self.slideVisionAnalyzer = slideVisionAnalyzer
  }

  var selectedWindow: PowerPointWindowDescriptor? {
    guard let selectedPowerPointWindowID else { return nil }
    return PowerPointWindowIdentityResolver.uniqueDescriptor(
      windowID: selectedPowerPointWindowID,
      in: powerPointWindows
    )
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
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    lastAcceptedCaptureSequenceNumber = nil
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
        stableFrameDetector.reset()
        stableContentChangeDetector.reset()
        lastAcceptedCaptureSequenceNumber = nil
        resetSlideAnalysis()
        captureStatus = .stopped
        await windowCapture.stop(operationID: stopOperationID)
        return
      }
      captureStatus = .capturing
    } catch {
      guard activeCaptureSessionID == operationID else { return }
      activeCaptureSessionID = nil
      activeCaptureWindowID = nil
      activeCaptureIdentity = nil
      captureStatus = .error(error.localizedDescription)
      stableFrameDetector.reset()
      stableContentChangeDetector.reset()
      lastAcceptedCaptureSequenceNumber = nil
      resetSlideAnalysis()
      await windowCapture.stop(operationID: nextCaptureOperationID())
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
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    lastAcceptedCaptureSequenceNumber = nil
    resetSlideAnalysis()
    captureStatus = .stopped
    await windowCapture.stop(operationID: operationID)
    return operationID
  }

  func showOverlayDemo() {
    boardScene = DemoBoardSceneFactory.make(language: selectedLanguage)
    overlayController.show(scene: boardScene, style: digitalInkStyle)
    status = .overlayVisible
  }

  func hideOverlay() {
    overlayController.hide()
    status = .ready
  }

  func startTranscription() async {
    do {
      try await speechProvider.start(language: selectedLanguage) { [weak self] segment in
        guard let self else { return }
        self.receive(segment)
      }
      status = .listening
    } catch {
      status = .error(error.localizedDescription)
    }
  }

  func stopTranscription() {
    speechProvider.stop()
    status = .ready
  }

  func receive(_ segment: TranscriptSegment) {
    liveTranscript = segment.text
    guard segment.isFinal else { return }

    transcriptSegments.append(segment)
    let fallbackTitle =
      selectedLanguage.rawValue.hasPrefix("ja") ? "現在のスライド" : "Current slide"
    let analysisTitle = latestSlideAnalysis?.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title =
      if let analysisTitle, !analysisTitle.isEmpty {
        analysisTitle
      } else {
        fallbackTitle
      }
    let slide = SlideContext(
      slideNumber: boardScene.slideNumber,
      title: title,
      textBlocks: latestSlideAnalysis?.textBlocks ?? [],
      speakerNotes: "",
      occupiedRegions: latestSlideAnalysis?.occupiedRegions
        ?? [NormalizedRect(x: 0.03, y: 0.05, width: 0.62, height: 0.90)],
      dwellTime: 40,
      languages: [selectedLanguage]
    )

    let proposals = boardEngine.propose(
      slide: slide,
      recentSegments: Array(transcriptSegments.suffix(8)),
      existingIntents: boardIntents
    )
    guard !proposals.isEmpty else { return }

    boardIntents.append(contentsOf: proposals)
    boardScene = sceneComposer.append(
      intents: proposals,
      to: boardScene,
      slideOccupied: slide.occupiedRegions
    )
    overlayController.update(scene: boardScene, style: digitalInkStyle)
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
    let observation = stableFrameDetector.ingest(frame.fingerprint)
    latestDifferenceFromStableFrame = observation.differenceFromStableFrame

    switch observation.stability {
    case .stable:
      stableFrameCount += 1
      if observation.differenceFromStableFrame != nil {
        contentRevisionCount += 1
      }
      if let contentFingerprint = frame.contentFingerprint {
        stableContentChangeDetector.rebase(to: contentFingerprint)
      } else {
        stableContentChangeDetector.reset()
      }
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: sessionID)
    case .significantVisualChange:
      if let contentFingerprint = frame.contentFingerprint {
        stableContentChangeDetector.rebase(to: contentFingerprint)
      } else {
        stableContentChangeDetector.reset()
      }
      stableFrameCount += 1
      contentRevisionCount += 1
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureSessionID: sessionID)
    case .unchanged:
      receiveContentFingerprintIfAvailable(frame, captureSessionID: sessionID)
    case .invalid, .collecting, .transitioning:
      stableContentChangeDetector.discardPendingChange()
    }
  }

  private func handleCaptureError(
    _ message: String,
    sessionID: CaptureOperationID
  ) async {
    guard sessionID == activeCaptureSessionID else { return }
    let stopOperationID = nextCaptureOperationID()
    activeCaptureSessionID = nil
    activeCaptureWindowID = nil
    activeCaptureIdentity = nil
    stableFrameDetector.reset()
    stableContentChangeDetector.reset()
    lastAcceptedCaptureSequenceNumber = nil
    resetSlideAnalysis()
    captureStatus = .error(message)
    await windowCapture.stop(operationID: stopOperationID)
  }

  private func startSlideAnalysis(
    _ frame: CapturedPowerPointFrame,
    captureSessionID: CaptureOperationID
  ) {
    analysisGeneration += 1
    let requestGeneration = analysisGeneration
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
          requestGeneration: requestGeneration
        )
      } catch is CancellationError {
        guard let self else { return }
        handleSlideAnalysisCancellation(
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration
        )
      } catch {
        guard let self else { return }
        handleSlideAnalysisError(
          error.localizedDescription,
          frame: frame,
          captureSessionID: captureSessionID,
          requestGeneration: requestGeneration
        )
      }
    }
  }

  private func receiveContentFingerprintIfAvailable(
    _ frame: CapturedPowerPointFrame,
    captureSessionID: CaptureOperationID
  ) {
    guard let contentFingerprint = frame.contentFingerprint else {
      stableContentChangeDetector.discardPendingChange()
      return
    }
    let observation = stableContentChangeDetector.ingest(contentFingerprint)
    guard observation.state == .contentChanged else { return }

    contentRevisionCount += 1
    latestStableFrame = frame.image
    startSlideAnalysis(frame, captureSessionID: captureSessionID)
  }

  private func receive(
    _ analysis: SlideVisualAnalysis,
    frame: CapturedPowerPointFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    latestSlideAnalysis = analysis
    slideAnalysisStatus = .ready
    slideAnalysisTask = nil
  }

  private func handleSlideAnalysisError(
    _ message: String,
    frame: CapturedPowerPointFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    slideAnalysisStatus = .error(message)
    slideAnalysisTask = nil
  }

  private func handleSlideAnalysisCancellation(
    frame: CapturedPowerPointFrame,
    captureSessionID: CaptureOperationID,
    requestGeneration: Int
  ) {
    guard captureSessionID == activeCaptureSessionID,
      requestGeneration == analysisGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    slideAnalysisStatus = .idle
    slideAnalysisTask = nil
  }

  private func resetSlideAnalysis() {
    analysisGeneration += 1
    slideAnalysisTask?.cancel()
    slideAnalysisTask = nil
    latestSlideAnalysis = nil
    slideAnalysisStatus = .idle
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
}
