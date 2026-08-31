# LectureBoard AI

**A context-aware macOS companion intended to add concise text and diagrams to the unused space of live PowerPoint slides.**

LectureBoard AI is an open-source research and development project for university lectures and online teaching. It is intended to listen to a lecturer, observe the current slide, estimate what is educationally important from context, and render a restrained digital-ink annotation layer. The lecturer should not need to say commands such as “write this on the board.”

> Status: **0.1.0-alpha repository scaffold**. The core context engine, vector board model, layout prototype, PowerPoint-window discovery, selected-window capture, user-confirmed slide-canvas crop, stable visual/content-update paths, Vision and raster-candidate analysis, transparent-overlay prototype, and tests are included. The current source passes 115 Core tests in 15 suites and 203 native app tests in 25 suites on the development Mac. It now contains a deterministic slide-identity tracker, a fail-closed app integration boundary, an explicit post-identity frame timeout that never admits stale or idle frames, a visual pipeline that remains closed until the user explicitly confirms the slide area, and deterministic fail-closed mapping from that confirmed crop to a current-frame overlay rectangle. A narrow schema-8 diagnostic has captured one static exact PowerPoint window from the fixed app's direct executable path, but it used explicit `diagnosticFullFrame` confirmation and reported semantic identity as unavailable. It is therefore not evidence of a user-confirmed canvas, visible overlay alignment, or production rendering. The production PowerPoint slide-identity provider, actual transitions, dynamic and mouse-ink behavior, microphone path, manual live canvas accuracy, visible overlay alignment, and independent LaunchServices launch remain unimplemented or unverified.

> Completion means publication of the public `v1.0.0` GitHub Release with a verified, signed, notarized, installable macOS artifact. The existing public repository and any alpha, beta, or release-candidate builds are intermediate milestones. See [`ROADMAP.md`](ROADMAP.md) for the validation gates.

## Design principles

- **Context before commands.** Importance is inferred from slide content, recent speech, novelty, repetition, discourse structure, emphasis, and the existing board.
- **Grounded output.** The app should not add facts that are absent from the slide, speaker notes, or transcript.
- **Stable board.** Confirmed annotations remain still so students can read and take notes.
- **Human priority.** Existing PowerPoint ink and the lecturer’s pen input always take precedence over AI annotations.
- **Local-first architecture.** Cloud providers are optional adapters, not hard-coded dependencies.
- **Japanese and English first.** These are initial target languages; the data model uses BCP 47 language tags and is designed for multilingual extension.

## Initial platform scope

- macOS 26 or later
- Apple silicon first
- Microsoft PowerPoint for Mac
- Target presentation environments, not yet runtime-verified: Zoom, Microsoft Teams, Google Meet, and classroom projection
- Target languages: Japanese, English, and a staged path toward Japanese–English code-switching

Focusing on one operating system is deliberate. Screen capture, transparent overlays, privacy permissions, live audio, and pen-tablet behavior are deeply platform-specific. The project will establish a dependable macOS experience before considering other platforms.

## What is already in this scaffold

