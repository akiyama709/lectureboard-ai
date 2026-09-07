# LectureBoard AI ローカル開発引継ぎ

更新日：2026年9月7日

## 最新の再開点（2026年9月7日3時台）

　本人試用に使用するproduction Appは，exact code-bearing commit `c525ee468283bee333166cb301a3c9570fae0086`から，arm64 Release，version 1.0.0 build 1，Hardened Runtime，ad hoc署名として作成し，`/Users/akiyama/Documents/LectureBoard AI Verification/Mock-Lecture-c525ee4/LectureBoard AI.app`へ固定した．executable SHA-256は`f86d6cd09ae571ac896880c95ca1e09f08ccaa978cc6d9c5912d1a71c211073c`，CDHashは`ad850f341f0fb45ddafde45ec074801a8dfdedf6`であり，build元とのbyte同一性とstrict deep署名を確認した．このAppは本人試用中に再build・置換・移動しない．

　同じcommitで`make doctor`は失敗0件，GitHub CLI未認証のwarning 1件で完了した．ChromeへのGitHub loginはCLI認証を意味しないが，local buildは妨げない．`make local-setup`はCore 250件・19 suiteを含めて合格した．固定Appの通常LaunchServices起動も，App window 1件，application ready，文字起こし停止，crashなしを確認した．ただし，新しいad hoc署名のprivacy identityには画面収録権限がまだなく，AppはPowerPoint refresh及びmanaged開始をfail closedで無効にした．許可button，System Settings，microphone，PowerPoint入力及び再試行には進まず，正常終了させた．

　次の人手境界は，このexact pathのAppだけをmacOSの「画面収録とシステムオーディオ録音」で1回許可し，必要なら同じAppを終了・再起動することである．その後，短い実マイク確認と，本人選択PPTXの作業用copyによる模擬講義で，partial認識，発話中の可視自動板書，遅延，canvas，overlay alignment，mouse優先，export及び原本不変を確認する．これらは現時点では未検証である．許可前に同じ試行を反復せず，このAppを再buildして新しいprivacy identityを作らない．本人受入前にGitHub Releaseを公開しない．

## 直前の再開点（2026年9月7日2時台）

　最新のコード修正commitは`fa62c73eada6d94daf094ac92c8032135fdd1e72`である．PowerPointの正確な返却objectとgeometryで結合済みの補助surfaceについて，黒帯又はnear-full-frameのアンチエイリアスに限り，黒白endpointの厳密pairに加えて98%以上の同方向変化を受理するようにした．中間的なendpoint coverageは従来どおり厳密pairを要求する．最初の広すぎる案は既存の否定test 2件を失敗させたため採用せず，狭い条件へ修正した．正方向と逆方向を含む新規回帰testを追加した．

　このexact commitはCore 250件・19 suite，App 480件・41 suite及び全26段階の`make verify`に合格した．native resultは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.07_02-55-42-+0900.xcresult`で，device run 542件，失敗・skip・expected failure 0件である．保存済みgate logのSHA-256は`52f26e2a1b2bad41b39197fb3ad54788d1ad6de061b4b54a3df94b5936b8ae38`である．最初の隔離環境実行はXcode cacheへの書込み拒否でstage 3に停止しており，成功とは数えない．通常のlocal Xcode権限で再実行した結果だけを合格証拠とする．

　commit `38d1482…`を基準に同じ最終policy修正と限定printを加えた固定診断Appは，生成した非privateのPowerPoint資料1件，windowed slide show，display 1台の条件で，managed開始，Stage A／B，challenge property復元，exact capture／semantic identity結合，calibration UIによるslide面の明示確定，日本語slide ID 257及び英語slide ID 258への意味的切替，切替後のVision解析，managed停止及び正常終了を完了した．canvas drag／確定とslide advanceは，利用者が本件に許可した限定local automationで合成資料だけへ実行した．これは手動の本人確認又は本人資料の検証ではない．role logのSHA-256は`df003b9dfed7aec6027de4bf45c45b9730c2028366270736ccacb602c2439f6e`である．証拠fileの詳細は`docs/build-verification.md`末尾にある．

　この時点の次作業はowner trial Appの作成であり，現在は上記のとおり完了した．本人模擬講義の結果はまだ得ていない．

## 直前の再開点（2026年9月7日0時台）

　最新source commitは`679cdfc2e83a957e0dd3808d4961f0958493a29a`である．Speech providerが一つの認識cycleへ一つのsegment IDを割り当て，同じcycleの2回の連続partialで安定した完結文だけを，既存のslide・canvas・analysis・identity・grounding・importance・public scene境界へ確定結果前に渡す経路を追加した．最新partial単独，未完文，疑問文，短文，低信頼，時刻逆転又はsegment不一致は公開しない．このsource経路は自動test済みであるが，実マイク及び可視板書では未検証である．

　現行commitで`make doctor`は失敗・warning 0件，`make local-setup`はCore 246件・19 suiteを含めて合格した．全26段階の`make verify`も合格し，native resultは`Test-LectureBoardAI-2026.09.07_00-39-21-+0900.xcresult`である．独立集計はApp 480件・41 suite，device run 542件，失敗・skip・expected failure 0件を示す．これは自動検証であり，live Speech，PowerPoint結合又は目視結果ではない．

　本人試用Appは`/Users/akiyama/Documents/LectureBoard AI Verification/Mock-Lecture-679cdfc/LectureBoard AI.app`へ，旧版を置換せず保存した．arm64 Release，Hardened Runtime，ad hoc署名，version 1.0.0，embedded commit `679cdfc2…`，UNBOUND tagである．executable SHA-256は`e5e3724d7a71dcc66bcf510bdfe4b798f149b5ba7b5b76b1372c0395e15962eb`，CDHashは`66efe7417d2cd38911d9fadbab269bd7bf8efc2e`で，buildとのbyte一致及びstrict署名を確認した．macOS sessionがロック中だったため，このAppは起動していない．次はロック解除後，このexact pathを通常起動し，まず文字起こし開始を1回だけ行ってpartial受信とcrashしないことを確認する．画面収録の再登録やTCC resetは行わない．

　直前の固定2666761 App再試行では，Speech権限callbackのMainActor継承による`EXC_BREAKPOINT`を確定した．commit `bb05ac8…`で権限・audio・認識結果callbackのactor入口を修正した．その修正Appの通常起動を準備した時点でロックを検出し，入力前に停止してexact processを終了した．したがって，権限又は画面収録の問題と推定して設定を繰り返さない．

## 直前の再開点（2026年9月6日23時台）

　省エネの段階1調査を実施した．固定2666761 Appの通常起動で文字起こしを1回開始し，8秒間「開始中」を観測後に停止した．TCCはLectureBoard AI自身を対象とするマイク許可要求を記録したが，許可付与・Speech要求・実認識は未確認である．sourceでは認識開始・停止のuser actionをsingle-flightにし，開始待ち・確定待ちの重複要求を抑止した．対象AppSlideIdentityIntegrationTestsの35件が23-40-58 xcresultで合格した．この修正は固定試用Appへまだ反映していない．次はマイク許可状態を本人が確認した後，固定Appの通常起動経路で認識開始を1回検証する．画面収録の再登録やTCC resetを繰り返さない．

　本人試用は管理スライドショー開始に失敗し，文字起こし開始時にTCCで終了した．exact AppのInfo.plistにSpeech利用目的が存在する一方，crash reportは説明欠落とChatGPTのresponsible processを記録する．通常起動へ変えた後は起動だけを確認しており，修正成功とは扱わない．本人は発話中の即時板書を明示し，全体開発の段取り整理を求めた．次の実行計画案と段階別合格条件は[development-plan-ja.md](development-plan-ja.md)にある．現在は段階0の計画整理で，次は通常起動と実マイクの部分認識の検証である．従来の黒白role challengeの調整を自動的に再開せず，構成の適合性を評価する．実装変更はまだしていない．

## 直前の履歴（2026年9月6日22時台）

　22時26分からの30分限定試験では，ロック解除後も管理開始がStage Bの補助窓判定で失敗した．タイトルバーと余白の影響を再現し，geometry照合済み経路に限定した黒白pair判定の中間修正を追加した．Core 242件・18 suite，App 476件・41 suite及び公開ツール境界testは合格したが，実機の役割確認は依然失敗する．最後の取得画像は1280×1410の縦長窓で大きな上下余白を含んだ．22時51分頃に実機試行を終了し，復元・終了と記録へ移った．実発話→可視板書は未到達であり，追加の閾値調整で成功扱いにしない．次は取得領域・補助窓の扱いを解決する必要がある．詳細はbuild-verification末尾を参照する．

　最新のworking treeはCore 240件・18 suite，App 476件・41 suiteの全テストに合格した．`make doctor`は失敗・警告0件，`make local-setup`と公開ツール境界テストも成功した．native resultは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.06_22-17-02-+0900.xcresult`である．正確な返却slide-show参照と現在の全ウィンドウ矩形の照合，及び補助窓のSDK contentRect内だけを使う指紋処理を追加した．矩形だけで対象を推定するfallbackではなく，既存pixel challenge，完全なinventory，freshness及び復元検査を併用する．

