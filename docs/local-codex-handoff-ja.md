# LectureBoard AI ローカル開発引継ぎ

更新日：2026年9月1日

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

　2026年9月1日現在，現行schema 10 sourceの中核Swift packageは137テスト・15 suite，ネイティブmacOS Appは228テスト・27 suiteがMac上で通過している．14時44分から14時45分JSTに全14段階の`make verify`が合格し，結果を反映した文書を含む状態でも14時50分から14時51分JSTに同じ全14段階へ再度合格した．最終native result bundleは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_14-50-49-+0900.xcresult`であり，authoritative total 228，failed 0，skipped 0，expected failure 0である．生成したarm64 runtimeはad hoc署名のstrict bundle検査へ合格したが，Developer ID署名，hardened runtime及びnotarization済みではない．このgateはlive schema 10分類の証拠ではない．2026年8月31日の完全gateは，その時点のschema 9 sourceに関する履歴証拠として保持する．

　16時17分の全14段階`make verify`は119 Coreテスト及び217 Appテスト時点の履歴証拠である．123件及び218件への変更後に行った最初の後続試行は，sandboxがSwift module cacheへの書込みを拒否したためCore manifestの計画段階で停止した．この失敗を成功証拠には数えない．

　その後の通常実行で，`make doctor`は失敗0件・warning 0件，`make local-setup`は成功し，Core 123件・15 suiteも通過した．さらに，当時のschema 9 sourceは23時02分から23時03分JSTに全14段階の`make verify`へ合格し，その結果を反映した文書を含む状態でも23時09分から23時10分JSTに同じ全14段階へ再度合格した．Core 123件・15 suite，native App 218件・25 suite，署名なしnative build，arm64 ad hoc runtime buildとstrict bundle署名，画面収録permissionを要求しない起動smoke及び公開前検査が全て成功した．最終native result bundleは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_23-09-45-+0900.xcresult`であり，authoritative total 218，failed 0，skipped 0，expected failure 0である．

　固定保存したschema 9 Appの直接実行では，post-fix idle continuityと4回の制御入力に対応する4 content revisionsを確認したが，identityは`unavailable`であり，overlay mappingは一度も成功していない．さらに2026年9月1日の限定診断では，見えるmouse strokeと消去後の視覚的復元を確認した．これらは固定schema 9 build固有の証拠であり，現行schema 10，意味的又は入力ごとのink分類，既存ink検出，利用者確認式canvas又はproduction renderingの証拠ではない．

　取得開始・停止・error・一覧更新・選択変更，frame順序，視覚更新，解析取消し及び古い解析結果の排除は，制御可能なfakeとnative画像fixtureによる回帰testで固定している．選択したPowerPoint窓については，ScreenCaptureKit窓ID，所有PID及び完全一致bundle identifierを取得開始まで固定し，重複，再利用又は所有者変更時にfail-closedで停止する．Coreには，同じpresentation session token及びslide IDが2回連続したときだけ基準又は切替を確定し，中断をまたいだ切替を推定しないtrackerがある．Appは，provider観測の対象，capture session及び順序を検査する．候補確定中に届いたframeは取得件数へ計上した後に視覚解析から除外する．基準確立又は切替時には以前の解析及び板書sceneを破棄し，Appが識別観測を受理したlocal mach絶対時刻よりScreenCaptureKitの`displayTime`が厳密に後である`.new` frameが到着するまで解析を再開しない．Apple Speechの確定結果についても，識別境界以前又は境界後frameをAppが受理したlocal時刻以前に生成された結果を，MainActorでの処理順にかかわらず板書候補から除外する．識別境界後のframe gateは，`waiting`，`synchronized`及び`timedOut`を明示する．時間切れはgateを開かず，古い境界又は停止済みsessionの遅延timeoutはtokenで拒否し，後着の厳密に新しい`.new` frameだけが時間切れ状態から回復できる．この挙動は決定論的testで確認済みであるが，production identity providerを伴う実行時挙動は未検証である．

