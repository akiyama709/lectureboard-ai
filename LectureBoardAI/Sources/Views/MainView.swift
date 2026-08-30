import CoreGraphics
import LectureBoardCore
import SwiftUI

struct MainView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationSplitView {
      List {
        Section("app.title") {
          Label("nav.powerPoint", systemImage: "rectangle.on.rectangle")
          Label("nav.contextEngine", systemImage: "brain.head.profile")
          Label("nav.digitalInk", systemImage: "pencil.and.scribble")
        }
      }
      .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          prototypeNotice
          permissions
          powerPointSelection
          captureMonitor
          languageAndStyle
          controls
          transcript
          BoardPreviewView(scene: model.boardScene, style: model.digitalInkStyle)
        }
        .padding(28)
      }
    }
    .task {
      await performScreenCaptureSetupAction(
        ScreenCaptureSetupPolicy.action(
          for: .viewAppeared(
            preflightGranted: model.permissionService.screenCaptureAccessGranted
          )
        )
      )
    }
    .onDisappear {
      Task { await model.stopWindowCapture() }
    }
  }

  @MainActor
  private func performScreenCaptureSetupAction(
    _ action: ScreenCaptureSetupPolicy.Action
  ) async {
    switch action {
    case .none:
      return
    case .requestScreenCapturePermission:
      let granted = model.requestScreenCapturePermission()
      await performScreenCaptureSetupAction(
        ScreenCaptureSetupPolicy.action(
          for: .permissionRequestCompleted(granted: granted)
        )
      )
    case .refreshPowerPointWindows:
      await model.refreshPowerPointWindows()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("app.title")
        .font(.largeTitle.bold())
      Text("app.subtitle")
        .font(.title3)
        .foregroundStyle(.secondary)
    }
  }

  private var prototypeNotice: some View {
    Label("status.prototype", systemImage: "hammer")
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
  }

  private var permissions: some View {
    GroupBox("setup.permissions") {
      HStack(spacing: 18) {
        PermissionBadge(
          titleKey: "setup.screen",
          granted: model.permissionService.screenCaptureAccessGranted
        )
        PermissionBadge(
          titleKey: "setup.microphone",
          granted: model.permissionService.microphoneGranted
        )
        PermissionBadge(
          titleKey: "setup.speech",
          granted: model.permissionService.speechRecognitionGranted
        )
        Spacer()
        Button("setup.requestScreen") {
          Task {
            await performScreenCaptureSetupAction(
              ScreenCaptureSetupPolicy.action(for: .permissionButtonPressed)
            )
          }
        }
      }
      .padding(.vertical, 8)
    }
  }

  private var powerPointSelection: some View {
    GroupBox("setup.powerPoint") {
      VStack(alignment: .leading, spacing: 10) {
        if model.powerPointWindows.isEmpty {
          Text("setup.noPowerPoint")
            .foregroundStyle(.secondary)
        } else {
          Picker("setup.powerPointWindow", selection: $model.selectedPowerPointWindowID) {
            ForEach(model.powerPointWindows) { window in
              Text(window.title.isEmpty ? window.applicationName : window.title)
                .tag(Optional(window.id))
            }
          }
          .labelsHidden()
          .frame(maxWidth: 500)
          .onChange(of: model.selectedPowerPointWindowID) { oldValue, newValue in
            guard oldValue != newValue else { return }
            guard let sessionID = model.activeCaptureSessionID(for: oldValue) else {
              return
            }
            Task {
              await model.stopWindowCapture(ifCurrentSessionID: sessionID)
            }
          }
        }

        HStack(spacing: 10) {
          Button("setup.refresh") {
            Task {
              await performScreenCaptureSetupAction(
                ScreenCaptureSetupPolicy.action(
                  for: .refreshButtonPressed(
                    preflightGranted: model.permissionService.screenCaptureAccessGranted
                  )
                )
              )
            }
          }
          Button("capture.start") {
            Task { await model.startWindowCapture() }
          }
          .disabled(
            !CaptureControlPolicy.canStart(
              screenCaptureAccessGranted:
                model.permissionService.screenCaptureAccessGranted,
              hasSelectedWindow: model.selectedWindow != nil,
              captureStatus: model.captureStatus
            )
          )
          Button("capture.stop") {
            Task { await model.stopWindowCapture() }
          }
          .disabled(model.captureStatus == .stopped)
        }
      }
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var captureMonitor: some View {
    GroupBox("capture.title") {
      VStack(alignment: .leading, spacing: 12) {
        captureStatusLabel
        slideAnalysisStatusLabel

        HStack(spacing: 24) {
          LabeledContent("capture.frames", value: "\(model.capturedFrameCount)")
          LabeledContent("capture.stableFrames", value: "\(model.stableFrameCount)")
          LabeledContent("capture.slideChanges", value: "\(model.slideChangeCount)")
        }

        HStack(spacing: 24) {
          LabeledContent(
            "analysis.textBlocks",
            value: "\(model.latestSlideAnalysis?.textBlocks.count ?? 0)"
          )
          LabeledContent(
            "analysis.graphicRegions",
            value: "\(model.latestSlideAnalysis?.graphicRegions.count ?? 0)"
          )
          LabeledContent(
            "analysis.occupiedRegions",
            value: "\(model.latestSlideAnalysis?.occupiedRegions.count ?? 0)"
          )
        }

        if let title = model.latestSlideAnalysis?.title, !title.isEmpty {
          LabeledContent("analysis.titleCandidate", value: title)
        }

        if let image = model.latestStableFrame {
          AnalyzedSlidePreview(
            image: image,
            occupiedRegions: model.latestSlideAnalysis?.occupiedRegions ?? []
          )
        } else {
          Text("capture.noStableFrame")
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var captureStatusLabel: some View {
    switch model.captureStatus {
    case .stopped:
      Label("capture.status.stopped", systemImage: "stop.circle")
        .foregroundStyle(.secondary)
    case .starting:
      Label("capture.status.starting", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case .capturing:
      Label("capture.status.capturing", systemImage: "record.circle")
        .foregroundStyle(.green)
    case .error(let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }

  @ViewBuilder
  private var slideAnalysisStatusLabel: some View {
    switch model.slideAnalysisStatus {
    case .idle:
      Label("analysis.status.idle", systemImage: "viewfinder")
        .foregroundStyle(.secondary)
    case .analyzing:
      Label("analysis.status.analyzing", systemImage: "text.viewfinder")
        .foregroundStyle(.secondary)
    case .ready:
      Label("analysis.status.ready", systemImage: "checkmark.circle")
        .foregroundStyle(.green)
    case .error(let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }

  private var languageAndStyle: some View {
    HStack(alignment: .top, spacing: 18) {
      GroupBox("setup.language") {
        Picker("setup.language", selection: $model.selectedLanguage) {
          Text("setup.japanese").tag(LanguageTag.japanese)
          Text("setup.english").tag(LanguageTag.englishUS)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 8)
      }

      GroupBox("style.title") {
        Picker("style.title", selection: $model.digitalInkStyle.preset) {
          Text("style.clean").tag(DigitalInkStyle.Preset.clean)
          Text("style.handwritten").tag(DigitalInkStyle.Preset.handwritten)
        }
        .onChange(of: model.digitalInkStyle.preset) { _, preset in
          model.digitalInkStyle = preset == .clean ? .clean : .handwritten
        }
        .labelsHidden()
        .padding(.vertical, 8)
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 12) {
      Button("setup.overlay") { model.showOverlayDemo() }
      Button("setup.stop") { model.hideOverlay() }
      Divider().frame(height: 24)
      Button("setup.transcription") {
        Task { await model.startTranscription() }
      }
      Button("setup.transcriptionStop") { model.stopTranscription() }
    }
    .buttonStyle(.bordered)
  }

  private var transcript: some View {
    GroupBox("transcript.live") {
      Text(model.liveTranscript.isEmpty ? "—" : model.liveTranscript)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .textSelection(.enabled)
        .padding(.vertical, 8)
    }
  }
}

private struct AnalyzedSlidePreview: View {
  let image: CGImage
  let occupiedRegions: [NormalizedRect]

  var body: some View {
    ZStack(alignment: .topLeading) {
      Image(decorative: image, scale: 1)
        .resizable()
        .scaledToFit()

      GeometryReader { proxy in
        ForEach(occupiedRegions.indices, id: \.self) { index in
          let region = occupiedRegions[index]
          Rectangle()
            .fill(.red.opacity(0.08))
            .stroke(.red.opacity(0.85), lineWidth: 1.5)
            .frame(
              width: region.width * proxy.size.width,
              height: region.height * proxy.size.height
            )
            .position(
              x: (region.x + region.width / 2) * proxy.size.width,
              y: (region.y + region.height / 2) * proxy.size.height
            )
        }
      }
    }
    .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: 240)
    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

private struct PermissionBadge: View {
  let titleKey: LocalizedStringKey
  let granted: Bool

  var body: some View {
    Label(titleKey, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
      .foregroundStyle(granted ? Color.green : Color.secondary)
  }
}
