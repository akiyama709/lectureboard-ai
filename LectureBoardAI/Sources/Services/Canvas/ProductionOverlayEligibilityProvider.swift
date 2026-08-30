import AppKit
import CoreGraphics

@MainActor
protocol ProductionOverlayLeaseScheduling: AnyObject, Sendable {
  func schedule(
    after duration: Duration,
    action: @escaping @MainActor @Sendable () -> Void
  )
  func cancel()
}

@MainActor
final class TaskProductionOverlayLeaseScheduler: ProductionOverlayLeaseScheduling {
  private var task: Task<Void, Never>?

  func schedule(
    after duration: Duration,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    cancel()
    task = Task { @MainActor in
      do {
        try await Task.sleep(for: max(duration, .zero))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      action()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  deinit {
    task?.cancel()
  }
}

typealias ProductionOverlayUnsafeEventHandler = @MainActor @Sendable () -> Void

@MainActor
protocol ProductionOverlaySafetyEventProviding: AnyObject, Sendable {
  func start(onUnsafeEvent: @escaping ProductionOverlayUnsafeEventHandler)
  func stop()
}

/// Invalidates a production overlay independently of ScreenCaptureKit delivery
/// cadence when application focus or the active Space changes. A later current
/// capture frame must pass the full eligibility policy before the overlay can
/// return.
@MainActor
final class SystemProductionOverlaySafetyEventProvider:
  ProductionOverlaySafetyEventProviding
{
  private struct Observation {
    let center: NotificationCenter
    let token: NSObjectProtocol
  }

  private var observations: [Observation] = []

  func start(onUnsafeEvent: @escaping ProductionOverlayUnsafeEventHandler) {
    stop()
    observe(
      NSWorkspace.didActivateApplicationNotification,
      center: NSWorkspace.shared.notificationCenter,
      onUnsafeEvent: onUnsafeEvent
    )
    observe(
      NSWorkspace.didDeactivateApplicationNotification,
      center: NSWorkspace.shared.notificationCenter,
      onUnsafeEvent: onUnsafeEvent
    )
    observe(
      NSWorkspace.activeSpaceDidChangeNotification,
      center: NSWorkspace.shared.notificationCenter,
      onUnsafeEvent: onUnsafeEvent
    )
    observe(
      NSApplication.didResignActiveNotification,
      center: .default,
      onUnsafeEvent: onUnsafeEvent
    )
  }

  func stop() {
    for observation in observations {
      observation.center.removeObserver(observation.token)
    }
    observations.removeAll()
  }

  private func observe(
    _ name: Notification.Name,
    center: NotificationCenter,
    onUnsafeEvent: @escaping ProductionOverlayUnsafeEventHandler
  ) {
    let token = center.addObserver(
      forName: name,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        onUnsafeEvent()
      }
    }
    observations.append(Observation(center: center, token: token))
  }

}

@MainActor
protocol ProductionOverlayEligibilityProviding {
  func allowsProductionOverlay(
    for identity: PowerPointWindowIdentity,
    screenGeometry: CaptureScreenGeometry
  ) -> Bool
}

struct ProductionOverlayWindowSnapshot: Equatable, Sendable {
  let windowID: CGWindowID
  let ownerProcessID: pid_t
  let layer: Int
  let isOnScreen: Bool
  let bounds: CGRect

  init?(
    windowID: CGWindowID,
    ownerProcessID: pid_t,
    layer: Int,
    isOnScreen: Bool,
    bounds: CGRect
  ) {
    let rawWidth = Double(bounds.size.width)
    let rawHeight = Double(bounds.size.height)
    let values = [
      Double(bounds.origin.x),
      Double(bounds.origin.y),
      rawWidth,
      rawHeight,
      Double(bounds.origin.x) + rawWidth,
      Double(bounds.origin.y) + rawHeight,
    ]
    guard
      windowID != 0,
      ownerProcessID > 0,
      values.allSatisfy(\.isFinite),
      rawWidth > 0,
      rawHeight > 0
    else {
      return nil
    }

    self.windowID = windowID
    self.ownerProcessID = ownerProcessID
    self.layer = layer
    self.isOnScreen = isOnScreen
    self.bounds = bounds
  }
}

enum ProductionOverlayEligibilityPolicy {
  private static let boundsTolerance = 2.0

  static func allowsProductionOverlay(
    identity: PowerPointWindowIdentity,
    screenGeometry: CaptureScreenGeometry,
    frontmostProcessID: pid_t?,
    frontmostBundleIdentifier: String?,
    windows: [ProductionOverlayWindowSnapshot]
  ) -> Bool {
    guard
      frontmostProcessID == identity.ownerProcessID,
      frontmostBundleIdentifier == identity.bundleIdentifier
    else {
      return false
    }

    let exactWindowIndices = windows.indices.filter {
      windows[$0].windowID == identity.windowID
    }
    guard
      exactWindowIndices.count == 1,
      let exactWindowIndex = exactWindowIndices.first
    else {
      return false
    }
    let window = windows[exactWindowIndex]
    guard
      window.ownerProcessID == identity.ownerProcessID,
      window.layer == 0,
      window.isOnScreen,
      screenRect(screenGeometry.screenRect, matches: window.bounds),
      // CGWindowListCopyWindowInfo preserves front-to-back order. Any validated
      // on-screen window ahead of the target that covers its captured content
      // makes the visible destination ambiguous, regardless of window layer.
      !windows[..<exactWindowIndex].contains(where: {
        $0.isOnScreen
          && hasPositiveAreaIntersection($0.bounds, screenGeometry.screenRect)
      })
    else {
      return false
    }
    return true
  }

  // ScreenCaptureKit and Core Graphics both document these rectangles in the
  // global display coordinate space. Until live PowerPoint measurements prove
  // a stable inset, require their edges to agree within rounding tolerance.
  private static func screenRect(_ screenRect: CGRect, matches bounds: CGRect) -> Bool {
    let tolerance = boundsTolerance
    return abs(Double(screenRect.minX) - Double(bounds.minX)) <= tolerance
      && abs(Double(screenRect.minY) - Double(bounds.minY)) <= tolerance
      && abs(Double(screenRect.maxX) - Double(bounds.maxX)) <= tolerance
      && abs(Double(screenRect.maxY) - Double(bounds.maxY)) <= tolerance
  }

  private static func hasPositiveAreaIntersection(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    let intersection = lhs.intersection(rhs)
    return !intersection.isNull && intersection.width > 0 && intersection.height > 0
  }
}

enum ProductionOverlayWindowListParser {
  static func parse(
    _ windowInfo: [[String: Any]],
    excludingOwnerProcessID excludedProcessID: pid_t
  ) -> [ProductionOverlayWindowSnapshot]? {
    var snapshots: [ProductionOverlayWindowSnapshot] = []
    snapshots.reserveCapacity(windowInfo.count)

    for info in windowInfo {
      guard
        let windowNumber = integer(info[kCGWindowNumber as String]),
        windowNumber > 0,
        windowNumber <= Int(UInt32.max),
        let ownerProcessIDValue = integer(info[kCGWindowOwnerPID as String]),
        ownerProcessIDValue > 0,
        ownerProcessIDValue <= Int(Int32.max)
      else {
        return nil
      }
      let ownerProcessID = pid_t(ownerProcessIDValue)
      guard ownerProcessID != excludedProcessID else { continue }

      guard
        let layer = integer(info[kCGWindowLayer as String]),
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(
          dictionaryRepresentation: boundsDictionary as CFDictionary
        ),
        let isOnScreen = parseOptionalOnScreenValue(
          info[kCGWindowIsOnscreen as String]
        ),
        let snapshot = ProductionOverlayWindowSnapshot(
          windowID: CGWindowID(windowNumber),
          ownerProcessID: ownerProcessID,
          layer: layer,
          isOnScreen: isOnScreen,
          bounds: bounds
        )
      else {
        return nil
      }
      snapshots.append(snapshot)
    }
    return snapshots
  }

  private static func integer(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let integer = number.intValue
    return number.doubleValue == Double(integer) ? integer : nil
  }

  private static func parseOptionalOnScreenValue(_ value: Any?) -> Bool? {
    // kCGWindowIsOnscreen is optional. The caller obtains this list with
    // optionOnScreenOnly, so absence still represents an on-screen window.
    guard let value else { return true }
    guard
      let number = value as? NSNumber,
      CFGetTypeID(number) == CFBooleanGetTypeID()
    else {
      return nil
    }
    return number.boolValue
  }
}

@MainActor
struct SystemProductionOverlayEligibilityProvider: ProductionOverlayEligibilityProviding {
  func allowsProductionOverlay(
    for identity: PowerPointWindowIdentity,
    screenGeometry: CaptureScreenGeometry
  ) -> Bool {
    let frontmostApplication = NSWorkspace.shared.frontmostApplication
    return ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
      identity: identity,
      screenGeometry: screenGeometry,
      frontmostProcessID: frontmostApplication?.processIdentifier,
      frontmostBundleIdentifier: frontmostApplication?.bundleIdentifier,
      windows: currentWindowSnapshots()
    )
  }

  private func currentWindowSnapshots() -> [ProductionOverlayWindowSnapshot] {
    guard
      let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return []
    }

    return ProductionOverlayWindowListParser.parse(
      windowInfo,
      excludingOwnerProcessID: ProcessInfo.processInfo.processIdentifier
    ) ?? []
  }
}
