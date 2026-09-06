# LectureBoard AI v1.0.0 利用案内

> 状態：手順案．正確な公開候補及び公開後の再取得物について[`build-verification.md`](build-verification.md)に証拠が記録されるまで，`v1.0.0`で動作確認済みとは扱わない．

## 導入前の確認

　[`supported-environment.md`](supported-environment.md)に定めた狭い構成だけを使用する．Apple silicon Mac，local display 1台，PowerPoint資料1件，既存slide showなし，PowerPointのwindow表示slide show及びsessionごとに日本語又は英語1言語である．

　無償配布AppはHardened Runtimeを有効にしてad hoc署名するが，Developer ID署名又はApple notarizationは行わない．そのため，Appleは公開者の識別又はnotarizationによる安全確認を行えない．`LectureBoard-AI-v1.0.0-arm64.zip`，`LectureBoard-AI-v1.0.0-test-results.json`，`SBOM.spdx.json`，`SHA256SUMS`及び`provenance.json`の正確な5件だけを，本projectのpublic・immutable・non-prereleaseな`v1.0.0` GitHub Releaseから取得する．5件を同じdirectoryへ置き，そのdirectoryへ移動してから，ZIPを開く前に次を実行する．

```bash
cd -- "/absolute/path/to/downloaded-release-assets"
/usr/bin/shasum -a 256 -c SHA256SUMS
```

　ZIP，test evidence，SBOM及びprovenanceの4件すべてに`OK`と表示されなければ，Appを開かず停止する．

## Installと初回起動

