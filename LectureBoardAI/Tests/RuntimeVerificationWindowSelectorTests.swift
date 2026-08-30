import CoreGraphics
import LectureBoardCore
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

    #expect(result.resolution == .selected(identity(windowID: 1)))
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

    #expect(result.resolution == .selected(identity(windowID: 1)))
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

  @Test func selectsOnlyTheUniquePowerPointDescriptorWithExactWindowID() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [
        window(id: 41, title: "Other Deck"),
        window(id: 42, title: "Runtime Verification"),
      ],
      target: .windowID(42)
    )

    #expect(result.resolution == .selected(identity(windowID: 42)))
    #expect(result.matchedWindowCount == 1)
  }

  @Test func reportsMissingExactWindowID() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [window(id: 41, title: "Runtime Verification")],
      target: .windowID(42)
    )

    #expect(result.resolution == .notFound)
    #expect(result.matchedWindowCount == 0)
  }

  @Test func rejectsDuplicateExactWindowID() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [
        window(id: 42, title: "Runtime Verification A"),
        window(id: 42, title: "Runtime Verification B"),
      ],
      target: .windowID(42)
    )

    #expect(result.resolution == .ambiguous)
    #expect(result.matchedWindowCount == 2)
  }

  @Test func rejectsDuplicateExactWindowIDEvenWhenOnlyOneOwnerIsPowerPoint() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [
        window(id: 42, title: "Runtime Verification"),
        window(
          id: 42,
          title: "Wrong Owner",
          applicationName: "Keynote",
          bundleIdentifier: "com.apple.Keynote"
        ),
      ],
      target: .windowID(42)
    )

    #expect(result.resolution == .ambiguous)
    #expect(result.matchedWindowCount == 2)
  }

  @Test func doesNotUseTheDisplayApplicationNameAsOwnerIdentity() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [
        window(
          id: 42,
          title: "Runtime Verification",
          applicationName: "Keynote"
        )
      ],
      target: .windowID(42)
    )

    #expect(result.resolution == .selected(identity(windowID: 42)))
    #expect(result.matchedWindowCount == 1)
  }

  @Test func rejectsExactWindowIDOwnedByWrongBundle() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [
        window(
          id: 42,
          title: "Runtime Verification",
          bundleIdentifier: "com.apple.Keynote"
        )
      ],
      target: .windowID(42)
    )

    #expect(result.resolution == .notFound)
    #expect(result.matchedWindowCount == 0)
  }

  @Test func titleAndIDSelectionBothRejectWrongBundleOwnership() {
    let windows = [
      window(
        id: 42,
        title: "Runtime Verification",
        bundleIdentifier: "com.microsoft.powerpoint"
      )
    ]

    let titleResult = RuntimeVerificationWindowSelector.select(
      from: windows,
      target: .titleSubstring("Runtime Verification")
    )
    let identifierResult = RuntimeVerificationWindowSelector.select(
      from: windows,
      target: .windowID(42)
    )

    #expect(titleResult.resolution == .notFound)
    #expect(titleResult.matchedWindowCount == 0)
    #expect(identifierResult.resolution == .notFound)
    #expect(identifierResult.matchedWindowCount == 0)
  }

  @Test func titleAndIDSelectionBothRejectMissingOwnerProcess() {
    let windows = [
      window(
        id: 42,
        title: "Runtime Verification",
        ownerProcessID: 0
      )
    ]

    let titleResult = RuntimeVerificationWindowSelector.select(
      from: windows,
      target: .titleSubstring("Runtime Verification")
    )
    let identifierResult = RuntimeVerificationWindowSelector.select(
      from: windows,
      target: .windowID(42)
    )

    #expect(titleResult.resolution == .notFound)
    #expect(titleResult.matchedWindowCount == 0)
    #expect(identifierResult.resolution == .notFound)
    #expect(identifierResult.matchedWindowCount == 0)
  }

  @Test func titleSelectionRejectsDuplicateWindowIdentifierAcrossOwners() {
    let result = RuntimeVerificationWindowSelector.select(
      from: [
        window(id: 42, title: "Runtime Verification"),
        window(
          id: 42,
          title: "Wrong Owner",
          ownerProcessID: 800,
          bundleIdentifier: "com.apple.Keynote"
        ),
      ],
      target: .titleSubstring("Runtime Verification")
    )

    #expect(result.resolution == .ambiguous)
    #expect(result.matchedWindowCount == 2)
  }

  private func window(
    id: CGWindowID,
    title: String,
    applicationName: String = "Microsoft PowerPoint",
    ownerProcessID: pid_t = 700,
    bundleIdentifier: String = "com.microsoft.Powerpoint"
  ) -> PowerPointWindowDescriptor {
    PowerPointWindowDescriptor(
      id: id,
      title: title,
      applicationName: applicationName,
      ownerProcessID: ownerProcessID,
      bundleIdentifier: bundleIdentifier,
      frame: .zero
    )
  }

  private func identity(
    windowID: CGWindowID,
    ownerProcessID: pid_t = 700
  ) -> PowerPointWindowIdentity {
    guard
      let identity = PowerPointWindowIdentity(
        windowID: windowID,
        ownerProcessID: ownerProcessID,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    else {
      preconditionFailure("The test fixture must have a valid PowerPoint identity.")
    }
    return identity
  }
}
