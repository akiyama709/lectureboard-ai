import CoreGraphics
import Foundation
import ScreenCaptureKit

enum PowerPointWindowScanScope: Equatable, Sendable {
  /// Human-facing inventory of windows currently visible in the active Space.
  case visibleOnly
  /// Identity inventory which also retains a confirmed slide-show window in another Space.
  case completeInventory

  var onScreenWindowsOnly: Bool {
    self == .visibleOnly
  }
}

struct PowerPointWindowIdentity: Hashable, Sendable {
  static let expectedBundleIdentifier = "com.microsoft.Powerpoint"

  let windowID: CGWindowID
  let ownerProcessID: pid_t
  let bundleIdentifier: String

  init?(
    windowID: CGWindowID,
    ownerProcessID: pid_t,
    bundleIdentifier: String
  ) {
    guard windowID != 0,
      ownerProcessID > 0,
      bundleIdentifier == Self.expectedBundleIdentifier
    else {
      return nil
    }

    self.windowID = windowID
    self.ownerProcessID = ownerProcessID
    self.bundleIdentifier = bundleIdentifier
  }
}

struct PowerPointWindowDescriptor: Identifiable, Hashable, Sendable {
  let id: CGWindowID
  let title: String
  let applicationName: String
  let ownerProcessID: pid_t
  let bundleIdentifier: String
  let frame: CGRect

  var identity: PowerPointWindowIdentity? {
    PowerPointWindowIdentity(
      windowID: id,
      ownerProcessID: ownerProcessID,
      bundleIdentifier: bundleIdentifier
    )
  }
}

enum PowerPointWindowIdentityResolver {
  static func uniqueDescriptor(
    windowID: CGWindowID,
    in windows: [PowerPointWindowDescriptor]
  ) -> PowerPointWindowDescriptor? {
    let identifierMatches = windows.filter { $0.id == windowID }
    guard identifierMatches.count == 1,
      let descriptor = identifierMatches.first,
      descriptor.identity != nil
    else {
      return nil
    }
    return descriptor
  }

  static func uniqueDescriptor(
    identity: PowerPointWindowIdentity,
    in windows: [PowerPointWindowDescriptor]
  ) -> PowerPointWindowDescriptor? {
    guard
      let descriptor = uniqueDescriptor(
        windowID: identity.windowID,
        in: windows
      ),
      descriptor.identity == identity
    else {
      return nil
    }
    return descriptor
  }
}

struct PowerPointWindowScanner: Sendable {
  private let scope: PowerPointWindowScanScope

  init(scope: PowerPointWindowScanScope = .visibleOnly) {
    self.scope = scope
  }

  func scan() async throws -> [PowerPointWindowDescriptor] {
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: scope.onScreenWindowsOnly
    )

    return content.windows
      .compactMap { window in
        guard let application = window.owningApplication else { return nil }
        let bundleID = application.bundleIdentifier
        guard
          PowerPointWindowIdentity(
            windowID: window.windowID,
            ownerProcessID: application.processID,
            bundleIdentifier: bundleID
          ) != nil
        else {
          return nil
        }

        return PowerPointWindowDescriptor(
          id: window.windowID,
          title: window.title ?? "",
          applicationName: application.applicationName,
          ownerProcessID: application.processID,
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