- A native SwiftUI/AppKit application shell
- Screen-capture permission checking
- Discovery of visible PowerPoint windows with ScreenCaptureKit
- A compiled selected-window ScreenCaptureKit stream with stable-snapshot preview
- Fail-closed binding of the selected ScreenCaptureKit window ID, owning process ID, and exact PowerPoint bundle identifier through capture start
- Deterministic coarse luminance fingerprints and stable-frame/significant-visual-change classification
- Persistent content-update detection from dense 160-by-90 RGB fingerprints
- A user-confirmed slide-canvas boundary because public macOS and PowerPoint APIs do not expose the exact internal slide rectangle: the user drags around the visible slide on a frozen exact-window preview and confirms it explicitly
- Fail-closed binding of that confirmation to the capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry, with invalidation after restart, mismatch, missing geometry, or geometry change
- Current-sample geometry parsing for idle deliveries: the repeated visual payload is marked geometry-valid only when current geometry exactly matches its geometry; changed, missing, or invalid current geometry, or missing last-payload geometry, leaves the repeat without geometry and invalidates the canvas before visual processing; an idle sample without an image buffer inherits only fixed stream surface dimensions from the last frame; live idle-attachment behavior remains unverified
- Fail-closed ScreenCaptureKit status and continuity handling: only `.complete` and `.started` are new deliveries and only `.idle` is a repeat; missing, malformed, unknown, `.blank`, and `.suspended` statuses, invalid samples, and conversion failures clear repeatable content and require a later `.new` frame before visual processing resumes; `.stopped` is terminal; surface scale factor is accepted only in the SDK-documented inclusive range from 1 through 4
- A cropped visual pipeline in which stable/content fingerprints, Vision requests, raster candidates, occupied regions, and board-placement input are produced only from the confirmed canvas; before confirmation, only capture-delivery metrics advance
- Immediate invalidation of old analysis for coarse or dense visual candidates and for missing or invalid dense fingerprints; a confirmed coarse frame without a valid dense fingerprint does not start analysis, and baseline recovery remains closed to proposals until current-frame analysis completes
- Rejection of canvas rectangles smaller than 32 by 24 source pixels or 1,024 square pixels, plus a current-board-context boundary that prevents pre-boundary transcripts from being proposed after a semantic slide, canvas, or capture reset
- Fail-closed transcript-driven placement when visual analysis has no occupied regions, even if the analysis request itself completed
- Capture-end cleanup of the latest stable frame, analysis, and board scene
- A compiled Vision text/rectangle analyzer that runs on confirmed stable visual frames and content updates
- A native RGB raster path capped at a 640-pixel long edge, with deterministic `strokeCandidateRegions`
- Deterministic filtering, padding, and merging of normalized occupied regions across text, rectangles, and stroke candidates
- Capture-monitor counts and an occupied-region preview overlay
- A deterministic independent slide-identity tracker that requires two consecutive matching samples, discards continuity across interruptions, and does not infer transitions across presentation sessions
- An app-side identity-provider boundary that rejects wrong-target, wrong-session, and out-of-order observations; excludes candidate-period frames from visual analysis after delivery metrics are recorded; clears old analysis and board scenes at confirmed boundaries; and resumes analysis only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation
- A local speech-result boundary that rejects final transcript results emitted before an identity boundary, before the app locally accepts the post-boundary frame, or while the app is still waiting for that frame
- Independent App and Apple-provider transcription generation guards; semantic slide, canvas, and capture boundaries stop transcription and reject old callbacks, leaving transcription closed until the user explicitly resumes it; live microphone behavior remains unverified
- A token-bound post-identity frame gate that exposes waiting, synchronized, and timed-out states; timeout remains fail-closed, and a later strictly newer `.new` frame can recover the gate
- A metadata-only schema-8 runtime-verification path: schema 6 adds slide-canvas state, schema 7 adds overlay-mapping state and fail-closed rejection reasons without coordinates or display identifiers, and schema 8 distinguishes explicit `diagnosticFullFrame` confirmation from no diagnostic request; historical schema-1 through schema-7 reports remain decodable with safe defaults for absent metadata
- Current-frame ScreenCaptureKit `screenRect` parsing that accepts only validated rectangle representations, permits negative global display origins, and never inherits an older screen position for an idle repeat
- A deterministic overlay mapper bound to the capture operation, exact window, exact surface geometry, output dimensions, and current frame; it maps the confirmed crop through `contentRect`, `scaleFactor`, `contentScale`, and the current `screenRect`, converts one unambiguous containing display from Quartz to AppKit coordinates, and otherwise hides the production overlay
- A click-through transparent overlay window prototype that can render into the mapped production rectangle only after confirmed semantic identity and current visual grounding; frontmost exact-PowerPoint ownership, one exact layer-zero on-screen window, two-point edge agreement, front-to-back occlusion, manual suppression, content-unavailable and visual-change invalidation, focus and Space events, and an independently expiring lease all fail closed; the safe default unavailable identity provider cannot show production output; deterministic synthetic and app-integration tests cover these branches, but not live PowerPoint alignment or z-order
- A demo-scene boundary that clears demo content at capture start and disables demo generation while capture is active or capture-provider shutdown is in progress
- A selectable Japanese or English Apple Speech recognizer prototype
- A pure-Swift `LectureBoardCore` package containing:
  - transcript and slide-context models
  - contextual importance scoring
  - grounded board-intent classification
  - vector board-scene models
  - empty-region layout planning
  - unit tests
- Japanese and English UI resources
- GitHub Actions core CI, issue templates, security policy, contribution guide, architecture decisions, and citation metadata

## What is not yet claimed to work

