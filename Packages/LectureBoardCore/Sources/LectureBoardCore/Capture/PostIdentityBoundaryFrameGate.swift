import Foundation

/// Metadata-only state for the visual-frame gate after an independent slide-identity boundary.
public enum SlideIdentityFrameSyncState: String, Codable, Equatable, Sendable {
  case notRequired
  case waiting
  case synchronized
  case timedOut
}

/// An opaque capability identifying one post-identity-boundary wait.
///
/// Tokens are deliberately runtime-only. They are not `Codable` and must not enter runtime
/// verification reports.
public struct SlideIdentityFrameBoundaryToken: Equatable, Hashable, Sendable {
  fileprivate let identifier: UUID

  fileprivate init() {
    identifier = UUID()
  }
}

/// Keeps visual analysis closed until a fresh ScreenCaptureKit frame follows an identity boundary.
///
/// A timeout is diagnostic only: it does not open the gate. The gate recovers from either
/// `waiting` or `timedOut` only when a newly delivered frame has a nonzero display time strictly
/// later than the boundary's mach absolute time.
public struct PostIdentityBoundaryFrameGate: Equatable, Sendable {
  public private(set) var state: SlideIdentityFrameSyncState = .notRequired

  private var minimumDisplayTime: UInt64?
  private var activeBoundaryToken: SlideIdentityFrameBoundaryToken?

  public init() {}

  public var requiresFreshFrame: Bool {
    state == .waiting || state == .timedOut
  }

  @discardableResult
  public mutating func beginWaiting(
    after minimumDisplayTime: UInt64
  ) -> SlideIdentityFrameBoundaryToken {
    let token = SlideIdentityFrameBoundaryToken()
    self.minimumDisplayTime = minimumDisplayTime
    activeBoundaryToken = token
    state = .waiting
    return token
  }

  /// Returns whether the frame may continue into visual analysis.
  @discardableResult
  public mutating func acceptFrame(
    isNewDelivery: Bool,
    displayTime: UInt64?
  ) -> Bool {
    guard requiresFreshFrame else { return true }
    guard isNewDelivery,
      let displayTime,
      let minimumDisplayTime,
      displayTime > 0,
      minimumDisplayTime > 0,
      displayTime > minimumDisplayTime
    else {
      return false
    }

    state = .synchronized
    self.minimumDisplayTime = nil
    activeBoundaryToken = nil
    return true
  }

  /// Marks only the currently waiting boundary as timed out.
  ///
  /// The active boundary remains in place so a later fresh frame can still synchronize the gate.
  @discardableResult
  public mutating func markTimedOut(
    for token: SlideIdentityFrameBoundaryToken
  ) -> Bool {
    guard state == .waiting, token == activeBoundaryToken else { return false }
    state = .timedOut
    return true
  }

  public mutating func reset() {
    state = .notRequired
    minimumDisplayTime = nil
    activeBoundaryToken = nil
  }
}
