# RF Telem の構造

`sdcard/WIDGETS/RFTelem/` の 4 ファイル。EdgeTX 2.11 以降の lvgl ウィジェット (lcd 描画は 2026-11-02 に削除)。
行番号は変わるので、関数名・節の見出し (`-- ===== XXX =====`) で探す。

| ファイル | 役割 | 読み込み |
|---|---|---|
| `main.lua` | 名前・オプション・`useLvgl = true` と、create/update/refresh/background の中継だけ | EdgeTX 起動時 (全ウィジェットの main.lua が読まれるので小さく保つ) |
| `core.lua` | CONFIG・色・ヘルパー・設定 (SET)・履歴 (HIST)・テレメトリ・トラッカー・アラーム・RF TELEMETRY (デコーダー/MSP)・FC 閲覧データ (FC)・バッテリー選択・tick・メニュー動作・RF2 の起動・refresh | ウィジェット作成時に main.lua が `loadScript(...)(DIR)` |
| `view.lua` | 画面 (LV)。core の `R` を受け取り `R.LV` に入る | core の直後に main.lua が読み込む |
| `rf2ui.lua` | RF2 設定画面の差し替え (LV.rf2) | RF2 を初めて開いたとき `R.rf2Skins()` |

- ファイル間の受け渡しは core の `R` テーブル (末尾の EXPORTS)。view / rf2ui は冒頭で `local fmt = R.fmt` のように取り込む。
  `COLOR` はテーマで差し替わるので、view / rf2ui では `R.COLOR` を読む代理テーブル
- Lua の 1 チャンクの上位 local は 200 まで (core は約 120)。新しいものは既存テーブル (LV / FC / SET / HIST / R) のフィールドに
- EdgeTX の Lua では文字列のメソッド呼び出し (`s:match()`) が使えない。`string.match(s, ...)` で書く

## 1 フレームの流れ

1. `main.lua` の refresh → `core.refresh`
2. テーマ (Settings の値、なければ Theme オプション) を決めて `R.COLOR`
3. `tick(wgt)`: `rfTelemetryPump` (CRSF キューを読み、0x88 → `setTelemetryValue`、0x7B → MSP 応答) → `readTelemetry` →
   接続/切断の判定 (切断時に `HIST.record` とフライトログ) → トラッカー → `runAlarms` → `bpUpdate` → `rfMspUpdate` →
   Close / BattPrev / Page スイッチの立ち上がり
   - RF2 を開いている間は 5 フレームに 1 回 (デコーダーも止めて RF2 に受信を渡す)
4. `R.LV.refresh`: RF2 を開いていればその run を呼ぶ。そうでなければ画面種別を決め、変わったときだけ `LV.build`
   (lvgl.clear + build)、毎フレームは `LV.update` が `LV.v` を埋める (ラベルの文字・色・幅は LV.v を読む関数)
- background (画面に出ていない間) は tick だけ

## MSP (接続後、1 つずつ・1.5 秒間隔・各 6 回まで)
`FC.startup`: MSP_API_VERSION (1) → MSP_PILOT_CONFIG (12、機体名を FC に合わせるか) → MSP_NAME (10) →
MSP_BATTERY_CONFIG (32、各プロファイルの容量) → MSP_GOVERNOR_PROFILE (148、目標ヘッドスピード。
PID# が変わると再要求) → MSP_DATAFLASH_SUMMARY (70、ブラックボックス)。FC 閲覧画面を開いている間はそのページ (112/111/148) が優先。
バッテリープロファイル変更は MSP_SET_BATTERY_PROFILE (176)、結果は BAT# センサーで確認

## 画面 (`LV.screenType`)

| 画面 | 条件 |
|---|---|
| settings | `wgt.settings` (Menu > Settings、全画面のみ) |
| history | `wgt.history` (Menu > Flight history、全画面のみ) |
| standby | 未接続でフライトログを出していない |
| flightlog | 切断後 (Close ボタン / Enter / Close スイッチ / 再接続まで。Settings で時間制限も可) |
| armwarning | 接続中で ARMD ≠ 0 |
| battselect | 接続直後のバッテリー選択 (`wgt.bp`、BAT# が来てから) |
| fcview | FC 設定の閲覧 (`wgt.infoView`、Page スイッチか Menu) |
| simple | それ以外で `CONFIG.simple.on` (Settings > Display > Simple screen)。`LV.buildSimple` (円弧 = lvgl arc、目盛 = line)。大きい機体画像は `wgt.modelLargePath` (`ensureModelImage` が `-L.png` の有無を見る) |
| dashboard | それ以外 |

- 組み立ての主な部品: `LV.rect` `LV.text` (中心 y 指定、実測行高) `LV.button` `LV.tab` (ラベル行 + 値) `LV.bar` `LV.topBar` `LV.touchBadge`
- ボタン (button / slider / textEdit) は全画面のときだけ EdgeTX が作る。全画面の出入りで組み直す
- 全画面でないとき左上 62×62 に EdgeTX ボタンが出るので、左上 68×68 (`LV.ICON`) には何も置かない
- フライトログは統計 (最大 400 サンプル) の集計を組み立ての 1 フレーム前に行い、グラフは 8px ごとの折れ線 (CPU limit 対策)

## RF2 (Rotorflight settings)
- `startRf2Lvgl`: 公式 `ui_lvgl_runner` を RfTool ウィジェットと同じ手順で起動。`rf2.executeScript` を包み、
  `ui_init` は API 版が分かっていれば省略、LVGL/mainMenu・page・messageBox・popupMenu・waitMessage は rf2ui.lua の版を返す
- 編集シート: 数値は native slider + ±、選択肢はボタン。数値は `field:change(v, page)` の後に値を入れ、選択肢は値を入れて `postEdit`
  (RF2 の LVGL/page.lua と同じ)。Save は `page:write()`、RF2 がページを読み直したら成功として Saved 表示 + 音 + 振動
- ARM・全画面解除で閉じる (`stopTool`)

## 設定と履歴
- `SETTINGS` (core): group / label / kind (number・bool・choice・text) / apply。Settings 画面はここから自動で作る。値は settings.txt
  (text = パック名、lvgl textEdit。EdgeTX は length バイトの NUL 詰めで返すので SET.set で制御文字と前後の空白を落とす)
- `HIST` (core): 切断時に CSV へ 1 行、stats-<機体名>.txt の合計・パック・直近を更新。履歴画面は stats を読む。
  `HIST.reset` は stats だけ空に (履歴画面の Reset)
- ブラックボックス消去 (`FC.eraseUpdate`、tick から): `wgt.erase` があれば MSP_DATAFLASH_ERASE (72) → 応答後 2 秒ごとに
  MSP_DATAFLASH_SUMMARY (70)、flags bit0 (ready) で完了。60 秒で打ち切り、切断で中止。進行は wgt.toolMsg (色付きの帯)

## 検証
- `tools/luatest`: `node run.js ../../sdcard/WIDGETS/RFTelem/main.lua driver.lua [args]`。lvgl と io の代役付き
  (不正なプロパティはエラー、全画面でないとボタンを作らない、ウィジェットのコードからの文字列メソッド呼び出しはエラー)。
  `ui` で Menu → Settings → FC 閲覧 → フライトログの Close → 履歴まで自動でタップし、履歴の中身も検査。
  `cpu longflight` で画面ごとの Lua 命令数。`decoder_test.lua` でデコーダーと MSP
- シミュレータ: `scripts/sim.ps1` (コピー側の core.lua だけ simulate = true)