　公開macOS及びPowerPoint APIは，PowerPoint内部で描画される正確なスライド面矩形を公開しない．ScreenCaptureKitの`contentRect`は取得surfaceを表し，PowerPoint内部のslide subviewを表さない．このため，Appは正確な取得operationから得たwindow previewを固定し，利用者が表示中のスライド面だけをdragで囲んで明示的に確定する．切出しはsource上で幅32 pixel，高さ24 pixel及び面積1,024平方pixelを全て満たさなければならない．確定結果はcapture operation，正確なScreenCaptureKit window ID，source pixel寸法及び検証済みScreenCaptureKit surface geometryへ固定する．再取得，window不一致，pixel寸法不一致，下記の限定idle policy適用後も利用可能なsurface geometryがない場合，又は`contentRect`，scale factor若しくはcontent scaleの変更時には，確定結果，解析及び板書sceneを無効化する．idle surfaceの扱いはApple保証ではなく，live attachment観測前の暫定application policyである．検証済み`.idle`で`contentRect`，`scaleFactor`及び`contentScale`の3 keyが全て欠落する場合だけ，直前にlatchしたsurface geometryを不変visual payloadの切出しへ再利用する．3 keyが全て揃う場合は，直前geometryとの完全一致をcurrent geometryとして受理する．一部欠落，不正形式，矛盾，non-idle，直前geometry欠落，又は直前output寸法とpayload寸法の不一致はfail closedとし，後続の`.new` frameまでrepeat geometryのpoisonをlatchする．3 key全欠落branchでは`screenRect`を継承も利用もせず，overlay mappingを閉じる．修正前schema 9 reportは限定された失敗classを確認した．修正後の限定fixed-path実行は18件のidle repeatをまたいでcanvasを`confirmed`に保ち，post-fix live continuityを確認した．ただし，reportは実attachmentの全欠落と完全一致tupleを区別する証拠を保存しておらず，実attachment形状及び他のPowerPoint表示modeでの一般性は未検証である．

　画面上の現在位置は，surface geometryと混同せず，frameごとのScreenCaptureKit `screenRect`から別の値として取得する．attachment内の矩形は`CGRect`，矩形型の`NSValue`及びdictionary representationを受理し，有限で正の幅・高さを要求する．複数displayでは負のglobal originも正当な値として受理する．surface 3 key全欠落branch以外のidle repeatでも直前frameの画面位置を継承せず，そのidle sample自身の`screenRect`だけを用いる．3 key全欠落branchは，そのsampleに`screenRect`があっても画面位置を空にする．現在位置が欠落又は不正である場合，確認済みcanvas及び視覚解析を直ちに破棄するのではなく，overlayだけを非表示にし，後続の有効なcurrent frameで再計算する．このcurrent-frame境界は合成attachmentでtest済みであるが，実ScreenCaptureKitの`screenRect`向き，単位及びidle時の提供挙動は未検証である．

　確認済みcanvasからoverlay表示矩形への変換は，capture operation，正確なwindow ID，完全一致するsurface geometry，出力pixel寸法及びcurrent frame sequenceへ固定する．canvasのpixel矩形が`contentRect`の範囲内にあることを確認し，`scaleFactor`及び`contentScale`を用いてcurrent `screenRect`へ対応付ける．丸め誤差として認めるのは出力1 pixel以内に限る．続いて，`CGDisplayBounds`のQuartz global座標から`NSScreen.frame`のAppKit座標へ変換し，対象矩形を完全に含む検証済みdisplayが正確に1件である場合だけ，click-through panelをその矩形へ表示する．production表示には，意味的slide identityとcurrent visual grounding，frontmostの正確なPowerPoint PID・bundle，1件だけのon-screen layer 0 exact window，current `screenRect`との各辺2 point以内の一致及び手前の重複window不在も要求する．証拠の欠落，古いoperation・window・frame，surface又は出力寸法の不一致，display境界の横断若しくは複数displayへの曖昧な包含，明示的非表示，focus・Space変更又はcapture cadenceから独立したlease失効ではfail-closedで非表示にする．板書sceneが空，canvas未確定，識別quarantine中，又は識別境界後の新規frame待機中にも表示しない．既定identity providerは`unavailable`であるためproduction表示を許可しない．

