# RotorHUD — Rotorflight テレメトリウィジェット (EdgeTX / TX16S MK3)

Rotorflight を積んだヘリのテレメトリを、EdgeTX のカラー液晶にウィジェットとして表示する Lua ウィジェットです。
ヘッドスピードを中心に、電圧・電流・バッテリー残量・ガバナー状態などを 1 画面にまとめ、
ARM 警告、フライトログ、バッテリープロファイルの選択、音声と振動によるアラームなどを備えています。

> **English summary** — RotorHUD is an EdgeTX Lua (lvgl) widget that shows Rotorflight helicopter telemetry
> on a colour radio (developed on a RadioMaster TX16S MK3, 800×480, EdgeTX 2.12, CRSF/ExpressLRS, Rotorflight 4.6).
> - **Features**: headspeed-centred dashboard and a simpler gauge screen, arm/arming-disabled warnings, post-flight log
>   with charts, flight history, battery-profile picker on connect, full-charge check, Rotorflight settings (the official
>   RF2 Lua hosted with a touch UI), voice + haptic alarms (Japanese voices made with VOICEVOX, English voices with Piper).
> - **Install**: copy `sdcard/` to the radio's SD card root (or `scripts/deploy.ps1 -Target E:\`), add the widget
>   `RotorHUD` to a full-screen layout, and **remove the `rf2bg` special function and the RfTool widget** —
>   RotorHUD decodes Rotorflight's custom telemetry itself.
> - **Voices**: Japanese (6 voices, VOICEVOX) and English (2 voices, Piper) are included under `SOUNDS/rf/`; credits and
>   terms in `SOUNDS/rf/CREDITS.txt`. Model pictures are your own: `/IMAGES/<model name>.png` (186×46) and
>   `<model name>-L.png` (320×124), transparent PNG.
> - Settings are made on the radio (widget full screen: hold ENTER in the App-mode layout, then Menu > Settings).
>   The rest of this README is in Japanese. License: GPL-3.0.
>
> **Disclaimer**: Use this widget at your own risk. The author accepts no liability for any damage arising from its
> use or inability to use it (including damage to models, radios or SD cards, crashes, injury or property damage).
> The accuracy of the displayed values and of the alarms (voice and haptic) is not guaranteed. Pre-flight checks and
> confirming the condition of your model remain the pilot's own responsibility.

> **免責事項**: 本ウィジェットは**ご自身の責任**でお使いください。使用したこと、または使用できなかったことによって生じた損害 (機体・送信機・SD カードの損傷、墜落、人身・物損事故など) について、作者は責任を負いかねます。表示やアラーム (音声・振動) の正確さは保証できません。飛行前の点検と機体の状態確認は、操縦者ご自身でお願いします。

## 特長

- **ヘッドスピード中心のダッシュボード**: Volt・Vcel・Current・Bec volt、Governor、Flight (MM:SS)、Profile/Rate、
  Battery バー (% / mAh)、Throttle バー (% / ℃)
- **シンプル表示**: スロットルとバッテリー残量の円弧、大きな機体画像、飛行時間・電流・ESC 温度のバーで構成した、ひと目で読める画面
- **接続状態に合わせた画面切替**: 待機 ("Waiting for connection") → ダッシュボード。
  `ARMD` ≠ 0 のときは全画面の ARM 警告 (原因と対処も表示)、切断後はフライトログを表示します
- **再接続で全リセット**: 最大・最小値とフライトタイマーを初期化してから表示します
- **接続直後のバッテリープロファイル選択**と、**満充電チェック** (満充電でなければお知らせ)
- **メニュー** (全画面時、DISARM 中): Rotorflight 設定 (タッチ対応の画面)、バッテリープロファイル、
  FC 設定の閲覧、ブラックボックス消去、飛行履歴、Settings
- **アラーム (音声 + 振動)**: 危険 / 注意 / 情報の 3 段階。声は日本語 6 種 (VOICEVOX) と英語 2 種 (Piper) から選べます
- **3 テーマ** (color / mono / cyan) と、機体名と同じ名前の PNG による機体画像の表示
- **検証環境**: EdgeTX Companion シミュレータ用のスクリプトと、画面なしのテスト (`tools/luatest`) を同梱しています

## 動作環境

