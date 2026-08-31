# LectureBoard AI ローカル開発引継ぎ

更新日：2026年8月31日

## 1．この文書の目的

　本書は，iPhone上のChatGPT会話で設計・作成したLectureBoard AIを，macOS上のローカルCodex環境で継続開発するための引継ぎ文書である．通常のChatGPT会話履歴とCodexのローカル開発履歴は別系統であるため，重要な合意事項をリポジトリ内に固定する．

## 2．ユーザーの要望

　LectureBoard AIは，PowerPointを用いた対面・オンライン講義中に，講師の発話と現在のスライドを理解し，スライドの空いた領域へ文字や簡単な図形を自動板書するmacOSアプリである．

　講師は通常，ペンタブでPowerPointの余白へ追記している．本アプリはその作業を自動化するが，講師自身の手書きを妨げてはならない．

　特に重要な要件は次のとおりである．

- 「ここを板書してください」などの音声コマンドを必要としない．
- 現在のスライド，発表者ノート，直前までの発話，反復，定義，対比，因果関係，既存板書等から重要性を文脈的に判断する．
- 判断に迷う場合は講師に質問せず，内部で保留し，後続の説明を待つ．
- 学生には未確定の下書きを見せない．
- 一度確定した板書は原則として動かさない．
- 文字だけでなく，囲み，矢印，因果図，比較図，階層図，簡単な概念図を扱う．
- 標準は「整ったデジタルインク風」とする．
- 「より手書き風」も選択でき，文字サイズ，線幅，揺れ，図形の整い具合，描画速度等を調整できるようにする．
- 日本語，英語，および日英混在講義へ段階的に対応する．
- 当面はmacOS版の完成度を優先し，Windows・Linux版は実装しない．
- 公開GitHubリポジトリは`akiyama709/lectureboard-ai`である．
- 本プロジェクトの「完成」は，検証済みで署名・notarization済みのインストール可能なmacOS配布物を伴う，公開`v1.0.0` GitHub Releaseの成立を指す．公開リポジトリ作成，ソース公開，α版，β版及びRelease Candidateは中間段階であり，完成とは呼ばない．

## 3．現時点の成果物

　リポジトリには，macOSアプリの骨格，透明オーバーレイの試作，PowerPointウィンドウ検出，選択ウィンドウの連続取得実装，利用者確認式のスライド面切出し，現在frameの画面位置に基づくfail-closedなoverlay座標変換，切出し後の安定フレーム・視覚更新判定，160×90のRGB指紋による持続的内容更新判定，安定した視覚フレームを対象とするVision文字・矩形解析，長辺640ピクセル以下のRGBラスタと筆跡候補解析，正規化占有領域の構築，Apple Speechによる一言語文字起こし，文脈判断コア，ベクトル板書モデル，空白配置試作，単体テスト，英語・日本語を同一ファイルに収録したREADME，設計文書，GitHub Actions，公開前検査が含まれる．