　capture開始時には，demo用の板書sceneだけでなく，既に表示されているfull-display demo panelも明示的に隠す．これにより，production capture中に旧demo windowだけが残る経路を防ぐ．座標変換，window移動に伴う再配置，current `screenRect`欠落時の非表示と回復，停止時の非表示及びdemo panel遮断は，合成geometryと制御可能なoverlayを用いたnative App testで確認済みである．実PowerPoint上の見た目の一致，window移動・resize，複数display，full-screen，発表者表示，scale factor，panel z-order及びclick-through入力は，まだ動作確認していない．

　`.complete`及び`.started`だけをnew delivery，`.idle`だけをrepeatとして扱う．`SCFrameStatus`の欠落，不正形式，未知値，`.blank`及び`.suspended`，不正sample並びに変換失敗ではrepeat可能なpayloadを破棄し，Appへ順序付きcontent unavailable境界を通知して，後続の`.new` frameまで視覚・板書経路を閉じる．`.stopped`は固定文言のterminal capture errorとして停止処理へ進む．`scaleFactor`はSDK文書の範囲である1以上4以下だけを受理する．確定前はcapture delivery件数だけを更新し，安定・内容指紋，Vision，raster候補，占有領域又は板書配置へ画像を渡さない．確定後は，切り出したスライド面だけから全ての視覚指紋及び解析入力を生成する．

　粗い視覚差分又はdense内容更新が候補状態へ入った時点で旧解析を無効化する．dense fingerprintの欠落又は不正も旧解析を直ちに無効化し，valid dense fingerprintのないcoarse confirmed frameでは解析を開始しない．baselineへ戻った後も，current frameの再解析が完了するまで板書提案を閉じる．意味的なslide，canvas又はcapture境界では現在の板書文脈を更新し，境界以前の発話を再提案しない．占有領域が空の解析結果も板書配置を許可しない．capture終了時には最新安定frame，解析及び板書sceneを消去する．

　文字起こしはApp側とApple provider側の二重generation guardを用いる．意味的なslide，canvas又はcapture境界でproviderを停止し，旧callback及び旧segmentを拒否する．安全側として利用者が明示的に再開するまで文字起こしを閉じたままとする．実microphone挙動は未検証である．capture開始時にはdemo sceneを消去し，capture中又はcapture provider停止処理中にはdemo生成を許可しない．これらは制御可能なprovider及びnative fixtureで確認した安全境界であり，実PowerPoint，live canvas精度，microphone又はoverlay alignmentの検証結果ではない．

　runtime検証reportの現行形式はschema 10である．schema 6はスライド面状態，schema 7はoverlay mapping状態及び拒否理由，schema 8は`slideCanvasConfirmationMode`，schema 9はbounded canvas failure理由を追加した．schema 10は9種類の`captureFailureSource`及び21種類の公開`captureSCStreamErrorCode`を追加する．sample stopped，delegate error，inactive stream及びstart failureは一つの同期routerへ入り，最初のterminal eventだけを採用する．後続又は同時callback，古いcapture operation，新規start前のtelemetry及びmanual stop後のcallbackは採用しない．既知SC error codeは対応する2種類のsourceだけで必須とし，他の7種類では禁止する．schema 1からschema 9，completed report及びcapture以外のfailureは新fieldを無視する．現行capture failureでfieldが欠落，不正，未知又は矛盾する場合は`unclassifiedCaptureFailure`へfail-closedで正規化する．runnerはmodel停止でlive stateをclearする前に採用済みtelemetryを最終JSONへcopyする．画像，認識文字列，座標，display ID，window title，raw error domain，raw numeric code，description又は`userInfo`は保存しない．これらは自動test済みであるが，live schema 10 reportは未検証である．

