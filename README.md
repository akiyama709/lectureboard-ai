# LectureBoard AI

**A context-aware macOS companion intended to add concise text and diagrams to the unused space of live PowerPoint slides.**

LectureBoard AI is an open-source research and development project for university lectures and online teaching. It is intended to listen to a lecturer, observe the current slide, estimate what is educationally important from context, and render a restrained digital-ink annotation layer. The lecturer should not need to say commands such as “write this on the board.”

> Status: **0.1.0-alpha repository scaffold**. The core context engine, vector board model, layout prototype, PowerPoint-window discovery, selected-window capture, stable visual/content-update paths, Vision and raster-candidate analysis, transparent-overlay prototype, and tests are included. The current source passes 80 Core tests and 89 native app tests on the development Mac. Its image-only classifier reports a stable `.significantVisualChange`; the app records that as a visual/content revision and does not claim that the PowerPoint slide identity changed. `slideChangeCount` is reserved for a future independent identity signal and remains zero in the current implementation. No live dynamic or mouse-ink result has yet been recorded for this semantic build; a dynamic attempt stopped before sending input because the ignored local automation helper could not establish a usable Accessibility window for the exact synthetic presentation. That result is not evidence that the production ScreenCaptureKit scanner or capture path failed.

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
- A metadata-only schema-3 runtime-verification path with content-revision and stroke-candidate counts; historical schema-1 and schema-2 reports remain decodable
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
- Identifying actual PowerPoint slide transitions from an independent slide-identity signal
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

A controlled current-build dynamic attempt produced no runtime report and sent no slide, keyboard, or mouse input. Core Graphics identified exactly one synthetic editing window, but PowerPoint exposed no usable Accessibility window for that presentation. A proposed PowerPoint-scripting fallback was not used after review found unresolved target-binding and time-of-check/time-of-use risks. Current-build dynamic and mouse-ink behavior therefore remain unverified.

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

　現段階は**0.1.0-alphaの初期リポジトリ**です．文脈判断の中核モデル，ベクトル板書モデル，空白配置の試作，PowerPointウィンドウ検出，選択ウィンドウの連続取得，安定した視覚・内容更新の判定，Vision及びラスタ候補解析，透明オーバーレイの試作，テストを収録しています．現行ソースは，開発用Mac上でCore 80件及びネイティブApp 89件のテストに合格しています．選択から取得開始まで，ScreenCaptureKit窓ID，所有PID及びPowerPointの完全一致bundle identifierを固定し，不一致又は重複時には取得を開始しません．画像差分だけからスライドの同一性を断定せず，Coreの`.significantVisualChange`をAppでは安定した視覚・内容更新として数えます．`slideChangeCount`は，将来の独立したスライド識別信号のために予約し，現行実装では増加させません．現行のruntimeレポートはschema 3であり，意味修正前のschema 2と機械的に区別できます．この意味修正後のビルドでは，動的スライド又はマウス手書きのライブ成功結果をまだ記録していません．動的検証の試行は，無視対象のローカル自動操作補助が対象合成資料の利用可能なAccessibilityウィンドウを確立できなかったため，入力送信前に停止しました．これは，本番のScreenCaptureKit窓検出又は取得が失敗した証拠ではありません．

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

　現行ビルドの動的検証では，Core Graphics上で合成資料の編集窓を1件へ特定しましたが，PowerPointが当該資料の利用可能なAccessibilityウィンドウを返しませんでした．補助はスライド，キーボード又はマウス入力を一度も送らず停止し，runtimeレポートも生成していません．PowerPointのスクリプト命令を使う代替案は，対象プロセスへの束縛及び照合から命令までの時間差に未解決の安全問題が見つかったため使用しませんでした．したがって，現行ビルドの動的挙動及びマウス手書き挙動は未検証です．

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
