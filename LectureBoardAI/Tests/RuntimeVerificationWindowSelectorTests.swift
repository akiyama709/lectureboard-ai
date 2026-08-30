import CoreGraphics
import Testing

@testable import LectureBoard_AI

struct RuntimeVerificationWindowSelectorTests {
  @Test func exactMatchTakesPriorityOverOtherPartialMatches() {
    let windows = [
      window(id: 1, title: "Runtime Verification"),
      window(id: 2, title: "Runtime Verification - PowerPoint"),
    ]

    let result = RuntimeVerificationWindowSelector.select(
      from: windows,
      titleSubstring: "Runtime Verification"
    )

    #expect(result.resolution == .selected(1))
    #expect(result.matchedWindowCount == 1)
  }

  @Test func selectsOnlyUniquePartialMatch() {
    let windows = [
      window(id: 1, title: "LectureBoard Runtime Verification - PowerPoint"),
      window(id: 2, title: "Unrelated Deck"),
    ]

    let result = RuntimeVerificationWindowSelector.select(
      from: windows,
      titleSubstring: "runtime verification"
    )

    #expect(result.resolution == .selected(1))
    #expect(result.matchedWindowCount == 1)
  }

  @Test func rejectsAmbiguousPartialMatches() {
    let windows = [
      window(id: 1, title: "Runtime Verification A"),
      window(id: 2, title: "Runtime Verification B"),
    ]

    let result = RuntimeVerificationWindowSelector.select(
      from: windows,
      titleSubstring: "Runtime Verification"
    )

    #expect(result.resolution == .ambiguous)
    #expect(result.matchedWindowCount == 2)
  }

  @Test func reportsNoMatchWithoutFallingBackToAnArbitraryWindow() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [window(id: 1, title: "Unrelated Deck")],
      titleSubstring: "Runtime Verification"
    )

    #expect(result.resolution == .notFound)
    #expect(result.matchedWindowCount == 0)
  }

  private func window(id: CGWindowID, title: String) -> PowerPointWindowDescriptor {
    PowerPointWindowDescriptor(
      id: id,
      title: title,
      applicationName: "Microsoft PowerPoint",
      bundleIdentifier: "com.microsoft.Powerpoint",
      frame: .zero
    )
  }
}
