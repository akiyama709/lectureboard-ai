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
        "diagnostics.title": "Runtime diagnostics",
        "diagnostics.lifecycle": "Application / transcription",
        "diagnostics.applicationLifecycle": "Application",
        "diagnostics.transcriptionLifecycle": "Transcription",
        "diagnostics.lifecycle.ready": "Ready",
        "diagnostics.lifecycle.scanning": "Scanning PowerPoint",
        "diagnostics.lifecycle.listening": "Transcribing",
        "diagnostics.lifecycle.finalizing": "Finalizing the current segment",
        "diagnostics.lifecycle.demoOverlay": "Demo overlay (not production)",
        "diagnostics.transcription.idle": "Idle",
        "diagnostics.transcription.starting": "Starting",
        "diagnostics.transcription.waitingForContext":
          "Waiting for current slide context",
        "diagnostics.transcription.listening": "Listening",
        "diagnostics.transcription.finalizing": "Finalizing the current segment",
        "diagnostics.transcriptPhase": "Transcript segment",
        "diagnostics.transcript.empty": "No transcript",
        "diagnostics.transcript.partial": "Partial",
        "diagnostics.transcript.final": "Final",
        "diagnostics.overlayMapping": "Board coordinates",
        "diagnostics.mapping.unavailable": "Unavailable",
        "diagnostics.mapping.mapped": "Mapped",
        "diagnostics.mapping.rejected": "Rejected",
        "diagnostics.overlayEligibility": "Production safety check",
        "diagnostics.eligibility.notEvaluated": "Not evaluated",
        "diagnostics.eligibility.allowed": "Allowed",
        "diagnostics.eligibility.blocked": "Blocked",
        "diagnostics.overlayPresentation": "Production board request",
        "diagnostics.presentation.hidden": "Hidden",
        "diagnostics.presentation.renderRequested": "Render requested",
        "diagnostics.publicBoardElements": "Confirmed production board elements",
        "diagnostics.renderRequestedDisclaimer":
          "The count excludes demo content and includes only confirmed or pinned production elements. Render requested only means that LectureBoard AI invoked the renderer; confirm that the board is actually visible over PowerPoint.",
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
        "error.recognitionInterrupted":
          "On-device speech recognition stopped unexpectedly. Transcription was stopped.",
        "error.recognitionFinalizationTimedOut":
          "On-device speech recognition did not finish the current segment in time. Transcription was stopped.",
        "error.rapidRestartLimitReached":
          "On-device speech recognition ended repeatedly before it could become stable. Transcription was stopped to prevent a restart loop.",
        "error.managedStartFailed":
          "Managed PowerPoint startup failed. Automatic cleanup could not be confirmed. If a slide show is still open, close it manually before trying again.",
      ],
      "ja": [
        "app.title": "LectureBoard AI",
        "status.supportedWorkflow":
          "対応する利用方法：PowerPoint資料1件，ウィンドウ表示のスライドショー，ディスプレイ1台，講義言語1種類．文字起こしを始める前に，表示中のスライド面を確定してください．",
        "diagnostics.title": "実行時診断",
        "diagnostics.lifecycle": "アプリ／文字起こし",
        "diagnostics.applicationLifecycle": "アプリ",
        "diagnostics.transcriptionLifecycle": "文字起こし",
        "diagnostics.lifecycle.ready": "準備完了",
        "diagnostics.lifecycle.scanning": "PowerPointを検出中",
        "diagnostics.lifecycle.listening": "文字起こし中",
        "diagnostics.lifecycle.finalizing": "現在の区間を確定中",
        "diagnostics.lifecycle.demoOverlay": "デモ表示中（本番表示ではありません）",
        "diagnostics.transcription.idle": "停止中",
        "diagnostics.transcription.starting": "開始中",
        "diagnostics.transcription.waitingForContext": "現在のスライド文脈を待機中",
        "diagnostics.transcription.listening": "認識中",
        "diagnostics.transcription.finalizing": "現在の区間を確定中",
        "diagnostics.transcriptPhase": "認識区間",
        "diagnostics.transcript.empty": "文字起こしなし",
        "diagnostics.transcript.partial": "暫定",
        "diagnostics.transcript.final": "確定",
        "diagnostics.overlayMapping": "板書座標",
        "diagnostics.mapping.unavailable": "利用不可",
        "diagnostics.mapping.mapped": "座標変換済み",
        "diagnostics.mapping.rejected": "座標変換を拒否",
        "diagnostics.overlayEligibility": "本番表示の安全確認",
        "diagnostics.eligibility.notEvaluated": "未評価",
        "diagnostics.eligibility.allowed": "許可",
        "diagnostics.eligibility.blocked": "遮断",
        "diagnostics.overlayPresentation": "本番板書の要求",
        "diagnostics.presentation.hidden": "非表示",
        "diagnostics.presentation.renderRequested": "描画要求済み",
        "diagnostics.publicBoardElements": "本番で確定済みの板書要素",
        "diagnostics.renderRequestedDisclaimer":
          "件数はデモを除き，本番用に確定又は固定された要素だけを示します．「描画要求済み」は描画処理を呼び出したことだけを示すため，PowerPoint上に板書が実際に見えるかは目視で確認してください．",
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
        "error.recognitionInterrupted":
          "端末内音声認識が予期せず終了したため，文字起こしを停止しました．",
        "error.recognitionFinalizationTimedOut":
          "端末内音声認識が現在の区間を時間内に確定できなかったため，文字起こしを停止しました．",
        "error.rapidRestartLimitReached":
          "端末内音声認識が安定する前に繰り返し終了しました．再開ループを防ぐため，文字起こしを停止しました．",
        "error.managedStartFailed":
          "PowerPointスライドショーの管理開始に失敗しました．自動的な後始末の完了は確認できません．スライドショーが開いたままの場合は，手動で閉じてから再試行してください．",
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
