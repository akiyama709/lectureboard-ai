# macOSローカル開発手順

更新日：2026年8月30日

## 前提

- Apple silicon搭載Macを優先する．
- macOS 26以降を初期対象とする．
- Xcode 26以降を使用する．
- リポジトリの外にあるファイルへは，必要な場合だけ明示的にアクセスを許可する．

## 1．プロジェクトを配置する

　ZIP版を使用する場合は，Finderで展開し，例えば次の場所へ置く．

```text
~/Developer/lectureboard-ai
```

　公開GitHubリポジトリは作成済みであるため，次の方法で取得できる．

```bash
git clone https://github.com/akiyama709/lectureboard-ai.git
cd lectureboard-ai
```

## 2．ターミナルで状態を確認する

```bash
cd ~/Developer/lectureboard-ai
make doctor
```

　`make doctor`は環境を変更せず，macOS，CPU，Xcode，Swift，XcodeGen，Git，GitHub CLIの有無を報告する．

## 3．XcodeGenを用意する

　XcodeGenがない場合に限り，Homebrewを利用して次を実行する．

```bash
brew install xcodegen
```

　Homebrew自体がない場合は，先にHomebrewを導入するか，XcodeGenの公式配布方法を選ぶ．本リポジトリのスクリプトは，パッケージ管理ツールを無断でインストールしない．

## 4．テストとXcodeプロジェクト生成

```bash
make local-setup
```

　このコマンドは，中核テストを実行し，利用可能であればXcodeプロジェクトを生成する．

## 5．Xcodeで開く

```bash
make open
```

　初回は，XcodeのSigning & CapabilitiesでDevelopment Teamの選択が必要になる場合がある．通常のローカルデバッグビルドでは，まずコード署名を伴わない`make build`でもコンパイル確認ができる．

## 6．ChatGPTデスクトップアプリのCodexで開く

　Codex CLIが導入済みであれば，次だけで本フォルダを開ける．

```bash
make codex
```

　手動で開く場合は，次のとおりである．

1. 新しいChatGPTデスクトップアプリを開く．
2. 左上の選択からCodexを開く．
3. ローカルフォルダとして`~/Developer/lectureboard-ai`を選ぶ．
4. `AGENTS.md`と`.codex/config.toml`を確認してから，このプロジェクトを信頼する．
5. `docs/local-codex-handoff-ja.md`第6節の開始指示文を送る．

　通常のChatGPT会話履歴とCodex履歴は別であるため，プロジェクトの重要な文脈は`AGENTS.md`と引継ぎ文書を正本とする．

## 7．通常の変更をGitHubへ反映する前に

　公開リポジトリは既に存在する．通常の変更では，初回リポジトリ作成用の`scripts/publish-to-github.sh`を再実行せず，作業ブランチ，Pull Request，必須CI及び`main`への統合を用いる．ローカルでは，少なくとも次を確認する．

```bash
make verify
gh auth status
gh api user --jq .login
```

　最後の出力が`akiyama709`であることを確認する．外部へのpush，Pull Request又はRelease公開は，その作業の承認範囲に従う．

## 8．完成版v1.0.0を公開する場合

　本プロジェクトの完成は，検証済みarm64 App archive，正確なsource commit，SHA-256，SBOM及びprovenanceを含む公開`v1.0.0` GitHub Releaseを再取得し，最終検証を完了した時点である．α版，β版及びRelease Candidateのapplication Releaseは公開しない．現時点では，いずれのGitHub Releaseも公開していない．

　正式版公開時には，[`v1-release-checklist.md`](v1-release-checklist.md)を用いて，公開予定コミットと同一の成果物，必須CI，Hardened Runtime，ad hoc署名，新規MacでのApp単位の「このまま開く」による導入及び起動，説明文書，checksum，SBOM及びprovenanceを検証する．Developer ID署名又はApple notarization済みとは表示しない．外部公開の直前に，正確なcommitとarchive SHA-256を示して明示的な最終確認を得た後，`v1.0.0`タグ及びGitHub Releaseを公開し，公開成果物を再取得して最終検証する．

　初回公開手順の履歴は[`github-publication-ja.md`](github-publication-ja.md)に残しているが，そのコマンド及びスクリプトは再利用しない．
