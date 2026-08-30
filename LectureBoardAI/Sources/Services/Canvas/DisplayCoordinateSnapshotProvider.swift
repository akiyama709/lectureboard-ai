import AppKit
import CoreGraphics

@MainActor
protocol DisplayCoordinateSnapshotProviding {
  func currentSnapshots() -> [DisplayCoordinateSnapshot]
}

@MainActor
struct SystemDisplayCoordinateSnapshotProvider: DisplayCoordinateSnapshotProviding {
  func currentSnapshots() -> [DisplayCoordinateSnapshot] {
    NSScreen.screens.compactMap { screen in
      guard
        let screenNumber = screen.deviceDescription[
          NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
      else {
        return nil
      }

      let displayID = CGDirectDisplayID(screenNumber.uint32Value)
      return DisplayCoordinateSnapshot(
        displayID: displayID,
        quartzGlobalFrame: CGDisplayBounds(displayID),
        appKitFrame: screen.frame
      )
    }
  }
}
