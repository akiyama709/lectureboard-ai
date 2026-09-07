import CoreGraphics
import Testing

@testable import LectureBoard_AI

struct PowerPointWindowIdentityTests {
  @Test func scanScopeSeparatesVisibleChooserFromCompleteInventory() {
    #expect(PowerPointWindowScanScope.visibleOnly.onScreenWindowsOnly)
    #expect(!PowerPointWindowScanScope.completeInventory.onScreenWindowsOnly)
  }

  @Test func resolvesOneExactWindowIDProcessAndBundleMatch() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [
      candidate(windowID: 41, ownerProcessID: 700),
      candidate(windowID: 42, ownerProcessID: 700),
    ]

    let index = ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
      for: expected,
      among: candidates
    )

    #expect(index == 1)
  }

  @Test func rejectsWrongBundleEvenWhenWindowIDAndProcessMatch() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [
      candidate(
        windowID: 42,
        ownerProcessID: 700,
        bundleIdentifier: "com.microsoft.powerpoint"
      )
    ]

    #expect(
      ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: expected,
        among: candidates
      ) == nil
    )
  }

  @Test func rejectsProcessReplacementAndWindowIDReuse() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [candidate(windowID: 42, ownerProcessID: 701)]

    #expect(
      ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: expected,
        among: candidates
      ) == nil
    )
  }

  @Test func rejectsDuplicateExactIdentities() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [
      candidate(windowID: 42, ownerProcessID: 700),
      candidate(windowID: 42, ownerProcessID: 700),
    ]

    #expect(
      ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: expected,
        among: candidates
      ) == nil
    )
  }

  @Test func rejectsDuplicateWindowIDEvenWhenOnlyOneFullIdentityMatches() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [
      candidate(windowID: 42, ownerProcessID: 700),
      candidate(windowID: 42, ownerProcessID: 701),
    ]

    #expect(
      ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: expected,
        among: candidates
      ) == nil
    )
  }

  @Test func rejectsTargetWindowWithoutAnOwner() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [
      ReenumeratedPowerPointWindowCandidate(
        windowID: 42,
        ownerProcessID: nil,
        bundleIdentifier: nil
      )
    ]

    #expect(
      ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: expected,
        among: candidates
      ) == nil
    )
  }

  @Test func rejectsAListWithoutTheFrozenTarget() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let candidates = [candidate(windowID: 41, ownerProcessID: 700)]

    #expect(
      ReenumeratedPowerPointWindowResolver.uniqueMatchingIndex(
        for: expected,
        among: candidates
      ) == nil
    )
  }

  @Test func identityRequiresANonzeroWindowPositiveProcessAndExactBundle() {
    #expect(
      PowerPointWindowIdentity(
        windowID: 0,
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      ) == nil
    )
    #expect(
      PowerPointWindowIdentity(
        windowID: 42,
        ownerProcessID: 0,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      ) == nil
    )
    #expect(
      PowerPointWindowIdentity(
        windowID: 42,
        ownerProcessID: 700,
        bundleIdentifier: "com.microsoft.powerpoint"
      ) == nil
    )
  }

  @Test func cachedDescriptorResolutionRejectsDuplicateWindowIdentifiers() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let descriptors = [
      descriptor(windowID: 42, ownerProcessID: 700),
      descriptor(
        windowID: 42,
        ownerProcessID: 701,
        bundleIdentifier: "com.apple.Keynote"
      ),
    ]

    #expect(
      PowerPointWindowIdentityResolver.uniqueDescriptor(
        windowID: 42,
        in: descriptors
      ) == nil
    )
    #expect(
      PowerPointWindowIdentityResolver.uniqueDescriptor(
        identity: expected,
        in: descriptors
      ) == nil
    )
  }

  @Test func cachedDescriptorResolutionReturnsOneExactFrozenIdentity() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let exact = descriptor(windowID: 42, ownerProcessID: 700)

    #expect(
      PowerPointWindowIdentityResolver.uniqueDescriptor(
        identity: expected,
        in: [exact]
      ) == exact
    )
  }

  @Test func cachedDescriptorResolutionRejectsFrozenIdentityMismatch() {
    let expected = identity(windowID: 42, ownerProcessID: 700)
    let replacement = descriptor(windowID: 42, ownerProcessID: 701)

    #expect(
      PowerPointWindowIdentityResolver.uniqueDescriptor(
        windowID: 42,
        in: [replacement]
      ) == replacement
    )
    #expect(
      PowerPointWindowIdentityResolver.uniqueDescriptor(
        identity: expected,
        in: [replacement]
      ) == nil
    )
  }

  private func identity(
    windowID: CGWindowID,
    ownerProcessID: pid_t
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

  private func candidate(
    windowID: CGWindowID,
    ownerProcessID: pid_t,
    bundleIdentifier: String = PowerPointWindowIdentity.expectedBundleIdentifier
  ) -> ReenumeratedPowerPointWindowCandidate {
    ReenumeratedPowerPointWindowCandidate(
      windowID: windowID,
      ownerProcessID: ownerProcessID,
      bundleIdentifier: bundleIdentifier
    )
  }

  private func descriptor(
    windowID: CGWindowID,
    ownerProcessID: pid_t,
    bundleIdentifier: String = PowerPointWindowIdentity.expectedBundleIdentifier
  ) -> PowerPointWindowDescriptor {
    PowerPointWindowDescriptor(
      id: windowID,
      title: "Controlled window",
      applicationName: "Display name is not an identity",
      ownerProcessID: ownerProcessID,
      bundleIdentifier: bundleIdentifier,
      frame: .zero
    )
  }
}
