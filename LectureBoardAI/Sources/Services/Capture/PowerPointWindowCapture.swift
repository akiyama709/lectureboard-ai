import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import LectureBoardCore
import ScreenCaptureKit

enum CapturedFrameDeliveryKind: Equatable, Sendable {
  case new
  case idleRepeat
}

enum CaptureFrameDeliveryDecision: Equatable, Sendable {
  case newFrame
  case idleRepeat
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
    case .blank, .suspended, .stopped:
      return .drop
    @unknown default:
      return .drop
    }
  }

  private static func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
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
    let values = [
      Double(contentRect.origin.x),
      Double(contentRect.origin.y),
      Double(contentRect.width),
      Double(contentRect.height),
      scaleFactor,
      contentScale,
    ]
    guard
      values.allSatisfy(\.isFinite),
      contentRect.origin.x >= 0,
      contentRect.origin.y >= 0,
      contentRect.width > 0,
      contentRect.height > 0,
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
    contentWidth = Double(contentRect.width)
    contentHeight = Double(contentRect.height)
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

enum CaptureSurfaceGeometryParser {
  static func parse(
    _ attachments: [SCStreamFrameInfo: Any]?,
    outputPixelWidth: Int,
    outputPixelHeight: Int
  ) -> CaptureSurfaceGeometry? {
    guard
      let attachments,
      let contentRect = parseRect(attachments[.contentRect]),
      let scaleFactor = parsePositiveDouble(attachments[.scaleFactor]),
      let contentScale = parsePositiveDouble(attachments[.contentScale])
    else {
      return nil
    }

    return CaptureSurfaceGeometry(
      contentRect: contentRect,
      scaleFactor: scaleFactor,
      contentScale: contentScale,
      outputPixelWidth: outputPixelWidth,
      outputPixelHeight: outputPixelHeight
    )
  }

