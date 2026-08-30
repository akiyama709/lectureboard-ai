# LectureBoard AI

**A context-aware macOS companion intended to add concise text and diagrams to the unused space of live PowerPoint slides.**

LectureBoard AI is an open-source research and development project for university lectures and online teaching. It is intended to listen to a lecturer, observe the current slide, estimate what is educationally important from context, and render a restrained digital-ink annotation layer. The lecturer should not need to say commands such as “write this on the board.”

> Status: **0.1.0-alpha repository scaffold**. The core context engine, vector board model, layout prototype, PowerPoint-window discovery, selected-window capture and Vision-analysis paths, transparent-overlay prototype, and tests are included. The current post-lifecycle-fix executable completed a five-second static synthetic PowerPoint run with 50 frames, one stable frame, and completed Vision analysis with maxima of 35 text observations, 9 rectangles, and 4 occupied regions. An earlier pre-lifecycle-fix executable completed one dynamic run with 220 frames, 5 stable frames, and 4 classified slide changes; that earlier run is calibration evidence, not runtime evidence for the current executable. These narrow runs do not establish OCR or coordinate accuracy, representative-deck coverage, lecture-length reliability, current dynamic-slide behavior, or standalone LaunchServices authorization.

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
- Deterministic frame fingerprints and stable-frame/slide-change classification
- A compiled Vision text/rectangle analyzer that runs on confirmed stable frames
- Deterministic filtering, padding, and merging of normalized occupied regions
- Capture-monitor counts and an occupied-region preview overlay
- A metadata-only runtime-verification path used for the narrowly scoped synthetic runs described above
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
- Reliable identification of the current slide across representative transitions and animations
- Independent LaunchServices startup, window reselection, and lecture-length reliability of continuous PowerPoint capture
- OCR correctness and coordinate accuracy of Vision text, rectangle, and occupancy analysis across representative decks
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

The direct executable run under the Codex-authorized environment and an independently launched app through LaunchServices are separate verification paths. The runtime figures above apply only to the direct Codex-authorized run; standalone LaunchServices startup remains unverified. The public CI currently runs only the platform-neutral core tests.

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

　現段階は**0.1.0-alphaの初期リポジトリ**です．文脈判断の中核モデル，ベクトル板書モデル，空白配置の試作，PowerPointウィンドウ検出，選択ウィンドウの連続取得・Vision解析経路，透明オーバーレイの試作，テストを収録しています．競合修正後の現行実行ファイルをCodexの許可下で直接起動した5秒間の静的な合成PowerPoint検証では，50フレーム，安定フレーム1件を観測し，Visionは完了状態へ到達しました．各計数で観測した最大値は，テキスト観測35件，矩形観測9件，占有領域4件でした．競合修正前の実行ファイルでは，別の動的runで220フレーム，安定フレーム5件，スライド変更4件を観測しましたが，これは現行実行ファイルの動的検証を意味しません．いずれも実講義で安定して使用できる完成版であることを意味しません．

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

　上記の数値は，同一の合成デッキを用い，現行実行ファイルと競合修正前の実行ファイルをそれぞれCodexの許可下で直接起動した2回の制御済みrunに限られます．OCR文字列の正しさ，矩形・占有領域の座標精度，代表的な実用デッキ，アニメーション，長時間実行，ウィンドウ再選択，独立したLaunchServices起動は未検証です．マイクによる文字起こし，クリック透過オーバーレイ，AI板書の講義中表示についても，今回の検証では確認していません．

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

　同じアプリ名及びbundle identifierであっても，再ビルドによりコードIDが変化し，macOSから画面収録の再許可を求められる場合があります．Codexの許可下で実行ファイルを直接起動する経路と，LaunchServicesを介して独立起動する経路は別の検証対象です．上記の実測値は前者だけに該当し，後者は未検証です．公開CIが現在実行するのは，プラットフォーム非依存のCoreテストだけです．

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
