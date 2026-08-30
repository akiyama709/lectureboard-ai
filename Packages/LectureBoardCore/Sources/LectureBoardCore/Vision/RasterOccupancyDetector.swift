import Foundation

public struct RasterOccupancyConfiguration: Hashable, Sendable {
  public var minimumChannelDifference: Int
  public var minimumComponentPixelCount: Int
  public var componentConnectionRadius: Int

  public init(
    minimumChannelDifference: Int = 48,
    minimumComponentPixelCount: Int = 6,
    componentConnectionRadius: Int = 2
  ) {
    self.minimumChannelDifference = min(max(minimumChannelDifference, 1), 255)
    self.minimumComponentPixelCount = max(minimumComponentPixelCount, 1)
    self.componentConnectionRadius = min(max(componentConnectionRadius, 1), 2)
  }
}

/// Finds raster regions that may contain strokes without asserting their origin.
///
/// Candidate pixels are selected by an integer, local second-difference test.
/// Linear gradients therefore remain empty, while thin light, dark, or differently
/// colored marks produce connected candidates. Dense high-frequency material is
/// retained conservatively because overlooking occupied content is more harmful to
/// board placement than reserving extra space.
public struct RasterOccupancyDetector: Sendable {
  public var configuration: RasterOccupancyConfiguration

  public init(configuration: RasterOccupancyConfiguration = .init()) {
    self.configuration = configuration
  }

  public func strokeCandidateRegions(in raster: RGBRaster) -> [NormalizedRect] {
    let candidateMask = makeCandidateMask(for: raster)
    let components = connectedComponents(
      in: candidateMask,
      width: raster.width,
      height: raster.height
    )

    return
      components
      .filter { $0.pixelCount >= configuration.minimumComponentPixelCount }
      .map { component in
        NormalizedRect(
          x: Double(component.minimumX) / Double(raster.width),
          y: Double(component.minimumY) / Double(raster.height),
          width: Double(component.maximumX - component.minimumX + 1) / Double(raster.width),
          height: Double(component.maximumY - component.minimumY + 1) / Double(raster.height)
        ).clamped()
      }
      .sorted(by: spatiallyPrecedes)
  }

  private func makeCandidateMask(for raster: RGBRaster) -> [Bool] {
    var result = Array(repeating: false, count: raster.width * raster.height)

    for y in 0..<raster.height {
      for x in 0..<raster.width {
        let leftX = max(x - 1, 0)
        let rightX = min(x + 1, raster.width - 1)
        let upperY = max(y - 1, 0)
        let lowerY = min(y + 1, raster.height - 1)
        var difference = 0

        for channel in 0..<3 {
          let value = raster.channel(channel, x: x, y: y)
          let horizontalBackground =
            (raster.channel(channel, x: leftX, y: y)
              + raster.channel(channel, x: rightX, y: y)) / 2
          let verticalBackground =
            (raster.channel(channel, x: x, y: upperY)
              + raster.channel(channel, x: x, y: lowerY)) / 2
          difference = max(
            difference,
            abs(value - horizontalBackground),
            abs(value - verticalBackground)
          )
        }

        result[y * raster.width + x] = difference >= configuration.minimumChannelDifference
      }
    }

    return result
  }

  private func connectedComponents(
    in mask: [Bool],
    width: Int,
    height: Int
  ) -> [PixelComponent] {
    var visited = Array(repeating: false, count: mask.count)
    var result: [PixelComponent] = []
    let radius = configuration.componentConnectionRadius

    for initialY in 0..<height {
      for initialX in 0..<width {
        let initialIndex = initialY * width + initialX
        guard mask[initialIndex], !visited[initialIndex] else { continue }

        visited[initialIndex] = true
        var queue: [(x: Int, y: Int)] = [(initialX, initialY)]
        var queueIndex = 0
        var component = PixelComponent(x: initialX, y: initialY)

        while queueIndex < queue.count {
          let point = queue[queueIndex]
          queueIndex += 1
          component.include(x: point.x, y: point.y)

          let minimumY = max(point.y - radius, 0)
          let maximumY = min(point.y + radius, height - 1)
          let minimumX = max(point.x - radius, 0)
          let maximumX = min(point.x + radius, width - 1)

          for neighborY in minimumY...maximumY {
            for neighborX in minimumX...maximumX {
              let neighborIndex = neighborY * width + neighborX
              guard mask[neighborIndex], !visited[neighborIndex] else { continue }
              visited[neighborIndex] = true
              queue.append((neighborX, neighborY))
            }
          }
        }

        result.append(component)
      }
    }

    return result
  }

  private func spatiallyPrecedes(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Bool {
    if lhs.y != rhs.y { return lhs.y < rhs.y }
    if lhs.x != rhs.x { return lhs.x < rhs.x }
    if lhs.height != rhs.height { return lhs.height > rhs.height }
    return lhs.width > rhs.width
  }
}

private struct PixelComponent {
  var minimumX: Int
  var minimumY: Int
  var maximumX: Int
  var maximumY: Int
  var pixelCount: Int = 0

  init(x: Int, y: Int) {
    minimumX = x
    minimumY = y
    maximumX = x
    maximumY = y
  }

  mutating func include(x: Int, y: Int) {
    minimumX = min(minimumX, x)
    minimumY = min(minimumY, y)
    maximumX = max(maximumX, x)
    maximumY = max(maximumY, y)
    pixelCount += 1
  }
}
