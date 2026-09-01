import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct SlideCanvasCropperTests {
  @Test func cropsUsingTopLeftNormalizedCoordinates() throws {
    let image = try #require(
      makeImage(
        width: 2,
        height: 2,
        rgbaBytes: [
          255, 0, 0, 255, 0, 255, 0, 255,
          0, 0, 255, 255, 255, 255, 0, 255,
        ]
      )
    )
    let frame = makeFrame(image: image, windowID: 42)
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 0.5)
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 7),
        windowID: 42,
        captureSurfaceGeometry: makeGeometry(width: 2, height: 2),
        region: region
      )
    )

    let prepared = try #require(
      SlideCanvasFramePreparer.makeFrame(
        from: frame,
        captureOperationID: CaptureOperationID(rawValue: 7),
        selection: selection
      )
    )
    let raster = try #require(
      CGImageRasterizer.makeRGBRaster(from: prepared.image)
    )

    #expect(raster.width == 2)
    #expect(raster.height == 1)
    #expect(raster.rgbBytes == [255, 0, 0, 0, 255, 0])
  }

  @Test func excludesPixelsOutsideTheConfirmedCanvasFromBothFingerprints() throws {
    let firstImage = try #require(
      makeSplitImage(
        width: 4,
        height: 2,
        outsideRGB: (255, 0, 0),
        insideRGB: (0, 0, 255)
      )
    )
    let secondImage = try #require(
      makeSplitImage(
        width: 4,
        height: 2,
        outsideRGB: (0, 255, 0),
        insideRGB: (0, 0, 255)
      )
    )
    let region = try #require(
      SlideCanvasRegion(x: 0.5, y: 0, width: 0.5, height: 1)
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 9),
        windowID: 21,
        captureSurfaceGeometry: makeGeometry(width: 4, height: 2),
        region: region
      )
    )

    let first = try #require(
      SlideCanvasFramePreparer.makeFrame(
        from: makeFrame(image: firstImage, windowID: 21),
        captureOperationID: CaptureOperationID(rawValue: 9),
        selection: selection
      )
    )
    let second = try #require(
      SlideCanvasFramePreparer.makeFrame(
        from: makeFrame(image: secondImage, windowID: 21),
        captureOperationID: CaptureOperationID(rawValue: 9),
        selection: selection
      )
    )

    #expect(first.image.width == 2)
    #expect(first.image.height == 2)
    #expect(first.fingerprint == second.fingerprint)
    #expect(first.contentFingerprint == second.contentFingerprint)
    #expect(first.fingerprint.luminance.allSatisfy { $0 == 18 })
  }

  @Test func rejectsOperationWindowAndSourceDimensionMismatches() throws {
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (1, 2, 3)))
    let frame = makeFrame(image: image, windowID: 33)
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 0.5, height: 1)
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 10),
        windowID: 33,
        captureSurfaceGeometry: makeGeometry(width: 4, height: 2),
        region: region
      )
    )

    #expect(!selection.matches(frame, captureOperationID: CaptureOperationID(rawValue: 9)))
    #expect(
      SlideCanvasFramePreparer.makeFrame(
        from: frame,
        captureOperationID: CaptureOperationID(rawValue: 9),
        selection: selection
      ) == nil
    )
    #expect(
      SlideCanvasFramePreparer.invalidationReason(
        for: frame,
        captureOperationID: CaptureOperationID(rawValue: 9),
        selection: selection
      ) == .selectionContextMismatch
    )

    let wrongWindow = makeFrame(image: image, windowID: 34)
    #expect(!selection.matches(wrongWindow, captureOperationID: CaptureOperationID(rawValue: 10)))
    #expect(
      SlideCanvasFramePreparer.makeFrame(
        from: wrongWindow,
        captureOperationID: CaptureOperationID(rawValue: 10),
        selection: selection
      ) == nil
    )

    let wrongDimensionsImage = try #require(
      makeSolidImage(width: 5, height: 2, rgb: (1, 2, 3))
    )
    let wrongDimensions = makeFrame(image: wrongDimensionsImage, windowID: 33)
    #expect(
      !selection.matches(
        wrongDimensions,
        captureOperationID: CaptureOperationID(rawValue: 10)
      )
    )
    #expect(
      SlideCanvasFramePreparer.makeFrame(
        from: wrongDimensions,
        captureOperationID: CaptureOperationID(rawValue: 10),
        selection: selection
      ) == nil
    )
  }

  @Test func rejectsInvalidSelectionProvenance() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )
    let operationID = CaptureOperationID(rawValue: 1)

    #expect(
      ConfirmedSlideCanvasSelection(
        captureOperationID: operationID,
        windowID: 0,
        captureSurfaceGeometry: makeGeometry(width: 10, height: 10),
        region: region
      ) == nil
    )
    #expect(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: 1,
        sourcePixelWidth: 0,
        sourcePixelHeight: 10
      ) == nil
    )
    #expect(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: 1,
        sourcePixelWidth: 10,
        sourcePixelHeight: -1
      ) == nil
    )
  }

  @Test func reusesExactFullFrameImageAndFingerprints() throws {
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (12, 34, 56)))
    let rawFingerprint = FrameFingerprint(
      sampleColumns: 1,
      sampleRows: 1,
      luminance: [123]
    )
    let rawContentFingerprint = ContentFingerprint(
      sampleColumns: 1,
      sampleRows: 1,
      cells: [RGBContentCell(red: 7, green: 8, blue: 9)]
    )
    let capturedAt = Date(timeIntervalSince1970: 123)
    let geometry = makeGeometry(width: 4, height: 2)
    let frame = CapturedPowerPointFrame(
      windowID: 44,
      sequenceNumber: 19,
      capturedAt: capturedAt,
      displayTime: 456,
      deliveryKind: .idleRepeat,
      captureSurfaceGeometry: geometry,
      image: image,
      fingerprint: rawFingerprint,
      contentFingerprint: rawContentFingerprint
    )
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 11),
        windowID: 44,
        captureSurfaceGeometry: geometry,
        region: region
      )
    )

    let prepared = try #require(
      SlideCanvasFramePreparer.makeFrame(
        from: frame,
        captureOperationID: CaptureOperationID(rawValue: 11),
        selection: selection
      )
    )

    #expect(prepared.image === image)
    #expect(prepared.fingerprint == rawFingerprint)
    #expect(prepared.contentFingerprint == rawContentFingerprint)
    #expect(prepared.windowID == 44)
    #expect(prepared.sequenceNumber == 19)
    #expect(prepared.capturedAt == capturedAt)
    #expect(prepared.displayTime == 456)
    #expect(prepared.deliveryKind == .idleRepeat)
  }

  @Test func rejectsInvalidFullFrameFingerprints() throws {
    let image = try #require(makeSolidImage(width: 2, height: 2, rgb: (1, 2, 3)))
    let geometry = makeGeometry(width: 2, height: 2)
    let frame = CapturedPowerPointFrame(
      windowID: 12,
      sequenceNumber: 1,
      capturedAt: .distantPast,
      deliveryKind: .new,
      captureSurfaceGeometry: geometry,
      image: image,
      fingerprint: FrameFingerprint(sampleColumns: 2, sampleRows: 2, luminance: [1]),
      contentFingerprint: nil
    )
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 5),
        windowID: 12,
        captureSurfaceGeometry: geometry,
        region: region
      )
    )

    #expect(
      SlideCanvasFramePreparer.makeFrame(
        from: frame,
        captureOperationID: CaptureOperationID(rawValue: 5),
        selection: selection
      ) == nil
    )
    #expect(
      SlideCanvasFramePreparer.invalidationReason(
        for: frame,
        captureOperationID: CaptureOperationID(rawValue: 5),
        selection: selection
      ) == .confirmedFrameRejected
    )
  }

  @Test func distinguishesNewAndIdleSurfaceGeometryRejections() throws {
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (1, 2, 3)))
    let operationID = CaptureOperationID(rawValue: 13)
    let region = try #require(SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1))
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: operationID,
        windowID: 33,
        captureSurfaceGeometry: makeGeometry(width: 4, height: 2),
        region: region
      )
    )
    let newFrame = makeFrame(
      image: image,
      windowID: 33,
      captureSurfaceGeometry: nil,
      deliveryKind: .new
    )
    let idleRepeat = makeFrame(
      image: image,
      windowID: 33,
      captureSurfaceGeometry: nil,
      deliveryKind: .idleRepeat
    )

    #expect(
      SlideCanvasFramePreparer.invalidationReason(
        for: newFrame,
        captureOperationID: operationID,
        selection: selection
      ) == .newFrameSurfaceGeometryUnavailableOrMismatched
    )
    #expect(
      SlideCanvasFramePreparer.invalidationReason(
        for: idleRepeat,
        captureOperationID: operationID,
        selection: selection
      ) == .idleRepeatSurfaceGeometryUnavailableOrMismatched
    )
  }

  @Test func rejectsGeometryChangeWhenOutputPixelDimensionsStayTheSame() throws {
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (1, 2, 3)))
    let originalGeometry = makeGeometry(width: 4, height: 2)
    let changedGeometry = makeGeometry(
      contentRect: CGRect(x: 1, y: 0, width: 3, height: 2),
      width: 4,
      height: 2
    )
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 0.5, height: 1)
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 12),
        windowID: 33,
        captureSurfaceGeometry: originalGeometry,
        region: region
      )
    )
    let changedFrame = makeFrame(
      image: image,
      windowID: 33,
      captureSurfaceGeometry: changedGeometry
    )

    #expect(
      !selection.matches(
        changedFrame,
        captureOperationID: CaptureOperationID(rawValue: 12)
      )
    )
    #expect(
      SlideCanvasFramePreparer.makeFrame(
        from: changedFrame,
        captureOperationID: CaptureOperationID(rawValue: 12),
        selection: selection
      ) == nil
    )
  }

  @Test func coarseFingerprintUsesTheCaptureLuminanceFormulaAndValidatesDimensions() throws {
    let image = try #require(
      makeImage(
        width: 2,
        height: 1,
        rgbaBytes: [255, 0, 0, 255, 0, 255, 0, 255]
      )
    )
    let fingerprint = try #require(
      CGImageRasterizer.makeFrameFingerprint(
        from: image,
        sampleColumns: 2,
        sampleRows: 1
      )
    )

    #expect(fingerprint.luminance == [53, 182])
    #expect(
      CGImageRasterizer.makeFrameFingerprint(
        from: image,
        sampleColumns: 0,
        sampleRows: 1
      ) == nil
    )
    #expect(
      CGImageRasterizer.makeFrameFingerprint(
        from: image,
        sampleColumns: CGImageRasterizer.maximumRenderedPixelCount + 1,
        sampleRows: 1
      ) == nil
    )
  }

  @Test func preparesBoundedFreshSampleWithTopLeftCropAndExplicitOrigin() throws {
    let requestID = FreshSampleRequestID()
    let operationID = CaptureOperationID(rawValue: 21)
    let image = try #require(
      makeImage(
        width: 2,
        height: 2,
        rgbaBytes: [
          255, 0, 0, 255, 0, 255, 0, 255,
          0, 0, 255, 255, 255, 255, 0, 255,
        ]
      )
    )
    let geometry = makeGeometry(width: 2, height: 2)
    let sample = try #require(
      makeFreshSample(
        requestID: requestID,
        operationID: operationID,
        image: image,
        geometry: geometry,
        windowID: 51
      )
    )
    let region = try #require(SlideCanvasRegion(x: 0, y: 0, width: 1, height: 0.5))
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: operationID,
        windowID: 51,
        captureSurfaceGeometry: geometry,
        region: region
      )
    )

    guard
      case .prepared(let prepared) = FreshSlideCanvasSamplePreparer.evaluate(
        sample,
        expectedIdentity: sample.identity,
        anchorSequenceNumber: 77,
        selection: selection
      )
    else {
      Issue.record("Expected a prepared bounded fresh sample.")
      return
    }
    let raster = try #require(CGImageRasterizer.makeRGBRaster(from: prepared.image))

    #expect(raster.width == 2)
    #expect(raster.height == 1)
    #expect(raster.rgbBytes == [255, 0, 0, 0, 255, 0])
    #expect(prepared.windowID == 51)
    #expect(prepared.sequenceNumber == 77)
    #expect(prepared.capturedAt == sample.capturedAt)
    #expect(prepared.displayTime == nil)
    #expect(prepared.deliveryKind == nil)
    #expect(
      prepared.origin
        == .boundedFreshSample(requestID: requestID, anchorSequenceNumber: 77)
    )
    #expect(prepared.fingerprint.isValid)
    #expect(prepared.contentFingerprint?.isValid == true)
  }

  @Test func preservesContinuousStreamOriginAndCompatibilityAccessors() throws {
    let image = try #require(makeSolidImage(width: 2, height: 2, rgb: (1, 2, 3)))
    let geometry = makeGeometry(width: 2, height: 2)
    let frame = CapturedPowerPointFrame(
      windowID: 61,
      sequenceNumber: 4,
      capturedAt: .distantPast,
      displayTime: 99,
      deliveryKind: .idleRepeat,
      captureSurfaceGeometry: geometry,
      image: image,
      fingerprint: FrameFingerprint(sampleColumns: 1, sampleRows: 1, luminance: [1]),
      contentFingerprint: nil
    )
    let region = try #require(SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1))
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: CaptureOperationID(rawValue: 22),
        windowID: 61,
        captureSurfaceGeometry: geometry,
        region: region
      )
    )

    let prepared = try #require(
      SlideCanvasFramePreparer.makeFrame(
        from: frame,
        captureOperationID: CaptureOperationID(rawValue: 22),
        selection: selection
      )
    )

    #expect(
      prepared.origin
        == .continuousStream(displayTime: 99, deliveryKind: .idleRepeat)
    )
    #expect(prepared.displayTime == 99)
    #expect(prepared.deliveryKind == .idleRepeat)
  }

  @Test func freshSampleRequestIDsAreOpaqueAndUnique() {
    let first = FreshSampleRequestID()
    let second = FreshSampleRequestID()

    #expect(first == first)
    #expect(first != second)
  }

  @Test func rejectsFreshOperationAndExactWindowMismatchesWithoutInvalidatingSelection() throws {
    let selectionOperationID = CaptureOperationID(rawValue: 30)
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (1, 2, 3)))
    let geometry = makeGeometry(width: 4, height: 2)
    let region = try #require(SlideCanvasRegion(x: 0, y: 0, width: 0.5, height: 1))
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: selectionOperationID,
        windowID: 71,
        captureSurfaceGeometry: geometry,
        region: region
      )
    )
    let wrongOperation = try #require(
      makeFreshSample(
        operationID: CaptureOperationID(rawValue: 31),
        image: image,
        geometry: geometry,
        windowID: 71
      )
    )
    let wrongWindow = try #require(
      makeFreshSample(
        operationID: selectionOperationID,
        image: image,
        geometry: geometry,
        windowID: 72
      )
    )
    let wrongProcess = try #require(
      makeFreshSample(
        operationID: selectionOperationID,
        image: image,
        geometry: geometry,
        windowID: 71,
        processID: 9_999
      )
    )
    let matching = try #require(
      makeFreshSample(
        operationID: selectionOperationID,
        image: image,
        geometry: geometry,
        windowID: 71
      )
    )

    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          matching,
          expectedIdentity: matching.identity,
          anchorSequenceNumber: 0,
          selection: selection
        )
      ) == .invalidAnchorSequence
    )

    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          wrongOperation,
          expectedIdentity: wrongOperation.identity,
          anchorSequenceNumber: 1,
          selection: selection
        )
      ) == .captureOperationMismatch
    )
    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          wrongWindow,
          expectedIdentity: matching.identity,
          anchorSequenceNumber: 1,
          selection: selection
        )
      ) == .windowIdentityMismatch
    )
    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          wrongProcess,
          expectedIdentity: matching.identity,
          anchorSequenceNumber: 1,
          selection: selection
        )
      ) == .windowIdentityMismatch
    )
    guard
      case .prepared = FreshSlideCanvasSamplePreparer.evaluate(
        matching,
        expectedIdentity: matching.identity,
        anchorSequenceNumber: 1,
        selection: selection
      )
    else {
      Issue.record("A rejected fresh sample must not invalidate the immutable selection.")
      return
    }
  }

  @Test func rejectsFreshProductionSurfaceTupleAndOutputDimensionMismatches() throws {
    let operationID = CaptureOperationID(rawValue: 40)
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (1, 2, 3)))
    let selectedGeometry = makeGeometry(width: 4, height: 2)
    let region = try #require(SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1))
    let selection = try #require(
      ConfirmedSlideCanvasSelection(
        captureOperationID: operationID,
        windowID: 81,
        captureSurfaceGeometry: selectedGeometry,
        region: region
      )
    )
    let changedTuple = makeGeometry(
      contentRect: CGRect(x: 1, y: 0, width: 3, height: 2),
      width: 4,
      height: 2
    )
    let tupleMismatch = try #require(
      makeFreshSample(
        operationID: operationID,
        image: image,
        geometry: changedTuple,
        windowID: 81
      )
    )
    let outputMismatch = try #require(
      makeFreshSample(
        operationID: operationID,
        image: image,
        geometry: makeGeometry(width: 5, height: 2),
        windowID: 81
      )
    )

    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          tupleMismatch,
          expectedIdentity: tupleMismatch.identity,
          anchorSequenceNumber: 1,
          selection: selection
        )
      ) == .surfaceGeometryMismatch
    )
    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          outputMismatch,
          expectedIdentity: outputMismatch.identity,
          anchorSequenceNumber: 1,
          selection: selection
        )
      ) == .outputDimensionsMismatch
    )
  }

  @Test func testOnlyFreshFullFrameRequiresOriginalSourceDimensions() throws {
    let operationID = CaptureOperationID(rawValue: 50)
    let image = try #require(makeSolidImage(width: 4, height: 2, rgb: (1, 2, 3)))
    let sample = try #require(
      makeFreshSample(
        operationID: operationID,
        image: image,
        geometry: makeGeometry(width: 4, height: 2),
        windowID: 91
      )
    )
    let mismatchedSelection = try #require(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: 91,
        sourcePixelWidth: 5,
        sourcePixelHeight: 2
      )
    )
    let matchingSelection = try #require(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: 91,
        sourcePixelWidth: 4,
        sourcePixelHeight: 2
      )
    )

    #expect(
      rejection(
        FreshSlideCanvasSamplePreparer.evaluate(
          sample,
          expectedIdentity: sample.identity,
          anchorSequenceNumber: 1,
          selection: mismatchedSelection
        )
      ) == .testOnlySourceDimensionsMismatch
    )
    guard
      case .prepared(let prepared) = FreshSlideCanvasSamplePreparer.evaluate(
        sample,
        expectedIdentity: sample.identity,
        anchorSequenceNumber: 1,
        selection: matchingSelection
      )
    else {
      Issue.record("Expected exact test-only source dimensions to pass.")
      return
    }
    #expect(prepared.image === image)
    #expect(prepared.contentFingerprint?.isValid == true)
  }

  @Test func fullFrameFreshSampleMatchesTheSameHighContrastImageFingerprint() throws {
    let operationID = CaptureOperationID(rawValue: 60)
    let image = try #require(
      makeImage(
        width: 2,
        height: 1,
        rgbaBytes: [255, 255, 255, 255, 0, 0, 0, 255]
      )
    )
    let anchorFingerprint = try #require(
      CGImageRasterizer.makeFrameFingerprint(from: image)
    )
    let anchorContentFingerprint = try #require(
      CGImageRasterizer.makeContentFingerprint(from: image)
    )
    let sample = try #require(
      makeFreshSample(
        operationID: operationID,
        image: image,
        geometry: makeGeometry(width: 2, height: 1),
        windowID: 101
      )
    )
    let selection = try #require(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: 101,
        sourcePixelWidth: 2,
        sourcePixelHeight: 1
      )
    )

    guard
      case .prepared(let prepared) = FreshSlideCanvasSamplePreparer.evaluate(
        sample,
        expectedIdentity: sample.identity,
        anchorSequenceNumber: 9,
        selection: selection
      )
    else {
      Issue.record("Expected a valid full-frame fresh sample.")
      return
    }

    #expect(prepared.fingerprint.normalizedDifference(from: anchorFingerprint) == 0)
    #expect(prepared.contentFingerprint == anchorContentFingerprint)
  }

  private func makeFrame(image: CGImage, windowID: CGWindowID) -> CapturedPowerPointFrame {
    makeFrame(
      image: image,
      windowID: windowID,
      captureSurfaceGeometry: makeGeometry(width: image.width, height: image.height)
    )
  }

  private func makeFrame(
    image: CGImage,
    windowID: CGWindowID,
    captureSurfaceGeometry: CaptureSurfaceGeometry?,
    deliveryKind: CapturedFrameDeliveryKind = .new
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: windowID,
      sequenceNumber: 1,
      capturedAt: Date(timeIntervalSince1970: 1),
      displayTime: 2,
      deliveryKind: deliveryKind,
      captureSurfaceGeometry: captureSurfaceGeometry,
      image: image,
      fingerprint: FrameFingerprint(sampleColumns: 1, sampleRows: 1, luminance: [0]),
      contentFingerprint: nil
    )
  }

  private func makeGeometry(
    contentRect: CGRect? = nil,
    width: Int,
    height: Int
  ) -> CaptureSurfaceGeometry {
    guard
      let geometry = CaptureSurfaceGeometry(
        contentRect: contentRect ?? CGRect(x: 0, y: 0, width: width, height: height),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: width,
        outputPixelHeight: height
      )
    else {
      preconditionFailure("Synthetic geometry must be valid.")
    }
    return geometry
  }

  private func makeFreshSample(
    requestID: FreshSampleRequestID = FreshSampleRequestID(),
    operationID: CaptureOperationID,
    image: CGImage,
    geometry: CaptureSurfaceGeometry,
    windowID: CGWindowID,
    processID: pid_t = 1_234
  ) -> FreshPowerPointWindowSample? {
    guard
      let identity = PowerPointWindowIdentity(
        windowID: windowID,
        ownerProcessID: processID,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    else {
      return nil
    }
    return FreshPowerPointWindowSample(
      requestID: requestID,
      captureOperationID: operationID,
      identity: identity,
      capturedAt: Date(timeIntervalSince1970: 2),
      captureSurfaceGeometry: geometry,
      image: image
    )
  }

  private func rejection(
    _ outcome: FreshSlideCanvasSamplePreparer.Outcome
  ) -> FreshSlideCanvasSampleRejection? {
    guard case .rejected(let reason) = outcome else { return nil }
    return reason
  }

  private func makeSplitImage(
    width: Int,
    height: Int,
    outsideRGB: (UInt8, UInt8, UInt8),
    insideRGB: (UInt8, UInt8, UInt8)
  ) -> CGImage? {
    guard width.isMultiple(of: 2) else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for _ in 0..<height {
      for column in 0..<width {
        let rgb = column < width / 2 ? outsideRGB : insideRGB
        bytes.append(contentsOf: [rgb.0, rgb.1, rgb.2, 255])
      }
    }
    return makeImage(width: width, height: height, rgbaBytes: bytes)
  }

  private func makeSolidImage(
    width: Int,
    height: Int,
    rgb: (UInt8, UInt8, UInt8)
  ) -> CGImage? {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for _ in 0..<(width * height) {
      bytes.append(contentsOf: [rgb.0, rgb.1, rgb.2, 255])
    }
    return makeImage(width: width, height: height, rgbaBytes: bytes)
  }

  private func makeImage(
    width: Int,
    height: Int,
    rgbaBytes: [UInt8]
  ) -> CGImage? {
    guard
      width > 0,
      height > 0,
      rgbaBytes.count == width * height * 4,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(rgbaBytes) as CFData)
    else {
      return nil
    }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(
        rawValue:
          CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}
