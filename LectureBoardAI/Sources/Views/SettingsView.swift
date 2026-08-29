import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Form {
      Picker("style.title", selection: $model.digitalInkStyle.preset) {
        Text("style.clean").tag(DigitalInkStyle.Preset.clean)
        Text("style.handwritten").tag(DigitalInkStyle.Preset.handwritten)
      }
      .onChange(of: model.digitalInkStyle.preset) { _, preset in
        model.digitalInkStyle = preset == .clean ? .clean : .handwritten
      }

      LabeledContent("style.lineWidth") {
        Slider(value: $model.digitalInkStyle.lineWidth, in: 1...6)
          .frame(width: 240)
      }

      Text(
        "settings.mixedLanguageNotice"
      )
      .foregroundStyle(.secondary)
    }
    .padding(24)
  }
}