| 項目 | 内容 |
|---|---|
| 対象送信機 | RadioMaster TX16S MK3 (800×480) |
| 対象ファームウェア | EdgeTX v2.12.0 "Queen Anne's Revenge" (edgetx-tx16smk3) |
| 通信 | CRSF / ExpressLRS |
| FC | Rotorflight 4.6 (センサー名は後述) |
| ウィジェット名 | `RotorHUD` (`/WIDGETS/RotorHUD/`: main.lua・core.lua・view.lua・rf2ui.lua) |

## インストール

1. `sdcard/` の中身を、送信機の SD カードのルートへコピーしてください
   (`WIDGETS/RotorHUD/` の 4 ファイル、`IMAGES/`、`SOUNDS/` がそれぞれ対応します)。
   Windows では、手作業のかわりに `scripts/deploy.ps1` も使えます:
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Target E:\`
   - `-Target` は SD のルートです。`auto` にすると、EdgeTX の SD カードらしいリムーバブルドライブを自動で探します
   - `-Tools` で診断ウィジェットも一緒にコピーし、`-DryRun` ではコピー対象の一覧だけを表示します
   - 追加と上書きだけを行い、SD 上のファイルは削除しません
   - 送信機を USB ストレージモードにするか、カードリーダーで SD を挿してから実行してください
2. 送信機側: ウィジェット画面 → 空きゾーンを長押し → Add Widget → `RotorHUD`。
   1 ゾーンの全画面レイアウトをおすすめします (小さいゾーンでは簡易表示になります)。
3. **Rotorflight のカスタムテレメトリは RotorHUD が自分で読み取ります** (下記)。Rotorflight 公式 Lua の
   **rf2bg (スペシャルファンクション) と RfTool ウィジェットは外してください**。
4. 機体を接続すると、センサー (Gov / Hspd / Vbat / BAT# など) が自動で作られます。

## Rotorflight テレメトリの内蔵デコーダー

RotorHUD は Rotorflight の CRSF カスタムテレメトリ (0x88) を自分で読み取り、公式と同じ ID・名前でセンサーを作ります。
rotorflight-lua-scripts の `rf2tlm.lua` / `rf2tlm_sensors.lua` / `MSP/crsf.lua`・`common.lua` を移植したものです (GPL-3.0)。
- **rf2bg のスペシャルファンクションは不要で、外しておく必要があります**: Lua の受信キューはすべてのスクリプトで 1 本しかないため、
  2 つのスクリプトが読むとフレームを取り合い、両方の値が欠けてしまいます。
  外し方: Model → Special Functions → `Lua Script` で `rf2bg` を選んでいる行を削除 (または OFF) します。
  RfTool ウィジェットを画面に置いている場合は、そちらも削除してください
- 受信を自分で受け持つので、**MSP の応答も受け取れます**: 接続後に各バッテリープロファイルの容量 (mAh)、ガバナー目標、
  ブラックボックスの空き容量などを FC から読み、画面に表示します
- 公式の初期化処理 (rf2bg) のうち、**機体名の自動設定も移植しています**: FC の「Set model name」(RF2 の Model ページ) が ON なら、
  接続中は機体名を FC の名前に変え、切断すると元に戻します (元の名前は settings.txt の `prevName` に保存)。
  RTC 設定とタイマー/GV のパラメータ設定は移植していません
- rf2bg を使い続けたい場合は `CONFIG.telemetry.decode = false` にしてください (このとき容量などの自動取得は使えません)
- テスト: `tools/luatest/decoder_test.lua` (手組みのフレームでセンサー・容量・機体名・ブラックボックス消去を照合)

## ライセンス

GNU General Public License v3.0 ([LICENSE](LICENSE))。テレメトリデコーダーと MSP 処理は
[rotorflight-lua-scripts](https://github.com/rotorflight/rotorflight-lua-scripts) (GPL-3.0) から移植しています。
音声のクレジットと利用規約は [sdcard/SOUNDS/rf/CREDITS.txt](sdcard/SOUNDS/rf/CREDITS.txt) をご覧ください
(日本語は VOICEVOX の各キャラクターの利用規約に、英語は Piper の音声モデルのライセンスに従います)。

## タッチを使う場合 (App mode レイアウト)

EdgeTX では、タッチとキーがウィジェットに届くのは**全画面表示のときだけ**で、Lua から全画面にすることはできません。
EdgeTX 2.12 の **App mode** レイアウトを使うと、ENTER の長押しだけで RotorHUD を全画面にできます。
1. 画面設定 (Screens) → レイアウトを **App mode** にして RotorHUD を置きます
2. 電源を入れたら **ENTER を長押し** → 全画面になり、タッチ・ダイヤル・ENTER が RotorHUD に届きます。
   全画面でないときは、待機画面などに「Hold ENTER to enable touch」と表示されます
3. EdgeTX のメニューに戻るときは **RTN の長押し**で全画面を抜けます (App mode では左上の EdgeTX ボタンからも戻れます)
- タッチを使わなくても、フライトログを閉じる・プロファイルを選ぶといった操作は `Close` に割り当てたスイッチでできます
- 左上の EdgeTX アイコンは、App mode で**全画面でないとき**に EdgeTX 本体が表示するもので、設定では消せません。
  全画面にすると消えます

## 描画方式とファイル構成

EdgeTX の lvgl ウィジェット (EdgeTX 2.11 以降) です。各画面を 1 回組み立て、変わった値だけを描き直します。
実機の計測 (tools/diagtest の DrawBench / LvglBench) では、旧来の lcd 描画の 4〜6fps に対し、12〜20fps で動作します。

| ファイル | 中身 | 読み込み |
|---|---|---|
| `main.lua` | 名前・オプションだけの入口 | EdgeTX の起動時 (全ウィジェット分が読まれるので小さくしています) |
| `core.lua` | 設定・テレメトリ (内蔵デコーダー、MSP)・アラーム・バッテリー選択・履歴・メニュー | ウィジェットの作成時 |
| `view.lua` | 画面 | ウィジェットの作成時 |
| `rf2ui.lua` | Rotorflight settings の画面 | 初めて開いたとき |

- ボタン (メニュー、Settings、バッテリー選択のタイル、フライトログの Close、RF2 設定) は**全画面のときだけ**表示されます
  (EdgeTX の仕様)。全画面のときは左上に Touch バッジが出ます

## メニュー (全画面時、DISARM のみ)

待機画面かダッシュボードのトップバーにある **Menu** (または ENTER) で開きます。ARM すると、メニューと開いている画面は閉じます。

| 項目 | 中身 |
|---|---|
| Rotorflight settings | 公式 RF2 の設定ツールをウィジェット内で動かし、タッチで操作しやすい画面にしたもの (下記)。接続中のみ |
| Battery profile | 接続直後と同じプロファイル選択画面。接続中で `BAT#` があるとき |
| View FC settings | PID ゲイン / レート / ガバナープロファイルの閲覧 (下記)。接続中のみ |
| Erase blackbox | FC のブラックボックス (dataflash) を消去します。1 回目のタップで「Tap again: erase (NN% used)」(オレンジ、3 秒) と表示され、もう一度タップすると消去します。進み具合と結果は画面下の帯に出ます (Erasing… → 緑の Blackbox erased + 確認音・振動)。接続中で、ブラックボックスの情報が読めたときのみ |
| Flight history | この機体の飛行履歴 (下記) |
| Settings | 音声・アラーム・飛行・パック名・表示の設定 (下記) |

