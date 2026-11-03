# RFTelem — Rotorflight テレメトリウィジェット (EdgeTX / TX16S MK3)

Rotorflight 搭載ヘリのテレメトリを、EdgeTX の Color LCD ウィジェットとして表示する Lua ウィジェット。
ヘッドスピードを中心に、電圧・電流・バッテリー残量・ガバナー状態などを 1 画面にまとめ、
ARM 警告・フライトログ・バッテリープロファイル選択・音声と振動のアラームを備える。

> **English summary** — RFTelem is an EdgeTX Lua (lvgl) widget that shows Rotorflight helicopter telemetry
> on a colour radio (developed on a RadioMaster TX16S MK3, 800×480, EdgeTX 2.12, CRSF/ExpressLRS, Rotorflight 4.6).
> - **Features**: headspeed-centred dashboard and a simpler gauge screen, arm/arming-disabled warnings, post-flight log
>   with charts, flight history, battery-profile picker on connect, full-charge check, Rotorflight settings (the official
>   RF2 Lua hosted with a touch UI), voice + haptic alarms (Japanese voices made with VOICEVOX, English voices with Piper).
> - **Install**: copy `sdcard/` to the radio's SD card root (or `scripts/deploy.ps1 -Target E:\`), add the widget
>   `RF Telem` to a full-screen layout, and **remove the `rf2bg` special function and the RfTool widget** —
>   RFTelem decodes Rotorflight's custom telemetry itself.
> - **Not included**: Japanese voice files (generate them with `tools/voice/make_voices.ps1` and VOICEVOX) and model
>   pictures (`/IMAGES/<model name>.png`, 186×46, and `<model name>-L.png`, 320×124, transparent PNG).
>   English voices (`SOUNDS/rf/en_male`, `en_female`) are included.
> - Settings are made on the radio (widget full screen: hold ENTER in the App-mode layout, then Menu > Settings).
>   The rest of this README is in Japanese. License: GPL-3.0. Use at your own risk.

> **免責事項**: 本ウィジェットの使用は**自己責任**で行ってください。使用または使用できなかったことによって生じた損害 (機体・送信機・SD カードの損傷、墜落、人身・物損事故など) について、作者は一切の責任を負いません。表示やアラーム (音声・振動) の正確さは保証されません。飛行前の点検と機体状態の確認は、操縦者自身の責任で行ってください。

## 特長

- **ヘッドスピード中心のダッシュボード**: Volt (最小値)・Vcel・Current (最大値)・Bec volt (最小値)、
  Governor、Flight (MM:SS)、Profile/Rate、Battery バー (% / mAh)、Throttle バー (% / ℃)
- **接続状態に応じた画面切替**: 待機 ("Waiting for connection") → ダッシュボード。
  `ARMD` ≠ 0 で全画面の ARM 警告、切断後はフライトログ。切替時はワイプ演出
- **再接続で全リセット**: 最大・最小値とフライトタイマーを初期化してから表示
- **接続直後のバッテリープロファイル選択**: FC の 6 プロファイルから選んで送信 (実機の FC では未検証)
- **メニュー** (全画面時、DISARM 中): Rotorflight 設定 (タッチ対応の RF Telem 調画面)、バッテリープロファイル、
  FC 設定の閲覧、飛行履歴、Settings
- **アラーム (音声 + 振動)**: 危険 / 注意 / 情報の 3 段階。声は日本語 6 種 (VOICEVOX) と英語 2 種 (Piper) から選択
- **3 テーマ** (color / mono / cyan) と、機体名と同名の PNG による機体画像表示
- **検証環境**: EdgeTX Companion シミュレータ用スクリプトと、画面なしのテスト (`tools/luatest`) を同梱

## 動作環境