1. 検証済みZIPをFinderでダブルクリックし，download quarantineを保持したまま展開する．`LectureBoard AI.app`を改名せず`/Applications`へ移す．release verifierは汎用`unzip`との互換性も確認するが，Gatekeeper受入ではFinderを用いる．
2. FinderからAppを1回開く．Appleへ登録・notarizeされていないため，macOSが初回起動を止めることを想定する．
3. Apple公式の[開発元が不明なMacアプリを開く](https://support.apple.com/ja-jp/guide/mac-help/mh40616/mac)に従い，「システム設定」→「プライバシーとセキュリティ」で当該Appだけの「このまま開く」を選び，認証して開く．
4. Gatekeeper全体を無効化せず，Terminalでquarantine metadataを除去しない．

　確認中は，この正確なAppを同じpathに保つ．同じ名称・bundle identifierでも，別buildはad hoc code identityが異なるため，macOSでは別Appとして扱われ得る．

## 権限

- **画面収録とシステムオーディオ録音**：選択したPowerPoint windowを取得するため画面accessが必要である．system audioは要求しない．Apple公式の[画面収録access設定](https://support.apple.com/ja-jp/guide/mac-help/mchld6aa7d23/mac)で正確なAppを確認する．
- **Automation → Microsoft PowerPoint**：managed開始が新しいPowerPoint slide-show objectを作成・読取するため，初回に明示許可する．既存slide showは採用しない．
- **マイク及び音声認識**：文字起こし開始時だけ要求する．Apple Speechは端末内認識を必須とし，選択言語で利用できなければnetwork fallbackを使わず停止する．認識は最大8秒のcycleで更新し，区間確定にさらに最大4秒かかり得る．この時間境界には決定論的testがあるが，正確なrelease候補による実microphone動作は受入確認まで未検証である．
- **アクセシビリティ及びフルディスクアクセス**：対応手順では不要である．正式版が要求した場合は，許可せず不具合として報告する．

　App内で画面収録が許可済みなら，再要求しない．未許可の場合だけ1回要求し，システム設定で正確な導入済みAppを有効にしてから，そのAppを終了し同じpathから開き直す．再起動後も未許可なら，要求を繰り返さず停止する．

## PowerPointの準備

1. 他のpresentation及び実行中のslide showを閉じる．
2. 通常のediting windowで資料1件だけを開く．
3. PowerPointの「スライドショー」→「スライドショーの設定」で，show typeを「出席者として閲覧する（ウィンドウ表示）」にする．英語UIでは「Browsed by an individual (window)」である．Microsoft公式の[window表示手順](https://support.microsoft.com/en-US/PowerPoint/training/create-a-self-running-presentation)も参照する．
4. 初回又は公開前確認では，元PPTXを閉じ，local複製物だけを使用する．[`user-acceptance-ja.md`](user-acceptance-ja.md)の実施前後integrity確認に従う．

　LectureBoard AIはpresentationを編集又は保存しない設計であるが，正確な候補におけるPPTX不変性は公開gateとして未検証である．初回確認では必ず複製物を用いる．

## 講義開始

1. LectureBoard AIを開き，sessionの言語として日本語又は英語を選ぶ．
2. 画面収録が許可済みであることを確認し，「PowerPointウィンドウを再検出」を選ぶ．
3. 正確なPowerPoint editing windowを1件選ぶ．
4. 「管理されたスライドショーを開始」を1回選ぶ．初回はPowerPoint Automation許可が表示され得る．
5. 新しいwindow表示slide showと取得状態を待つ．PowerPointが返したobjectを1件の正確な取得windowへ結び付けられない場合，Appは続行せず停止しなければならない．
6. frozen preview上でPowerPoint操作部と周囲UIを除外し，表示中slideだけを囲んでスライド面を確定する．
7. 現在のslide identity，新しいframe及びvisual analysisが準備済みとなってから，文字起こしを開始する．

　実行時診断は，アプリ状態と文字起こし状態を別々に表示する．「現在のスライド文脈を待機中」は，正確なidentity，canvas，新しいframe及びcurrent解析が揃うまで出力を意図的に閉じている状態である．「描画要求済み」はrendererを呼び出したことだけを示すため，板書がPowerPoint上に実際に見えることを講師が確認する．本番板書件数にデモ内容は含まれない．

　講義中はPowerPointを通常どおり操作する．mouse又はpenによる人間入力が常に優先される．「板書を隠す」はAI出力を直ちに隠す．slide identity，canvas，current analysis，focus又はwindow geometryが不確実になれば，overlayは推測せず非表示になることを想定する．

## 停止とexport

1. 文字起こしを停止し，続いて取得を停止する．
2. managed slide showが閉じ，PowerPoint editing windowが残ることを確認する．
3. 取得停止後に「セッションを書き出す」を選ぶ．JSON filenameを指定すると，同じbasenameのSVGも隣に作成される．
4. 両fileを講義dataとして扱う．confirmed又はpinnedのpublic board sceneと派生板書文を含み得るが，source slide画像，raw audio，全文文字起こし，OCR source text，window title，capture identifier及び非公開intentは含めない設計である．
5. PowerPoint複製物を保存せず閉じ，公開候補確認ではfile integrityを照合する．

## Troubleshootingと安全なfallback

- **画面収録要求が反復する**：正確な導入済み候補だけを使用しているか確認し，同じAppを1回終了・再起動する．複数のDerivedData buildを許可せず，要求buttonを繰り返し押さない．
- **PowerPoint windowが出ない**：画面収録許可，表示中の通常editing window 1件及び既存slide showなしを確認し，1回更新する．
- **managed開始が失敗する**：対応PowerPoint versionとwindow表示show typeを確認する．full screen，Presenter View又はkiosk modeへ変更して回避しない．
- **端末内音声認識を利用できない**：文字起こしなしで続行するかsessionを停止する．Appは意図的にnetwork fallbackを持たない．
- **overlayが消える**：PowerPointを前面へ戻し，windowを移動・resizeせず，再選択を求められた場合だけslide面を確定し直す．非表示が安全状態である．
- **exportが無効**：取得を停止し，public board sceneが1件以上生成されたか確認する．
- **crash，誤window，根拠のない内容，入力妨害又はfile変更**：Appの利用を停止する．privacy確認前にslide，画像，音声，文字起こし又はexportをissueへ添付しない．

　安全境界をすぐ復旧できない場合，LectureBoard AIを停止し，PowerPointだけで講義を継続する．

## 更新，削除及びsupport

　更新時は，新しいReleaseを別途取得・checksum検証する．新しいAppの初回起動確認が終わるまで旧Appを残し，実行中Appを上書きしない．ad hoc code identityが変わるため，新版ではApp単位の権限を再設定する場合がある．

　削除時は，文字起こしと取得を停止してLectureBoard AIを終了し，`LectureBoard AI.app`だけをゴミ箱へ移す．必要ならmacOSの「プライバシーとセキュリティ」から該当権限を外す．別途保存したsession exportは自動削除されない．

　通常の不具合はGitHub Issuesへ報告できるが，非公開slide，screenshot，音声，文字起こし，export，credential又はlocal absolute pathを添付しない．security又はprivacy脆弱性は[`SECURITY.md`](../SECURITY.md)に従う．keyboard-only操作，VoiceOver，physical pen tablet，複数display，full-screen mode，日英混在認識及びonline meeting compositionは，後続release文書が明記しない限り`v1.0.0`で未検証である．
