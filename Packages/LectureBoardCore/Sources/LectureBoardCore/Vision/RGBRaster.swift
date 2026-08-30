import Foundation

/// An immutable RGB8 raster in top-left, row-major order.
///
/// The initializer fails when the dimensions are not positive, their byte count
/// overflows `Int`, or `rgbBytes` does not contain exactly three bytes per pixel.
/// `RGBRaster` intentionally is not `Codable`: callers should keep encoded image
/// transport outside `LectureBoardCore` and construct this deterministic value at
/// the analysis boundary.
public struct RGBRaster: Hashable, Sendable {
  public let width: Int
  public let height: Int
  public let rgbBytes: [UInt8]

  public init?(width: Int, height: Int, rgbBytes: [UInt8]) {
    guard width > 0, height > 0 else { return nil }

    let (pixelCount, pixelCountOverflowed) = width.multipliedReportingOverflow(by: height)
    guard !pixelCountOverflowed else { return nil }

    let (expectedByteCount, byteCountOverflowed) = pixelCount.multipliedReportingOverflow(by: 3)
    guard !byteCountOverflowed, rgbBytes.count == expectedByteCount else { return nil }

    self.width = width
    self.height = height
    self.rgbBytes = rgbBytes
  }

  func channel(_ channel: Int, x: Int, y: Int) -> Int {
    Int(rgbBytes[((y * width) + x) * 3 + channel])
  }
}
