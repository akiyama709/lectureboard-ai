import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import LectureBoardCore
import ScreenCaptureKit
import Synchronization

enum CapturedFrameDeliveryKind: Equatable, Sendable {
  case new
  case idleRepeat
}

enum CaptureFrameDeliveryDecision: Equatable, Sendable {
  case newFrame
  case idleRepeat
  case terminalFailure
  case drop
}

enum CaptureFrameDeliveryDecisionResolver {
  static func resolve(statusValue: Any?) -> CaptureFrameDeliveryDecision {
    guard
      let statusValue,
      !isBoolean(statusValue),
      let rawValue = statusValue as? Int,
      let status = SCFrameStatus(rawValue: rawValue)
    else {
      return .drop
    }

    switch status {
    case .complete, .started:
      return .newFrame
    case .idle:
      return .idleRepeat
    case .blank, .suspended:
      return .drop
    case .stopped:
      return .terminalFailure
    @unknown default:
      return .drop
    }
  }

  private static func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
  }
}

struct CaptureOutputContinuity<Payload> {
  private(set) var repeatablePayload: Payload?

  mutating func acceptNewPayload(_ payload: Payload) {
    repeatablePayload = payload
  }

  mutating func makeAndAcceptRepeatedPayload(
    _ transform: (Payload) -> Payload
  ) -> Payload? {
    guard let repeatablePayload else { return nil }
    let repeatedPayload = transform(repeatablePayload)
    self.repeatablePayload = repeatedPayload
    return repeatedPayload
  }

  mutating func markContentUnavailable() {
    repeatablePayload = nil
  }
}

/// ScreenCaptureKit geometry that identifies how window content was placed in one
/// fixed-size stream output surface.
struct CaptureSurfaceGeometry: Equatable, Sendable {
  let contentOriginX: Double
  let contentOriginY: Double
  let contentWidth: Double
  let contentHeight: Double
  let scaleFactor: Double
  let contentScale: Double
  let outputPixelWidth: Int
  let outputPixelHeight: Int

  init?(
    contentRect: CGRect,
    scaleFactor: Double,
    contentScale: Double,
    outputPixelWidth: Int,
    outputPixelHeight: Int
  ) {
    let rawWidth = Double(contentRect.size.width)
    let rawHeight = Double(contentRect.size.height)
    let values = [
      Double(contentRect.origin.x),
      Double(contentRect.origin.y),
      rawWidth,
      rawHeight,
      scaleFactor,
      contentScale,
    ]
    guard
      values.allSatisfy(\.isFinite),
      contentRect.origin.x >= 0,
      contentRect.origin.y >= 0,
      rawWidth > 0,
      rawHeight > 0,
      scaleFactor >= 1,
      scaleFactor <= 4,
      contentScale > 0,
      outputPixelWidth > 0,
      outputPixelHeight > 0
    else {
      return nil
    }

    contentOriginX = Double(contentRect.origin.x)
    contentOriginY = Double(contentRect.origin.y)
    contentWidth = rawWidth
    contentHeight = rawHeight
    self.scaleFactor = scaleFactor
    self.contentScale = contentScale
    self.outputPixelWidth = outputPixelWidth
    self.outputPixelHeight = outputPixelHeight
  }

  var contentRect: CGRect {
    CGRect(
      x: contentOriginX,
      y: contentOriginY,
      width: contentWidth,
      height: contentHeight
    )
  }
}

/// The current onscreen location reported for one ScreenCaptureKit sample.
///
/// Unlike `CaptureSurfaceGeometry`, a negative origin is valid because a window
/// may be located on a display to the left of or above the main display.
struct CaptureScreenGeometry: Equatable, Sendable {
  let screenOriginX: Double
  let screenOriginY: Double
  let screenWidth: Double
  let screenHeight: Double

  init?(screenRect: CGRect) {
    let rawWidth = Double(screenRect.size.width)
    let rawHeight = Double(screenRect.size.height)
    let values = [
      Double(screenRect.origin.x),
      Double(screenRect.origin.y),
      rawWidth,
      rawHeight,
    ]
    guard
      values.allSatisfy(\.isFinite),
      rawWidth > 0,
      rawHeight > 0
    else {
      return nil
    }

    screenOriginX = Double(screenRect.origin.x)
    screenOriginY = Double(screenRect.origin.y)
    screenWidth = rawWidth
    screenHeight = rawHeight
  }

  var screenRect: CGRect {
    CGRect(
      x: screenOriginX,
      y: screenOriginY,
      width: screenWidth,
      height: screenHeight
    )
  }
}

enum CaptureFrameRectParser {
  static func parse(_ value: Any?) -> CGRect? {
    if let rect = value as? CGRect {
      return rect
    }
    if let value = value as? NSValue {
      let actualType = String(cString: value.objCType)
      let rectType = String(cString: NSValue(rect: .zero).objCType)
      guard actualType == rectType else { return nil }
      return value.rectValue
    }
    if let value = value as? NSDictionary {
      return CGRect(dictionaryRepresentation: value as CFDictionary)
    }
    return nil
  }
}

enum CaptureSurfaceGeometryParser {
  enum AttachmentState: Equatable {
    case absent
    case valid(CaptureSurfaceGeometry)
    case invalid
  }

  static func parse(
    _ attachments: [SCStreamFrameInfo: Any]?,
    outputPixelWidth: Int,
    outputPixelHeight: Int
  ) -> CaptureSurfaceGeometry? {
    guard
      case .valid(let geometry) = attachmentState(
        attachments,
        outputPixelWidth: outputPixelWidth,
        outputPixelHeight: outputPixelHeight
      )
    else {
      return nil
    }
    return geometry
  }

