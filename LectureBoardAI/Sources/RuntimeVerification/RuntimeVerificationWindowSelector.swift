import CoreGraphics
import Foundation
import LectureBoardCore

struct RuntimeVerificationWindowSelection: Equatable, Sendable {
  enum Resolution: Equatable, Sendable {
    case selected(PowerPointWindowIdentity)
    case notFound
    case ambiguous
  }

  let resolution: Resolution
  let matchedWindowCount: Int
}

enum RuntimeVerificationWindowSelector {
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

    let eligibleWindows = windows.filter { $0.identity != nil }
    let exactMatches = eligibleWindows.filter { normalized($0.title) == target }
    let preferredMatches: [PowerPointWindowDescriptor]
    if exactMatches.isEmpty {
      preferredMatches = eligibleWindows.filter { normalized($0.title).contains(target) }
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
      guard let identity = preferredMatches[0].identity else {
        return RuntimeVerificationWindowSelection(
          resolution: .notFound,
          matchedWindowCount: 0
        )
      }
      let identifierMatchCount = windows.filter { $0.id == identity.windowID }.count
      guard identifierMatchCount == 1 else {
        return RuntimeVerificationWindowSelection(
          resolution: .ambiguous,
          matchedWindowCount: identifierMatchCount
        )
      }
      return RuntimeVerificationWindowSelection(
        resolution: .selected(identity),
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
      guard let identity = identifierMatches[0].identity else {
        return RuntimeVerificationWindowSelection(
          resolution: .notFound,
          matchedWindowCount: 0
        )
      }
      return RuntimeVerificationWindowSelection(
        resolution: .selected(identity),
        matchedWindowCount: 1
      )
    default:
      return RuntimeVerificationWindowSelection(
        resolution: .ambiguous,
        matchedWindowCount: identifierMatches.count
      )
    }
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
