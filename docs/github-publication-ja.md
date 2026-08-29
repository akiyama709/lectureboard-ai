# GitHub公開チェックリスト

想定公開先：`akiyama709/lectureboard-ai`

## 1．公開前の判断

- [x] リポジトリ所有アカウントが`akiyama709`である
- [x] リポジトリ名を`lectureboard-ai`とする
- [x] Publicとして公開してよい
- [x] MIT Licenseでよい
- [x] 所属機関の知財・職務発明・ソフトウェア公開規程を確認した
- [x] 本プロジェクトに第三者の秘密情報が含まれていない
- [x] 使用した既存コード・画像・フォントのライセンスを確認した

## 2．ファイル

- [x] READMEの「実装済み」と「未実装」が正確である
- [x] `.env`や秘密鍵がない
- [x] 実際のPowerPoint資料がない
- [x] 講義音声，学生データ，未発表原稿がない
- [x] 画像内に個人情報や著作物がない
- [x] `.DS_Store`と`.build`が除外されている
- [x] `swift test --package-path Packages/LectureBoardCore`が通る

## 3．GitHub設定

- [x] Default branchを`main`とする
- [x] Issuesを有効にする
- [ ] Discussionsは必要に応じて有効にする
- [ ] Private vulnerability reportingを有効にする
- [ ] Secret scanningを有効にする
- [ ] Dependabot alertsを有効にする
- [ ] Branch protectionまたはrulesetを設定する
- [ ] Pull RequestでCI通過を必須にする
- [ ] Force pushとbranch deletionを制限する

## 4．初回公開コマンド

GitHub上で空のPublicリポジトリ`lectureboard-ai`を作成した後，ローカルで次を実行する．

```bash
cd lectureboard-ai
git init
git add .
git commit -m "Initial macOS-first LectureBoard AI prototype"
git branch -M main
git remote add origin git@github.com:akiyama709/lectureboard-ai.git
git push -u origin main
```

HTTPSを使用する場合：

```bash
git remote add origin https://github.com/akiyama709/lectureboard-ai.git
```

## 5．初期Issue候補

- Implement live microphone transcription provider
- Implement ScreenCaptureKit PowerPoint window capture
- Implement Vision-based slide whitespace map
- Implement composite output window
- Implement human pen-ink layer
- Define evidence-constrained AI provider schema
- Evaluate Japanese-English code switching
- Add signed and notarized alpha release pipeline

## 6．初回リリース

最初のGitHub Releaseは，実PowerPoint取得と実音声入力が統合されるまでは`v0.1.0-alpha`とし，完成品と誤解されない説明を付す．

## 7．誤アカウント公開防止

同梱の`scripts/publish-to-github.sh`は，GitHub CLIで現在認証されているアカウントが`akiyama709`であることを確認する．一致しない場合は，リポジトリを作成せず停止する．

```bash
./scripts/publish-to-github.sh
```

このスクリプトは公開直前に再度確認を求める．所属機関の知財・ソフトウェア公開規程の確認が終わるまでは実行しない．