  static func attachmentState(
    _ attachments: [SCStreamFrameInfo: Any]?,
    outputPixelWidth: Int,
    outputPixelHeight: Int
  ) -> AttachmentState {
    let surfaceKeys: [SCStreamFrameInfo] = [.contentRect, .scaleFactor, .contentScale]
    let presentKeyCount = surfaceKeys.reduce(into: 0) { count, key in
      if attachments?[key] != nil {
        count += 1
      }
    }
    guard presentKeyCount > 0 else { return .absent }
    guard
      presentKeyCount == surfaceKeys.count,
      let attachments,
      let contentRect = CaptureFrameRectParser.parse(attachments[.contentRect]),
      let scaleFactor = parsePositiveDouble(attachments[.scaleFactor]),
      let contentScale = parsePositiveDouble(attachments[.contentScale]),
      let geometry = CaptureSurfaceGeometry(
        contentRect: contentRect,
        scaleFactor: scaleFactor,
        contentScale: contentScale,
        outputPixelWidth: outputPixelWidth,
        outputPixelHeight: outputPixelHeight
      )
    else {
      return .invalid
    }

    return .valid(geometry)
  }

  private static func parsePositiveDouble(_ value: Any?) -> Double? {
    guard let value else { return nil }
    if let number = value as? NSNumber {
      guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
      let parsed = number.doubleValue
      return parsed.isFinite && parsed > 0 ? parsed : nil
    }
    if let parsed = value as? Double {
      return parsed.isFinite && parsed > 0 ? parsed : nil
    }
    return nil
  }
}

enum CaptureScreenGeometryParser {
  static func parse(
    _ attachments: [SCStreamFrameInfo: Any]?
  ) -> CaptureScreenGeometry? {
    guard
      let screenRect = CaptureFrameRectParser.parse(attachments?[.screenRect])
    else {
      return nil
    }
    return CaptureScreenGeometry(screenRect: screenRect)
  }
}

struct CapturedPowerPointFrame: @unchecked Sendable {
  let windowID: CGWindowID
  let sequenceNumber: UInt64
  let capturedAt: Date
  /// ScreenCaptureKit's mach absolute time for the displayed source frame.
  let displayTime: UInt64?
  let deliveryKind: CapturedFrameDeliveryKind
  let captureSurfaceGeometry: CaptureSurfaceGeometry?
  let captureScreenGeometry: CaptureScreenGeometry?
  let image: CGImage
  let fingerprint: FrameFingerprint
  let contentFingerprint: ContentFingerprint?

  init(
    windowID: CGWindowID,
    sequenceNumber: UInt64,
    capturedAt: Date,
    displayTime: UInt64? = nil,
    deliveryKind: CapturedFrameDeliveryKind,
    captureSurfaceGeometry: CaptureSurfaceGeometry? = nil,
    captureScreenGeometry: CaptureScreenGeometry? = nil,
    image: CGImage,
    fingerprint: FrameFingerprint,
    contentFingerprint: ContentFingerprint?
  ) {
    self.windowID = windowID
    self.sequenceNumber = sequenceNumber
    self.capturedAt = capturedAt
    self.displayTime = displayTime
    self.deliveryKind = deliveryKind
    self.captureSurfaceGeometry = captureSurfaceGeometry
    self.captureScreenGeometry = captureScreenGeometry
    self.image = image
    self.fingerprint = fingerprint
    self.contentFingerprint = contentFingerprint
  }
}

enum CapturedPowerPointFrameFactory {
  static func makeNewFrame(
    windowID: CGWindowID,
    sequenceNumber: UInt64,
    capturedAt: Date,
    displayTime: UInt64? = nil,
    captureSurfaceGeometry: CaptureSurfaceGeometry? = nil,
    captureScreenGeometry: CaptureScreenGeometry? = nil,
    image: CGImage,
    fingerprint: FrameFingerprint
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: capturedAt,
      displayTime: displayTime,
      deliveryKind: .new,
      captureSurfaceGeometry: captureSurfaceGeometry,
      captureScreenGeometry: captureScreenGeometry,
      image: image,
      fingerprint: fingerprint,
      contentFingerprint: CGImageRasterizer.makeContentFingerprint(from: image)
    )
  }

  static func makeIdleRepeat(
    from lastFrame: CapturedPowerPointFrame,
    sequenceNumber: UInt64,
    capturedAt: Date,
    currentAttachments: [SCStreamFrameInfo: Any]?
  ) -> CapturedPowerPointFrame {
    // ScreenCaptureKit defines idle as no newly generated frame because the
    // display did not change, but Apple does not document geometry attachment
    // presence for idle samples. As a provisional application policy, treat a
    // verified idle with all three surface keys absent as continuity of the
    // unchanged visual surface. Partial, malformed, or conflicting current
    // evidence remains fail closed and requires a later new frame to recover.
    let currentSurfaceGeometryState: CaptureSurfaceGeometryParser.AttachmentState
    if CaptureFrameDeliveryDecisionResolver.resolve(
      statusValue: currentAttachments?[.status]
    ) == .idleRepeat {
      currentSurfaceGeometryState = CaptureSurfaceGeometryParser.attachmentState(
        currentAttachments,
        outputPixelWidth: lastFrame.image.width,
        outputPixelHeight: lastFrame.image.height
      )
    } else {
      currentSurfaceGeometryState = .invalid
    }
    let repeatedSurfaceGeometry: CaptureSurfaceGeometry?
    let repeatedScreenGeometry: CaptureScreenGeometry?
    let currentScreenGeometry: CaptureScreenGeometry?
    if currentAttachments?.keys.contains(.screenRect) == true {
      // A present but malformed current screenRect must poison overlay mapping.
      // Reuse is allowed only when ScreenCaptureKit omitted the key entirely.
      currentScreenGeometry = CaptureScreenGeometryParser.parse(currentAttachments)
    } else {
      // The production eligibility check independently re-reads the exact
      // frontmost CGWindow and requires its current bounds to match this value
      // before rendering or renewing the short overlay lease.
      currentScreenGeometry = lastFrame.captureScreenGeometry
    }
    switch (lastFrame.captureSurfaceGeometry, currentSurfaceGeometryState) {
    case (.some(let lastSurfaceGeometry), .absent)
    where lastSurfaceGeometry.outputPixelWidth == lastFrame.image.width
      && lastSurfaceGeometry.outputPixelHeight == lastFrame.image.height:
      repeatedSurfaceGeometry = lastSurfaceGeometry
      repeatedScreenGeometry = currentScreenGeometry
    case (.some(let lastSurfaceGeometry), .valid(let currentSurfaceGeometry))
    where currentSurfaceGeometry == lastSurfaceGeometry:
      repeatedSurfaceGeometry = currentSurfaceGeometry
      repeatedScreenGeometry = currentScreenGeometry
    default:
      repeatedSurfaceGeometry = nil
      repeatedScreenGeometry = nil
    }

    // Idle means no new visual content: reuse only the prior visual payload and
    // display time. A current valid screenRect replaces the prior value; a
    // malformed present value fails closed. When ScreenCaptureKit omits the key,
    // the prior value is only a candidate for the independent live window
    // eligibility check and its short lease.
    return CapturedPowerPointFrame(
      windowID: lastFrame.windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: capturedAt,
      displayTime: lastFrame.displayTime,
      deliveryKind: .idleRepeat,
      captureSurfaceGeometry: repeatedSurfaceGeometry,
      captureScreenGeometry: repeatedScreenGeometry,
      image: lastFrame.image,
      fingerprint: lastFrame.fingerprint,
      contentFingerprint: lastFrame.contentFingerprint
    )
  }
}