### Rotorflight settings
- SD に rotorflight-lua-scripts の**一式** (`SCRIPTS/RF2`・`SCRIPTS/TOOLS/rf2.lua`・`SCRIPTS/FUNCTIONS/rf2bg.lua`・
  `WIDGETS/RfStats`・`WIDGETS/RfTool`) を置いておいてください (置くだけで、rf2bg のスペシャルファンクションと RfTool ウィジェットは使いません)。
  初回は RF2 のコンパイルが走り、終わると自動で開き直します
- 公式 RF2 (lvgl 版) の画面部品だけを差し替えています (`rf2ui.lua`)。値の読み書き・保存・再起動は RF2 の処理そのままです
- メインメニューはタイル、各ページはカードや表で表示します (指で縦にスクロール)。値をタップすると下から編集パネルが出ます
  (スライダー、-10 -1 +1 +10、OK / Cancel。選択肢はボタンを並べて 1 タップで選べます)。上部に Back / Save / Menu (Reload・Reboot FC)
- Save 後、FC への書き込みが終わると緑の「Saved to the FC」を 2.5 秒表示し、確認音と振動 2 回でお知らせします。
  ARM 中などで保存できないときは RF2 の警告が出て、Saved は表示されません
- `CONFIG.tools.rf2Skin = false` にすると RF2 公式の画面になります。RTN でも戻れます
- ExpressLRS の Lua ツールは描画方式の違いでウィジェット内では開けないため、SYS > Tools からお使いください

