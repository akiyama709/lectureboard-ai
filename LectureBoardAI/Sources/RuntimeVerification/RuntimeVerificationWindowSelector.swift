import CoreGraphics
import Foundation
import LectureBoardCore

struct RuntimeVerificationWindowSelection: Equatable, Sendable {
  enum Resolution: Equatable, Sendable {
    case selected(CGWindowID)
    case notFound
    case ambiguous
  }

  let resolution: Resolution
  let matchedWindowCount: Int
}

enum RuntimeVerificationWindowSelector {
  private static let powerPointApplicationName = "Microsoft PowerPoint"
  private static let powerPointBundleIdentifier = "com.microsoft.Powerpoint"

  static func select(
    from windows: [PowerPointWindowDescriptor],
    target: RuntimeVerificationWindowTarget
  ) -> RuntimeVerificationWindowSelection {
    switch target {
    case .titleSubstring(let titleSubstring):
      select(from: windows, titleSubstring: titleSubstring)
    case .windowID(let windowID):
      select(from: windows, windowID: CGWindowID(windowID))
    }
  }

  static func select(
    from windows: [PowerPointWindowDescriptor],
    titleSubstring: String
  ) -> RuntimeVerificationWindowSelection {
    let target = normalized(titleSubstring)
    guard !target.isEmpty else {
      return RuntimeVerificationWindowSelection(
        resolution: .notFound,
        matchedWindowCount: 0
      )
    }

    let exactMatches = windows.filter { normalized($0.title) == target }
    let preferredMatches: [PowerPointWindowDescriptor]
    if exactMatches.isEmpty {
      preferredMatches = windows.filter { normalized($0.title).contains(target) }
    } else {
      preferredMatches = exactMatches
    }

    switch preferredMatches.count {
    case 0:
      return RuntimeVerificationWindowSelection(
        resolution: .notFound,
        matchedWindowCount: 0
      )
    case 1:
      return RuntimeVerificationWindowSelection(
        resolution: .selected(preferredMatches[0].id),
        matchedWindowCount: 1
      )
    default:
      return RuntimeVerificationWindowSelection(
        resolution: .ambiguous,
        matchedWindowCount: preferredMatches.count
      )
    }
  }

  private static func select(
    from windows: [PowerPointWindowDescriptor],
    windowID: CGWindowID
  ) -> RuntimeVerificationWindowSelection {
    let identifierMatches = windows.filter { $0.id == windowID }
    switch identifierMatches.count {
    case 0:
      return RuntimeVerificationWindowSelection(
        resolution: .notFound,
        matchedWindowCount: 0
      )
    case 1:
      guard isMicrosoftPowerPoint(identifierMatches[0]) else {
        return RuntimeVerificationWindowSelection(
          resolution: .notFound,
          matchedWindowCount: 0
        )
      }
      return RuntimeVerificationWindowSelection(
        resolution: .selected(identifierMatches[0].id),
        matchedWindowCount: 1
      )
    default:
      return RuntimeVerificationWindowSelection(
        resolution: .ambiguous,
        matchedWindowCount: identifierMatches.count
      )
    }
  }

  private static func isMicrosoftPowerPoint(
    _ window: PowerPointWindowDescriptor
  ) -> Bool {
    window.bundleIdentifier.caseInsensitiveCompare(powerPointBundleIdentifier) == .orderedSame
      && window.applicationName.caseInsensitiveCompare(powerPointApplicationName) == .orderedSame
  }

  private static func normalized(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
  }
}