　統合診断Appはbuildできたが，GUI操作前にmacOSのロック状態を確認したため，修正後のmanaged challengeは未実行である．診断Appは通常終了し，PowerPointは合成資料1件・slide show 0件を確認した．次はMac本体でロック解除後，合成資料で管理スライドショーを検証する．画面収録の設定変更を繰り返さない．実発話から可視板書までの所有者模擬講義，通常起動の権限持続，最終26段階gate及び公開・公開後検証は未完了である．詳細は`docs/build-verification.md`末尾と指定Obsidian開発ノートにある．

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
- 本プロジェクトの「完成」は，検証済みarm64 App archive，正確なsource commit，checksum manifest，内容を含まないtest evidence，SBOM，provenance及び公開後の全5添付asset再取得検証を伴う，正式な公開`v1.0.0` GitHub Releaseの成立を指す．有料又は教育機関名義のApple Developer membershipは使用しないため，archiveはad hoc署名とし，Developer ID署名又はApple notarization済みとは表示しない．α版，β版又はRelease Candidateのapplication Releaseは公開しない．

## 3．現時点の成果物

　リポジトリには，macOSアプリの骨格，透明オーバーレイの試作，PowerPointウィンドウ検出，選択ウィンドウの連続取得実装，利用者確認式のスライド面切出し，現在frameの画面位置に基づくfail-closedなoverlay座標変換，切出し後の安定フレーム・視覚更新判定，160×90のRGB指紋による持続的内容更新判定，post-baseline coarse候補又はpending dense候補に限定した最大2回のone-shot sample経路，安定した視覚フレームを対象とするVision文字・矩形解析，長辺640ピクセル以下のRGBラスタと筆跡候補解析，正規化占有領域の構築，端末内認識を必須としnetwork fallbackを許さないApple Speech一言語文字起こし，文脈判断コア，ベクトル板書モデル，空白配置試作，単体テスト，英語・日本語を同一ファイルに収録したREADME，設計文書，GitHub Actions，公開前検査が含まれる．

　2026年9月1日現在，現行schema 11 sourceの中核Swift packageは153テスト・15 suite，ネイティブmacOS Appは259テスト・30 suiteがMac上で通過している．最終監査と文書同期後のcurrent treeに対する全14段階の`make verify`も23時50分頃から23時51分頃JSTに合格した．complete-gate native result bundleは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult`であり，authoritative total 259，failed 0，skipped 0，expected failure 0である．生成したarm64 runtime executableのSHA-256は`a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9`，ad hoc CDHashは`7a60426b1fb628f6fd3dce9b1c3516092d5a799a`であり，strict bundle検査へ合格したが，Developer ID署名，hardened runtime及びnotarization済みではない．自動gateはlive schema 11 bounded-fresh確認，動的入力又はmouse inkの証拠ではない．この結果pointerはgate後の文書限定変更であり，commit前の文書及び公開検査は個別に再確認して合格した．142 Core／251 App時点のschema 10 gate及びそれ以前のgateは，各時点のsourceに関する履歴証拠として保持する．

　2026年9月6日16時56分頃から17時00分頃には，後続のdocumentation-inclusive working treeがCore 235件・18 suite，native App 455件・40 suite及び全26段階の`make verify`に合格した．native result bundleは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.06_16-56-29-+0900.xcresult`である．このtreeは，最大8秒の端末内音声認識cycle，4秒のfinal待機，bounded audio tail，callback mailbox及びrestart backoff，保守的なgrounding parser，idle時のscreen-position候補とfresh exact-window再検査，並びにapplicationと文字起こしを分けた実行時診断を含む．これは未commit treeの自動test結果であり，実microphone，managed PowerPoint，利用者確認式canvas，PowerPoint上の可視自動板書，owner-selected PPTX受入，Hardened Runtime配布archive又はGitHub公開の証拠ではない．

