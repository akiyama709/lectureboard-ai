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

struct CapturedPowerPointFrame: @unchecked Sendable {
  let windowID: CGWindowID
  let sequenceNumber: UInt64
  let capturedAt: Date
  let deliveryKind: CapturedFrameDeliveryKind
  let image: CGImage
  let fingerprint: FrameFingerprint
  let contentFingerprint: ContentFingerprint?
}

enum CapturedPowerPointFrameFactory {
  static func makeNewFrame(
    windowID: CGWindowID,
    sequenceNumber: UInt64,
    capturedAt: Date,
    image: CGImage,
    fingerprint: FrameFingerprint
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: capturedAt,
      deliveryKind: .new,
      image: image,
      fingerprint: fingerprint,
      contentFingerprint: CGImageRasterizer.makeContentFingerprint(from: image)
    )
  }

  static func makeIdleRepeat(
    from lastFrame: CapturedPowerPointFrame,
    sequenceNumber: UInt64,
    capturedAt: Date
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: lastFrame.windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: capturedAt,
      deliveryKind: .idleRepeat,
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

    switch frameStatus(in: sampleBuffer) {
    case .blank, .suspended, .stopped:
      return
    case .idle:
      emitRepeatedFrameIfAvailable()
    case .complete, .started, nil:
      emitNewFrame(from: sampleBuffer)
    @unknown default:
      return
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: any Error) {
    errorHandler(error.localizedDescription)
  }

  func streamDidBecomeInactive(_ stream: SCStream) {
    errorHandler(NSLocalizedString("error.captureWindowInactive", comment: ""))
  }

  private func emitRepeatedFrameIfAvailable() {
    guard let lastFrame else { return }
    sequenceNumber &+= 1
    frameHandler(
      CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: lastFrame,
        sequenceNumber: sequenceNumber,
        capturedAt: Date()
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
      image: image,
      fingerprint: fingerprint
    )
    lastFrame = frame
    frameHandler(frame)
  }

  private func frameStatus(in sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: false
      ) as? [[SCStreamFrameInfo: Any]],
      let rawValue = attachments.first?[.status] as? Int
    else {
      return nil
    }
    return SCFrameStatus(rawValue: rawValue)
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