| 項目 | 内容 |
|---|---|
| 対象送信機 | RadioMaster TX16S MK3 (800×480) |
| 対象ファームウェア | EdgeTX v2.12.0 "Queen Anne's Revenge" (edgetx-tx16smk3) |
| 通信 | CRSF / ExpressLRS |
| FC | Rotorflight (センサー名は後述) |
| ウィジェット名 | `RF Telem` (`/WIDGETS/RFTelem/`: main.lua・core.lua・view.lua・rf2ui.lua) |

## インストール

1. `sdcard/` の中身を、送信機の SD カードのルートへコピーする
   (`WIDGETS/RFTelem/` の 4 ファイル、`IMAGES/`、`SOUNDS/` がそれぞれ対応する)。
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
- 公式の初期化処理 (rf2bg) のうち、**機体名の自動設定は移植済み**: FC の「Set model name」(RF2 の Model ページ、
  MSP_PILOT_CONFIG の model_flags bit 0) が ON なら、接続中は機体名を FC の名前 (MSP_NAME) に変え、切断で元に戻す
  (元の名前は settings.txt の `prevName`)。RTC 設定とタイマー/GV のパラメータ設定は移植していない
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

## 描画方式とファイル構成

EdgeTX の lvgl ウィジェット (EdgeTX 2.11 以降)。各画面を 1 回組み立て、変わった値だけを再描画する。
実機の計測 (tools/diagtest の DrawBench / LvglBench) で、旧 lcd 描画 4〜6fps に対し 12〜20fps (実機ダッシュボード 16.5fps)。

| ファイル | 中身 | 読み込み |
|---|---|---|
| `main.lua` | 名前・オプションだけの入口 | EdgeTX 起動時 (全ウィジェット分が読まれるので小さく保つ) |
| `core.lua` | 設定・テレメトリ (内蔵デコーダー、MSP)・アラーム・バッテリー選択・履歴・メニュー | ウィジェット作成時 |
| `view.lua` | 画面 | ウィジェット作成時 |
| `rf2ui.lua` | Rotorflight settings の画面 | 初めて開いたとき |

- ボタン (メニュー、Settings、バッテリー選択のタイル、フライトログの Close、RF2 設定) は**全画面のときだけ**出る
  (EdgeTX の仕様)。App mode で ENTER 長押し → 全画面。全画面のときは左上に青い Touch バッジ

## メニュー (全画面時、DISARM のみ)

待機画面かダッシュボードのトップバーの **Menu** (または ENTER)。ARM するとメニューと開いている画面は閉じる。

| 項目 | 中身 |
|---|---|
| Rotorflight settings | 公式 RF2 の設定ツールをウィジェット内で動かし、画面を RF Telem 調にしたもの (下記)。接続中のみ |
| Battery profile | 接続直後と同じプロファイル選択画面。接続中で `BAT#` があるとき |
| View FC settings | PID ゲイン / レート / ガバナープロファイルの閲覧 (下記)。接続中のみ |
| Erase blackbox | FC のブラックボックス (dataflash) を消去。1 回目のタップで行が「Tap again: erase (NN% used)」(オレンジ、3 秒) になり、もう一度で消去。進行と結果は下の帯 (Erasing… → 緑の Blackbox erased + 確認音・振動)。接続中でブラックボックス情報 (MSP 70) が読めたときのみ |
| Flight history | この機体の飛行履歴 (下記) |
| Settings | 音声・アラーム・飛行・表示の設定 (下記) |

### Rotorflight settings
- SD に rotorflight-lua-scripts の**一式** (`SCRIPTS/RF2`・`SCRIPTS/TOOLS/rf2.lua`・`SCRIPTS/FUNCTIONS/rf2bg.lua`・
  `WIDGETS/RfStats`・`WIDGETS/RfTool`) が必要 (置くだけ。rf2bg のスペシャルファンクションと RfTool ウィジェットは使わない)。
  初回は RF2 のコンパイルが走り、終わると自動で開き直す
