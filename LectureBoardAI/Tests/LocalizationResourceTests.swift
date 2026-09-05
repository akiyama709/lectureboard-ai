import Foundation
import Testing

@Suite("Localization resources")
struct LocalizationResourceTests {
  @Test("English and Japanese localization files contain required status text")
  func localizationFilesContainRequiredStatusText() throws {
    let expectedStrings = [
      "en": [
        "app.title": "LectureBoard AI",
        "status.supportedWorkflow":
          "Supported workflow: one PowerPoint presentation, a windowed slide show, one display, and one lecture language. Confirm the visible slide area before starting transcription.",
        "capture.diagnostic.explanation":
          "Diagnostic mode does not start or semantically bind a slide show, so it cannot display production board output.",
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
        "capture.slideCanvas.needsConfirmation":
          "Slide area has not been confirmed; visual analysis is paused",
        "capture.slideCanvas.confirmed":
          "User-confirmed slide area is active",
        "capture.slideCanvas.invalidated":
          "Window geometry changed; confirm the slide area again",
        "capture.slideCanvas.confirm": "Confirm slide area",
        "error.onDeviceRecognitionUnavailable":
          "On-device speech recognition is unavailable for the selected language. Transcription did not start because audio must not be sent off this Mac.",
      ],
      "ja": [
        "app.title": "LectureBoard AI",
        "status.supportedWorkflow":
          "対応する利用方法：PowerPoint資料1件，ウィンドウ表示のスライドショー，ディスプレイ1台，講義言語1種類．文字起こしを始める前に，表示中のスライド面を確定してください．",
        "capture.diagnostic.explanation":
          "診断モードはスライドショーを開始せず，意味的にも結び付けないため，本番用の板書を表示できません．",
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
        "capture.slideCanvas.needsConfirmation":
          "スライド面が未確認のため，視覚解析を停止しています",
        "capture.slideCanvas.confirmed":
          "利用者が確認したスライド面を使用しています",
        "capture.slideCanvas.invalidated":
          "ウィンドウ寸法が変わったため，スライド面を再確認してください",
        "capture.slideCanvas.confirm": "スライド面を確定",
        "error.onDeviceRecognitionUnavailable":
          "選択した言語の端末内音声認識を現在利用できません．音声を外部へ送信しないため，文字起こしを開始しません．",
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
