import Foundation
import Testing

@testable import LectureBoardCore

struct SlideCanvasRegionTests {
  @Test func acceptsAFullFrameAndReportsItsSemanticIdentity() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )

    #expect(region.isFullFrame)
    #expect(
      region.normalizedRect
        == NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    )
  }

  @Test func rejectsNonFiniteEmptyAndOutOfBoundsRegions() {
    #expect(SlideCanvasRegion(x: .nan, y: 0, width: 1, height: 1) == nil)
    #expect(SlideCanvasRegion(x: 0, y: .infinity, width: 1, height: 1) == nil)
    #expect(SlideCanvasRegion(x: 0, y: 0, width: 0, height: 1) == nil)
    #expect(SlideCanvasRegion(x: 0, y: 0, width: 1, height: -0.1) == nil)
    #expect(SlideCanvasRegion(x: -0.1, y: 0, width: 1, height: 1) == nil)
    #expect(SlideCanvasRegion(x: 0, y: -0.1, width: 1, height: 1) == nil)
    #expect(SlideCanvasRegion(x: 0.2, y: 0, width: 0.81, height: 1) == nil)
    #expect(SlideCanvasRegion(x: 0, y: 0.2, width: 1, height: 0.81) == nil)
    #expect(SlideCanvasRegion(x: 1, y: 0, width: 0.1, height: 1) == nil)
  }

  @Test func mapsTopLeftCoordinatesWithOutwardRounding() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0.101, y: 0.201, width: 0.301, height: 0.401)
    )
    let pixels = try #require(
      region.pixelRect(sourcePixelWidth: 100, sourcePixelHeight: 50)
    )

    #expect(pixels.x == 10)
    #expect(pixels.y == 10)
    #expect(pixels.maxX == 41)
    #expect(pixels.maxY == 31)
    #expect(pixels.width == 31)
    #expect(pixels.height == 21)
  }

  @Test func clampsRightAndBottomBoundariesToTheSourceDimensions() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0.9, y: 0.8, width: 0.1, height: 0.2)
    )
    let pixels = try #require(
      region.pixelRect(sourcePixelWidth: 13, sourcePixelHeight: 7)
    )

    #expect(pixels.x == 11)
    #expect(pixels.y == 5)
    #expect(pixels.maxX == 13)
    #expect(pixels.maxY == 7)
  }

  @Test func mapsAnyRepresentablePositiveRegionToAtLeastOnePixel() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0.5, y: 0.5, width: 0.000_001, height: 0.000_001)
    )
    let pixels = try #require(
      region.pixelRect(sourcePixelWidth: 2, sourcePixelHeight: 2)
    )

    #expect(pixels.width == 1)
    #expect(pixels.height == 1)
  }

  @Test func rejectsInvalidSourcePixelDimensions() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )

    #expect(region.pixelRect(sourcePixelWidth: 0, sourcePixelHeight: 10) == nil)
    #expect(region.pixelRect(sourcePixelWidth: 10, sourcePixelHeight: -1) == nil)
  }

  @Test func mapsTheFullFrameWithoutOverflowAtIntMax() throws {
    let region = try #require(
      SlideCanvasRegion(x: 0, y: 0, width: 1, height: 1)
    )
    let pixels = try #require(
      region.pixelRect(sourcePixelWidth: Int.max, sourcePixelHeight: Int.max)
    )

    #expect(pixels.x == 0)
    #expect(pixels.y == 0)
    #expect(pixels.width == Int.max)
    #expect(pixels.height == Int.max)
    #expect(pixels.maxX == Int.max)
    #expect(pixels.maxY == Int.max)
  }
}
