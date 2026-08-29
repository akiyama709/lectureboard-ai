import AppKit

struct DigitalInkStyle: Equatable {
  enum Preset: String, CaseIterable, Identifiable {
    case clean
    case handwritten

    var id: String { rawValue }
  }

  var preset: Preset
  var primaryColor: NSColor
  var emphasisColor: NSColor
  var lineWidth: CGFloat
  var handDrawnVariation: CGFloat

  static let clean = DigitalInkStyle(
    preset: .clean,
    primaryColor: .labelColor,
    emphasisColor: .systemRed,
    lineWidth: 2.2,
    handDrawnVariation: 0
  )

  static let handwritten = DigitalInkStyle(
    preset: .handwritten,
    primaryColor: .labelColor,
    emphasisColor: .systemRed,
    lineWidth: 2.6,
    handDrawnVariation: 0.8
  )
}