　このdecoder-hardening後runtimeを，旧固定Appを置換せず，`LectureBoard AI Schema 11 Decoder Hardened Verification.app`としてbyte-identicalに固定した．executable SHA-256は`a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9`，ad hoc CDHashは`7a60426b1fb628f6fd3dce9b1c3516092d5a799a`であり，strict complete-bundle署名検査に合格した．固定pathの対象なしpreflight report `LectureBoard-Runtime-Schema11-DecoderHardened-FrozenApp-Preflight-2026-09-01.json`のSHA-256は`36dce0ffe83c11edbfc3990b16eee645e608fb174777330131c453d766d376d8`であり，画面収録preflightのbefore／after `authorized`，permission要求なし，matched window 0件，snapshot 0件，安全な`windowNotFound`，report生成及び自動終了だけを確認した．

　最初のcurrent static試行は，stableかつ十分な大きさのnew又はchanged slideshow windowが現れないとしてruntime起動前に停止した．続くpassive `--verify-only`は，exact editing windowがfrontmostかつAccessibility-focusedではないとして入力なしで停止した．strict `--exit-exact-slideshow`はexact titleとwindow ID `31785`へ結合し，Escapeを正確に1回だけ送ってAccessibility上の消失を確認したが，期限内にCore Graphics上の消失とediting windowの安定復元を同時確認できず，runtime及びreportなしでfail closedとなった．その後のpassive検査は，exact Core Graphics window 1件，exact Accessibility window 1件，frontmost及びfocusedを入力なしで確認した．明示的に1回へ限定したretryだけを行い，staticを完了した．この経過はslideshow window lifecycleの遅延又は再利用と整合するが，root原因を確定したものではない．

　成功した30秒static reportのSHA-256は`d018faf503ada46eefe0af0ac97f64cca7394cf690b6b2153b1614955ebc2a80`，helper sidecarのSHA-256は`bd22de08bae4a7fafa3e4b37024b7eeca8b34f5184e0ddab3267075de47c02da`である．116 snapshots，301 frames，すなわちnew 2及びrepeat 299，stable frame 1，content revision 0，最終Vision `completed`，semantic identity `unavailable`及びslide change 0を記録した．diagnostic full-frame canvasを用い，overlay metadataは1 snapshotだけ`mapped`となったが，production overlayは描画されず，目視alignmentも検証していない．

　60秒dynamic reportのSHA-256は`c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c`である．extra又はreuseなしの6 revision event，最終revision後のVision完了，source `coarseSignificantVisualChange` 5件及び`continuousDenseIdleRepeat` 1件，`boundedFreshSample` 0件，230 snapshots，599 frames，すなわちnew 15及びrepeat 584，stable frame 6，semantic identity `unavailable`並びにslide change 0を記録した．別途保存したoperator-captured helper sidecarのSHA-256は`5c7b0c73a8f059187f9319c2e681995e2e6a91042c5163bb821bf30bd37e488f`であり，8秒間隔の6入力と各input window内のrevision attributionを支持する．ただし，sidecarはruntime reportへ暗号的に結合されておらず，release-grade provenanceではない．これは当該固定buildのvisual content update証拠であるが，決定的なexact-input証明，意味的slide transition又はbounded one-shot pathのlive成功証拠ではない．

　single-stroke reportのSHA-256は`70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1`，helper sidecarのSHA-256は`518c60746850c40a6e428704eda2af834eaa95240b9efcb2d117ebf8f69c1aed`である．116 snapshots，301 frames，すなわちnew 27及びrepeat 274，aggregate phaseに対応するcontent revision 2件，最終Vision `completed`，semantic identity `unavailable`及びslide change 0を記録した．revision sourceは`continuousDenseNew`及び`continuousDenseIdleRepeat`であり，`boundedFreshSample`ではない．before及びafter-erase画像はSHA-256 `2dcc102c64a42bf50345e769c05528c16497a98ae60b9b421cc74324479e67f4`でbyte-identical，after-ink画像はSHA-256 `e0dbffd2e02423e64efb119ac62d31ea25b9503981589c1940308c790b865c91`で，赤い線1本を目視できる．これは当該固定buildのpixel上の手書き及び復元と，aggregate timingの証拠に限る．意味的又は入力ごとのink／erase分類，既存ink認識，AI板書rendering，利用者確認式canvas，visible overlay alignment，semantic slide identity又はlive `boundedFreshSample`は未検証である．

　16時17分の全14段階`make verify`は119 Coreテスト及び217 Appテスト時点の履歴証拠である．123件及び218件への変更後に行った最初の後続試行は，sandboxがSwift module cacheへの書込みを拒否したためCore manifestの計画段階で停止した．この失敗を成功証拠には数えない．