　runtime専用の`--confirm-full-frame-canvas` flagは，実frameが1件以上届いた後に，そのframe全体を診断目的で明示的に確認する．flagを指定しない通常動作は従来どおり利用者確認式であり，自動確認しない．frameが届かないまま待機期限を迎えた場合は，固定文言の専用failure `captureFrameUnavailable`を記録する．この診断経路による確認は，利用者がスライド面を確認した証拠ではなく，PowerPoint UI除外，overlay alignment又はproduction renderingの証拠にもならない．

　実行時証拠は，ビルドごとに分離する．過去のschema 1ビルドをCodexの許可下で直接起動した40秒の動的検証では，372フレーム，安定スナップショット6件及び画像差分イベント5件を記録した．当時の実装は，この5件を旧`slideChangeCount`欄へ入れていたが，画像だけではスライド同一性を断定できないため，確認済みスライド切替と解釈してはならない．

　その後のschema 2対応済み・意味修正前ビルドによる別の40秒の動的検証では，373フレーム，安定スナップショット6件，旧方式の画像差分イベント5件及び内容更新2件を記録した．レポート`runtime-dynamic-content-revision-2026-08-30.json`のSHA-256は`704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`である．これはcaptureとschema 2メタデータ生成に関する当該ビルド固有の履歴証拠であり，現行ソース又はスライド同一性の検証結果ではない．

　意味修正後のschema 3では，Coreが粗い画像差分を`.significantVisualChange`と呼び，Appが安定した視覚・内容更新へ計上し，画像だけから`slideChangeCount`を増やさない意味を確立した．schema 3 buildについて，動的slide又はmouse手書きのlive成功reportは記録されていない．schema 4は独立slide識別tracker，schema 5は識別境界後のframe同期状態，schema 6はスライド面状態，schema 7はoverlay mapping状態，schema 8はcanvas確認provenance，schema 9はcanvas失敗・無効化理由を追加する．いずれのschema変更も，それ自体では実PowerPointの識別，自動fresh-frame取得，スライド面特定精度又はoverlay alignmentを証明しない．

　画面がロックされた状態で行ったschema 7の診断試行では，正確なPowerPoint windowを1件選択したが，capture frameは0件であった．試行は`captureFrameUnavailable`としてfail-closedで終了し，診断用全frame確認へ到達しなかった．これは正確なwindow選択と0-frame failure診断の実行時証拠であり，schema 7又は後続schemaにおけるlive frame取得，利用者確認式canvas，overlay mapping・alignment・rendering，動的slide又はmouse inkの成功証拠ではない．

　その後，DerivedData内のschema 8 runtime executableを直接起動した15秒のlive静的exact-window診断は成功し，window ID 13577から152件のnew frame，stable frame 1件，Vision `completed`，text 39件，rectangle 14件，`strokeCandidateRegions` 69件及びoccupied region 3件を記録した．reportは`diagnosticFullFrame`，canvas `confirmed`，overlay mapping `mapped`，identity `unavailable`，content revision 0件及びslide change 0件を記録した．external verification directory内のreport `LectureBoard-Runtime-Schema8-ExactWindow-Static-2026-08-31.json`のSHA-256は`593cc70cd666498c8d68cd9f3b8156b617c45d066cc955992106c5c1e18a8b84`である．これは，明示flagで取得window全体を診断用canvasとして用いたdirect verifier文脈の静的capture及びmetadata生成の証拠である．利用者確認式canvasの精度，PowerPoint UI除外，overlayの目視alignment又はproduction rendering，動的slide切替，mouse ink及び意味的slide identityは未検証である．

