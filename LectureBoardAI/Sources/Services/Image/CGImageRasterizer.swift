import CoreGraphics
import LectureBoardCore

/// Converts native capture images into deterministic Core values at the app boundary.
enum CGImageRasterizer {
  static let defaultMaximumLongEdge = 640
  static let defaultFingerprintColumns = 160
  static let defaultFingerprintRows = 90
  /// Keeps the two temporary pixel buffers below about seven megabytes total.
  static let maximumRenderedPixelCount = 1_048_576

  /// Produces an sRGB RGB8 raster in top-left, row-major order.
  ///
  /// Images larger than `maximumLongEdge` are scaled down without changing their
  /// aspect ratio. Smaller images are not enlarged. Alpha is composited over an
  /// opaque white background before the alpha channel is discarded.
  static func makeRGBRaster(
    from image: CGImage,
    maximumLongEdge: Int = defaultMaximumLongEdge
  ) -> RGBRaster? {
    guard
      maximumLongEdge > 0,
      let dimensions = aspectFitDimensions(
        width: image.width,
        height: image.height,
        maximumLongEdge: maximumLongEdge
      ),
      let rgbBytes = renderRGB(
        image,
        width: dimensions.width,
        height: dimensions.height
      )
    else {
      return nil
    }

    return RGBRaster(
      width: dimensions.width,
      height: dimensions.height,
      rgbBytes: rgbBytes
    )
  }

  /// Produces a fixed-grid sRGB fingerprint in top-left, row-major order.
  static func makeContentFingerprint(
    from image: CGImage,
    sampleColumns: Int = defaultFingerprintColumns,
    sampleRows: Int = defaultFingerprintRows
  ) -> ContentFingerprint? {
    guard
      sampleColumns > 0,
      sampleRows > 0,
      let rgbBytes = renderRGB(
        image,
        width: sampleColumns,
        height: sampleRows
      )
    else {
      return nil
    }

    var cells: [RGBContentCell] = []
    cells.reserveCapacity(rgbBytes.count / 3)
    for offset in stride(from: 0, to: rgbBytes.count, by: 3) {
      cells.append(
        RGBContentCell(
          red: rgbBytes[offset],
          green: rgbBytes[offset + 1],
          blue: rgbBytes[offset + 2]
        )
      )
    }

    let fingerprint = ContentFingerprint(
      sampleColumns: sampleColumns,
      sampleRows: sampleRows,
      cells: cells
    )
    return fingerprint.isValid ? fingerprint : nil
  }

  private static func aspectFitDimensions(
    width: Int,
    height: Int,
    maximumLongEdge: Int
  ) -> (width: Int, height: Int)? {
    guard width > 0, height > 0, maximumLongEdge > 0 else { return nil }

    let longEdge = max(width, height)
    guard longEdge > maximumLongEdge else { return (width, height) }

    let scale = Double(maximumLongEdge) / Double(longEdge)
    guard scale.isFinite, scale > 0 else { return nil }

    let scaledWidth = max(1, Int((Double(width) * scale).rounded()))
    let scaledHeight = max(1, Int((Double(height) * scale).rounded()))
    return (
      min(scaledWidth, maximumLongEdge),
      min(scaledHeight, maximumLongEdge)
    )
  }

  private static func renderRGB(
    _ image: CGImage,
    width: Int,
    height: Int
  ) -> [UInt8]? {
    guard image.width > 0, image.height > 0, width > 0, height > 0 else {
      return nil
    }

    let (pixelCount, pixelCountOverflowed) = width.multipliedReportingOverflow(by: height)
    guard
      !pixelCountOverflowed,
      pixelCount <= maximumRenderedPixelCount
    else {
      return nil
    }

    let (rgbaByteCount, rgbaByteCountOverflowed) = pixelCount.multipliedReportingOverflow(
      by: 4
    )
    let (rgbByteCount, rgbByteCountOverflowed) = pixelCount.multipliedReportingOverflow(by: 3)
    guard
      !rgbaByteCountOverflowed,
      !rgbByteCountOverflowed,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else {
      return nil
    }

    var rgbaBytes = [UInt8](repeating: 255, count: rgbaByteCount)
    let bitmapInfo =
      CGBitmapInfo.byteOrder32Big.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue

    let rendered = rgbaBytes.withUnsafeMutableBytes { storage -> Bool in
      guard
        let baseAddress = storage.baseAddress,
        let context = CGContext(
          data: baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        )
      else {
        return false
      }

      context.interpolationQuality = .high
      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: width, height: height)
      )
      return true
    }
    guard rendered else { return nil }

    var rgbBytes: [UInt8] = []
    rgbBytes.reserveCapacity(rgbByteCount)
    for offset in stride(from: 0, to: rgbaBytes.count, by: 4) {
      rgbBytes.append(rgbaBytes[offset])
      rgbBytes.append(rgbaBytes[offset + 1])
      rgbBytes.append(rgbaBytes[offset + 2])
    }
    return rgbBytes
  }
}
