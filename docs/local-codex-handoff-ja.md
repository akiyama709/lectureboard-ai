# LectureBoard AI ローカル開発引継ぎ

更新日：2026年8月30日

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

　リポジトリには，macOSアプリの骨格，透明オーバーレイの試作，PowerPointウィンドウ検出，選択ウィンドウの連続取得実装，安定フレーム・視覚更新判定，160×90のRGB指紋による持続的内容更新判定，安定した視覚フレームを対象とするVision文字・矩形解析，長辺640ピクセル以下のRGBラスタと筆跡候補解析，正規化占有領域の構築，Apple Speechによる一言語文字起こし，文脈判断コア，ベクトル板書モデル，空白配置試作，単体テスト，英語・日本語を同一ファイルに収録したREADME，設計文書，GitHub Actions，公開前検査が含まれる．

　2026年8月30日現在，中核Swiftパッケージの98テスト及びネイティブmacOSアプリの110テストがMac上で通過している．AppKit，ScreenCaptureKit，Vision，Speech，AVFoundationを含む`arm64`アプリは，Xcode 26.6によるコンパイル・リンク，アドホック署名及び署名整合性検査に成功した．取得開始・停止・エラー・一覧更新・選択変更，フレーム順序，視覚更新，解析取消し及び古い解析結果の排除は，制御可能なfakeとネイティブ画像fixtureによる回帰テストで固定している．選択したPowerPoint窓については，ScreenCaptureKit窓ID，所有PID及び完全一致bundle identifierを取得開始まで固定し，重複，再利用又は所有者変更時にfail-closedで停止する．Coreには，同じpresentation session token及びslide IDが2回連続したときだけ基準又は切替を確定し，中断をまたいだ切替を推定しないtrackerがある．Appは，provider観測の対象，capture session及び順序を検査する．候補確定中に届いたフレームは取得件数へ計上した後に視覚解析から除外する．基準確立又は切替時には以前の解析及び板書sceneを破棄し，Appが識別観測を受理したローカルmach絶対時刻よりScreenCaptureKitの`displayTime`が厳密に後である`.new`フレームが到着するまで解析を再開しない．Apple Speechの確定結果についても，識別境界以前又は境界後フレームをAppが受理したローカル時刻以前に生成された結果を，MainActorでの処理順にかかわらず板書候補から除外する．識別境界後のframe gateは，`waiting`，`synchronized`及び`timedOut`を明示する．時間切れはgateを開かず，古い境界又は停止済みsessionの遅延timeoutはtokenで拒否し，後着の厳密に新しい`.new`フレームだけが時間切れ状態から回復できる．この挙動は決定論的テストで確認済みであるが，production identity providerを伴う実行時挙動は未検証である．

　runtime検証レポートの現行形式はschema 5であり，識別状態，識別境界後のframe同期状態，sample数，continuity break数，内容更新数及び筆跡候補領域数を，画像，認識文字列，座標，slide ID，資料path又はsession tokenを含まないメタデータとして記録する．schema 1からschema 4までは履歴形式として引き続き読込可能であり，欠落するframe同期状態は`notRequired`，欠落する識別状態及び追加計数は`unavailable`及び0として復号する．

　実行時証拠は，ビルドごとに分離する．過去のschema 1ビルドをCodexの許可下で直接起動した40秒の動的検証では，372フレーム，安定スナップショット6件及び画像差分イベント5件を記録した．当時の実装は，この5件を旧`slideChangeCount`欄へ入れていたが，画像だけではスライド同一性を断定できないため，確認済みスライド切替と解釈してはならない．

　その後のschema 2対応済み・意味修正前ビルドによる別の40秒の動的検証では，373フレーム，安定スナップショット6件，旧方式の画像差分イベント5件及び内容更新2件を記録した．レポート`runtime-dynamic-content-revision-2026-08-30.json`のSHA-256は`704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`である．これはcaptureとschema 2メタデータ生成に関する当該ビルド固有の履歴証拠であり，現行ソース又はスライド同一性の検証結果ではない．

　意味修正後のschema 3では，Coreが粗い画像差分を`.significantVisualChange`と呼び，Appが安定した視覚・内容更新へ計上し，画像だけから`slideChangeCount`を増やさない意味を確立した．schema 3ビルドについて，動的スライド又はマウス手書きのライブ成功レポートは記録されていない．schema 4は，この意味を維持したまま独立スライド識別tracker，App側のfail-closedな統合境界及び内容非保持の識別メタデータを追加した．現行schema 5は，識別境界後のframe同期状態を追加するが，それ自体は実PowerPointの識別又は自動fresh-frame取得を証明しない．

　実PowerPointに対する読取り専用probeでは，Automation preflightが`0`，PowerPointのslide show windowが1件，Core Graphics windowが2件であることを確認した．しかし，PowerPointから継承される`window.id`は`nil`であり，意味的なslide IDを取得対象の正確なwindow IDへ照合できなかった．名称，列挙順又は概略座標による弱いfallbackは採用していない．既定identity providerは，受理した取得開始ごとに，Automation許可を要求せず，Apple Eventも送らず，`unavailable`を1回通知する．したがって，production adapter，実PowerPointのslide identity，現行schema 5の動的スライド及びマウス手書きは未実装又は未検証である．OCR文字列，座標，検出率，代表的資料，長時間運転及び実講義での有用性も未検証である．

