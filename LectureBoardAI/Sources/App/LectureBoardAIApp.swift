import SwiftUI

@main
struct LectureBoardAIApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      MainView()
        .environmentObject(model)
        .frame(minWidth: 920, minHeight: 640)
    }
    .windowStyle(.titleBar)

    Settings {
      SettingsView()
        .environmentObject(model)
        .frame(width: 520, height: 360)
    }
  }
}