- 公式 RF2 (lvgl 版) の画面部品だけを差し替え (`rf2ui.lua`)。値の読み書き・保存・再起動は RF2 の処理のまま
- メインメニューはタイル、各ページはカード/表のタイル (指で縦スクロール)。値をタップ → 下から編集パネル
  (スライダー、-10 -1 +1 +10、OK / Cancel。選択肢はボタンを並べて 1 タップ)。上部に Back / Save / Menu (Reload・Reboot FC)
- Save 後、FC への書き込みが済むと緑の「Saved to the FC」を 2.5 秒 + 確認音 + 振動 2 回 (書き込み中はボタンが Saving)。
  ARM 中などで保存できない時は RF2 の警告が出て、Saved は出ない (実機確認済み)
- `CONFIG.tools.rf2Skin = false` で RF2 公式の画面。RTN でも戻れる
- ExpressLRS の Lua ツールは lcd 描画のためウィジェット内では開けない (SYS > Tools から使う)

### FC 設定の閲覧 (全画面不要)
- オプション `Page` に割り当てたスイッチを押すたびに PID ゲイン → レート → ガバナープロファイル → 通常画面
  (メニューの View FC settings からも)。読むだけ。変更は Rotorflight settings
- 閲覧中にスイッチで PID / レートのプロファイルを切り替えると、そのプロファイルの値を読み直す。ARM・切断で閉じる

### Flight history
- 飛行ごと (ローター回転 10 秒以上、`CONFIG.history.minSec`) に、切断の時点で記録する
  - `/LOGS/RFTelem-<機体名>.csv`: 1 飛行 1 行 (日時、パック、ローター時間、消費 mAh、残量、最大 rpm・A・W、最低電圧・セル・BEC、最高 ESC 温度)
  - `/WIDGETS/RFTelem/stats-<機体名>.txt`: 合計 (回数・ローター時間・mAh・最終日時)、パック (バッテリープロファイル) ごとの回数・mAh・最終使用、直近 6 飛行
- 画面: 合計 4 項目、パックごとの表 (Settings > Packs の名前があればその名前)、直近の飛行の表
- **Reset** (タイトル右): 1 回目で「Sure?」(赤、3 秒)、もう一度で stats を 0 に戻す。`/LOGS` の CSV は残る

### Settings
SD の `/WIDGETS/RFTelem/settings.txt` に保存。ウィジェットオプションの同じ項目 (Theme / Voice / BattLand) より優先。

| タブ | 項目 |
|---|---|
| Voice | 声 (試聴付き)、アラーム On/Off、振動 On/Off、効果音 On/Off (試聴付き) |
| Alarms | 着陸指示 %、セル電圧 注意/危険、ESC 温度 注意/危険、BEC |
| Flight | 飛行時間の読み上げ、フライトログを閉じるまでの秒数、満充電チェック On/Off と満充電とみなすセル電圧 (既定 4.10V)、バッテリー選択を現状のまま閉じるまでの秒数 (0 = しない) |
| Packs | バッテリープロファイル 1〜6 の名前 (例 `6S 5000`、16 文字まで。タップで EdgeTX のキーボード)。右に FC の容量。選択画面のタイルと履歴に出る。空にすると `Profile N` |
| Display | テーマ、fps 表示、機体画像、シンプル表示 (下記) |

追加するときは `core.lua` の `SETTINGS` に 1 行 (必要なら `SET.groups` にタブ)。

### シンプル表示 (Settings > Display > Simple screen)
ダッシュボードの代わりに、図形中心の画面 (通常の黒基調テーマ)。
- 左のカード: スロットルの円弧 (0〜100%、270°、下が開く) と外周の目盛 (5% ごと、0 / 50 / 100% は白く長い)。
  塗りの色 = ガバナー状態。左上に `Throttle NN%`、右上にガバナー目標。
  その内側に電池残量の円弧 (色は通常と同じ 50% / 20% 区切り、灰色の小目盛 = 25 / 50 / 75%、赤い目盛 = 着陸指示 %)。
  中央のリング = アーム (緑 = ARM、灰色 = DISARM)、中に残量 %、`消費/容量 mAh` (容量 = 選択中のバッテリープロファイルの容量、
  MSP 32)、バッテリープロファイル (Settings > Packs の名前、無ければ `Battery #N`)。下の開きにヘッドスピード