　画面収録の許可は起動文脈ごとに区別する．過去のschema 1・競合修正後実行ファイルをCodexの許可下から直接起動した経路ではpreflightが`authorized`であったが，LaunchServicesを介した同時期の別起動では`unknown`となり，許可要求を行わず`screenRecordingUnavailable`で終了した．これらは現行schema 5ビルド又は独立起動の確認結果ではない．既定の`make build-runtime`はビルドごとに`cdhash`が変わり得るアドホック署名であり，同じアプリ名とbundle identifierでも再許可が必要になる場合がある．再起動後の状態及び現行ビルドの独立起動は，まだ確認済みではない．

## 4．最初にローカルで行うこと

```bash
make doctor
make local-setup
make test-app
make build-runtime
make test-runtime-launch-smoke
```

　`make test-runtime-launch-smoke`は，画面収録許可を要求せず，不正引数では診断を出してJSONを残さず自動終了し，対象窓なしではメタデータだけの失敗JSONを書いて自動終了することを確認する．通常の公開前検査`make verify`にも，Coreテスト，Appテスト，ネイティブビルド，runtimeビルド及びこの起動スモークを組み込む．

　次の実機確認は，次の順で進める．

1. 意味的なスライド情報を，選択済みの正確なScreenCaptureKit window IDへfail-closedで結び付けられるproduction identity providerを実装する．PowerPointの`window.id`が`nil`である間は，名称，列挙順又は概略座標を代替照合に用いず，公開API又はPowerPoint更新で厳密な経路が成立するまで保留する．
2. exact-window one-shot取得を検討する場合は，stream frameとは異なるprovenance及びcapture epochを設計し，画像へ架空の`displayTime`を付けない．実装後も，production providerを伴う静止スライドで検証するまで自動再同期を確認済みと表現しない．
3. 現行schema 5ビルドを用いた制御済み動的スライド操作で，baseline，切替，中断，session変更，frame quarantine，frame同期の待機・時間切れ・回復及びruntimeメタデータを，将来のproduction provider完成後に検証する．
4. 同一スライド上のマウス手書きと消去について，持続的内容更新及び`strokeCandidateRegions`の狭い動作を検証する．候補を既存インク確定と一般化しない．
5. スライドキャンバスの切り出しとPowerPoint操作UIの除外を実装・検証する．
6. 実PowerPointの独立スライド識別結果と画像由来の内容更新を別々に校正し，その後に初めて`slideChangeCount`の実機精度を評価する．
7. まだ保存していない現行schema 5の検証対象アプリを固定保存先へ新たに用意した後，LaunchServicesから独立起動した場合の画面収録preflight及びMac再起動後の状態を確認する．
8. PowerPointウィンドウの終了，再選択，PowerPoint再起動及びディスプレイ再接続からの復旧を確認する．
9. 日本語，英語，日英混在，アニメーション及び長時間の代表的講義資料における視覚更新とスライド識別の精度を確認する．
10. OCR文字列，タイトル候補，矩形，占有領域及び赤枠座標の正しさを確認する．
11. 透明オーバーレイの位置，サイズ，クリック透過及びペンタブ入力を妨げないことを確認する．
12. 日本語及び英語のマイク認識，複数ディスプレイ並びにオンライン共有を確認する．

　確認結果は，成功・失敗を問わず`docs/build-verification.md`へ記録する．

## 5．次の実装単位

　選択したPowerPointウィンドウの連続取得，粗い輝度指紋による安定視覚判定，160×90のRGB指紋による持続的内容更新，Visionによる文字・矩形解析，長辺640ピクセル以下のRGBラスタ，`strokeCandidateRegions`，正規化占有領域，独立スライド識別tracker，App側のfail-closedな統合境界及び識別境界後の明示的timeout状態は実装され，Core 98件・App 110件のテストに合格している．ただし，現在は選択ウィンドウ全体を解析しており，スライドキャンバスを切り出さず，PowerPointの操作UIを除外していない．筆跡候補は既存インクの確定分類でもなく，座標精度も未検証である．

　production identity providerは，実PowerPointの意味的なslide IDを選択済みの正確なwindow IDへ結び付けられる公開経路が成立してから実装する．`window.id`が`nil`であった実測結果を無視して弱いfallbackへ進んではならない．このブロッカーと独立に進められる次の実装単位は，スライドキャンバスの分離及びPowerPoint UI除外である．自動fresh-frame取得を先に扱う場合は，stream frameとは異なるprovenanceを設けたうえで，現行schema 5ビルドによる実行時検証を別に行う．代表的な講義資料での検出率，認識内容，タイトル候補，矩形，占有領域及び赤枠座標の校正，LaunchServicesの許可境界，長時間運転と終了処理，既存インク検出及びより頑健な空白分析は，それぞれ別の検証項目として残す．

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
