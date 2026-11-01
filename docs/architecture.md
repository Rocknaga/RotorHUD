# main.lua の構造

`sdcard/WIDGETS/RFTelem/main.lua` (約 1740 行、単一ファイル)。行番号は目安。
関数名で検索するのが確実 (`Ctrl+T` / アウトライン)。

## 先頭から順に

| 範囲 (目安) | 内容 |
|---|---|
| 1–144 | ヘッダーコメント (INSTALL / 対象機種 / 画像 / 用語 / 再接続 / フライトログ / テーマ) |
| 145 | `CONFIG` — センサー候補名、閾値、ガバナー色・状態番号、画像パス、テーマ、TX 電池範囲 |
| 263–347 | `buildColorTheme` / `COLOR_THEMES` (`color` / `mono` / `cyan`) / `COLOR` |
| 351–435 | ヘルパー: `resolveSensor` `getGovColor` `getChargeColor` `getTxBatteryPct` `decodeGovernor` `fmt` `fmtTime` `fmtUnit` |
| 451–458 | `FONT_SPECS` (実測値) / `fitFont` |
| 476–560 | ビットマップ: `tryLoadBitmap` `drawBitmapFit` `ensureModelImage` `ensureTxBatteryIcons` `pickTxBatteryIcon` |
| 571–602 | ウィジェット API: `create` `update` `background` |
| 604 | `readTelemetry` — 全センサーを `t` テーブルに集約 |
| 661–790 | 状態トラッカー: `updateFlightTimer` `updateMaxCurrent` `updateMinVoltage` `updateMinBecVoltage` `updateMaxEscTemp` `updateArmWarning` `updateMaxCapacity` `updateMaxHeadspeed` `updateMinCharge` `isTelemetryConnected` `resetTelemetryState` |
| 817–1060 | 描画部品: `drawIconChip` `drawBigStat` `drawEmbeddedStat` `drawStatBar` `drawBatteryIcon` `drawSignalBars` `drawDotChip` |
| 1058–1085 | 小・中ゾーン用: `drawSmall` `drawMedium` |
| 1086–1225 | アイコン / 図形: `*IconFn` 群、`drawHollowRect`、`drawChamferedRect` (角丸の代用) |
| 1228–1346 | 特殊画面: `drawTransitionOverlay` `drawStandby` `drawFlightLog` `drawArmSwitchWarning` |
| 1348 | `drawLarge` — 800×480 本画面 (案C「インストルメントクラスター」) |
| 1641 | `refresh` — 毎フレームの入口 |
| 1730– | `options` (`Theme` のみ) と `return { name = "RF Telem", ... }` |

## 毎フレームの処理 (`tick`)

- `tick(wgt)`: `rfTelemetryPump` (CRSF キューを最大 20 フレーム読み、0x88 → `setTelemetryValue` でセンサー化、
  0x7B → MSP 応答の組み立て) → テレメトリ読み取り → 接続/切断の判定 → 全トラッカー → `updateFlightSamples` → `runAlarms`
- `refresh` (表示中) と `background` (非表示中) の両方が `tick` を呼ぶ。描画は `refresh` だけ
- 末尾で `bpUpdate` (バッテリープロファイル選択) と `rfMspUpdate` (接続後に MSP_BATTERY_CONFIG を最大 6 回要求) を呼ぶ
- RF TELEMETRY 節: `RF_SENSORS` (sid → 名前・単位・桁・解読関数、公式と同じ全 ID)、`decodeCustomFrame`、
  `decodeMspFrame`、`mspRequest` (MSP v1 単一フレーム)、`parseBatteryConfig`
- `runAlarms`: 危険 (`critical`、繰り返し) / 注意 (`caution`、1 回、ヒステリシスで再武装) /
  情報 (`onChange`、接続直後の初期値では鳴らさない)。`latch` が継続時間とヒステリシスを持つ
