import CoreGraphics
import Foundation
import LectureBoardCore
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

    let frame = CapturedPowerPointFrameFactory.makeNewFrame(
      windowID: 42,
      sequenceNumber: 7,
      capturedAt: capturedAt,
      image: image,
      fingerprint: coarseFingerprint
    )

    #expect(frame.windowID == 42)
    #expect(frame.sequenceNumber == 7)
    #expect(frame.capturedAt == capturedAt)
    #expect(frame.deliveryKind == .new)
    #expect(frame.fingerprint == coarseFingerprint)
    let contentFingerprint = try #require(frame.contentFingerprint)
    #expect(contentFingerprint.sampleColumns == 160)
    #expect(contentFingerprint.sampleRows == 90)
    #expect(contentFingerprint.cells.count == 160 * 90)
    #expect(contentFingerprint.isValid)

    let repeatedAt = Date(timeIntervalSince1970: 124)
    let repeated = CapturedPowerPointFrameFactory.makeIdleRepeat(
      from: frame,
      sequenceNumber: 8,
      capturedAt: repeatedAt
    )
    #expect(repeated.windowID == frame.windowID)
    #expect(repeated.sequenceNumber == 8)
    #expect(repeated.capturedAt == repeatedAt)
    #expect(repeated.deliveryKind == .idleRepeat)
    #expect(repeated.image === frame.image)
    #expect(repeated.fingerprint == coarseFingerprint)
    #expect(repeated.contentFingerprint == contentFingerprint)
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
