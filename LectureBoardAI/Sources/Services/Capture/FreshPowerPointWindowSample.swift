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
  /// The local mach-absolute time immediately before the one-shot capture
  /// request entered ScreenCaptureKit. This is fresh-sample provenance only;
  /// it must never be treated as a continuous stream display time.
  let requestStartedMachAbsoluteTime: UInt64
  let capturedAt: Date
  let captureSurfaceGeometry: CaptureSurfaceGeometry
  let image: CGImage
}