- Reliable recognition of Japanese and English within the same utterance
- Parsing every PowerPoint object and speaker note
- Acquiring actual PowerPoint slide identity through a production provider and validating it against live transitions
- Automatic exact-window fresh-frame acquisition when a static slide produces only idle repeats after an identity boundary; explicit fail-closed timeout state is implemented and tested, but remains live-unverified with a production identity provider
- Reliable visual/content-update behavior across representative transitions and animations
- Independent LaunchServices startup, window reselection, and lecture-length reliability of continuous PowerPoint capture
- OCR correctness and coordinate accuracy of Vision text, rectangle, and occupancy analysis across representative decks
- Live accuracy of manual slide-canvas localization and PowerPoint-control exclusion across presentation modes, window sizes, displays, and representative decks; ScreenCaptureKit surface padding and `contentRect` mapping are also unverified
- Classifying raster stroke candidates as existing PowerPoint ink
- Robust empty-space segmentation on arbitrary slide designs
- Production-grade diagram generation
- Runtime microphone transcription, click-through overlay behavior, exact slide-canvas overlay alignment, and AI board rendering during a lecture; the coordinate path is implemented and deterministically tested, but its `screenRect` assumptions, visual accuracy, display behavior, z-order, and input non-interference remain live-unverified
- Cloud or local large-language-model integration
- Developer ID-signed, hardened, and notarized distribution

These are tracked in [`ROADMAP.md`](ROADMAP.md).

## Repository layout

```text
lectureboard-ai/
├── LectureBoardAI/                 # Native macOS application
├── Packages/LectureBoardCore/      # Platform-neutral models and logic
├── docs/                           # Requirements, architecture, privacy, ADRs
├── .github/                        # CI and issue templates
├── project.yml                     # XcodeGen project specification
└── Makefile
```

The documentation index is available at [`docs/README.md`](docs/README.md). Current verification limits are recorded in [`docs/build-verification.md`](docs/build-verification.md).

## Build

### Requirements

- macOS 26+
- Xcode 26+
- XcodeGen 2.46.0 (the locally verified version)

```bash
git clone https://github.com/akiyama709/lectureboard-ai.git
cd lectureboard-ai
make bootstrap
make test-core
make test-app
make build
make build-runtime
open LectureBoardAI.xcodeproj
```

`make build` is a compile-and-link check with code signing disabled; it does not produce the runtime artifact used for native behavior claims. `make test-app` runs the native app unit tests with local ad hoc signing. `make build-runtime` produces an arm64 Debug app with local ad hoc signing for controlled runtime checks. Ad hoc signing is neither Developer ID distribution signing nor notarization, and rebuilding can change the app's code identity even when its name and bundle identifier remain the same. macOS may therefore require Screen Recording permission again after a rebuild.

Direct executable runs under the Codex-authorized environment and an independently launched app through LaunchServices are separate verification paths. Standalone LaunchServices startup remains unverified. The public CI currently runs only the platform-neutral Core tests.

Two controlled dynamic reports remain as build-specific historical evidence. A schema-1 build recorded 372 frames and 5 image-difference events in the legacy `slideChangeCount` field. A later schema-2 but pre-semantic-correction build recorded 373 frames, the same 5 legacy heuristic events, and 2 content revisions; that report has SHA-256 `704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`. Neither report verifies slide identity or the current semantic build, and neither should be interpreted as five independently identified slide transitions.

Schema 3 established the corrected meaning in which image differences are content revisions rather than slide identity, but no successful live dynamic or mouse-ink report was recorded for a schema-3 build. Schema 4 added identity state and counters as metadata only, schema 5 added post-identity frame-sync state, schema 6 added slide-canvas state, and schema 7 added metadata-only overlay-mapping state and rejection reasons. Schema 8 is the current format and adds confirmation provenance so an explicit `diagnosticFullFrame` request cannot be mistaken for user confirmation. Schema-1 through schema-7 reports remain decodable with safe defaults. None of these schema changes itself provides live PowerPoint identity, user-confirmed canvas accuracy, or visible overlay-alignment evidence.

A current schema-8 fixed app completed one five-second direct-executable static diagnostic against exact PowerPoint window ID 13577 without requesting Screen Recording permission. It recorded 53 new frames, one stable frame, completed Vision analysis, `diagnosticFullFrame`, confirmed canvas state, metadata-only overlay state `mapped`, and identity `unavailable`, with zero content revisions and zero slide changes. This is narrow evidence for direct exact-window static capture and metadata production only. The full captured window was confirmed automatically for diagnostics; no user-confirmed slide canvas or production overlay was rendered or visually aligned.

