import Foundation
import Testing

@testable import LectureBoardCore

struct RasterOccupancyDetectorTests {
  private let detector = RasterOccupancyDetector()

  @Test func rejectsInvalidRasterDimensionsAndByteCounts() {
    #expect(RGBRaster(width: 0, height: 1, rgbBytes: []) == nil)
    #expect(RGBRaster(width: 1, height: 0, rgbBytes: []) == nil)
    #expect(RGBRaster(width: -1, height: 1, rgbBytes: []) == nil)
    #expect(RGBRaster(width: 2, height: 2, rgbBytes: Array(repeating: 0, count: 11)) == nil)
    #expect(RGBRaster(width: Int.max, height: 2, rgbBytes: []) == nil)

    let raster = RGBRaster(
      width: 2,
      height: 2,
      rgbBytes: Array(repeating: 0, count: 12)
    )
    #expect(raster != nil)
  }

  @Test func normalizesConfigurationBounds() {
    let configuration = RasterOccupancyConfiguration(
      minimumChannelDifference: 300,
      minimumComponentPixelCount: 0,
      componentConnectionRadius: -4
    )

    #expect(configuration.minimumChannelDifference == 255)
    #expect(configuration.minimumComponentPixelCount == 1)
    #expect(configuration.componentConnectionRadius == 1)
  }

  @Test func uniformWhiteBlackAndColoredBackgroundsHaveNoCandidates() {
    let colors = [
      RGB(red: 255, green: 255, blue: 255),
      RGB(red: 0, green: 0, blue: 0),
      RGB(red: 36, green: 118, blue: 184),
    ]

    for color in colors {
      let raster = RasterFixture(width: 32, height: 24, fill: color).raster
      #expect(detector.strokeCandidateRegions(in: raster).isEmpty)
    }
  }

  @Test func detectsDarkLightAndDifferentColorThinLines() {
    let fixtures: [(background: RGB, stroke: RGB)] = [
      (.white, .black),
      (.black, .white),
      (
        RGB(red: 36, green: 118, blue: 184),
        RGB(red: 220, green: 64, blue: 92)
      ),
    ]

    for fixture in fixtures {
      var builder = RasterFixture(width: 40, height: 24, fill: fixture.background)
      builder.drawHorizontalLine(fromX: 7, throughX: 31, y: 11, color: fixture.stroke)

      let regions = detector.strokeCandidateRegions(in: builder.raster)
      #expect(regions.count == 1)
      #expect(regions[0].x <= 7.0 / 40.0)
      #expect(regions[0].maxX >= 32.0 / 40.0)
      #expect(regions[0].y <= 11.0 / 24.0)
      #expect(regions[0].maxY >= 12.0 / 24.0)
    }
  }

  @Test func removesSeparatedIsolatedPixelNoise() {
    var builder = RasterFixture(width: 48, height: 32, fill: .white)
    for point in [(4, 4), (16, 8), (30, 6), (9, 23), (37, 25)] {
      builder.set(x: point.0, y: point.1, color: .black)
    }

    #expect(detector.strokeCandidateRegions(in: builder.raster).isEmpty)
  }

  @Test func detectsFiveThinLinesWithoutAreaFilteringThemAway() {
    var builder = RasterFixture(width: 80, height: 64, fill: .white)
    let lineRows = [8, 19, 30, 41, 52]
    for row in lineRows {
      builder.drawHorizontalLine(fromX: 10, throughX: 69, y: row, color: .black)
    }

    let regions = detector.strokeCandidateRegions(in: builder.raster)
    #expect(regions.count == 5)
    #expect(zip(regions, regions.dropFirst()).allSatisfy { $0.y < $1.y })
    for (region, row) in zip(regions, lineRows) {
      #expect(region.height <= 4.0 / 64.0)
      #expect(region.y <= Double(row) / 64.0)
      #expect(region.maxY >= Double(row + 1) / 64.0)
    }
  }

  @Test func erasedLineReturnsToNoCandidates() {
    var builder = RasterFixture(width: 40, height: 24, fill: .white)
    builder.drawHorizontalLine(fromX: 5, throughX: 34, y: 12, color: .black)
    #expect(detector.strokeCandidateRegions(in: builder.raster).count == 1)

    builder.fill(.white)
    #expect(detector.strokeCandidateRegions(in: builder.raster).isEmpty)
  }

