import CoreGraphics
import Foundation
import LectureBoardCore
import ScreenCaptureKit
import Testing

@testable import LectureBoard_AI

struct CGImageRasterizerTests {
  @Test func preservesTopLeftRowMajorQuadrantsAndRGBChannels() throws {
    let image = try #require(
      makeImage(
        width: 2,
        height: 2,
        premultipliedRGBABytes: [
          255, 0, 0, 255, 0, 255, 0, 255,
          0, 0, 255, 255, 255, 255, 0, 255,
        ]
      )
    )

    let raster = try #require(
      CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 640)
    )

    #expect(raster.width == 2)
    #expect(raster.height == 2)
    #expect(
      raster.rgbBytes == [
        255, 0, 0, 0, 255, 0,
        0, 0, 255, 255, 255, 0,
      ]
    )
  }

  @Test func preservesAspectRatioWhenScalingLandscapeAndPortraitImages() throws {
    let landscape = try #require(makeSolidImage(width: 800, height: 400))
    let portrait = try #require(makeSolidImage(width: 400, height: 800))

    let landscapeRaster = try #require(
      CGImageRasterizer.makeRGBRaster(from: landscape, maximumLongEdge: 640)
    )
    let portraitRaster = try #require(
      CGImageRasterizer.makeRGBRaster(from: portrait, maximumLongEdge: 640)
    )

    #expect(landscapeRaster.width == 640)
    #expect(landscapeRaster.height == 320)
    #expect(portraitRaster.width == 320)
    #expect(portraitRaster.height == 640)
  }

  @Test func doesNotEnlargeImagesBelowTheMaximumLongEdge() throws {
    let image = try #require(makeSolidImage(width: 320, height: 180))

    let raster = try #require(
      CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 640)
    )

    #expect(raster.width == 320)
    #expect(raster.height == 180)
  }

  @Test func producesDefaultFixedSizeFingerprint() throws {
    let image = try #require(makeSolidImage(width: 320, height: 180))

    let fingerprint = try #require(
      CGImageRasterizer.makeContentFingerprint(from: image)
    )

    #expect(fingerprint.sampleColumns == 160)
    #expect(fingerprint.sampleRows == 90)
    #expect(fingerprint.cells.count == 160 * 90)
    #expect(fingerprint.isValid)
  }

  @Test func captureFrameFactoryWiresDenseFingerprintIntoNewDelivery() throws {
    let image = try #require(makeSolidImage(width: 320, height: 180))
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 42, count: 32 * 18)
    )
    let capturedAt = Date(timeIntervalSince1970: 123)
    let displayTime: UInt64 = 12_345
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 3, y: 4, width: 300, height: 160),
        scaleFactor: 2,
        contentScale: 0.75,
        outputPixelWidth: 320,
        outputPixelHeight: 180
      )
    )
    let screenGeometry = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: -320, y: 24, width: 320, height: 180)
      )
    )

    let frame = CapturedPowerPointFrameFactory.makeNewFrame(
      windowID: 42,
      sequenceNumber: 7,
      capturedAt: capturedAt,
      displayTime: displayTime,
      captureSurfaceGeometry: geometry,
      captureScreenGeometry: screenGeometry,
      image: image,
      fingerprint: coarseFingerprint
    )

    #expect(frame.windowID == 42)
    #expect(frame.sequenceNumber == 7)
    #expect(frame.capturedAt == capturedAt)
    #expect(frame.displayTime == displayTime)
    #expect(frame.deliveryKind == .new)
    #expect(frame.captureSurfaceGeometry == geometry)
    #expect(frame.captureScreenGeometry == screenGeometry)
    #expect(frame.fingerprint == coarseFingerprint)
    let contentFingerprint = try #require(frame.contentFingerprint)
    #expect(contentFingerprint.sampleColumns == 160)
    #expect(contentFingerprint.sampleRows == 90)
    #expect(contentFingerprint.cells.count == 160 * 90)
    #expect(contentFingerprint.isValid)

    #expect(CaptureFrameDisplayTimeParser.parse(UInt64(123)) == 123)
    #expect(CaptureFrameDisplayTimeParser.parse(NSNumber(value: 456)) == 456)
    #expect(CaptureFrameDisplayTimeParser.parse(NSNumber(value: -1)) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse(NSNumber(value: 1.5)) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse(NSNumber(value: true)) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse(NSNumber(value: false)) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse(true) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse(false) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse(UInt64(0)) == nil)
    #expect(CaptureFrameDisplayTimeParser.parse("123") == nil)
  }

  @Test func frameDeliveryDecisionAcceptsOnlyDocumentedActionableStatuses() {
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: SCFrameStatus.complete.rawValue
      ) == .newFrame
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: NSNumber(value: SCFrameStatus.complete.rawValue)
      ) == .newFrame
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: SCFrameStatus.started.rawValue
      ) == .newFrame
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: SCFrameStatus.idle.rawValue
      ) == .idleRepeat
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: SCFrameStatus.blank.rawValue
      ) == .drop
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: SCFrameStatus.suspended.rawValue
      ) == .drop
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: SCFrameStatus.stopped.rawValue
      ) == .terminalFailure
    )
  }

  @Test func frameDeliveryDecisionFailsClosedForUntrustedStatusValues() {
    #expect(CaptureFrameDeliveryDecisionResolver.resolve(statusValue: nil) == .drop)
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(statusValue: Int.max) == .drop
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(statusValue: "complete") == .drop
    )
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: Double(SCFrameStatus.complete.rawValue)
      ) == .drop
    )
    #expect(CaptureFrameDeliveryDecisionResolver.resolve(statusValue: true) == .drop)
    #expect(
      CaptureFrameDeliveryDecisionResolver.resolve(
        statusValue: NSNumber(value: true)
      ) == .drop
    )
  }

  @Test func unavailableDeliveryBreaksIdleRepeatContinuityUntilANewPayload() {
    var continuity = CaptureOutputContinuity<Int>()

    continuity.acceptNewPayload(1)
    #expect(continuity.repeatablePayload == 1)

    continuity.markContentUnavailable()
    #expect(continuity.repeatablePayload == nil)
    // An idle delivery cannot restore a payload after this gap.
    #expect(continuity.repeatablePayload == nil)

    continuity.acceptNewPayload(2)
    #expect(continuity.repeatablePayload == 2)
  }

  @Test func idleRepeatUsesCurrentMatchingGeometryAndReusesVisualPayload() throws {
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160)
    )
    let repeatedAt = Date(timeIntervalSince1970: 124)
    let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 8,
      capturedAt: repeatedAt,
      currentAttachments: makeSurfaceGeometryAttachments(
        contentRect: CGRect(x: 3, y: 4, width: 300, height: 160),
        screenRect: CGRect(x: 120, y: 80, width: 320, height: 180)
      )
    )

    #expect(repeated.windowID == frame.windowID)
    #expect(repeated.sequenceNumber == 8)
    #expect(repeated.capturedAt == repeatedAt)
    #expect(repeated.displayTime == frame.displayTime)
    #expect(repeated.deliveryKind == .idleRepeat)
    #expect(repeated.captureSurfaceGeometry == frame.captureSurfaceGeometry)
    #expect(
      repeated.captureScreenGeometry?.screenRect
        == CGRect(x: 120, y: 80, width: 320, height: 180)
    )
    #expect(repeated.image === frame.image)
    #expect(repeated.fingerprint == frame.fingerprint)
    #expect(repeated.contentFingerprint == frame.contentFingerprint)
  }

  @Test func idleRepeatRejectsEveryConflictingCurrentSurfaceField() throws {
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 0, y: 0, width: 320, height: 180)
    )
    let validRect = CGRect(x: 0, y: 0, width: 320, height: 180)
    let conflicts: [(String, [SCStreamFrameInfo: Any])] = [
      (
        "contentRect",
        makeSurfaceGeometryAttachments(
          contentRect: CGRect(x: 8, y: 5, width: 304, height: 170)
        )
      ),
      (
        "scaleFactor",
        [
          .status: SCFrameStatus.idle.rawValue,
          .contentRect: validRect,
          .scaleFactor: Double(3),
          .contentScale: Double(0.75),
        ]
      ),
      (
        "contentScale",
        [
          .status: SCFrameStatus.idle.rawValue,
          .contentRect: validRect,
          .scaleFactor: Double(2),
          .contentScale: Double(0.8),
        ]
      ),
    ]

    for (name, attachments) in conflicts {
      let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: frame,
        sequenceNumber: 8,
        capturedAt: Date(timeIntervalSince1970: 124),
        currentAttachments: attachments
      )

      #expect(repeated.image === frame.image, "Unexpected payload for \(name)")
      #expect(repeated.captureSurfaceGeometry == nil, "Accepted conflicting \(name)")
      #expect(repeated.captureScreenGeometry == nil, "Accepted screenRect with \(name)")
    }
  }

  @Test func idleRepeatReusesPriorGeometryWhenAllCurrentSurfaceMetadataIsAbsent() throws {
    let previousScreenRect = CGRect(x: 20, y: 30, width: 320, height: 180)
    let currentScreenRect = CGRect(x: -700, y: 50, width: 320, height: 180)
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160),
      screenRect: previousScreenRect
    )

    let missingSurfaceMetadata = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 8,
      capturedAt: Date(timeIntervalSince1970: 124),
      currentAttachments: [
        .status: SCFrameStatus.idle.rawValue,
        .screenRect: currentScreenRect,
      ]
    )

    #expect(frame.captureSurfaceGeometry != nil)
    #expect(missingSurfaceMetadata.image === frame.image)
    #expect(missingSurfaceMetadata.captureSurfaceGeometry == frame.captureSurfaceGeometry)
    #expect(missingSurfaceMetadata.captureScreenGeometry?.screenRect == currentScreenRect)
  }

  @Test func idleRepeatRejectsEveryProperSubsetOfCurrentSurfaceMetadata() throws {
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160)
    )
    let rect = CGRect(x: 3, y: 4, width: 300, height: 160)
    let properSubsets: [(String, [SCStreamFrameInfo: Any])] = [
      ("contentRect", [.contentRect: rect]),
      ("scaleFactor", [.scaleFactor: Double(2)]),
      ("contentScale", [.contentScale: Double(0.75)]),
      (
        "contentRect+scaleFactor",
        [.contentRect: rect, .scaleFactor: Double(2)]
      ),
      (
        "contentRect+contentScale",
        [.contentRect: rect, .contentScale: Double(0.75)]
      ),
      (
        "scaleFactor+contentScale",
        [.scaleFactor: Double(2), .contentScale: Double(0.75)]
      ),
    ]

    for (name, surfaceAttachments) in properSubsets {
      var attachments = surfaceAttachments
      attachments[.status] = SCFrameStatus.idle.rawValue
      attachments[.screenRect] = CGRect(x: 20, y: 30, width: 320, height: 180)
      let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: frame,
        sequenceNumber: 8,
        capturedAt: Date(timeIntervalSince1970: 124),
        currentAttachments: attachments
      )

      #expect(repeated.image === frame.image, "Unexpected payload for \(name)")
      #expect(repeated.captureSurfaceGeometry == nil, "Accepted partial \(name)")
      #expect(repeated.captureScreenGeometry == nil, "Accepted screenRect with \(name)")
    }
  }

  @Test func idleRepeatRejectsMalformedOrNullCurrentSurfaceMetadata() throws {
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160)
    )
    let rect = CGRect(x: 3, y: 4, width: 300, height: 160)
    let malformedCases: [(String, [SCStreamFrameInfo: Any])] = [
      (
        "contentRect wrong type",
        [
          .contentRect: "invalid",
          .scaleFactor: Double(2),
          .contentScale: Double(0.75),
        ]
      ),
      (
        "scaleFactor Boolean",
        [
          .contentRect: rect,
          .scaleFactor: NSNumber(value: true),
          .contentScale: Double(0.75),
        ]
      ),
      (
        "contentScale nonfinite",
        [
          .contentRect: rect,
          .scaleFactor: Double(2),
          .contentScale: Double.infinity,
        ]
      ),
      (
        "contentRect null",
        [
          .contentRect: NSNull(),
          .scaleFactor: Double(2),
          .contentScale: Double(0.75),
        ]
      ),
      (
        "scaleFactor null",
        [
          .contentRect: rect,
          .scaleFactor: NSNull(),
          .contentScale: Double(0.75),
        ]
      ),
      (
        "contentScale null",
        [
          .contentRect: rect,
          .scaleFactor: Double(2),
          .contentScale: NSNull(),
        ]
      ),
    ]

    for (name, surfaceAttachments) in malformedCases {
      var attachments = surfaceAttachments
      attachments[.status] = SCFrameStatus.idle.rawValue
      attachments[.screenRect] = CGRect(x: 20, y: 30, width: 320, height: 180)
      let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: frame,
        sequenceNumber: 8,
        capturedAt: Date(timeIntervalSince1970: 124),
        currentAttachments: attachments
      )

      #expect(repeated.image === frame.image, "Unexpected payload for \(name)")
      #expect(repeated.captureSurfaceGeometry == nil, "Accepted malformed \(name)")
      #expect(repeated.captureScreenGeometry == nil, "Accepted screenRect with \(name)")
    }
  }

  @Test func idleRepeatRejectsAbsentSurfaceMetadataWithoutVerifiedIdleStatus() throws {
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160),
      screenRect: CGRect(x: 20, y: 30, width: 320, height: 180)
    )
    let invalidStatuses: [(String, Any?)] = [
      ("missing", nil),
      ("complete", SCFrameStatus.complete.rawValue),
      ("started", SCFrameStatus.started.rawValue),
      ("blank", SCFrameStatus.blank.rawValue),
      ("suspended", SCFrameStatus.suspended.rawValue),
      ("stopped", SCFrameStatus.stopped.rawValue),
      ("unknown", Int.max),
      ("malformed", "idle"),
      ("Boolean", NSNumber(value: true)),
    ]

    for (name, status) in invalidStatuses {
      var attachments: [SCStreamFrameInfo: Any] = [:]
      if let status {
        attachments[.status] = status
      }
      let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: frame,
        sequenceNumber: 8,
        capturedAt: Date(timeIntervalSince1970: 124),
        currentAttachments: attachments
      )

      #expect(repeated.captureSurfaceGeometry == nil, "Accepted \(name) status")
      #expect(repeated.captureScreenGeometry == nil, "Accepted screenRect for \(name)")
    }
  }

  @Test func idleRepeatRejectsAbsentSurfaceMetadataWhenEitherPriorOutputDimensionIsInconsistent()
    throws
  {
    let image = try #require(makeSolidImage(width: 320, height: 180))
    for (name, width, height) in [
      ("width", 640, 180),
      ("height", 320, 360),
    ] {
      let mismatchedGeometry = try #require(
        CaptureSurfaceGeometry(
          contentRect: CGRect(x: 3, y: 4, width: 300, height: 160),
          scaleFactor: 2,
          contentScale: 0.75,
          outputPixelWidth: width,
          outputPixelHeight: height
        )
      )
      let frame = CapturedPowerPointFrameFactory.makeNewFrame(
        windowID: 42,
        sequenceNumber: 7,
        capturedAt: Date(timeIntervalSince1970: 123),
        captureSurfaceGeometry: mismatchedGeometry,
        image: image,
        fingerprint: FrameFingerprint(
          sampleColumns: 32,
          sampleRows: 18,
          luminance: Array(repeating: 42, count: 32 * 18)
        )
      )
      let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
        from: frame,
        sequenceNumber: 8,
        capturedAt: Date(timeIntervalSince1970: 124),
        currentAttachments: [.status: SCFrameStatus.idle.rawValue]
      )

      #expect(repeated.captureSurfaceGeometry == nil, "Accepted mismatched \(name)")
    }
  }

  @Test func productionFrameContinuityPoisonsInvalidIdleUntilNewFrameRecovery() throws {
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160)
    )
    let invalidIdleCases: [(String, [SCStreamFrameInfo: Any])] = [
      (
        "partial",
        [
          .status: SCFrameStatus.idle.rawValue,
          .contentRect: CGRect(x: 3, y: 4, width: 300, height: 160),
        ]
      ),
      (
        "malformed",
        [
          .status: SCFrameStatus.idle.rawValue,
          .contentRect: "invalid",
          .scaleFactor: Double(2),
          .contentScale: Double(0.75),
        ]
      ),
      (
        "conflicting",
        makeSurfaceGeometryAttachments(
          contentRect: CGRect(x: 8, y: 5, width: 304, height: 170)
        )
      ),
    ]

    for (name, invalidAttachments) in invalidIdleCases {
      var continuity = CaptureOutputContinuity<CapturedPowerPointFrame>()
      continuity.acceptNewPayload(frame)
      let invalid = try #require(
        continuity.makeAndAcceptRepeatedPayload { lastFrame in
          CapturedPowerPointFrameFactory.makeIdleRepeat(
            from: lastFrame,
            sequenceNumber: 8,
            capturedAt: Date(timeIntervalSince1970: 124),
            currentAttachments: invalidAttachments
          )
        }
      )
      let absentAfterInvalid = try #require(
        continuity.makeAndAcceptRepeatedPayload { lastFrame in
          CapturedPowerPointFrameFactory.makeIdleRepeat(
            from: lastFrame,
            sequenceNumber: 9,
            capturedAt: Date(timeIntervalSince1970: 125),
            currentAttachments: [.status: SCFrameStatus.idle.rawValue]
          )
        }
      )

      #expect(invalid.captureSurfaceGeometry == nil, "Accepted \(name) idle")
      #expect(absentAfterInvalid.captureSurfaceGeometry == nil, "Revived after \(name)")
      #expect(absentAfterInvalid.captureScreenGeometry == nil, "Revived screen after \(name)")

      let recoveredFrame = try makeFactoryTestFrame(
        geometryRect: CGRect(x: 4, y: 5, width: 298, height: 158),
        sequenceNumber: 10
      )
      continuity.acceptNewPayload(recoveredFrame)
      let absentAfterNewFrame = try #require(
        continuity.makeAndAcceptRepeatedPayload { lastFrame in
          CapturedPowerPointFrameFactory.makeIdleRepeat(
            from: lastFrame,
            sequenceNumber: 11,
            capturedAt: Date(timeIntervalSince1970: 127),
            currentAttachments: [.status: SCFrameStatus.idle.rawValue]
          )
        }
      )
      #expect(
        absentAfterNewFrame.captureSurfaceGeometry == recoveredFrame.captureSurfaceGeometry,
        "Did not recover after new frame for \(name)"
      )
      #expect(
        absentAfterNewFrame.captureScreenGeometry
          == recoveredFrame.captureScreenGeometry
      )
    }
  }

  @Test func validIdleGeometryRemainsLatchedAcrossMetadataEmptyIdleRepeats() throws {
    let screenRect = CGRect(x: 20, y: 30, width: 320, height: 180)
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160),
      screenRect: screenRect
    )
    var continuity = CaptureOutputContinuity<CapturedPowerPointFrame>()
    continuity.acceptNewPayload(frame)

    let matching = try #require(
      continuity.makeAndAcceptRepeatedPayload { lastFrame in
        CapturedPowerPointFrameFactory.makeIdleRepeat(
          from: lastFrame,
          sequenceNumber: 8,
          capturedAt: Date(timeIntervalSince1970: 124),
          currentAttachments: makeSurfaceGeometryAttachments(
            contentRect: CGRect(x: 3, y: 4, width: 300, height: 160)
          )
        )
      }
    )
    let absent = try #require(
      continuity.makeAndAcceptRepeatedPayload { lastFrame in
        CapturedPowerPointFrameFactory.makeIdleRepeat(
          from: lastFrame,
          sequenceNumber: 9,
          capturedAt: Date(timeIntervalSince1970: 125),
          currentAttachments: [.status: SCFrameStatus.idle.rawValue]
        )
      }
    )

    #expect(matching.captureSurfaceGeometry == frame.captureSurfaceGeometry)
    #expect(absent.captureSurfaceGeometry == matching.captureSurfaceGeometry)
    #expect(matching.captureScreenGeometry?.screenRect == screenRect)
    #expect(absent.captureScreenGeometry?.screenRect == screenRect)
  }

  @Test func idleRepeatDoesNotAdoptGeometryWhenPriorGeometryWasMissing() throws {
    let frame = try makeFactoryTestFrame(geometryRect: nil)
    let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 8,
      capturedAt: Date(timeIntervalSince1970: 124),
      currentAttachments: makeSurfaceGeometryAttachments(
        contentRect: CGRect(x: 3, y: 4, width: 300, height: 160)
      )
    )

    #expect(frame.captureSurfaceGeometry == nil)
    #expect(repeated.image === frame.image)
    #expect(repeated.captureSurfaceGeometry == nil)
  }

  @Test func idleRepeatUsesCurrentScreenPositionOrReusesPriorOnlyWhenAbsent() throws {
    let previousRect = CGRect(x: 20, y: 30, width: 320, height: 180)
    let currentRect = CGRect(x: -700, y: 50, width: 320, height: 180)
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160),
      screenRect: previousRect
    )

    let moved = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 8,
      capturedAt: Date(timeIntervalSince1970: 124),
      currentAttachments: makeSurfaceGeometryAttachments(
        contentRect: CGRect(x: 3, y: 4, width: 300, height: 160),
        screenRect: currentRect
      )
    )
    let missing = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 9,
      capturedAt: Date(timeIntervalSince1970: 125),
      currentAttachments: makeSurfaceGeometryAttachments(
        contentRect: CGRect(x: 3, y: 4, width: 300, height: 160)
      )
    )
    let invalid = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 10,
      capturedAt: Date(timeIntervalSince1970: 126),
      currentAttachments: makeSurfaceGeometryAttachments(
        contentRect: CGRect(x: 3, y: 4, width: 300, height: 160),
        screenRect: CGRect(x: 40, y: 50, width: 0, height: 180)
      )
    )

    #expect(frame.captureScreenGeometry?.screenRect == previousRect)
    #expect(moved.captureScreenGeometry?.screenRect == currentRect)
    #expect(missing.captureScreenGeometry?.screenRect == previousRect)
    #expect(invalid.captureScreenGeometry == nil)
  }

  @Test func malformedIdleScreenPositionCannotBeRevivedByAnAbsentIdleButValidIdleRecovers()
    throws
  {
    let originalRect = CGRect(x: 20, y: 30, width: 320, height: 180)
    let recoveredRect = CGRect(x: -700, y: 50, width: 320, height: 180)
    let frame = try makeFactoryTestFrame(
      geometryRect: CGRect(x: 3, y: 4, width: 300, height: 160),
      screenRect: originalRect
    )
    var continuity = CaptureOutputContinuity<CapturedPowerPointFrame>()
    continuity.acceptNewPayload(frame)

    let malformed = try #require(
      continuity.makeAndAcceptRepeatedPayload { lastFrame in
        CapturedPowerPointFrameFactory.makeIdleRepeat(
          from: lastFrame,
          sequenceNumber: 8,
          capturedAt: Date(timeIntervalSince1970: 124),
          currentAttachments: [
            .status: SCFrameStatus.idle.rawValue,
            .screenRect: "malformed",
          ]
        )
      }
    )
    let absentAfterMalformed = try #require(
      continuity.makeAndAcceptRepeatedPayload { lastFrame in
        CapturedPowerPointFrameFactory.makeIdleRepeat(
          from: lastFrame,
          sequenceNumber: 9,
          capturedAt: Date(timeIntervalSince1970: 125),
          currentAttachments: [.status: SCFrameStatus.idle.rawValue]
        )
      }
    )
    let validRecovery = try #require(
      continuity.makeAndAcceptRepeatedPayload { lastFrame in
        CapturedPowerPointFrameFactory.makeIdleRepeat(
          from: lastFrame,
          sequenceNumber: 10,
          capturedAt: Date(timeIntervalSince1970: 126),
          currentAttachments: [
            .status: SCFrameStatus.idle.rawValue,
            .screenRect: recoveredRect,
          ]
        )
      }
    )

    #expect(frame.captureScreenGeometry?.screenRect == originalRect)
    #expect(malformed.captureSurfaceGeometry == frame.captureSurfaceGeometry)
    #expect(malformed.captureScreenGeometry == nil)
    #expect(absentAfterMalformed.captureSurfaceGeometry == frame.captureSurfaceGeometry)
    #expect(absentAfterMalformed.captureScreenGeometry == nil)
    #expect(validRecovery.captureSurfaceGeometry == frame.captureSurfaceGeometry)
    #expect(validRecovery.captureScreenGeometry?.screenRect == recoveredRect)
  }

  @Test func parsesCompleteScreenCaptureKitSurfaceGeometry() throws {
    let rect = CGRect(x: 12.5, y: 6.25, width: 960, height: 540)
    let bridgedAttachments: [SCStreamFrameInfo: Any] = [
      .contentRect: NSValue(rect: rect),
      .scaleFactor: NSNumber(value: 2.0),
      .contentScale: NSNumber(value: 0.8),
    ]

    let bridged = try #require(
      CaptureSurfaceGeometryParser.parse(
        bridgedAttachments,
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      )
    )

    #expect(bridged.contentRect == rect)
    #expect(bridged.scaleFactor == 2)
    #expect(bridged.contentScale == 0.8)
    #expect(bridged.outputPixelWidth == 1_920)
    #expect(bridged.outputPixelHeight == 1_080)

    let directAttachments: [SCStreamFrameInfo: Any] = [
      .contentRect: rect,
      .scaleFactor: Double(2),
      .contentScale: Double(0.8),
    ]
    #expect(
      CaptureSurfaceGeometryParser.parse(
        directAttachments,
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == bridged
    )
  }

  @Test func parsesDictionaryRepresentedScreenCaptureKitContentRect() throws {
    let rect = CGRect(x: 12.5, y: 6.25, width: 960, height: 540)
    let attachments: [SCStreamFrameInfo: Any] = [
      .contentRect: rect.dictionaryRepresentation,
      .scaleFactor: NSNumber(value: 2.0),
      .contentScale: NSNumber(value: 0.8),
    ]

    let geometry = try #require(
      CaptureSurfaceGeometryParser.parse(
        attachments,
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      )
    )

    #expect(geometry.contentRect == rect)
  }

  @Test func parsesSupportedScreenCaptureKitScreenRectRepresentations() throws {
    let rect = CGRect(x: -1_200.5, y: -60.25, width: 960, height: 540)
    let representations: [Any] = [
      rect,
      NSValue(rect: rect),
      rect.dictionaryRepresentation,
    ]

    for representation in representations {
      let geometry = try #require(
        CaptureScreenGeometryParser.parse([.screenRect: representation])
      )
      #expect(geometry.screenRect == rect)
      #expect(geometry.screenOriginX == -1_200.5)
      #expect(geometry.screenOriginY == -60.25)
      #expect(geometry.screenWidth == 960)
      #expect(geometry.screenHeight == 540)
    }
  }

  @Test func rejectsMissingOrInvalidScreenCaptureKitScreenRect() {
    let invalidRects = [
      CGRect(x: 0, y: 0, width: 0, height: 540),
      CGRect(x: 0, y: 0, width: 960, height: 0),
      CGRect(x: 0, y: 0, width: -1, height: 540),
      CGRect(x: 0, y: 0, width: 960, height: -1),
      CGRect(x: CGFloat.infinity, y: 0, width: 960, height: 540),
      CGRect(x: 0, y: -CGFloat.infinity, width: 960, height: 540),
      CGRect(x: 0, y: 0, width: CGFloat.nan, height: 540),
      CGRect(x: 0, y: 0, width: 960, height: CGFloat.infinity),
    ]

    #expect(CaptureScreenGeometryParser.parse(nil) == nil)
    #expect(CaptureScreenGeometryParser.parse([:]) == nil)
    #expect(CaptureScreenGeometryParser.parse([.screenRect: "invalid"]) == nil)
    #expect(
      CaptureScreenGeometryParser.parse([.screenRect: NSNumber(value: 42)]) == nil
    )
    #expect(
      CaptureScreenGeometryParser.parse(
        [.screenRect: NSValue(point: CGPoint(x: 20, y: 30))]
      ) == nil
    )
    for rect in invalidRects {
      #expect(CaptureScreenGeometryParser.parse([.screenRect: rect]) == nil)
      #expect(CaptureScreenGeometry(screenRect: rect) == nil)
    }
  }

  @Test func rejectsMissingOrInvalidScreenCaptureKitSurfaceGeometry() {
    let rect = CGRect(x: 0, y: 0, width: 960, height: 540)
    let valid: [SCStreamFrameInfo: Any] = [
      .contentRect: rect,
      .scaleFactor: NSNumber(value: 2.0),
      .contentScale: NSNumber(value: 1.0),
    ]

    #expect(
      CaptureSurfaceGeometryParser.parse(
        nil,
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
    #expect(
      CaptureSurfaceGeometryParser.parse(
        [.contentRect: rect, .scaleFactor: 2.0],
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
    #expect(
      CaptureSurfaceGeometryParser.parse(
        [
          .contentRect: CGRect(x: -.infinity, y: 0, width: 960, height: 540),
          .scaleFactor: 2.0,
          .contentScale: 1.0,
        ],
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
    #expect(
      CaptureSurfaceGeometryParser.parse(
        [
          .contentRect: CGRect(x: 0, y: 0, width: -960, height: 540),
          .scaleFactor: 2.0,
          .contentScale: 1.0,
        ],
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
    #expect(
      CaptureSurfaceGeometryParser.parse(
        [
          .contentRect: rect,
          .scaleFactor: NSNumber(value: true),
          .contentScale: 1.0,
        ],
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
    #expect(
      CaptureSurfaceGeometryParser.parse(
        [
          .contentRect: rect,
          .scaleFactor: 2.0,
          .contentScale: 0.0,
        ],
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
    #expect(
      CaptureSurfaceGeometryParser.parse(
        valid,
        outputPixelWidth: 0,
        outputPixelHeight: 1_080
      ) == nil
    )
  }

  @Test func acceptsDocumentedScreenCaptureKitScaleFactorBounds() {
    let rect = CGRect(x: 0, y: 0, width: 960, height: 540)

    for scaleFactor in [Double(1), Double(4)] {
      #expect(
        CaptureSurfaceGeometry(
          contentRect: rect,
          scaleFactor: scaleFactor,
          contentScale: 1,
          outputPixelWidth: 1_920,
          outputPixelHeight: 1_080
        ) != nil
      )
      #expect(
        CaptureSurfaceGeometryParser.parse(
          [
            .contentRect: rect,
            .scaleFactor: NSNumber(value: scaleFactor),
            .contentScale: NSNumber(value: 1),
          ],
          outputPixelWidth: 1_920,
          outputPixelHeight: 1_080
        ) != nil
      )
    }
  }

  @Test func rejectsUndocumentedScreenCaptureKitScaleFactors() {
    let rect = CGRect(x: 0, y: 0, width: 960, height: 540)

    for scaleFactor in [Double(0), Double(0.5), Double(4.001), .infinity, .nan] {
      #expect(
        CaptureSurfaceGeometry(
          contentRect: rect,
          scaleFactor: scaleFactor,
          contentScale: 1,
          outputPixelWidth: 1_920,
          outputPixelHeight: 1_080
        ) == nil
      )
      #expect(
        CaptureSurfaceGeometryParser.parse(
          [
            .contentRect: rect,
            .scaleFactor: NSNumber(value: scaleFactor),
            .contentScale: NSNumber(value: 1),
          ],
          outputPixelWidth: 1_920,
          outputPixelHeight: 1_080
        ) == nil
      )
    }

    #expect(
      CaptureSurfaceGeometryParser.parse(
        [
          .contentRect: rect,
          .scaleFactor: NSNumber(value: true),
          .contentScale: NSNumber(value: 1),
        ],
        outputPixelWidth: 1_920,
        outputPixelHeight: 1_080
      ) == nil
    )
  }

  @Test func compositesTransparentAndSemitransparentPixelsOverWhite() throws {
    let image = try #require(
      makeImage(
        width: 2,
        height: 1,
        premultipliedRGBABytes: [
          0, 0, 0, 0,
          128, 0, 0, 128,
        ]
      )
    )

    let first = try #require(
      CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 640)
    )
    let second = try #require(
      CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 640)
    )

    #expect(first.rgbBytes == [255, 255, 255, 255, 127, 127])
    #expect(second == first)
  }

  @Test func convertsCaptureStyleBGRAWithTopLeftOrientationAndAlpha() throws {
    let image = try #require(
      makeBGRAImage(
        width: 2,
        height: 2,
        premultipliedBGRABytes: [
          0, 0, 255, 255, 0, 255, 0, 255,
          255, 0, 0, 255, 0, 0, 128, 128,
        ]
      )
    )

    let raster = try #require(
      CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 640)
    )

    #expect(raster.width == 2)
    #expect(raster.height == 2)
    #expect(
      raster.rgbBytes == [
        255, 0, 0, 0, 255, 0,
        0, 0, 255, 255, 127, 127,
      ]
    )
  }

  @Test func rejectsInvalidRasterLimitsAndFingerprintDimensions() throws {
    let image = try #require(makeSolidImage(width: 2, height: 2))

    #expect(CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 0) == nil)
    #expect(CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: -1) == nil)
    #expect(
      CGImageRasterizer.makeContentFingerprint(
        from: image,
        sampleColumns: 0,
        sampleRows: 90
      ) == nil
    )
    #expect(
      CGImageRasterizer.makeContentFingerprint(
        from: image,
        sampleColumns: 160,
        sampleRows: -1
      ) == nil
    )
  }

  @Test func rejectsNonOverflowingOversizedFingerprintBeforeAllocation() throws {
    let image = try #require(makeSolidImage(width: 2, height: 2))
    let oversizedColumnCount = CGImageRasterizer.maximumRenderedPixelCount + 1

    #expect(
      CGImageRasterizer.makeContentFingerprint(
        from: image,
        sampleColumns: oversizedColumnCount,
        sampleRows: 1
      ) == nil
    )
    #expect(
      CGImageRasterizer.makeContentFingerprint(
        from: image,
        sampleColumns: Int.max / 8,
        sampleRows: 1
      ) == nil
    )
  }

  @Test func rejectsOversizedRasterOutputButAllowsBoundedDownscaling() throws {
    let oversizedEdge = 1_025
    let image = try #require(
      makeContextImage(width: oversizedEdge, height: oversizedEdge)
    )

    #expect(
      CGImageRasterizer.makeRGBRaster(
        from: image,
        maximumLongEdge: oversizedEdge
      ) == nil
    )
    let bounded = try #require(
      CGImageRasterizer.makeRGBRaster(from: image, maximumLongEdge: 640)
    )
    #expect(bounded.width == 640)
    #expect(bounded.height == 640)
  }

  private func makeFactoryTestFrame(
    geometryRect: CGRect?,
    screenRect: CGRect? = nil,
    sequenceNumber: UInt64 = 7
  ) throws -> CapturedPowerPointFrame {
    let image = try #require(makeSolidImage(width: 320, height: 180))
    let geometry: CaptureSurfaceGeometry?
    if let geometryRect {
      geometry = try #require(
        CaptureSurfaceGeometry(
          contentRect: geometryRect,
          scaleFactor: 2,
          contentScale: 0.75,
          outputPixelWidth: 320,
          outputPixelHeight: 180
        )
      )
    } else {
      geometry = nil
    }
    let screenGeometry: CaptureScreenGeometry?
    if let screenRect {
      screenGeometry = try #require(CaptureScreenGeometry(screenRect: screenRect))
    } else {
      screenGeometry = nil
    }
    return CapturedPowerPointFrameFactory.makeNewFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(timeIntervalSince1970: 123),
      displayTime: 12_345,
      captureSurfaceGeometry: geometry,
      captureScreenGeometry: screenGeometry,
      image: image,
      fingerprint: FrameFingerprint(
        sampleColumns: 32,
        sampleRows: 18,
        luminance: Array(repeating: 42, count: 32 * 18)
      )
    )
  }

  private func makeSurfaceGeometryAttachments(
    contentRect: CGRect,
    screenRect: CGRect? = nil
  ) -> [SCStreamFrameInfo: Any] {
    var attachments: [SCStreamFrameInfo: Any] = [
      .status: SCFrameStatus.idle.rawValue,
      .contentRect: contentRect,
      .scaleFactor: Double(2),
      .contentScale: Double(0.75),
    ]
    if let screenRect {
      attachments[.screenRect] = screenRect
    }
    return attachments
  }

  private func makeSolidImage(width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
    guard !overflow else { return nil }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixelCount * 4)
    for _ in 0..<pixelCount {
      bytes.append(contentsOf: [12, 34, 56, 255])
    }
    return makeImage(width: width, height: height, premultipliedRGBABytes: bytes)
  }

  private func makeImage(
    width: Int,
    height: Int,
    premultipliedRGBABytes: [UInt8]
  ) -> CGImage? {
    guard
      width > 0,
      height > 0,
      premultipliedRGBABytes.count == width * height * 4,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(premultipliedRGBABytes) as CFData)
    else {
      return nil
    }

    let bitmapInfo = CGBitmapInfo(
      rawValue:
        CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo,
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private func makeBGRAImage(
    width: Int,
    height: Int,
    premultipliedBGRABytes: [UInt8]
  ) -> CGImage? {
    guard
      width > 0,
      height > 0,
      premultipliedBGRABytes.count == width * height * 4,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(premultipliedBGRABytes) as CFData)
    else {
      return nil
    }

    let bitmapInfo = CGBitmapInfo(
      rawValue:
        CGBitmapInfo.byteOrder32Little.rawValue
        | CGImageAlphaInfo.premultipliedFirst.rawValue
    )
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo,
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private func makeContextImage(width: Int, height: Int) -> CGImage? {
    guard
      width > 0,
      height > 0,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo:
          CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }

    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}
