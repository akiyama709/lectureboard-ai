import Foundation

public enum ScreenRecordingPermissionState: String, Codable, Equatable, Sendable {
  case unknown
  case notDetermined
  case denied
  case authorized
}

public enum RuntimeCaptureState: String, Codable, Equatable, Sendable {
  case idle
  case starting
  case capturing
  case stopped
  case failed
}

public enum RuntimeVisionState: String, Codable, Equatable, Sendable {
  case idle
  case analyzing
  case completed
  case failed
}

/// A metadata-only observation. It deliberately carries no frame image or recognized slide text.
public struct RuntimeVerificationSnapshot: Codable, Equatable, Sendable {
  public let timestamp: Date
  public let elapsedMilliseconds: Int
  public let screenRecordingPermission: ScreenRecordingPermissionState
  public let captureState: RuntimeCaptureState
  public let visionState: RuntimeVisionState
  public let frameCount: Int
  public let newFrameCount: Int
  public let repeatedFrameCount: Int
  public let stableFrameCount: Int
  public let slideChangeCount: Int
  public let recognizedTextCount: Int
  public let detectedRectangleCount: Int
  public let occupiedRegionCount: Int
  public let lastNewFrameAt: Date?
  public let latestDifferenceFromStableFrame: Double?

  public init(
    timestamp: Date,
    elapsedMilliseconds: Int,
    screenRecordingPermission: ScreenRecordingPermissionState,
    captureState: RuntimeCaptureState,
    visionState: RuntimeVisionState,
    frameCount: Int,
    newFrameCount: Int,
    repeatedFrameCount: Int,
    stableFrameCount: Int,
    slideChangeCount: Int,
    recognizedTextCount: Int,
    detectedRectangleCount: Int,
    occupiedRegionCount: Int,
    lastNewFrameAt: Date? = nil,
    latestDifferenceFromStableFrame: Double? = nil
  ) {
    self.timestamp =
      timestamp.timeIntervalSinceReferenceDate.isFinite
      ? timestamp
      : Date(timeIntervalSince1970: 0)
    self.elapsedMilliseconds = max(elapsedMilliseconds, 0)
    self.screenRecordingPermission = screenRecordingPermission
    self.captureState = captureState
    self.visionState = visionState
    self.frameCount = max(frameCount, 0)
    self.newFrameCount = max(newFrameCount, 0)
    self.repeatedFrameCount = max(repeatedFrameCount, 0)
    self.stableFrameCount = max(stableFrameCount, 0)
    self.slideChangeCount = max(slideChangeCount, 0)
    self.recognizedTextCount = max(recognizedTextCount, 0)
    self.detectedRectangleCount = max(detectedRectangleCount, 0)
    self.occupiedRegionCount = max(occupiedRegionCount, 0)
    self.lastNewFrameAt = lastNewFrameAt.flatMap {
      $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil
    }
    self.latestDifferenceFromStableFrame = latestDifferenceFromStableFrame.flatMap {
      $0.isFinite ? min(max($0, 0), 1) : nil
    }
  }
}