enum PowerPointWindowCaptureError: LocalizedError {
  case selectedWindowUnavailable

  var errorDescription: String? {
    switch self {
    case .selectedWindowUnavailable:
      NSLocalizedString("error.captureWindowUnavailable", comment: "")
    }
  }
}

enum FreshPowerPointWindowSampleError: Error, Equatable, Sendable {
  case unsupported
  case inactiveCapture
  case requestAlreadyInFlight
  case selectedWindowUnavailable
  case invalidSample
}

enum CaptureFrameDisplayTimeParser {
  static func parse(_ value: Any?) -> UInt64? {
    if let number = value as? NSNumber,
      CFGetTypeID(number) == CFBooleanGetTypeID()
    {
      return nil
    }
    if let value = value as? UInt64, value > 0 {
      return value
    }
    if let value = value as? NSNumber, value.uint64Value > 0 {
      return UInt64(value.stringValue)
    }
    return nil
  }
}

struct CaptureOperationID: Comparable, Hashable, Sendable {
  let rawValue: UInt64

  static func < (lhs: CaptureOperationID, rhs: CaptureOperationID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

struct CaptureSessionLifecycle: Sendable {
  private(set) var latestOperationID: CaptureOperationID?
  private(set) var activeSessionID: CaptureOperationID?

  mutating func acceptStart(_ operationID: CaptureOperationID) -> Bool {
    guard isNewer(operationID) else { return false }
    latestOperationID = operationID
    activeSessionID = operationID
    return true
  }

  mutating func acceptStop(_ operationID: CaptureOperationID) -> Bool {
    guard isNewer(operationID) else { return false }
    latestOperationID = operationID
    activeSessionID = nil
    return true
  }

  func isCurrent(_ operationID: CaptureOperationID) -> Bool {
    latestOperationID == operationID && activeSessionID == operationID
  }

  mutating func finishFailedStart(_ operationID: CaptureOperationID) {
    guard isCurrent(operationID) else { return }
    activeSessionID = nil
  }

  private func isNewer(_ operationID: CaptureOperationID) -> Bool {
    guard let latestOperationID else { return true }
    return operationID > latestOperationID
  }
}

struct FreshSampleCaptureLifecycle: Sendable {
  private(set) var activeOperationID: CaptureOperationID?
  private(set) var activeIdentity: PowerPointWindowIdentity?
  private(set) var inFlightRequestID: FreshSampleRequestID?

  mutating func activate(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity
  ) {
    activeOperationID = operationID
    activeIdentity = identity
  }

  mutating func deactivate() {
    activeOperationID = nil
    activeIdentity = nil
  }

  mutating func beginRequest(
    _ requestID: FreshSampleRequestID,
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity
  ) -> Bool {
    guard
      activeOperationID == operationID,
      activeIdentity == identity,
      inFlightRequestID == nil
    else {
      return false
    }
    inFlightRequestID = requestID
    return true
  }

  func acceptsCompletion(
    requestID: FreshSampleRequestID,
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity
  ) -> Bool {
    activeOperationID == operationID
      && activeIdentity == identity
      && inFlightRequestID == requestID
  }

  mutating func finishRequest(_ requestID: FreshSampleRequestID) {
    guard inFlightRequestID == requestID else { return }
    inFlightRequestID = nil
  }
}

typealias CaptureFrameHandler = @Sendable (CapturedPowerPointFrame) -> Void
typealias CaptureContentUnavailableHandler = @Sendable (UInt64) -> Void
typealias CaptureErrorHandler = @Sendable (String) -> Void
typealias CaptureFailureHandler = @Sendable (CaptureFailureEvent) -> Void

struct CaptureFailureEvent: Equatable, Sendable {
  let message: String
  let source: RuntimeCaptureFailureSource
  let scStreamErrorCode: RuntimeSCStreamErrorCode?
}

final class CaptureTerminalFailureGate: Sendable {
  private let hasReportedFailure = Mutex(false)

  @discardableResult
  func report(
    _ event: CaptureFailureEvent,
    to failureHandler: CaptureFailureHandler
  ) -> Bool {
    let accepted = hasReportedFailure.withLock { hasReportedFailure in
      guard !hasReportedFailure else { return false }
      hasReportedFailure = true
      return true
    }
    guard accepted else { return false }
    failureHandler(event)
    return true
  }
}

final class CaptureTerminalFailureRouter: Sendable {
  private let failureHandler: CaptureFailureHandler
  private let gate = CaptureTerminalFailureGate()

  init(failureHandler: @escaping CaptureFailureHandler) {
    self.failureHandler = failureHandler
  }

  @discardableResult
  func reportSampleStatusStopped(message: String) -> Bool {
    gate.report(
      CaptureFailureEventFactory.sampleStatusStopped(message: message),
      to: failureHandler
    )
  }

  @discardableResult
  func reportDelegateStopped(error: any Error) -> Bool {
    gate.report(
      CaptureFailureEventFactory.delegateStopped(error: error),
      to: failureHandler
    )
  }

  @discardableResult
  func reportDelegateBecameInactive(message: String) -> Bool {
    gate.report(
      CaptureFailureEventFactory.delegateBecameInactive(message: message),
      to: failureHandler
    )
  }
}

enum CaptureFailureEventFactory {
  static func sampleStatusStopped(message: String) -> CaptureFailureEvent {
    CaptureFailureEvent(
      message: message,
      source: .sampleStatusStopped,
      scStreamErrorCode: nil
    )
  }

  static func delegateStopped(error: any Error) -> CaptureFailureEvent {
    event(
      error: error,
      knownSource: .delegateStoppedWithKnownSCError,
      unknownSCSource: .delegateStoppedWithUnknownSCError,
      unknownSource: .delegateStoppedWithUnknownError
    )
  }

  static func delegateBecameInactive(message: String) -> CaptureFailureEvent {
    CaptureFailureEvent(
      message: message,
      source: .delegateBecameInactive,
      scStreamErrorCode: nil
    )
  }

  static func startFailed(error: any Error) -> CaptureFailureEvent {
    event(
      error: error,
      knownSource: .startFailedWithKnownSCError,
      unknownSCSource: .startFailedWithUnknownSCError,
      unknownSource: .startFailedWithUnknownError
    )
  }

  static func unclassified(message: String) -> CaptureFailureEvent {
    CaptureFailureEvent(
      message: message,
      source: .unclassifiedCaptureFailure,
      scStreamErrorCode: nil
    )
  }

  private static func event(
    error: any Error,
    knownSource: RuntimeCaptureFailureSource,
    unknownSCSource: RuntimeCaptureFailureSource,
    unknownSource: RuntimeCaptureFailureSource
  ) -> CaptureFailureEvent {
    let nsError = error as NSError
    guard nsError.domain == SCStreamErrorDomain else {
      return CaptureFailureEvent(
        message: error.localizedDescription,
        source: unknownSource,
        scStreamErrorCode: nil
      )
    }
    guard let code = RuntimeSCStreamErrorCodeNormalizer.normalize(nsError.code) else {
      return CaptureFailureEvent(
        message: error.localizedDescription,
        source: unknownSCSource,
        scStreamErrorCode: nil
      )
    }
    return CaptureFailureEvent(
      message: error.localizedDescription,
      source: knownSource,
      scStreamErrorCode: code
    )
  }
}

enum RuntimeSCStreamErrorCodeNormalizer {
  static func normalize(_ rawCode: Int) -> RuntimeSCStreamErrorCode? {
    guard let code = SCStreamError.Code(rawValue: rawCode) else { return nil }
    switch code {
    case .userDeclined:
      return .userDeclined
    case .failedToStart:
      return .failedToStart
    case .missingEntitlements:
      return .missingEntitlements
    case .failedApplicationConnectionInvalid:
      return .failedApplicationConnectionInvalid
    case .failedApplicationConnectionInterrupted:
      return .failedApplicationConnectionInterrupted
    case .failedNoMatchingApplicationContext:
      return .failedNoMatchingApplicationContext
    case .attemptToStartStreamState:
      return .attemptToStartStreamState
    case .attemptToStopStreamState:
      return .attemptToStopStreamState
    case .attemptToUpdateFilterState:
      return .attemptToUpdateFilterState
    case .attemptToConfigState:
      return .attemptToConfigState
    case .internalError:
      return .internalError
    case .invalidParameter:
      return .invalidParameter
    case .noWindowList:
      return .noWindowList
    case .noDisplayList:
      return .noDisplayList
    case .noCaptureSource:
      return .noCaptureSource
    case .removingStream:
      return .removingStream
    case .userStopped:
      return .userStopped
    case .failedToStartAudioCapture:
      return .failedToStartAudioCapture
    case .failedToStopAudioCapture:
      return .failedToStopAudioCapture
    case .failedToStartMicrophoneCapture:
      return .failedToStartMicrophoneCapture
    case .systemStoppedStream:
      return .systemStoppedStream
    @unknown default:
      return nil
    }
  }
}

protocol PowerPointWindowCapturing: Sendable {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws

  func stop(operationID: CaptureOperationID) async

  func captureFreshSample(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    requestID: FreshSampleRequestID
  ) async throws -> FreshPowerPointWindowSample

  func managedSlideShowRoleCaptureEvidenceLease(
    operationID: CaptureOperationID
  ) async throws -> PowerPointManagedSlideShowRoleCaptureEvidenceLease
}

extension PowerPointWindowCapturing {
  func managedSlideShowRoleCaptureEvidenceLease(
    operationID: CaptureOperationID
  ) async throws -> PowerPointManagedSlideShowRoleCaptureEvidenceLease {
    throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
  }

  func captureFreshSample(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    requestID: FreshSampleRequestID
  ) async throws -> FreshPowerPointWindowSample {
    throw FreshPowerPointWindowSampleError.unsupported
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws {
    try await start(
      operationID: operationID,
      identity: identity,
      onFrame: onFrame,
      onContentUnavailable: onContentUnavailable,
      onError: { message in
        onFailure(CaptureFailureEventFactory.unclassified(message: message))
      }
    )
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    try await start(
      operationID: operationID,
      identity: identity,
      onFrame: onFrame,
      onError: onError
    )
  }
}

struct ReenumeratedPowerPointWindowCandidate: Equatable, Sendable {
  let windowID: CGWindowID
  let ownerProcessID: pid_t?
  let bundleIdentifier: String?

  var identity: PowerPointWindowIdentity? {
    guard let ownerProcessID, let bundleIdentifier else { return nil }
    return PowerPointWindowIdentity(
      windowID: windowID,
      ownerProcessID: ownerProcessID,
      bundleIdentifier: bundleIdentifier
    )
  }
}

enum ReenumeratedPowerPointWindowResolver {
  static func uniqueMatchingIndex(
    for expectedIdentity: PowerPointWindowIdentity,
    among candidates: [ReenumeratedPowerPointWindowCandidate]
  ) -> Int? {
    let identifierMatches = candidates.indices.filter {
      candidates[$0].windowID == expectedIdentity.windowID
    }
    guard identifierMatches.count == 1,
      let index = identifierMatches.first,
      candidates[index].identity == expectedIdentity
    else {
      return nil
    }
    return index
  }
}

actor PowerPointWindowCapture: PowerPointWindowCapturing {
  private var lifecycle = CaptureSessionLifecycle()
  private var freshSampleLifecycle = FreshSampleCaptureLifecycle()
  private var roleEvidenceCaptureGeneration: UInt64 = 0

  private var stream: SCStream?
  private var output: CaptureOutput?
  private var roleEvidenceLease: PowerPointManagedSlideShowRoleCaptureEvidenceLease?

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    try await start(
      operationID: operationID,
      identity: identity,
      onFrame: onFrame,
      onContentUnavailable: { _ in },
      onFailure: { event in onError(event.message) }
    )
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    try await start(
      operationID: operationID,
      identity: identity,
      onFrame: onFrame,
      onContentUnavailable: onContentUnavailable,
      onFailure: { event in onError(event.message) }
    )
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws {
    guard lifecycle.acceptStart(operationID) else {
      throw CancellationError()
    }
    freshSampleLifecycle.deactivate()

    let previousStream = stream
    let previousOutput = output
    let previousRoleEvidenceLease = roleEvidenceLease
    stream = nil
    output = nil
    roleEvidenceLease = nil

    if let previousRoleEvidenceLease {
      await previousRoleEvidenceLease.stop()
    }

    if previousRoleEvidenceLease == nil, let previousStream {
      try? await previousStream.stopCapture()
      if let previousOutput {
        try? previousStream.removeStreamOutput(previousOutput, type: .screen)
      }
    }

    guard lifecycle.isCurrent(operationID) else {
      throw CancellationError()
    }

    let content: SCShareableContent
    do {
      // Re-resolve the already selected exact identity across Spaces. This does not broaden the
      // capture filter: the stream below still uses only the one retained SCWindow.
      content = try await SCShareableContent.excludingDesktopWindows(
        true,
        onScreenWindowsOnly: false
      )
    } catch {
      lifecycle.finishFailedStart(operationID)
      throw error
    }
    guard lifecycle.isCurrent(operationID) else {
      throw CancellationError()
    }
    let candidates = content.windows.map { window in
      ReenumeratedPowerPointWindowCandidate(
        windowID: window.windowID,
        ownerProcessID: window.owningApplication?.processID,
        bundleIdentifier: window.owningApplication?.bundleIdentifier
      )
    }
    guard
      let windowIndex = ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: identity,
        among: candidates
      )
    else {
      lifecycle.finishFailedStart(operationID)
      throw PowerPointWindowCaptureError.selectedWindowUnavailable
    }
    let window = content.windows[windowIndex]

    guard roleEvidenceCaptureGeneration < UInt64.max else {
      lifecycle.finishFailedStart(operationID)
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }
    roleEvidenceCaptureGeneration += 1
    let roleEvidenceComponents: PowerPointManagedSlideShowRoleScreenCaptureEvidenceLeaseComponents
    do {
      roleEvidenceComponents =
        try PowerPointManagedSlideShowRoleScreenCaptureEvidenceLeaseFactory
        .make(
          captureOperationID: operationID,
          captureGeneration: roleEvidenceCaptureGeneration,
          candidateWindow: window,
          retainedPowerPointWindows: content.windows
        )
    } catch {
      lifecycle.finishFailedStart(operationID)
      throw error
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = makeConfiguration(for: filter)
    let output = CaptureOutput(
      windowID: identity.windowID,
      frameHandler: onFrame,
      contentUnavailableHandler: onContentUnavailable,
      failureHandler: onFailure,
      roleEvidenceRecorder: roleEvidenceComponents.primaryRecorder
    )
    let stream = SCStream(
      filter: filter,
      configuration: configuration,
      delegate: output
    )
    try stream.addStreamOutput(
      output,
      type: .screen,
      sampleHandlerQueue: output.sampleHandlerQueue
    )
    let roleEvidenceStopHandle = PowerPointManagedSlideShowRolePrimaryStreamStopHandle(
      stream: stream,
      output: output
    )
    try roleEvidenceComponents.primaryRecorder.installStopAction {
      await roleEvidenceStopHandle.stop()
    }

    do {
      try await stream.startCapture()
      guard lifecycle.isCurrent(operationID) else {
        await roleEvidenceComponents.lease.stop()
        throw CancellationError()
      }
      self.output = output
      self.stream = stream
      roleEvidenceLease = roleEvidenceComponents.lease
      freshSampleLifecycle.activate(
        operationID: operationID,
        identity: identity
      )
    } catch {
      await roleEvidenceComponents.lease.stop()
      lifecycle.finishFailedStart(operationID)
      throw error
    }
  }

  func stop(operationID: CaptureOperationID) async {
    guard lifecycle.acceptStop(operationID) else { return }
    freshSampleLifecycle.deactivate()
    let stream = stream
    let output = output
    let roleEvidenceLease = roleEvidenceLease
    self.stream = nil
    self.output = nil
    self.roleEvidenceLease = nil
    if let roleEvidenceLease {
      await roleEvidenceLease.stop()
    }
    guard roleEvidenceLease == nil else { return }
    guard let stream else { return }
    try? await stream.stopCapture()
    if let output {
      try? stream.removeStreamOutput(output, type: .screen)
    }
  }

  /// Returns only the lease created from the exact `SCWindow` objects retained at capture start.
  func managedSlideShowRoleCaptureEvidenceLease(
    operationID: CaptureOperationID
  ) async throws -> PowerPointManagedSlideShowRoleCaptureEvidenceLease {
    guard lifecycle.isCurrent(operationID), stream != nil, output != nil,
      let roleEvidenceLease,
      roleEvidenceLease.captureOperationID == operationID
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    }
    return roleEvidenceLease
  }

  func captureFreshSample(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    requestID: FreshSampleRequestID
  ) async throws -> FreshPowerPointWindowSample {
    guard lifecycle.isCurrent(operationID), stream != nil, output != nil else {
      throw FreshPowerPointWindowSampleError.inactiveCapture
    }
    guard
      freshSampleLifecycle.beginRequest(
        requestID,
        operationID: operationID,
        identity: identity
      )
    else {
      if freshSampleLifecycle.inFlightRequestID != nil {
        throw FreshPowerPointWindowSampleError.requestAlreadyInFlight
      }
      throw FreshPowerPointWindowSampleError.inactiveCapture
    }
    defer {
      freshSampleLifecycle.finishRequest(requestID)
    }

    let window = try await reenumeratedWindow(for: identity)
    try ensureCurrentFreshSampleRequest(
      requestID,
      operationID: operationID,
      identity: identity
    )

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = makeConfiguration(for: filter)
    let requestStartedMachAbsoluteTime = mach_absolute_time()
    let surface = try await captureFreshSurface(
      contentFilter: filter,
      configuration: configuration
    )
    try ensureCurrentFreshSampleRequest(
      requestID,
      operationID: operationID,
      identity: identity
    )

    _ = try await reenumeratedWindow(for: identity)
    try ensureCurrentFreshSampleRequest(
      requestID,
      operationID: operationID,
      identity: identity
    )

    return FreshPowerPointWindowSample(
      requestID: requestID,
      captureOperationID: operationID,
      identity: identity,
      requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime,
      capturedAt: surface.capturedAt,
      captureSurfaceGeometry: surface.captureSurfaceGeometry,
      image: surface.image
    )
  }

  private func ensureCurrentFreshSampleRequest(
    _ requestID: FreshSampleRequestID,
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity
  ) throws {
    guard
      lifecycle.isCurrent(operationID),
      stream != nil,
      output != nil,
      freshSampleLifecycle.acceptsCompletion(
        requestID: requestID,
        operationID: operationID,
        identity: identity
      )
    else {
      throw FreshPowerPointWindowSampleError.inactiveCapture
    }
  }

  private func reenumeratedWindow(
    for identity: PowerPointWindowIdentity
  ) async throws -> SCWindow {
    // A fullscreen PowerPoint surface can leave the active Space while the controller app is
    // foreground. Re-resolve only the exact bound ID/PID/bundle, then capture that one window.
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: false
    )
    let candidates = content.windows.map { window in
      ReenumeratedPowerPointWindowCandidate(
        windowID: window.windowID,
        ownerProcessID: window.owningApplication?.processID,
        bundleIdentifier: window.owningApplication?.bundleIdentifier
      )
    }
    guard
      let windowIndex = ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: identity,
        among: candidates
      )
    else {
      throw FreshPowerPointWindowSampleError.selectedWindowUnavailable
    }
    return content.windows[windowIndex]
  }

