import Foundation
import LectureBoardCore

struct RuntimeVerificationReportWriter: Sendable {
  func write(_ report: RuntimeVerificationReport, toPath path: String) throws {
    let outputURL = URL(fileURLWithPath: path)
    let outputDirectory = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [
      .prettyPrinted,
      .sortedKeys,
      .withoutEscapingSlashes,
    ]
    let data = try encoder.encode(report)
    try data.write(to: outputURL, options: .atomic)
  }
}