　その後の通常実行で，`make doctor`は失敗0件・warning 0件，`make local-setup`は成功し，Core 123件・15 suiteも通過した．さらに，当時のschema 9 sourceは23時02分から23時03分JSTに全14段階の`make verify`へ合格し，その結果を反映した文書を含む状態でも23時09分から23時10分JSTに同じ全14段階へ再度合格した．Core 123件・15 suite，native App 218件・25 suite，署名なしnative build，arm64 ad hoc runtime buildとstrict bundle署名，画面収録permissionを要求しない起動smoke及び公開前検査が全て成功した．最終native result bundleは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_23-09-45-+0900.xcresult`であり，authoritative total 218，failed 0，skipped 0，expected failure 0である．

　固定保存したschema 9 Appの直接実行では，post-fix idle continuityと4回の制御入力に対応する4 content revisionsを確認したが，identityは`unavailable`であり，overlay mappingは一度も成功していない．さらに2026年9月1日の限定診断では，見えるmouse strokeと消去後の視覚的復元を確認した．これらは固定schema 9 build固有の証拠であり，現行schema 11，意味的又は入力ごとのink分類，既存ink検出，利用者確認式canvas又はproduction renderingの証拠ではない．

　取得開始・停止・error・一覧更新・選択変更，frame順序，視覚更新，解析取消し及び古い解析結果の排除は，制御可能なfakeとnative画像fixtureによる回帰testで固定している．選択したPowerPoint窓については，ScreenCaptureKit窓ID，所有PID及び完全一致bundle identifierを取得開始まで固定し，重複，再利用又は所有者変更時にfail-closedで停止する．Coreには，同じpresentation session token及びslide IDが2回連続したときだけ基準又は切替を確定し，中断をまたいだ切替を推定しないtrackerがある．Appは，provider観測の対象，capture session及び順序を検査する．候補確定中に届いたframeは取得件数へ計上した後に視覚解析から除外する．基準確立又は切替時には以前の解析及び板書sceneを破棄し，Appが識別観測を受理したlocal mach絶対時刻よりScreenCaptureKitの`displayTime`が厳密に後である`.new` frameが到着するまで解析を再開しない．Apple Speechの確定結果についても，識別境界以前又は境界後frameをAppが受理したlocal時刻以前に生成された結果を，MainActorでの処理順にかかわらず板書候補から除外する．識別境界後のframe gateは，`waiting`，`synchronized`及び`timedOut`を明示する．時間切れはgateを開かず，古い境界又は停止済みsessionの遅延timeoutはtokenで拒否し，後着の厳密に新しい`.new` frameだけが時間切れ状態から回復できる．この挙動は決定論的testで確認済みであるが，production identity providerを伴う実行時挙動は未検証である．

　公開macOS及びPowerPoint APIは，PowerPoint内部で描画される正確なスライド面矩形を公開しない．ScreenCaptureKitの`contentRect`は取得surfaceを表し，PowerPoint内部のslide subviewを表さない．このため，Appは正確な取得operationから得たwindow previewを固定し，利用者が表示中のスライド面だけをdragで囲んで明示的に確定する．切出しはsource上で幅32 pixel，高さ24 pixel及び面積1,024平方pixelを全て満たさなければならない．確定結果はcapture operation，正確なScreenCaptureKit window ID，source pixel寸法及び検証済みScreenCaptureKit surface geometryへ固定する．再取得，window不一致，pixel寸法不一致，下記の限定idle policy適用後も利用可能なsurface geometryがない場合，又は`contentRect`，scale factor若しくはcontent scaleの変更時には，確定結果，解析及び板書sceneを無効化する．idle surfaceの扱いはApple保証ではなく，live attachment観測前の暫定application policyである．検証済み`.idle`で`contentRect`，`scaleFactor`及び`contentScale`の3 keyが全て欠落する場合だけ，直前にlatchしたsurface geometryを不変visual payloadの切出しへ再利用する．3 keyが全て揃う場合は，直前geometryとの完全一致をcurrent geometryとして受理する．一部欠落，不正形式，矛盾，non-idle，直前geometry欠落，又は直前output寸法とpayload寸法の不一致はfail closedとし，後続の`.new` frameまでrepeat geometryのpoisonをlatchする．画面位置は別の限定規則に従い，valid current `screenRect`を優先し，present malformed値を拒否し，key欠落時だけprior validated矩形を候補として引き継ぐ．修正前schema 9 reportは限定された失敗classを確認した．修正後の限定fixed-path実行は18件のidle repeatをまたいでcanvasを`confirmed`に保ち，post-fix live continuityを確認した．ただし，reportは実attachmentの全欠落と完全一致tupleを区別する証拠を保存しておらず，key欠落時のproduction overlay，実attachment形状及び他のPowerPoint表示modeでの一般性は未検証である．

　画面上の位置は，surface geometryと混同せず，ScreenCaptureKit `screenRect`から別の値として取得する．attachment内の矩形は`CGRect`，矩形型の`NSValue`及びdictionary representationを受理し，有限で正の幅・高さを要求する．複数displayでは負のglobal originも正当な値として受理する．verified idle repeatはsample自身のvalid `screenRect`を優先し，keyが存在するのに不正なら画面位置を空にする．key自体が欠落する場合に限り，prior validated矩形を候補として引き継ぐ．production表示とlease更新は，候補とは独立に，frontmostの正確なPowerPointに属するon-screen layer 0 exact windowをその時点で再取得し，current Core Graphics boundsの各辺が候補と2 point以内で一致し，手前の重複windowがない場合だけ許可する．このため，移動，resize，focus喪失，window消失又はocclusion後にprior候補だけで表示を継続しない．使用可能な位置がない場合も，確認済みcanvas及び視覚解析を直ちに破棄せず，overlayだけを非表示にする．これらは合成attachment及び制御可能なeligibility testによる実装証拠であり，実ScreenCaptureKitの`screenRect`向き，単位，idle時のkey欠落及び可視overlayは未検証である．

　確認済みcanvasからoverlay表示矩形への変換は，capture operation，正確なwindow ID，完全一致するsurface geometry，出力pixel寸法及びcurrent frame sequenceへ固定する．canvasのpixel矩形が`contentRect`の範囲内にあることを確認し，`scaleFactor`及び`contentScale`を用いてframe-carried validated screen-position候補へ対応付ける．丸め誤差として認めるのは出力1 pixel以内に限る．続いて，`CGDisplayBounds`のQuartz global座標から`NSScreen.frame`のAppKit座標へ変換し，対象矩形を完全に含む検証済みdisplayが正確に1件である場合だけ，click-through panelをその矩形へ表示する．production表示には，意味的slide identityとcurrent visual grounding，frontmostの正確なPowerPoint PID・bundle，1件だけのon-screen layer 0 exact window，その時点で再取得したCore Graphics boundsとの各辺2 point以内の一致及び手前の重複window不在も要求する．idle key欠落でprior候補を引き継いだ場合もこの再検査を省略しない．証拠の欠落，古いoperation・window・frame，surface又は出力寸法の不一致，display境界の横断若しくは複数displayへの曖昧な包含，明示的非表示，focus・Space変更又はcapture cadenceから独立したlease失効ではfail-closedで非表示にする．板書sceneが空，canvas未確定，識別quarantine中，又は識別境界後の新規frame待機中にも表示しない．既定identity providerは`unavailable`であるためproduction表示を許可しない．

　capture開始時には，demo用の板書sceneだけでなく，既に表示されているfull-display demo panelも明示的に隠す．これにより，production capture中に旧demo windowだけが残る経路を防ぐ．座標変換，window移動に伴う再配置，new delivery又は利用可能なprior候補のない`screenRect`欠落時の非表示と回復，verified idle key欠落時の候補引継ぎ，停止時の非表示及びdemo panel遮断は，合成geometryと制御可能なoverlayを用いたnative App testで確認済みである．実PowerPoint上の見た目の一致，idle key欠落，window移動・resize，複数display，full-screen，発表者表示，scale factor，panel z-order及びclick-through入力は，まだ動作確認していない．

　`.complete`及び`.started`だけをnew delivery，`.idle`だけをrepeatとして扱う．`SCFrameStatus`の欠落，不正形式，未知値，`.blank`及び`.suspended`，不正sample並びに変換失敗ではrepeat可能なpayloadを破棄し，Appへ順序付きcontent unavailable境界を通知して，後続の`.new` frameまで視覚・板書経路を閉じる．`.stopped`は固定文言のterminal capture errorとして停止処理へ進む．`scaleFactor`はSDK文書の範囲である1以上4以下だけを受理する．確定前はcapture delivery件数だけを更新し，安定・内容指紋，Vision，raster候補，占有領域又は板書配置へ画像を渡さない．確定後は，切り出したスライド面だけから全ての視覚指紋及び解析入力を生成する．

　粗い視覚差分又はdense内容更新が候補状態へ入った時点で旧解析を無効化する．dense fingerprintの欠落又は不正も旧解析を直ちに無効化し，valid dense fingerprintのないcoarse confirmed frameでは解析を開始しない．baselineへ戻った後も，current frameの再解析が完了するまで板書提案を閉じる．意味的なslide，canvas又はcapture境界では現在の板書文脈を更新し，境界以前の発話を再提案しない．占有領域が空の解析結果も板書配置を許可しない．capture終了時には最新安定frame，解析及び板書sceneを消去する．

　文字起こしはApp側とApple provider側の二重generation guardを用いる．意味的なslide又は一時的なcapture-content unavailable境界でproviderを停止し，旧callback及び旧segmentを拒否する．利用者の開始要求が継続している場合だけ，current identity，canvas，post-identity frame gate及びcurrent visual analysisが全て再びreadyとなった後に自動再開する．利用者の停止，canvas境界及びcapture終了は再開要求を消去する．この挙動は決定論的testで確認したが，実microphone挙動は未検証である．capture開始時にはdemo sceneを消去し，capture中又はcapture provider停止処理中にはdemo生成を許可しない．これらは制御可能なprovider及びnative fixtureで確認した安全境界であり，実PowerPoint，live canvas精度，microphone又はoverlay alignmentの検証結果ではない．

　runtime検証reportの現行形式はschema 11である．schema 6はスライド面状態，schema 7はoverlay mapping状態及び拒否理由，schema 8は`slideCanvasConfirmationMode`，schema 9はbounded canvas failure理由，schema 10は9種類の`captureFailureSource`及び21種類の公開`captureSCStreamErrorCode`を追加した．schema 11は，正の`contentRevisionCount`ごとに，最新revisionのordinal，最初のqualifying stream observationのmach絶対時刻，確定mach絶対時刻及び5種類のbounded sourceを記録する．current schemaでcountが負，countとeventが不整合，又は時刻が0若しくは逆転する場合はfail closedでdecodeしない．特に負数を0へ丸めてeventなしとして受理しない．schema 1からschema 10は追加eventを無視し，当時のcounter semanticsを保持する．terminal capture failureについては，sample stopped，delegate error，inactive stream及びstart failureが一つの同期routerへ入り，最初のeventだけを採用する．画像，認識文字列，座標，display ID，window title，入力時刻，raw error domain，raw numeric code，description又は`userInfo`は保存しない．schema 11のintervalはdetector evidenceの範囲であり，それ自体は意味的slide identity又は入力との因果を証明しない．

　runtime専用の`--confirm-full-frame-canvas` flagは，実frameが1件以上届いた後に，そのframe全体を診断目的で明示的に確認する．flagを指定しない通常動作は従来どおり利用者確認式であり，自動確認しない．frameが届かないまま待機期限を迎えた場合は，固定文言の専用failure `captureFrameUnavailable`を記録する．この診断経路による確認は，利用者がスライド面を確認した証拠ではなく，PowerPoint UI除外，overlay alignment又はproduction renderingの証拠にもならない．

　実行時証拠は，ビルドごとに分離する．過去のschema 1ビルドをCodexの許可下で直接起動した40秒の動的検証では，372フレーム，安定スナップショット6件及び画像差分イベント5件を記録した．当時の実装は，この5件を旧`slideChangeCount`欄へ入れていたが，画像だけではスライド同一性を断定できないため，確認済みスライド切替と解釈してはならない．

　その後のschema 2対応済み・意味修正前ビルドによる別の40秒の動的検証では，373フレーム，安定スナップショット6件，旧方式の画像差分イベント5件及び内容更新2件を記録した．レポート`runtime-dynamic-content-revision-2026-08-30.json`のSHA-256は`704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`である．これはcaptureとschema 2メタデータ生成に関する当該ビルド固有の履歴証拠であり，現行ソース又はスライド同一性の検証結果ではない．

　意味修正後のschema 3では，Coreが粗い画像差分を`.significantVisualChange`と呼び，Appが安定した視覚・内容更新へ計上し，画像だけから`slideChangeCount`を増やさない意味を確立した．schema 3 buildについて，動的slide又はmouse手書きのlive成功reportは記録されていない．schema 4は独立slide識別tracker，schema 5は識別境界後のframe同期状態，schema 6はスライド面状態，schema 7はoverlay mapping状態，schema 8はcanvas確認provenance，schema 9はcanvas失敗・無効化理由，schema 10はcapture終端分類，schema 11はcontent revision evidence intervalを追加する．いずれのschema変更も，それ自体では実PowerPointの意味的識別，live coarse-fresh確認，スライド面特定精度又はoverlay alignmentを証明しない．

　画面がロックされた状態で行ったschema 7の診断試行では，正確なPowerPoint windowを1件選択したが，capture frameは0件であった．試行は`captureFrameUnavailable`としてfail-closedで終了し，診断用全frame確認へ到達しなかった．これは正確なwindow選択と0-frame failure診断の実行時証拠であり，schema 7又は後続schemaにおけるlive frame取得，利用者確認式canvas，overlay mapping・alignment・rendering，動的slide又はmouse inkの成功証拠ではない．

　その後，DerivedData内のschema 8 runtime executableを直接起動した15秒のlive静的exact-window診断は成功し，window ID 13577から152件のnew frame，stable frame 1件，Vision `completed`，text 39件，rectangle 14件，`strokeCandidateRegions` 69件及びoccupied region 3件を記録した．reportは`diagnosticFullFrame`，canvas `confirmed`，overlay mapping `mapped`，identity `unavailable`，content revision 0件及びslide change 0件を記録した．external verification directory内のreport `LectureBoard-Runtime-Schema8-ExactWindow-Static-2026-08-31.json`のSHA-256は`593cc70cd666498c8d68cd9f3b8156b617c45d066cc955992106c5c1e18a8b84`である．これは，明示flagで取得window全体を診断用canvasとして用いたdirect verifier文脈の静的capture及びmetadata生成の証拠である．利用者確認式canvasの精度，PowerPoint UI除外，overlayの目視alignment又はproduction rendering，動的slide切替，mouse ink及び意味的slide identityは未検証である．

　過去の実PowerPoint読取り専用probeでは，PowerPointから継承される`window.id`が`nil`であり，意味的なslide IDを取得対象の正確なwindow IDへ照合できなかった．現行sourceは，この問題を弱い名称，列挙順又は近似geometry fallbackで回避せず，利用者が明示的に開始するmanaged workflowを実装した．PowerPointが返した正確なslide-show objectを保持し，windowed show typeだけを受理し，そのobjectへの短い可逆的なrole challengeによって新規の正確なScreenCaptureKit windowを特定し，property復元後にApp bindingを確立してから，同じobjectからslide ID及びindexを読む．one-shot，session，tombstone，取消し及び遅延cleanup境界には決定論的testがある．通常のpassive取得は引き続きAutomationを要求せずidentity `unavailable`となる．実PowerPointに対するApple Event実行，managed exact-window binding，意味的slide transition及びcleanupの一連のlive挙動はまだ未検証である．固定schema 9診断で確認した見えるmouse strokeを，意味的又は入力ごとのink分類，既存ink検出，現行source又はproduction canvasへ一般化してはならない．OCR文字列，座標，検出率，代表的資料，長時間運転及び実講義での有用性も未検証である．

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

　2026年9月1日の固定schema 9 five-stroke診断は，report `LectureBoard-Runtime-Schema9-MouseInk-2026-09-01.json`，SHA-256 `534a285e8f3830891c374746338aa361ab9ebf15cf1f4b199e686d1166b17cb7`を残した．20秒間に78 snapshots，80 frames，すなわち65 new及び15 repeat，4 content revisions並びにslide change 0件を記録した．手書き前と消去後の画像はbyte-identicalであり，手書き後には5 connected componentsがあった．これは見えるmouse strokeと消去後の視覚的復元だけの証拠であり，意味的又は入力ごとの分類，既存PowerPoint ink検出，production canvas，current schema 11又は別個のpost-erase revisionを検証しない．

　early aggregate failure reportのSHA-256は`44ed13c6b338a48fe5c92290c47a0ea8ae4fb105590ddddfa65a6a3d421eb5db`である．約12.068秒，60 frames，すなわち44 new及び16 repeat，3 revisionsの後に`captureFailed`となったが，schema 9はterminal sourceを保持していない．内部SC logから原因又は入力との因果を断定してはならない．content-mutation inputを送らない30秒static control reportのSHA-256は`60deb22f7c3561ed2c4b105ea69c0a9e5f196a6d5b7f6c42e6f23eb399b8c0fc`で，41 frames，すなわち4 new及び37 repeat，1 content revisionを記録した．したがって，false-positive-freeの証拠ではない．

　single-stroke reportのSHA-256は`494eb356282f8c49c9a57d7d67ec2e56cb31a22326da69d373b556f047332d45`であり，15 new，15 repeat，1 revision及び1 componentを記録した．five-stroke rerunのSHA-256は`7cadc164d28f534fe3620261eb26b14c20d7694b16216629d940d1c5e9870385`であり，66 new，15 repeat，4 revisions及び5 componentsを記録した．両runとも手書き前と消去後の画像はbyte-identicalだったが，別個のpost-erase revisionは記録しなかった．統合metadata audit `LectureBoard-Runtime-Schema9-Live-Checkpoint-Audit-2026-09-01.json`のSHA-256は`a547704072066e63047abaffc8e4bec0149be39760901e852236158d103ceff2`，image auditは`38552053c77b46d6a9eccb0cbde8f1baeef6faadf74bee9f57247e8e110d95a9`である．

　coarse及びdense detectorは同じ候補を3 observationで確定する契約を維持する．dense detectorのdifference thresholdは`0.08`，minimum changed-pixel fractionは`0.001`，persistence toleranceは`0`である．erase候補及び後述の4秒動的候補は必要な3件目を入力境界内で受けなかったため，thresholdを弱めなかった．現行sourceは，initial baselineを除くpost-baseline coarse候補又はdense pending候補に対してだけ，最大2回を約100 ms間隔で取得するbounded one-shot fresh sampleを実装した．typed opaque candidate token，capture operation，正確なwindow identity，stream anchor，canvas，semantic identity及びvisual continuityを全てguardし，provider busyの再待機も最大10回に制限する．coarse pathは同じCGImage raster pathによる等価性を確認してから，元detector fingerprintとexact tokenだけを進める．one-shot resultをcapture metrics，identity，post-identity frame gate及びoverlay provenanceへ混入させず，fresh-only解析からoverlayを再表示しない．これらは決定論的Core及びApp testに合格した．decoder-hardening後live runはcontinuous sourceだけで完了し，`boundedFreshSample`を1件も生成しなかったため，実PowerPointにおける`SCScreenshotManager` status・geometry attachment，timing及びfresh確認は未検証である．

　最新review済みignored helper sourceのSHA-256は`a91888a45f98414551bb96e6b38201e2faaa931f6462885f01024bdc9c319a2d`である．保存したreview済みarm64 binary `DriveExactPowerPointInk-Schema11-MachIntervals-Reviewed-2026-09-01`のSHA-256は`0910f1115b420443a8938111a296c4a16652bc258bd0c9a793813d98dc6f5ae3`である．helperは各入力のmach start／completionを保持し，各schema 11 revision intervalが一つの入力完了後かつ次入力開始前に完全に収まることを要求し，snapshot timestamp fallbackを用いない．production scheduleは60秒，8秒間隔6入力及び最終14秒である．GUI-free self-test，strict format，Swift 6 warnings-as-errors compile，20回反復及び独立reviewに合格した．decoder-hardening後の6入力runはこのstrict interval policyを満たしたが，すべてcontinuous stream sourceであり，helper成功からbounded fresh経路のlive動作を推定しない．

　別名固定した`LectureBoard AI Schema 11 Interval Verification.app`による30秒static report `LectureBoard-Runtime-Schema11-Interval-Static-2026-09-01.json`のSHA-256は`bbe4cb946125aa255c1dae3b77052cadfd3b63b330f22f4bd267c47b0b5bfbfd`である．117 snapshots，最大48 frames，すなわちnew 3及びrepeat 45，stable frame 1，baseline content revision 1，Vision `completed`及びslide change 0を記録した．入力なしで完了した固定buildのstatic metadata証拠であるが，false-positive-free，利用者確認式canvas又はproduction overlayの証拠ではない．

　同Appの4秒間隔dynamic stress report `LectureBoard-Runtime-Schema11-Interval-Dynamic-4s-Stress-Failed-2026-09-01.json`のSHA-256は`310461032606b6bb7a5ffd9b7e6090eb78bd64b499be53500feac0754a14aad1`である．155 snapshots，最大101 frames，stable frame 5，baselineを含むrevision 6及びslide change 0で終了したが，revision 2のevidence区間が次の入力をまたいだためstrict helperは不合格とした．最初の入力後にcoarse候補を2件得た後，3件目が次入力後まで届かなかったことが原因であり，6入力の個別検出成功とは扱わない．

　coarse fresh修正後かつdecoder hardening前のAppを`LectureBoard AI Schema 11 Coarse Fresh Verification.app`として固定した．arm64 executable SHA-256は`d829b0fdc01df309657e75afa348c36491b073d2f05b505d878a9021ce15f11e`，ad hoc CDHashは`9601c6f038ab0094402a44a4f5c18d6853310019`であり，strict bundle署名検査に合格した．固定path preflight report `LectureBoard-Runtime-Schema11-CoarseFresh-FrozenApp-Preflight-2026-09-01.json`のSHA-256は`fdd52a2e132592236f9faba865537872289eb1b98de58d91c7aeb53047e8300e`である．permission要求なし，before／after `authorized`，意図した`windowNotFound`及び自動終了だけを確認した．最初のstatic PowerPoint checkpointはlocked-session Accessibility preflightで停止し，入力又はreportを生成しなかった．これは履歴上の安全な失敗として保持する．

　session解除後，同じdecoder-hardening前固定Appはstatic，8秒間隔6入力dynamic及びsingle-stroke／eraseを別々に完了した．保存済みruntime reportのSHA-256は順に`76ccbb00397b46753cace26a471d871a0b5555b0e6447cef6cec819be22dcf53`，`87551e6151e206b4887ea82b3a26ddc3db204c575c82c788135e1cf9fd23b252`及び`6487fa3586454d893f3116868dc8098f48a7425d659f271e2a4d249d7c187289`である．single-strokeのbefore及びafter-erase画像はSHA-256 `21854ac6048ee58528dbd8a52fc914ca8a5b9e6399fc947f69bdcb37c88ef5b7`でbyte-identical，after-ink画像はSHA-256 `daf9a8ad32d5b3d9504d3036ebbc897b360de92d1e523df0b595105e11fe0946`である．これらは旧producer／decoder build固有の履歴証拠であり，上記decoder-hardening後Appのrunへ置き換えず，逆方向にも一般化しない．両固定App及び全report・画像をbuild，移動，置換又は改名しない．

## 4．最初にローカルで行うこと

```bash
make doctor
make local-setup
make test-app
make build-runtime
make test-runtime-launch-smoke
```

　`make test-runtime-launch-smoke`は，画面収録許可を要求せず，不正引数では診断を出してJSONを残さず自動終了し，対象窓なしではメタデータだけの失敗JSONを書いて自動終了することを確認する．通常の公開前検査`make verify`にも，Coreテスト，Appテスト，ネイティブビルド，runtimeビルド及びこの起動スモークを組み込む．

　次の作業は，次の順で進める．固定schema 8，schema 9，schema 10及びschema 11 App，report，helper sidecar及び画像はbuild，置換，移動又は改名せず，それぞれのbuild固有証拠として保持する．新規reportはsystem temporary directory内の一意なpathへ書き，内容を検証してからexternal verification directoryへcopyし，`cmp`とSHA-256で保存結果を確認する．

1. 合成資料を用いた固定診断Appでは，PowerPoint資料1件，windowed slide show，display 1台の条件で，managed object／window／slide binding，日本語・英語slide切替及び正常cleanupまで確認した．次は同じ範囲を新しいexact production owner trial Appと本人の作業用copyで確認する．
2. 合成資料のcalibration UIではslide面だけのdrag・明示確定とcurrent visual analysisを確認した．次は本人によるcanvas確認，production overlayの目視alignment及びclick-through mouse priorityを確認する．診断Appの結果を可視自動板書の成功証拠へ読み替えない．
3. 日本語と英語を別sessionで，microphoneからfinal transcript，current `SlideContext`，context engine，confirmed board scene及びvisible board renderingまで確認する．
4. 公開board sceneだけを含むsession JSON／SVG exportをlive検証し，元`.pptx`が不変であることをhash及びZIP整合性で確認する．
5. 正常停止，取消し，許可拒否，window終了及びcapture中断のcleanup／recoveryを同じ対応範囲で反復確認する．
6. 代表的な日本語・英語資料，privacy，accessibility，license，既知の制限，導入，初回講義及びtroubleshooting文書を完成させる．full-screen，Presenter View，複数display，日英code switching，physical pen tablet，speaker notes import及びcloud adapterはpost-v1範囲とし，成功を推定しない．
7. current treeで最終`make verify`を一度だけ実行し，Hardened Runtime，ad hoc署名，checksum manifest，内容を含まないtest evidence，SBOM及びcommit-bound provenanceを備える正確な`v1.0.0` archiveを生成して，App単位の「このまま開く」を検証する．
8. 正確なcommitとarchive SHA-256を示してユーザーの明示確認を得た場合だけpublic `v1.0.0` GitHub Releaseを作成し，再downloadしたartifactのbyte同一性，SHA-256，ad hoc署名，Hardened Runtime，metadata，導入及び起動を再確認する．

　確認結果は，成功・失敗を問わず`docs/build-verification.md`へ記録する．

## 5．次の実装単位

　選択したPowerPoint windowの連続取得からoverlayのfail-closedな座標変換までの決定論的基盤に加え，schema 10のbounded capture-terminal診断，schema 11のcontent revision interval，post-baseline coarse／dense候補に限定したbounded one-shot sample経路，8秒単位の端末内音声認識継続，保守的grounding及び誤解を避ける実行時診断を実装した．現行working treeはCore 235件・18 suite，App 455件・40 suite及び全26段階gateに合格する．decoder-hardening後の固定Appは，static exact-window capture，6件のdynamic visual revision及びsingle-stroke／eraseを完了した．operator-captured helper sidecarとの組合せは，8秒間隔の6入力windowへのattributionを支持するが，runtime reportへ暗号的に結合されておらず，release-grade provenanceではない．dynamic sourceはcoarse 5件及びcontinuous dense idle repeat 1件，stroke runもcontinuous dense 2件であり，`boundedFreshSample`をliveには通っていない．手書き後の赤線と消去後のbyte-identical復元はpixel証拠であり，意味的又は入力ごとのink／erase分類，既存ink検出，semantic slide identity，利用者確認精度，目視alignment，AI rendering又はproduction挙動の証拠ではない．

　exact-window-bound managed identity provider，条件付き文字起こし自動再開，公開scene限定JSON／SVG export及びno-fee release metadataは現行sourceへ実装済みであり，それぞれ対象testが合格している．2026年9月7日の固定診断Appは，合成資料に限ってmanaged開始，exact object／window／slide binding，明示canvas確定，2回の意味的slide切替，切替後解析，managed停止及び正常終了を完了した．この結果に対応する最終policyはcommit `fa62c73…`へ固定し，全26段階gateに合格した．production owner trial Appはcommit `c525ee4…`から上記exact pathへ固定し，通常起動と権限未付与時のfail-closed停止まで確認した．次は同じAppへ画面収録を1回許可し，前節2以降の実マイク・可視板書・本人資料受入を行う．全固定App及び証拠fileは移動・置換しない．

　AIやクラウドサービスを先に接続してはならない．まず，何を見て，どのスライドを対象とし，どこが空いており，どの発話を根拠としたかを観察・記録できる基盤を完成させる．

## 6．ローカルCodex開始時の指示文

　次の文章をローカルCodexの最初のメッセージとして使用できる．

```text
AGENTS.md，docs/local-codex-handoff-ja.md，ROADMAP.md，docs/build-verification.mdを最初に読んでください．次にmake doctorとmake local-setupを実行し，このMac上でネイティブmacOSアプリがビルドできる状態にしてください．発生した問題を一つずつ修正し，各修正にテストを追加し，検証結果をdocs/build-verification.mdへ記録してください．現段階で未検証の機能を，動作確認済みであるかのように記述しないでください．
```

## 7．公開方針

　公開リポジトリ`akiyama709/lectureboard-ai`は2026年8月29日に作成済みであるが，リポジトリが公開されていること自体は製品完成を意味しない．`main`ではプルリクエストと`LectureBoardCore tests`の成功が必須であり，force pushとブランチ削除は禁止されている．

　α版，β版又はRelease Candidateのapplication GitHub Releaseは公開しない．開発中の内部検証は，制御条件，代表条件，機能凍結後の最終artifactという順で進めるが，いずれも公開版又は完成とは扱わない．検証済み配布物を正式な公開`v1.0.0` GitHub Releaseとして一般取得可能にし，公開後の再ダウンロード，byte同一性，ハッシュ，ad hoc署名，Hardened Runtime，metadata，導入及び起動を確認した時点だけを完成とする．

　公開前には必ず次を実行する．

```bash
make verify
```

　`scripts/publish-to-github.sh`は初回リポジトリ公開専用であり，再実行しない．今後は作業ブランチをpushし，プルリクエストの必須CI成功後に`main`へ統合する．正式版は，最終candidateの受入検証後，バージョン整合性を確認し，`v1.0.0`タグ，リリースノート本文，ad hoc署名済みApp archive，SHA-256 checksum manifest，内容を含まないtest evidence，SBOM及びprovenanceの正確な5添付assetを備えたGitHub Releaseとして公開する．Developer ID署名又はApple notarization済みとは表示しない．外部公開に当たるpush，PR，タグ及びReleaseの実行は，それぞれ必要な確認を得て行う．

## 8．2026-09-07限定権限試験と次の再開点

　固定`c525ee4` Appについて，正確なマイク許可dialogをApp pathまで照合して許可し，Appleの説明が表示された音声認識許可は秋山さんがsystem UI上で許可した．文字起こし開始後は停止可能状態へ遷移し，Mac内蔵の`Kyoko`で非privateの合成文「地球環境問題では、地域ごとの違いが重要です。」をspeaker再生した．未知の認識本文は読み出さず，既知の2断片だけを照合したが，いずれもUI上で確認できなかった．入力は反復せず，停止を1回行うとidleへ戻り，Appはcrashしなかった．これはpermissionとstart／stop lifecycleの証拠であり，実発話認識，partial又はfinal，pre-final板書及び可視板書の成功証拠ではない．speaker出力のrouting又はecho cancellationを含む原因は未確定である．

　秋山さんの明示許可に基づき，画面収録設定に存在した有効な`LectureBoard AI.app`行1件を選択して削除し，固定identifierの再照会で行が消えたことを確認した．その後の正規設定windowが保持されず，Apple純正System Settings実行fileを直接起動した経路はmacOSのlaunch constraintにより`Code Signing Invalid`で拒否された．この直接起動経路は廃止し，再試行しない．問題report画像は`Mock-Lecture-c525ee4/system-settings-direct-launch-rejected-20260907.png`へ保存し，SHA-256は`421ce0ba2ca5ef29ea51bb11dd68753a419b43407cfdafd400458659aee0a169`である．System Settingsの失敗であり，LectureBoard AI又は設定dataを破損した証拠ではない．

　行削除後にApp本来の画面収録要求を1回だけ実行したが，設定windowは保持されなかった．秋山さんから反復する画面収録作業をskipする指示があったため，固定Appを正常終了して打ち切り，再起動しなかった．`c525ee4`固定Appは不完全な履歴証拠として保持し，受入候補には使わない．次は文書を同期したclean exact commitから最終候補を新しいpathへ1回だけ固定し，自動evidence，5 asset生成及びlocal verifyへ進む．本人がcore lecture受入を行う場合だけ，その最終候補へ画面収録を1回許可する．これをskipする場合，capture又は本人受入を成功扱いにせず，GitHub公開完了とも記録しない．

## 9．2026-09-07 exact-commit evidence固定失敗と所有group修正

　clean commit `ac81e0da02a0fe4e3ddd0a34103ea1663897ad7c`に対するisolated `evidence` transactionは，全26段階，Core 250件・19 suite及びApp 480件・41 suiteへ合格した．しかし，authoritative `.xcresult`の固定時に2候補が`pairDigestMismatch`で安全側に棄却され，旧上限2回のため3回目のcopy前に`copyAttemptsExhausted`で停止した．指定したevidence directoryは作成されず，asset，tag，push及びGitHub Releaseも作成していない．これはApp test失敗ではなく，exact-commit release evidence成功でもない．

　安定済みresultだけを使った最初の診断は原本とcopyのmanifestが一致したため，commit `3a72f61a526f5f09a6ed70ff013e0f3297ef343a`でcopy上限を一時的に4へ増やした．しかし，そのclean isolated `evidence`も全26段階の後に4候補を全て棄却し，600秒deadlineで停止した．evidence directory及びassetは作成されていない．これにより遅延更新の説明と再試行増加案は否定され，4回案は撤回した．

　新しい隔離checkoutで480件testを1回生成し，生成直後の`.xcresult`を保持してcopy前後の完全manifestを比較した．sourceは2回のmanifest間で不変だった．Xcodeがtemporary checkoutへ作成した全entryはowner 501・group 0であり，通常userが指定検証directoryへ`ditto --rsrc --extattr --acl`でcopyすると，path，bytes，mode，flag，ACL及び拡張属性は一致したまま，保存先entryのgroupだけが20になった．userはgroup 0を保存先へ再現できないため，配置依存の正常な所有group正規化をcopy破損と誤判定していたことが原因である．

　修正はprivate `.xcresult`専用digestのowner及びgroup fieldだけを正規化する．path，bytes，mode，flag，ACL及び拡張属性の完全一致は維持する．source／candidateのstability tokenはuid，gid，inode，size，mtime及びctimeを引き続き含むため，観測中の所有変更はfail closedとなる．copy上限は2回，deadlineは600秒へ戻した．新回帰testはcopy側のgroupだけを変更した場合の一致を要求し，mode変更及びcontent変更は別々に拒否する．既存の連続改変，期限，final seal，source／candidate改変，root／parent／path差替え及びquery分離境界も維持する．次はこの根本修正をclean commitへ固定し，そのexact commitで`evidence`を再実行する．
