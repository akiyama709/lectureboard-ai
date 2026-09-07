# 開発ロードマップ

　本書は日付の約束ではなく，検証ゲートを示す．英語版[`ROADMAP.md`](../ROADMAP.md)を正本とし，本書は同じマイルストーンの日本語版とする．

## 完成の定義と現在地

　本プロジェクトの完成は，公開GitHubリポジトリ`akiyama709/lectureboard-ai`において，`LectureBoard-AI-v1.0.0-arm64.zip`，`LectureBoard-AI-v1.0.0-test-results.json`，`SBOM.spdx.json`，`SHA256SUMS`及び`provenance.json`の正確な5件だけを添付した，immutableかつ非prereleaseの正式な`v1.0.0` GitHub Releaseを公開し，認証なしで全5添付assetを再取得して最終検証を終えた時点とする．Release noteは第6 assetではなくRelease本文へ置く．有料又は教育機関名義のApple Developer membershipは使用せず，archiveはad hoc署名とし，Developer ID署名又はApple notarization済みとは表示しない．α版，β版又はRCのapplication Releaseは公開しない．

　現在は公開前の開発基盤であり，application GitHub Releaseはまだ公開していない．実装済み，履歴上の実機証拠及び現行版で未検証の事項は，[`build-verification.md`](build-verification.md)の区別を維持する．

## M0：公開リポジトリ基盤

状態：完了済み．ただし，製品リリース又はプロジェクト完成ではない．

- macOS専用の初期スコープ
- ネイティブアプリの骨格
- プロバイダ非依存のCore設計
- 音声コマンドを要求しない文脈優先設計
- 根拠を保持する板書意図モデル
- 透明オーバーレイ試作
- CI及びオープンソース統治文書

完了条件：ソース，統治文書及び再現可能なローカル検証が公開リポジトリに揃う．

## M1：観察可能な講義プロトタイプ

- 選択したPowerPointウィンドウだけをScreenCaptureKitで連続取得する
- 安定した視覚フレーム及び持続的内容更新を確定する
- 画像差分とは独立したスライド同一性信号を実装する
- Visionで文字及び図形を解析する
- スライドキャンバスを切り出し，PowerPoint UIを除外する
- 文字，図形及び確認済み既存インクから占有領域を作る
- 確定した発話を文脈板書エンジンへ送る
- 文字，囲み，矢印及び因果図を安定描画する
- 講義セッションをJSON及びSVGとして保存する

完了条件：制御資料を用いた10分間の日本語又は英語講義が，既存内容への重なり及び講義妨害なく動作する．

## M2：文脈板書の品質

- `.pptx`の文字，図形及び発表者ノートを取り込む
- 根拠リンク付きAI要約アダプタを追加する
- 不確実な内容を講師へ質問せず保留する
- 氏名，数値，日付，引用及び数式を検証する
- 板書密度及び図表頻度を調整可能にする
- 板書判断の誤表示及び見逃しを評価する

完了条件：代表的な講義群について，独立評価者が大半の板書を有用かつ根拠付きと判断する．

## M3：日本語・英語混在講義

- 短い区間の言語変化を検出する
- 原語の専門用語を保持する
- 重要語を二言語表示できるようにする
- セッション用語集を維持する
- 同意済みの日本語及び英語評価資料を整備する

完了条件：繰り返し手動で言語を切り替えず，日英混在講義が動作する．

## M4：対応範囲の実機受入

- 資料1件，通常の全画面又はwindow表示slide show，display 1台の読取専用visual講義経路を完成する
- 利用者確認式canvas，可視overlay alignment，click-through mouse priority及びpublic-scene exportを検証する
- 正常停止，取消し，許可拒否，window終了及びcapture中断時のcleanupを検証する
- 元PowerPoint fileが不変であることを確認する
- アクセシビリティ評価
- privacy，license，既知の制限，導入，初回講義及びfallback文書を完成する

完了条件：文書化されたfallback手順を備え，対応範囲の講義経路を反復実行できる．この内部検証gate自体は公開又は完成ではない．

## M5：代表条件の検証

- 代表的な日本語及び英語資料を別sessionで反復検証する
- OCR，図形，座標，占有領域及び板書有用性を校正する
- 正確な画面選択，板書開始，取得停止及び対応範囲の復旧経路をPowerPointを自動操作せず反復検証する
- microphone，透明overlay及びmouse input非干渉を検証する
- プライバシー，アクセシビリティ，ライセンス及び第三者表示を確認する
- 利用手順及び既知の制約を公開可能な形で整備する

完了条件：対応Mac上で機能範囲の固定されたbuildを反復利用でき，重要な失敗及び制約がすべて追跡される．この内部検証gateも完成ではない．

## M6：正確なv1.0.0公開候補

- `v1.0.0`の機能範囲及び対応環境を凍結する
- リリースを阻害する不具合を解消し，残る問題を分類する
- 再現可能な配布ビルドを作る
- Hardened Runtime及びad hoc署名を適用し，entitlement allowlistを検証する
- cleanな正確なcommitに対して`evidence`を実行し，private gate log及び凍結`.xcresult`をlocal evidenceとして保持し，内容を含まないJSONだけをpublic assetとする
- App archive，SHA-256 checksum manifest，内容を含まないtest evidence，SBOM及びcommit-bound provenanceを生成する
- 新規の対応MacでGatekeeper，インストール，初回起動，権限及び中核講義経路を確認する
- リリースノート，導入，プライバシー，セキュリティ，トラブル対応及びフォールバック文書を完成させる

完了条件：公開予定と同一の候補成果物が，[`v1-release-checklist.md`](v1-release-checklist.md)の公開前項目をすべて満たす．公開及び公開後gateが完了するまでは，本プロジェクトの完成ではない．

## M7：GitHub正式版v1.0.0

- 公開対象コミットで必須CI及びローカルリリース検証を完了する
- 外部公開操作に対する明示的な最終確認を得る
- 承認済みコミットへ`v1.0.0`タグを付ける
- ad hoc署名済みmacOS App archive，SHA-256 checksum manifest，内容を含まないtest evidence，SBOM及びprovenanceの正確な5添付assetだけを含む，immutableかつnon-draft・non-prereleaseのGitHub Releaseを公開し，リリースノートはRelease本文へ置く
- 認証なしの`verify-public`を実行し，public REST metadata及びannotated-tag refsを保存し，全5 assetの正確な名称，byte一致，commit結合並びにarchive検証を完了する
- 再取得したpublic archiveを用いて，AppleのApp単位の「このまま開く」経路，permission，installation，launch及び対応workflowを再検証する
- 公開URL，metadata，tag-ref及び最終証拠を検証記録へ保存する

完了条件：immutableな公開`v1.0.0` GitHub Releaseを一般利用者が取得でき，再取得した全5 assetが最終検証に合格する．この時点だけを本プロジェクトの完成とする．

## 完成後の探索項目

- Keynote及びPDFプレゼンテーション対応
- 明示的なopt-inによる個人筆記スタイル適応
- 対応言語の追加
- 学生側の任意翻訳板書
- macOS版が十分に安定した後のWindows及びLinux対応
