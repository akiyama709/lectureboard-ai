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
          languageAndStyle
          controls
          transcript
          BoardPreviewView(scene: model.boardScene, style: model.digitalInkStyle)
        }
        .padding(28)
      }
    }
    .task {
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
          granted: model.permissionService.screenCaptureGranted
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
        Button("setup.request") {
          Task { await model.requestPermissions() }
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
        }

        Button("setup.refresh") {
          Task { await model.refreshPowerPointWindows() }
        }
      }
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
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

private struct PermissionBadge: View {
  let titleKey: LocalizedStringKey
  let granted: Bool

  var body: some View {
    Label(titleKey, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
      .foregroundStyle(granted ? Color.green : Color.secondary)
  }
}