- 右上のカード: 機体画像を大きく。`/IMAGES/<機体名>-L.png` (320×124、透過。`CONFIG.simple.imageW/H`)、無ければ通常の小さい画像
- 右下のカード: 飛行時間 (満量 = Settings の飛行時間読み上げ、Off なら `CONFIG.simple.flightSec`)、電流 (`CONFIG.simple.currentMax`)、
  ESC 温度 (満量 = ESC 危険、オレンジの目盛 = 注意。注意でオレンジ、危険で赤) の 10 分割バー。行の間に仕切り線
- トップバー・Menu・警告はダッシュボードと同じ

### 満充電チェック
接続ごとに 1 回、接続の静音時間 + 1 秒後 (値が落ち着いてから)、DISARM かつローター停止で Vcel が Settings > Flight の
「Full at cell」未満なら、画面の上に **BATTERY NOT FULL** のウィンドウ (オレンジ枠、注意音 + 振動)。
セル電圧と基準値、電池の形 (3.5V〜基準値の割合で塗り) を表示。閉じ方: ウィンドウのどこをタップしても (全画面時) /
ENTER・RTN / Close スイッチ (バッテリー選択より先にこちらを閉じる) / ARM / 10 秒で自動 (下のバーが残り時間、`CONFIG.alarm.fullAlertSec`)

## 画面の補足
- トップバー: 警告、時刻、リンク品質 (RQly の %)、電波バー、TX 電池 (中に残量 %)
- ダッシュボードの Headspeed の右上に、FC のガバナー目標ヘッドスピード (`target 2100`、MSP_GOVERNOR_PROFILE。PID プロファイルが変わると読み直し)
- バッテリー選択画面の下段は飛行前チェック: ARM 可否、ガバナー目標、ブラックボックスの空き (MSP_DATAFLASH_SUMMARY、10% 未満でオレンジ)

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
- 時間制限なし: 選ぶまで (または ARM するまで) 表示したまま。ARM したら即閉じ、現在のプロファイルのまま (ARM 中は送信しない)。
  `CONFIG.batteryProfile.timeoutSec` を 1 以上にすると、その秒数で現在のまま閉じる
- 決定すると `MSP_SET_BATTERY_PROFILE` (176) を CRSF で送り、`BAT#` センサーが変わったら成功
  (「バッテリープロファイル、N」)。2 秒ごとに再送、3 回で失敗 (「変更できませんでした」)