　実PowerPointに対する読取り専用probeでは，Automation preflightが`0`，PowerPointのslide show windowが1件，Core Graphics windowが2件であることを確認した．しかし，PowerPointから継承される`window.id`は`nil`であり，意味的なslide IDを取得対象の正確なwindow IDへ照合できなかった．名称，列挙順又は概略座標による弱いfallbackは採用していない．既定identity providerは，受理した取得開始ごとに，Automation許可を要求せず，Apple Eventも送らず，`unavailable`を1回通知する．固定schema 9のfixed-path診断では4回の制御入力に対応する4 content revisionsを確認したが，identityは`unavailable`のままでslide changeも0件であった．したがって，production adapter及び実PowerPointの意味的slide transitionは未実装又は未検証である．固定schema 9診断で確認した見えるmouse strokeを，意味的又は入力ごとのink分類，既存ink検出，現行schema 10又はproduction canvasへ一般化してはならない．OCR文字列，座標，検出率，代表的資料，長時間運転及び実講義での有用性も未検証である．

　画面収録の許可は起動文脈とbuild identityごとに区別する．過去のschema 1・競合修正後実行fileをCodexの許可下から直接起動した経路ではpreflightが`authorized`であったが，LaunchServicesを介した同時期の別起動では`unknown`となり，許可要求を行わず`screenRecordingUnavailable`で終了した．これらは当時のschema 8 buildのlive frame取得確認ではない．既定の`make build-runtime`はbuildごとに`cdhash`が変わり得るad hoc署名であり，同じApp名とbundle identifierでも再許可が必要になる場合がある．したがって，次の実機再試行では固定保存した同一Appをbuild・置換・移動せずに用いる．

　上記成功buildとbyte-identicalな固定検証App `LectureBoard AI Schema 8 Verification.app`をexternal verification directoryへcopyした．そのarm64 executableのSHA-256は`316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260`，ad hoc CDHashは`e989a694c94daac85db9b4cd31de5179965da384`であり，complete bundleはstrict署名検査に合格した．この固定Appの保存先にあるexecutableを直接，許可要求なし，正確なwindow ID 13577，5秒及び`diagnosticFullFrame`の条件で起動した静的診断は正常終了した．画面収録preflightはcapture前後とも`authorized`，`permissionWasRequested`は`false`であり，snapshot 21件，frame 53件，new frame 53件，repeat 0件，stable frame 1件，content revision 0件，slide change 0件，Vision `completed`，text 44件，rectangle 14件，`strokeCandidateRegions` 106件及びoccupied region 3件を記録した．canvasは`confirmed`，overlay mappingは`mapped`，identityは`unavailable`であった．external verification directory内のreport `LectureBoard-Runtime-Schema8-FrozenApp-Static-2026-08-31.json`のSHA-256は`1758fda4429cc5ba3b1ed46c14069c8b104fb0d425103907362cd8e49d41f1c5`である．これにより，固定pathからの直接起動，画面収録preflight及び静的captureは確認済みとなった．LaunchServices文脈の起動とfail-closed終了は後述の限定検査で確認したが，capture authorizationは未検証である．固定Appを再build，置換又は移動してはならない．

　最初にexternal verification directoryをreport出力先とした試行は，captureを行った形跡があったものの新規report fileを作成できなかったため，成功証拠に含めない．成功した再試行ではreportをsystem temporary directory内の一意なpathへ出力して内容を検証し，external verification directoryへcopyした後に`cmp`で同一性を確認した．今後のruntime検証でも，新規reportはまずsystem temporary directory内の一意なpathへ書き，正常終了，schema及び期待するmetadataを検証してからexternal verification directoryへcopyし，copy前後の一致と保存先SHA-256を確認する．

　固定schema 8 AppをLaunchServicesから起動した限定検査は，report `LectureBoard-Runtime-Schema8-LaunchServices-Preflight-2026-08-31.json`，SHA-256 `ad18b286fa5b4e14f3c15aa92a4672665a65edf3c54102c495383e161bec67f4`を残した．起動，引数伝達，許可要求なし，fail-closed report生成及び自動終了だけを確認し，`screenRecordingUnavailable`でcapture前に終了した．したがって，LaunchServices文脈の画面収録許可，frame取得，canvas又はoverlayは未検証である．

