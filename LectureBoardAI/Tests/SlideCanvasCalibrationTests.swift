import CoreGraphics
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct SlideCanvasCalibrationTests {
  @Test func automaticSelectionExcludesSurfacePaddingAndExactlyMatchesSamplerCrop() throws {
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 10.25, y: 5.25, width: 79.5, height: 39.5),
        scaleFactor: 2,
        contentScale: 0.5,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let samplerCrop = try #require(
      FrameFingerprintSampler.PixelCrop(surfaceGeometry: geometry)
    )
    let region = try #require(AutomaticSlideCanvasSelection.region(for: geometry))
    let roundTrip = try #require(
      region.pixelRect(sourcePixelWidth: 200, sourcePixelHeight: 120)
    )

    #expect(!region.isFullFrame)
    #expect(roundTrip.x == samplerCrop.x)
    #expect(roundTrip.y == samplerCrop.y)
    #expect(roundTrip.width == samplerCrop.width)
    #expect(roundTrip.height == samplerCrop.height)
    #expect(roundTrip.x == 21)
    #expect(roundTrip.y == 11)
    #expect(roundTrip.width == 158)
    #expect(roundTrip.height == 78)
  }

  @Test func automaticSelectionPreservesTrueFullContentSurface() throws {
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 0, y: 0, width: 100, height: 60),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: 200,
        outputPixelHeight: 120
      )
    )
    let region = try #require(AutomaticSlideCanvasSelection.region(for: geometry))

    #expect(region.isFullFrame)
    #expect(
      region.pixelRect(sourcePixelWidth: 200, sourcePixelHeight: 120)?.width == 200
    )
    #expect(
      region.pixelRect(sourcePixelWidth: 200, sourcePixelHeight: 120)?.height == 120
    )
  }

  @Test func automaticSelectionRejectsTooSmallContentCrop() throws {
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 10, y: 10, width: 31, height: 31),
        scaleFactor: 1,
        contentScale: 1,
        outputPixelWidth: 100,
        outputPixelHeight: 100
      )
    )

    #expect(AutomaticSlideCanvasSelection.region(for: geometry) == nil)
  }

  @Test func automaticSelectionRejectsContentGeometryOutsideOutputSurface() throws {
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 90, y: 10, width: 20, height: 40),
        scaleFactor: 1,
        contentScale: 1,
        outputPixelWidth: 100,
        outputPixelHeight: 100
      )
    )

    #expect(FrameFingerprintSampler.PixelCrop(surfaceGeometry: geometry) == nil)
    #expect(AutomaticSlideCanvasSelection.region(for: geometry) == nil)
  }

  @Test func dragSelectionNormalizesForwardAndReverseDrags() throws {
    let size = CGSize(width: 200, height: 100)
    let forward = try #require(
      SlideCanvasDragSelection.region(
        from: CGPoint(x: 20, y: 10),
        to: CGPoint(x: 180, y: 90),
        in: size
      )
    )
    let reverse = try #require(
      SlideCanvasDragSelection.region(
        from: CGPoint(x: 180, y: 90),
        to: CGPoint(x: 20, y: 10),
        in: size
      )
    )

    #expect(forward == reverse)
    #expect(forward.normalizedRect.x == 0.1)
    #expect(forward.normalizedRect.y == 0.1)
    #expect(forward.normalizedRect.width == 0.8)
    #expect(forward.normalizedRect.height == 0.8)
  }

  @Test func dragSelectionClampsToPreviewBounds() throws {
    let region = try #require(
      SlideCanvasDragSelection.region(
        from: CGPoint(x: -20, y: 25),
        to: CGPoint(x: 240, y: 75),
        in: CGSize(width: 200, height: 100)
      )
    )

    #expect(region.normalizedRect.x == 0)
    #expect(region.normalizedRect.y == 0.25)
    #expect(region.normalizedRect.width == 1)
    #expect(region.normalizedRect.height == 0.5)
  }

  @Test func dragSelectionRejectsInvalidPreviewGeometryAndTinyDrags() {
    #expect(
      SlideCanvasDragSelection.region(
        from: .zero,
        to: CGPoint(x: 10, y: 10),
        in: .zero
      ) == nil
    )
    #expect(
      SlideCanvasDragSelection.region(
        from: CGPoint(x: CGFloat.nan, y: 0),
        to: CGPoint(x: 10, y: 10),
        in: CGSize(width: 100, height: 100)
      ) == nil
    )
    #expect(
      SlideCanvasDragSelection.region(
        from: CGPoint(x: 10, y: 10),
        to: CGPoint(x: 10, y: 10),
        in: CGSize(width: 100, height: 100)
      ) == nil
    )
  }

  @Test func sourcePixelPolicyRejectsWidthHeightAndAreaBelowTheMinimum() throws {
    let sourceWidth = 80
    let sourceHeight = 40
    let tooNarrow = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 31.0 / 80.0, height: 1)
    )
    let tooShort = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 23.0 / 40.0)
    )
    let tooSmallByArea = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 32.0 / 80.0, height: 24.0 / 40.0)
    )

    #expect(
      !SlideCanvasSelectionPolicy.accepts(
        tooNarrow,
        sourcePixelWidth: sourceWidth,
        sourcePixelHeight: sourceHeight
      )
    )
    #expect(
      !SlideCanvasSelectionPolicy.accepts(
        tooShort,
        sourcePixelWidth: sourceWidth,
        sourcePixelHeight: sourceHeight
      )
    )
    #expect(
      !SlideCanvasSelectionPolicy.accepts(
        tooSmallByArea,
        sourcePixelWidth: sourceWidth,
        sourcePixelHeight: sourceHeight
      )
    )
  }

  @Test func sourcePixelPolicyAllowsBoundaryAndPracticalAspectRatios() throws {
    let sourceWidth = 80
    let sourceHeight = 40
    let exactBoundary = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 32.0 / 80.0, height: 32.0 / 40.0)
    )
    let horizontal = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 24.0 / 40.0)
    )
    let vertical = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 32.0 / 80.0, height: 1)
    )
    let fullFrame = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )

    for region in [exactBoundary, horizontal, vertical, fullFrame] {
      #expect(
        SlideCanvasSelectionPolicy.accepts(
          region,
          sourcePixelWidth: sourceWidth,
          sourcePixelHeight: sourceHeight
        )
      )
    }
  }
}
