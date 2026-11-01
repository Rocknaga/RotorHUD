# RFTelem — Rotorflight テレメトリウィジェット (EdgeTX / TX16S MK3)

Rotorflight 搭載ヘリのテレメトリを、EdgeTX の Color LCD ウィジェットとして表示する Lua ウィジェット。
ヘッドスピードを中心に、電圧・電流・バッテリー残量・ガバナー状態などを 1 画面にまとめ、
ARM 警告・フライトログ・バッテリープロファイル選択・音声と振動のアラームを備える。

> **免責事項**: 本ウィジェットの使用は**自己責任**で行ってください。使用または使用できなかったことによって生じた損害 (機体・送信機・SD カードの損傷、墜落、人身・物損事故など) について、作者は一切の責任を負いません。表示やアラーム (音声・振動) の正確さは保証されません。飛行前の点検と機体状態の確認は、操縦者自身の責任で行ってください。

## 特長

- **ヘッドスピード中心のダッシュボード**: Volt (最小値)・Vcel・Current (最大値)・Bec volt (最小値)、
  Governor、Flight (MM:SS)、Profile/Rate、Battery バー (% / mAh)、Throttle バー (% / ℃)
- **接続状態に応じた画面切替**: 待機 ("Waiting for connection") → ダッシュボード。
  `ARMD` ≠ 0 で全画面の ARM 警告、切断後はフライトログ。切替時はワイプ演出
- **再接続で全リセット**: 最大・最小値とフライトタイマーを初期化してから表示
- **接続直後のバッテリープロファイル選択**: FC の 6 プロファイルから選んで送信 (実機の FC では未検証)
- **設定メニュー**: 全画面時に ENTER/タップで Rotorflight 設定 (公式 RF2 ツール)・ExpressLRS・バッテリープロファイルを
  ウィジェット内で開く (DISARM 中のみ)
- **アラーム (音声 + 振動)**: 危険 / 注意 / 情報の 3 段階。声は VOICEVOX 由来の 6 種から選択
- **3 テーマ** (color / mono / cyan) と、機体名と同名の PNG による機体画像表示
- **検証環境**: EdgeTX Companion シミュレータ用スクリプトと、画面なしのテスト (`tools/luatest`) を同梱

## 動作環境

| 項目 | 内容 |
|---|---|
| 対象送信機 | RadioMaster TX16S MK3 (800×480) |
| 対象ファームウェア | EdgeTX v2.12.0 "Queen Anne's Revenge" (edgetx-tx16smk3) |
| 通信 | CRSF / ExpressLRS |
| FC | Rotorflight (センサー名は後述) |
| ウィジェット名 | `RF Telem` (`/WIDGETS/RFTelem/main.lua`) |

## インストール