  private func captureFreshSurface(
    contentFilter: SCContentFilter,
    configuration: SCStreamConfiguration
  ) async throws -> FreshCapturedPowerPointSurface {
    try await withCheckedThrowingContinuation { continuation in
      SCScreenshotManager.captureSampleBuffer(
        contentFilter: contentFilter,
        configuration: configuration
      ) { sampleBuffer, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard
          let sampleBuffer,
          let surface = FreshPowerPointSampleBufferConverter.makeSurface(
            from: sampleBuffer,
            capturedAt: Date()
          )
        else {
          continuation.resume(
            throwing: FreshPowerPointWindowSampleError.invalidSample
          )
          return
        }
        continuation.resume(returning: surface)
      }
    }
  }

  private func makeConfiguration(for filter: SCContentFilter) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    let nativeWidth = max(filter.contentRect.width * CGFloat(filter.pointPixelScale), 2)
    let nativeHeight = max(filter.contentRect.height * CGFloat(filter.pointPixelScale), 2)
    let longestEdge = max(nativeWidth, nativeHeight)
    let scale = min(1, 1920 / longestEdge)

    configuration.width = Int(nativeWidth * scale)
    configuration.height = Int(nativeHeight * scale)
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.queueDepth = 3
    configuration.scalesToFit = true
    configuration.preservesAspectRatio = true
    configuration.showsCursor = false
    configuration.capturesAudio = false
    configuration.ignoreShadowsSingleWindow = true
    return configuration
  }
}

