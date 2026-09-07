# LectureBoard AI v1.0.0 公開前ユーザー受入確認

## 位置付け

　この確認は，公開予定の正確な`v1.0.0`候補を，プロジェクト所有者が自分で選んだPPTXで一度使用し，対応範囲の講義経路に重大な問題がないことをGitHub公開前に判断する必須gateである．正式受入の現在の状態は**未実施**である．旧owner-trial候補`f18c873…`，`e2c66af…`及び`926be08…`は，発話から確定板書が生じなかったため不合格とした．実partial信頼度，同文安定timer及び狭い空白への配置を修正した`7dd1c78…`は段階5の予備再試験待ちであり，この文書の実施前条件を満たす正式release候補ではない．この文書のcheck boxは予定と記録欄であり，実際の操作と証拠がない項目を完了扱いにしてはならない．

　この受入は，公開の承認とは別である．受入合格後も，正確なrelease commit及び最終ZIPのSHA-256を示したうえで，外部公開について別途明示承認を得る．

## 資料とプライバシーの境界

　使用するPPTXは秋山知宏さんが選ぶ資料であり，非公開内容を含む可能性がある．元のPPTXを上書きしない．受入時はMac上に専用の複製物を作り，その複製物だけをPowerPointで開く．LectureBoard AIのlocal providerだけを使い，PPTX，slide画像，音声，文字起こし又はexportをcloud provider，connector若しくは別のmodel contextへ送らない．

　PPTX，取得画像，録音，文字起こし及びsession exportをGitへ追加せず，GitHub Releaseへも添付しない．公開repositoryへ残すのは，候補commit，App／ZIPのdigest，環境，実施日時，合否及び内容を含まない不具合要約だけとする．元PPTX及び複製物のSHA-256値を記録する場合は，非公開のObsidian開発ノートだけに置く．

## 実施前の条件

- [ ] 合成PPTXによる視覚観測workflow，canvas，overlay，mouse priority，export及び取得停止の現行候補検証が先に合格している．
- [ ] 対象は，公開予定commitから生成したHardened Runtime・arm64・ad hoc署名の正確な候補Appである．
- [ ] 候補commit，App executable SHA-256及びZIP SHA-256を記録している．
- [ ] macOS及びPowerPointのversionが[`supported-environment.md`](supported-environment.md)の対象範囲内である．
- [ ] local displayは1台であり，PowerPointで開くpresentationは受入用複製物1件だけである．
- [ ] PowerPointの通常のfull screen又はwindow表示slide showを使う．Presenter View，multidisplay及びkiosk modeは対応範囲外である．
- [ ] 元PPTXの存在，byte size及びSHA-256を記録し，同じ内容の受入用複製物を作成した．
- [ ] 受入用複製物のAutoSaveを無効にし，元PPTXを閉じたままにしている．

## 権限確認

　画面収録，マイク及び音声認識の各表示を確認する．画面収録が許可済みなら，「画面収録を許可」を再度押さない．未許可の場合だけ1回要求し，システム設定で正確な候補Appを有効にしてから，同じpathのAppを終了・再起動する．再起動後も未許可なら要求を繰り返さず，受入を停止して不具合として記録する．

- [ ] 画面収録は再起動後に許可済みと表示され，PowerPoint window更新が有効になる．
- [ ] マイク及び音声認識は，文字起こしを開始する時点で許可済みになる．
- [ ] 許可dialog又はシステム設定が反復表示されない．

## 対応講義経路

