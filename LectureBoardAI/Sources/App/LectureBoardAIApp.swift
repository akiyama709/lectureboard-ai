import LectureBoardCore
import SwiftUI

@main
@MainActor
struct LectureBoardAIApp: App {
  @StateObject private var model: AppModel
  @NSApplicationDelegateAdaptor(RuntimeVerificationApplicationDelegate.self)
  private var applicationDelegate

  #if DEBUG
    private enum LaunchMode {
      case standard
      case runtimeVerification(RuntimeVerificationConfiguration)
      case invalidRuntimeVerification(String)
    }

    private let launchMode: LaunchMode
    private let runtimeVerificationRunner: RuntimeVerificationRunner

    init() {
      let runner = RuntimeVerificationRunner()

      let resolvedLaunchMode: LaunchMode
      do {
        if let configuration = try RuntimeVerificationArguments.parse(CommandLine.arguments) {
          resolvedLaunchMode = .runtimeVerification(configuration)
        } else {
          resolvedLaunchMode = .standard
        }
      } catch {
        resolvedLaunchMode = .invalidRuntimeVerification(String(describing: error))
      }
      let appModel: AppModel
      switch resolvedLaunchMode {
      case .standard:
        appModel = AppModel(slideCanvasConfirmationMode: .automaticCapturedContent)
      case .runtimeVerification, .invalidRuntimeVerification:
        appModel = AppModel()
      }
      _model = StateObject(wrappedValue: appModel)
      runtimeVerificationRunner = runner
      launchMode = resolvedLaunchMode
      applicationDelegate.configureTerminationCleanup {
        await appModel.prepareForApplicationTermination()
      }

      switch resolvedLaunchMode {
      case .standard:
        break
      case .runtimeVerification(let configuration):
        applicationDelegate.configureRuntimeVerification {
          await runner.run(configuration: configuration, model: appModel)
        }
      case .invalidRuntimeVerification(let message):
        applicationDelegate.configureInvalidRuntimeVerification(
          errorDescription: message
        )
      }
    }
  #else
    init() {
      let appModel = AppModel(slideCanvasConfirmationMode: .automaticCapturedContent)
      _model = StateObject(wrappedValue: appModel)
      applicationDelegate.configureTerminationCleanup {
        await appModel.prepareForApplicationTermination()
      }
    }
  #endif

  var body: some Scene {
    WindowGroup {
      rootView
        .environmentObject(model)
    }
    .windowStyle(.titleBar)

    Settings {
      SettingsView()
        .environmentObject(model)
        .frame(width: 520, height: 360)
    }
  }

  @ViewBuilder
  private var rootView: some View {
    #if DEBUG
      switch launchMode {
      case .standard:
        MainView()
          .frame(minWidth: 920, minHeight: 640)
      case .runtimeVerification:
        RuntimeVerificationHostView(runner: runtimeVerificationRunner)
      case .invalidRuntimeVerification(let message):
        RuntimeVerificationLaunchErrorView(message: message)
      }
    #else
      MainView()
        .frame(minWidth: 920, minHeight: 640)
    #endif
  }
}