1. `sdcard/` の中身を、送信機の SD カードのルートへコピーする
   (`WIDGETS/RFTelem/main.lua`、`IMAGES/`、`SOUNDS/` がそれぞれ対応する)。
   Windows では、手動コピーのかわりに `scripts/deploy.ps1` が使える:
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Target E:\`
   - `-Target` は SD のルート。`auto` なら、EdgeTX の SD カードらしいリムーバブルドライブを自動検出する
   - `-Tools` で診断ウィジェットも、`-DryRun` でコピー対象の一覧のみ
   - 追加・上書きのみで、SD 上のファイルを削除しない
   - 送信機を USB ストレージモードにするか、カードリーダーで SD を挿してから実行する
2. ラジオ側: ウィジェット画面 → 空きゾーン長押し → Add Widget → `RF Telem`。
   フル表示は 1 ゾーン全画面レイアウト推奨 (小さいゾーンは簡易表示に切り替わる)。
3. **Rotorflight のカスタムテレメトリは RF Telem 自身が解読する** (下記)。Rotorflight 公式 Lua の
   **rf2bg (スペシャルファンクション) と RfTool ウィジェットは外す**。
4. 機体を接続すると、センサー (Gov / Hspd / Vbat / BAT# など) が自動で作られる。

## Rotorflight テレメトリの内蔵デコーダー

RF Telem は Rotorflight の CRSF カスタムテレメトリ (0x88) を自分で解読し、公式と同じ ID・名前で
センサーを作る。rotorflight-lua-scripts の `rf2tlm.lua` / `rf2tlm_sensors.lua` / `MSP/crsf.lua`・`common.lua`
を移植したもの (GPL-3.0)。
- **rf2bg のスペシャルファンクションは不要。むしろ外すこと**: Lua の受信キューは全スクリプトで 1 本しか無く、
  2 つのスクリプトが読むとフレームを奪い合って両方の値が欠ける。
  外し方: Model → Special Functions → `Lua Script` で `rf2bg` を選んでいる行を削除 (または OFF)。
  RfTool ウィジェットを画面に置いていれば、それも削除する
- 受信を自分で持つので、**MSP の応答も受け取れる**: 接続後に `MSP_BATTERY_CONFIG` で各バッテリープロファイルの
  容量 (mAh) を FC から読み、Battery バー (「Battery #2 5000mAh」) と選択画面に表示する
- 公式の初期化処理にある FC への書き込み (RTC 設定・モデル名の自動設定) は移植していない
- rf2bg を使い続けたい場合は `CONFIG.telemetry.decode = false` (このとき容量の自動取得は無効)
- 検証: `tools/luatest/decoder_test.lua` (手組みのフレームで 15 センサーと 6 容量を照合)。**実機では未検証**

## ライセンス

GNU General Public License v3.0 ([LICENSE](LICENSE))。テレメトリデコーダーと MSP 処理は
[rotorflight-lua-scripts](https://github.com/rotorflight/rotorflight-lua-scripts) (GPL-3.0) からの移植。
音声は VOICEVOX で生成 (各キャラクターの利用規約に従う。クレジット: [docs/voicevox_script.md](docs/voicevox_script.md))。

## タッチを使う場合 (App mode レイアウト)

EdgeTX ではタッチとキーがウィジェットに届くのは**全画面表示のときだけ**で、Lua からは全画面にできない。
EdgeTX 2.12 の **App mode** レイアウトを使うと、Enter 長押しだけで RF Telem が全画面になる。
1. 画面設定 (Screens) → レイアウトを **App mode** にして RF Telem を置く
2. 電源投入後に **ENTER を長押し** → 全画面 (タッチ・ダイヤル・Enter が RF Telem に届く)。
   全画面でないときは待機画面などに「Hold ENTER to enable touch」と出る
3. EdgeTX のメニューに戻るときは **RTN 長押し** で全画面を抜ける (App mode では左上の EdgeTX ボタンからも)
- シミュレータで確認済み: Enter 長押しで全画面 → プロファイル選択のタイルをタップで送信まで動作。
  シミュレータでは画面の長押し・タップでは全画面にならなかった (実機のタッチ長押しは未確認)
- タッチが無くても、フライトログを閉じる・プロファイルを選ぶは `Close` のスイッチで操作できる
- 左上の EdgeTX アイコンは、App mode で**全画面でないとき**に EdgeTX 本体が出すもので、設定では消せない
  (EdgeTX 2.12 のソース `view_main.cpp` で確認)。全画面にすると消える

## 描画方式 (lvgl)

EdgeTX の lvgl ウィジェットとして描く (`CONFIG.lvgl = true`)。各画面を 1 回組み立て、変わった値だけを再描画する。
実機の計測 (tools/diagtest の DrawBench / LvglBench) で、従来の lcd 描画 4〜6fps に対し lvgl は 12〜20fps。
- ボタン (メニュー、バッテリー選択のタイル、フライトログの Close、RF2 設定) は**全画面のときだけ**出る (EdgeTX の仕様)。
  App mode で ENTER 長押し → 全画面
- Rotorflight settings は公式 RF2 の **lvgl 版 UI** (タッチ対応の GUI) をウィジェット内で開く。RTN で戻る
- **FC 設定の閲覧 (全画面不要)**: オプション `Page` に割り当てたスイッチを押すたびに PID ゲイン → レート →
  ガバナープロファイル → 通常画面。読むだけで、変更は全画面の Rotorflight settings で行う。
  メニューの View FC settings からも開ける。ARM・切断で閉じる
- ExpressLRS ツールは lcd 描画のため lvgl 版では開けない (SYS > Tools から使う)
- 待機画面の小さなアイコンと、画面切替のワイプ演出は lvgl 版には無い
- `CONFIG.lvgl = false` で従来の lcd 描画に戻る (下記の RF2 カード型画面などはこちら用)

## 設定メニュー (Rotorflight / ExpressLRS / バッテリープロファイル)

全画面表示中、待機画面かダッシュボードで **ENTER (またはタップ)** → メニュー。ダイヤルで選び ENTER (またはタップ)、RTN で閉じる。
**ARM 中は開けない**。ツール使用中に ARM するとその場で閉じる (全画面を抜けたときも閉じる)。

| 項目 | 中身 | 使える条件 |
|---|---|---|
| Rotorflight settings | SD にある**公式 Rotorflight Lua (RF2) の設定ツール**をそのままウィジェット内で動かす。全ページの編集と FC への保存は RF2 の機能 | 機体と接続中 |
| ExpressLRS | SD にある **ELRS Lua** (`/SCRIPTS/TOOLS/elrs.lua` など `CONFIG.tools.elrs` の候補) をそのまま動かす。全項目 | CRSF モジュールあり |
| Battery profile | 接続直後と同じプロファイル選択画面 | 接続中で `BAT#` あり |

