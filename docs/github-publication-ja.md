# 初回GitHubリポジトリ公開記録

想定公開先：`akiyama709/lectureboard-ai`

## この文書の位置付け

　本書は，2026年8月29日に公開ソースリポジトリを初めて作成した際の判断，確認及び手順を残す履歴文書である．公開リポジトリは作成済みであり，以下の初回公開コマンド及び`scripts/publish-to-github.sh`を再実行しない．

　この初回リポジトリ公開は，完成版の公開ではない．α版，β版，Release Candidate（RC）及び`v1.0.0`のGitHub Releaseはまだ公開していない．本プロジェクトの完成条件と正式公開手順は，[`v1-release-checklist.md`](v1-release-checklist.md)を正本とする．

## 1．初回公開時の判断

- [x] リポジトリ所有アカウントが`akiyama709`である
- [x] リポジトリ名を`lectureboard-ai`とする
- [x] Publicとして公開してよい
- [x] MIT Licenseでよい
- [x] 所属機関の知財・職務発明・ソフトウェア公開規程を確認した
- [x] 本プロジェクトに第三者の秘密情報が含まれていない
- [x] 使用した既存コード・画像・フォントのライセンスを確認した

## 2．初回公開時のファイル確認

- [x] READMEの「実装済み」と「未実装」が正確である
- [x] `.env`や秘密鍵がない
- [x] 実際のPowerPoint資料がない
- [x] 講義音声，学生データ，未発表原稿がない
- [x] 画像内に個人情報や著作物がない
- [x] `.DS_Store`と`.build`が除外されている
- [x] `swift test --package-path Packages/LectureBoardCore`が通る

## 3．初回公開時点のGitHub設定スナップショット

　次のチェック状態は初回公開時点の記録であり，現在の設定又は`v1.0.0`公開可否を証明するものではない．正式版公開時には現行設定を改めて検証する．

- [x] Default branchを`main`とする
- [x] Issuesを有効にする
- [ ] Discussionsは必要に応じて有効にする
- [ ] Private vulnerability reportingを有効にする
- [ ] Secret scanningを有効にする
- [ ] Dependabot alertsを有効にする
- [ ] Branch protectionまたはrulesetを設定する
- [ ] Pull RequestでCI通過を必須にする
- [ ] Force pushとbranch deletionを制限する

## 4．初回公開に用いた手順（履歴・再実行禁止）

　次のコマンドは，空のPublicリポジトリを初めて作成する場合の履歴である．対象リポジトリは既に存在するため，現在の開発又は正式版公開では使用しない．

```bash
cd lectureboard-ai
git init
git add .
git commit -m "Initial macOS-first LectureBoard AI prototype"
git branch -M main
git remote add origin git@github.com:akiyama709/lectureboard-ai.git
git push -u origin main
```

　HTTPSを使用する場合の当時の代替案は次のとおりであった．

```bash
git remote add origin https://github.com/akiyama709/lectureboard-ai.git
```

## 5．初回公開時のIssue候補

　次の一覧は初回公開時の候補であり，現在の実装状況を示すものではない．現状は[`AGENTS.md`](../AGENTS.md)，[`ROADMAP.md`](../ROADMAP.md)及び[`build-verification.md`](build-verification.md)を参照する．

- Implement live microphone transcription provider
- Implement ScreenCaptureKit PowerPoint window capture
- Implement Vision-based slide whitespace map
- Implement composite output window
- Implement human pen-ink layer
- Define evidence-constrained AI provider schema
- Evaluate Japanese-English code switching
- Add a distribution verification pipeline（当時案．現行の無償配布方針はADR 0013を参照）

## 6．当時のプレリリース案（未実施）

　初回公開時には`v0.1.0-alpha`というGitHub Release案があったが，実施していない．現行方針では，`v0.1.0-alpha`を含むα版，β版又はRCのGitHub Releaseは公開せず，最初のapplication Releaseを正式版`v1.0.0`とする．

## 7．初回公開スクリプト（履歴・再実行禁止）

　同梱の`scripts/publish-to-github.sh`は，初回リポジトリ作成時に，GitHub CLIで認証中のアカウントを確認するためのスクリプトである．現在のリポジトリ更新，作業ブランチのpush，PR又は`v1.0.0` GitHub Releaseには使用しない．

　誤実行時のローカル副作用を防ぐため，現行スクリプトは既存のGit checkout内，又は同名のGitHubリポジトリが存在する場合，`git init`，stage及びcommitより前に終了する．GitHub上の不存在を安全に確認できない場合も変更せずに終了する．これは履歴スクリプトを再利用可能にするものではない．

```bash
./scripts/publish-to-github.sh
```

　上記は履歴上の呼出し方を示すだけであり，再実行しない．通常の変更は作業ブランチ，Pull Request，必須CI及び`main`への統合によって行う．完成版のタグ及びGitHub Releaseを外部公開する直前には，別途，明示的な最終確認を得る．

## 8．完成版公開への移行

　`v1.0.0`では，公開予定コミットからHardened Runtimeを有効にしたarm64 Appを構築し，ad hoc署名，SHA-256 checksum manifest，内容を含まないtest evidence，SPDX SBOM及びcommit-bound provenanceを検証する．有料又は教育機関名義のApple Developer membershipは使用せず，Developer ID署名又はApple notarization済みとは表示しない．AppleのApp単位の「このまま開く」を用いる導入，初回起動及び対応機能を検証した後，正確なcommitとarchive SHA-256を示して明示的な最終確認を得る．公開`v1.0.0`の全5添付assetを再取得し，同一byte，署名，metadata，導入及び起動を再検証して証拠を記録した時点を完成とする．