- 消音: オプション `Mute` (SOURCE) の値 > 0 で音声と注意の振動を止める (`isMuted`)

## 画面の切り替え (`drawLarge` 内の screenType)

| 現在の画面 | 条件 | 次の画面 |
|---|---|---|
| standby ("Waiting for connection") | 接続 (`RSSI` > 0 または 信号センサー > 0) | dashboard |
| dashboard | `ARMD` ≠ 0 (遅延なし) | armwarning |
| armwarning | `ARMD` = 0 | dashboard |
| dashboard / armwarning | 切断 (接続済みだった後のみ) | flightlog |
| flightlog | Close (ボタン / Enter / Close スイッチ)。時間では閉じない (CONFIG.flightLogTimeoutSec = 0) | standby |
| flightlog | 再接続 | dashboard (`resetTelemetryState` 実行) |

- armwarning の文言: `ARMD` = 67108872 → "ARM SWITCH WAS ON AT POWER-UP"、それ以外 → "ARMING DISABLED" + コード
- armwarning は接続中のみ (未接続時は standby / flightlog が優先)

- 画面種別が変わるたびに `screenTransitionTime` を更新し、`drawTransitionOverlay`
  (0.5 秒の ease-out ワイプ + スキャンライン) を各画面の出口で重ねる。
- 電源投入直後はフライトログを出さない (`showFlightLog` は初期 false。接続→切断の瞬間だけ true)。
- 再接続時は `resetTelemetryState` で 最大/最小値・フライトタイマー・センサーキャッシュを初期化。
- フライトタイマーは `getTime()/100` 秒を使い、ローター停止中は一時停止して接続が切れるまで積算。

## `drawLarge` のレイアウト (800×480 基準、比率で配置)

1. トップバー (面取り矩形): 左に警告 (低セル電圧・ESC 高温。赤文字、複数は 2 秒ごとに切替)、
   右に日時 `YYYY/MM/DD HH:MM`・信号アイコン・TX 電池 PNG
2. クラスターパネル (高さ 32%): 幅 30/40/30。中央 Headspeed (数値 XXLSIZE + rpm、ラベル行に max)、
   左 Volt(+min)/Vcel、右 Current(+max)/Bec volt(+min)
3. 中段 (13.5%): 1 枚のパネルを 4 等分し Arm / Governor / Flight (MM:SS) / Profile/Rate (`PID/RTE`)。
   Arm・Governor は左端の色帯で状態表示 (Armed=緑・Disarmed=灰、Governor は CONFIG.govColors)。
   Gov センサーが無いときは Governor タブが Motor On/Off になる
- クラスターと中段の全項目は `drawTab` で描く: 上 18px がラベル行 (アイコン + 灰色ラベル、右に min/max)、
  下に値 (白、最大 MIDSIZE)。文字幅は `lcd.sizeText` で実測 (`fitFontMeasured`)
4. Battery バー (18%): バー内に白文字で `% / mAh` (DBLSIZE 上限)
5. フッター (15%): Throttle バー (`% / ℃`、白文字固定) とモデル名カード
   (機体画像 186×46 を等倍・中央、その下にモデル名)

## バッテリープロファイル選択 (`drawBattSelect` / `bpUpdate`)