　この時点の厳密な入力helperは，source SHA-256 `823d96053b81fe539489a5edc1214494184df94d19cb29c28130316df67ffd01`，binary SHA-256 `a08dc9fe2043d9b9e184e50061b220f4b50406f1d1082e6d0dc94a5f8c3aadea`であった．GUI-free self-testはhardening 72件，exact window-menu 60件及びslideshow policy 34件を報告し，lint，Swift 6 strict typecheck，compile及び独立reviewに合格した．実PowerPointでもexact menu selection，focus再検査及び別processのslideshow probeが成功した．ただし，続くschema 8 slideshow試行はreport `LectureBoard-Runtime-Schema8-Slideshow-Canvas-Invalidated-2026-08-31.json`，SHA-256 `93c5fd28598bf9d11b3cbb086a2fe05e413e834ea920106bcb2ea274da026956`を残し，new frame 1件，repeat 2件を受けた後，約535 msでcanvas無効化によりfail-closedで終了した．予定したslide advance及びmouse入力より前に停止したため，動的slide又はinkの成功証拠ではない．

　修正前schema 9再試行は，report `LectureBoard-Runtime-Schema9-Slideshow-IdleGeometry-Invalidated-2026-08-31.json`，SHA-256 `edc97ebb2588771318676d1c0ffcf4c55f4f02e1cdb556649eededd8f1f372f8`を残した．new frame 1件及びrepeat 2件の後，入力前に停止し，rootとsnapshotの両方で`idleRepeatSurfaceGeometryUnavailableOrMismatched`を記録した．これは限定された失敗classだけを確認する証拠であり，attachmentの全欠落と不一致を区別せず，修正後の回復，動的slide，mouse ink，利用者確認式canvas又はvisible overlayを検証しない．

　修正後の固定Appを保存pathから直接起動した制御付き診断は，report `LectureBoard-Runtime-Schema9-IdlePolicy-Dynamic-2026-08-31.json`，SHA-256 `390bee97a34dbde9dc434f876cdf2b05c0a4836effd0d36b528e6231db3ca7e2`を残した．154 snapshotsでnew frame 15件，idle repeat 18件，stable frame 4件，4回の制御入力に対応する4 content revisions及びslide change 0件を記録し，canvasは全snapshotで`confirmed`だった．これは限定fixed-path診断におけるpost-fix idle continuityと入力に対応する内容更新の証拠である．identityは全始終`unavailable`，slide changeは0件，overlay mappingは成功0件であるため，意味的slide transition，利用者確認式canvas，visible overlay alignment又はproduction renderingの証拠ではない．

　続く当時のschema 9に対する最初のmouse-ink試行は，strokeを送る前に`screencapture`出力が空となり安全側で停止した．runtime report及び検証画像は生成されておらず，mouse inkの成否に関する実行時証拠はない．その後，安全helperをsource SHA-256 `47d43abcb8dec2a0d6724c2bf3d2f81fa29c60bb00514747fa6b99b89dba523d`，binary SHA-256 `90b14a40b138924d404202af28e9fd3a98e48139c75a6ca7031cb0adf84daebc`へhardeningした．GUI-free self-test，strict lint，Swift 6 strict-concurrency typecheck，compile，20回の反復検査及び独立read-only reviewは合格し，reviewでP0からP3までの指摘はなかった．これはhelper単体の安全境界に関する証拠であり，次のmouse-ink本試行の結果はまだ確定していない．

　さらに，existing slideshowの終了境界を明示的にfail closedとするhelperへ更新した．source SHA-256は`a5866aaed585dd6ce5a92e740be6fe28274b2d105185d3bc350b86f6ed3fc388`，当時の一時arm64 binaryのSHA-256は`7df7a10ad977afbcd2740d9619ec078ab81e2d25e8e9cbf2f32e381e552d790e`である．GUI-free self-testはexisting-slideshow exitのexplicit outcome 79件に合格し，local反復5回，別workerによる反復20回及び独立read-only reviewも合格した．reviewでP0からP3までの指摘はなかった．これらはhelperの実行可能な安全分岐の証拠だけであり，mouse inkの証拠ではない．