  private static func parseRect(_ value: Any?) -> CGRect? {
    if let rect = value as? CGRect {
      return rect
    }
    if let value = value as? NSValue {
      return value.rectValue
    }
    return nil
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

struct CapturedPowerPointFrame: @unchecked Sendable {
  let windowID: CGWindowID
  let sequenceNumber: UInt64
  let capturedAt: Date
  /// ScreenCaptureKit's mach absolute time for the displayed source frame.
  let displayTime: UInt64?
  let deliveryKind: CapturedFrameDeliveryKind
  let captureSurfaceGeometry: CaptureSurfaceGeometry?
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
    // The stream surface size is fixed for this capture. An idle sample may omit
    // its image buffer, but its geometry must still come from its own attachments.
    let parsedCurrentSurfaceGeometry = CaptureSurfaceGeometryParser.parse(
      currentAttachments,
      outputPixelWidth: lastFrame.image.width,
      outputPixelHeight: lastFrame.image.height
    )
    let repeatedSurfaceGeometry: CaptureSurfaceGeometry?
    if let lastSurfaceGeometry = lastFrame.captureSurfaceGeometry,
      let parsedCurrentSurfaceGeometry,
      parsedCurrentSurfaceGeometry == lastSurfaceGeometry
    {
      repeatedSurfaceGeometry = parsedCurrentSurfaceGeometry
    } else {
      repeatedSurfaceGeometry = nil
    }

    // Idle means no new visual content: reuse only the prior visual payload and
    // display time. Geometry remains valid only when current attachments attest
    // that the reused payload still has exactly the same surface placement.
    return CapturedPowerPointFrame(
      windowID: lastFrame.windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: capturedAt,
      displayTime: lastFrame.displayTime,
      deliveryKind: .idleRepeat,
      captureSurfaceGeometry: repeatedSurfaceGeometry,
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

enum CaptureFrameDisplayTimeParser {
  static func parse(_ value: Any?) -> UInt64? {
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

typealias CaptureFrameHandler = @Sendable (CapturedPowerPointFrame) -> Void
typealias CaptureErrorHandler = @Sendable (String) -> Void

protocol PowerPointWindowCapturing: Sendable {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws

  func stop(operationID: CaptureOperationID) async
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

  private var stream: SCStream?
  private var output: CaptureOutput?

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    guard lifecycle.acceptStart(operationID) else {
      throw CancellationError()
    }

    let previousStream = stream
    let previousOutput = output
    stream = nil
    output = nil

    if let previousStream {
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
      content = try await SCShareableContent.excludingDesktopWindows(
        true,
        onScreenWindowsOnly: true
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

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = makeConfiguration(for: filter)
    let output = CaptureOutput(
      windowID: identity.windowID,
      frameHandler: onFrame,
      errorHandler: onError
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

    do {
      try await stream.startCapture()
      guard lifecycle.isCurrent(operationID) else {
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(output, type: .screen)
        throw CancellationError()
      }
      self.output = output
      self.stream = stream
    } catch {
      try? stream.removeStreamOutput(output, type: .screen)
      lifecycle.finishFailedStart(operationID)
      throw error
    }
  }

  func stop(operationID: CaptureOperationID) async {
    guard lifecycle.acceptStop(operationID) else { return }
    let stream = stream
    let output = output
    self.stream = nil
    self.output = nil
    guard let stream else { return }
    try? await stream.stopCapture()
    if let output {
      try? stream.removeStreamOutput(output, type: .screen)
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

private final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate,
  @unchecked Sendable
{
  let sampleHandlerQueue = DispatchQueue(
    label: "io.github.akiyama709.LectureBoardAI.window-capture",
    qos: .userInitiated
  )

  private let windowID: CGWindowID
  private let frameHandler: CaptureFrameHandler
  private let errorHandler: CaptureErrorHandler
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private var sequenceNumber: UInt64 = 0
  private var lastFrame: CapturedPowerPointFrame?

  init(
    windowID: CGWindowID,
    frameHandler: @escaping CaptureFrameHandler,
    errorHandler: @escaping CaptureErrorHandler
  ) {
    self.windowID = windowID
    self.frameHandler = frameHandler
    self.errorHandler = errorHandler
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen, sampleBuffer.isValid else { return }

    switch frameDeliveryDecision(in: sampleBuffer) {
    case .idleRepeat:
      emitRepeatedFrameIfAvailable(from: sampleBuffer)
    case .newFrame:
      emitNewFrame(from: sampleBuffer)
    case .drop:
      return
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: any Error) {
    errorHandler(error.localizedDescription)
  }

  func streamDidBecomeInactive(_ stream: SCStream) {
    errorHandler(NSLocalizedString("error.captureWindowInactive", comment: ""))
  }

  private func emitRepeatedFrameIfAvailable(from sampleBuffer: CMSampleBuffer) {
    guard let lastFrame else { return }
    sequenceNumber &+= 1
    frameHandler(
      CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: lastFrame,
        sequenceNumber: sequenceNumber,
        capturedAt: Date(),
        currentAttachments: frameAttachments(in: sampleBuffer)
      )
    )
  }

  private func emitNewFrame(from sampleBuffer: CMSampleBuffer) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    guard let fingerprint = FrameFingerprintSampler.makeFingerprint(from: pixelBuffer) else {
      return
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let image = imageContext.createCGImage(inputImage, from: inputImage.extent) else {
      return
    }

    sequenceNumber &+= 1
    let frame = CapturedPowerPointFrameFactory.makeNewFrame(
      windowID: windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(),
      displayTime: frameDisplayTime(in: sampleBuffer),
      captureSurfaceGeometry: CaptureSurfaceGeometryParser.parse(
        frameAttachments(in: sampleBuffer),
        outputPixelWidth: image.width,
        outputPixelHeight: image.height
      ),
      image: image,
      fingerprint: fingerprint
    )
    lastFrame = frame
    frameHandler(frame)
  }

  private func frameDeliveryDecision(
    in sampleBuffer: CMSampleBuffer
  ) -> CaptureFrameDeliveryDecision {
    CaptureFrameDeliveryDecisionResolver.resolve(
      statusValue: frameAttachments(in: sampleBuffer)?[.status]
    )
  }

  private func frameDisplayTime(in sampleBuffer: CMSampleBuffer) -> UInt64? {
    CaptureFrameDisplayTimeParser.parse(
      frameAttachments(in: sampleBuffer)?[.displayTime]
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

private enum FrameFingerprintSampler {
  static let sampleColumns = 32
  static let sampleRows = 18

  static func makeFingerprint(from pixelBuffer: CVPixelBuffer) -> FrameFingerprint? {
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

    let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
    var luminance: [UInt8] = []
    luminance.reserveCapacity(sampleColumns * sampleRows)

    for row in 0..<sampleRows {
      let y = min(height - 1, ((row * 2 + 1) * height) / (sampleRows * 2))
      for column in 0..<sampleColumns {
        let x = min(width - 1, ((column * 2 + 1) * width) / (sampleColumns * 2))
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