- `wgt.bp.phase`: wait (BAT# 待ち・ARM 警告中は待つ。BAT# が 5 秒来なければ終了) → pick (選択中) →
  send (`mspSetBatteryProfile` を 2 秒ごと最大 3 回、BAT# == 目標で成功) → done (結果を 1.5 秒表示)
- 入力: `tick` の Close スイッチ立ち上がり = `bpStep`、`refresh` のタップ/Enter = `bpChoose`、ダイヤル = `bpStep`、RTN = 閉じる
- ARM / 切断で即終了。画面種別 `battselect` は armwarning の次、dashboard の前

## 設定メニューとツールホスト (TOOLS HOST 節、`refresh` の前)

- `wgt.menu = { sel }`: 全画面時、standby / dashboard で ENTER かタップ (DISARM、h ≥ 160)。`drawMenu` が
  `MENU_ITEMS` (rf2 / elrs / batt) を描き、行の矩形を `wgt.menuRects` に置く。使えない項目は理由付きで灰色 (`menuItemState`)
- `openMenuItem`: batt → `wgt.bp` を pick で開く。rf2 / elrs → `startRf2` / `startElrs` を pcall し `wgt.hosted = { kind, run, compiling }`
- `startRf2`: 公式 `tool.lua` と同じ手順で、常に `ui_lcd` を返す (lcd 描画のため)。未コンパイルなら `COMPILE/compile.lua`
  (1 フレーム 1 ファイル、終わると 1 を返す) を返し、終了時に `refresh` が開き直す
- `refresh` 冒頭: `wgt.hosted` があれば、ARM → 閉じる / 全画面でない → 閉じる / RTN 2 回 (1 秒以内) → 閉じる /
  それ以外は `run(event, touchState)` を呼んで return (ウィジェットの描画はしない)。0 以外が返ったら閉じる
- RF2 の GUI 化 (`rf2SkinInstall`、`CONFIG.tools.rf2Skin`): `rf2.executeScript` を包み、`LCD/shared` `LCD/waitMessage`
  `LCD/messageBox` `LCD/popupMenu` `LCD/mainMenu` `LCD/page` を `RF2_SKIN` の関数 (`rf2Skin*`) に差し替える。
  ui_lcd.lua の状態遷移・MSP・保存はそのまま。各モジュールは描画しながら `RF2UI.hits` にタップ領域
  `{x, y, w, h, fn, ev}` を積み、`refresh` が次のフレームで `rf2SkinInput` によりタップを照合して fn を実行し、
  ev (ENTER / EXIT / ENTER_LONG / PAGE) を ui_lcd に渡す。後に積んだもの (ポップアップ・タイトル帯) が優先。
  ページは `rf2CardModel` が RF2 の labels/fields を y 座標で行にまとめてカードに組み直す: 単独ラベル = 見出し (新カード)、
  見出しより右の単独ラベル = 表示専用の値、ラベル 2 個以上の行 = 表の列見出し、その後の「行見出し + 無名フィールド」 = 表の行、
  それ以外 = タイル (3 列)。モデルは Page.fields が入れ替わったら作り直す。編集パネル (y 296〜) はスライダー
  (`RF2UI.slider`、ドラッグは touchState.startY で判定) と ±、選択肢 6 個以下はボタン。
  `wgt.fcApi` (rfMspUpdate が MSP_API_VERSION で先に取得) があれば `ui_init` を差し替えて API 待ちを省く。
  ホスト側は RF2 の実行後に `rf2.mspQueue:processQueue()` をもう 1 回呼ぶ。ポップアップは `RF2UI.backdrop` (直前の画面) の上に描く
  (ウィジェットは毎フレーム全描画のため)
- `stopTool`: `wgt.hosted`・`wgt.menu` と RF2 の唯一のグローバル `rf2` を消して GC。エラーは `wgt.toolMsg` で 3 秒表示
  (シミュレータでは /LOGS/rftelem_alarms.log にも)
- ホスト中は `rfTelemetryPump` と `rfMspUpdate` が止まる (ツールが `crossfireTelemetryPop` の全フレームを受け取るため)。
  `tick` (トラッカー・アラーム) は続く

## 待機画面 (`drawStandby`)

- トップバーなし (画面上端から描く。時計と TX 電池は待機画面自身に表示)
- 上段パネル: 大きな時計 (XXLSIZE) + 日付 | 機体画像 + 機体名
- 状態帯: 「Waiting for connection」(ドットが増減) + 2 秒周期で動くスキャンバー
- タブ (26/30/22/22%): TX battery (電圧、%、残量色の帯) / Last flight (このセッションの飛行時間と消費 mAh) /
  Voice (選択中の声) / Alarms (On / Muted / Off、色の帯)

## フライトログ (`drawFlightLog`)

- 閉じ方: タイトル帯の Close ボタン (タップ、全画面時のみ) / Enter (全画面時のみ) /
  オプション `Close` のスイッチ (立ち上がりで閉じる。`tick` で判定するので全画面でなくても効く)。時間制限なし

- タイトル帯 (Flight log / 機体名 / Close ボタン) → 4 タブ × 2 段 (`drawTab`) → 統合折れ線グラフ 1 枚
- 上段: Flight time / Max rpm (avg) / Max amps (avg) / Max power (V×A の最大)
- 下段: Used mAh (残量%) / Min volt (最小セル電圧) / Min Bec / Max ESC
- グラフ: Headspeed / Current / Voltage。`updateFlightSamples` がローター回転中だけ 1 秒ごとに記録
  (`wgt.samples`)。400 点を超えたら隣同士を平均して半分にし、間隔を倍にする (メモリ固定)。
  横軸は回転していた時間
- グラフ (`drawFlightChart`): 3 系列を 1 枚に重ねた 2px の折れ線 (`lcd.drawLine`、シミュレータで動作確認済み。
  無ければ 2×2 の点)。各系列を `chartAxis` で 4 区切りの軸に合わせ、目盛り線は共通。
  目盛り数字は左に Headspeed、右に Current と Voltage を各系列の色で。刻みは 1/1.2/1.5/2/2.5/3/4/5/6/8×10^n。
  凡例はラベル行 (色 + 名前 + max/min。max/min はトラッカー値でタブと一致)
- 横軸: 5s〜1h の刻みから 3 区切り以下になるものを m:ss で
- 負荷対策 (CPU limit): サンプルの集計 (`flightSampleStats`) と折れ線の頂点 (`wgt.chartCache`、8px ごと) は
  サンプルが変わるまでキャッシュ。集計したフレームはグラフ本体を描かず次フレームに回す
- 再接続時に `resetTelemetryState` がサンプルも初期化

## 変更するときの目安

- 色・テーマ → `buildColorTheme` / `COLOR_THEMES`
- センサー名が違う → `CONFIG.sensors` の候補リスト先頭に追加
- 文字がはみ出す → まず `FONT_SPECS` の実測値と `fitFont` の引数を確認 (推定で調整しない)
- 新しいオプション → 末尾の `options` と `refresh` 内の読み取り (EdgeTX の制約: 数値/色/ソース/真偽)

## lvgl 版 (LVGL VIEW 節、CONFIG.lvgl = true)

- `refresh` は tick の後 `LV.refresh` に渡す。画面種別 (`LV.screenType`、lcd 版と同じ判定) / テーマ / ゾーン / 全画面かどうか /
  機体画像 / ARMD が変わったときだけ `LV.build` (lvgl.clear + lvgl.build) で組み直し、毎フレームは `LV.update` が `LV.v` を埋める
- 部品: `LV.rect` `LV.text` (中心 y 指定、実測行高) `LV.button` `LV.tab` (drawTab と同じ配置) `LV.bar` `LV.topBar`
- 画面: buildDashboard / buildStandby / buildArmWarning / buildBattSelect / buildFlightLog (グラフは line の pts、画面に入った時に 1 回計算) /
  buildMenu (表示は visible 関数) / buildToolMsg / buildSmall (小ゾーン)
- ボタンは全画面のときだけ作られる (EdgeTX の仕様)。全画面でない時は Close スイッチ等の従来の操作が有効
- RF2: `startRf2Lvgl` が公式 `ui_lvgl_runner` を返し、ホスト中は RF2 がウィジェットの lvgl ツリーを使う。2 が返ったら閉じて組み直す。
  ARM・全画面解除で閉じる。`wgt.fcApi` があれば `ui_init` を差し替えて API 待ちを省く
