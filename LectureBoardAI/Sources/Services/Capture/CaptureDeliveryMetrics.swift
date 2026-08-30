import Foundation

struct CaptureDeliveryMetrics: Equatable, Sendable {
  private(set) var newFrameCount = 0
  private(set) var repeatedFrameCount = 0
  private(set) var lastNewFrameAt: Date?

  mutating func record(_ kind: CapturedFrameDeliveryKind, capturedAt: Date) {
    switch kind {
    case .new:
      newFrameCount += 1
      lastNewFrameAt = capturedAt
    case .idleRepeat:
      repeatedFrameCount += 1
    }
  }

  mutating func reset() {
    self = CaptureDeliveryMetrics()
  }
}
