# macOSローカル開発手順

更新日：2026年8月29日

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

GitHub公開後は，次の方法へ切り替えられる．

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

## 7．GitHubへ公開する前に

```bash
make verify
gh auth status
gh api user --jq .login
```

最後の出力が`akiyama709`であることを確認する．公開は次で行う．

```bash
./scripts/publish-to-github.sh
```

このスクリプトは，公開直前に確認を求める．
