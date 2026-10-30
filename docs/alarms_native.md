# アラームのバックアップ設定 (案C: EdgeTX 標準機能)

ウィジェット (案B) のアラームは、RF Telem がそのモデルの画面に置かれていないと動かない。
命に関わる 2 項目 (バッテリー残量わずか / セル電圧危険) だけ、EdgeTX 標準の
論理スイッチ (Logical Switches) + スペシャルファンクション (Special Functions) でも鳴らす。

> **未検証**: この手順は実機でも Companion でもまだ設定していない。EdgeTX 2.12 の画面上の
> 表記が下と違う場合は、近い項目を選び、結果を CLAUDE.md に追記すること。

## 1. 音声ファイルを置く

Play Track で選べるのは、ラジオの音声言語フォルダ (`/SOUNDS/<言語>/`、例 `/SOUNDS/en/`) にある
ファイルだけ、と理解している (未確認)。`sdcard/SOUNDS/rf/<声>/` (例 `no7/`) にある次の 2 つを、
SD カードの音声言語フォルダへコピーする。ファイル名は短く (6 文字) してある。

| ファイル | 内容 |
|---|---|
| `rfbatt.wav` | バッテリー残量、わずか。着陸してください |
| `rfcell.wav` | セル電圧、危険。着陸してください |

## 2. 論理スイッチ (Model → Logical Switches)

| LS | Function | V1 | V2 | AND switch | Delay | 意味 |
|---|---|---|---|---|---|---|
| L01 | `a>x` | `Hspd` | `50` | — | — | ローター回転中 (`CONFIG.rpmRunningThreshold` と同じ値) |
| L02 | `a<x` | `Bat%` | `11` | `L01` | `1.0` | 残量 10% 以下 (回転中のみ。Bat% は DISARM で 0 になるため L01 が必須) |
| L03 | `a<x` | `Vcel` | `3.50` | `L01` | `2.0` | セル電圧 3.50V 未満が 2 秒継続 (`CONFIG.alarm.cellCritical` と同じ値) |

L01〜L03 がすでに使われているモデルでは、空いている番号を使う。

## 3. スペシャルファンクション (Model → Special Functions)

| SF | Switch | Action | 値 | Repeat |
|---|---|---|---|---|
| SF1 | `L02` | Play Track | `rfbatt` | 10s |
| SF2 | `L02` | Haptic | `3` | 10s |
| SF3 | `L03` | Play Track | `rfcell` | 10s |
| SF4 | `L03` | Haptic | `3` | 10s |

Haptic の値はラジオの振動パターン番号。TX16S MK3 に振動モーターがあるかは未確認。

## 4. ウィジェット側の重複を止める

`sdcard/WIDGETS/RFTelem/main.lua` の `CONFIG.alarm.nativeBackup = true` にする。
ウィジェットはバッテリー残量わずか・セル電圧危険を読み上げなくなる
(10% 以下の残量の読み上げも止まる)。他のアラームは今まで通り。

閾値を変えるときは、L02/L03 の値と `CONFIG.alarm` の値を両方そろえること。