- 必要なもの: rotorflight-lua-scripts の**一式** (`SCRIPTS/RF2`・`SCRIPTS/TOOLS/rf2.lua`・`SCRIPTS/FUNCTIONS/rf2bg.lua`・
  `WIDGETS/RfStats`・`WIDGETS/RfTool`) が SD にあること (ファイルとして置くだけ。rf2bg のスペシャルファンクションと
  RfTool ウィジェットは**使わない**)。初回は RF2 のコンパイル画面が出て、終わると自動で開き直す
- **RF2 の画面は RF Telem のテーマとタッチ操作に差し替えている** (`CONFIG.tools.rf2Skin = true`)。
  RF2 の lcd 版の描画部分 (メインメニュー・ページ・ポップアップ・メッセージ・待機表示) だけを置き換え、
  値の読み書き・保存・再起動は RF2 の処理のまま。lvgl 版は使えない (ウィジェットは lcd 描画か lvgl のどちらかに固定、
  EdgeTX 2.12 `lua_widget.cpp` で確認)
  - タイトル帯: `< Back` (戻る) / `<` `>` (前後のページ) / `Menu` (Save・Reload・Reboot・Acc Cal)
  - メインメニュー: ページ一覧を 3 列のタイルで表示。タップで開く
  - ページは**カード型**: RF2 の見出しごとにカード、各項目は「ラベル + 大きな値」のタイル (3 列、ダッシュボードと同じ書式)。
    PID Gains / Rates などの表は、列見出し・行見出し付きの格子。値が読み込まれるまでタイトル下に走る帯
  - 値をタップ → 下に編集パネル: 名前・値・範囲、**スライダー** (タップ/ドラッグ)、`-10` `-1` `+1` `+10`、`OK`。
    選択肢が 6 個以下の項目は選択肢ボタン。ダイヤルでも変えられる。パネル外のタップでも確定。
    **変えたら `Menu` → `Save` で FC に保存**
  - 長いページは上下スワイプかダイヤルでスクロール
  - 速さ対策: 接続中に API バージョンを先に読んでおき、RF2 起動時の待ちを省く。MSP の処理を 1 フレーム 2 回
  - 右下の fps はフレームレート (速さの確認用、`CONFIG.tools.rf2Fps = false` で消す)
  - `rf2Skin = false` で RF2 本来の lcd 画面に戻せる
- 閉じ方: 各ツールの RTN (RF2 はメインメニューで RTN)。RF2 の「Waiting for connection」のように RTN が効かない画面では
  **RTN を 1 秒以内に 2 回**で強制的に閉じる
- ツール使用中は内蔵デコーダーが受信を止める (ツールが応答を受け取るため)。その間ダッシュボードの値は更新されないが、
  アラームの判定は続く (センサー値は止まっている)
