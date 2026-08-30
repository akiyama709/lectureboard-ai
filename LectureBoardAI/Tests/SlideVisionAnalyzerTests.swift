import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct SlideVisionAnalyzerTests {
  @Test func wiresRasterCandidatesIntoAssembledOccupancy() async throws {
    let image = try #require(makeStrokeImage())
    let raster = try #require(CGImageRasterizer.makeRGBRaster(from: image))
    let occupancyDetector = RasterOccupancyDetector(
      configuration: RasterOccupancyConfiguration(
        minimumChannelDifference: 40,
        minimumComponentPixelCount: 4,
        componentConnectionRadius: 2
      )
    )
    let assembler = SlideAnalysisAssembler(
      configuration: SlideAnalysisConfiguration(
        minimumTextConfidence: 1,
        minimumGeometryConfidence: 1,
        minimumTextArea: 1,
        minimumGeometryArea: 1,
        maximumGeometryArea: 1,
        occupancyPadding: 0.01,
        mergeTolerance: 0
      )
    )
    let expectedCandidates = occupancyDetector.strokeCandidateRegions(in: raster)
    let expectedAnalysis = assembler.assemble(
      textObservations: [],
      geometryObservations: [],
      strokeCandidateRegions: expectedCandidates
    )
    let analyzer = SlideVisionAnalyzer(
      assembler: assembler,
      rasterOccupancyDetector: occupancyDetector
    )

    let analysis = try await analyzer.analyze(makeFrame(image: image))

    #expect(!expectedCandidates.isEmpty)
    #expect(analysis.textBlocks.isEmpty)
    #expect(analysis.graphicRegions.isEmpty)
    #expect(analysis.strokeCandidateRegions == expectedAnalysis.strokeCandidateRegions)
    #expect(analysis.occupiedRegions == expectedAnalysis.occupiedRegions)
    #expect(!analysis.occupiedRegions.isEmpty)
  }

  @Test func preCancelledAnalysisStopsBeforeNativeWork() async throws {
    let image = try #require(makeOversizedImage())
    let analyzer = SlideVisionAnalyzer()
    let frame = makeFrame(image: image)

    let task = Task {
      withUnsafeCurrentTask { currentTask in
        currentTask?.cancel()
      }
      return try await analyzer.analyze(frame)
    }

    do {
      _ = try await task.value
      Issue.record("Expected cancellation before native analysis work.")
    } catch is CancellationError {
      // Expected.
    } catch {
      Issue.record("Expected CancellationError, received: \(error)")
    }
  }

  private func makeFrame(image: CGImage) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: 1,
      capturedAt: .distantPast,
      deliveryKind: .new,
      image: image,
      fingerprint: FrameFingerprint(
        sampleColumns: 1,
        sampleRows: 1,
        luminance: [255]
      ),
      contentFingerprint: nil
    )
  }

  private func makeOversizedImage() -> CGImage? {
    let edge = 1_025
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: edge,
        height: edge,
        bitsPerComponent: 8,
        bytesPerRow: edge * 4,
        space: colorSpace,
        bitmapInfo:
          CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    return context.makeImage()
  }

  private func makeStrokeImage() -> CGImage? {
    let width = 32
    let height = 24
    var bytes = [UInt8](repeating: 255, count: width * height * 4)

    for y in 9..<15 {
      for x in 7..<25 {
        let offset = (y * width + x) * 4
        bytes[offset] = 16
        bytes[offset + 1] = 32
        bytes[offset + 2] = 160
        bytes[offset + 3] = 255
      }
    }

    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(bytes) as CFData)
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
