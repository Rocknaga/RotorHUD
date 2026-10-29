# 音声ファイル (VOICEVOX)

台本の正本は [tools/voice/voices.csv](../tools/voice/voices.csv) (`file,group,text`)。
このファイルを直して、スクリプトで一括生成する。手作業での書き出しは不要。

```powershell
# 全ファイル生成 (VOICEVOX エンジンが起動していなければ自動で起動する)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\voice\make_voices.ps1
# 一部だけ作り直す / 話者を変える / 話者一覧
powershell -NoProfile -ExecutionPolicy Bypass -File tools\voice\make_voices.ps1 -Only gov_active,armed
powershell -NoProfile -ExecutionPolicy Bypass -File tools\voice\make_voices.ps1 -Speaker 30 -SpeedScale 1.15
powershell -NoProfile -ExecutionPolicy Bypass -File tools\voice\make_voices.ps1 -ListSpeakers
```

- 出力: `sdcard/SOUNDS/rf/<file>.wav` (32 kHz / 16 bit / モノラル PCM)。deploy.ps1 で SD へコピーされる
- 既定の話者: **No.7 / アナウンス (ID 30)**、話速 1.15
- 読み: VOICEVOX が英字を読めないものはカタカナにしてある (ESC→イーエスシー、BEC→ビーイーシー、PID→ピーアイディー)
- 利用規約: キャラクターごとの規約に従う。公開する場合は「VOICEVOX:No.7」などのクレジットが必要

## グループと鳴るタイミング (main.lua の ALARMS)

| group | ファイル | 鳴るとき |
|---|---|---|
| governor | gov_* | ガバナー状態が変わったとき (LOST-HS は critical) |
| profile | bank1–6 / profile1–6 | バンク (RTE#) / プロファイル (PID#) が変わったとき。接続直後にも現在値を 1 回 |
| link | connected / disconnected | テレメトリー接続時 / 停止中の切断時 (回転中の切断は telemetry_lost) |
| battery | batt000–100 | 回転中に残量が 10% の区切りを下回ったとき (30/20% は注意の振動つき) |
| arm | armed / disarmed | ARM 状態が変わったとき。接続直後にも現在値を 1 回 |
| arm | arm_switch_on / arm_disabled | ARMD ≠ 0 になったとき (注意: 短い振動つき)。67108872 は arm_switch_on |
| caution | cell_low / esc_hot / flight_time | 注意: 短い振動 + 1 回 |
| critical | cell_critical / batt_critical / esc_critical / bec_low / gov_losths / telemetry_lost | 危険: 振動パターン + 10 秒ごとに繰り返し |
| armd | armd_* (27 種) | ARM 不可の理由。arm_disabled の後に最大 2 つ ([rotorflight_notes.md](rotorflight_notes.md)) |
| native | rfbatt / rfcell | 案C の EdgeTX 標準機能用 ([alarms_native.md](alarms_native.md)) |
| reserve | rescue_on/off, failsafe, battprofile1–6 | 用意のみ。センサー名が未確認のため未使用 |

ガバナーは 4.6 の HOLD / FALLBACK / BYPASS 用 (gov_hold / gov_fallback / gov_bypass) と、
4.5 の THR-OFF / LOST-HS 用 (gov_throff / gov_losths) の両方がある。FALLBACK と LOST-HS は危険扱い。

## 未決

- **VBar Control 風の言い回し**: 現在の台本は仮。VBar Control の案内文言は記憶では再現できないため、
  ユーザーから実際の案内一覧 (または動画) をもらって合わせる。