　続くpreflightでは，passive exact editing focus確認が失敗し，focus-onlyは成功，exact menu selectionはediting window ID `19218`で成功し，2回目のfocus-onlyも成功した．しかし，slideshow probeはstableかつsubstantialなnew又はchanged windowを確立できずfail closedで停止した．直後の読取り専用probeでは，exact slideshow window ID `19229`（1,512×982）とexact editing window ID `19218`（1,512×900）を確認した．その後，`IOConsoleLocked = Yes`を確認したため，Escape，mouse，LectureBoard runtime，report又はimageは実行・生成せず，existing slideshowをそのまま維持した．これはfail-closed preflightとlock境界での非干渉の証拠であり，mouse ink，live capture又はruntime reportの証拠ではない．

　2026年9月1日の固定schema 9 five-stroke診断は，report `LectureBoard-Runtime-Schema9-MouseInk-2026-09-01.json`，SHA-256 `534a285e8f3830891c374746338aa361ab9ebf15cf1f4b199e686d1166b17cb7`を残した．20秒間に78 snapshots，80 frames，すなわち65 new及び15 repeat，4 content revisions並びにslide change 0件を記録した．手書き前と消去後の画像はbyte-identicalであり，手書き後には5 connected componentsがあった．これは見えるmouse strokeと消去後の視覚的復元だけの証拠であり，意味的又は入力ごとの分類，既存PowerPoint ink検出，production canvas，current schema 10又は別個のpost-erase revisionを検証しない．

　early aggregate failure reportのSHA-256は`44ed13c6b338a48fe5c92290c47a0ea8ae4fb105590ddddfa65a6a3d421eb5db`である．約12.068秒，60 frames，すなわち44 new及び16 repeat，3 revisionsの後に`captureFailed`となったが，schema 9はterminal sourceを保持していない．内部SC logから原因又は入力との因果を断定してはならない．content-mutation inputを送らない30秒static control reportのSHA-256は`60deb22f7c3561ed2c4b105ea69c0a9e5f196a6d5b7f6c42e6f23eb399b8c0fc`で，41 frames，すなわち4 new及び37 repeat，1 content revisionを記録した．したがって，false-positive-freeの証拠ではない．

　single-stroke reportのSHA-256は`494eb356282f8c49c9a57d7d67ec2e56cb31a22326da69d373b556f047332d45`であり，15 new，15 repeat，1 revision及び1 componentを記録した．five-stroke rerunのSHA-256は`7cadc164d28f534fe3620261eb26b14c20d7694b16216629d940d1c5e9870385`であり，66 new，15 repeat，4 revisions及び5 componentsを記録した．両runとも手書き前と消去後の画像はbyte-identicalだったが，別個のpost-erase revisionは記録しなかった．統合metadata audit `LectureBoard-Runtime-Schema9-Live-Checkpoint-Audit-2026-09-01.json`のSHA-256は`a547704072066e63047abaffc8e4bec0149be39760901e852236158d103ceff2`，image auditは`38552053c77b46d6a9eccb0cbde8f1baeef6faadf74bee9f57247e8e110d95a9`である．

　dense detectorの既定契約はdifference threshold `0.08`，minimum changed-pixel fraction `0.001`，persistence tolerance `0`及び同一候補3 deliveryである．erase候補は3件目のqualifying deliveryを受けなかったため，thresholdは弱めなかった．次の実装候補は，dense candidate pending時だけ最大2回を約100 ms間隔で取得するbounded one-shot fresh sampleである．capture operation，正確なwindow，canvas，identity及びcandidate generationを全てguardし，capture metrics，identity及びoverlay provenanceへ混入させない．現時点では未実装である．

　最新review済みignored helper sourceのSHA-256は`37e07382857c0a72cdfc08e8bb30b52162837409b004ced6d6f34e8bef2f7aaf`である．保存したreview済みarm64 binary `DriveExactPowerPointInk-Schema10-Reviewed-2026-09-01`のSHA-256は`e7d5b1d01fa6929834526766fc606c1deb2fc78f4558cd0a990e65a62dd9a15d`である．GUI-free self-test 20件全て，lint，Swift 6 strict typecheck，compile及び独立reviewに合格した．これはhelperのtest済みpolicyだけの証拠であり，all-Spaces切替，Escape後のWindowServer挙動，実Accessibility focus変更及びend-to-end inputはlive未検証である．

