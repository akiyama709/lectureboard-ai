import AVFoundation
import AppKit
import Combine
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

  @Published var status: Status = .ready
  @Published var powerPointWindows: [PowerPointWindowDescriptor] = []
  @Published var selectedPowerPointWindowID: CGWindowID?
  @Published var selectedLanguage: LanguageTag = .japanese
  @Published var liveTranscript = ""
  @Published var boardScene = BoardScene(slideNumber: 1)
  @Published var digitalInkStyle = DigitalInkStyle.clean

  let permissionService = PermissionService()
  private let scanner = PowerPointWindowScanner()
  private let overlayController = OverlayWindowController()
  private let speechProvider = AppleSpeechRecognizerProvider()
  private let boardEngine = ContextualBoardEngine()
  private let sceneComposer = BoardSceneComposer()
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
      powerPointWindows = try await scanner.scan()
      if selectedPowerPointWindowID == nil {
        selectedPowerPointWindowID = powerPointWindows.first?.id
      }
      status = .ready
    } catch {
      status = .error(error.localizedDescription)
    }
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
    let slide = SlideContext(
      slideNumber: boardScene.slideNumber,
      title: selectedLanguage.rawValue.hasPrefix("ja") ? "現在のスライド" : "Current slide",
      textBlocks: [],
      speakerNotes: "",
      occupiedRegions: [NormalizedRect(x: 0.03, y: 0.05, width: 0.62, height: 0.90)],
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
}