### FC 設定の閲覧 (全画面不要)
- オプション `Page` に割り当てたスイッチを押すたびに、PID ゲイン → レート → ガバナープロファイル → 通常画面 と切り替わります
  (メニューの View FC settings からも開けます)。閲覧のみで、変更は Rotorflight settings から行います
- 閲覧中にスイッチで PID / レートのプロファイルを切り替えると、そのプロファイルの値を読み直します。ARM・切断で閉じます

### Flight history
- 飛行ごと (ローター回転 10 秒以上、`CONFIG.history.minSec`) に、切断の時点で記録します
  - `/LOGS/RotorHUD-<機体名>.csv`: 1 飛行 1 行 (日時、パック、ローター時間、消費 mAh、残量、最大 rpm・A・W、最低電圧・セル・BEC、最高 ESC 温度)
  - `/WIDGETS/RotorHUD/stats-<機体名>.txt`: 合計 (回数・ローター時間・mAh・最終日時)、パック (バッテリープロファイル) ごとの回数・mAh・最終使用、直近 6 飛行
- 画面: 合計 4 項目、パックごとの表 (Settings > Packs で名前を付けていればその名前)、直近の飛行の表
- **Reset** (タイトルの右): 1 回目で「Sure?」(赤、3 秒)、もう一度で集計を 0 に戻します。`/LOGS` の CSV はそのまま残ります

### Settings
SD の `/WIDGETS/RotorHUD/settings.txt` に保存されます。ウィジェットオプションの同じ項目 (Theme / Voice / BattLand) より優先されます。

| タブ | 項目 |
|---|---|
| Voice | 声 (試聴付き)、アラーム On/Off、振動 On/Off、効果音 On/Off (試聴付き) |
| Alarms | 着陸指示の残量 %、セル電圧 注意/危険、ESC 温度 注意/危険、BEC |
| Flight | 飛行時間の読み上げ、フライトログを閉じるまでの秒数、満充電チェック On/Off と満充電とみなすセル電圧 (既定 4.10V)、バッテリー選択を現状のまま閉じるまでの秒数 (0 = 閉じない) |
| Packs | バッテリープロファイル 1〜6 の名前 (例 `6S 5000`、16 文字まで。タップで EdgeTX のキーボードが開きます)。右に FC の容量を表示。選択画面のタイルと履歴に使われます。空にすると `Profile N` |
| Display | テーマ、fps 表示、機体画像、シンプル表示 (下記) |

設定を追加するときは、`core.lua` の `SETTINGS` に 1 行足してください (必要なら `SET.groups` にタブも)。

### シンプル表示 (Settings > Display > Simple screen)
ダッシュボードの代わりに、図形を中心にした画面を表示します。
- 左のカード: スロットルの円弧 (0〜100%、270°、下が開いた形) と、外周の目盛 (5% ごと、0 / 50 / 100% は白く長い目盛)。
  塗りの色はガバナーの状態を表します。左上に `Throttle NN%`、右上にガバナー目標を表示します。
  その内側にバッテリー残量の円弧があります (色は通常と同じく 50% / 20% で切り替わり、灰色の小さな目盛が 25 / 50 / 75%、赤い目盛が着陸指示の %)。
  中央のリングはアーム状態 (緑 = ARM、灰色 = DISARM) で、中に残量 %、`消費/容量 mAh` (容量は選択中のバッテリープロファイルのもの)、
  バッテリープロファイル (Settings > Packs の名前、無ければ `Battery #N`) を表示します。下の開いた部分にヘッドスピードを表示します
- 右上のカード: 機体画像を大きく表示します。`/IMAGES/<機体名>-L.png` (320×124、透過。`CONFIG.simple.imageW/H`)、無ければ通常の小さい画像
- 右下のカード: 飛行時間 (満量は Settings の飛行時間読み上げの秒数、Off なら `CONFIG.simple.flightSec`)、電流 (`CONFIG.simple.currentMax`)、
  ESC 温度 (満量は ESC 危険の温度、オレンジの目盛が注意の温度。注意でオレンジ、危険で赤) の 10 分割バー
- トップバー・Menu・警告はダッシュボードと同じです