A later read-only PowerPoint probe observed Automation preflight status `0`, one PowerPoint slide-show window, and two Core Graphics windows. PowerPoint's inherited `window.id` was `nil`, so the probe could not bind the semantic slide result to the exact captured window ID. No weaker name-, order-, or geometry-based fallback was adopted. The production identity adapter therefore remains unimplemented, and actual PowerPoint slide identity, current schema-8 dynamic behavior, same-slide mouse ink, independent LaunchServices launch, and live microphone behavior remain unverified. Manual canvas localization and UI-exclusion accuracy, visible overlay alignment and rendering, z-order, multiple displays, resizing, and click-through behavior also remain unverified.

## Continue development locally with ChatGPT Codex

The repository includes `AGENTS.md`, conservative project-scoped Codex settings in `.codex/config.toml`, a local toolchain diagnostic, and a Japanese handoff document. On the Mac that will run the prototype:

```bash
make doctor
make local-setup
make open
make codex
```

Then open this repository as a local folder in **Codex** in the ChatGPT desktop app and begin with [`docs/local-codex-handoff-ja.md`](docs/local-codex-handoff-ja.md). Regular ChatGPT history and Codex history are separate, so the repository documents are the durable project context.

## Test only the platform-neutral core

```bash
swift test --package-path Packages/LectureBoardCore
```

## Privacy

Lecture audio and slide content may contain unpublished research, personal information, or student contributions. The architecture therefore separates capture, transcription, contextual reasoning, and rendering through provider protocols. No API key or lecture data is committed to the repository. See [`docs/privacy-and-security.md`](docs/privacy-and-security.md).

## Contributing

Contributions are welcome after the initial architecture stabilizes. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and open an issue before starting a large architectural change.

## License

MIT License. See [`LICENSE`](LICENSE).

Microsoft PowerPoint and other product names are trademarks of their respective owners. This project is independent and is not affiliated with or endorsed by Microsoft, Apple, Zoom, Google, or OpenAI.

---

<a name="日本語"></a>
## 日本語

　**LectureBoard AIは，PowerPointを用いた講義中に，スライドの空いた領域へ文字や図形を自動板書することを目指す，macOS向けオープンソース研究試作です．**

　講師が「ここを板書してください」などの命令を発することなく使える構成を目指します．現在のスライド，発表者ノート，直前までの発話，反復，対比，因果関係，定義，発話上の強調，既存板書などから，何を学生に残すべきかを文脈的に判断する設計です．

　現段階は**0.1.0-alphaの初期リポジトリ**です．文脈判断の中核model，vector板書model，空白配置試作，PowerPoint window検出，選択windowの連続取得，利用者確認式のスライド面切出し，安定視覚・内容更新判定，Vision及びraster候補解析，透明overlay試作，testを収録しています．現行sourceは，開発用Mac上でCore 115件・15 suite及びnative App 203件・25 suiteのtestに合格しています．

　公開macOS及びPowerPoint APIは内部の正確なスライド面矩形を公開しないため，利用者が正確な取得windowの静止preview上で表示中のスライド面を囲み，明示的に確定します．確定結果はcapture operation，正確なwindow ID，source pixel寸法及び検証済みScreenCaptureKit surface geometryへ固定し，再取得，不一致，geometry欠落又は変更時に無効化します．切出しは幅32 pixel，高さ24 pixel及び面積1,024平方pixelを全て満たす必要があります．確定前はdelivery件数だけを記録し，確定後は切出し画像だけから全ての視覚指紋及び解析入力を生成します．

　overlay位置は，surface geometryとは別に，各frame自身のScreenCaptureKit `screenRect`から求めます．idle repeatでも過去の画面位置を継承しません．確認済み切出しを`contentRect`，`scaleFactor`，`contentScale`及びcurrent `screenRect`へ対応付け，対象を完全に含むdisplayが一意である場合だけQuartz座標からAppKit座標へ変換します．operation，window，surface，出力寸法若しくはcurrent frameが一致しない場合，又は位置証拠が欠落・矛盾・曖昧である場合は，production overlayだけを非表示にします．表示には，意味的slide identityとcurrent visual groundingに加え，frontmostの正確なPowerPoint PID・bundle，1件だけのon-screen layer 0 exact window，2 point以内のbounds一致及び手前の重複window不在を要求します．明示的な非表示，content unavailable，視覚変化，focus・Space変更及びcapture cadenceから独立したlease失効でも閉じます．既定identity providerは`unavailable`であるためproduction表示を許可しません．これらは合成geometry及び制御可能なApp統合testで確認した実装証拠であり，実PowerPoint上の見た目の一致又はz-orderを確認した結果ではありません．