struct FreshCapturedPowerPointSurface: @unchecked Sendable {
  let capturedAt: Date
  let captureSurfaceGeometry: CaptureSurfaceGeometry
  let image: CGImage
}

enum FreshPowerPointSampleBufferConverter {
  static func makeSurface(
    from sampleBuffer: CMSampleBuffer,
    capturedAt: Date
  ) -> FreshCapturedPowerPointSurface? {
    let attachments = frameAttachments(in: sampleBuffer)
    guard
      sampleBuffer.isValid,
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: attachments?[.status]
      ) == .newFrame,
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
      CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
    else {
      return nil
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let imageContext = CIContext(options: [.cacheIntermediates: false])
    guard
      let image = imageContext.createCGImage(inputImage, from: inputImage.extent),
      let captureSurfaceGeometry = CaptureSurfaceGeometryParser.parse(
        attachments,
        outputPixelWidth: image.width,
        outputPixelHeight: image.height
      )
    else {
      return nil
    }

    return FreshCapturedPowerPointSurface(
      capturedAt: capturedAt,
      captureSurfaceGeometry: captureSurfaceGeometry,
      image: image
    )
  }

  private static func frameAttachments(
    in sampleBuffer: CMSampleBuffer
  ) -> [SCStreamFrameInfo: Any]? {
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: false
      ) as? [[SCStreamFrameInfo: Any]]
    else {
      return nil
    }
    return attachments.first
  }
}