### 満充電チェック
接続ごとに 1 回、値が落ち着いてから (接続の静音時間 + 1 秒後)、DISARM かつローター停止の状態で Vcel が Settings > Flight の
「Full at cell」より低ければ、画面の上に **BATTERY NOT FULL** のウィンドウを出します (オレンジの枠、注意音 + 振動)。
セル電圧と基準値、電池の形 (3.5V〜基準値に対する割合で塗り) を表示します。閉じ方: ウィンドウのどこかをタップ (全画面時) /
ENTER・RTN / Close スイッチ (バッテリー選択より先にこちらを閉じます) / ARM / 10 秒で自動 (下のバーが残り時間、`CONFIG.alarm.fullAlertSec`)

## 画面の補足
- トップバー: 警告、時刻、リンク品質 (RQly の %)、電波バー、TX 電池 (中に残量 %。Radio Setup のバッテリー範囲で換算)
- ダッシュボードの Headspeed の右上に、FC のガバナー目標ヘッドスピード (`target 2100`。PID プロファイルが変わると読み直し) を表示します
- バッテリー選択画面の下段は飛行前チェックです: ARM の可否、ガバナー目標、ブラックボックスの空き (10% 未満でオレンジ)
- ARM 警告画面では、原因に応じた対処も表示します (例: FC の CMS メニューが開いている、CLI 接続中、再起動が必要 など)

## バッテリープロファイル選択 (接続直後)

機体と接続し、DISARM で ARM 警告が無ければ、FC の 6 つのバッテリープロファイルから選ぶ画面を表示します。
- 全画面表示のとき: タイルをタップで即決定 / ダイヤルで移動して ENTER で決定 / RTN で閉じる
- 全画面でないとき: `Close` のスイッチを押すたびに次へ進み、3 秒押さなければ決定します
- **オプション `BattSW`** を ON にすると、MK3 の **SW1〜SW6 ボタン**で直接選べます (ON のボタン n = プロファイル n。
  複数が ON なら最後に ON にしたもの)。電源を入れる前にボタンを押しておけば、接続後に操作なしで自動送信されます
- **オプション `BattSel`** はダイヤル/スライダー用です (6 等分)。SW1〜SW6 はそれぞれ独立した 2 ポジションスイッチなので、
  `BattSel` に割り当てると 1 か 6 にしかなりません
- **トリムボタンで前後に送る** (全画面不要): 画面横のダイヤルと SYS/MDL/TELE/PAGE/RTN/ENTER はスイッチ・ソースとして読めませんが、
  トリムの上下はスイッチとして論理スイッチに使えます。
  例: L10 = AND, V1 = T5 下 → `BattPrev` に L10 / L11 = AND, V1 = T5 上 → `Close` に L11。
  T5 をミキサーで使っていないことが条件です (押すとトリム値自体は動きます)。実機での設定はまだ確認していません
- 選ぶまで (または ARM するまで) 表示したままにします。ARM したらすぐ閉じ、現在のプロファイルのままになります (ARM 中は送信しません)。
  Settings > Flight の「Picker keeps after」を 1 以上にすると、その秒数で現在のまま閉じます
- 決定すると `MSP_SET_BATTERY_PROFILE` (176) を CRSF で送り、`BAT#` センサーが変わったら成功です
  (「バッテリープロファイル、N」)。2 秒ごとに再送し、3 回で失敗とします (「変更できませんでした」)
- FC はこの設定を保存しない (RAM のみ) ため、電源を入れるたびに選ぶ前提です
- タイルの名前は Settings > Packs で付けられます (例 "6S 5000")。容量は接続時に FC から読みます。無効にするには `CONFIG.batteryProfile.enabled = false`
- 根拠 (ソース確認): [docs/rotorflight_notes.md](docs/rotorflight_notes.md)

## アラーム (音声 + 振動)

`core.lua` の ALARMS と `CONFIG.alarm` で判定しています。画面に出ていない間も `background()` から判定します。

