# RFTelem — Rotorflight テレメトリウィジェット (EdgeTX / TX16S MK3)

Rotorflight 搭載ヘリのテレメトリを、EdgeTX の Color LCD ウィジェットとして表示する Lua ウィジェット。
Claude との対話で開発してきたものを、VS Code 上の通常のプロジェクトとして引き継ぐためにまとめたもの。

| 項目 | 内容 |
|---|---|
| 対象送信機 | RadioMaster TX16S MK3 (800×480) |
| 対象ファームウェア | EdgeTX v2.12.0 "Queen Anne's Revenge" (edgetx-tx16smk3) |
| 通信 | CRSF / ExpressLRS |
| FC | Rotorflight (センサー名は下表) |
| ウィジェット名 | `RF Telem` (`/WIDGETS/RFTelem/main.lua`) |

## すぐ始める

0. **`.vscode/` は手動配置が必要**。Claude のリモートツールは `.vscode` への書き込みが許可されておらず、
   `settings.json` / `tasks.json` / `extensions.json` の3ファイルだけ自動配置できなかった。
   チャットで受け取った3ファイルを `C:\Dev\RFTelem\.vscode\` に置く。
   置かなくても `main.lua` の編集と型チェック (`.luarc.json`) は動くが、手順4の `Ctrl+Shift+B` は使えない
   (代わりに下記の PowerShell コマンドで同じことができる)。
1. VS Code で `C:\Dev\RFTelem` を開く (`code C:\Dev\RFTelem`)。
2. 推奨拡張機能 (`sumneko.lua` ほか) のインストールを促されたら承諾 (手順0を行った場合)。
   `sumneko.lua` を入れれば、`.luarc.json` と `types/edgetx.lua` により EdgeTX API の補完・型チェックが効く。
3. `main.lua` を編集: `sdcard/WIDGETS/RFTelem/main.lua`
4. SD カードへ反映: `Ctrl+Shift+B` → **Deploy to SD card** → SD のドライブ (`E:\` など) または `auto` を入力。
   - 送信機を USB ストレージモードにするか、カードリーダーで SD を挿してから実行。
   - 診断ウィジェットも入れる場合は **Deploy to SD card (+ diagnostic widget)**。
   - 何がコピーされるか先に見るなら **Deploy dry run**。
   - タスクを使わない場合 (PowerShell):
     `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Dev\RFTelem\scripts\deploy.ps1 -Target E:\`
     (`-Tools` で診断ウィジェットも、`-DryRun` で一覧のみ)
5. ラジオ側: ウィジェット画面 → 空きゾーン長押し → Add Widget → `RF Telem`。
   フル表示は 1 ゾーン全画面レイアウト推奨 (小さいゾーンは簡易表示に切り替わる)。

> `scripts/deploy.ps1` は追加・上書きのみで、SD 上のファイルを削除しない。

## シミュレータで確認する (EdgeTX Companion 2.12)

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

## フォルダ構成

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
└─ .vscode/                     手動配置 (上の手順0)
```

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
- `Theme`: `0`=color / `1`=mono / `2`=cyan (EdgeTX のウィジェットオプションには文字列選択が無いため数値指定)
- `Mute`: 消音に使うソース (スイッチ SA など、または論理スイッチ)。値が 0 より大きい間 (スイッチ下 / LS 真)
  音声と注意の振動を止める。危険の振動は止めない。空欄なら消音しない

## アラーム (音声 + 振動)

`main.lua` の ALARMS と `CONFIG.alarm`。画面に出ていない間も `background()` から判定する。

| 段階 | 振動 | 音声 | 項目 |
|---|---|---|---|
| 危険 | パターン | 10 秒ごと | セル電圧 < 3.50V (2 秒継続)、残量 ≤ 10%、ESC ≥ 90℃、BEC < 6.0V、ヘッドスピードロスト、回転中の通信断 |
| 注意 | 短く 1 回 | 1 回 | セル電圧 < 3.60V (2 秒継続)、ESC ≥ 80℃、残量 30% / 20%、飛行時間 (`flightTimeSec`、既定オフ)、ARM 不可 (ARMD ≠ 0) |
| 情報 | なし | 変化時 | 接続 / 切断、ARM / DISARM・バンク (RTE#)・プロファイル (PID#) (この 3 つは接続直後にも現在値)、ガバナー状態、残量 10% 刻み |

- 音声ファイルは `sdcard/SOUNDS/rf/` (VOICEVOX で生成。[docs/voicevox_script.md](docs/voicevox_script.md))
- 案C (EdgeTX 標準機能でのバックアップ): [docs/alarms_native.md](docs/alarms_native.md)。設定したら `CONFIG.alarm.nativeBackup = true`
- 振動の有無・`playHaptic` の単位は TX16S MK3 で未確認

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

## 実機で測った値 (この機種・このファームウェア固有)

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

- `main.lua` 自体は実機で動作確認しながら開発したもの。**今回新規に書いた `deploy.ps1`・`.vscode`・
  `.luarc.json`・`types/edgetx.lua` は、作成環境に PowerShell も VS Code も無かったため未実行**。
  初回に動かなくても `main.lua` には影響しない。deploy が合わなければ SD に手動コピーでよい
  (`sdcard/` の中身を SD のルートへ)。
- `main.lua` 冒頭のコメントの一部は旧レイアウト時代の記述が残っている
  (例: 現在は存在しない "Max Amp/Min Volt" チップへの言及)。挙動の一次情報はコード本体。
- EdgeTX 2.12 のウィジェットオプションに文字列選択型があるかは確認していない。
  Theme を数値指定にしているのは、開発時にその前提で作ったため。
- 型スタブは使用 API のみ。未宣言のグローバルは警告になるので、必要に応じて `types/edgetx.lua` に追加する。
- Git リポジトリは未初期化 (`git init` は未実行)。
