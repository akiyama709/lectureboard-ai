import Foundation
import Testing

@Suite("Localization resources")
struct LocalizationResourceTests {
  @Test("English and Japanese localization files contain required status text")
  func localizationFilesContainRequiredStatusText() throws {
    let expectedStrings = [
      "en": [
        "app.title": "LectureBoard AI",
        "capture.slideIdentity.unavailable":
          "Independent slide identity is unavailable",
        "capture.slideIdentity.establishing":
          "Stabilizing independent slide-identity signal",
        "capture.slideIdentity.identified":
          "Independent slide-identity signal is stable",
        "capture.slideIdentity.interrupted":
          "Slide-identity continuity was interrupted",
        "capture.slideIdentityFrameSync.waiting":
          "Waiting for a fresh frame after the slide-identity boundary",
        "capture.slideIdentityFrameSync.synchronized":
          "Fresh post-identity frame accepted",
        "capture.slideIdentityFrameSync.timedOut":
          "Fresh-frame wait timed out; analysis remains paused",
      ],
      "ja": [
        "app.title": "LectureBoard AI",
        "capture.slideIdentity.unavailable":
          "独立したスライド識別は利用できません",
        "capture.slideIdentity.establishing":
          "独立したスライド識別信号を安定化しています",
        "capture.slideIdentity.identified":
          "独立したスライド識別信号が安定しました",
        "capture.slideIdentity.interrupted":
          "スライド識別の連続性が中断しました",
        "capture.slideIdentityFrameSync.waiting":
          "スライド識別境界後の新しいフレームを待っています",
        "capture.slideIdentityFrameSync.synchronized":
          "識別境界後の新しいフレームを受理しました",
        "capture.slideIdentityFrameSync.timedOut":
          "新しいフレームの待機が時間切れになり，解析を停止しています",
      ],
    ]

    for (localization, expectedLocalizationStrings) in expectedStrings {
      let localizationURL = try #require(
        Bundle.main.url(forResource: localization, withExtension: "lproj")
      )
      let localizationBundle = try #require(Bundle(url: localizationURL))
      let stringsURL = try #require(
        localizationBundle.url(forResource: "Localizable", withExtension: "strings")
      )
      let stringsData = try Data(contentsOf: stringsURL)
      let strings = try #require(
        PropertyListSerialization.propertyList(from: stringsData, format: nil)
          as? [String: String]
      )

      for (key, expectedValue) in expectedLocalizationStrings {
        #expect(strings[key] == expectedValue)
      }
    }
  }
}