/// Exact primary stream/output pair retained by the role-evidence lease's bounded stop task.
private final class PowerPointManagedSlideShowRolePrimaryStreamStopHandle: @unchecked Sendable {
  private let stream: SCStream
  private let output: CaptureOutput

  init(stream: SCStream, output: CaptureOutput) {
    self.stream = stream
    self.output = output
  }

  func stop() async {
    try? await stream.stopCapture()
    try? stream.removeStreamOutput(output, type: .screen)
  }
}

private final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate,
  @unchecked Sendable
{
  let sampleHandlerQueue = DispatchQueue(
    label: "io.github.akiyama709.LectureBoardAI.window-capture",
    qos: .userInitiated
  )

  private let windowID: CGWindowID
  private let frameHandler: CaptureFrameHandler
  private let contentUnavailableHandler: CaptureContentUnavailableHandler
  private let terminalFailureRouter: CaptureTerminalFailureRouter
  private let roleEvidenceRecorder: PowerPointManagedSlideShowRoleCaptureDeliveryBuffer
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private var sequenceNumber: UInt64 = 0
  private var continuity = CaptureOutputContinuity<CapturedPowerPointFrame>()

  init(
    windowID: CGWindowID,
    frameHandler: @escaping CaptureFrameHandler,
    contentUnavailableHandler: @escaping CaptureContentUnavailableHandler,
    failureHandler: @escaping CaptureFailureHandler,
    roleEvidenceRecorder: PowerPointManagedSlideShowRoleCaptureDeliveryBuffer
  ) {
    self.windowID = windowID
    self.frameHandler = frameHandler
    self.contentUnavailableHandler = contentUnavailableHandler
    self.roleEvidenceRecorder = roleEvidenceRecorder
    terminalFailureRouter = CaptureTerminalFailureRouter(failureHandler: failureHandler)
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen else { return }
    precondition(sequenceNumber < UInt64.max, "Capture delivery sequence exhausted.")
    sequenceNumber += 1
    let deliverySequenceNumber = sequenceNumber
    let callbackMachAbsoluteTime = mach_absolute_time()
    guard sampleBuffer.isValid else {
      reportContentUnavailable(sequenceNumber: deliverySequenceNumber)
      return
    }

    switch frameDeliveryDecision(in: sampleBuffer) {
    case .idleRepeat:
      emitRepeatedFrameIfAvailable(
        from: sampleBuffer,
        sequenceNumber: deliverySequenceNumber,
        callbackMachAbsoluteTime: callbackMachAbsoluteTime
      )
    case .newFrame:
      emitNewFrame(
        from: sampleBuffer,
        sequenceNumber: deliverySequenceNumber,
        callbackMachAbsoluteTime: callbackMachAbsoluteTime
      )
    case .terminalFailure:
      continuity.markContentUnavailable()
      roleEvidenceRecorder.recordGap()
      terminalFailureRouter.reportSampleStatusStopped(
        message: NSLocalizedString("error.captureWindowInactive", comment: "")
      )
    case .drop:
      reportContentUnavailable(sequenceNumber: deliverySequenceNumber)
      return
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: any Error) {
    roleEvidenceRecorder.recordGap()
    terminalFailureRouter.reportDelegateStopped(error: error)
  }

  func streamDidBecomeInactive(_ stream: SCStream) {
    roleEvidenceRecorder.recordGap()
    terminalFailureRouter.reportDelegateBecameInactive(
      message: NSLocalizedString("error.captureWindowInactive", comment: "")
    )
  }

  private func emitRepeatedFrameIfAvailable(
    from sampleBuffer: CMSampleBuffer,
    sequenceNumber: UInt64,
    callbackMachAbsoluteTime: UInt64
  ) {
    let currentAttachments = frameAttachments(in: sampleBuffer)
    guard
      let repeatedFrame = continuity.makeAndAcceptRepeatedPayload({ lastFrame in
        CapturedPowerPointFrameFactory.makeIdleRepeat(
          from: lastFrame,
          sequenceNumber: sequenceNumber,
          capturedAt: Date(),
          currentAttachments: currentAttachments
        )
      })
    else {
      reportContentUnavailable(sequenceNumber: sequenceNumber)
      return
    }
    // Preserve fail-closed gaps. Once an idle delivery supplies partial,
    // malformed, or conflicting geometry, a later metadata-empty idle delivery
    // cannot revive geometry from the older new frame; only a later new frame
    // can re-establish it.
    roleEvidenceRecorder.recordIdle(
      deliverySequence: sequenceNumber,
      callbackMachAbsoluteTime: callbackMachAbsoluteTime
    )
    frameHandler(repeatedFrame)
  }

  private func emitNewFrame(
    from sampleBuffer: CMSampleBuffer,
    sequenceNumber: UInt64,
    callbackMachAbsoluteTime: UInt64
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      reportContentUnavailable(sequenceNumber: sequenceNumber)
      return
    }
    guard let fingerprint = FrameFingerprintSampler.makeFingerprint(from: pixelBuffer) else {
      reportContentUnavailable(sequenceNumber: sequenceNumber)
      return
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let image = imageContext.createCGImage(inputImage, from: inputImage.extent) else {
      reportContentUnavailable(sequenceNumber: sequenceNumber)
      return
    }

    let attachments = frameAttachments(in: sampleBuffer)
    let displayTime = CaptureFrameDisplayTimeParser.parse(attachments?[.displayTime])
    let frame = CapturedPowerPointFrameFactory.makeNewFrame(
      windowID: windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(),
      displayTime: displayTime,
      captureSurfaceGeometry: CaptureSurfaceGeometryParser.parse(
        attachments,
        outputPixelWidth: image.width,
        outputPixelHeight: image.height
      ),
      captureScreenGeometry: CaptureScreenGeometryParser.parse(attachments),
      image: image,
      fingerprint: fingerprint
    )
    continuity.acceptNewPayload(frame)
    roleEvidenceRecorder.recordGenerated(
      fingerprint: fingerprint,
      displayTime: displayTime,
      deliverySequence: sequenceNumber,
      callbackMachAbsoluteTime: callbackMachAbsoluteTime
    )
    frameHandler(frame)
  }

  private func reportContentUnavailable(sequenceNumber: UInt64) {
    continuity.markContentUnavailable()
    roleEvidenceRecorder.recordGap()
    contentUnavailableHandler(sequenceNumber)
  }

  private func frameDeliveryDecision(
    in sampleBuffer: CMSampleBuffer
  ) -> CaptureFrameDeliveryDecision {
    CaptureFrameDeliveryDecisionResolver.resolve(
      statusValue: frameAttachments(in: sampleBuffer)?[.status]
    )
  }

  private func frameAttachments(
    in sampleBuffer: CMSampleBuffer
  ) -> [SCStreamFrameInfo: Any]? {
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: false
      ) as? [[SCStreamFrameInfo: Any]]
    else {
      return nil
    }
    return attachments.first
  }
}

