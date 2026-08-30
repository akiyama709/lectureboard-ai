# LectureBoard AI

**A context-aware macOS companion intended to add concise text and diagrams to the unused space of live PowerPoint slides.**

LectureBoard AI is an open-source research and development project for university lectures and online teaching. It is intended to listen to a lecturer, observe the current slide, estimate what is educationally important from context, and render a restrained digital-ink annotation layer. The lecturer should not need to say commands such as “write this on the board.”

> Status: **0.1.0-alpha repository scaffold**. The core context engine, vector board model, layout prototype, PowerPoint-window discovery, selected-window capture, stable visual/content-update paths, Vision and raster-candidate analysis, transparent-overlay prototype, and tests are included. The current source passes 90 Core tests and 103 native app tests on the development Mac. It now contains a deterministic slide-identity tracker and a fail-closed app integration boundary, but no production PowerPoint slide-identity provider. For each accepted capture start, the default provider performs no Automation permission request or Apple Event and reports identity as unavailable once. Consequently, actual PowerPoint slide transitions and current schema-4 dynamic or mouse-ink behavior remain unverified.

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
- A compiled Vision text/rectangle analyzer that runs on confirmed stable visual frames and content updates
- A native RGB raster path capped at a 640-pixel long edge, with deterministic `strokeCandidateRegions`
- Deterministic filtering, padding, and merging of normalized occupied regions across text, rectangles, and stroke candidates
- Capture-monitor counts and an occupied-region preview overlay
- A deterministic independent slide-identity tracker that requires two consecutive matching samples, discards continuity across interruptions, and does not infer transitions across presentation sessions
- An app-side identity-provider boundary that rejects wrong-target, wrong-session, and out-of-order observations; excludes candidate-period frames from visual analysis after delivery metrics are recorded; clears old analysis and board scenes at confirmed boundaries; and resumes analysis only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation
- A local speech-result boundary that rejects final transcript results emitted before an identity boundary or while the app is still waiting for that post-boundary frame
- A metadata-only schema-4 runtime-verification path with identity state, sample count, continuity-break count, content-revision count, and stroke-candidate count; historical schema-1 through schema-3 reports remain decodable without identity metadata
- A click-through transparent overlay window prototype
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
- Fresh-frame resynchronization or explicit timeout/state handling when a static slide produces only idle repeats after an identity boundary
- Reliable visual/content-update behavior across representative transitions and animations
- Independent LaunchServices startup, window reselection, and lecture-length reliability of continuous PowerPoint capture
- OCR correctness and coordinate accuracy of Vision text, rectangle, and occupancy analysis across representative decks
- Cropping analysis to the slide canvas and excluding PowerPoint controls or other window UI
- Classifying raster stroke candidates as existing PowerPoint ink
- Robust empty-space segmentation on arbitrary slide designs
- Production-grade diagram generation
- Runtime microphone transcription, click-through overlay behavior, and AI board rendering during a lecture
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

Schema 3 established the corrected meaning in which image differences are content revisions rather than slide identity, but no successful live dynamic or mouse-ink report was recorded for a schema-3 build. Schema 4 is the current format and adds identity state and counters as metadata only; it does not itself provide live PowerPoint identity evidence.

A later read-only PowerPoint probe observed Automation preflight status `0`, one PowerPoint slide-show window, and two Core Graphics windows. PowerPoint's inherited `window.id` was `nil`, so the probe could not bind the semantic slide result to the exact captured window ID. No weaker name-, order-, or geometry-based fallback was adopted. The production identity adapter therefore remains unimplemented, and actual PowerPoint slide identity, current schema-4 dynamic behavior, and same-slide mouse ink remain unverified.

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

　現段階は**0.1.0-alphaの初期リポジトリ**です．文脈判断の中核モデル，ベクトル板書モデル，空白配置の試作，PowerPointウィンドウ検出，選択ウィンドウの連続取得，安定した視覚・内容更新の判定，Vision及びラスタ候補解析，透明オーバーレイの試作，テストを収録しています．現行ソースは，開発用Mac上でCore 90件及びネイティブApp 103件のテストに合格しています．選択から取得開始まで，ScreenCaptureKit窓ID，所有PID及びPowerPointの完全一致bundle identifierを固定し，不一致又は重複時には取得を開始しません．Coreには2回連続一致で基準又は切替を確定する独立スライド識別trackerがあり，Appには対象，session及び順序を検査して不一致を拒否するprovider境界があります．候補確認中のフレームは取得件数へ計上した後に視覚解析から除外し，基準確立又は切替時には以前の解析と板書sceneを破棄します．解析の再開には，識別観測をAppが受理したローカルmach絶対時刻よりScreenCaptureKitの`displayTime`が厳密に後である`.new`フレームを要求します．文字起こしについても，識別境界以前に生成された確定結果又は境界後の新規フレーム待機中に届いた確定結果を板書候補から除外します．ただし，実PowerPointから識別信号を得るproduction providerは未実装であり，静止スライドで新しい表示フレームが生じない場合の再同期又は明示的なtimeout状態も未設計です．既定providerは，受理した取得開始ごとに，Automation許可を要求せず，Apple Eventも送らず，識別不能を1回通知します．現行runtimeレポートはschema 4であり，識別状態，sample数及びcontinuity break数を内容非保持メタデータとして記録します．schema 1からschema 3までは履歴形式として読込可能ですが，識別情報は`unavailable`及び0として復号します．実PowerPointのスライド同一性，現行schema 4の動的スライド及びマウス手書きは未検証です．

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

　その後の実PowerPointに対する読取り専用probeでは，Automation preflightが`0`，PowerPointのslide show windowが1件，Core Graphics windowが2件であることを確認しました．しかし，PowerPointから継承される`window.id`が`nil`であり，意味的なスライド情報を取得対象の正確なwindow IDへ照合できませんでした．名称，列挙順又は概略座標による弱いfallbackは採用していません．したがって，production identity adapter，実PowerPointのスライド同一性，現行schema 4の動的挙動及びマウス手書き挙動は未実装又は未検証です．

　現行実装は，160×90のRGB指紋による持続的な内容更新判定，長辺640ピクセル以下のRGBラスタ，及び`strokeCandidateRegions`を備えます．ただし，筆跡候補は既存PowerPointインクの確定分類ではありません．スライドキャンバスの切り出し，PowerPointの操作UI除外，OCR文字列，矩形・占有領域の座標精度，代表的な実用デッキ，アニメーション，長時間実行，ウィンドウ再選択，独立したLaunchServices起動は未検証です．マイクによる文字起こし，クリック透過オーバーレイ，AI板書の講義中表示についても，今回の検証では確認していません．

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
