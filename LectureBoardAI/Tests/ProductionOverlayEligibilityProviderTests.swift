import CoreGraphics
import Foundation
import Testing

@testable import LectureBoard_AI

struct ProductionOverlayEligibilityProviderTests {
  private let selectedBounds = CGRect(x: 100, y: 200, width: 640, height: 360)

  @Test func acceptsOnlyExactFrontmostOnScreenLayerZeroWindow() throws {
    let identity = try #require(makeIdentity())
    let screen = try #require(CaptureScreenGeometry(screenRect: selectedBounds))
    let window = try #require(makeWindow())

    #expect(
      ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
        identity: identity,
        screenGeometry: screen,
        frontmostProcessID: 700,
        frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        windows: [window]
      )
    )
  }

  @Test func rejectsNonFrontmostOrWrongBundleApplication() throws {
    let identity = try #require(makeIdentity())
    let screen = try #require(CaptureScreenGeometry(screenRect: selectedBounds))
    let window = try #require(makeWindow())

    #expect(
      !ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
        identity: identity,
        screenGeometry: screen,
        frontmostProcessID: 701,
        frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        windows: [window]
      )
    )
    #expect(
      !ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
        identity: identity,
        screenGeometry: screen,
        frontmostProcessID: 700,
        frontmostBundleIdentifier: "com.example.NotPowerPoint",
        windows: [window]
      )
    )
  }

  @Test func rejectsMissingDuplicateWrongOwnerLayerOrOffscreenExactWindow() throws {
    let identity = try #require(makeIdentity())
    let screen = try #require(CaptureScreenGeometry(screenRect: selectedBounds))
    let exact = try #require(makeWindow())
    let wrongOwner = try #require(makeWindow(ownerProcessID: 701))
    let wrongLayer = try #require(makeWindow(layer: 1))
    let offscreen = try #require(makeWindow(isOnScreen: false))

    for windows in [[], [exact, exact], [wrongOwner], [wrongLayer], [offscreen]] {
      #expect(
        !ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
          identity: identity,
          screenGeometry: screen,
          frontmostProcessID: 700,
          frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
          windows: windows
        )
      )
    }
  }

  @Test func rejectsScreenRectThatDoesNotMatchExactWindowBounds() throws {
    let identity = try #require(makeIdentity())
    let shiftedScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 103, y: 200, width: 640, height: 360)
      )
    )
    let shrunkScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 120, y: 220, width: 600, height: 320)
      )
    )
    let window = try #require(makeWindow())

    for screen in [shiftedScreen, shrunkScreen] {
      #expect(
        !ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
          identity: identity,
          screenGeometry: screen,
          frontmostProcessID: 700,
          frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
          windows: [window]
        )
      )
    }
  }

  @Test func acceptsTwoPointCoordinateRoundingAtTheBoundary() throws {
    let identity = try #require(makeIdentity())
    let roundedScreen = try #require(
      CaptureScreenGeometry(
        screenRect: CGRect(x: 102, y: 198, width: 636, height: 364)
      )
    )
    let window = try #require(makeWindow())

    #expect(
      ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
        identity: identity,
        screenGeometry: roundedScreen,
        frontmostProcessID: 700,
        frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        windows: [window]
      )
    )
  }

  @Test func rejectsIntersectingWindowAheadOfSelectedWindowRegardlessOfLayer() throws {
    let identity = try #require(makeIdentity())
    let screen = try #require(CaptureScreenGeometry(screenRect: selectedBounds))
    let selected = try #require(makeWindow())
    let sameProcessDialog = try #require(
      makeWindow(
        windowID: 43,
        bounds: CGRect(x: 200, y: 250, width: 240, height: 120)
      )
    )
    let sameProcessFloatingDialog = try #require(
      makeWindow(
        windowID: 46,
        layer: 1,
        bounds: CGRect(x: 200, y: 250, width: 240, height: 120)
      )
    )
    let otherApplicationWindow = try #require(
      makeWindow(
        windowID: 44,
        ownerProcessID: 900,
        bounds: CGRect(x: 300, y: 300, width: 200, height: 100)
      )
    )
    let nonoverlappingFrontWindow = try #require(
      makeWindow(
        windowID: 45,
        ownerProcessID: 900,
        bounds: CGRect(x: 900, y: 200, width: 200, height: 100)
      )
    )

    for frontWindow in [
      sameProcessDialog, sameProcessFloatingDialog, otherApplicationWindow,
    ] {
      #expect(
        !ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
          identity: identity,
          screenGeometry: screen,
          frontmostProcessID: 700,
          frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
          windows: [frontWindow, selected]
        )
      )
    }
    #expect(
      ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
        identity: identity,
        screenGeometry: screen,
        frontmostProcessID: 700,
        frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        windows: [nonoverlappingFrontWindow, selected]
      )
    )
    #expect(
      ProductionOverlayEligibilityPolicy.allowsProductionOverlay(
        identity: identity,
        screenGeometry: screen,
        frontmostProcessID: 700,
        frontmostBundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        windows: [selected, sameProcessDialog]
      )
    )
  }

  @Test func windowListParserKeepsOptionalOnScreenKeyAbsenceAndPreservesOrder() throws {
    let frontBounds = CGRect(x: 200, y: 250, width: 240, height: 120)
    let parsed = try #require(
      ProductionOverlayWindowListParser.parse(
        [
          windowInfo(windowID: 43, ownerProcessID: 700, layer: 1, bounds: frontBounds),
          windowInfo(
            windowID: 42,
            ownerProcessID: 700,
            layer: 0,
            bounds: selectedBounds,
            isOnScreen: true
          ),
        ],
        excludingOwnerProcessID: 999
      )
    )

    #expect(parsed.map(\.windowID) == [43, 42])
    let allAreOnScreen = parsed.allSatisfy { $0.isOnScreen }
    #expect(allAreOnScreen)
  }

  @Test func windowListParserFailsWholeSnapshotForMalformedNonSelfWindow() {
    var malformedOccluder = windowInfo(
      windowID: 43,
      ownerProcessID: 700,
      layer: 1,
      bounds: CGRect(x: 200, y: 250, width: 240, height: 120)
    )
    malformedOccluder.removeValue(forKey: kCGWindowBounds as String)

    #expect(
      ProductionOverlayWindowListParser.parse(
        [malformedOccluder, windowInfo()],
        excludingOwnerProcessID: 999
      ) == nil
    )

    var malformedOnScreen = windowInfo()
    malformedOnScreen[kCGWindowIsOnscreen as String] = NSNumber(value: 1)
    #expect(
      ProductionOverlayWindowListParser.parse(
        [malformedOnScreen],
        excludingOwnerProcessID: 999
      ) == nil
    )
  }

  @Test func windowListParserExcludesCurrentProcessOverlayBeforePolicyEvaluation() throws {
    let parsed = try #require(
      ProductionOverlayWindowListParser.parse(
        [
          windowInfo(
            windowID: 99,
            ownerProcessID: 555,
            layer: 10,
            bounds: selectedBounds
          ),
          windowInfo(),
        ],
        excludingOwnerProcessID: 555
      )
    )

    #expect(parsed.map(\.windowID) == [42])
  }

  @Test func rejectsInvalidWindowSnapshotGeometry() {
    #expect(
      ProductionOverlayWindowSnapshot(
        windowID: 42,
        ownerProcessID: 700,
        layer: 0,
        isOnScreen: true,
        bounds: CGRect(x: 0, y: 0, width: -1, height: 100)
      ) == nil
    )
    #expect(
      ProductionOverlayWindowSnapshot(
        windowID: 42,
        ownerProcessID: 700,
        layer: 0,
        isOnScreen: true,
        bounds: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)
      ) == nil
    )
  }

  private func makeIdentity() -> PowerPointWindowIdentity? {
    PowerPointWindowIdentity(
      windowID: 42,
      ownerProcessID: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }

  private func makeWindow(
    windowID: CGWindowID = 42,
    ownerProcessID: pid_t = 700,
    layer: Int = 0,
    isOnScreen: Bool = true,
    bounds: CGRect? = nil
  ) -> ProductionOverlayWindowSnapshot? {
    ProductionOverlayWindowSnapshot(
      windowID: windowID,
      ownerProcessID: ownerProcessID,
      layer: layer,
      isOnScreen: isOnScreen,
      bounds: bounds ?? selectedBounds
    )
  }

  private func windowInfo(
    windowID: CGWindowID = 42,
    ownerProcessID: pid_t = 700,
    layer: Int = 0,
    bounds: CGRect? = nil,
    isOnScreen: Bool? = nil
  ) -> [String: Any] {
    var info: [String: Any] = [
      kCGWindowNumber as String: NSNumber(value: windowID),
      kCGWindowOwnerPID as String: NSNumber(value: ownerProcessID),
      kCGWindowLayer as String: NSNumber(value: layer),
      kCGWindowBounds as String: (bounds ?? selectedBounds).dictionaryRepresentation,
    ]
    if let isOnScreen {
      info[kCGWindowIsOnscreen as String] = NSNumber(value: isOnScreen)
    }
    return info
  }
}
