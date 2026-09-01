import CoreGraphics
import Foundation

/// An opaque correlation token for one bounded fresh-sample request.
struct FreshSampleRequestID: Hashable, Sendable {
  private let value: UUID

  init() {
    value = UUID()
  }
}

/// A one-shot ScreenCaptureKit image bound to one exact capture operation and
/// PowerPoint window identity.
struct FreshPowerPointWindowSample: @unchecked Sendable {
  let requestID: FreshSampleRequestID
  let captureOperationID: CaptureOperationID
  let identity: PowerPointWindowIdentity
  let capturedAt: Date
  let captureSurfaceGeometry: CaptureSurfaceGeometry
  let image: CGImage
}