1. 受入用複製物をPowerPointで開き，通常のfull screen又はwindow表示slide showを開始する．slide showはLectureBoard AIより先に開いていてもよい．
2. LectureBoard AIでPowerPoint windowを更新し，受講者に見せる正確なslide-show画面を1件選び，「この画面で板書を開始」を1回実行する．選択後にslide showを開いた場合は，windowを再更新して新しいslide-show画面を選び直す．
3. 選択した画面が受入用複製物の受講者向け表示であることを確認する．
4. frozen preview上で実際のslide canvasだけを選択・確定し，PowerPointのcontrol又は余白を含めない．
5. 少なくとも3枚の視覚的に異なるslideを通常の講義速度で進め，local visual epoch，visual analysis及びoverlayの追従を観察する．PowerPoint内部のslide ID又はindexの取得は合格条件としない．
6. 日本語又は英語のうち資料の主言語で約30秒，通常の模擬講義として自然に話す．命令用の定型句は用いない．一つの重要な宣言文を発話してから，その安定した内容に基づく板書がfinal transcriptより前にPowerPoint上へ現れるかを目視し，発話終了から可視化までの秒数を記録する．final transcript確定後に同じ板書が重複せず，文脈に根拠のある状態を保つことも確認する．少なくとも1件の自動板書がPowerPoint上に実際に見えることを目視確認する．
7. mouse又はtrackpadで短い手書き線を1本描き，AI overlayが入力を妨げず，人間入力が優先されることを確認する．
8. text，box，arrow又は簡単なdiagramが表示された場合，既存内容を覆わず，根拠のない内容を追加せず，読める間は安定していることを確認する．
9. 文字起こしを停止し，final transcriptが確定した後に，文字起こしが停止済みであることを確認する．
10. Appの取得を停止し，PowerPoint slide showが開いたまま通常操作できることを確認する．
11. 取得状態が停止済みであることを確認してから，lecture sessionをJSON及びSVGへexportし，slide画像，OCR全文，音声，文字起こし，window title又は非公開intentが含まれないことを確認する．
12. PowerPointでslide showを通常の方法で終了し，受入用複製物を保存せずに閉じ，元PPTX及び複製物のbyte sizeとSHA-256を実施前の値と比較する．

　実行時診断の`final`，座標変換済み，許可，描画要求済み又は正数の本番板書件数は，原因調査の補助であり，可視板書の代替証拠ではない．PowerPoint上で自動板書を1件も目視できなければ，診断値にかかわらず不合格とする．

## 合格条件

- [ ] 受講者に見せるものと異なるPowerPoint windowを取得していない．
- [ ] crash，停止不能，反復する権限要求又は残存する補助windowがない．
- [ ] 確定した安定視覚変化がlocal visual epochを更新し，analysis及びoverlayが現在の画面へ追従する．
- [ ] board内容はslide又はそのsessionの発話に根拠があり，利用者が読める間は不意に変化しない．
- [ ] 少なくとも1件の根拠ある板書がfinal transcript確定前に見え，発話終了から可視化までの時間を記録した．
- [ ] 命令用定型句なしの自然な模擬講義から，少なくとも1件の根拠ある自動板書をPowerPoint上で目視した．
- [ ] overlayはslide canvasへ整列し，既存内容とmouse入力を妨げない．
- [ ] JSON／SVG exportは表示可能なpublic board sceneだけを含む．
- [ ] 元PPTX及び受入用複製物のbyte sizeとSHA-256が実施前後で一致する．
- [ ] 非公開資料又は派生contentをrepository，GitHub又は外部serviceへ送っていない．

　一つでも満たさない場合は**不合格**であり，公開を進めない．再現条件と内容を含まない現象要約を記録し，修正後の新しい候補で最初から再実施する．

## 非公開記録テンプレート

```text
状態：未実施／合格／不合格
実施日時：
release commit：
候補ZIP SHA-256：
App executable SHA-256：
macOS：
PowerPoint：
資料言語：日本語／英語
slide枚数：
元PPTX SHA-256（Obsidianだけに記録）：
複製物・実施前SHA-256（Obsidianだけに記録）：
複製物・実施後SHA-256（Obsidianだけに記録）：
画面選択・板書開始：未実施／合格／不合格
canvas・overlay：未実施／合格／不合格
文字起こし・grounding：未実施／合格／不合格
発話終了からpre-final板書可視化まで（秒）：
final確定後の重複：未実施／なし／あり
mouse priority：未実施／合格／不合格
JSON・SVG export：未実施／合格／不合格
停止・cleanup：未実施／合格／不合格
内容を含まない所見：
総合判定：未実施／合格／不合格
```
