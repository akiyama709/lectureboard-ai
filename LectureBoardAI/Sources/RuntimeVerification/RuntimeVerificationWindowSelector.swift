import CoreGraphics
import Foundation

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

  private static func normalized(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
  }
}