- FC は RAM にだけ保持する (保存しない) ので、電源を入れるたびに選ぶ前提
- タイルの名前は `CONFIG.batteryProfile.labels` で変えられる (例 "6S 5000")。無効化は `enabled = false`
- 飛行中のダッシュボードでは Battery バーのラベルに現在のプロファイルを表示 (「Battery #2」、
  labels を設定していれば「Battery #2 6S 5000」)。容量は MSP からは読めないため labels に手で書く
  ([docs/rotorflight_notes.md](docs/rotorflight_notes.md))
- 根拠 (ソース確認): [docs/rotorflight_notes.md](docs/rotorflight_notes.md)。**実機の FC では未検証**

## アラーム (音声 + 振動)
- **効果音** (playTone): 接続 (上がる2音) / 切断 (下がる2音) / 注意 (2回) / 危険 (高い3連) を音声の前に鳴らす。
  Settings > Voice > Sound effects で On/Off と試聴 (Test)。Mute スイッチで音声と一緒に消える。音の高さ・長さは CONFIG.alarm.toneEffects

`core.lua` の ALARMS と `CONFIG.alarm`。画面に出ていない間も `background()` から判定する。

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

**コード側** — `core.lua` 冒頭の `CONFIG`

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
| `Voice` | アラームの声。`0`=No.7 アナウンス / `1`=青山龍星 / `2`=玄野武宏 / `3`=冥鳴ひまり / `4`=Voidoll / `5`=ずんだもん / `6`=English 男性 / `7`=English 女性 (Piper、`tools/voice/make_voices_en.py`。クレジットは `SOUNDS/rf/CREDITS.txt`) |

**機体画像**: 機体名と同名の PNG (例: `GOOSKY S2.png`) を `/IMAGES` に置く。表示は **等倍 1:1** なので、
**186×46 の透過キャンバスに縮小した機体を中央配置**したファイルを作る (理由は下記)。シンプル表示用は
`<機体名>-L.png` (320×124)。メーカーの画像から作ったものは著作権の都合でリポジトリに含めていない (各自で用意)。

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

`sdcard/WIDGETS/RFTelem/` の core.lua / view.lua / rf2ui.lua を編集する。拡張機能 `sumneko.lua` を入れると、
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
  (`sdcard\` の core.lua は false のまま)。Companion に「RFTelem Sim (TX16S MK3)」プロファイルも作る。
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
│  ├─ WIDGETS/RFTelem/          ウィジェット (main.lua 入口 / core.lua / view.lua / rf2ui.lua)
│  ├─ IMAGES/                   機体画像など
│  └─ SOUNDS/rf/<声>/           アラーム音声 (英語 en_male / en_female のみ同梱。日本語は make_voices.ps1 で生成)
├─ tools/diagtest/sdcard/       診断ウィジェット (フォント・ビットマップ実測 DiagTest、描画速度 DrawBench / LvglBench)
├─ tools/voice/                 音声台本 voices.csv / voices_en.csv、VOICEVOX 一括生成 make_voices.ps1、Piper 生成 make_voices_en.py
├─ tools/luatest/               画面なし検証 (Node + fengari、lvgl / io の代役付き。`npm install` → `npm test`)
├─ types/edgetx.lua             lua-language-server 用 EdgeTX API 宣言 (使用分のみ)
├─ scripts/deploy.ps1           SD カードへのコピー
├─ scripts/sim.ps1, sim-capture.ps1, sim-template/   シミュレータ起動・LCD キャプチャ
├─ sim/                         シミュレータ用 SD イメージとキャプチャ (自動生成、git 対象外)
├─ docs/
│  ├─ architecture.md           ファイル構成・処理の流れ・画面遷移
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
- タッチとキー、lvgl のボタンは **ウィジェットがフルスクリーン表示のときだけ** 有効 (EdgeTX 2.12)
- EdgeTX の Lua (5.3) では文字列のメソッド呼び出し (`s:match()` など) が使えない (シミュレータで確認)。`string.match(s, ...)` の形で書く。
  また `12.5 == math.floor(12.5)` が true になるので、整数判定は `isWhole` を使う
- 1 フレームの Lua 命令数が多すぎると「CPU limit」で止まる。luatest の `cpu longflight` で画面ごとの最大を確認する
  (lvgl の組み立て自体は C なので数えない)。目安: 約 30,000 で停止の実績。現在の最大はフライトログを開くフレームの約 16,000

## 注意・未検証

- 実機 (TX16S MK3) で動作を確認しながら開発している。実機で未確認の項目:
  トリム → 論理スイッチによる操作、飛行履歴・飛行前チェック・リンク品質・ガバナー目標の表示 (2026-11-02 追加)。
  シミュレータのフォント描画が実機と同じかも未確認なので、最終判断は実機で行う。
- `scripts/deploy.ps1` が環境に合わない場合は、`sdcard/` の中身を SD のルートへ手動でコピーすればよい
  (そのときは SD の `WIDGETS/RFTelem/*.luac` を消すと確実)。
- EdgeTX 2.12 のウィジェットオプションに文字列選択型は無い (VALUE/COLOR/SOURCE/BOOL)。Theme などは数値指定。
- 型スタブは使用 API のみ。未宣言のグローバルは警告になるので、必要に応じて `types/edgetx.lua` に追加する。