　idle repeatのvisual payloadにgeometry provenanceを付与するのは，current sample attachmentのgeometryが直前visual payload geometryと完全一致する場合だけです．current geometryの変更・欠落・不正，又は直前geometryの欠落時は，geometryなしのrepeatとしてdelivery件数だけを記録し，視覚処理前にcanvasを無効化します．image bufferがないidle sampleでは固定stream surface寸法だけを直前frameから継承します．`.complete`・`.started`だけをnew，`.idle`だけをrepeatとして扱います．`SCFrameStatus`の欠落，不正形式，未知値，`.blank`及び`.suspended`，不正sample並びに変換失敗はrepeat可能なpayloadを破棄し，Appへcontent unavailable境界を通知して，後続の`.new` frameまで視覚・板書経路を閉じます．`.stopped`は固定文言のterminal capture errorです．`scaleFactor`はSDK文書の範囲である1以上4以下だけを受理します．実ScreenCaptureKitのidle attachment及びdrop配送挙動は未検証です．

　粗い視覚差分又はdense内容更新が候補状態へ入った時点，若しくはdense fingerprintが欠落・不正となった時点で旧解析を無効化します．valid dense fingerprintのないcoarse confirmed frameでは解析を開始せず，baseline復帰後もcurrent frameの再解析完了まで板書提案を閉じます．意味的なslide，canvas又はcapture境界では旧発話と板書候補を新しい文脈で再提案せず，占有領域が空の解析結果も板書配置を許可しません．capture終了時には最新安定frame，解析及び板書sceneを消去します．capture開始時にはdemo sceneを消去し，capture中又はcapture provider停止処理中はdemo生成を許可しません．

　文字起こしはAppとApple providerの二重generation guardを用います．意味的なslide，canvas又はcapture境界でproviderを停止し，旧callback及び旧segmentを拒否します．利用者が明示的に再開するまで文字起こしを閉じたままとします．独立slide識別tracker，post-identity fresh-frame gate及びschema 8 metadataは実装されていますが，production identity providerは未実装です．schema 6はcanvas状態，schema 7は座標・display IDを含まないoverlay mapping状態及び拒否理由，schema 8は診断用`diagnosticFullFrame`と診断要求なしを区別する確認provenanceを追加します．schema 1からschema 7までは履歴形式として読込可能です．現行schema 8による限定的な静的exact-window取得は確認済みですが，実PowerPointのslide identity，動的挙動，利用者確認式canvas精度，microphone，mouse手書き，visible overlay alignment及びLaunchServices独立起動は未検証です．

　本プロジェクトの完成は，検証済みで署名・notarization済みのインストール可能なmacOS配布物を伴う，公開`v1.0.0` GitHub Releaseの成立を意味します．既存の公開リポジトリ並びにα版，β版及びRelease Candidateは中間段階です．検証ゲートは[`ROADMAP.md`](ROADMAP.md)に示します．

### 当面の対象

- macOS 26以降
- Apple silicon搭載Macを優先
- Microsoft PowerPoint for Mac
- 対象予定であり，実行時未検証の環境：Zoom，Microsoft Teams，Google Meet，教室投影
- 初期の対象言語：日本語，英語，および段階的な日英混在対応

### 基本原則

- 音声コマンドではなく，講義文脈から重要性を判断する．
- スライド，発表者ノート，発話に根拠のない事実を付け加えない．
- 一度確定した板書をむやみに動かさない．
- 講師によるPowerPoint上の手書きをAIより優先する．
- ローカル処理を基本とし，クラウドAIは交換可能な任意アダプターとする．
- 日本語と英語を初期の対象言語とし，内部ではBCP 47言語タグを用いる．

### 制御された実行時検証の限界

　過去のschema 1ビルドでは，40秒間に372フレームと画像差分イベント5件を旧`slideChangeCount`欄へ記録しました．その後のschema 2対応済み・意味修正前ビルドでは，別の40秒間に373フレーム，旧方式の画像差分イベント5件及び内容更新2件を記録しました．後者のレポートSHA-256は`704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`です．いずれも特定ビルドに限る履歴証拠であり，スライド同一性又は現行の意味修正後ビルドを検証した結果ではありません．5件を確認済みスライド切替と表現してはなりません．