## 4．最初にローカルで行うこと

```bash
make doctor
make local-setup
make test-app
make build-runtime
make test-runtime-launch-smoke
```

　`make test-runtime-launch-smoke`は，画面収録許可を要求せず，不正引数では診断を出してJSONを残さず自動終了し，対象窓なしではメタデータだけの失敗JSONを書いて自動終了することを確認する．通常の公開前検査`make verify`にも，Coreテスト，Appテスト，ネイティブビルド，runtimeビルド及びこの起動スモークを組み込む．

　次の作業は，次の順で進める．固定schema 8 App及び`LectureBoard AI Schema 9 Idle Policy Verification.app`はbuild，置換又は移動せず，それぞれの履歴証拠として保持する．新規reportはsystem temporary directory内の一意なpathへ書き，内容を検証してからexternal verification directoryへcopyし，`cmp`とSHA-256で保存結果を確認する．

1. bounded one-shot fresh-sample経路をtest-firstで実装し，operation，window，canvas，identity，candidate generation，停止，restart及びstale completionの各分岐を固定する．detector thresholdは弱めない．
2. 明確に分離したschema 10検証artifactで，static control，mouse ink及びeraseを再試行し，別個のpost-erase content revisionとbounded capture failure sourceを確認できるか検証する．見えるstroke及び視覚的復元と，意味的ink分類，既存ink検出及びper-input分類を分けて記録する．
3. 利用者確認式スライド面と実装済みoverlay座標変換を，window表示，full-screen，発表者表示，複数display，異なるscale factor，window移動，resize及び再選択で別々に検証する．未検証のmodeを成功扱いしない．
4. 意味的なスライド情報を，選択済みの正確なScreenCaptureKit window IDへfail-closedで結び付けられるproduction identity providerを実装する．PowerPointの`window.id`が`nil`である間は弱いfallbackを採用しない．
5. LaunchServices capture authorization，post-restart permission persistence，PowerPoint windowの終了・再選択・再起動・display再接続，日本語・英語・日英混在・animation・長時間の代表的資料，OCR，click-through，pen tablet，microphone及びonline共有を，それぞれ独立した検証項目として扱う．

　確認結果は，成功・失敗を問わず`docs/build-verification.md`へ記録する．

## 5．次の実装単位

　選択したPowerPoint windowの連続取得からoverlayのfail-closedな座標変換までの決定論的基盤に加え，schema 10のbounded capture-terminal診断を実装した．現行sourceはCore 137件・15 suite，App 228件・27 suite及び全14段階gateに合格する．schema 10診断は最初のterminal eventだけを同期採用し，stale operationを拒否し，新規start及びmanual stopでresetし，runner最終JSONへ保持する．互換性，正規化及びprivacy boundaryもtest済みであるが，live schema 10 reportは未検証である．固定schema 9 Appのlive証拠は，idle continuity，visual content updates，見えるmouse stroke及び消去後の視覚的復元に限定する．意味的又は入力ごとのink分類，既存ink検出，別個のpost-erase revision，利用者確認精度，目視alignment及びproduction renderingは未検証である．

　直近の作業単位は，bounded one-shot fresh sampleをtest-firstで実装してpost-erase revisionを再検証することである．その後，利用者確認式canvasと実PowerPoint上のoverlayを独立して検証し，exact-window-bound production identity providerを弱いfallbackなしで追跡する．固定schema 8及びschema 9 Appは移動・置換しない．いずれの新規reportもsystem temporary directory内の一意なpathで検証してからexternal verification directoryへcopyする．代表資料，OCR，LaunchServices，長時間運転，既存ink，複数display，click-through，pen tablet及びmicrophoneは別の検証項目として残す．

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
