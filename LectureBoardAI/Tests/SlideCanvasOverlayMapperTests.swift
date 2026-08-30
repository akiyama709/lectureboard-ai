import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct SlideCanvasOverlayMapperTests {
  private let operationID = CaptureOperationID(rawValue: 41)
  private let windowID: CGWindowID = 73

  @Test func mapsCanonicalCanvasFromSurfacePixelsToAppKitCoordinates() throws {
    let surface = try #require(canonicalSurface())
    let screen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 160, height: 80))
    )
    let selection = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let frame = makeFrame(surface: surface, screen: screen, sequenceNumber: 19)
    let display = try #require(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
      )
    )

    let placement = try #require(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: frame,
        captureOperationID: operationID,
        displays: [display]
      )
    )

    #expect(placement.captureOperationID == operationID)
    #expect(placement.windowID == windowID)
    #expect(placement.frameSequenceNumber == 19)
    expectEqual(
      placement.appKitTargetFrame,
      CGRect(x: 140, y: 630, width: 80, height: 60)
    )
  }

  @Test func rejectsWrongOperationWindowSurfaceAndOutputDimensions() throws {
    let surface = try #require(canonicalSurface())
    let screen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 160, height: 80))
    )
    let region = try #require(
      SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
    )
    let selection = try #require(makeSelection(surface: surface, region: region))
    let display = try #require(canonicalDisplay())
    let frame = makeFrame(surface: surface, screen: screen)

    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: frame,
        captureOperationID: CaptureOperationID(rawValue: operationID.rawValue + 1),
        displays: [display]
      ) == nil
    )

    let wrongWindowFrame = makeFrame(
      surface: surface,
      screen: screen,
      windowID: windowID + 1
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: wrongWindowFrame,
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )

    let changedSurface = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 11, y: 10, width: 79, height: 40),
        scaleFactor: 2,
        contentScale: 0.5,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: changedSurface, screen: screen),
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )

    let mismatchedImageFrame = makeFrame(
      surface: surface,
      screen: screen,
      imageWidth: 201,
      imageHeight: 120
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: mismatchedImageFrame,
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )

    let testOnlySelection = try #require(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: windowID,
        sourcePixelWidth: 200,
        sourcePixelHeight: 120
      )
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: testOnlySelection,
        frame: frame,
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )
  }

  @Test func rejectsCanvasWhoseOutwardRoundedPixelsCrossSurfacePadding() throws {
    let surface = try #require(canonicalSurface())
    let screen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 160, height: 80))
    )
    let display = try #require(canonicalDisplay())
    let frame = makeFrame(surface: surface, screen: screen)
    let crossesLeftPadding = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.095, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let crossesBottomPadding = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.6)
      )
    )

    for selection in [crossesLeftPadding, crossesBottomPadding] {
      #expect(
        SlideCanvasOverlayMapper.makePlacement(
          selection: selection,
          frame: frame,
          captureOperationID: operationID,
          displays: [display]
        ) == nil
      )
    }

    let exactContentSupport = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.1, y: 1.0 / 6.0, width: 0.8, height: 2.0 / 3.0)
      )
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: exactContentSupport,
        frame: frame,
        captureOperationID: operationID,
        displays: [display]
      ) != nil
    )
  }

  @Test func rejectsMissingScreenGeometryAndScreenContentSizeMismatch() throws {
    let surface = try #require(canonicalSurface())
    let selection = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let display = try #require(canonicalDisplay())

    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: surface, screen: nil),
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )

    let mismatchedScreen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 162, height: 80))
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: surface, screen: mismatchedScreen),
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )
  }

  @Test func permitsExactlyOneOutputPixelOfScreenSizeRoundingDrift() throws {
    let surface = try #require(canonicalSurface())
    let selection = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let display = try #require(canonicalDisplay())
    let exactBoundary = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 161, height: 80))
    )
    let beyondBoundary = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 100, y: 200, width: 161.000_001, height: 80)
      )
    )

    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: surface, screen: exactBoundary),
        captureOperationID: operationID,
        displays: [display]
      ) != nil
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: surface, screen: beyondBoundary),
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )
  }

  @Test func permitsExactlyOneOutputPixelOfSurfaceBoundaryDrift() throws {
    let exactBoundarySurface = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 10, y: 10, width: 90.5, height: 40),
        scaleFactor: 2,
        contentScale: 0.5,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let beyondBoundarySurface = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 10, y: 10, width: 90.500_001, height: 40),
        scaleFactor: 2,
        contentScale: 0.5,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let region = try #require(
      SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
    )
    let exactSelection = try #require(
      makeSelection(surface: exactBoundarySurface, region: region)
    )
    let beyondSelection = try #require(
      makeSelection(surface: beyondBoundarySurface, region: region)
    )
    let exactScreen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 181, height: 80))
    )
    let beyondScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 100, y: 200, width: 181.000_002, height: 80)
      )
    )
    let display = try #require(canonicalDisplay())

    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: exactSelection,
        frame: makeFrame(surface: exactBoundarySurface, screen: exactScreen),
        captureOperationID: operationID,
        displays: [display]
      ) != nil
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: beyondSelection,
        frame: makeFrame(surface: beyondBoundarySurface, screen: beyondScreen),
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )
  }

  @Test func rejectsCrossDisplayAndAmbiguousDisplayPlacements() throws {
    let surface = try #require(canonicalSurface())
    let screen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 100, y: 200, width: 160, height: 80))
    )
    let selection = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let frame = makeFrame(surface: surface, screen: screen)
    let left = try #require(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 200, height: 900),
        appKitFrame: CGRect(x: 0, y: 0, width: 200, height: 900)
      )
    )
    let right = try #require(
      DisplayCoordinateSnapshot(
        displayID: 2,
        quartzGlobalFrame: CGRect(x: 200, y: 0, width: 200, height: 900),
        appKitFrame: CGRect(x: 200, y: 0, width: 200, height: 900)
      )
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: frame,
        captureOperationID: operationID,
        displays: [left, right]
      ) == nil
    )

    let firstMirror = try #require(canonicalDisplay(displayID: 10))
    let secondMirror = try #require(canonicalDisplay(displayID: 11))
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: frame,
        captureOperationID: operationID,
        displays: [firstMirror, secondMirror]
      ) == nil
    )
    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: frame,
        captureOperationID: operationID,
        displays: []
      ) == nil
    )
  }

  @Test func convertsAPlacementOnANegativePositionDisplay() throws {
    let surface = try #require(canonicalSurface())
    let screen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: -900, y: 100, width: 160, height: 80))
    )
    let selection = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let display = try #require(
      DisplayCoordinateSnapshot(
        displayID: 3,
        quartzGlobalFrame: CGRect(x: -1_000, y: 0, width: 1_000, height: 800),
        appKitFrame: CGRect(x: -1_000, y: 0, width: 1_000, height: 800)
      )
    )

    let placement = try #require(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: surface, screen: screen),
        captureOperationID: operationID,
        displays: [display]
      )
    )
    expectEqual(
      placement.appKitTargetFrame,
      CGRect(x: -860, y: 630, width: 80, height: 60)
    )
  }

  @Test func validatesDisplayCoordinateSnapshotsFailClosed() {
    #expect(
      DisplayCoordinateSnapshot(
        displayID: 0,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        appKitFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
      ) == nil
    )
    #expect(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
        appKitFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
      ) == nil
    )
    #expect(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 0, height: 100),
        appKitFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
      ) == nil
    )
    #expect(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: -100, height: 100),
        appKitFrame: CGRect(x: 0, y: 0, width: 100, height: 100)
      ) == nil
    )
    #expect(
      DisplayCoordinateSnapshot(
        displayID: 1,
        quartzGlobalFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        appKitFrame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)
      ) == nil
    )
  }

  @Test func rejectsNonFiniteDerivedSurfaceArithmetic() throws {
    let surface = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(
          x: 0,
          y: 0,
          width: Double.greatestFiniteMagnitude,
          height: 40
        ),
        scaleFactor: 4,
        contentScale: 1,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let selection = try #require(
      makeSelection(
        surface: surface,
        region: SlideCanvasRegion(x: 0.3, y: 0.25, width: 0.4, height: 0.5)
      )
    )
    let screen = try #require(
      CaptureScreenGeometry(screenRect: CGRect(x: 0, y: 0, width: 160, height: 80))
    )
    let display = try #require(canonicalDisplay())

    #expect(
      SlideCanvasOverlayMapper.makePlacement(
        selection: selection,
        frame: makeFrame(surface: surface, screen: screen),
        captureOperationID: operationID,
        displays: [display]
      ) == nil
    )
  }

  private func canonicalSurface() -> CaptureSurfaceGeometry? {
    CaptureSurfaceGeometry(
      contentRect: CGRect(x: 10, y: 10, width: 80, height: 40),
      scaleFactor: 2,
      contentScale: 0.5,
      outputPixelWidth: 200,
      outputPixelHeight: 120
    )
  }

  private func canonicalDisplay(
    displayID: CGDirectDisplayID = 1
  ) -> DisplayCoordinateSnapshot? {
    DisplayCoordinateSnapshot(
      displayID: displayID,
      quartzGlobalFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
      appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )
  }

  private func makeSelection(
    surface: CaptureSurfaceGeometry,
    region: SlideCanvasRegion?
  ) -> ConfirmedSlideCanvasSelection? {
    guard let region else { return nil }
    return ConfirmedSlideCanvasSelection(
      captureOperationID: operationID,
      windowID: windowID,
      captureSurfaceGeometry: surface,
      region: region
    )
  }

  private func makeFrame(
    surface: CaptureSurfaceGeometry,
    screen: CaptureScreenGeometry?,
    sequenceNumber: UInt64 = 1,
    windowID: CGWindowID? = nil,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil
  ) -> CapturedPowerPointFrame {
    let image = makeImage(
      width: imageWidth ?? surface.outputPixelWidth,
      height: imageHeight ?? surface.outputPixelHeight
    )
    return CapturedPowerPointFrame(
      windowID: windowID ?? self.windowID,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(timeIntervalSince1970: 1),
      displayTime: 2,
      deliveryKind: .new,
      captureSurfaceGeometry: surface,
      captureScreenGeometry: screen,
      image: image,
      fingerprint: FrameFingerprint(sampleColumns: 1, sampleRows: 1, luminance: [0]),
      contentFingerprint: nil
    )
  }

  private func makeImage(width: Int, height: Int) -> CGImage {
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let image = context.makeImage()
    else {
      preconditionFailure("Synthetic image must be valid.")
    }
    return image
  }

  private func expectEqual(
    _ actual: CGRect,
    _ expected: CGRect,
    tolerance: Double = 1e-9
  ) {
    #expect(abs(Double(actual.minX - expected.minX)) <= tolerance)
    #expect(abs(Double(actual.minY - expected.minY)) <= tolerance)
    #expect(abs(Double(actual.width - expected.width)) <= tolerance)
    #expect(abs(Double(actual.height - expected.height)) <= tolerance)
  }
}