　2026年8月31日現在，schema 9対応後の中核Swift packageは119テスト・15 suite，関連するネイティブmacOS Appはidle surface対象test 57件・2 suite及び完全test 217件・25 suiteがMac上で通過している．完全testのresult bundleは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_16-17-38-+0900.xcresult`である．runtime-launch script，shell構文検査，Swift-format lint及び全14段階の`make verify`も合格した．schema 8固定版を保持したまま，修正後schema 9 Appを別名で固定し，strict署名及びpermission requestなしの固定path preflightを確認した．ただし，macOS sessionがlock中だったため，修正後のlive capture及びidle回復は未検証である．取得開始・停止・error・一覧更新・選択変更，frame順序，視覚更新，解析取消し及び古い解析結果の排除は，制御可能なfakeとnative画像fixtureによる回帰testで固定している．選択したPowerPoint窓については，ScreenCaptureKit窓ID，所有PID及び完全一致bundle identifierを取得開始まで固定し，重複，再利用又は所有者変更時にfail-closedで停止する．Coreには，同じpresentation session token及びslide IDが2回連続したときだけ基準又は切替を確定し，中断をまたいだ切替を推定しないtrackerがある．Appは，provider観測の対象，capture session及び順序を検査する．候補確定中に届いたframeは取得件数へ計上した後に視覚解析から除外する．基準確立又は切替時には以前の解析及び板書sceneを破棄し，Appが識別観測を受理したlocal mach絶対時刻よりScreenCaptureKitの`displayTime`が厳密に後である`.new` frameが到着するまで解析を再開しない．Apple Speechの確定結果についても，識別境界以前又は境界後frameをAppが受理したlocal時刻以前に生成された結果を，MainActorでの処理順にかかわらず板書候補から除外する．識別境界後のframe gateは，`waiting`，`synchronized`及び`timedOut`を明示する．時間切れはgateを開かず，古い境界又は停止済みsessionの遅延timeoutはtokenで拒否し，後着の厳密に新しい`.new` frameだけが時間切れ状態から回復できる．この挙動は決定論的testで確認済みであるが，production identity providerを伴う実行時挙動は未検証である．

　公開macOS及びPowerPoint APIは，PowerPoint内部で描画される正確なスライド面矩形を公開しない．ScreenCaptureKitの`contentRect`は取得surfaceを表し，PowerPoint内部のslide subviewを表さない．このため，Appは正確な取得operationから得たwindow previewを固定し，利用者が表示中のスライド面だけをdragで囲んで明示的に確定する．切出しはsource上で幅32 pixel，高さ24 pixel及び面積1,024平方pixelを全て満たさなければならない．確定結果はcapture operation，正確なScreenCaptureKit window ID，source pixel寸法及び検証済みScreenCaptureKit surface geometryへ固定する．再取得，window不一致，pixel寸法不一致，下記の限定idle policy適用後も利用可能なsurface geometryがない場合，又は`contentRect`，scale factor若しくはcontent scaleの変更時には，確定結果，解析及び板書sceneを無効化する．idle surfaceの扱いはApple保証ではなく，live attachment観測前の暫定application policyである．検証済み`.idle`で`contentRect`，`scaleFactor`及び`contentScale`の3 keyが全て欠落する場合だけ，直前にlatchしたsurface geometryを不変visual payloadの切出しへ再利用する．3 keyが全て揃う場合は，直前geometryとの完全一致をcurrent geometryとして受理する．一部欠落，不正形式，矛盾，non-idle，直前geometry欠落，又は直前output寸法とpayload寸法の不一致はfail closedとし，後続の`.new` frameまでrepeat geometryのpoisonをlatchする．3 key全欠落branchでは`screenRect`を継承も利用もせず，overlay mappingを閉じる．修正前schema 9 reportは限定された失敗classを確認したが，修正後のlive回復及び実attachment形状は未検証である．

　画面上の現在位置は，surface geometryと混同せず，frameごとのScreenCaptureKit `screenRect`から別の値として取得する．attachment内の矩形は`CGRect`，矩形型の`NSValue`及びdictionary representationを受理し，有限で正の幅・高さを要求する．複数displayでは負のglobal originも正当な値として受理する．surface 3 key全欠落branch以外のidle repeatでも直前frameの画面位置を継承せず，そのidle sample自身の`screenRect`だけを用いる．3 key全欠落branchは，そのsampleに`screenRect`があっても画面位置を空にする．現在位置が欠落又は不正である場合，確認済みcanvas及び視覚解析を直ちに破棄するのではなく，overlayだけを非表示にし，後続の有効なcurrent frameで再計算する．このcurrent-frame境界は合成attachmentでtest済みであるが，実ScreenCaptureKitの`screenRect`向き，単位及びidle時の提供挙動は未検証である．

　確認済みcanvasからoverlay表示矩形への変換は，capture operation，正確なwindow ID，完全一致するsurface geometry，出力pixel寸法及びcurrent frame sequenceへ固定する．canvasのpixel矩形が`contentRect`の範囲内にあることを確認し，`scaleFactor`及び`contentScale`を用いてcurrent `screenRect`へ対応付ける．丸め誤差として認めるのは出力1 pixel以内に限る．続いて，`CGDisplayBounds`のQuartz global座標から`NSScreen.frame`のAppKit座標へ変換し，対象矩形を完全に含む検証済みdisplayが正確に1件である場合だけ，click-through panelをその矩形へ表示する．production表示には，意味的slide identityとcurrent visual grounding，frontmostの正確なPowerPoint PID・bundle，1件だけのon-screen layer 0 exact window，current `screenRect`との各辺2 point以内の一致及び手前の重複window不在も要求する．証拠の欠落，古いoperation・window・frame，surface又は出力寸法の不一致，display境界の横断若しくは複数displayへの曖昧な包含，明示的非表示，focus・Space変更又はcapture cadenceから独立したlease失効ではfail-closedで非表示にする．板書sceneが空，canvas未確定，識別quarantine中，又は識別境界後の新規frame待機中にも表示しない．既定identity providerは`unavailable`であるためproduction表示を許可しない．

　capture開始時には，demo用の板書sceneだけでなく，既に表示されているfull-display demo panelも明示的に隠す．これにより，production capture中に旧demo windowだけが残る経路を防ぐ．座標変換，window移動に伴う再配置，current `screenRect`欠落時の非表示と回復，停止時の非表示及びdemo panel遮断は，合成geometryと制御可能なoverlayを用いたnative App testで確認済みである．実PowerPoint上の見た目の一致，window移動・resize，複数display，full-screen，発表者表示，scale factor，panel z-order及びclick-through入力は，まだ動作確認していない．

　`.complete`及び`.started`だけをnew delivery，`.idle`だけをrepeatとして扱う．`SCFrameStatus`の欠落，不正形式，未知値，`.blank`及び`.suspended`，不正sample並びに変換失敗ではrepeat可能なpayloadを破棄し，Appへ順序付きcontent unavailable境界を通知して，後続の`.new` frameまで視覚・板書経路を閉じる．`.stopped`は固定文言のterminal capture errorとして停止処理へ進む．`scaleFactor`はSDK文書の範囲である1以上4以下だけを受理する．確定前はcapture delivery件数だけを更新し，安定・内容指紋，Vision，raster候補，占有領域又は板書配置へ画像を渡さない．確定後は，切り出したスライド面だけから全ての視覚指紋及び解析入力を生成する．

　粗い視覚差分又はdense内容更新が候補状態へ入った時点で旧解析を無効化する．dense fingerprintの欠落又は不正も旧解析を直ちに無効化し，valid dense fingerprintのないcoarse confirmed frameでは解析を開始しない．baselineへ戻った後も，current frameの再解析が完了するまで板書提案を閉じる．意味的なslide，canvas又はcapture境界では現在の板書文脈を更新し，境界以前の発話を再提案しない．占有領域が空の解析結果も板書配置を許可しない．capture終了時には最新安定frame，解析及び板書sceneを消去する．

　文字起こしはApp側とApple provider側の二重generation guardを用いる．意味的なslide，canvas又はcapture境界でproviderを停止し，旧callback及び旧segmentを拒否する．安全側として利用者が明示的に再開するまで文字起こしを閉じたままとする．実microphone挙動は未検証である．capture開始時にはdemo sceneを消去し，capture中又はcapture provider停止処理中にはdemo生成を許可しない．これらは制御可能なprovider及びnative fixtureで確認した安全境界であり，実PowerPoint，live canvas精度，microphone又はoverlay alignmentの検証結果ではない．

　runtime検証reportの現行形式はschema 9である．schema 6は識別・frame同期・解析counterへスライド面状態を追加し，schema 7はoverlay mapping状態及び個別のfail-closed rejection理由，schema 8は`slideCanvasConfirmationMode`を追加した．schema 9は，report rootの`slideCanvasFailureReason`及びsnapshotの`slideCanvasInvalidationReason`へboundedな理由だけを追加する．画像，認識文字列，座標，display ID又はwindow titleを保存せず，従来のgeneric failure code及びmessageも変更しない．schema 1からschema 8までは履歴形式として引き続き読込可能であり，新field欠落時は`nil`としてdecodeする．schema 9のcanvas failureでroot reasonが欠落する場合は`unclassifiedInvalidation`へfail-closedで正規化する．slide ID，資料path又はsession tokenも記録しない．valid new frame後のidle repeatでsurface geometryが欠落する経路，selection及びpayload rejectionの分類，runnerが終了前にterminal snapshotを残す経路をtestで固定した．

　runtime専用の`--confirm-full-frame-canvas` flagは，実frameが1件以上届いた後に，そのframe全体を診断目的で明示的に確認する．flagを指定しない通常動作は従来どおり利用者確認式であり，自動確認しない．frameが届かないまま待機期限を迎えた場合は，固定文言の専用failure `captureFrameUnavailable`を記録する．この診断経路による確認は，利用者がスライド面を確認した証拠ではなく，PowerPoint UI除外，overlay alignment又はproduction renderingの証拠にもならない．

　実行時証拠は，ビルドごとに分離する．過去のschema 1ビルドをCodexの許可下で直接起動した40秒の動的検証では，372フレーム，安定スナップショット6件及び画像差分イベント5件を記録した．当時の実装は，この5件を旧`slideChangeCount`欄へ入れていたが，画像だけではスライド同一性を断定できないため，確認済みスライド切替と解釈してはならない．

　その後のschema 2対応済み・意味修正前ビルドによる別の40秒の動的検証では，373フレーム，安定スナップショット6件，旧方式の画像差分イベント5件及び内容更新2件を記録した．レポート`runtime-dynamic-content-revision-2026-08-30.json`のSHA-256は`704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`である．これはcaptureとschema 2メタデータ生成に関する当該ビルド固有の履歴証拠であり，現行ソース又はスライド同一性の検証結果ではない．

　意味修正後のschema 3では，Coreが粗い画像差分を`.significantVisualChange`と呼び，Appが安定した視覚・内容更新へ計上し，画像だけから`slideChangeCount`を増やさない意味を確立した．schema 3 buildについて，動的slide又はmouse手書きのlive成功reportは記録されていない．schema 4は独立slide識別tracker，schema 5は識別境界後のframe同期状態，schema 6はスライド面状態，schema 7はoverlay mapping状態，schema 8はcanvas確認provenance，schema 9はcanvas失敗・無効化理由を追加する．いずれのschema変更も，それ自体では実PowerPointの識別，自動fresh-frame取得，スライド面特定精度又はoverlay alignmentを証明しない．

　画面がロックされた状態で行ったschema 7の診断試行では，正確なPowerPoint windowを1件選択したが，capture frameは0件であった．試行は`captureFrameUnavailable`としてfail-closedで終了し，診断用全frame確認へ到達しなかった．これは正確なwindow選択と0-frame failure診断の実行時証拠であり，schema 7又は後続schemaにおけるlive frame取得，利用者確認式canvas，overlay mapping・alignment・rendering，動的slide又はmouse inkの成功証拠ではない．

　その後，DerivedData内のschema 8 runtime executableを直接起動した15秒のlive静的exact-window診断は成功し，window ID 13577から152件のnew frame，stable frame 1件，Vision `completed`，text 39件，rectangle 14件，`strokeCandidateRegions` 69件及びoccupied region 3件を記録した．reportは`diagnosticFullFrame`，canvas `confirmed`，overlay mapping `mapped`，identity `unavailable`，content revision 0件及びslide change 0件を記録した．external verification directory内のreport `LectureBoard-Runtime-Schema8-ExactWindow-Static-2026-08-31.json`のSHA-256は`593cc70cd666498c8d68cd9f3b8156b617c45d066cc955992106c5c1e18a8b84`である．これは，明示flagで取得window全体を診断用canvasとして用いたdirect verifier文脈の静的capture及びmetadata生成の証拠である．利用者確認式canvasの精度，PowerPoint UI除外，overlayの目視alignment又はproduction rendering，動的slide切替，mouse ink及び意味的slide identityは未検証である．

　実PowerPointに対する読取り専用probeでは，Automation preflightが`0`，PowerPointのslide show windowが1件，Core Graphics windowが2件であることを確認した．しかし，PowerPointから継承される`window.id`は`nil`であり，意味的なslide IDを取得対象の正確なwindow IDへ照合できなかった．名称，列挙順又は概略座標による弱いfallbackは採用していない．既定identity providerは，受理した取得開始ごとに，Automation許可を要求せず，Apple Eventも送らず，`unavailable`を1回通知する．したがって，production adapter，実PowerPointのslide identity，現行semantic buildの動的slide及びmouse手書きは未実装又は未検証である．OCR文字列，座標，検出率，代表的資料，長時間運転及び実講義での有用性も未検証である．

　画面収録の許可は起動文脈とbuild identityごとに区別する．過去のschema 1・競合修正後実行fileをCodexの許可下から直接起動した経路ではpreflightが`authorized`であったが，LaunchServicesを介した同時期の別起動では`unknown`となり，許可要求を行わず`screenRecordingUnavailable`で終了した．これらは現行schema 8 buildのlive frame取得確認ではない．既定の`make build-runtime`はbuildごとに`cdhash`が変わり得るad hoc署名であり，同じApp名とbundle identifierでも再許可が必要になる場合がある．したがって，次の実機再試行では固定保存した同一Appをbuild・置換・移動せずに用いる．

　上記成功buildとbyte-identicalな固定検証App `LectureBoard AI Schema 8 Verification.app`をexternal verification directoryへcopyした．そのarm64 executableのSHA-256は`316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260`，ad hoc CDHashは`e989a694c94daac85db9b4cd31de5179965da384`であり，complete bundleはstrict署名検査に合格した．この固定Appの保存先にあるexecutableを直接，許可要求なし，正確なwindow ID 13577，5秒及び`diagnosticFullFrame`の条件で起動した静的診断は正常終了した．画面収録preflightはcapture前後とも`authorized`，`permissionWasRequested`は`false`であり，snapshot 21件，frame 53件，new frame 53件，repeat 0件，stable frame 1件，content revision 0件，slide change 0件，Vision `completed`，text 44件，rectangle 14件，`strokeCandidateRegions` 106件及びoccupied region 3件を記録した．canvasは`confirmed`，overlay mappingは`mapped`，identityは`unavailable`であった．external verification directory内のreport `LectureBoard-Runtime-Schema8-FrozenApp-Static-2026-08-31.json`のSHA-256は`1758fda4429cc5ba3b1ed46c14069c8b104fb0d425103907362cd8e49d41f1c5`である．これにより，固定pathからの直接起動，画面収録preflight及び静的captureは確認済みとなった．LaunchServices文脈の起動とfail-closed終了は後述の限定検査で確認したが，capture authorizationは未検証である．固定Appを再build，置換又は移動してはならない．

　最初にexternal verification directoryをreport出力先とした試行は，captureを行った形跡があったものの新規report fileを作成できなかったため，成功証拠に含めない．成功した再試行ではreportをsystem temporary directory内の一意なpathへ出力して内容を検証し，external verification directoryへcopyした後に`cmp`で同一性を確認した．今後のruntime検証でも，新規reportはまずsystem temporary directory内の一意なpathへ書き，正常終了，schema及び期待するmetadataを検証してからexternal verification directoryへcopyし，copy前後の一致と保存先SHA-256を確認する．

　固定schema 8 AppをLaunchServicesから起動した限定検査は，report `LectureBoard-Runtime-Schema8-LaunchServices-Preflight-2026-08-31.json`，SHA-256 `ad18b286fa5b4e14f3c15aa92a4672665a65edf3c54102c495383e161bec67f4`を残した．起動，引数伝達，許可要求なし，fail-closed report生成及び自動終了だけを確認し，`screenRecordingUnavailable`でcapture前に終了した．したがって，LaunchServices文脈の画面収録許可，frame取得，canvas又はoverlayは未検証である．

　厳密な入力helperは，最終source SHA-256 `823d96053b81fe539489a5edc1214494184df94d19cb29c28130316df67ffd01`，binary SHA-256 `a08dc9fe2043d9b9e184e50061b220f4b50406f1d1082e6d0dc94a5f8c3aadea`である．GUI-free self-testはhardening 72件，exact window-menu 60件及びslideshow policy 34件を報告し，lint，Swift 6 strict typecheck，compile及び独立reviewに合格した．実PowerPointでもexact menu selection，focus再検査及び別processのslideshow probeが成功した．ただし，続くschema 8 slideshow試行はreport `LectureBoard-Runtime-Schema8-Slideshow-Canvas-Invalidated-2026-08-31.json`，SHA-256 `93c5fd28598bf9d11b3cbb086a2fe05e413e834ea920106bcb2ea274da026956`を残し，new frame 1件，repeat 2件を受けた後，約535 msでcanvas無効化によりfail-closedで終了した．予定したslide advance及びmouse入力より前に停止したため，動的slide又はinkの成功証拠ではない．

　修正前schema 9再試行は，report `LectureBoard-Runtime-Schema9-Slideshow-IdleGeometry-Invalidated-2026-08-31.json`，SHA-256 `edc97ebb2588771318676d1c0ffcf4c55f4f02e1cdb556649eededd8f1f372f8`を残した．new frame 1件及びrepeat 2件の後，入力前に停止し，rootとsnapshotの両方で`idleRepeatSurfaceGeometryUnavailableOrMismatched`を記録した．これは限定された失敗classだけを確認する証拠であり，attachmentの全欠落と不一致を区別せず，修正後の回復，動的slide，mouse ink，利用者確認式canvas又はvisible overlayを検証しない．

## 4．最初にローカルで行うこと

```bash
make doctor
make local-setup
make test-app
make build-runtime
make test-runtime-launch-smoke
```

　`make test-runtime-launch-smoke`は，画面収録許可を要求せず，不正引数では診断を出してJSONを残さず自動終了し，対象窓なしではメタデータだけの失敗JSONを書いて自動終了することを確認する．通常の公開前検査`make verify`にも，Coreテスト，Appテスト，ネイティブビルド，runtimeビルド及びこの起動スモークを組み込む．

　次の実機確認は，次の順で進める．固定schema 8 App及び`LectureBoard AI Schema 9 Idle Policy Verification.app`はbuild，置換又は移動せず，それぞれの履歴証拠として保持する．新規reportはsystem temporary directory内の一意なpathへ書き，内容を検証してからexternal verification directoryへcopyし，`cmp`とSHA-256で保存結果を確認する．現在の再開点は1である．

1. macOS session解除後，固定schema 8／9 Appの既知SHA-256とstrict署名を再確認し，既存の厳密helperでexact menu selection，focus再検査及びslideshow probeを最初から行う．lock中又は安全境界不成立時は入力を送らない．
2. 固定schema 9 idle policy Appを用い，入力前のlive idle配送と暫定all-absent-metadata policyによるcanvas継続又はfail-closed reasonを検証する．artifactを再build又は置換してから既存の画面収録許可を読み替えない．
3. 安全なlive回復を確認した場合だけcontrolled dynamicへ進み，その成功後の別runでmouse inkを検証する．失敗又は別reasonを記録した場合は，その事実を保存し，次の挙動修正もtest-firstで行う．reportはsystem temporary directory内の一意なpathで検証してから保存する．
4. LaunchServicesの限定試行は起動とfail-closed終了だけを確認済みである．capture authorization及びpost-restart permission persistenceは別に検証し，固定pathの直接起動が`authorized`であったことをLaunchServices文脈へ読み替えない．
5. 現行schema 9 Appの利用者確認式スライド面と実装済みoverlay座標変換を，window表示，full-screen，発表者表示，複数display，異なるscale factor，window移動，resize及び再選択で別々に検証する．ScreenCaptureKit surface padding，`contentRect`，`contentScale`及びcurrent `screenRect`の対応，QuartzからAppKitへの変換，操作UI除外，panel z-order及び見た目の座標精度を記録し，未検証のmodeを成功扱いしない．
6. 同一スライド上のマウス手書きと消去について，持続的内容更新及び`strokeCandidateRegions`の狭い動作を検証する．候補を既存インク確定と一般化しない．
7. 意味的なスライド情報を，選択済みの正確なScreenCaptureKit window IDへfail-closedで結び付けられるproduction identity providerを実装する．PowerPointの`window.id`が`nil`である間は，名称，列挙順又は概略座標を代替照合に用いず，公開API又はPowerPoint更新で厳密な経路が成立するまで保留する．
8. exact-window one-shot取得を検討する場合は，stream frameとは異なるprovenance及びcapture epochを設計し，画像へ架空の`displayTime`を付けない．実装後も，production providerを伴う静止スライドで検証するまで自動再同期を確認済みと表現しない．
9. production identity provider完成後に，baseline，切替，中断，session変更，frame quarantine，frame同期の待機・時間切れ・回復及びruntime metadataを検証する．実PowerPointの独立slide識別結果と画像由来の内容更新を別々に校正した後に初めて`slideChangeCount`の実機精度を評価する．
10. PowerPoint windowの終了，再選択，PowerPoint再起動及びdisplay再接続からの復旧，日本語・英語・日英混在・animation・長時間の代表的資料，OCR文字列，title候補，矩形，占有領域，click-through，pen tablet入力非干渉，microphone認識及びonline共有を，それぞれ独立した検証項目として扱う．

　確認結果は，成功・失敗を問わず`docs/build-verification.md`へ記録する．

## 5．次の実装単位

　選択したPowerPoint windowの連続取得，利用者確認式のスライド面切出し，切出し後の粗い輝度指紋による安定視覚判定，160×90のRGB指紋による持続的内容更新，Visionによる文字・矩形解析，長辺640 pixel以下のRGB raster，`strokeCandidateRegions`，正規化占有領域，独立slide識別tracker，App側のfail-closedな統合境界，識別境界後の明示的timeout状態，確認済みcanvasへのfail-closedなoverlay座標変換及びschema 9のmetadata-only診断は実装され，Core 119件・15 suite，idle surface対象App 57件・2 suite及び完全App 217件・25 suiteのtestに合格している．スライド面確定はcapture operation，正確なwindow ID，source pixel寸法及び検証済みScreenCaptureKit surface geometryへ固定され，確定がなければdelivery件数以外の視覚処理を開始しない．resize，session，window不一致，限定idle policy適用後も利用可能なsurface geometryがない場合，又はsurface geometryの変更時には確定結果を無効化する．暫定application policyでは，検証済み`.idle`でsurface 3 keyが全て欠落する場合だけ，直前にlatchしたsurface geometryを不変visual payloadの切出しへ再利用する．complete tupleは完全一致時だけcurrent geometryとして受理する．一部欠落，不正，矛盾，non-idle，直前geometry欠落又はoutput不一致はfail closedとし，`.new` frameまでpoisonをlatchする．3 key全欠落branchでは`screenRect`を継承も利用もせず，overlay mappingを閉じる．overlay位置はその他の受理済みcurrent sampleではその`screenRect`だけを用い，過去位置を継承しない．確認済みcanvas，`contentRect`，`scaleFactor`，`contentScale`，current `screenRect`及び一意に包含するdisplay snapshotからAppKit表示矩形を計算し，operation，window，surface，出力寸法又はcurrent frame sequenceが一致しない場合は表示しない．さらに，意味的slide identity，current visual grounding，frontmost exact PowerPoint window，bounds一致，occlusion不在及び有効なleaseを要求し，明示的非表示，focus・Space変更，content unavailable又は視覚変化で閉じる．capture開始時には旧demo panelも非表示にする．既定identity providerは`unavailable`であるためproduction表示を許可しない．ただし，このidle policyはApple保証ではなく，合成fixture及び制御可能なApp統合testで固定した暫定挙動である．修正前schema 9 reportは限定failure classを確認した．修正後Appは別名固定し，strict署名及びpermission requestなしの固定path preflightを確認したが，macOS sessionがlock中だったためlive capture及び回復，実attachment形状，実PowerPoint上の利用者確認精度，操作UI除外，目視alignment，production rendering，動的表示，複数display，resize，z-order又はclick-through入力は未検証である．筆跡候補も既存inkの確定分類ではなく，座標精度は未検証である．

　直近の作業単位は，固定schema 8 copy及び`LectureBoard AI Schema 9 Idle Policy Verification.app`を移動・置換せず，macOS session解除後に同じ厳密helperでexact editing window，focus及びslideshowを最初から確認し，post-fix live idle回復を検証することである．修正前reportで理由classは確定し，修正後Appのstrict署名及び固定path preflightも確認したが，lock中はPowerPointの必須Accessibility属性を再確認できなかったためlive recoveryは未検証である．安全な回復を確認した後だけdynamicへ進み，その成功後の別runでmouse inkを検証する．新たな失敗への挙動変更はtest-firstで行う．LaunchServices capture authorizationは別に検証し，いずれの新規reportもsystem temporary directory内の一意なpathで検証してからexternal verification directoryへcopyする．その後，実装済みoverlay座標変換を利用者確認式canvasと実PowerPointで検証し，合成test又は診断用全frame確認では見えない座標系，display scale，window移動，resize，full-screen，発表者表示，z-order及び入力透過の問題を一つずつtest-firstで修正する．切出し座標，診断用全frame確認及び表示座標を同一視せず，成功した表示modeだけを検証済みとして記録する．これと並行して，production identity providerは，実PowerPointの意味的なslide IDを選択済みの正確なwindow IDへ結び付けられる公開経路を調査し，その経路が成立した場合だけ実装する．`window.id`が`nil`であった実測結果を無視して弱いfallbackへ進んではならない．自動fresh-frame取得を先に扱う場合は，stream frameとは異なるprovenanceを設けたうえで，現行schema 9 buildによる実行時検証を別に行う．代表的な講義資料での検出率，認識内容，title候補，矩形，占有領域及び赤枠座標の校正，LaunchServicesの許可境界，長時間運転と終了処理，既存ink検出及びより頑健な空白分析は，それぞれ別の検証項目として残す．

　AIやクラウドサービスを先に接続してはならない．まず，何を見て，どのスライドを対象とし，どこが空いており，どの発話を根拠としたかを観察・記録できる基盤を完成させる．

## 6．ローカルCodex開始時の指示文

　次の文章をローカルCodexの最初のメッセージとして使用できる．

```text
AGENTS.md，docs/local-codex-handoff-ja.md，ROADMAP.md，docs/build-verification.mdを最初に読んでください．次にmake doctorとmake local-setupを実行し，このMac上でネイティブmacOSアプリがビルドできる状態にしてください．発生した問題を一つずつ修正し，各修正にテストを追加し，検証結果をdocs/build-verification.mdへ記録してください．現段階で未検証の機能を，動作確認済みであるかのように記述しないでください．
```

## 7．公開方針

　公開リポジトリ`akiyama709/lectureboard-ai`は2026年8月29日に作成済みであるが，リポジトリが公開されていること自体は製品完成を意味しない．`main`ではプルリクエストと`LectureBoardCore tests`の成功が必須であり，force pushとブランチ削除は禁止されている．

　公開段階は，α版，β版，Release Candidate，`v1.0.0`正式版の順とする．α版は機能・安全性・実機証拠を形成する開発版，β版は`v1.0.0`の機能範囲を固定して代表環境で検証する版，Release Candidateは機能凍結後に配布・署名・プライバシー・アクセシビリティ・クリーン導入を確認する候補である．検証済み配布物を公開`v1.0.0` GitHub Releaseとして一般取得可能にし，公開後の再ダウンロード，ハッシュ，署名，Gatekeeper及び起動を確認した時点だけを完成とする．

　公開前には必ず次を実行する．

```bash
make verify
```

　`scripts/publish-to-github.sh`は初回リポジトリ公開専用であり，再実行しない．今後は作業ブランチをpushし，プルリクエストの必須CI成功後に`main`へ統合する．正式版は，Release Candidateの受入検証後，バージョン整合性を確認し，`v1.0.0`タグ，リリースノート，署名・notarization済み配布物及びSHA-256を備えたGitHub Releaseとして公開する．外部公開に当たるpush，PR，タグ及びReleaseの実行は，それぞれ必要な確認を得て行う．