  @Test func linearColorGradientRemainsBlank() {
    var builder = RasterFixture(width: 64, height: 32, fill: .black)
    for y in 0..<builder.height {
      for x in 0..<builder.width {
        let red = UInt8((x * 255) / (builder.width - 1))
        let green = UInt8((x * 143) / (builder.width - 1) + 40)
        let blue = UInt8(220 - (x * 180) / (builder.width - 1))
        builder.set(x: x, y: y, color: RGB(red: red, green: green, blue: blue))
      }
    }

    #expect(detector.strokeCandidateRegions(in: builder.raster).isEmpty)
  }

  @Test func checkerboardIsReservedConservatively() {
    var builder = RasterFixture(width: 32, height: 24, fill: .white)
    for y in 0..<builder.height {
      for x in 0..<builder.width where (x + y).isMultiple(of: 2) {
        builder.set(x: x, y: y, color: .black)
      }
    }

    let regions = detector.strokeCandidateRegions(in: builder.raster)
    #expect(regions == [NormalizedRect(x: 0, y: 0, width: 1, height: 1)])
  }

  @Test func edgeCandidatesAreClampedToNormalizedBounds() {
    var leftBuilder = RasterFixture(width: 32, height: 24, fill: .white)
    leftBuilder.drawVerticalLine(x: 0, fromY: 3, throughY: 20, color: .black)
    let leftRegions = detector.strokeCandidateRegions(in: leftBuilder.raster)
    #expect(leftRegions.count == 1)
    #expect(leftRegions[0].x == 0)
    #expect(leftRegions[0].y >= 0)
    #expect(leftRegions[0].maxX <= 1)
    #expect(leftRegions[0].maxY <= 1)

    var bottomBuilder = RasterFixture(width: 32, height: 24, fill: .white)
    bottomBuilder.drawHorizontalLine(fromX: 3, throughX: 28, y: 23, color: .black)
    let bottomRegions = detector.strokeCandidateRegions(in: bottomBuilder.raster)
    #expect(bottomRegions.count == 1)
    #expect(bottomRegions[0].maxY == 1)
    #expect(bottomRegions[0].x >= 0)
    #expect(bottomRegions[0].maxX <= 1)
  }

  @Test func outputOrderAndRepeatedResultsAreDeterministic() {
    var builder = RasterFixture(width: 64, height: 48, fill: .white)
    builder.drawHorizontalLine(fromX: 35, throughX: 57, y: 30, color: .black)
    builder.drawHorizontalLine(fromX: 39, throughX: 58, y: 9, color: .black)
    builder.drawHorizontalLine(fromX: 5, throughX: 25, y: 9, color: .black)

    let first = detector.strokeCandidateRegions(in: builder.raster)
    let second = detector.strokeCandidateRegions(in: builder.raster)

    #expect(first == second)
    #expect(first.count == 3)
    #expect(first[0].y == first[1].y)
    #expect(first[0].x < first[1].x)
    #expect(first[1].y < first[2].y)
  }
}

private struct RGB: Equatable {
  var red: UInt8
  var green: UInt8
  var blue: UInt8

  static let black = RGB(red: 0, green: 0, blue: 0)
  static let white = RGB(red: 255, green: 255, blue: 255)
}

private struct RasterFixture {
  let width: Int
  let height: Int
  private var rgbBytes: [UInt8]

  init(width: Int, height: Int, fill color: RGB) {
    self.width = width
    self.height = height
    rgbBytes = []
    rgbBytes.reserveCapacity(width * height * 3)
    for _ in 0..<(width * height) {
      rgbBytes.append(color.red)
      rgbBytes.append(color.green)
      rgbBytes.append(color.blue)
    }
  }

  var raster: RGBRaster {
    RGBRaster(width: width, height: height, rgbBytes: rgbBytes)!
  }

  mutating func fill(_ color: RGB) {
    for y in 0..<height {
      for x in 0..<width {
        set(x: x, y: y, color: color)
      }
    }
  }

  mutating func set(x: Int, y: Int, color: RGB) {
    let offset = (y * width + x) * 3
    rgbBytes[offset] = color.red
    rgbBytes[offset + 1] = color.green
    rgbBytes[offset + 2] = color.blue
  }

  mutating func drawHorizontalLine(
    fromX: Int,
    throughX: Int,
    y: Int,
    color: RGB
  ) {
    for x in fromX...throughX {
      set(x: x, y: y, color: color)
    }
  }

  mutating func drawVerticalLine(
    x: Int,
    fromY: Int,
    throughY: Int,
    color: RGB
  ) {
    for y in fromY...throughY {
      set(x: x, y: y, color: color)
    }
  }
}
