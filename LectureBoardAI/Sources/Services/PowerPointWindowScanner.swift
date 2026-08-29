import CoreGraphics
import Foundation
import ScreenCaptureKit

struct PowerPointWindowDescriptor: Identifiable, Hashable, Sendable {
  let id: CGWindowID
  let title: String
  let applicationName: String
  let bundleIdentifier: String
  let frame: CGRect
}

struct PowerPointWindowScanner: Sendable {
  func scan() async throws -> [PowerPointWindowDescriptor] {
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: true
    )

    return content.windows
      .compactMap { window in
        guard let application = window.owningApplication else { return nil }
        let bundleID = application.bundleIdentifier
        let applicationName = application.applicationName
        let isPowerPoint =
          bundleID.caseInsensitiveCompare("com.microsoft.Powerpoint") == .orderedSame
          || applicationName.localizedCaseInsensitiveContains("PowerPoint")
        guard isPowerPoint else { return nil }

        return PowerPointWindowDescriptor(
          id: window.windowID,
          title: window.title ?? "",
          applicationName: applicationName,
          bundleIdentifier: bundleID,
          frame: window.frame
        )
      }
      .sorted { lhs, rhs in
        if lhs.title.isEmpty != rhs.title.isEmpty {
          return !lhs.title.isEmpty
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
  }
}
