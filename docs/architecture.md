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

- `tick(wgt)`: テレメトリ読み取り → 接続/切断の判定 → 全トラッカー → `updateFlightSamples` → `runAlarms`
- `refresh` (表示中) と `background` (非表示中) の両方が `tick` を呼ぶ。描画は `refresh` だけ
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
| flightlog | 切断から 60 秒経過、またはタップ (フルスクリーン時のみ届く) | standby |
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

## 待機画面 (`drawStandby`)

- トップバーなし (画面上端から描く。時計と TX 電池は待機画面自身に表示)
- 上段パネル: 大きな時計 (XXLSIZE) + 日付 | 機体画像 + 機体名
- 状態帯: 「Waiting for connection」(ドットが増減) + 2 秒周期で動くスキャンバー
- タブ (26/30/22/22%): TX battery (電圧、%、残量色の帯) / Last flight (このセッションの飛行時間と消費 mAh) /
  Voice (選択中の声) / Alarms (On / Muted / Off、色の帯)

## フライトログ (`drawFlightLog`)

- 閉じ方: タイトル帯の Close ボタン (タップ、全画面時のみ) / Enter (全画面時のみ) /
  オプション `Close` のスイッチ (立ち上がりで閉じる。`tick` で判定するので全画面でなくても効く) / 60 秒経過

- タイトル帯 (Flight log / 機体名 / 自動終了までの残り秒) → 4 タブ × 2 段 (`drawTab`) → グラフ 3 枚
- 上段: Flight time / Max rpm (avg) / Max amps (avg) / Max power (V×A の最大)
- 下段: Used mAh (残量%) / Min volt (最小セル電圧) / Min Bec / Max ESC
- グラフ: Headspeed / Current / Voltage。`updateFlightSamples` がローター回転中だけ 1 秒ごとに記録
  (`wgt.samples`)。400 点を超えたら隣同士を平均して半分にし、間隔を倍にする (メモリ固定)。
  横軸は回転していた時間。描画は 2px 幅の矩形を並べた面グラフ (`drawSeriesChart`)
- 見出しの max/min はフレーム毎のトラッカー値 (タブと一致)。グラフの縦軸スケールだけサンプルから決める
- 目盛り: 縦軸は 1/2/5×10^n の刻みで約 4 区切り (左 40px に数値、線は背景に実線 + 塗りの上に切れ目)、
  横軸は 5s〜1h の刻みから 3 区切り以下になるものを m:ss で
- 負荷対策 (CPU limit): サンプルの集計 (`flightSampleStats`) と各列の高さ (`wgt.chartCache`) は
  サンプルが変わるまでキャッシュ。集計したフレームはグラフ本体を描かず次フレームに回す
- 再接続時に `resetTelemetryState` がサンプルも初期化

## 変更するときの目安

- 色・テーマ → `buildColorTheme` / `COLOR_THEMES`
- センサー名が違う → `CONFIG.sensors` の候補リスト先頭に追加
- 文字がはみ出す → まず `FONT_SPECS` の実測値と `fitFont` の引数を確認 (推定で調整しない)
- 新しいオプション → 末尾の `options` と `refresh` 内の読み取り (EdgeTX の制約: 数値/色/ソース/真偽)
