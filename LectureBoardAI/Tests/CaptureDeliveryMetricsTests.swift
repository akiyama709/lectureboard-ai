import Foundation
import Testing

@testable import LectureBoard_AI

struct CaptureDeliveryMetricsTests {
  @Test func distinguishesNewFramesFromIdleRepeats() {
    let firstDate = Date(timeIntervalSince1970: 10)
    let secondDate = Date(timeIntervalSince1970: 20)
    var metrics = CaptureDeliveryMetrics()

    metrics.record(.new, capturedAt: firstDate)
    metrics.record(.idleRepeat, capturedAt: secondDate)

    #expect(metrics.newFrameCount == 1)
    #expect(metrics.repeatedFrameCount == 1)
    #expect(metrics.lastNewFrameAt == firstDate)
  }

  @Test func resetClearsAllMeasurements() {
    var metrics = CaptureDeliveryMetrics()
    metrics.record(.new, capturedAt: Date(timeIntervalSince1970: 10))
    metrics.record(.idleRepeat, capturedAt: Date(timeIntervalSince1970: 20))

    metrics.reset()

    #expect(metrics == CaptureDeliveryMetrics())
  }
}
