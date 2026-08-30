import LectureBoardCore
import SwiftUI

#if DEBUG
  struct RuntimeVerificationHostView: View {
    @ObservedObject var runner: RuntimeVerificationRunner

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("LectureBoard AI Runtime Verification")
          .font(.title2.bold())
        Text(statusText)
          .foregroundStyle(.secondary)
        ProgressView()
          .controlSize(.small)
      }
      .padding(24)
      .frame(minWidth: 480, minHeight: 180, alignment: .leading)
    }

    private var statusText: String {
      switch runner.state {
      case .idle:
        return "Waiting to start."
      case .preparing:
        return "Preparing screen capture and locating PowerPoint."
      case .observing:
        return "Collecting metadata-only observations."
      case .finished:
        return "The report was written."
      case .failed(let message):
        return message
      }
    }
  }

  struct RuntimeVerificationLaunchErrorView: View {
    let message: String

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Runtime Verification Configuration Error")
          .font(.title2.bold())
        Text(message)
          .foregroundStyle(.red)
      }
      .padding(24)
      .frame(minWidth: 480, minHeight: 180, alignment: .leading)
    }
  }
#endif