| 段階 | 振動 | 音声 | 項目 |
|---|---|---|---|
| 危険 | パターン | 10 秒ごと (残量は 20 秒ごと) | 残量 ≤ `BattLand` (既定 20%) で「バッテリー、NNパーセント」「着陸してください」(以後 1% 下がるごとに残量を読み上げ)、セル電圧 < 3.50V (2 秒継続)、ESC ≥ 90℃、BEC < 6.0V、ヘッドスピードロスト (FALLBACK)、回転中の通信断 |
| 注意 | 短く 1 回 | 1 回 | 残量 ≤ `BattLand` + 10%、セル電圧 < 3.60V (2 秒継続)、ESC ≥ 80℃、飛行時間 (`flightTimeSec`、既定オフ)、ARM 不可 (ARMD ≠ 0)、満充電でない |
| 情報 | 下記 | 変化時 | ARM / DISARM・レート (RTE#)・プロファイル (PID#)・バッテリープロファイル (接続直後にも現在値)、ガバナー状態、残量 10% 刻み (着陸指示以下は 1% 刻み) |

- **振動**: ARM で 1 回、DISARM で 2 回、レート・PID プロファイルの切り替えで 1 回 (同じスイッチで一緒に変わるので 1 回にまとめます)
- **効果音** (playTone): 接続 (上がる 2 音) / 切断 (下がる 2 音) / 注意 (2 回) / 危険 (高い 3 連) を音声の前に鳴らします。
  Settings > Voice > Sound effects で On/Off と試聴 (Test) ができます。Mute スイッチで音声と一緒に止まります。音の高さ・長さは `CONFIG.alarm.toneEffects`
- 接続・切断は EdgeTX 本体が読み上げるので、ウィジェットからは言いません (`CONFIG.alarm.edgetxLinkVoice = true`)。
  接続直後のウィジェットの報告 (ARM・レート・プロファイル・バッテリープロファイル・選択の案内) は、
  本体の音声と重ならないよう 3 秒遅らせています (`connectQuietSec`)。回転中の切断は振動のみです。
  本体の接続音声を止める設定 (モデルの「テレメトリアラーム無効」) は RSSI/RQly 低下の警告も止めてしまうので、おすすめしません
- 音声ファイルは `sdcard/SOUNDS/rf/<声>/` にあります (日本語は VOICEVOX、英語は Piper で生成。[docs/voicevox_script.md](docs/voicevox_script.md))。
  音量は RMS -14 dBFS に揃えています
- EdgeTX 標準機能でのバックアップ案: [docs/alarms_native.md](docs/alarms_native.md)。設定したら `CONFIG.alarm.nativeBackup = true`

## 設定

**コード側** — `core.lua` 冒頭の `CONFIG`

| キー | 既定 | 内容 |
|---|---|---|
| `theme` | `"color"` | `"color"` / `"mono"` / `"cyan"` (送信機側の Theme オプションや Settings が優先) |
| `showModelImage` | `true` | 機体画像の表示 (`/IMAGES/<機体名>.png`) |
| `modelImageW` / `modelImageH` | 186 / 46 | 機体画像ファイルの寸法 (この枠ぴったりで作ってください) |
| `vCellGood` / `vCellWarn` | 3.8 / 3.6 | セル電圧の色分けの閾値 |
| `escTempWarn` | 90 | ESC 温度の警告の閾値 (℃) |
| `rpmRunningThreshold` | 50 | ローター回転中とみなす回転数 (最大値・最小値の記録条件に使用) |
| `flightLogTimeoutSec` | 0 | フライトログを自動で閉じるまでの秒数 (0 = 閉じない。Settings でも変更可) |
| `txBattery.minV` / `maxV` | 6.4 / 8.4 | TX 電池の % の換算範囲 (Radio Setup のバッテリー範囲が読めないときだけ使用) |
| `sensors.*` | — | センサー名の候補リスト (先頭が実機で確認した名前) |

**送信機側** — ウィジェットを長押し → Edit

| オプション | 内容 |
|---|---|
| `Theme` | `0`=color / `1`=mono / `2`=cyan (数値で指定します) |
| `Mute` | 消音に使うソース (スイッチ SA など、または論理スイッチ)。値が 0 より大きい間 (スイッチ下 / LS 真) は音声と注意の振動を止めます。危険の振動は止めません。空欄なら消音しません |
| `Close` | フライトログを閉じるソース (押しボタン SH など)。押した瞬間に待機画面へ戻ります。全画面でなくても使えます (全画面表示中はタップ・ENTER でも閉じられます)。バッテリープロファイル選択画面では「次のプロファイルへ」、満充電チェックのウィンドウが出ているときはそれを閉じます |
| `BattLand` | 着陸指示を出す残量 % (10〜50、既定 20) |
| `BattSW` | ON で SW1〜SW6 ボタンがバッテリープロファイル 1〜6 を選びます |
| `BattSel` | バッテリープロファイルを選ぶダイヤル/スライダー (6 等分。SW ボタンには使えません。空欄なら使いません) |
| `BattPrev` | 選択画面で 1 つ前のプロファイルへ (`Close` が次へ)。トリム → 論理スイッチ経由を想定しています |
| `Page` | FC 設定の閲覧ページを順に開くスイッチ |
| `Voice` | アラームの声。`0`=No.7 アナウンス / `1`=青山龍星 / `2`=玄野武宏 / `3`=冥鳴ひまり / `4`=Voidoll / `5`=ずんだもん / `6`=English 男性 / `7`=English 女性 |

**機体画像**: 機体名と同じ名前の PNG (例: `GOOSKY S2.png`) を `/IMAGES` に置いてください。表示は**等倍 1:1** なので、
**186×46 の透過キャンバスに、縮小した機体を中央に配置**したファイルを作ってください。シンプル表示用は
`<機体名>-L.png` (320×124) です。接続中に機体名が FC の名前に変わる場合は、その名前で探します。
メーカーの画像などから作ったものは著作権の都合でリポジトリに含めていないので、各自でご用意ください。

## 確認済みのセンサー名 (実機の Telemetry 一覧 42 項目から確定)

| 用途 | 名前 | 用途 | 名前 |
|---|---|---|---|
| ガバナー状態 | `Gov` | ヘッドスピード | `Hspd` |
| 電圧 / セル電圧 / セル数 | `Vbat` / `Vcel` / `Cel#` | 電流 | `Curr` |
| ESC 温度 | `Tesc` | 残量 % | `Bat%` |
| 消費容量 (mAh) | `EscC` | スロットル | `Thr` |
| BEC 電圧 | `Vbec` | レートプロファイル / PID プロファイル | `RTE#` / `PID#` |
| ARM フラグ | `ARM` | アーミング無効フラグ | `ARMD` |
| バッテリープロファイル | `BAT#` | 通信品質 | `RQly` (`1RSS`, `RSNR`, `RSSI`) |

- `ARM`: `0`/`2` = DISARM、`1`/`3` = ARM
- `ARMD`: 0 以外で全画面の警告を出します。`67108872` は「ARM スイッチが ON のまま機体の電源を入れた」状態です
- 消費容量・残量は DISARM で 0 に戻るため、ローター回転中だけ最大容量 / 最小残量を記録しています

## 開発

### VS Code

`sdcard/WIDGETS/RotorHUD/` の core.lua / view.lua / rf2ui.lua を編集します。拡張機能 `sumneko.lua` を入れると、
`.luarc.json` と `types/edgetx.lua` により EdgeTX API の補完・型チェックが効きます。
SD への反映は「インストール」の `deploy.ps1` コマンドでできます。

### シミュレータで確認する (EdgeTX Companion 2.12)

前提: Companion 2.12.0 (`C:\Program Files (x86)\EdgeTX\Companion 2.12`)。TX16S MK3 の 800×480 シミュレータを使います。

```powershell
# 起動 (Theme: 0=color / 1=mono / 2=cyan)。初回は SD イメージを sim\sdcard に自動作成
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sim.ps1 -Theme 0
# LCD を 800×480 等倍で保存 (sim\captures\)。シナリオ 1 周 = 140 秒
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sim-capture.ps1 -Count 25 -Interval 6
```

- `sim.ps1` は `sdcard\` を `sim\sdcard` にコピーし、**コピー側だけ** `CONFIG.simulate = true` にします
  (`sdcard\` の core.lua は false のまま)。Companion に「RotorHUD Sim (TX16S MK3)」プロファイルも作ります。
- `simulate = true` のとき、`readTelemetry` は `simulateTelemetry` のシナリオの値を返します
  (standby → armwarning → スプールアップ → 飛行 → 低電圧・ESC 高温 → THR-OFF → DISARM → flightlog)。
- `sim-capture.ps1` はシミュレータのカメラボタン (LCD をクリップボードへコピー) をクリックします。
  ボタンの位置は 2560×1440 の環境で測った値なので、画面構成が違う場合は `-ButtonX/-ButtonY` で調整してください。
- シミュレータのフォント描画が実機と同じかは確認していないので、最終的な判断は実機で行っています。
- `sim\` は .gitignore 済みです (SD イメージとキャプチャ)。モデル・ラジオ設定の元は `scripts\sim-template\` にあります。

### 画面なしのテスト (tools/luatest)

`cd tools/luatest; npm install; npm test` (Node + fengari。EdgeTX・lvgl・ファイル入出力の代役付き)。
`node run.js ../../sdcard/WIDGETS/RotorHUD/main.lua driver.lua [ui|full|simple|cpu longflight|...]` で個別のシナリオを、
`decoder_test.lua` でデコーダーと MSP を確認できます。

### 音声の作り方

- 日本語: `tools/voice/voices.csv` (文言) と `voicesets.csv` (声) → `make_voices.ps1` (VOICEVOX が必要)
- 英語: `tools/voice/voices_en.csv` → `make_voices_en.py` (Piper と音声モデルが必要。使い方はスクリプト冒頭に記載)

### フォルダ構成

```
RotorHUD/
├─ sdcard/                      SD カードのルートと同じ構造 (deploy でそのままコピーされます)
│  ├─ WIDGETS/RotorHUD/         ウィジェット (main.lua 入口 / core.lua / view.lua / rf2ui.lua)
│  ├─ IMAGES/                   TX 電池のアイコン (機体画像は各自で追加)
│  └─ SOUNDS/rf/<声>/           アラーム音声 (日本語 6 種・英語 2 種。クレジットと規約は CREDITS.txt)
├─ tools/diagtest/sdcard/       診断ウィジェット (フォント・ビットマップ実測 DiagTest、描画速度 DrawBench / LvglBench)
├─ tools/voice/                 音声の文言と生成スクリプト (VOICEVOX / Piper)
├─ tools/luatest/               画面なしのテスト (Node + fengari)
├─ types/edgetx.lua             lua-language-server 用の EdgeTX API 宣言 (使用分のみ)
├─ scripts/deploy.ps1           SD カードへのコピー
├─ scripts/sim.ps1, sim-capture.ps1, sim-template/   シミュレータの起動・LCD キャプチャ
├─ docs/
│  ├─ architecture.md           ファイル構成・処理の流れ・画面遷移
│  ├─ project_summary.md        知見のまとめ
│  ├─ voicevox_script.md        音声の生成方法と鳴るタイミング
│  ├─ alarms_native.md          EdgeTX 標準機能でのアラームのバックアップ手順
│  ├─ rotorflight_notes.md      Rotorflight 4.6 のソースから確認したガバナー状態・ARM 不可フラグ
│  └─ mockups/                  GUI 案の HTML モック
└─ .luarc.json, .editorconfig, .gitignore
```

### 実機で測った値 (この機種・このファームウェア固有)

`lcd.sizeText("0123456789")` による実測です。他の機種・バージョンでは再測定が必要です (`tools/diagtest` をお使いください)。

| フォント | 1文字幅 | 高さ |
|---|---|---|
| (既定) | 12 | 27 |
| `SMLSIZE` | 10 | 23 |
| `MIDSIZE` | 19 | 42 |
| `DBLSIZE` | 25 | 55 |
| `XXLSIZE` | 51 | 93 |

- `getTime()` の単位は **10 ms (1/100 秒)** です。秒に直すときは `/100`
- タッチとキー、lvgl のボタンは**ウィジェットが全画面表示のときだけ**有効です (EdgeTX 2.12)
- EdgeTX の Lua (5.3) では文字列のメソッド呼び出し (`s:match()` など) が使えないため、`string.match(s, ...)` の形で書いています。
  また `12.5 == math.floor(12.5)` が true になるので、整数の判定には `isWhole` を使っています
- 1 フレームの Lua 命令数が多すぎると「CPU limit」で止まります。luatest の `cpu longflight` で画面ごとの最大値を確認しています
  (目安: 約 30,000 で停止。現在の最大はフライトログを開くフレームの約 16,000)

## 注意・未確認の項目

- 実機 (TX16S MK3) で動作を確認しながら開発しています。実機でまだ確認していないもの:
  トリム → 論理スイッチによる操作、ARM 警告画面の CMS メニューの対処表示
- `scripts/deploy.ps1` が環境に合わない場合は、`sdcard/` の中身を SD のルートへ手でコピーしてください
  (その際、SD の `WIDGETS/RotorHUD/*.luac` を消しておくと確実です)
- EdgeTX 2.12 のウィジェットオプションに文字列の選択型は無いため (VALUE/COLOR/SOURCE/BOOL)、Theme などは数値で指定します
- 型の宣言 (`types/edgetx.lua`) は使っている API だけです。未宣言のグローバルは警告になるので、必要に応じて追加してください
