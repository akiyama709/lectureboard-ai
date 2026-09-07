import AppKit
import CoreGraphics
import LectureBoardCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var sessionExportError: String?

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
          supportedWorkflowNotice
          permissions
          powerPointSelection
          captureMonitor
          languageAndStyle
          controls
          runtimeDiagnostics
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
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { @MainActor in
        model.recheckScreenCapturePermission()
        await performScreenCaptureSetupAction(
          ScreenCaptureSetupPolicy.action(
            for: .sceneBecameActive(
              preflightGranted: model.permissionService.screenCaptureAccessGranted
            )
          )
        )
      }
    }
    .onDisappear {
      Task { await model.stopWindowCapture() }
    }
    .alert("session.export.error", isPresented: exportErrorIsPresented) {
      Button("common.ok", role: .cancel) {}
    } message: {
      Text(sessionExportError ?? "")
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
      model.recheckScreenCapturePermission()
      await performScreenCaptureSetupAction(
        ScreenCaptureSetupPolicy.action(
          for: .permissionRequestCompleted(granted: granted)
        )
      )
    case .refreshPowerPointWindows:
      await model.refreshPowerPointWindows()
    case .refreshPowerPointWindowsAfterSceneActivation:
      await model.refreshPowerPointWindowsAfterSceneActivation()
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

  private var supportedWorkflowNotice: some View {
    Label("status.supportedWorkflow", systemImage: "checklist")
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
  }

  private var permissions: some View {
    let screenCaptureAccessGranted = model.permissionService.screenCaptureAccessGranted

    return GroupBox("setup.permissions") {
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
        if ScreenCaptureSetupPolicy.showsPermissionButton(
          preflightGranted: screenCaptureAccessGranted
        ) {
          Button("setup.requestScreen") {
            Task {
              await performScreenCaptureSetupAction(
                ScreenCaptureSetupPolicy.action(for: .permissionButtonPressed)
              )
            }
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
          .disabled(
            !ScreenCaptureSetupPolicy.enablesWindowRefresh(
              preflightGranted: model.permissionService.screenCaptureAccessGranted
            )
          )
          Button("capture.managedStart") {
            Task { await model.startManagedSlideShowCapture() }
          }
          .buttonStyle(.borderedProminent)
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
        Text("capture.managedStart.explanation")
          .font(.footnote)
          .foregroundStyle(.secondary)

        DisclosureGroup("capture.diagnostic.title") {
          VStack(alignment: .leading, spacing: 8) {
            Button("capture.diagnostic.start") {
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
            Text("capture.diagnostic.explanation")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.top, 6)
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
        slideIdentityStatusLabel
        slideIdentityFrameSyncStatusLabel
        slideCanvasStatusLabel

        HStack(spacing: 24) {
          LabeledContent(
            "capture.slideIdentitySamples",
            value: "\(model.slideIdentitySampleCount)"
          )
          LabeledContent(
            "capture.slideIdentityInterruptions",
            value: "\(model.slideIdentityContinuityBreakCount)"
          )
        }

        HStack(spacing: 24) {
          LabeledContent("capture.frames", value: "\(model.capturedFrameCount)")
          LabeledContent("capture.stableFrames", value: "\(model.stableFrameCount)")
          LabeledContent("capture.slideChanges", value: "\(model.slideChangeCount)")
          LabeledContent("capture.contentRevisions", value: "\(model.contentRevisionCount)")
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
            "analysis.strokeCandidateRegions",
            value: "\(model.latestSlideAnalysis?.strokeCandidateRegions.count ?? 0)"
          )
          LabeledContent(
            "analysis.occupiedRegions",
            value: "\(model.latestSlideAnalysis?.occupiedRegions.count ?? 0)"
          )
        }

        if let title = model.latestSlideAnalysis?.title, !title.isEmpty {
          LabeledContent("analysis.titleCandidate", value: title)
        }

        if let image = model.slideCanvasPreviewFrame {
          SlideCanvasSelectionPreview(
            image: image,
            status: model.slideCanvasStatus,
            confirmedRegion: model.confirmedSlideCanvasRegion,
            onBeginSelection: model.beginSlideCanvasSelection,
            onConfirmSelection: { region in
              _ = model.confirmSlideCanvasSelection(region)
            },
            onCancelSelection: model.cancelSlideCanvasSelection
          )
          .id(model.slideCanvasCalibrationRevision)
        } else {
          Text("capture.slideCanvas.noWindowFrame")
            .foregroundStyle(.secondary)
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

  @ViewBuilder
  private var slideIdentityStatusLabel: some View {
    switch model.slideIdentityState {
    case .unavailable:
      Label("capture.slideIdentity.unavailable", systemImage: "questionmark.circle")
        .foregroundStyle(.secondary)
    case .establishing:
      Label("capture.slideIdentity.establishing", systemImage: "ellipsis.circle")
        .foregroundStyle(.secondary)
    case .identified:
      Label("capture.slideIdentity.identified", systemImage: "checkmark.seal")
        .foregroundStyle(.green)
    case .interrupted:
      Label(
        "capture.slideIdentity.interrupted",
        systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
      )
      .foregroundStyle(.orange)
    }
  }

  @ViewBuilder
  private var slideIdentityFrameSyncStatusLabel: some View {
    switch model.slideIdentityFrameSyncState {
    case .notRequired:
      EmptyView()
    case .waiting:
      Label("capture.slideIdentityFrameSync.waiting", systemImage: "hourglass")
        .foregroundStyle(.orange)
    case .synchronized:
      Label(
        "capture.slideIdentityFrameSync.synchronized",
        systemImage: "checkmark.circle"
      )
      .foregroundStyle(.green)
    case .timedOut:
      Label(
        "capture.slideIdentityFrameSync.timedOut",
        systemImage: "exclamationmark.triangle"
      )
      .foregroundStyle(.orange)
    }
  }

  @ViewBuilder
  private var slideCanvasStatusLabel: some View {
    switch model.slideCanvasStatus {
    case .unavailable:
      Label("capture.slideCanvas.unavailable", systemImage: "rectangle.dashed")
        .foregroundStyle(.secondary)
    case .waitingForFrame:
      Label("capture.slideCanvas.waitingForFrame", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case .needsConfirmation:
      Label("capture.slideCanvas.needsConfirmation", systemImage: "viewfinder.rectangular")
        .foregroundStyle(.orange)
    case .selecting:
      Label("capture.slideCanvas.selecting", systemImage: "viewfinder.rectangular")
        .foregroundStyle(.orange)
    case .confirmed:
      Label("capture.slideCanvas.confirmed", systemImage: "checkmark.rectangle")
        .foregroundStyle(.green)
    case .invalidated:
      Label("capture.slideCanvas.invalidated", systemImage: "exclamationmark.rectangle")
        .foregroundStyle(.orange)
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
      Button("setup.transcription") {
        Task { await model.requestTranscriptionStart() }
      }
      .disabled(!model.canRequestTranscriptionStart)
      Button("setup.transcriptionStop") { model.requestTranscriptionStop() }
        .disabled(!model.canRequestTranscriptionStop)
      Button("board.hide") { model.hideOverlay() }
      Divider().frame(height: 24)
      Button("session.export") { exportSession() }
        .disabled(!model.canExportLectureSession)
    }
    .buttonStyle(.bordered)
  }

  private var runtimeDiagnostics: some View {
    GroupBox("diagnostics.title") {
      VStack(alignment: .leading, spacing: 6) {
        LabeledContent("diagnostics.applicationLifecycle") {
          applicationLifecycleDiagnosticValue
        }
        LabeledContent("diagnostics.transcriptionLifecycle") {
          transcriptionLifecycleDiagnosticValue
        }
        LabeledContent("diagnostics.transcriptPhase") {
          transcriptPhaseDiagnosticValue
        }
        LabeledContent("diagnostics.overlayMapping") {
          overlayMappingDiagnosticValue
        }
        LabeledContent("diagnostics.overlayEligibility") {
          overlayEligibilityDiagnosticValue
        }
        LabeledContent("diagnostics.overlayPresentation") {
          overlayPresentationDiagnosticValue
        }
        LabeledContent(
          "diagnostics.publicBoardElements",
          value: "\(model.productionConfirmedBoardElementCount)"
        )
        Text("diagnostics.renderRequestedDisclaimer")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .font(.callout)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var applicationLifecycleDiagnosticValue: some View {
    switch model.status {
    case .ready, .listening, .finalizingTranscription:
      Text("diagnostics.lifecycle.ready")
    case .scanning:
      Text("diagnostics.lifecycle.scanning")
    case .overlayVisible:
      Text("diagnostics.lifecycle.demoOverlay")
    case .error(let message):
      Text(message)
        .foregroundStyle(.red)
    }
  }

  @ViewBuilder
  private var transcriptionLifecycleDiagnosticValue: some View {
    switch model.transcriptionLifecycleState {
    case .idle:
      Text("diagnostics.transcription.idle")
    case .starting:
      Text("diagnostics.transcription.starting")
    case .waitingForContext:
      Text("diagnostics.transcription.waitingForContext")
    case .listening:
      Text("diagnostics.transcription.listening")
    case .finalizing:
      Text("diagnostics.transcription.finalizing")
    case .failed(let message):
      Text(message)
        .foregroundStyle(.red)
    }
  }

  @ViewBuilder
  private var transcriptPhaseDiagnosticValue: some View {
    switch model.liveTranscriptPhase {
    case .empty:
      Text("diagnostics.transcript.empty")
    case .partial:
      Text("diagnostics.transcript.partial")
    case .final:
      Text("diagnostics.transcript.final")
    }
  }

  @ViewBuilder
  private var overlayMappingDiagnosticValue: some View {
    switch model.slideCanvasOverlayMappingState {
    case .unavailable:
      Text("diagnostics.mapping.unavailable")
    case .mapped:
      Text("diagnostics.mapping.mapped")
    case .rejected:
      Text("diagnostics.mapping.rejected")
    }
  }

  @ViewBuilder
  private var overlayEligibilityDiagnosticValue: some View {
    switch model.productionOverlayEligibilityState {
    case .notEvaluated:
      Text("diagnostics.eligibility.notEvaluated")
    case .allowed:
      Text("diagnostics.eligibility.allowed")
    case .blocked:
      Text("diagnostics.eligibility.blocked")
    }
  }

  @ViewBuilder
  private var overlayPresentationDiagnosticValue: some View {
    switch model.productionOverlayPresentationState {
    case .hidden:
      Text("diagnostics.presentation.hidden")
    case .renderRequested:
      Text("diagnostics.presentation.renderRequested")
    }
  }

  private var exportErrorIsPresented: Binding<Bool> {
    Binding(
      get: { sessionExportError != nil },
      set: { if !$0 { sessionExportError = nil } }
    )
  }

  @MainActor
  private func exportSession() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "lectureboard-session.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      _ = try model.exportLectureSession(to: url)
    } catch {
      sessionExportError = error.localizedDescription
    }
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

private struct SlideCanvasSelectionPreview: View {
  let image: CGImage
  let status: SlideCanvasStatus
  let confirmedRegion: SlideCanvasRegion?
  let onBeginSelection: () -> Void
  let onConfirmSelection: (SlideCanvasRegion) -> Void
  let onCancelSelection: () -> Void

  @State private var draftRegion: SlideCanvasRegion?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("capture.slideCanvas.windowPreview")
        .font(.headline)

      ZStack(alignment: .topLeading) {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFit()

        GeometryReader { proxy in
          if let region = visibleRegion?.normalizedRect {
            Rectangle()
              .fill(.blue.opacity(0.10))
              .stroke(.blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
              .frame(
                width: region.width * proxy.size.width,
                height: region.height * proxy.size.height
              )
              .position(
                x: (region.x + region.width / 2) * proxy.size.width,
                y: (region.y + region.height / 2) * proxy.size.height
              )
          }

          Color.clear
            .contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 2)
                .onChanged { value in
                  guard status == .selecting else { return }
                  draftRegion = SlideCanvasDragSelection.region(
                    from: value.startLocation,
                    to: value.location,
                    in: proxy.size
                  )
                }
            )
        }
      }
      .aspectRatio(CGFloat(image.width) / CGFloat(max(image.height, 1)), contentMode: .fit)
      .frame(maxWidth: .infinity, maxHeight: 240)
      .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
      .clipShape(RoundedRectangle(cornerRadius: 8))

      controls
    }
  }

  private var visibleRegion: SlideCanvasRegion? {
    status == .selecting ? draftRegion : confirmedRegion
  }

  @ViewBuilder
  private var controls: some View {
    switch status {
    case .needsConfirmation, .invalidated:
      HStack(spacing: 10) {
        Text("capture.slideCanvas.instructions")
          .foregroundStyle(.secondary)
        Spacer()
        Button("capture.slideCanvas.begin", action: onBeginSelection)
      }
    case .selecting:
      HStack(spacing: 10) {
        Text("capture.slideCanvas.dragInstructions")
          .foregroundStyle(.secondary)
        Spacer()
        Button("capture.slideCanvas.cancel", action: onCancelSelection)
        Button("capture.slideCanvas.confirm") {
          guard let draftRegion else { return }
          onConfirmSelection(draftRegion)
        }
        .buttonStyle(.borderedProminent)
        .disabled(draftRegion == nil)
      }
    case .confirmed:
      HStack(spacing: 10) {
        Text("capture.slideCanvas.confirmedInstructions")
          .foregroundStyle(.secondary)
        Spacer()
        Button("capture.slideCanvas.reselect", action: onBeginSelection)
      }
    case .unavailable, .waitingForFrame:
      EmptyView()
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
