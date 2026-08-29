import AVFoundation
import AppKit
import Combine
import CoreGraphics
import LectureBoardCore
import Speech

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
  @Published private(set) var stableFrameCount = 0
  @Published private(set) var slideChangeCount = 0
  @Published private(set) var latestStableFrame: CGImage?
  @Published private(set) var slideAnalysisStatus: SlideAnalysisStatus = .idle
  @Published private(set) var latestSlideAnalysis: SlideVisualAnalysis?

  let permissionService = PermissionService()
  private let scanner = PowerPointWindowScanner()
  private let overlayController = OverlayWindowController()
  private let speechProvider = AppleSpeechRecognizerProvider()
  private let windowCapture = PowerPointWindowCapture()
  private let slideVisionAnalyzer = SlideVisionAnalyzer()
  private let boardEngine = ContextualBoardEngine()
  private let sceneComposer = BoardSceneComposer()
  private var stableFrameDetector = StableFrameDetector()
  private var captureGeneration = 0
  private var analysisGeneration = 0
  private var slideAnalysisTask: Task<Void, Never>?
  private var transcriptSegments: [TranscriptSegment] = []
  private var boardIntents: [BoardIntent] = []

  var selectedWindow: PowerPointWindowDescriptor? {
    powerPointWindows.first { $0.id == selectedPowerPointWindowID }
  }

  func requestPermissions() async {
    _ = permissionService.requestScreenCapture()
    _ = await permissionService.requestMicrophone()
    _ = await permissionService.requestSpeechRecognition()
  }

  func refreshPowerPointWindows() async {
    status = .scanning
    do {
      let windows = try await scanner.scan()
      let previousSelection = selectedPowerPointWindowID
      powerPointWindows = windows

      if let previousSelection,
        windows.contains(where: { $0.id == previousSelection })
      {
        selectedPowerPointWindowID = previousSelection
      } else {
        await stopWindowCapture()
        selectedPowerPointWindowID = windows.first?.id
      }
      status = .ready
    } catch {
      status = .error(error.localizedDescription)
    }
  }

  func startWindowCapture() async {
    guard let selectedPowerPointWindowID else {
      captureStatus = .error(
        NSLocalizedString("error.captureWindowUnavailable", comment: "")
      )
      return
    }

    captureGeneration += 1
    let generation = captureGeneration
    captureStatus = .starting
    capturedFrameCount = 0
    stableFrameCount = 0
    slideChangeCount = 0
    latestStableFrame = nil
    stableFrameDetector.reset()
    resetSlideAnalysis()

    do {
      try await windowCapture.start(
        windowID: selectedPowerPointWindowID,
        onFrame: { [weak self] frame in
          Task { @MainActor [weak self] in
            self?.receive(frame, generation: generation)
          }
        },
        onError: { [weak self] message in
          Task { @MainActor [weak self] in
            await self?.handleCaptureError(message, generation: generation)
          }
        }
      )
      guard generation == captureGeneration,
        selectedPowerPointWindowID == self.selectedPowerPointWindowID
      else {
        await windowCapture.stop()
        return
      }
      captureStatus = .capturing
    } catch {
      guard generation == captureGeneration else { return }
      captureStatus = .error(error.localizedDescription)
    }
  }

  func stopWindowCapture() async {
    captureGeneration += 1
    await windowCapture.stop()
    stableFrameDetector.reset()
    resetSlideAnalysis()
    captureStatus = .stopped
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

  private func receive(_ frame: CapturedPowerPointFrame, generation: Int) {
    guard generation == captureGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    capturedFrameCount = Int(frame.sequenceNumber)
    let observation = stableFrameDetector.ingest(frame.fingerprint)

    switch observation.stability {
    case .stable:
      stableFrameCount += 1
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureGeneration: generation)
    case .slideChanged:
      stableFrameCount += 1
      slideChangeCount += 1
      latestStableFrame = frame.image
      startSlideAnalysis(frame, captureGeneration: generation)
    case .invalid, .collecting, .unchanged, .transitioning:
      break
    }
  }

  private func handleCaptureError(_ message: String, generation: Int) async {
    guard generation == captureGeneration else { return }
    captureGeneration += 1
    await windowCapture.stop()
    stableFrameDetector.reset()
    resetSlideAnalysis()
    captureStatus = .error(message)
  }

  private func startSlideAnalysis(
    _ frame: CapturedPowerPointFrame,
    captureGeneration: Int
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
          captureGeneration: captureGeneration,
          requestGeneration: requestGeneration
        )
      } catch is CancellationError {
        return
      } catch {
        guard let self else { return }
        handleSlideAnalysisError(
          error.localizedDescription,
          frame: frame,
          captureGeneration: captureGeneration,
          requestGeneration: requestGeneration
        )
      }
    }
  }

  private func receive(
    _ analysis: SlideVisualAnalysis,
    frame: CapturedPowerPointFrame,
    captureGeneration: Int,
    requestGeneration: Int
  ) {
    guard captureGeneration == self.captureGeneration,
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
    captureGeneration: Int,
    requestGeneration: Int
  ) {
    guard captureGeneration == self.captureGeneration,
      requestGeneration == analysisGeneration,
      frame.windowID == selectedPowerPointWindowID
    else {
      return
    }
    slideAnalysisStatus = .error(message)
    slideAnalysisTask = nil
  }

  private func resetSlideAnalysis() {
    analysisGeneration += 1
    slideAnalysisTask?.cancel()
    slideAnalysisTask = nil
    latestSlideAnalysis = nil
    slideAnalysisStatus = .idle
  }
}
