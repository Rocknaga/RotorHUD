# Rotorflight ソースから確認した事実

出典: rotorflight-firmware `release/4.6.0` (2026-06-30)。比較用に `release/4.5.1` も参照。
推測ではなくソースの記述。ファイルパスは `src/main/` 以下。

## 実機の FC は 4.6 系

実機で確認済みの ARMD = 67108872 = 0x4000008 = bit 26 + bit 3。
- 4.6.0: bit 26 = `ARMING_DISABLED_ARM_SWITCH`、bit 25 = `OVERRIDE` (新設) → 一致
- 4.5.1: `ARM_SWITCH` は bit 25 (同じ状況なら 33554440 になる) → 不一致

## ガバナー状態 (`Gov` センサー)

CRSF カスタムテレメトリの `GOVERNOR_STATE` (0x1205, U8) は `getGovernorState()` の値をそのまま送る
(`telemetry/sensors.c`)。`telemetry/crsf.c` の `govStateNames[]` 文字列は使われていない古い表。

| 値 | 4.6.0 (`flight/governor.h`) | 4.5.1 | 意味 (4.6 `governor.c`) |
|---|---|---|---|
| 0 | THROTTLE_OFF | 同 | スロットル OFF |
| 1 | THROTTLE_IDLE | 同 | アイドル |
| 2 | SPOOLUP | SPOOLING_UP | スプールアップ |
| 3 | RECOVERY | 同 | HOLD から復帰 |
| 4 | ACTIVE | 同 | ガバナー動作中 |
| 5 | **THROTTLE_HOLD** | ZERO_THROTTLE | 飛行中にスロットルを切った直後 (タイムアウトまでに戻せば RECOVERY) |
| 6 | **FALLBACK** | LOST_HEADSPEED | ヘッドスピード信号なし。カーブで代替制御 (`!gov.motorRPMGood`) |
| 7 | AUTOROTATION | 同 | オートローテーション |
| 8 | BAILOUT | AUTOROTATION_BAILOUT | オートロからの復帰 |
| 9 | **BYPASS** | (なし) | ガバナーバイパス |

main.lua は 4.6 の表 (`CONFIG.govStateNumberMap`) を使う。4.5 の表は `govStateNumberMap45` に残してある。

## ARM 不可フラグ (`ARMD` センサー、0x1203, U32)

`fc/runtime_config.h` の列挙型が正。`fc/runtime_config.c` の `armingDisableFlagNames[]` は
bit 5/6 が Betaflight 由来の RUNAWAY/CRASH のままで列挙型とずれている。

| bit | 名前 | 立つ条件 (確認できたもの) |
|---|---|---|
| 0 | NO_GYRO | |
| 1 | FAILSAFE | |
| 2 | RX_FAILSAFE | |
| 3 | BAD_RX_RECOVERY | 受信機復帰時にアームスイッチ ON |
| 4 | BOXFAILSAFE | |
| 5 | GOVERNOR | ガバナーモード (電動/ニトロ) なのに高速 RPM 源がない (`governor.c`) |
| 6 | RPM_SIGNAL | 同上、または RPM フィルターの RPM なし (`rpm_filter.c`) |
| 7 | THROTTLE | |
| 8 | ANGLE | |
| 9 | BOOT_GRACE_TIME | 起動直後 (`init.c`)、条件成立で解除 (`core.c`) |
| 10 | NOPREARM | PREARM モード設定時、PREARM が OFF |
| 11 | LOAD | RT/CPU/システム負荷 > 75% |
| 12 | CALIBRATING | |
| 13 | CLI | |
| 14 | CMS_MENU | |
| 15 | BST | |
| 16 | MSP | |
| 17 | PARALYZE | PARALYZE モード ON |
| 18 | GPS | |
| 19 | RESC | レスキュー / GPS レスキューのスイッチ ON |
| 20 | RPMFILTER | RPM フィルターのエラー |
| 21 | REBOOT_REQUIRED | |
| 22 | DSHOT_BITBANG | |
| 23 | ACC_CALIBRATION | |
| 24 | MOTOR_PROTOCOL | |
| 25 | OVERRIDE | サーボ / ミキサーのオーバーライド中 (4.6 新設) |
| 26 | ARM_SWITCH | 他の理由があるときにアームしようとすると常に付く |

main.lua の `ARMD_REASONS` / `decodeArmd` がこの表。ARM 警告画面に理由を表示し、音声で最大 2 つ読み上げる。

## ARM フラグ (`ARM` センサー、0x1202, U8)

`armingFlags`: bit 0 = ARMED、bit 1 = WAS_EVER_ARMED、bit 2 = WAS_ARMED_WITH_PREARM。
→ 0/2 = DISARM、1/3 = ARM (bit 2 が立つと 4〜7 もあり得るので main.lua は `% 2` で判定)。

## 未使用だが送られているセンサー (音声だけ用意済み)

| センサー | ID | 用意した音声 |
|---|---|---|
| RESCUE_STATE | 0x1204 (U8: 0=OFF, 1=PULLUP, 2=FLIP, 3=CLIMB, 4=HOVER, 5=EXIT) | rescue_on / rescue_off |
| FLIGHT_MODE | 0x1201 (U16 フラグ。FAILSAFE_MODE など) | failsafe |
| BATTERY_PROFILE | 0x1214 (U8、1 始まり) | battprofile1–6 |

これらは実機の Telemetry 一覧 (42 項目) での名前が未確認のため、main.lua にはまだ組み込んでいない。