enum FrameFingerprintSampler {
  static let sampleColumns = 32
  static let sampleRows = 18

  struct PixelCrop: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init?(surfaceGeometry: CaptureSurfaceGeometry) {
      // `contentRect` is already expressed in points in the output surface. Only the documented
      // pixels-per-point scale converts it to buffer pixels; `contentScale` is not another factor.
      let scaleFactor = surfaceGeometry.scaleFactor
      let rawMinimumX = surfaceGeometry.contentOriginX * scaleFactor
      let rawMinimumY = surfaceGeometry.contentOriginY * scaleFactor
      let rawMaximumX =
        (surfaceGeometry.contentOriginX + surfaceGeometry.contentWidth) * scaleFactor
      let rawMaximumY =
        (surfaceGeometry.contentOriginY + surfaceGeometry.contentHeight) * scaleFactor
      let values = [rawMinimumX, rawMinimumY, rawMaximumX, rawMaximumY]
      guard values.allSatisfy(\.isFinite),
        let minimumX = Int(exactly: rawMinimumX.rounded(.up)),
        let minimumY = Int(exactly: rawMinimumY.rounded(.up)),
        let maximumX = Int(exactly: rawMaximumX.rounded(.down)),
        let maximumY = Int(exactly: rawMaximumY.rounded(.down)),
        minimumX >= 0,
        minimumY >= 0,
        maximumX > minimumX,
        maximumY > minimumY,
        maximumX <= surfaceGeometry.outputPixelWidth,
        maximumY <= surfaceGeometry.outputPixelHeight
      else {
        return nil
      }
      x = minimumX
      y = minimumY
      width = maximumX - minimumX
      height = maximumY - minimumY
    }
  }

  static func makeFingerprint(
    from pixelBuffer: CVPixelBuffer,
    pixelCrop: PixelCrop? = nil
  ) -> FrameFingerprint? {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
      return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard width > 0, height > 0 else { return nil }
    let crop: PixelCrop
    if let pixelCrop {
      let (maximumX, horizontalOverflow) = pixelCrop.x.addingReportingOverflow(pixelCrop.width)
      let (maximumY, verticalOverflow) = pixelCrop.y.addingReportingOverflow(pixelCrop.height)
      guard pixelCrop.x >= 0, pixelCrop.y >= 0, pixelCrop.width > 0, pixelCrop.height > 0,
        !horizontalOverflow, !verticalOverflow, maximumX <= width, maximumY <= height
      else { return nil }
      crop = pixelCrop
    } else {
      guard
        let fullBuffer = CaptureSurfaceGeometry(
          contentRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
          scaleFactor: 1,
          contentScale: 1,
          outputPixelWidth: width,
          outputPixelHeight: height
        ),
        let fullCrop = PixelCrop(surfaceGeometry: fullBuffer)
      else { return nil }
      crop = fullCrop
    }

    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
    var luminance: [UInt8] = []
    luminance.reserveCapacity(sampleColumns * sampleRows)

    for row in 0..<sampleRows {
      let y =
        crop.y
        + min(
          crop.height - 1,
          ((row * 2 + 1) * crop.height) / (sampleRows * 2)
        )
      for column in 0..<sampleColumns {
        let x =
          crop.x
          + min(
            crop.width - 1,
            ((column * 2 + 1) * crop.width) / (sampleColumns * 2)
          )
        let offset = y * bytesPerRow + x * 4
        let blue = Int(bytes[offset])
        let green = Int(bytes[offset + 1])
        let red = Int(bytes[offset + 2])
        luminance.append(UInt8((54 * red + 183 * green + 19 * blue) >> 8))
      }
    }

    return FrameFingerprint(
      sampleColumns: sampleColumns,
      sampleRows: sampleRows,
      luminance: luminance
    )
  }
}