- シミュレータで確認済み: メニュー表示 → RF2 の初回コンパイル → 自動で開き直し → RTN 2 回で閉じる。
  差し替え画面はシミュレータ (RF2 の擬似応答) で、タイル → ページ → タップで編集 → ±・OK → Menu → Save まで操作。
  実機 (2026-11-01) では差し替え前の RF2 が FC と通信してメインメニューまで表示された。
  シミュレータには CRSF モジュールが無いため、**RF2 の FC との通信・編集・保存と ELRS ツールは未検証**。
  実機での Lua メモリ量も未確認

## バッテリープロファイル選択 (接続直後)

機体と接続し、DISARM で ARM 警告が無ければ、FC の 6 つのバッテリープロファイルから選ぶ画面を出す。
- 全画面表示: タイルをタップで即決定 / ダイヤルで移動・Enter で決定 / RTN で閉じる
- 全画面でない: `Close` のスイッチを押すたびに次へ。3 秒押さなければ決定
- **オプション `BattSW`** を ON にすると、MK3 の **SW1〜SW6 ボタン**で直接選ぶ (ON のボタン n = プロファイル n。
  複数 ON なら最後に ON にしたもの)。電源投入前にボタンを押しておけば、接続後に操作なしで自動送信される。
  シミュレータで確認済み (SW3 → プロファイル 3)
- **オプション `BattSel`** はダイヤル/スライダー用 (6 等分)。SW1〜SW6 は 1 個ずつ独立した 2 ポジションスイッチなので、
  `BattSel` に割り当てると 1 か 6 にしかならない (実機で「1→6」になった原因)
- **トリムボタンで前後に送る** (全画面不要): 画面横のダイヤルと SYS/MDL/TELE/PAGE/RTN/ENTER は
  スイッチ・ソースとして読めない (全画面時のみウィジェットに届く) が、トリムの上下はスイッチとして論理スイッチに使える。
  例: L10 = AND, V1 = T5 下 → `BattPrev` に L10 / L11 = AND, V1 = T5 上 → `Close` に L11。
  T5 をミキサーで使っていないこと (押すとトリム値自体は動く)。実機での設定は未確認
- 15 秒操作が無ければ現在のまま閉じる。ARM したら即閉じる (ARM 中は送信しない)
- 決定すると `MSP_SET_BATTERY_PROFILE` (176) を CRSF で送り、`BAT#` センサーが変わったら成功
  (「バッテリープロファイル、N」)。2 秒ごとに再送、3 回で失敗 (「変更できませんでした」)