　現行schema 8の固定Appは，保存先のexecutableを直接起動する5秒の静的診断において，画面収録許可を要求せず，正確なPowerPoint window ID 13577からnew frame 53件，stable frame 1件及び完了したVision解析を記録しました．reportは`diagnosticFullFrame`，canvas `confirmed`，metadata-only overlay mapping `mapped`，identity `unavailable`，content revision 0件及びslide change 0件でした．これは，direct executable文脈における静的exact-window取得とmetadata生成だけの限定的な証拠です．取得window全体を診断用に自動確認しており，利用者確認式canvas又はproduction overlayの表示・目視整列を確認した結果ではありません．

　その後の実PowerPointに対する読取り専用probeでは，Automation preflightが`0`，PowerPointのslide show windowが1件，Core Graphics windowが2件であることを確認しました．しかし，PowerPointから継承される`window.id`が`nil`であり，意味的なスライド情報を取得対象の正確なwindow IDへ照合できませんでした．名称，列挙順又は概略座標による弱いfallbackは採用していません．したがって，production identity adapter，実PowerPointのスライド同一性，現行schema 8の動的挙動，マウス手書き挙動及びLaunchServices独立起動は未実装又は未検証です．

　現行実装は，利用者が確認したスライド面だけを対象とする160×90のRGB指紋，長辺640ピクセル以下のRGBラスタ，`strokeCandidateRegions`，及び確認済みスライド面から透明overlay矩形へのfail-closedな座標変換を備えます．ただし，筆跡候補は既存PowerPointインクの確定分類ではありません．切出し，無効化及びoverlay座標変換には合成画像・geometry fixtureと制御可能なfakeによる実装証拠があり，上記静的診断では全取得windowを用いたmetadata-only mappingが`mapped`へ到達しました．しかし，実PowerPoint上の利用者確認式スライド面特定，操作UI除外，ScreenCaptureKit surface padding，`contentRect`，`contentScale`及び`screenRect`の対応，表示mode，window移動・resize，複数display，overlayの見た目の一致・z-order・click-through入力，OCR文字列，矩形・占有領域の座標精度，代表的な実用deck，animation，長時間実行，window再選択並びに独立したLaunchServices起動は未検証です．マイクによる文字起こし，動的slide，mouse手書き及びAI板書の講義中表示についても，今回の検証では確認していません．

### ビルド

```bash
git clone https://github.com/akiyama709/lectureboard-ai.git
cd lectureboard-ai
make bootstrap
make test-core
make test-app
make build
make build-runtime
open LectureBoardAI.xcodeproj
```

　`make build`は，署名を無効にしたコンパイル・リンク検査であり，ネイティブ動作確認に用いるアプリを生成する手順ではありません．`make test-app`は，ローカルのアドホック署名を用いてmacOSアプリの単体テストを実行します．`make build-runtime`は，制御された動作確認用としてarm64 Debugアプリをアドホック署名で生成します．アドホック署名はDeveloper ID配布署名又はnotarizationではありません．

　同じアプリ名及びbundle identifierであっても，再ビルドによりコードIDが変化し，macOSから画面収録の再許可を求められる場合があります．Codexの許可下で実行ファイルを直接起動する経路と，LaunchServicesを介して独立起動する経路は別の検証対象です．上記の履歴実測値は前者だけに該当し，後者は未検証です．公開CIが現在実行するのは，プラットフォーム非依存のCoreテストだけです．

### Mac上でローカル開発を継続する

```bash
make doctor
make local-setup
make open
make codex
```

　その後，新しいChatGPTデスクトップアプリのCodexで本フォルダを開き，[`docs/local-codex-handoff-ja.md`](docs/local-codex-handoff-ja.md)を最初に読ませます．通常のChatGPT履歴とCodex履歴は別であるため，`AGENTS.md`と引継ぎ文書を継続開発の正本とします．

### 現在の実装範囲と未実装範囲

　現在含まれる内容と，まだ完成を主張しない内容は，上記英語版及び[`ROADMAP.md`](ROADMAP.md)に明示しています．講義音声や未発表スライドを扱うため，プライバシー設計は[`docs/privacy-and-security.md`](docs/privacy-and-security.md)にまとめています．