- FC は RAM にだけ保持する (保存しない) ので、電源を入れるたびに選ぶ前提
- タイルの名前は `CONFIG.batteryProfile.labels` で変えられる (例 "6S 5000")。無効化は `enabled = false`
- 飛行中のダッシュボードでは Battery バーのラベルに現在のプロファイルを表示 (「Battery #2」、
  labels を設定していれば「Battery #2 6S 5000」)。容量は MSP からは読めないため labels に手で書く
  ([docs/rotorflight_notes.md](docs/rotorflight_notes.md))
- 根拠 (ソース確認): [docs/rotorflight_notes.md](docs/rotorflight_notes.md)。**実機の FC では未検証**

## アラーム (音声 + 振動)

`main.lua` の ALARMS と `CONFIG.alarm`。画面に出ていない間も `background()` から判定する。

| 段階 | 振動 | 音声 | 項目 |
|---|---|---|---|
| 危険 | パターン | 10 秒ごと (残量は 20 秒ごと) | 残量 ≤ `BattLand` (既定 20%) で「バッテリー、NNパーセント」「着陸してください」(NN はその時の残量。以後 1% 下がるごとに残量だけ読み上げ)、セル電圧 < 3.50V (2 秒継続)、ESC ≥ 90℃、BEC < 6.0V、ヘッドスピードロスト (FALLBACK)、回転中の通信断 |
| 注意 | 短く 1 回 | 1 回 | 残量 ≤ `BattLand` + 10%、セル電圧 < 3.60V (2 秒継続)、ESC ≥ 80℃、飛行時間 (`flightTimeSec`、既定オフ)、ARM 不可 (ARMD ≠ 0) |
| 情報 | なし | 変化時 | ARM / DISARM・レート (RTE#)・プロファイル (PID#)・バッテリープロファイル (接続直後にも現在値)、ガバナー状態、残量 10% 刻み (着陸指示以下は 1% 刻み) |

- 接続・切断は EdgeTX 本体が読み上げるので、ウィジェットは言わない (`CONFIG.alarm.edgetxLinkVoice = true`)。
  接続直後のウィジェットの報告 (ARM・レート・プロファイル・バッテリープロファイル・選択案内) は
  本体の音声と重ならないよう 3 秒遅らせる (`connectQuietSec`)。回転中の切断は振動のみ。
  本体の接続音声を止める設定 (モデルの「テレメトリアラーム無効」) は RSSI/RQly 低下警告も止めるので使わない
- 音声ファイルは `sdcard/SOUNDS/rf/<声>/` (VOICEVOX で 6 種類生成。[docs/voicevox_script.md](docs/voicevox_script.md))。
  以前の版で SD 直下 `/SOUNDS/rf/*.wav` に置いたファイルはもう使わない (deploy.ps1 は削除しないので手で消してよい)。
  音量は RMS -14 dBFS に揃えてある (VOICEVOX の出力のままでは実機で小さかった)
- 案C (EdgeTX 標準機能でのバックアップ): [docs/alarms_native.md](docs/alarms_native.md)。設定したら `CONFIG.alarm.nativeBackup = true`
- 振動の有無・`playHaptic` の単位は TX16S MK3 で未確認

## 設定

**コード側** — `main.lua` 冒頭の `CONFIG`

| キー | 既定 | 内容 |
|---|---|---|
| `theme` | `"color"` | `"color"` / `"mono"` / `"cyan"` (ラジオ側 Theme オプションが優先) |
| `showModelImage` | `true` | 機体画像の表示 (`/IMAGES/<機体名>.png`) |
| `modelImageW` / `modelImageH` | 186 / 46 | 機体画像ファイルの寸法 (この枠ぴったりで作る) |
| `vCellGood` / `vCellWarn` | 3.8 / 3.6 | セル電圧の色分け閾値 |
| `escTempWarn` | 90 | ESC 温度の警告閾値 (℃) |
| `rpmRunningThreshold` | 50 | ローター回転中とみなす回転数 (最大値・最小値の記録条件に使用) |
| `flightLogTimeoutSec` | 60 | フライトログの自動終了時間 |
| `txBattery.minV` / `maxV` | 6.4 / 8.4 | TX 電池残量% の換算範囲 |
| `sensors.*` | — | センサー名の候補リスト (先頭が実機で確認済みの名前) |

**ラジオ側** — ウィジェット長押し → Edit

| オプション | 内容 |
|---|---|
| `Theme` | `0`=color / `1`=mono / `2`=cyan。数値指定 (ウィジェットオプションに文字列選択を使えるかは未確認。「注意・未検証」参照) |
| `Mute` | 消音に使うソース (スイッチ SA など、または論理スイッチ)。値が 0 より大きい間 (スイッチ下 / LS 真) 音声と注意の振動を止める。危険の振動は止めない。空欄なら消音しない |
| `Close` | フライトログを閉じるソース (押しボタン SH など)。押した瞬間に待機画面へ戻る。全画面でなくても効く (全画面表示中はタップ・Enter でも閉じられる)。バッテリープロファイル選択画面では「次のプロファイルへ」になる |
| `BattLand` | 着陸指示を出す残量 % (10〜50、既定 20) |
| `BattSW` | ON で SW1〜SW6 ボタンがバッテリープロファイル 1〜6 を選ぶ |
| `BattSel` | バッテリープロファイルを選ぶダイヤル/スライダー (6 等分。SW ボタンには使わない。空欄なら使わない) |
| `BattPrev` | 選択画面で 1 つ前のプロファイルへ (`Close` が次へ)。トリム → 論理スイッチ経由を想定 |
| `Voice` | アラームの声。`0`=No.7 アナウンス / `1`=青山龍星 / `2`=玄野武宏 / `3`=冥鳴ひまり / `4`=Voidoll / `5`=ずんだもん |

**機体画像**: 機体名と同名の PNG (例: `S2 Ultra.png`) を `/IMAGES` に置く。表示は **等倍 1:1** なので、
**186×46 の透過キャンバスに縮小した機体を中央配置**したファイルを作る (理由は下記)。
`sdcard/IMAGES/S2 Ultra.png` は `assets/model_image.png` から作った仮画像。

## 確認済みセンサー名 (実機の Telemetry 一覧 42 項目から確定)

| 用途 | 名前 | 用途 | 名前 |
|---|---|---|---|
| ガバナー状態 | `Gov` | ヘッドスピード | `Hspd` |
| 電圧 / セル電圧 / セル数 | `Vbat` / `Vcel` / `Cel#` | 電流 | `Curr` |
| ESC 温度 | `Tesc` | 残量 % | `Bat%` |
| 消費容量 (mAh) | `EscC` | スロットル | `Thr` |
| BEC 電圧 | `Vbec` | レートプロファイル / PID プロファイル | `RTE#` / `PID#` |
| ARM フラグ | `ARM` | アーミング無効フラグ | `ARMD` |
| 通信品質 | `RQly` (`1RSS`, `RSNR`, `RSSI`) | | |

- `ARM`: `0`/`2` = DISARM、`1`/`3` = ARM
- `ARMD`: 0 以外で全画面警告。`67108872` は「ARM スイッチ ON の状態で機体電源投入」を意味する
- 消費容量・残量は DISARM で 0 に戻るため、ローター回転中のみ 最大容量 / 最小残量 を記録している

## 開発

### VS Code

`sdcard/WIDGETS/RFTelem/main.lua` を編集する。拡張機能 `sumneko.lua` を入れると、
`.luarc.json` と `types/edgetx.lua` により EdgeTX API の補完・型チェックが効く。

`.vscode/tasks.json` がある場合は、`Ctrl+Shift+B` → **Deploy to SD card** → SD のドライブ (`E:\` など) または `auto` を入力すると SD へ反映できる。
診断ウィジェットも入れるなら **Deploy to SD card (+ diagnostic widget)**、コピー対象の一覧だけ見るなら **Deploy dry run**。
同じ操作は「インストール」の `deploy.ps1` コマンドでも行える。

### シミュレータで確認する (EdgeTX Companion 2.12)

前提: Companion 2.12.0 (`C:\Program Files (x86)\EdgeTX\Companion 2.12`)。TX16S MK3 の 800×480 シミュレータを使う。

```powershell
# 起動 (Theme: 0=color / 1=mono / 2=cyan)。初回は SD イメージを sim\sdcard に自動作成
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sim.ps1 -Theme 0
# LCD を 800×480 等倍で保存 (sim\captures\)。シナリオ 1 周 = 140 秒
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sim-capture.ps1 -Count 25 -Interval 6
```

- `sim.ps1` は `sdcard\` を `sim\sdcard` にコピーし、**コピー側だけ** `CONFIG.simulate = true` にする
  (`sdcard\` の main.lua は false のまま)。Companion に「RFTelem Sim (TX16S MK3)」プロファイルも作る。
- `simulate = true` のとき、`readTelemetry` は `simulateTelemetry` のシナリオ値を返す
  (standby → armwarning → スプールアップ → 飛行 → 低電圧・ESC 高温 → THR-OFF → DISARM → flightlog)。
- `sim-capture.ps1` はシミュレータのカメラボタン (LCD をクリップボードへコピー) をクリックする。
  ボタン位置は 2560×1440 環境で測った値なので、画面構成が違えば `-ButtonX/-ButtonY` で調整する。
- シミュレータのフォント描画が実機と同じかは未確認。最終判断は実機で行う。
- `sim\` は .gitignore 済み (SD イメージとキャプチャ)。モデル・ラジオ設定の元は `scripts\sim-template\`。

### フォルダ構成

```
RFTelem/
├─ sdcard/                      SD カードのルートと同じ構造 (deploy でそのままコピーされる)
│  ├─ WIDGETS/RFTelem/main.lua  ウィジェット本体
│  └─ IMAGES/txbatt_{10,25,50,75,100}.png   トップバーの TX 電池アイコン (45×22)
├─ assets/                      SD には自動コピーされない素材
│  ├─ ROTORFLIGHT_fitted.png    229×104 の透過キャンバスにロゴ (200px) を中央配置
│  └─ model_image.png           初期の機体画像サンプル (320×90)
├─ tools/diagtest/sdcard/       診断ウィジェット (フォント・ビットマップ実測用、1回使い切り)
├─ tools/voice/                 音声台本 voices.csv と VOICEVOX 一括生成 make_voices.ps1
├─ tools/luatest/               画面なし検証 (Node + fengari。`npm install` → `npm test`)
├─ types/edgetx.lua             lua-language-server 用 EdgeTX API 宣言 (使用分のみ)
├─ scripts/deploy.ps1           SD カードへのコピー
├─ scripts/sim.ps1, sim-capture.ps1, sim-template/   シミュレータ起動・LCD キャプチャ
├─ sim/                         シミュレータ用 SD イメージとキャプチャ (自動生成、git 対象外)
├─ docs/
│  ├─ architecture.md           main.lua の構造と画面遷移
│  ├─ project_summary.md        他プロジェクトへ渡すための知見まとめ
│  ├─ voicevox_script.md        音声の生成方法と鳴るタイミング
│  ├─ alarms_native.md          案C: EdgeTX 標準機能でのアラームバックアップ手順
│  ├─ rotorflight_notes.md      Rotorflight 4.6 ソースから確認したガバナー状態・ARM 不可フラグ
│  └─ mockups/                  GUI 案の HTML モック (A/B/C、白黒+シアン案など)
├─ .luarc.json, .editorconfig, .gitignore
└─ .vscode/                     VS Code 用設定 (settings / tasks / extensions)
```

### 実機で測った値 (この機種・このファームウェア固有)

`lcd.sizeText("0123456789")` による実測。他機種・他バージョンでは再測定が必要
(`tools/diagtest` を使う)。

| フォント | 1文字幅 | 高さ |
|---|---|---|
| (既定) | 12 | 27 |
| `SMLSIZE` | 10 | 23 |
| `MIDSIZE` | 19 | 42 |
| `DBLSIZE` | 25 | 55 |
| `XXLSIZE` | 51 | 93 |

- `getTime()` の単位は **10 ms (1/100 秒)**。秒に直すときは `/100`
- `lcd.drawBitmap` の scale は **パーセント指定**。ただし `getBitmapSize` は信頼できないので、
  画像は表示サイズに事前リサイズして等倍で描く運用にしている
- タッチ (`EVT_TOUCH_TAP`) は **ウィジェットがフルスクリーン表示のときだけ** 届く。
  そのためフライトログは 60 秒で自動的に待機画面へ戻る

## 注意・未検証

- `main.lua` は実機 (TX16S MK3) で動作を確認しながら開発している。実機で未確認の項目:
  FC へのバッテリープロファイル送信 (ソース確認のみ)、振動の有無と `playHaptic` の単位、
  トリム → 論理スイッチによる操作、実機でのタッチ長押し (シミュレータでは Enter 長押しで確認済み)、
  設定メニューの RF2 / ELRS ツール (FC・モジュールとの通信、メモリ量)。
  シミュレータのフォント描画が実機と同じかも未確認なので、最終判断は実機で行う。
- `scripts/deploy.ps1` が環境に合わない場合は、`sdcard/` の中身を SD のルートへ手動でコピーすればよい。
- `main.lua` 冒頭のコメントの一部は旧レイアウト時代の記述が残っている
  (例: 現在は存在しない "Max Amp/Min Volt" チップへの言及)。挙動の一次情報はコード本体。
- EdgeTX 2.12 のウィジェットオプションに文字列選択型があるかは確認していない。
  Theme を数値指定にしているのは、開発時にその前提で作ったため。
- 型スタブは使用 API のみ。未宣言のグローバルは警告になるので、必要に応じて `types/edgetx.lua` に追加する。
