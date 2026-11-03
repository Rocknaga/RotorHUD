-- RotorHUD core: configuration, telemetry (built-in Rotorflight decoder,
-- MSP over CRSF), trackers, alarms, battery-profile picker, user settings,
-- menu actions and the hosted RF2 tool. Loaded by main.lua; the screens are
-- view.lua (R.LV). Everything view.lua / rf2ui.lua need is exported on R.
-- License: GPL-3.0 (the RF TELEMETRY section and the RF2 hosting are adapted
-- from rotorflight-lua-scripts).
local R = { DIR = ... or "/WIDGETS/RotorHUD/" }

-- ============================== CONFIG ==================================
local CONFIG = {
  -- Each parameter tries every candidate name, in order, until one resolves.
  -- Includes both the long names from the Telemetry Sensors list AND the
  -- short abbreviations EdgeTX shows in its own top status bar (Vbec, Vcel,
  -- RTE#, PID#, etc), since radios can expose either depending on firmware.
  sensors = {
    -- All exact names below are confirmed from the radio's own full
    -- Telemetry Sensors list (42 sensors, cross-checked directly) -
    -- not guesses. Each is listed first in its candidate array, with
    -- the older guessed/long-form names kept afterward only as a
    -- fallback for a differently-configured radio.
    governor        = { "Gov", "Governor State", "Governor", "Flight Mode", "FM" },
    rpm             = { "Hspd", "Headspeed", "RPM" },
    voltage         = { "Vbat", "Battery Voltage", "RxBt" },
    cellVoltage     = { "Vcel", "Battery Cell Voltage" },
    cellCount       = { "Cel#", "Battery Cell Count", "Cels" },
    current         = { "Curr", "Battery Current" },
    temp            = { "Tesc", "ESC Temp", "EscT", "Tmp1", "Temp1" },
    charge          = { "Bat%", "Battery Charge Level", "Capa", "Fuel" }, -- % remaining, 0-100
    capacity        = { "EscC", "#1 ESC Capacity", "Capacity", "Fuel Used", "Consumption", "Capa", "Fuel", "mAh", "ESC Cap", "Cap1" }, -- mAh
    throttle        = { "Thr", "Throttle Control", "Thro" },
    becVoltage      = { "Vbec", "BEC Voltage" },                  -- used for "RC Volt" chip
    bank            = { "RTE#", "Rates Profile", "Rate Profile" }, -- used for "Profile/Rate" chip
    pidProfile      = { "PID#", "PID Profile" }, -- combined with bank as "pid/rate" in that same chip
    armDisableFlags = { "ARMD", "Arming Disable Flags" },
    armFlags        = { "ARM", "Arming Flags", "Arm", "AFlags", "Armed" }, -- used to show Armed/Disarmed next to Headspeed
    -- RQly/1RSS/RSNR are all confirmed present on this radio (a mix of
    -- CRSF-standard and receiver-specific link sensors) - tried in
    -- that order since RQly (link quality %) is the most directly
    -- useful for the signal-bars icon.
    signal          = { "RQly", "1RSS", "RSNR", "RSSI" },
    -- Battery profile, 1-based (0x1214). Name from rotorflight-lua-scripts
    -- src/SCRIPTS/RF2/rf2tlm_sensors.lua - the same table that names every
    -- sensor above.
    batteryProfile  = { "BAT#", "Bat#" },
  },

  -- Built-in Rotorflight telemetry decoder (see RF TELEMETRY). With
  -- decode = true the rf2bg special function / RfTool widget must be
  -- removed: both read the same CRSF queue and would split the frames.
  -- Set false to keep using rf2bg (then no capacities from the FC).
  telemetry = {
    decode = true,
    readCapacities = true, -- MSP_BATTERY_CONFIG -> per-profile mAh
  },

  perfOverlay = false, -- fps / ms per frame / Lua KB, bottom-right (speed check; Settings > Display)
  -- Simple screen (Settings > Display) in place of the dashboard: mostly
  -- shapes (LVGL VIEW buildSimple). Full scales of its meters: current,
  -- and flight time when Settings > Flight time call is off. Its large
  -- model picture: /IMAGES/<model>-L.png, exactly imageW x imageH.
  simple = { on = false, currentMax = 200, flightSec = 360, imageW = 320, imageH = 124 },
  -- Rotorflight settings: the official RF2 Lua (installed under /SCRIPTS/RF2/)
  -- runs inside the widget; rf2Skin draws its screens in the widget's style
  -- (rf2ui.lua), false = RF2's own lvgl screens.
  tools = {
    rf2Dir = "/SCRIPTS/RF2/",
    rf2Skin = true,
  },

  -- Battery-profile picker shown right after connecting (see BATTERY
  -- PROFILE below). Labels are free text for the 6 FC profiles, e.g.
  -- "6S 5000" - the widget only sends the profile number.
  batteryProfile = {
    enabled     = true,
    labels      = { "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5", "Profile 6" },
    timeoutSec  = 0,    -- >0: no input this long keeps the current profile; 0 = stays until chosen or armed
    applyIdleSec = 3,   -- switch-stepping: apply after this long without a press
    retrySec    = 2,    -- resend if BAT# hasn't changed by then
    maxTries    = 3,
  },

  -- Per-cell voltage thresholds (volts) for battery-related coloring.
  vCellGood = 3.8,
  vCellWarn = 3.6,

  -- ESC temperature threshold (deg C) for a warning row in the status list.
  escTempWarn = 90,

  -- Headspeed above this value is considered "spinning" for the Motor chip
  -- and flight timer (helps when Governor State sensor isn't available).
  rpmRunningThreshold = 50,

  -- How long the post-flight log stays up before auto-switching to the
  -- plain standby screen, in seconds. Touch (full-screen widgets only -
  -- see the FLIGHT LOG note near the top of this file) can still
  -- dismiss it sooner; this timeout is what makes the same behavior
  -- work even when the widget isn't full-screen and never gets touch
  -- events at all.
  -- Flight history (FLIGHT HISTORY): flights shorter than this (rotor
  -- time, s) aren't recorded
  history = { minSec = 10 },
  flightLogTimeoutSec = 0, -- >0: back to standby after this long; 0 = stays until closed or reconnected

  -- Model picture in the footer's side card (/IMAGES/<model name>.png).
  -- The file must be pre-sized to exactly modelImageW x modelImageH
  -- (transparent padding around the picture) - it is drawn 1:1 and
  -- centered as a fixed box, since getBitmapSize() isn't trustworthy.
  showModelImage = true,
  modelImageW = 186,
  modelImageH = 46,

  govColors = {
    { match = "ACTIVE",   color = "green"  },
    { match = "SPOOLUP",  color = "yellow" },
    { match = "RECOVERY", color = "yellow" },
    { match = "BYPASS",   color = "yellow" },
    { match = "HOLD",     color = "orange" },
    { match = "AUTOROT",  color = "orange" },
    { match = "BAILOUT",  color = "orange" },
    { match = "FALLBACK", color = "red"    },
    { match = "LOST",     color = "red"    },
    { match = "OFF",      color = "red"    },
    { match = "THR-OFF",  color = "grey"   },
    { match = "IDLE",     color = "grey"   },
  },

  -- Gov sensor = getGovernorState() sent raw as U8 (rotorflight-firmware
  -- src/main/telemetry/sensors.c). Numbering is from flight/governor.h of
  -- release/4.6.0. 4.5.x differs (5 = THR-OFF / zero throttle, 6 =
  -- LOST-HS, no 9) - see govStateNumberMap45. The radio is on 4.6: its
  -- ARMD 67108872 = bit 26 (ARM_SWITCH in 4.6; bit 25 in 4.5) + bit 3.
  govStateNumberMap = {
    [0] = "OFF", [1] = "IDLE", [2] = "SPOOLUP", [3] = "RECOVERY", [4] = "ACTIVE",
    [5] = "HOLD", [6] = "FALLBACK", [7] = "AUTOROT", [8] = "BAILOUT", [9] = "BYPASS",
  },
  govStateNumberMap45 = {
    [0] = "OFF", [1] = "IDLE", [2] = "SPOOLUP", [3] = "RECOVERY",
    [4] = "ACTIVE", [5] = "THR-OFF", [6] = "LOST-HS", [7] = "AUTOROT", [8] = "BAILOUT",
  },

  -- Where to look for a model picture, tried in order. {name} is replaced
  -- with the current model's name (as set in Model Setup).
  imagePaths = {
    "/IMAGES/{name}.png",
    "/IMAGES/{name}.bmp",
  },


  -- "color" (default), "mono", or "cyan":
  --   "mono" swaps every status color for a shade of gray, so state is
  --   shown by brightness instead of hue.
  --   "cyan" is a black/white basis with every non-danger accent
  --   unified to one cyan-blue (see the CYAN THEME note near the top
  --   of this file) - red/danger states are left alone on purpose.
  theme = "color",

  -- Transmitter battery range for the top bar's battery icon, in volts:
  -- read from Radio Setup > Battery range (getGeneralSettings battMin /
  -- battMax, EdgeTX 2.12 api_general.cpp); these only if that fails.
  txBattery = {
    minV = 6.4, -- 0%
    maxV = 8.4, -- 100%
  },

  -- Companion simulator test mode. When true, readTelemetry() ignores the
  -- real sensors and plays back a scripted flight (see simulateTelemetry)
  -- so every screen and transition can be checked without a CRSF link.
  -- MUST be false on the real radio.
  simulate = false,

  -- Voice + haptic alarms (see ALARMS below). Voice files are
  -- <dir><voice set>/<name>.wav, generated from tools/voice/voices.csv
  -- for every set in tools/voice/voicesets.csv (same order as here).
  -- The radio-side "Voice" option picks the set: 0 = first entry.
  alarm = {
    enabled     = true,
    dir         = "/SOUNDS/rf/",
    -- Japanese (VOICEVOX, tools/voice/make_voices.ps1), then English (Piper,
    -- tools/voice/make_voices_en.py): the same file names in each folder
    voiceSets   = { "no7", "ryusei", "takehiro", "himari", "voidoll", "zundamon", "en_male", "en_female" },
    voiceLabels = { "No.7", "Ryusei", "Takehiro", "Himari", "Voidoll", "Zundamon", "English M", "English F" }, -- standby screen
    repeatSec   = 10,    -- critical alarms repeat this often while active
    cellCaution = 3.60,  -- V/cell, sustained cellSustainSec (rotor spinning)
    cellCritical = 3.50,
    cellSustainSec = 2,  -- ignore short sag under load
    cellHyst    = 0.10,  -- must recover this far above the threshold to re-arm
    -- % remaining that triggers "battery NN%, land now" (critical,
    -- repeating). The radio-side "BattLand" option overrides it (10-50).
    -- The 10% voice step just above it (<= land + 10) gets the caution
    -- haptic.
    battLand    = 20,
    battRepeatSec = 20, -- the land-now call repeats this often (haptic + voice)
    -- EdgeTX speaks telemetry connected / back / lost itself (telemetry/
    -- telemetry.cpp, unless the model's "disable telemetry alarms" is set -
    -- which would also drop its RSSI/RQly warnings). While true the widget
    -- leaves those calls to EdgeTX (a link lost in flight still gets the
    -- critical haptic) and holds its own connect reports (arm, bank,
    -- profile, battery profile, picker) for connectQuietSec so they come
    -- after the system voice instead of on top of it.
    edgetxLinkVoice = true,
    connectQuietSec = 3,
    escCaution  = 80,    -- deg C
    escCritical = 90,
    escHyst     = 5,
    becCritical = 6.0,   -- V
    becHyst     = 0.3,
    flightTimeSec = 0,   -- >0: one "flight time" call when the timer passes it
    -- Battery not full: once per connect, after the connect quiet time + 1 s
    -- (values settled), disarmed with the rotor stopped, Vcel below fullCell
    -- opens a window over the screen (caution tone + haptic). It closes on
    -- a tap anywhere on it, ENTER, the Close switch, arming, or after
    -- fullAlertSec. Settings > Flight.
    fullCheck = true,
    fullCell = 4.10,     -- V per cell
    fullAlertSec = 10,
    -- Haptic patterns: { duration, pause } per pulse, passed to playHaptic.
    -- UNVERIFIED on TX16S MK3: whether it has a vibration motor at all, and
    -- whether playHaptic's units are ms or 10ms - tune on the radio.
    -- Sound effects (playTone: Hz, ms on, ms pause) ahead of the voice:
    -- link up / down, and every caution / critical alarm. Settings >
    -- Voice > Sound effects, muted with the Mute switch like the voice.
    tones = true,
    toneEffects = {
      connect    = { { 880, 80, 30 }, { 1320, 140, 0 } },          -- rising
      disconnect = { { 1320, 80, 30 }, { 880, 140, 0 } },          -- falling
      caution    = { { 1000, 100, 80 }, { 1000, 100, 0 } },        -- two beeps
      critical   = { { 2000, 70, 40 }, { 2000, 70, 40 }, { 2000, 70, 0 } }, -- three fast, high
      saved      = { { 1200, 60, 20 }, { 1800, 120, 0 } },         -- FC settings saved
    },
    hapticCaution  = { { 30, 0 } },
    hapticSaved    = { { 40, 60 }, { 40, 0 } }, -- FC settings saved: two short pulses
    hapticCritical = { { 60, 30 }, { 60, 30 }, { 60, 0 } },
    hapticArm      = { { 40, 0 } },              -- armed: one pulse
    hapticDisarm   = { { 40, 60 }, { 40, 0 } },  -- disarmed: two
    hapticProfile  = { { 40, 0 } },              -- rate / PID profile changed: one for both
    -- Option C: set true when the EdgeTX logical-switch backup
    -- (docs/alarms_native.md) covers low battery / low cell, so the
    -- widget doesn't call them out a second time.
    nativeBackup = false,
  },
}

-- ============================== COLORS ===================================

-- Three full palettes, built once at load time, so switching themes at
-- runtime (from the radio's own widget options - see OPTIONS below) is
-- just reassigning which table the COLOR local points at, rather than
-- re-computing anything per frame.
local function buildColorTheme(name)
  local c = {
    green  = lcd.RGB(0x5D, 0xCA, 0xA5), -- matches mockup accent green
    yellow = lcd.RGB(0xE0, 0xC0, 0x00),
    orange = lcd.RGB(0xE0, 0x80, 0x00),
    red    = lcd.RGB(0xE2, 0x4B, 0x4A), -- matches mockup danger red
    grey   = lcd.RGB(0x88, 0x87, 0x80),
    white  = lcd.RGB(0xF2, 0xF2, 0xF3), -- matches mockup primary text
    black  = lcd.RGB(0x00, 0x00, 0x00),
    bg     = lcd.RGB(0x0E, 0x0F, 0x11), -- matches mockup screen background
    chip   = lcd.RGB(0x1C, 0x1E, 0x21), -- matches mockup card background
    panel  = lcd.RGB(0x1C, 0x1E, 0x21),
    accentPanel  = lcd.RGB(0x17, 0x18, 0x1B), -- headspeed card fill
    accentBorder = lcd.RGB(0x2A, 0x2C, 0x30), -- headspeed card border
    barBg  = lcd.RGB(0x2A, 0x2C, 0x30),
    dim    = lcd.RGB(0x8A, 0x8D, 0x93), -- matches mockup secondary text
    muted  = lcd.RGB(0x5F, 0x60, 0x5F), -- matches mockup footer text
    accent = lcd.RGB(0x50, 0xA0, 0xE0),

    -- Dedicated, more saturated colors just for the battery bar fill -
    -- kept separate from the general green/yellow/red above (which are
    -- also used for governor/motor state) so the battery bar can be
    -- extra vivid without changing every other status color.
    battGood = lcd.RGB(0x00, 0xE6, 0x76),
    battWarn = lcd.RGB(0xFF, 0xD6, 0x00),
    battBad  = lcd.RGB(0xFF, 0x2D, 0x55),
  }

  if name == "mono" then
    -- Monochrome: state is shown by brightness instead of hue - dim
    -- gray for "nominal/off", brighter gray for "caution". Red/danger
    -- (red, battBad) is NOT grayed - it stays red, same as cyan below.
    -- Surfaces (bg/chip/panel/bar) stay the same near-black/dark-gray
    -- tones either way, since those are structural, not status-bearing.
    c.green  = lcd.RGB(0x50, 0x50, 0x50)
    c.yellow = lcd.RGB(0xA8, 0xA8, 0xA8)
    c.orange = lcd.RGB(0xC8, 0xC8, 0xC8)
    c.grey   = lcd.RGB(0x60, 0x60, 0x60)
    -- Bar fills (throttle = accent, battery = batt*) carry white text, so
    -- they stay dark enough for it: 0x70 = 5.0:1, 0x80 = 3.9:1 (the old
    -- 0xC0/0xA8 were ~1.8:1 and unreadable in the simulator).
    c.accent = lcd.RGB(0x70, 0x70, 0x70)
    c.battGood = lcd.RGB(0x50, 0x50, 0x50)
    c.battWarn = lcd.RGB(0x80, 0x80, 0x80)
  elseif name == "cyan" then
    -- Black/white basis with every non-danger accent unified to one
    -- cyan-blue. Red/danger states are deliberately left alone in
    -- every theme, including this one - that's a safety signal, not a
    -- look-and-feel choice, and diluting it into "just another accent"
    -- would make actual warnings harder to spot at a glance.
    local cyan = lcd.RGB(0x26, 0xE0, 0xFF)
    c.bg     = lcd.RGB(0x00, 0x00, 0x00)
    c.chip   = lcd.RGB(0x1A, 0x1A, 0x1A)
    c.panel  = lcd.RGB(0x1A, 0x1A, 0x1A)
    c.accentPanel  = lcd.RGB(0x14, 0x14, 0x14)
    c.accentBorder = cyan
    c.barBg  = lcd.RGB(0x2C, 0x2C, 0x2C)
    c.white  = lcd.RGB(0xFF, 0xFF, 0xFF)
    c.dim    = lcd.RGB(0xB0, 0xB0, 0xB0)
    c.muted  = lcd.RGB(0x70, 0x70, 0x70)
    c.green  = cyan
    c.yellow = cyan
    c.orange = cyan
    -- Bar fills use a deeper cyan (white text 4.3:1; the bright cyan
    -- was 1.6:1). Borders and status stripes keep the bright cyan.
    local barCyan = lcd.RGB(0x00, 0x86, 0xA0)
    c.accent = barCyan
    c.battGood = barCyan
    c.battWarn = barCyan
    -- battBad and red are intentionally left as red - see note above.
  end
  return c
end

-- Index 0/1/2 maps to these, matching the "Theme" widget option below
-- (EdgeTX widget options have no string/enum picker, only plain
-- numbers, so the mapping has to live here as a comment instead of on
-- the radio's own edit screen).
local THEME_NAMES = { "color", "mono", "cyan" }

local COLOR_THEMES = {
  color = buildColorTheme("color"),
  mono = buildColorTheme("mono"),
  cyan = buildColorTheme("cyan"),
}

-- Default/fallback before any widget option has been read (e.g. the
-- very first create() call) - CONFIG.theme still works as a coded-in
-- default, but the radio's own widget option (if set) takes over from
-- refresh() onward. See "local COLOR = ..." reassignment in refresh().
local COLOR = COLOR_THEMES[CONFIG.theme] or COLOR_THEMES.color

-- ============================== HELPERS ===================================
local function resolveSensor(cache, key, names)
  if cache[key] ~= nil then return cache[key] end
  for i = 1, #names do
    local info = getFieldInfo(names[i])
    if info then
      cache[key] = info.id
      return info.id
    end
  end
  return nil
end

-- "ACTIVE" -> "Active" - used for our own labels/values so the dashboard
-- reads as calm sentence case, matching the refined mockup. Never applied
-- to the model name, which is the rider's own text and stays as typed.
local function toSentenceCase(text)
  if not text or text == "" then return text end
  local lower = string.lower(text)
  return string.upper(string.sub(lower, 1, 1)) .. string.sub(lower, 2)
end

local function getGovColor(text)
  if not text then return COLOR.grey end
  local upper = string.upper(text)
  for i = 1, #CONFIG.govColors do
    local rule = CONFIG.govColors[i]
    if string.find(upper, rule.match) then
      return COLOR[rule.color]
    end
  end
  return COLOR.dim
end

local function getChargeColor(pct)
  if not pct then return COLOR.dim end
  if pct >= 50 then return COLOR.battGood
  elseif pct >= 20 then return COLOR.battWarn
  else return COLOR.battBad end
end

-- Transmitter battery voltage -> percentage, using the configured
-- min/max range. getValue("tx-voltage") is a fixed EdgeTX source
-- available on every radio, so this needs no sensor discovery.
local function getTxBatteryPct()
  local ok, voltage = pcall(function() return getValue("tx-voltage") end)
  if not ok or not voltage or voltage <= 0 then return nil, nil end
  local cfg = CONFIG.txBattery
  if cfg.radio == nil then
    local okG, g = pcall(getGeneralSettings)
    cfg.radio = (okG and g and g.battMin and g.battMax and g.battMax > g.battMin) and g or false
  end
  local minV, maxV = cfg.minV, cfg.maxV
  if cfg.radio then minV, maxV = cfg.radio.battMin, cfg.radio.battMax end
  local pct = (voltage - minV) / (maxV - minV) * 100
  pct = math.max(0, math.min(100, pct))
  return pct, voltage
end

local function decodeGovernor(rawValue)
  if rawValue == nil then return nil end
  if type(rawValue) == "string" then return rawValue end
  if type(rawValue) == "number" then
    return CONFIG.govStateNumberMap[math.floor(rawValue)] or ("STATE " .. tostring(rawValue))
  end
  return nil
end

-- ARMD (Arming Disable Flags) bits, rotorflight-firmware release/4.6.0
-- src/main/fc/runtime_config.h (the armingDisableFlagNames[] strings in
-- runtime_config.c are stale at bits 5/6, so the enum is the source).
-- { bit, short name shown on screen, voice file [, what to do: up to 3
-- SMLSIZE lines under the reason on the arm warning] }
local ARMD_REASONS = {
  { 0,  "NO GYRO",       "armd_nogyro" },
  { 1,  "FAILSAFE",      "armd_failsafe" },
  { 2,  "RX LOSS",       "armd_rxloss", { "The FC gets no RC channels from the receiver" } },
  { 3,  "BAD RX",        "armd_badrx" },
  { 4,  "FAILSAFE SW",   "armd_boxfailsafe" },
  { 5,  "GOVERNOR",      "armd_governor" },
  { 6,  "RPM SIGNAL",    "armd_rpmsignal" },
  { 7,  "THROTTLE",      "armd_throttle" },
  { 8,  "ANGLE",         "armd_angle" },
  { 9,  "BOOT GRACE",    "armd_bootgrace", { "The FC has just powered up - wait a few seconds" } },
  { 10, "NO PREARM",     "armd_noprearm" },
  { 11, "CPU LOAD",      "armd_load" },
  { 12, "CALIBRATING",   "armd_calib" },
  { 13, "CLI",           "armd_cli", { "The configurator's CLI is open", "Leave the CLI, or power-cycle the FC" } },
  -- opened by sticks (rotorflight-firmware cms/cms.c cmsUpdate: collective
  -- mid, yaw low, pitch high, disarmed); disarming or waiting don't close it
  { 14, "CMS MENU",      "armd_cms", { "The FC's stick menu (CMS) is open",
    "Opened by sticks: collective mid + yaw left + pitch forward", "Close it with Exit in the CMS, or power-cycle the FC" } },
  { 15, "BST",           "armd_bst" },
  { 16, "MSP",           "armd_msp" },
  { 17, "PARALYZE",      "armd_paralyze" },
  { 18, "GPS",           "armd_gps" },
  { 19, "RESCUE SW",     "armd_rescuesw" },
  { 20, "RPM FILTER",    "armd_rpmfilter" },
  { 21, "REBOOT REQ",    "armd_reboot", { "Changed settings need a restart - power-cycle the FC" } },
  { 22, "DSHOT BITBANG", "armd_bitbang" },
  { 23, "NO ACC CAL",    "armd_noacccal" },
  { 24, "MOTOR PROTO",   "armd_motorproto" },
  { 25, "OVERRIDE",      "armd_override" },
  { 26, "ARM SWITCH",    "armd_armswitch" },
}

local ARMD_ARM_SWITCH_AT_POWERUP = 67108872 -- bit 26 + bit 3, confirmed on the radio

-- Reasons set in an ARMD value. ARM_SWITCH (bit 26) is always added by
-- the FC on top of any other reason, so it's only reported on its own.
-- Plain arithmetic instead of bit ops: EdgeTX Lua is 5.2-based.
local function decodeArmd(code)
  local list = {}
  if not code or code <= 0 then return list end
  code = math.floor(code)
  for i = 1, #ARMD_REASONS do
    local r = ARMD_REASONS[i]
    if r[1] ~= 26 and math.floor(code / 2 ^ r[1]) % 2 == 1 then list[#list + 1] = r end
  end
  if #list == 0 and math.floor(code / 2 ^ 26) % 2 == 1 then list[1] = ARMD_REASONS[27] end
  return list
end

-- x has no fractional part. Not "x == math.floor(x)": on EdgeTX 2.12
-- (Lua 5.3) 12.5 == math.floor(12.5) is true (measured in the simulator).
local function isWhole(x)
  return string.sub(string.format("%.3f", x), -4) == ".000"
end

local function fmt(value, decimals)
  if value == nil then return "--" end
  if decimals and decimals > 0 then
    return string.format("%." .. decimals .. "f", value)
  end
  return string.format("%d", math.floor(value + 0.5)) -- %d needs a whole number (Lua 5.3)
end

local function fmtTime(totalSeconds)
  totalSeconds = math.floor(totalSeconds or 0)
  local m = math.floor(totalSeconds / 60)
  local s = totalSeconds % 60
  return string.format("%02d:%02d", m, s)
end

-- Only append a unit when there is an actual value (avoids showing "--V").
local function fmtUnit(value, decimals, unit)
  if value == nil then return "--" end
  return fmt(value, decimals) .. (unit or "")
end

-- Pick a font size that fits inside a box of the given pixel width/height,
-- considering both the available height AND the pixel width of the text
-- at each size - this is what stops "OFF" or "100" from overflowing a
-- narrow chip even when the chip is tall enough on its own.
-- Measured on this exact radio/firmware using a dedicated diagnostic
-- widget (lcd.sizeText("0123456789", flag) for each size) - not
-- estimates. The earlier "MIDSIZE/DBLSIZE render too large, avoid
-- them" conclusion turned out to be wrong: they were never broken,
-- they're just genuinely bigger in absolute pixels on this radio than
-- assumed. All four tiers are back in play now that the real numbers
-- are known.
local FONT_SPECS = {
  { font = XXLSIZE, charW = 51, lineH = 93 },
  { font = DBLSIZE, charW = 25, lineH = 55 },
  { font = MIDSIZE, charW = 19, lineH = 42 },
  { font = SMLSIZE, charW = 10, lineH = 23 },
}

local function fitFont(w, h, text, maxFont)
  local len = string.len(text or "")
  for i = 1, #FONT_SPECS do
    local spec = FONT_SPECS[i]
    local allowed = (maxFont == nil) or (spec.font <= maxFont)
    if allowed and spec.lineH <= h and spec.charW * len <= w then
      return spec.font
    end
  end
  return SMLSIZE
end

-- ---- Model image loading -------------------------------------------------
-- EdgeTX has used two different bitmap APIs across versions: the newer
-- Bitmap.open()/Bitmap.getSize() (2.7+) and the older lcd.loadBitmap()/
-- lcd.getBitmapSize(). Both are tried, wrapped in pcall so a radio missing
-- one API (or a missing file) never throws a script error.
local function tryLoadBitmap(path)
  local ok, bmp = pcall(function()
    if Bitmap and Bitmap.open then
      return Bitmap.open(path)
    elseif lcd and lcd.loadBitmap then
      return lcd.loadBitmap(path)
    end
    return nil
  end)
  if ok then return bmp end
  return nil
end

-- Looks up the current model's name and tries to load a matching picture
-- from /IMAGES (tried against each pattern in CONFIG.imagePaths). Only
-- runs the disk lookup once per model name - the result (bitmap or "none
-- found") is cached on wgt so refresh() isn't hitting the SD card every
-- frame.
local function ensureModelImage(wgt)
  local info = model and model.getInfo and model.getInfo()
  local name = info and info.name or nil
  if not name or name == wgt.modelImageName then
    return
  end
  wgt.modelImageName = name
  wgt.modelBitmap, wgt.modelImagePath, wgt.modelLargePath = nil, nil, nil
  local large = "/IMAGES/" .. name .. "-L.png" -- the simple screen's (CONFIG.simple)
  pcall(function()
    local f = io.open(large, "r")
    if f then io.close(f); wgt.modelLargePath = large end
  end)
  for i = 1, #CONFIG.imagePaths do
    local path = string.gsub(CONFIG.imagePaths[i], "{name}", name)
    local bmp = tryLoadBitmap(path)
    if bmp then
      wgt.modelBitmap, wgt.modelImagePath = bmp, path
      break
    end
  end
  -- Fall back to the picture assigned in Model Setup (if any), in case the
  -- filename doesn't match the model name exactly.
  if not wgt.modelBitmap and info and info.bitmap and info.bitmap ~= "" then
    wgt.modelBitmap = tryLoadBitmap("/IMAGES/" .. info.bitmap)
    if wgt.modelBitmap then wgt.modelImagePath = "/IMAGES/" .. info.bitmap end
  end
end

-- Per-flight time series for the flight-log graphs (one sample per
-- `interval` seconds while the rotor spins). Past FLIGHT_SAMPLES_MAX the
-- series are halved (pairs averaged) and the interval doubles, so a
-- flight of any length fits in fixed memory.
local FLIGHT_SAMPLES_MAX = 400

local function newFlightSamples()
  return { rpm = {}, current = {}, voltage = {}, interval = 1, last = nil }
end

-- Alarm bookkeeping (see ALARMS): last seen values for change detection,
-- latched conditions, and when each one last fired.
local function newAlarmState()
  return { prev = {}, active = {}, since = {}, fired = {}, lastFire = {}, sayFirst = {} }
end

-- ============================== USER SETTINGS =============================
-- Settings changed on the radio by touch (Menu > Settings, full screen),
-- kept on the SD card in SET.file as key=value lines and loaded at
-- start. A value set here wins over the matching widget option (Theme,
-- Voice, BattLand) and over CONFIG. To add a setting: one entry in
-- SETTINGS (group = the tab it shows in), with apply() putting the value
-- where the code reads it; the Settings screen (LVGL VIEW) lists it.
local SET = {}

SET.file = "/WIDGETS/RotorHUD/settings.txt"

local USER = {}

SET.groups = { "Voice", "Alarms", "Flight", "Packs", "Display" }

local SETTINGS = {
  { key = "voice", group = "Voice", label = "Voice", kind = "choice", choices = CONFIG.alarm.voiceLabels,
    option = "Voice", test = "voice" },
  { key = "alarms", group = "Voice", label = "Alarms", kind = "bool",
    default = CONFIG.alarm.enabled, apply = function(v) CONFIG.alarm.enabled = v end },
  { key = "haptic", group = "Voice", label = "Vibration", kind = "bool",
    default = true, apply = function(v) CONFIG.alarm.haptic = v end },
  { key = "tones", group = "Voice", label = "Sound effects", kind = "bool",
    default = true, apply = function(v) CONFIG.alarm.tones = v end, test = "tones" },
  { key = "battLand", group = "Alarms", label = "Land at battery", kind = "number", min = 10, max = 50, step = 5,
    unit = "%", option = "BattLand", default = CONFIG.alarm.battLand },
  { key = "cellCaution", group = "Alarms", label = "Cell caution", kind = "number", min = 3.30, max = 3.90,
    step = 0.05, decimals = 2, unit = "V", default = CONFIG.alarm.cellCaution,
    apply = function(v) CONFIG.alarm.cellCaution, CONFIG.vCellWarn = v, v end },
  { key = "cellCritical", group = "Alarms", label = "Cell critical", kind = "number", min = 3.20, max = 3.80,
    step = 0.05, decimals = 2, unit = "V", default = CONFIG.alarm.cellCritical,
    apply = function(v) CONFIG.alarm.cellCritical = v end },
  { key = "escCaution", group = "Alarms", label = "ESC caution", kind = "number", min = 60, max = 120, step = 5,
    unit = "\194\176C", default = CONFIG.alarm.escCaution, apply = function(v) CONFIG.alarm.escCaution = v end },
  { key = "escCritical", group = "Alarms", label = "ESC critical", kind = "number", min = 70, max = 130, step = 5,
    unit = "\194\176C", default = CONFIG.alarm.escCritical, apply = function(v) CONFIG.alarm.escCritical = v end },
  { key = "becCritical", group = "Alarms", label = "BEC critical", kind = "number", min = 4.5, max = 8.0, step = 0.1,
    decimals = 1, unit = "V", default = CONFIG.alarm.becCritical, apply = function(v) CONFIG.alarm.becCritical = v end },
  { key = "theme", group = "Display", label = "Theme", kind = "choice", choices = { "Color", "Mono", "Cyan" },
    option = "Theme" },
  { key = "perf", group = "Display", label = "Frame rate", kind = "bool",
    default = CONFIG.perfOverlay, apply = function(v) CONFIG.perfOverlay = v end },
  { key = "modelImage", group = "Display", label = "Model picture", kind = "bool",
    default = CONFIG.showModelImage, apply = function(v) CONFIG.showModelImage = v end },
  { key = "simple", group = "Display", label = "Simple screen", kind = "bool",
    default = CONFIG.simple.on, apply = function(v) CONFIG.simple.on = v end },
  { key = "flightTime", group = "Flight", label = "Flight time call", kind = "number", min = 0, max = 900, step = 30,
    unit = " s", zero = "Off", default = CONFIG.alarm.flightTimeSec, apply = function(v) CONFIG.alarm.flightTimeSec = v end },
  { key = "logClose", group = "Flight", label = "Flight log closes", kind = "number", min = 0, max = 300, step = 30,
    unit = " s", zero = "Never", default = CONFIG.flightLogTimeoutSec, apply = function(v) CONFIG.flightLogTimeoutSec = v end },
  { key = "fullCheck", group = "Flight", label = "Full charge check", kind = "bool",
    default = CONFIG.alarm.fullCheck, apply = function(v) CONFIG.alarm.fullCheck = v end },
  { key = "fullCell", group = "Flight", label = "Full at cell", kind = "number", min = 3.80, max = 4.40, step = 0.05,
    decimals = 2, unit = "V", default = CONFIG.alarm.fullCell, apply = function(v) CONFIG.alarm.fullCell = v end },
  { key = "pickTimeout", group = "Flight", label = "Picker keeps after", kind = "number", min = 0, max = 60, step = 5,
    unit = " s", zero = "Never", default = CONFIG.batteryProfile.timeoutSec,
    apply = function(v) CONFIG.batteryProfile.timeoutSec = v end },
}
-- not shown (no group): the model's own name while it has the FC's (FC.nameUpdate)
SETTINGS[#SETTINGS + 1] = { key = "prevName", group = "", label = "", kind = "text", length = 15, default = "" }
-- battery profile names (picker tiles, history), free text typed on the radio
for i = 1, 6 do
  SETTINGS[#SETTINGS + 1] = { key = "pack" .. i, group = "Packs", label = "Pack " .. i, kind = "text", length = 16,
    pack = i, default = CONFIG.batteryProfile.labels[i],
    apply = function(v) CONFIG.batteryProfile.labels[i] = (v ~= "") and v or ("Profile " .. i) end }
end

-- current value: the user's, else the widget option, else the default
SET.byKey = {}
for _, def in ipairs(SETTINGS) do SET.byKey[def.key] = def end

function SET.value(wgt, def)
  local u = USER[def.key]
  if u ~= nil then return u end
  local o = def.option and wgt and wgt.options and wgt.options[def.option]
  if o ~= nil and (def.kind ~= "number" or (o >= def.min and o <= def.max)) then
    return math.floor(o)
  end
  if def.kind == "choice" then return 0 end
  return def.default
end

function SET.save()
  pcall(function()
    local f = io.open(SET.file, "w")
    if not f then return end
    for _, def in ipairs(SETTINGS) do
      local v = USER[def.key]
      if v ~= nil then
        if type(v) == "boolean" then v = v and 1 or 0 end
        io.write(f, def.key, "=", tostring(v), "\n")
      end
    end
    io.close(f)
  end)
end

function SET.load()
  pcall(function()
    local f = io.open(SET.file, "r")
    if not f then return end
    local text = io.read(f, 2048) or ""
    io.close(f)
    for key, val in string.gmatch(text, "([%w_]+)=([^\r\n]*)") do
      for _, def in ipairs(SETTINGS) do
        if def.key == key then
          local n = tonumber(val)
          if def.kind == "text" then USER[key] = val
          elseif n then USER[key] = (def.kind == "bool") and (n ~= 0) or n end
        end
      end
    end
  end)
  for _, def in ipairs(SETTINGS) do
    if def.apply and USER[def.key] ~= nil then def.apply(USER[def.key]) end
  end
end

function SET.set(def, v)
  if def.kind == "number" then
    v = math.max(def.min, math.min(def.max, v))
    v = math.floor(v / def.step + 0.5) * def.step
    if def.decimals then v = tonumber(string.format("%." .. def.decimals .. "f", v)) end
  elseif def.kind == "text" then -- one line in settings.txt; EdgeTX's TextEdit hands back length bytes
    v = string.sub((string.gsub(tostring(v or ""), "%c", "")), 1, def.length or 16)
    v = string.match(v, "^%s*(.-)%s*$")
  end
  USER[def.key] = v
  if def.apply then def.apply(v) end
  SET.save()
end

function SET.text(wgt, def)
  local v = SET.value(wgt, def)
  if def.kind == "bool" then return v and "On" or "Off" end
  if def.kind == "choice" then return def.choices[(v or 0) + 1] or def.choices[1] end
  if def.kind == "text" then return v or "" end
  if v == nil then return "--" end
  if def.zero and v == 0 then return def.zero end
  return string.format("%." .. (def.decimals or 0) .. "f", v) .. (def.unit or "")
end

-- ============================== FLIGHT HISTORY ============================
-- Every flight (a connect with at least CONFIG.history.minSec of rotor
-- time) is written when the link drops: one CSV line per flight in
-- /LOGS/RotorHUD-<model>.csv, and running totals in
-- /WIDGETS/RotorHUD/stats-<model>.txt (flights, rotor time, mAh, last
-- flight; per battery profile ("pack") the flights, mAh and last use; the
-- last flights) for the history screen. Plain key=value lines.
local HIST = { MAXRECENT = 6 }

function HIST.name(model) return (string.gsub(model or "model", "[^%w%-_]", "_")) end
function HIST.statsPath(model) return "/WIDGETS/RotorHUD/stats-" .. HIST.name(model) .. ".txt" end

function HIST.empty() return { flights = 0, seconds = 0, mah = 0, last = "", packs = {}, recent = {} } end

function HIST.load(model)
  local s = HIST.empty()
  pcall(function()
    local f = io.open(HIST.statsPath(model), "r")
    if not f then return end
    local text = io.read(f, 4096) or ""
    io.close(f)
    for key, val in string.gmatch(text, "([%w_]+)=([^\n]*)") do
      local pn = string.match(key, "^p(%d)$")
      local rn = string.match(key, "^r(%d)$")
      if pn then
        local n, mah, last = string.match(val, "^(%d+),(%d+),(.*)$")
        if n then s.packs[tonumber(pn)] = { n = tonumber(n), mah = tonumber(mah), last = last } end
      elseif rn then
        local d, sec, mah, rpm, pack = string.match(val, "^([^|]*)|(%d+)|(%d+)|(%d+)|(%d*)$")
        if d then
          s.recent[tonumber(rn)] = { date = d, sec = tonumber(sec), mah = tonumber(mah), rpm = tonumber(rpm),
            pack = tonumber(pack) }
        end
      elseif key == "last" then
        s.last = val
      elseif tonumber(val) then
        s[key] = tonumber(val)
      end
    end
  end)
  return s
end

function HIST.save(model, s)
  pcall(function()
    local f = io.open(HIST.statsPath(model), "w")
    if not f then return end
    io.write(f, "flights=", tostring(s.flights), "\n", "seconds=", tostring(s.seconds), "\n",
      "mah=", tostring(s.mah), "\n", "last=", s.last, "\n")
    for i = 1, 6 do
      local p = s.packs[i]
      if p then io.write(f, "p", tostring(i), "=", tostring(p.n), ",", tostring(p.mah), ",", p.last, "\n") end
    end
    for i = 1, #s.recent do
      local r = s.recent[i]
      io.write(f, "r", tostring(i), "=", r.date, "|", tostring(r.sec), "|", tostring(r.mah), "|",
        tostring(r.rpm), "|", r.pack and tostring(r.pack) or "", "\n")
    end
    io.close(f)
  end)
end

-- Flight history > Reset: totals, packs and recent start over. The full
-- record (/LOGS/RotorHUD-<model>.csv) is kept.
function HIST.reset(model) HIST.save(model, HIST.empty()) end

function HIST.record(wgt)
  local sec = math.floor(wgt.flightSeconds or 0)
  if sec < CONFIG.history.minSec then return end
  local info = model and model.getInfo and model.getInfo()
  local name = info and info.name or "model"
  local ok, dt = pcall(getDateTime)
  local date = (ok and dt) and string.format("%04d/%02d/%02d %02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min) or ""
  local mah = math.floor(wgt.maxCapacity or 0)
  local rpm = math.floor(wgt.maxHeadspeed or 0)
  local pack = wgt.flightPack
  pcall(function() -- the full record, one CSV line per flight
    local path = "/LOGS/RotorHUD-" .. HIST.name(name) .. ".csv"
    local exists = io.open(path, "r")
    if exists then io.close(exists) end
    local f = io.open(path, "a")
    if not f then return end
    if not exists then
      io.write(f, "date,model,pack,rotor_s,used_mah,min_charge,max_rpm,max_a,max_w,min_v,min_cell,min_bec,max_esc\n")
    end
    local function n(v, d) return v and string.format("%." .. (d or 0) .. "f", v) or "" end
    io.write(f, date, ",", name, ",", pack and tostring(pack) or "", ",", tostring(sec), ",", tostring(mah), ",",
      n(wgt.minCharge), ",", tostring(rpm), ",", n(wgt.maxCurrent, 1), ",", n(wgt.maxPower), ",",
      n(wgt.minVoltage, 1), ",", n(wgt.minCellVoltage, 2), ",", n(wgt.minBecVoltage, 1), ",", n(wgt.maxEscTemp), "\n")
    io.close(f)
  end)
  local s = HIST.load(name)
  s.flights, s.seconds, s.mah, s.last = s.flights + 1, s.seconds + sec, s.mah + mah, date
  if pack then
    local p = s.packs[pack] or { n = 0, mah = 0, last = "" }
    p.n, p.mah, p.last = p.n + 1, p.mah + mah, date
    s.packs[pack] = p
  end
  table.insert(s.recent, 1, { date = date, sec = sec, mah = mah, rpm = rpm, pack = pack })
  while #s.recent > HIST.MAXRECENT do table.remove(s.recent) end
  HIST.save(name, s)
  wgt.histCache = nil
end

-- ============================== WIDGET API ================================
local function create(zone, options)
  SET.load()
  return {
    zone = zone,
    options = options,
    sensorCache = {},
    flightSeconds = 0,
    flightBaseSeconds = 0,
    flightRunStart = nil,
    modelImageName = nil,
    modelBitmap = nil,
    maxCurrent = nil,
    minVoltage = nil,
    minBecVoltage = nil,
    wasConnected = false,
    showFlightLog = false, -- only true right after a real disconnect (see refresh())
    disconnectTime = nil,
    armWarningActive = false,
    maxEscTemp = nil,
    maxCapacity = nil,
    maxHeadspeed = nil,
    minCharge = nil,
    minCellVoltage = nil,
    maxPower = nil,
    samples = newFlightSamples(),
    alarm = newAlarmState(),
    alarmMuted = false,
    wasRunning = false,
    lastScreenType = nil,
    screenTransitionTime = nil,
  }
end

local function update(wgt, options)
  wgt.options = options
end

-- ---- Simulator scenario (CONFIG.simulate only) -----------------------
-- One 140s loop, in seconds from the first refresh:
--   0-5    disconnected            -> standby
--   5-12   ARMD=67108872           -> armwarning
--   12-17  connected, disarmed     -> dashboard (idle)
--   17-27  armed, SPOOLUP          -> headspeed/throttle ramp up
--   27-67  ACTIVE                  -> pack drains, temp crosses escTempWarn,
--                                     PID/RTE switch at 47s
--   67-72  HOLD (throttle cut), spool down
--   72-75  disarmed (EscC/Bat% drop to 0 like the real FC)
--   75-140 disconnected            -> flightlog, then standby after 60s
-- Values are a plausible 12S setup, not measurements.
local SIM_CYCLE_SEC = 140

local SIM_CELLS = 12

local function lerp(a, b, f)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return a + (b - a) * f
end

local function simulateTelemetry(wgt)
  local now = getTime()
  if not wgt.simStart then wgt.simStart = now end
  local s = ((now - wgt.simStart) / 100) % SIM_CYCLE_SEC

  if s < 5 or s >= 75 then
    return {} -- link down: every sensor nil, signal nil
  end

  local t = {
    signal = 100, armd = 0, armFlags = 0, gov = "OFF", rpm = 0, throttle = 0,
    voltage = 50.4, current = 0.4, temp = 32, charge = 100, capacity = 0,
    becV = 8.3, bank = 1, pidProfile = 1,
    -- Follows mspSetBatteryProfile() 0.5s after a "send" (no FC here)
    battProfile = wgt.simBattProfile or 1,
  }
  if wgt.simBattPending and now >= wgt.simBattPending.at then
    wgt.simBattProfile, wgt.simBattPending = wgt.simBattPending.value, nil
  end

  if s < 12 then
    t.armd = 67108872
  elseif s < 17 then
    -- connected, disarmed, idle on the bench
  elseif s < 27 then
    local f = (s - 17) / 10
    t.armFlags, t.gov = 1, "SPOOLUP"
    t.rpm      = lerp(0, 2100, f)
    t.throttle = lerp(0, 85, f)
    t.current  = lerp(1, 25, f)
    t.voltage  = lerp(50.4, 49.6, f)
    t.capacity = lerp(0, 60, f)
    t.charge   = lerp(100, 99, f)
    t.temp     = lerp(32, 40, f)
  elseif s < 67 then
    local f = (s - 27) / 40
    local wobble = math.sin(s * 3.1)
    t.armFlags, t.gov = 1, "ACTIVE"
    t.rpm      = 2100 + 25 * wobble
    t.throttle = 80 + 8 * wobble
    t.current  = 45 + 35 * math.max(0, math.sin(s * 0.9))
    t.voltage  = lerp(49.6, 42.6, f) - t.current * 0.02
    t.capacity = lerp(60, 3800, f)
    t.charge   = lerp(99, 25, f)
    t.temp     = lerp(40, 96, f)
    t.becV     = 8.2 - 0.3 * math.max(0, wobble)
    if s >= 47 then t.bank, t.pidProfile = 2, 3 end
  elseif s < 72 then
    local f = (s - 67) / 5
    t.armFlags, t.gov = 1, "HOLD"
    t.rpm      = lerp(2100, 0, f)
    t.current  = lerp(5, 0.4, f)
    t.voltage  = lerp(43.5, 45.6, f)
    t.capacity = 3800
    t.charge   = 25
    t.temp     = lerp(96, 88, f)
    t.bank, t.pidProfile = 2, 3
  else
    -- disarmed: FC resets consumed/remaining to 0, as on the real radio
    t.voltage, t.temp, t.bank, t.pidProfile = 45.8, 86, 2, 3
    t.capacity, t.charge = 0, 0
  end

  t.perCellVoltage = t.voltage / SIM_CELLS
  return t
end

local function readTelemetry(wgt)
  if CONFIG.simulate then return simulateTelemetry(wgt) end
  local c, s = wgt.sensorCache, CONFIG.sensors

  local govId    = resolveSensor(c, "governor", s.governor)
  local rpmId    = resolveSensor(c, "rpm", s.rpm)
  local vId      = resolveSensor(c, "voltage", s.voltage)
  local cellVId  = resolveSensor(c, "cellVoltage", s.cellVoltage)
  local cellCId  = resolveSensor(c, "cellCount", s.cellCount)
  local aId      = resolveSensor(c, "current", s.current)
  local tId      = resolveSensor(c, "temp", s.temp)
  local chgId    = resolveSensor(c, "charge", s.charge)
  local capId    = resolveSensor(c, "capacity", s.capacity)
  local thrId    = resolveSensor(c, "throttle", s.throttle)
  local becId    = resolveSensor(c, "becVoltage", s.becVoltage)
  local bankId   = resolveSensor(c, "bank", s.bank)
  local pidId    = resolveSensor(c, "pidProfile", s.pidProfile)
  local armdId   = resolveSensor(c, "armDisableFlags", s.armDisableFlags)
  local armfId   = resolveSensor(c, "armFlags", s.armFlags)
  local sigId    = resolveSensor(c, "signal", s.signal)
  local bpId     = resolveSensor(c, "batteryProfile", s.batteryProfile)

  local govText  = decodeGovernor(govId and getValue(govId) or nil)
  local rpm      = rpmId and getValue(rpmId) or nil
  local voltage  = vId and getValue(vId) or nil
  local current  = aId and getValue(aId) or nil
  local temp     = tId and getValue(tId) or nil
  local charge   = chgId and getValue(chgId) or nil
  local capacity = capId and getValue(capId) or nil
  local throttle = thrId and getValue(thrId) or nil -- CALIBRATE: may be -100..100 on some radios
  local becV     = becId and getValue(becId) or nil
  local bank     = bankId and getValue(bankId) or nil
  local pidProfile = pidId and getValue(pidId) or nil
  local armd     = armdId and getValue(armdId) or nil
  local armFlags = armfId and getValue(armfId) or nil
  local signal   = sigId and getValue(sigId) or nil
  local battProfile = bpId and getValue(bpId) or nil

  local perCellVoltage = nil
  if cellVId then
    perCellVoltage = getValue(cellVId)
  elseif cellCId and voltage then
    local cc = getValue(cellCId)
    if cc and cc > 0 then perCellVoltage = voltage / cc end
  end

  -- Normalize throttle to 0-100% if it looks like a -100..100 stick value.
  if throttle and throttle < 0 then
    throttle = (throttle + 100) / 2
  end

  return {
    gov = govText, rpm = rpm, voltage = voltage, perCellVoltage = perCellVoltage,
    current = current, temp = temp, charge = charge, capacity = capacity, throttle = throttle,
    becV = becV, bank = bank, pidProfile = pidProfile, armd = armd, armFlags = armFlags, signal = signal,
    battProfile = (battProfile and battProfile > 0) and math.floor(battProfile) or nil,
  }
end

-- Track a simple flight timer: runs while the rotor is spinning, resets to
-- zero once it stops (mirrors the "00:00 / paused" behavior on the ground).
local function updateFlightTimer(wgt, t)
  local now = getTime() -- getTime() ticks are 10ms each (i.e. 1/100 second)
  local running = (t.rpm and t.rpm > CONFIG.rpmRunningThreshold)
                  or (t.gov and (string.find(string.upper(t.gov), "ACTIVE")
                                 or string.find(string.upper(t.gov), "SPOOLUP")
                                 or string.find(string.upper(t.gov), "RECOVERY")))

  -- Accumulates across multiple motor on/off cycles within the same
  -- session, same lifecycle as Max Amp/Min Volt: pauses (holds its
  -- value) while the rotor is stopped, resumes adding on the next
  -- spin-up, and is only cleared by resetTelemetryState on a telemetry
  -- reconnect - never just because the motor stopped.
  if running then
    if not wgt.flightRunStart then
      wgt.flightRunStart = now
    end
    wgt.flightSeconds = wgt.flightBaseSeconds + (now - wgt.flightRunStart) / 100
  elseif wgt.flightRunStart then
    -- Just stopped: fold this run segment into the held base total,
    -- then stay paused there (not reset to 0).
    wgt.flightBaseSeconds = wgt.flightBaseSeconds + (now - wgt.flightRunStart) / 100
    wgt.flightRunStart = nil
    wgt.flightSeconds = wgt.flightBaseSeconds
  end
  return running
end

-- Tracks peak current draw for the current flight, resetting alongside
-- the flight timer (i.e. once the rotor stops, next spin-up starts a
-- fresh peak rather than carrying the previous flight's number forward).
-- Tracks the highest current draw seen since the widget was created
-- (i.e. since the radio was turned on) - persists across the whole
-- session rather than resetting when the rotor stops, so it survives
-- between flights until the radio is power-cycled or the script
-- reloads.
local function updateMaxCurrent(wgt, t, running)
  if running and t.current and (not wgt.maxCurrent or t.current > wgt.maxCurrent) then
    wgt.maxCurrent = t.current
  end
end

-- Tracks the lowest pack voltage seen since the widget was created -
-- same persistent, session-wide lifecycle as updateMaxCurrent above.
local function updateMinVoltage(wgt, t, running)
  if running and t.voltage and (not wgt.minVoltage or t.voltage < wgt.minVoltage) then
    wgt.minVoltage = t.voltage
  end
end

-- Same idea as updateMinVoltage, but for BEC voltage - a separate
-- sensor/rail, so it gets its own session-low tracker.
local function updateMinBecVoltage(wgt, t, running)
  if running and t.becV and (not wgt.minBecVoltage or t.becV < wgt.minBecVoltage) then
    wgt.minBecVoltage = t.becV
  end
end

-- Tracks the highest ESC temperature seen this session - same
-- persistent, session-wide lifecycle as updateMaxCurrent/MinVoltage.
local function updateMaxEscTemp(wgt, t, running)
  if running and t.temp and (not wgt.maxEscTemp or t.temp > wgt.maxEscTemp) then
    wgt.maxEscTemp = t.temp
  end
end

-- Tracks how long "Arming Disable Flags" has been continuously nonzero
-- (any reason, not just one specific code), so the full-screen arm
-- warning only kicks in once that's been sustained for at least a
-- second - a debounce against a single noisy/momentary reading rather
-- than a real, persistent block on arming.
-- Debounce interval set to 0: the warning screen now triggers
-- immediately on any nonzero reading, with no minimum sustain time.
local function updateArmWarning(wgt, t)
  wgt.armWarningActive = (t.armd ~= nil and t.armd ~= 0)
end

-- Latches the last known capacity-consumed reading while telemetry is
-- alive, so it's still available to show on the flight-log screen
-- after the link drops (t.capacity itself goes nil once disconnected,
-- since it's a live sensor read rather than something this script
-- accumulates on its own).
-- Tracks the highest capacity-consumed reading seen this session -
-- NOT just the latest one. Rotorflight/Betaflight-style FCs commonly
-- reset consumed capacity back to 0 on disarm, which happens before
-- the telemetry link actually drops - a plain "latch the latest value"
-- would end up holding that post-reset 0 instead of the real flight's
-- peak consumption, which is what actually happened here.
local function updateMaxCapacity(wgt, t, running)
  if running and t.capacity and (not wgt.maxCapacity or t.capacity > wgt.maxCapacity) then
    wgt.maxCapacity = t.capacity
  end
end

-- Tracks the highest headspeed seen this session - for the flight log,
-- same persistent lifecycle as the other max/min trackers.
local function updateMaxHeadspeed(wgt, t, running)
  if running and t.rpm and (not wgt.maxHeadspeed or t.rpm > wgt.maxHeadspeed) then
    wgt.maxHeadspeed = t.rpm
  end
end

-- Tracks the lowest battery-charge % seen this session (i.e. the most
-- depleted point reached) - same reasoning as updateMaxCapacity above:
-- a plain latch of "whatever's most recent" is vulnerable to any
-- post-disarm reset/jump on the FC side, so this only ever moves down.
-- Gated on "running" (rotor spinning), same as updateMinVoltage - a
-- charge% sensor can briefly report a bogus 0 right as telemetry
-- first comes up, before it settles on the real reading; requiring
-- the rotor to actually be spinning avoids latching onto that.
local function updateMinCharge(wgt, t, running)
  if running and t.charge and (not wgt.minCharge or t.charge < wgt.minCharge) then
    wgt.minCharge = t.charge
  end
end

-- Flight-log extras, same "only while running" gating as the trackers
-- above: lowest cell voltage, peak power (V x A), and the graph samples.
local function updateFlightSamples(wgt, t, running)
  if not running then return end
  if t.perCellVoltage and (not wgt.minCellVoltage or t.perCellVoltage < wgt.minCellVoltage) then
    wgt.minCellVoltage = t.perCellVoltage
  end
  if t.voltage and t.current then
    local p = t.voltage * t.current
    if not wgt.maxPower or p > wgt.maxPower then wgt.maxPower = p end
  end

  local s, now = wgt.samples, getTime()
  if s.last and now - s.last < s.interval * 100 then return end
  s.last = now
  local n = #s.rpm + 1
  s.rpm[n] = t.rpm or 0
  s.current[n] = t.current or 0
  s.voltage[n] = t.voltage or 0
  if n >= FLIGHT_SAMPLES_MAX then
    for _, key in ipairs({ "rpm", "current", "voltage" }) do
      local src, dst = s[key], {}
      for i = 1, n - 1, 2 do dst[#dst + 1] = (src[i] + src[i + 1]) / 2 end
      s[key] = dst
    end
    s.interval = s.interval * 2
  end
end

-- Telemetry link check, used to detect a reconnect (link was down, now
-- it's back). Prefers the fixed "RSSI" source EdgeTX exposes on every
-- radio/protocol; falls back to our own resolved link-quality sensor
-- (t.signal) if that fixed source isn't available for some reason.
local function isTelemetryConnected(t)
  if CONFIG.simulate then return t.signal ~= nil and t.signal > 0 end
  local ok, rssi = pcall(function() return getValue("RSSI") end)
  if ok and rssi and rssi > 0 then return true end
  if t.signal and t.signal > 0 then return true end
  return false
end

-- Clears every piece of accumulated state (peak current/min voltage,
-- flight timer, and the sensor-id cache) so a fresh reconnect starts
-- clean rather than carrying over numbers from before the link drop.
-- Model picture and TX battery icon caches are left alone - those
-- don't depend on the model's telemetry link.
local function resetTelemetryState(wgt)
  wgt.sensorCache = {}
  wgt.maxCurrent = nil
  wgt.minVoltage = nil
  wgt.minBecVoltage = nil
  wgt.maxEscTemp = nil
  wgt.maxCapacity = nil
  wgt.maxHeadspeed = nil
  wgt.minCharge = nil
  wgt.minCellVoltage = nil
  wgt.maxPower = nil
  wgt.samples = newFlightSamples()
  wgt.alarm = newAlarmState()
  wgt.flightSeconds = 0
  wgt.flightBaseSeconds = 0
  wgt.flightRunStart = nil
  wgt.disconnectTime = nil
end

-- Rendered text width: lcd.sizeText when available (exact, proportional
-- font), else the FONT_SPECS digit average.
local function textWidth(text, font)
  if lcd.sizeText then
    local ok, tw = pcall(lcd.sizeText, text, font)
    if ok and tw then return tw end
  end
  for i = 1, #FONT_SPECS do
    if FONT_SPECS[i].font == font then return string.len(text) * FONT_SPECS[i].charW end
  end
  return string.len(text) * 12 -- default font
end

-- fitFont, but checking the measured width instead of the digit average,
-- so words like "Disarmed"/"Recovery" don't drop a size needlessly.
local function fitFontMeasured(w, h, text, maxFont)
  for i = 1, #FONT_SPECS do
    local spec = FONT_SPECS[i]
    if (maxFont == nil or spec.font <= maxFont) and spec.lineH <= h
       and textWidth(text, spec.font) <= w then
      return spec.font
    end
  end
  return SMLSIZE
end

-- The one readout style used by the cluster and the status tabs: an
-- 18px label row (optional icon + dim label, optional min/max on the
-- right) and the value below it, left-aligned, at up to MIDSIZE. An
-- optional markColor draws a 4px color stripe down the left edge for
-- state-at-a-glance (Arm, Governor).
local TAB_LABEL_H = 18

-- Post-flight summary, shown instead of the plain standby screen right
-- after the link drops (i.e. the aircraft was powered off). All of
-- these values are just whatever this session's trackers were already
-- holding at the moment of disconnect - resetTelemetryState() doesn't
-- clear them until the *next* reconnect, so they're still sitting
-- there, unchanged, for exactly this purpose.
-- Max/min/average of the graph samples in one pass, cached until the
-- samples change. The flight log redraws every frame and the series can
-- hold up to FLIGHT_SAMPLES_MAX points: recomputing them per frame pushed
-- a 400-sample log close to EdgeTX's per-frame "CPU limit".
-- Second return value is true on the frame the stats were (re)computed.
local function flightSampleStats(wgt)
  local s, c = wgt.samples, wgt.flightStats
  local n = #s.rpm
  if c and c.series == s.rpm and c.n == n then return c, false end
  local rpm, cur, volt = s.rpm, s.current, s.voltage
  local maxRpm, maxCur, sumRpm, sumCur, minV, maxV = 0, 0, 0, 0, nil, nil
  for i = 1, n do
    local r, a, v = rpm[i], cur[i], volt[i]
    if r > maxRpm then maxRpm = r end
    if a > maxCur then maxCur = a end
    sumRpm, sumCur = sumRpm + r, sumCur + a
    if v > 0 then
      if not minV or v < minV then minV = v end
      if not maxV or v > maxV then maxV = v end
    end
  end
  c = { series = rpm, n = n, maxRpm = maxRpm, maxCur = maxCur, minV = minV, maxV = maxV,
        avgRpm = (n > 0) and sumRpm / n or nil, avgCur = (n > 0) and sumCur / n or nil }
  wgt.flightStats = c
  return c, true
end

-- Smallest "nice" number (NICE_MANTISSAS x 10^n) that is >= x. Finer than
-- plain 1/2/5 so a 2125 rpm peak gets a 0-2400 axis instead of 0-4000.
local NICE_MANTISSAS = { 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10 }

local function niceUp(x)
  if x <= 0 then return 1 end
  local mag = 10 ^ math.floor(math.log(x, 10))
  local n = x / mag
  for i = 1, #NICE_MANTISSAS do
    if n <= NICE_MANTISSAS[i] + 1e-9 then return NICE_MANTISSAS[i] * mag end
  end
  return 10 * mag
end

-- 4-division axis covering lo..hi with a nice step. fromZero pins the
-- bottom at 0 (headspeed, current); otherwise the bottom is the step
-- multiple below lo (pack voltage). All series share the same 4 grid
-- lines this way, each with its own labels. Returns bottom, step.
local CHART_DIVS = 4

local function chartAxis(lo, hi, fromZero)
  if fromZero then
    return 0, niceUp(math.max(hi, 1) / CHART_DIVS)
  end
  local step = niceUp(math.max(hi - lo, 0.1) / CHART_DIVS)
  local bottom = math.floor(lo / step) * step
  while bottom + CHART_DIVS * step < hi do
    step = niceUp(step * 1.01)
    bottom = math.floor(lo / step) * step
  end
  return bottom, step
end

-- Time-axis step in seconds: the first of these giving <= 3 intervals,
-- so the "m:ss" labels (~50px in SMLSIZE) never collide.
local TIME_STEPS = { 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600 }

-- ============================== ALARMS ====================================
-- Voice + haptic alerts, evaluated by tick() - which runs from BOTH
-- refresh() and background(), so alarms keep working while another
-- screen is shown (refresh only runs while the widget is visible).
--   critical: haptic pattern + voice, repeated every alarm.repeatSec
--             while the condition holds
--   caution : short haptic + voice, once per crossing; re-armed only
--             after the value recovers past its hysteresis
--   info    : voice only, on change (governor, PID/rate, battery 10%
--             steps, arm/disarm)
-- The "Mute" widget option silences every voice and the caution haptic;
-- the critical haptic is never muted.

-- 4.6 names (HOLD/FALLBACK/BYPASS) and the 4.5 ones (THR-OFF/LOST-HS).
local GOV_VOICE = {
  ["OFF"] = "gov_off", ["IDLE"] = "gov_idle", ["SPOOLUP"] = "gov_spoolup",
  ["RECOVERY"] = "gov_recovery", ["ACTIVE"] = "gov_active", ["HOLD"] = "gov_hold",
  ["FALLBACK"] = "gov_fallback", ["AUTOROT"] = "gov_autorot", ["BAILOUT"] = "gov_bailout",
  ["BYPASS"] = "gov_bypass", ["THR-OFF"] = "gov_throff", ["LOST-HS"] = "gov_losths",
}

-- No headspeed signal: called out as a repeating critical, not as info.
local GOV_CRITICAL = { ["FALLBACK"] = true, ["LOST-HS"] = true }

-- A SOURCE widget option counts as "on" while its value is > 0 (switch
-- down / momentary pressed / logical switch true). Unset = never on.
local function sourceActive(src)
  if not src or src == 0 then return false end
  local ok, v = pcall(getValue, src)
  return ok and type(v) == "number" and v > 0
end

local function isMuted(wgt)
  return sourceActive(wgt.options and wgt.options.Mute)
end

local function playPattern(pattern)
  if not playHaptic or CONFIG.alarm.haptic == false then return end
  for i = 1, #pattern do playHaptic(pattern[i][1], pattern[i][2]) end
end

-- One of CONFIG.alarm.toneEffects, unless effects are off or muted.
local function playEffect(wgt, name, force)
  local cfg = CONFIG.alarm
  local tones = cfg.toneEffects[name]
  if not tones or not playTone then return end
  if not force and (cfg.tones == false or (wgt and wgt.alarmMuted)) then return end
  for i = 1, #tones do playTone(tones[i][1], tones[i][2], tones[i][3]) end
  if CONFIG.simulate then
    pcall(function()
      local f = io.open("/LOGS/rotorhud_alarms.log", "a")
      if f then io.write(f, string.format("%.2f tone %s", getTime() / 100, name), "\n"); io.close(f) end
    end)
  end
end

-- Folder of the voice set chosen with the "Voice" option (0-based index
-- into CONFIG.alarm.voiceSets; out of range falls back to the first set).
local function voiceSetDir(wgt)
  local sets = CONFIG.alarm.voiceSets
  local idx = USER.voice
  if idx == nil then idx = wgt.options and wgt.options.Voice end
  idx = idx and math.floor(idx) or 0
  return sets[idx + 1] or sets[1]
end

-- voice: one file name, or a list played in order (e.g. { "batt020", "land" }).
local function alert(wgt, tier, voice)
  local cfg = CONFIG.alarm
  local muted = wgt.alarmMuted
  if tier == "critical" or tier == "caution" then playEffect(wgt, tier) end
  local files = (type(voice) == "table") and voice or { voice }
  for i = 1, #files do
    local path = cfg.dir .. voiceSetDir(wgt) .. "/" .. files[i] .. ".wav"
    if CONFIG.simulate then
      -- Simulator only: debug output plus /LOGS/rotorhud_alarms.log, so a
      -- run can be checked from the SD folder without the debug window.
      local line = string.format("%.2f %s %s%s", getTime() / 100, tier, path, muted and " (muted)" or "")
      print("RotorHUD alarm: " .. line)
      pcall(function()
        local f = io.open("/LOGS/rotorhud_alarms.log", "a")
        if f then io.write(f, line, "\n"); io.close(f) end
      end)
    end
    if not muted and playFile then playFile(path) end
  end
  if tier == "critical" then
    playPattern(cfg.hapticCritical)
  elseif tier == "caution" and not muted then
    playPattern(cfg.hapticCaution)
  end
end

-- Debounced on/off state for one condition: turns on after onCond has
-- held for sustainSec, turns off only once offCond is true.
local function latch(a, key, onCond, offCond, sustainSec)
  local now = getTime()
  if a.active[key] then
    if offCond then a.active[key], a.since[key] = nil, nil end
  elseif onCond then
    a.since[key] = a.since[key] or now
    if now - a.since[key] >= (sustainSec or 0) * 100 then a.active[key] = true end
  else
    a.since[key] = nil
  end
  return a.active[key] == true
end

-- repeatSec: this alarm's repeat interval (default CONFIG.alarm.repeatSec).
local function critical(wgt, key, isOn, voice, repeatSec)
  local a = wgt.alarm
  if not isOn then a.lastFire[key] = nil; return end
  local now = getTime()
  if not a.lastFire[key] or now - a.lastFire[key] >= (repeatSec or CONFIG.alarm.repeatSec) * 100 then
    a.lastFire[key] = now
    alert(wgt, "critical", voice)
  end
end

local function caution(wgt, key, isOn, voice)
  local a = wgt.alarm
  if not isOn then a.fired[key] = nil; return end
  if not a.fired[key] then
    a.fired[key] = true
    alert(wgt, "caution", voice)
  end
end

-- Fires `fn(new)` when `value` changes. The first value seen after a
-- (re)connect is the initial state, not a change - it's only announced
-- for keys listed in a.sayFirst (bank/profile, right after "connected").
local function onChange(a, key, value, fn)
  if value == nil then return end
  local old = a.prev[key]
  -- Connect reports wait out a.quietUntil (EdgeTX's own link voice);
  -- prev stays unset meanwhile, so the first value is still said after.
  if old == nil and a.sayFirst[key] and getTime() < (a.quietUntil or 0) then return end
  a.prev[key] = value
  if (old ~= nil and old ~= value) or (old == nil and a.sayFirst[key]) then
    a.sayFirst[key] = nil
    fn(value)
  end
end

-- Landing threshold in % from the "BattLand" option (10-50), else CONFIG.
local function battLandPct(wgt)
  local v = USER.battLand
  if v == nil then v = wgt.options and wgt.options.BattLand end
  if v and v >= 10 and v <= 50 then return math.floor(v) end
  return CONFIG.alarm.battLand
end

local function runAlarms(wgt, t, running, connected)
  local cfg = CONFIG.alarm
  if not cfg.enabled then return end
  wgt.alarmMuted = isMuted(wgt)
  local a = wgt.alarm
  local landPct = battLandPct(wgt)

  -- Link reports. Connect: "connected", then the current bank/profile as
  -- soon as those sensors report. Disconnect while the rotor was spinning
  -- is the critical "telemetry lost"; otherwise (normal power-off) just
  -- "disconnected". Nothing at power-up when there was never a link.
  -- wgt.alarmLink lives outside wgt.alarm, which is reset on reconnect.
  if connected ~= wgt.alarmLink then
    local own = not cfg.edgetxLinkVoice -- false: EdgeTX already says it
    if connected then
      playEffect(wgt, "connect")
      if own then alert(wgt, "info", "connected") end
      a.sayFirst.arm, a.sayFirst.armd, a.sayFirst.bank, a.sayFirst.pid = true, true, true, true
      a.sayFirst.battprof = true
      a.quietUntil = getTime() + (cfg.edgetxLinkVoice and cfg.connectQuietSec * 100 or 0)
    elseif wgt.alarmLink ~= nil then
      if wgt.wasRunning then
        alert(wgt, "critical", own and "telemetry_lost" or {}) -- haptic + effect either way
      else
        playEffect(wgt, "disconnect")
        if own then alert(wgt, "info", "disconnected") end
      end
    end
    wgt.alarmLink = connected
  end
  if not connected then return end

  -- Critical
  local cellCrit = not cfg.nativeBackup and running and t.perCellVoltage ~= nil and
    latch(a, "cellCrit", t.perCellVoltage < cfg.cellCritical,
      t.perCellVoltage >= cfg.cellCritical + cfg.cellHyst, cfg.cellSustainSec)
  critical(wgt, "cellCrit", cellCrit, "cell_critical")

  -- "Battery NN%, land now" with NN = the charge at the time it's said
  -- (1% voice files exist for 0-50, the BattLand range).
  local battCrit = not cfg.nativeBackup and running and t.charge ~= nil and t.charge <= landPct
  local battNow = t.charge and math.max(0, math.min(100, math.floor(t.charge))) or 0
  critical(wgt, "battCrit", battCrit, { string.format("batt%03d", battNow), "land" }, cfg.battRepeatSec)

  local escCrit = t.temp ~= nil and
    latch(a, "escCrit", t.temp >= cfg.escCritical, t.temp < cfg.escCritical - cfg.escHyst, 0)
  critical(wgt, "escCrit", escCrit, "esc_critical")

  local becCrit = t.becV ~= nil and t.becV > 0 and
    latch(a, "becCrit", t.becV < cfg.becCritical, t.becV >= cfg.becCritical + cfg.becHyst, 1)
  critical(wgt, "becCrit", becCrit, "bec_low")

  local govUpper = t.gov and string.upper(t.gov)
  critical(wgt, "govLost", govUpper ~= nil and GOV_CRITICAL[govUpper] == true, GOV_VOICE[govUpper])

  -- Caution. While the matching critical is active the caution counts as
  -- already said, so it doesn't pop up again the moment the critical
  -- clears (the value is still below the caution threshold then).
  local cellCau = running and t.perCellVoltage ~= nil and
    latch(a, "cellCau", t.perCellVoltage < cfg.cellCaution,
      t.perCellVoltage >= cfg.cellCaution + cfg.cellHyst, cfg.cellSustainSec)
  if cellCrit then a.fired.cellCau = cellCau or nil else caution(wgt, "cellCau", cellCau, "cell_low") end

  local escCau = t.temp ~= nil and
    latch(a, "escCau", t.temp >= cfg.escCaution, t.temp < cfg.escCaution - cfg.escHyst, 0)
  if escCrit then a.fired.escCau = escCau or nil else caution(wgt, "escCau", escCau, "esc_hot") end

  caution(wgt, "timer", cfg.flightTimeSec > 0 and wgt.flightSeconds >= cfg.flightTimeSec, "flight_time")

  -- The battery-profile picker after a connect: the state reports (arm,
  -- governor, rate, profile) stay quiet while it is up, and the values are
  -- taken as known, so they aren't said once it closes either. While it
  -- is pending (waiting for BAT#) they are held back, and said as usual if
  -- no picker comes.
  -- (arming closes the picker: from then on everything is said as usual)
  local armedNow = t.armFlags ~= nil and math.floor(t.armFlags) % 2 == 1
  local bpPhase = (wgt.bp and not armedNow) and wgt.bp.phase or nil
  local function info(key, value, fn)
    if bpPhase == "wait" then return end
    if bpPhase then
      if value ~= nil then a.prev[key] = value end
      a.sayFirst[key] = nil
      return
    end
    onChange(a, key, value, fn)
  end

  -- Info. Arm state first, so right after "connected" the order is
  -- arm -> (arming blocked) -> bank -> profile.
  info("arm", t.armFlags and (math.floor(t.armFlags) % 2 == 1), function(armed)
    alert(wgt, "info", armed and "armed" or "disarmed")
  end)
  -- Arming blocked (ARMD nonzero, same trigger as the arm-warning screen):
  -- caution, said when it becomes nonzero or changes code, followed by up
  -- to two decoded reasons; nothing when it clears.
  onChange(a, "armd", t.armd and math.floor(t.armd), function(code)
    if code == ARMD_ARM_SWITCH_AT_POWERUP then
      alert(wgt, "caution", "arm_switch_on")
    elseif code ~= 0 then
      alert(wgt, "caution", "arm_disabled")
      local reasons = decodeArmd(code)
      for i = 1, math.min(2, #reasons) do alert(wgt, "info", reasons[i][3]) end
    end
  end)
  info("gov", govUpper, function(g)
    if not GOV_CRITICAL[g] then alert(wgt, "info", GOV_VOICE[g]) end -- critical above
  end)
  -- Bank = RTE# (rates profile, the V-bar "bank"), Profile = PID#.
  info("bank", t.bank and math.floor(t.bank), function(b) alert(wgt, "info", "bank" .. b) end)
  info("pid", t.pidProfile and math.floor(t.pidProfile), function(p) alert(wgt, "info", "profile" .. p) end)
  -- Haptics on a change (not the first value after a connect - wgt.alarm
  -- starts over then): arm one pulse, disarm two; rate / PID profile one
  -- pulse for both, as one switch moves them together (right away, and
  -- further changes within 1 s add nothing).
  local hp = a.haptic or {}
  a.haptic = hp
  if t.armFlags ~= nil then
    if hp.arm ~= nil and hp.arm ~= armedNow then playPattern(armedNow and cfg.hapticArm or cfg.hapticDisarm) end
    hp.arm = armedNow
  end
  if t.bank ~= nil or t.pidProfile ~= nil then
    local prof = tostring(t.bank and math.floor(t.bank)) .. "/" .. tostring(t.pidProfile and math.floor(t.pidProfile))
    local now = getTime()
    if hp.prof ~= nil and hp.prof ~= prof then
      if now - (hp.profAt or -1000) > 100 then playPattern(cfg.hapticProfile) end
      hp.profAt = now
    end
    hp.prof = prof
  end
  -- Battery profile (BAT#): also how a picker change gets confirmed aloud.
  -- With the picker: the current profile isn't announced on connect (the
  -- picker asks instead), only a change made with it.
  if bpPhase == "wait" then
    -- held back until the picker shows (or doesn't)
  elseif bpPhase and a.prev.battprof == nil then
    a.prev.battprof, a.sayFirst.battprof = t.battProfile, nil
  else
    onChange(a, "battprof", t.battProfile, function(b) alert(wgt, "info", "battprofile" .. b) end)
  end

  -- Battery: one call per 10% step going down, rotor spinning only (the
  -- FC zeroes Bat% on disarm). "90%" is said when the charge reaches 90
  -- (ceil, so 99% stays in the 100 step). The step within 10% above the
  -- landing threshold adds the caution haptic; at or below the threshold
  -- the repeating "land now" critical above takes over.
  if running and t.charge then
    local step = math.max(0, math.min(10, math.ceil(t.charge / 10)))
    local last = a.prev.battStep
    if last == nil or step > last then
      a.prev.battStep = step -- first reading, or a fresh pack
    elseif step < last then
      a.prev.battStep = step
      local pct = step * 10
      if pct > landPct then -- critical (or the native backup) covers the rest
        local tier = (pct <= landPct + 10) and "caution" or "info"
        alert(wgt, tier, string.format("batt%03d", pct))
      end
    end
  end

  -- At or below the landing threshold: every 1% drop is called out (the
  -- critical above keeps the haptic + "land now" every battRepeatSec).
  -- The first reading only seeds the counter - the critical just said it.
  if running and t.charge and t.charge <= landPct then
    local last = a.prev.battPct
    if last == nil or battNow > last then
      a.prev.battPct = battNow
    elseif battNow < last then
      a.prev.battPct = battNow
      alert(wgt, "info", string.format("batt%03d", battNow))
    end
  end
end

-- Battery not full (CONFIG.alarm.fullCheck): one look per connect, see
-- CONFIG.alarm. wgt.fullAlert = { at, cell } while the window is open.
local function fullChargeCheck(wgt, t, connected, running, armed)
  local cfg, now = CONFIG.alarm, getTime()
  if not connected then wgt.fullChecked, wgt.fullAlert = nil, nil; return end
  local a = wgt.fullAlert
  if a and (armed or now - a.at > cfg.fullAlertSec * 100) then wgt.fullAlert = nil end
  if wgt.fullChecked or not cfg.fullCheck then return end
  if now < (wgt.alarm.quietUntil or 0) + 100 or not t.perCellVoltage or t.perCellVoltage <= 0 then return end
  wgt.fullChecked = true
  if armed or running or t.perCellVoltage >= cfg.fullCell then return end
  wgt.fullAlert = { at = now, cell = t.perCellVoltage }
  playEffect(wgt, "caution")
  playPattern(cfg.hapticCaution)
end

-- ============================== RF TELEMETRY ==============================
-- Rotorflight CRSF custom telemetry decoder + MSP-over-CRSF client, so the
-- rf2bg special function (or the RfTool widget) isn't needed.
-- Ported from rotorflight-lua-scripts (GPL-3.0, like this file):
--   src/SCRIPTS/RF2/rf2tlm.lua          frame loop
--   src/SCRIPTS/RF2/rf2tlm_sensors.lua  sensor ids / names / units / decoders
--   src/SCRIPTS/RF2/MSP/crsf.lua, common.lua  MSP framing
-- Same sids and names as rf2tlm, so the model's existing sensors carry on.
-- bit32 calls rewritten as arithmetic. Not ported: background_init's FC
-- writes (RTC, model name) - only decoding and the MSP reads we need.
--
-- crossfireTelemetryPop reads ONE queue shared by every script (EdgeTX 2.12
-- lua/api_general.cpp getTelemetryQueue), so rf2bg / RfTool must be off:
-- two readers split the frames between them and both lose data.
local function decNil(d, p) return nil, p end

local function decU8(d, p) return d[p], p + 1 end

local function decS8(d, p) local v = d[p]; return v < 0x80 and v or v - 0x100, p + 1 end

local function decU16(d, p) return d[p] * 256 + d[p + 1], p + 2 end

local function decS16(d, p) local v = d[p] * 256 + d[p + 1]; return v < 0x8000 and v or v - 0x10000, p + 2 end

local function decU24(d, p) return (d[p] * 256 + d[p + 1]) * 256 + d[p + 2], p + 3 end

local function decS24(d, p) local v = decU24(d, p); return v < 0x800000 and v or v - 0x1000000, p + 3 end

local function decU32(d, p) return ((d[p] * 256 + d[p + 1]) * 256 + d[p + 2]) * 256 + d[p + 3], p + 4 end

local function decS32(d, p) local v = decU32(d, p); return v < 0x80000000 and v or v - 0x100000000, p + 4 end

local function decS12S12(d, p)
  local a = (d[p] % 16) * 256 + d[p + 1]
  local b = math.floor(d[p] / 16) * 256 + d[p + 2]
  return a < 0x800 and a or a - 0x1000, b < 0x800 and b or b - 0x1000, p + 3
end

local function decCellV(d, p) local v = d[p]; return v > 0 and v + 200 or 0, p + 1 end

local function decCells(d, p)
  local cnt = d[p]; p = p + 1
  setTelemetryValue(0x1020, 0, 0, cnt, UNIT_RAW, 0, "Cel#")
  for i = 1, cnt do
    local v = d[p]; p = p + 1
    v = v > 0 and v + 200 or 0
    setTelemetryValue(0x102F, 0, 0, cnt * 16777216 + (i - 1) * 65536 + v, UNIT_CELLS, 2, "Cels")
  end
  return nil, p
end

local function decControl(d, p)
  local pt, rl, yw, cl
  pt, rl, p = decS12S12(d, p)
  yw, cl, p = decS12S12(d, p)
  setTelemetryValue(0x1031, 0, 0, pt, UNIT_DEGREE, 2, "CPtc")
  setTelemetryValue(0x1032, 0, 0, rl, UNIT_DEGREE, 2, "CRol")
  setTelemetryValue(0x1033, 0, 0, 3 * yw, UNIT_DEGREE, 2, "CYaw")
  setTelemetryValue(0x1034, 0, 0, cl, UNIT_DEGREE, 2, "CCol")
  return nil, p
end

local function decTriple(sids, names, unit, prec)
  return function(d, p)
    for i = 1, 3 do
      local v; v, p = decS16(d, p)
      setTelemetryValue(sids[i], 0, 0, v, unit, prec, names[i])
    end
    return nil, p
  end
end

local function decLatLong(d, p)
  local lat, lon
  lat, p = decS32(d, p)
  lon, p = decS32(d, p)
  setTelemetryValue(0x1125, 0, 0, 0, UNIT_GPS, 0, "GPS")
  setTelemetryValue(0x1125, 0, 0, lat / 10, 44) -- UNIT_GPS_LATITUDE
  setTelemetryValue(0x1125, 0, 0, lon / 10, 43) -- UNIT_GPS_LONGITUDE
  return nil, p
end

local function decAdjFunc(d, p)
  local fun, val
  fun, p = decU16(d, p)
  val, p = decS32(d, p)
  setTelemetryValue(0x1221, 0, 0, fun, UNIT_RAW, 0, "AdjF")
  setTelemetryValue(0x1222, 0, 0, val, UNIT_RAW, 0, "AdjV")
  return nil, p
end

-- sid -> { name, unit, prec, decoder }, every sensor rf2tlm_sensors.lua
-- knows: a frame is a run of sid/value pairs, and an unknown sid makes the
-- rest of the frame unreadable, so the table can't be trimmed.
local RF_SENSORS = {
  [0x1000] = { "NONE", UNIT_RAW, 0, decNil },      [0x1001] = { "BEAT", UNIT_RAW, 0, decU16 },
  [0x1011] = { "Vbat", UNIT_VOLTS, 2, decU16 },    [0x1012] = { "Curr", UNIT_AMPS, 2, decU16 },
  [0x1013] = { "Capa", UNIT_MAH, 0, decU16 },      [0x1014] = { "Bat%", UNIT_PERCENT, 0, decU8 },
  [0x1020] = { "Cel#", UNIT_RAW, 0, decU8 },       [0x1021] = { "Vcel", UNIT_VOLTS, 2, decCellV },
  [0x102F] = { "Cels", UNIT_VOLTS, 2, decCells },  [0x1030] = { "Ctrl", UNIT_RAW, 0, decControl },
  [0x1031] = { "CPtc", UNIT_DEGREE, 1, decS16 },   [0x1032] = { "CRol", UNIT_DEGREE, 1, decS16 },
  [0x1033] = { "CYaw", UNIT_DEGREE, 1, decS16 },   [0x1034] = { "CCol", UNIT_DEGREE, 1, decS16 },
  [0x1035] = { "Thr", UNIT_PERCENT, 0, decS8 },
  [0x1041] = { "EscV", UNIT_VOLTS, 2, decU16 },    [0x1042] = { "EscI", UNIT_AMPS, 2, decU16 },
  [0x1043] = { "EscC", UNIT_MAH, 0, decU16 },      [0x1044] = { "EscR", UNIT_RPMS, 0, decU24 },
  [0x1045] = { "EscP", UNIT_PERCENT, 1, decU16 },  [0x1046] = { "Esc%", UNIT_PERCENT, 1, decU16 },
  [0x1047] = { "EscT", UNIT_CELSIUS, 0, decU8 },   [0x1048] = { "BecT", UNIT_CELSIUS, 0, decU8 },
  [0x1049] = { "BecV", UNIT_VOLTS, 2, decU16 },    [0x104A] = { "BecI", UNIT_AMPS, 2, decU16 },
  [0x104E] = { "EscF", UNIT_RAW, 0, decU32 },      [0x104F] = { "Esc#", UNIT_RAW, 0, decU8 },
  [0x1051] = { "Es2V", UNIT_VOLTS, 2, decU16 },    [0x1052] = { "Es2I", UNIT_AMPS, 2, decU16 },
  [0x1053] = { "Es2C", UNIT_MAH, 0, decU16 },      [0x1054] = { "Es2R", UNIT_RPMS, 0, decU24 },
  [0x1057] = { "Es2T", UNIT_CELSIUS, 0, decU8 },   [0x105F] = { "Es2#", UNIT_RAW, 0, decU8 },
  [0x1080] = { "Vesc", UNIT_VOLTS, 2, decU16 },    [0x1081] = { "Vbec", UNIT_VOLTS, 2, decU16 },
  [0x1082] = { "Vbus", UNIT_VOLTS, 2, decU16 },    [0x1083] = { "Vmcu", UNIT_VOLTS, 2, decU16 },
  [0x1090] = { "Iesc", UNIT_AMPS, 2, decU16 },     [0x1091] = { "Ibec", UNIT_AMPS, 2, decU16 },
  [0x1092] = { "Ibus", UNIT_AMPS, 2, decU16 },     [0x1093] = { "Imcu", UNIT_AMPS, 2, decU16 },
  [0x10A0] = { "Tesc", UNIT_CELSIUS, 0, decU8 },   [0x10A1] = { "Tbec", UNIT_CELSIUS, 0, decU8 },
  [0x10A3] = { "Tmcu", UNIT_CELSIUS, 0, decU8 },
  [0x10B1] = { "Hdg", UNIT_DEGREE, 1, decS16 },    [0x10B2] = { "Alt", UNIT_METERS, 2, decS24 },
  [0x10B3] = { "Var", UNIT_METERS_PER_SECOND, 2, decS16 },
  [0x10C0] = { "Hspd", UNIT_RPMS, 0, decU16 },     [0x10C1] = { "Tspd", UNIT_RPMS, 0, decU16 },
  [0x1100] = { "Attd", UNIT_DEGREE, 1,
               decTriple({ 0x1101, 0x1102, 0x1103 }, { "Ptch", "Roll", "Yaw" }, UNIT_DEGREE, 1) },
  [0x1101] = { "Ptch", UNIT_DEGREE, 0, decS16 },   [0x1102] = { "Roll", UNIT_DEGREE, 0, decS16 },
  [0x1103] = { "Yaw", UNIT_DEGREE, 0, decS16 },
  [0x1110] = { "Accl", UNIT_G, 2,
               decTriple({ 0x1111, 0x1112, 0x1113 }, { "AccX", "AccY", "AccZ" }, UNIT_G, 2) },
  [0x1111] = { "AccX", UNIT_G, 1, decS16 },        [0x1112] = { "AccY", UNIT_G, 1, decS16 },
  [0x1113] = { "AccZ", UNIT_G, 1, decS16 },
  [0x1121] = { "Sats", UNIT_RAW, 0, decU8 },       [0x1122] = { "PDOP", UNIT_RAW, 0, decU8 },
  [0x1123] = { "HDOP", UNIT_RAW, 0, decU8 },       [0x1124] = { "VDOP", UNIT_RAW, 0, decU8 },
  [0x1125] = { "GPS", UNIT_RAW, 0, decLatLong },   [0x1126] = { "GAlt", UNIT_METERS, 1, decS16 },
  [0x1127] = { "GCrs", UNIT_DEGREE, 1, decS16 },
  [0x1128] = { "GSpd", UNIT_METERS_PER_SECOND, 2, decU16 },
  [0x1129] = { "GDis", UNIT_METERS, 1, decU16 },   [0x112A] = { "GDir", UNIT_METERS, 1, decU16 },
  [0x1141] = { "CPU%", UNIT_PERCENT, 0, decU8 },   [0x1142] = { "SYS%", UNIT_PERCENT, 0, decU8 },
  [0x1143] = { "RT%", UNIT_PERCENT, 0, decU8 },
  [0x1200] = { "MDL#", UNIT_RAW, 0, decU8 },       [0x1201] = { "Mode", UNIT_RAW, 0, decU16 },
  [0x1202] = { "ARM", UNIT_RAW, 0, decU8 },        [0x1203] = { "ARMD", UNIT_RAW, 0, decU32 },
  [0x1204] = { "Resc", UNIT_RAW, 0, decU8 },       [0x1205] = { "Gov", UNIT_RAW, 0, decU8 },
  [0x1211] = { "PID#", UNIT_RAW, 0, decU8 },       [0x1212] = { "RTE#", UNIT_RAW, 0, decU8 },
  [0x1214] = { "BAT#", UNIT_RAW, 0, decU8 },       [0x1213] = { "LED#", UNIT_RAW, 0, decU8 },
  [0x1220] = { "ADJ", UNIT_RAW, 0, decAdjFunc },
  [0xDB00] = { "DBG0", UNIT_RAW, 0, decS32 },      [0xDB01] = { "DBG1", UNIT_RAW, 0, decS32 },
  [0xDB02] = { "DBG2", UNIT_RAW, 0, decS32 },      [0xDB03] = { "DBG3", UNIT_RAW, 0, decS32 },
  [0xDB04] = { "DBG4", UNIT_RAW, 0, decS32 },      [0xDB05] = { "DBG5", UNIT_RAW, 0, decS32 },
  [0xDB06] = { "DBG6", UNIT_RAW, 0, decS32 },      [0xDB07] = { "DBG7", UNIT_RAW, 0, decS32 },
}

local CRSF_CUSTOM_TELEM, CRSF_MSP_WRITE, CRSF_MSP_RESP = 0x88, 0x7C, 0x7B

local CRSF_ADDR_FC, CRSF_ADDR_RADIO = 0xC8, 0xEA

local MSP_BATTERY_CONFIG, MSP_SET_BATTERY_PROFILE = 32, 176

local MSP_API_VERSION = 1

-- Byte XOR in plain arithmetic (EdgeTX Lua is 5.2-based: no ~ operator).
local function xor8(a, b)
  local r, bit = 0, 1
  for _ = 1, 8 do
    if a % 2 ~= b % 2 then r = r + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end

-- One 0x88 frame: { dest, origin, frame id, sid hi, sid lo, value..., ... }
-- (rf2tlm.lua crossfirePop). Frame-id gaps count as skipped frames.
local function decodeCustomFrame(rt, data)
  local fid = data[3]
  if rt.frameId and (fid - rt.frameId) % 256 > 1 then rt.skip = rt.skip + 1 end
  rt.frameId, rt.count = fid, rt.count + 1
  local p = 4
  while p < #data do
    local sid; sid, p = decU16(data, p)
    local s = RF_SENSORS[sid]
    if not s then break end
    local val; val, p = s[4](data, p)
    if val then setTelemetryValue(sid, 0, 0, val, s[2], s[3], s[1]) end
  end
  setTelemetryValue(0xEE01, 0, 0, rt.count, UNIT_RAW, 0, "*Cnt")
  setTelemetryValue(0xEE02, 0, 0, rt.skip, UNIT_RAW, 0, "*Skp")
end

-- MSP v1 reply reassembly (common.lua mspReceivedReply): status byte =
-- error 0x80 | version 0x60 | start 0x10 | sequence 0x0F, then size and
-- command on the start frame, then data, split over as many frames as
-- needed. Calls rt.onReply(cmd, bytes, isError) when complete.
local function decodeMspFrame(rt, data)
  local status = data[3]
  if not status then return end
  local start = math.floor(status / 16) % 2 == 1
  local version = math.floor(status / 32) % 4
  local p = 4
  if start then
    if version ~= 1 then rt.rx = nil; return end -- only MSP v1 is requested
    rt.rx = { size = data[p], cmd = data[p + 1], buf = {}, err = status >= 128, seq = status % 16 }
    p = p + 2
  elseif not rt.rx or (rt.rx.seq + 1) % 16 ~= status % 16 then
    rt.rx = nil
    return
  else
    rt.rx.seq = status % 16
  end
  local rx = rt.rx
  while p <= #data and #rx.buf < rx.size do
    rx.buf[#rx.buf + 1] = data[p]
    p = p + 1
  end
  if #rx.buf >= rx.size then
    rt.rx = nil
    if rt.onReply then rt.onReply(rx.cmd, rx.buf, rx.err) end
  end
end

-- Queue one MSP v1 request that fits a single frame (<= 4 data bytes).
-- False when the CRSF output buffer is busy or no module is CRSF.
local mspSeq = 0

local function mspRequest(cmd, payload)
  if not crossfireTelemetryPush or crossfireTelemetryPush() ~= true then return false end
  local frame = { CRSF_ADDR_FC, CRSF_ADDR_RADIO, 0x30 + mspSeq, #payload, cmd }
  local crc = xor8(#payload, cmd)
  for i = 1, #payload do
    frame[#frame + 1] = payload[i]
    crc = xor8(crc, payload[i])
  end
  frame[#frame + 1] = crc
  mspSeq = (mspSeq + 1) % 16
  return crossfireTelemetryPush(CRSF_MSP_WRITE, frame) == true
end

-- Drain the shared queue (at most 20 frames per call to stay clear of the
-- CPU limit): custom telemetry -> sensors, MSP replies -> rt.onReply.
local function rfTelemetryPump(wgt)
  if CONFIG.simulate or not CONFIG.telemetry.decode or not crossfireTelemetryPop then return end
  if wgt.hosted then return end -- a hosted tool (RF2 / ELRS) owns the queue now
  local rt = wgt.rt
  for _ = 1, 20 do
    local cmd, data = crossfireTelemetryPop()
    if not cmd then return end
    if cmd == CRSF_CUSTOM_TELEM and data then
      decodeCustomFrame(rt, data)
    elseif cmd == CRSF_MSP_RESP and data and data[1] == CRSF_ADDR_RADIO and data[2] == CRSF_ADDR_FC then
      decodeMspFrame(rt, data)
    end
  end
end

-- MSP_BATTERY_CONFIG (32) reply, 4.6 / API 12.09+ layout (msp.c, same as
-- MSP/mspBatteryConfig.lua): U16 active capacity, U8 cells, U8 voltage src,
-- U8 current src, 4 x U16 cell voltages, U8 lvc %, U8 consumption warn %,
-- then 6 x U16 profile capacities - all little-endian, capacities at 16..27.
local function parseBatteryConfig(buf)
  if #buf < 27 then return nil end
  local caps = {}
  for i = 1, 6 do caps[i] = buf[16 + (i - 1) * 2] + buf[17 + (i - 1) * 2] * 256 end
  return caps
end

-- FC settings pages, read only (LVGL VIEW "fcview", opened by the "Page"
-- option switch without full screen, or from the menu). Reply layouts and
-- display scales are rotorflight-lua-scripts' MSP/mspPidTuning.lua,
-- mspRcTuning.lua + MSP/RATES/*.lua and mspGovernorProfile.lua: a value
-- shows as raw / scale, whole numbers when scale <= 1.
local FC = {}

function FC.u16(buf, i) return (buf[i] or 0) + (buf[i + 1] or 0) * 256 end

function FC.scaled(raw, scale)
  if raw == nil then return "--" end
  if not scale then return tostring(raw) end
  local v = raw / scale
  if scale <= 1 then return tostring(math.floor(v)) end
  v = math.floor(v * 100 + 0.5) / 100
  if isWhole(v) then return string.format("%d", math.floor(v)) end
  return (string.gsub(string.format("%.2f", v), "0$", ""))
end

-- rates type -> column headings and scales (rcRates, rates, rcExpo)
FC.rateTypes = {
  [0] = { "NONE",    { "RC Rate", "Rate", "RC Expo" },   { nil, nil, nil },   { nil, nil, nil } },
  [1] = { "BETAFL",  { "RC Rate", "Rate", "RC Expo" },   { 100, 100, 100 },   { 100, 100, 100 } },
  [2] = { "RACEFL",  { "Rate", "Acro+", "Expo" },        { 0.1, nil, nil },   { 4, nil, nil } },
  [3] = { "KISS",    { "RC Rate", "Rate", "RC Curve" },  { 100, 100, 100 },   { 100, 100, 100 } },
  [4] = { "ACTUAL",  { "Center Sens", "Max Rate", "Expo" }, { 0.1, 0.1, 100 }, { 4, 4, 100 } },
  [5] = { "QUICK",   { "RC Rate", "Max Rate", "Expo" },  { 100, 0.1, 100 },   { 100, 0.208, 100 } },
  [6] = { "ROTORFL", { "Rate", "Shape", "Expo" },        { 0.2, 1, 1 },       { 8, 1, 1 } },
}

FC.pages = {
  { cmd = 112, title = "PID gains", -- MSP_PID_TUNING
    parse = function(b)
      local cols = { "P", "I", "D", "F", "B", "O" }
      local function axis(base, bOff, oOff)
        return { FC.u16(b, base), FC.u16(b, base + 2), FC.u16(b, base + 4), FC.u16(b, base + 6),
                 FC.u16(b, bOff), oOff and FC.u16(b, oOff) or "-" }
      end
      return { kind = "table", cols = cols, sig = "pid",
        rows = { { "Roll", axis(1, 25, 31) }, { "Pitch", axis(9, 27, 33) }, { "Yaw", axis(17, 29, nil) } } }
    end },
  { cmd = 111, title = "Rates", -- MSP_RC_TUNING
    parse = function(b)
      local rt = FC.rateTypes[b[1] or 0] or FC.rateTypes[0]
      local rows, names = {}, { "Roll", "Pitch", "Yaw", "Collective" }
      for a = 0, 3 do
        local base, sc = 2 + a * 6, (a == 3) and rt[4] or rt[3]
        rows[a + 1] = { names[a + 1], { FC.scaled(b[base], sc[1]), FC.scaled(b[base + 2], sc[2]), FC.scaled(b[base + 1], sc[3]) } }
      end
      return { kind = "table", cols = rt[2], rows = rows, note = rt[1], sig = "rates" .. rt[1] }
    end },
  { cmd = 148, title = "Governor profile", -- MSP_GOVERNOR_PROFILE
    parse = function(b)
      local items = {
        { "Headspeed", FC.u16(b, 1) .. " rpm" }, { "Gain", b[3] }, { "P gain", b[4] }, { "I gain", b[5] },
        { "D gain", b[6] }, { "F gain", b[7] }, { "TTA gain", b[8] }, { "TTA limit", (b[9] or "--") .. "%" },
        { "Yaw weight", b[10] }, { "Cyclic weight", b[11] }, { "Coll. weight", b[12] },
        { "Max throttle", (b[13] or "--") .. "%" },
      }
      if #b >= 14 then items[#items + 1] = { "Min throttle", b[14] .. "%" } end
      if #b >= 15 then items[#items + 1] = { "Fallback drop", b[15] .. "%" } end
      return { kind = "list", items = items, sig = "gov" .. #items }
    end },
}

-- RF2's simulator replies, so CONFIG.simulate shows the pages too
FC.startup = { MSP_API_VERSION, 12, 10, MSP_BATTERY_CONFIG, 148, 70 }

FC.sim = {
  [112] = { 70, 0, 225, 0, 90, 0, 120, 0, 100, 0, 200, 0, 70, 0, 120, 0, 100, 0, 125, 0, 83, 0, 0, 0, 0, 0, 0, 0, 0, 0, 25, 0, 25, 0 },
  [111] = { 6, 50, 40, 12, 0, 0, 0, 50, 40, 12, 0, 0, 0, 80, 50, 12, 0, 0, 0, 100, 0, 12, 0, 0, 0 },
  [148] = { 0x34, 0x08, 40, 10, 20, 0, 10, 0, 20, 20, 10, 10, 100, 10, 10 },
}

-- Per connect: ask for the profile capacities (after the connect quiet
-- time, retried every 1.5s, at most 6 times). Fills wgt.battCaps[1..6].
-- Also MSP_API_VERSION (1) first, kept in wgt.fcApi so the hosted RF2 tool
-- can skip its own "Waiting for API version" round trip (see TOOLS HOST).
local function rfMspUpdate(wgt, connected)
  local cfg, rt = CONFIG.telemetry, wgt.rt
  if CONFIG.simulate or not cfg.decode or not connected or wgt.hosted then return end
  local now = getTime()
  if wgt.infoView then -- an FC settings page is open: its data first
    local cmd = FC.pages[wgt.infoView].cmd
    wgt.fc = wgt.fc or {}
    if not wgt.fc[cmd] and now - (rt.fcAskedAt or -1000) >= 100 then
      if mspRequest(cmd, {}) then rt.fcAskedAt = now end
    end
    return
  end
  if now < (wgt.alarm.quietUntil or 0) or now - (rt.capAskedAt or -1000) < 150 then return end
  -- after a connect, one request at a time (each retried every 1.5 s, at
  -- most 6 times): API version, battery capacities, governor target
  -- headspeed (MSP_GOVERNOR_PROFILE, again when PID# changes), blackbox
  -- space (MSP_DATAFLASH_SUMMARY)
  local have = { [MSP_API_VERSION] = wgt.fcApi, [MSP_BATTERY_CONFIG] = wgt.battCaps or not cfg.readCapacities,
                 [148] = wgt.govTarget, [70] = wgt.blackbox, [12] = wgt.fcSetName ~= nil,
                 [10] = wgt.fcName or wgt.fcSetName == false }
  for _, cmd in ipairs(FC.startup) do
    if not have[cmd] and (rt.tries[cmd] or 0) < 6 then
      if mspRequest(cmd, {}) then rt.capAskedAt, rt.tries[cmd] = now, (rt.tries[cmd] or 0) + 1 end
      return
    end
  end
end

-- Menu > Erase blackbox (tapped twice): MSP_DATAFLASH_ERASE (72), then
-- MSP_DATAFLASH_SUMMARY (70) every 2 s until the flash reports ready, as
-- RF2's PAGES/status.lua does. Progress and result in the tool banner.
function FC.eraseUpdate(wgt, connected)
  local e = wgt.erase
  if not e then return end
  local now = getTime()
  if not connected then
    wgt.erase, wgt.toolMsg = nil, { text = "Blackbox erase: link lost", at = now }
    return
  end
  if CONFIG.simulate then
    if now - e.since > 50 then wgt.blackbox.used, e.phase = 0, "done" end
  elseif wgt.hosted then -- RF2 owns the queue for now
  elseif e.phase == "send" then
    if now - (e.askedAt or -1000) >= 150 and e.tries < 6 and mspRequest(72, {}) then
      e.askedAt, e.tries = now, e.tries + 1
    end
  elseif now - e.askedAt >= 200 and mspRequest(70, {}) then
    e.askedAt = now
  end
  if e.phase == "done" then
    wgt.erase = nil
    wgt.toolMsg = { text = "Blackbox erased", at = now, color = COLOR.green }
    playEffect(wgt, "saved")
    playPattern(CONFIG.alarm.hapticSaved)
  elseif now - e.since > 6000 then
    wgt.erase, wgt.toolMsg = nil, { text = "Blackbox erase: no answer from the FC", at = now }
  else
    wgt.toolMsg = { text = "Erasing blackbox...", at = now, color = COLOR.accent }
  end
end

-- Model name from the FC, as rf2bg did (RF2 background_init.lua): with
-- the FC's "set model name" flag (Model page in RF2, MSP_PILOT_CONFIG),
-- the model takes the craft name (MSP_NAME) while connected; the radio's
-- own name is kept in settings.txt (prevName) and put back when the link
-- drops, or at the next start if the radio was switched off connected.
-- Runs after HIST.record in tick, so a flight is filed under the FC name.
function FC.nameUpdate(wgt, connected)
  if CONFIG.simulate or not (model and model.getInfo and model.setInfo) then return end
  local def = SET.byKey.prevName
  if connected then
    local name = wgt.fcName
    if wgt.nameDone or not wgt.fcSetName or not name or name == "" then return end
    wgt.nameDone = true
    name = string.sub(name, 1, 15) -- EdgeTX model names are 15 characters
    local info = model.getInfo()
    if info.name == name then return end
    if (USER.prevName or "") == "" then SET.set(def, info.name) end
    info.name = name
    model.setInfo(info)
  else
    wgt.nameDone = nil
    local prev = USER.prevName
    if prev and prev ~= "" then
      local info = model.getInfo()
      info.name = prev
      model.setInfo(info)
      SET.set(def, "")
    end
  end
end

local function newRfTelemetryState(wgt)
  local rt = { count = 0, skip = 0, tries = {} }
  rt.onReply = function(cmd, buf, isError)
    if cmd == MSP_BATTERY_CONFIG and not isError then wgt.battCaps = parseBatteryConfig(buf) end
    if (cmd == 112 or cmd == 111 or cmd == 148) and not isError then
      wgt.fc = wgt.fc or {}
      wgt.fc[cmd] = buf
    end
    if cmd == 148 and not isError and #buf >= 2 then wgt.govTarget = FC.u16(buf, 1) end
    if cmd == 70 and not isError and #buf >= 13 then -- flags, sectors, total, used (U32 LE)
      local function u32(i) return buf[i] + buf[i + 1] * 256 + buf[i + 2] * 65536 + buf[i + 3] * 16777216 end
      wgt.blackbox = { ready = buf[1] % 2 == 1, supported = math.floor(buf[1] / 2) % 2 == 1, total = u32(6),
        used = u32(10) }
      if wgt.erase and wgt.erase.phase == "wait" and wgt.blackbox.ready then wgt.erase.phase = "done" end
    end
    if cmd == 12 and not isError then -- MSP_PILOT_CONFIG: model_flags U32 at 11, bit 0 = MODEL_SET_NAME (API 12.09+)
      wgt.fcSetName = #buf >= 14 and buf[11] % 2 == 1
    end
    if cmd == 10 and not isError then -- MSP_NAME: the craft name, up to a 0
      local s = ""
      for i = 1, #buf do
        if buf[i] == 0 then break end
        s = s .. string.char(buf[i])
      end
      wgt.fcName = s
    end
    if cmd == 72 and not isError and wgt.erase and wgt.erase.phase == "send" then
      wgt.erase.phase, wgt.erase.askedAt = "wait", getTime()
    end
    if cmd == MSP_API_VERSION and not isError and #buf >= 3 then
      wgt.fcApi = buf[2] + buf[3] / 100 + 0.00001 -- as RF2's MSP/mspApiVersion.lua
    end
  end
  return rt
end

-- ============================== BATTERY PROFILE ===========================
-- Right after a connect (disarmed), a picker for the FC's 6 battery
-- profiles. The choice goes out as MSP_SET_BATTERY_PROFILE (176) through
-- mspRequest above; success is confirmed by the BAT# sensor changing.
-- The FC keeps the profile in RAM only (no EEPROM write: sensors/battery.c
-- changeBatteryProfile), i.e. until its next power-up - hence asking on
-- every connect.

-- Queue the MSP write for profile 1..6. False when the CRSF output buffer
-- is busy or no module is CRSF (the caller retries).
local function mspSetBatteryProfile(wgt, profile)
  if CONFIG.simulate then -- no FC: simulateTelemetry follows after 0.5s
    wgt.simBattPending = { value = profile, at = getTime() + 50 }
    return true
  end
  return mspRequest(MSP_SET_BATTERY_PROFILE, { profile - 1 })
end

-- wgt.bp: nil = no picker. phase: "wait" (for BAT# / no arm warning),
-- "pick", "send" (until BAT# == target), "done" (result shown 1.5s).
local function bpStart(wgt)
  wgt.bp = CONFIG.batteryProfile.enabled and { phase = "wait", since = getTime() } or nil
end

local function bpApply(wgt, t)
  local bp = wgt.bp
  if t.battProfile == bp.sel then
    bp.phase, bp.doneAt, bp.result = "done", getTime(), "same"
  else
    bp.phase, bp.target, bp.tries, bp.sentAt = "send", bp.sel, 0, nil
  end
end

-- "BattSel" option: a multi-position source (the TX16S 6-pos buttons, a
-- pot, a slider) picks the profile directly - its -1024..1024 range is cut
-- into 6 equal bands (1..6). Nil when the option is unset.
local function bpSourceProfile(wgt)
  local src = wgt.options and wgt.options.BattSel
  if not src or src == 0 then return nil end
  local ok, v = pcall(getValue, src)
  if not ok or type(v) ~= "number" then return nil end
  return math.max(1, math.min(6, math.floor((v + 1024) / 2048 * 6) + 1))
end

-- "BattSW" option (TX16S MK3): the six buttons SW1..SW6 are separate
-- 2-position switches (radio.yml switchConfig), not one 6-pos source - so
-- BattSel on one of them could only ever read profile 1 (off) or 6 (on),
-- which is what the radio did. With BattSW on, the button that is ON picks
-- the profile (SWn = profile n); if several are on, the one switched on
-- most recently wins. Nil when the option is off or no button is on.
local FUNC_SWITCHES = { "SW1", "SW2", "SW3", "SW4", "SW5", "SW6" }

local function bpFuncSwitchProfile(wgt)
  if not (wgt.options and wgt.options.BattSW == 1) then return nil end
  wgt.fsPrev = wgt.fsPrev or {}
  local first
  for i = 1, #FUNC_SWITCHES do
    local ok, v = pcall(getValue, FUNC_SWITCHES[i])
    local on = ok and type(v) == "number" and v > 0
    if on and not wgt.fsPrev[i] then wgt.fsLast = i end -- just switched on
    wgt.fsPrev[i] = on
    if on and not first then first = i end
  end
  if wgt.fsLast and wgt.fsPrev[wgt.fsLast] then return wgt.fsLast end
  return first
end

-- Inputs: step (switch press / rotary), choose (tap / Enter), dismiss.
local function bpStep(wgt, dir)
  local bp = wgt.bp
  if not bp or bp.phase ~= "pick" then return false end
  bp.sel = (bp.sel - 1 + dir) % 6 + 1
  bp.lastInput, bp.stepped = getTime(), true
  return true
end

local function bpChoose(wgt, t, profile)
  local bp = wgt.bp
  if not bp or bp.phase ~= "pick" then return false end
  bp.sel = profile or bp.sel
  bpApply(wgt, t)
  return true
end

local function bpUpdate(wgt, t, connected)
  local bp = wgt.bp
  if not bp then return end
  local cfg, now = CONFIG.batteryProfile, getTime()
  local armed = t.armFlags ~= nil and math.floor(t.armFlags) % 2 == 1
  -- Never talk to the FC while armed; a lost link ends the picker too.
  if not connected or armed then wgt.bp = nil; return end

  if bp.phase == "wait" then
    if wgt.armWarningActive or now < (wgt.alarm.quietUntil or 0) then
      bp.since = now -- arm switch still on / EdgeTX link voice: ask after
    elseif t.battProfile then
      bp.phase, bp.sel, bp.since, bp.lastInput = "pick", t.battProfile, now, nil
      alert(wgt, "info", "battprofile_select")
    elseif now - bp.since > 500 then
      wgt.bp = nil -- no BAT# sensor: firmware/telemetry without profiles
    end
  elseif bp.phase == "pick" then
    -- Selector source: its position is the choice. Read on entry too, so a
    -- 6-pos button set before power-up is applied applyIdleSec after the
    -- link comes up without touching anything (same profile -> "same").
    local sp = bpFuncSwitchProfile(wgt) or bpSourceProfile(wgt)
    if sp and sp ~= bp.srcLast then
      bp.srcLast, bp.sel, bp.lastInput, bp.stepped = sp, sp, now, true
    end
    if bp.stepped and now - bp.lastInput >= cfg.applyIdleSec * 100 then
      bpApply(wgt, t)
    elseif cfg.timeoutSec > 0 and now - (bp.lastInput or bp.since) >= cfg.timeoutSec * 100 then
      wgt.bp = nil -- no answer: keep the current profile
    end
  elseif bp.phase == "send" then
    if t.battProfile == bp.target then
      bp.phase, bp.doneAt, bp.result = "done", now, "ok" -- voice: runAlarms' BAT# onChange
    elseif not bp.sentAt or now - bp.sentAt >= cfg.retrySec * 100 then
      if bp.tries >= cfg.maxTries then
        bp.phase, bp.doneAt, bp.result = "done", now, "fail"
        alert(wgt, "caution", "battprofile_failed")
      elseif mspSetBatteryProfile(wgt, bp.target) then
        bp.tries, bp.sentAt = bp.tries + 1, now
      end
    end
  elseif bp.phase == "done" and now - bp.doneAt >= 150 then
    wgt.bp = nil
  end
end

-- Per-tick state update shared by refresh() and background(): read the
-- sensors, handle connect/disconnect, run every tracker and the alarms.
-- Returns the telemetry table and the link state for drawing.
local function tick(wgt)
  wgt.rt = wgt.rt or newRfTelemetryState(wgt)
  rfTelemetryPump(wgt) -- decode queued frames into sensors before reading them
  local t = readTelemetry(wgt)

  -- Reconnect detection: if the link just came back after being down,
  -- wipe accumulated state before anything else uses it this frame.
  local connected = isTelemetryConnected(t)
  if wgt.wasConnected and not connected then
    -- Just disconnected after a real connection (not the initial
    -- power-up state) - that's the one moment the flight log should
    -- show fresh, and the flight goes into the history.
    wgt.showFlightLog = true
    HIST.record(wgt)
  end
  if connected and not wgt.wasConnected then
    resetTelemetryState(wgt)
    t = readTelemetry(wgt) -- re-read with the freshly cleared sensor cache
    bpStart(wgt)
    wgt.battCaps, wgt.fcApi, wgt.rt.tries, wgt.rt.capAskedAt = nil, nil, {}, nil
    wgt.govTarget, wgt.blackbox, wgt.flightPack, wgt.lastPid, wgt.erase = nil, nil, nil, nil, nil
    wgt.fcSetName, wgt.fcName = nil, nil
  end
  wgt.wasConnected = connected

  if connected then
    if wgt.lastPid ~= nil and t.pidProfile ~= wgt.lastPid then -- the target is per PID profile
      wgt.govTarget = nil
      if wgt.rt.tries then wgt.rt.tries[148] = nil end
    end
    wgt.lastPid = t.pidProfile
    if CONFIG.simulate then
      wgt.govTarget = wgt.govTarget or 2100
      wgt.battCaps = wgt.battCaps or { 5000, 5000, 4500, 4500, 3800, 3800 }
      wgt.blackbox = wgt.blackbox or { supported = true, total = 4194304, used = 1048576 }
    end
  end

  local running = updateFlightTimer(wgt, t)
  if running and t.battProfile then wgt.flightPack = t.battProfile end
  updateMaxCurrent(wgt, t, running)
  updateMinVoltage(wgt, t, running)
  updateMinBecVoltage(wgt, t, running)
  updateMaxEscTemp(wgt, t, running)
  updateArmWarning(wgt, t)
  updateMaxCapacity(wgt, t, running)
  updateMaxHeadspeed(wgt, t, running)
  updateMinCharge(wgt, t, running)
  updateFlightSamples(wgt, t, running)
  runAlarms(wgt, t, running, connected)
  fullChargeCheck(wgt, t, connected, running, t.armFlags ~= nil and math.floor(t.armFlags) % 2 == 1)
  wgt.wasRunning = running and connected
  bpUpdate(wgt, t, connected)
  rfMspUpdate(wgt, connected)
  FC.eraseUpdate(wgt, connected)
  FC.nameUpdate(wgt, connected)

  -- Track when this disconnect started, so the flight log can
  -- auto-dismiss after a timeout - this is what makes the dismiss
  -- behavior work even in a zone that never receives touch events.
  if not connected then
    if not wgt.disconnectTime then
      wgt.disconnectTime = getTime()
    end
    local disconnectedSec = (getTime() - wgt.disconnectTime) / 100
    if CONFIG.flightLogTimeoutSec > 0 and disconnectedSec > CONFIG.flightLogTimeoutSec then
      wgt.showFlightLog = false
    end
  else
    wgt.disconnectTime = nil
  end

  -- "Close" option (e.g. the SH momentary button): a press - rising edge,
  -- so a switch already held at disconnect doesn't count - closes the
  -- flight log, or steps the battery-profile picker to the next profile.
  -- Polled here, so it works without full-screen mode, which is the only
  -- mode where touch/key events reach a widget.
  local closeOn = sourceActive(wgt.options and wgt.options.Close)
  if closeOn and not wgt.closeWasOn then
    if wgt.fullAlert then -- the battery-not-full window first
      wgt.fullAlert = nil
    elseif not connected then
      wgt.showFlightLog = false
    else
      bpStep(wgt, 1)
    end
  end
  wgt.closeWasOn = closeOn

  -- "BattPrev" option: same, one profile back. Keys and the side wheel
  -- can't be sources, but trim buttons can drive a logical switch (e.g.
  -- T5 down -> L10 -> BattPrev, T5 up -> L11 -> Close).
  local prevOn = sourceActive(wgt.options and wgt.options.BattPrev)
  if prevOn and not wgt.prevWasOn and connected then bpStep(wgt, -1) end
  wgt.prevWasOn = prevOn

  -- "Page" option: FC settings pages (read only), each press the next one,
  -- then back to the dashboard. Works without full screen. Closed when
  -- arming or disconnecting; reopening reads the values again.
  local armedNow = t.armFlags ~= nil and math.floor(t.armFlags) % 2 == 1
  local pageOn = sourceActive(wgt.options and wgt.options.Page)
  if pageOn and not wgt.pageWasOn and connected and not armedNow then
    local nextView = (wgt.infoView or 0) + 1
    wgt.infoView = (nextView <= #FC.pages) and nextView or nil
    if wgt.infoView then
      wgt.fc = wgt.fc or {}
      wgt.fc[FC.pages[wgt.infoView].cmd] = CONFIG.simulate and FC.sim[FC.pages[wgt.infoView].cmd] or nil
    end
  end
  wgt.pageWasOn = pageOn
  if armedNow or not connected then wgt.infoView = nil end
  -- The page follows the profile switches: when PID# / RTE# change while
  -- it is open, the page is read again (MSP replies are for the FC's
  -- current profile).
  if wgt.infoView then
    local prof = tostring(t.pidProfile) .. "/" .. tostring(t.bank)
    if wgt.fcProf and wgt.fcProf ~= prof then
      local cmd = FC.pages[wgt.infoView].cmd
      wgt.fc = { [cmd] = CONFIG.simulate and FC.sim[cmd] or nil }
    end
    wgt.fcProf = prof
  else
    wgt.fcProf = nil
  end
  return t, connected
end

-- Called by EdgeTX while the widget is NOT on screen: keep the trackers,
-- flight samples and alarms running.
local function background(wgt)
  tick(wgt)
end

-- The widget-style RF2 screens (rf2ui.lua), loaded the first time RF2 opens.
function R.rf2Skins()
  if not R.rf2SkinTable then R.rf2SkinTable = assert(loadScript(R.DIR .. "rf2ui.lua"))(R, R.LV) end
  return R.rf2SkinTable
end

-- RF2's own lvgl UI (ui_lvgl_runner), started as the RfTool widget does;
-- it builds its screens in this widget's lvgl tree.
local function startRf2Lvgl(apiVersion)
  local dir = CONFIG.tools.rf2Dir
  local compiled = loadScript(dir .. "COMPILE/scripts_compiled.lua")
  if not compiled then return nil, "Rotorflight Lua not found in " .. dir end
  if chdir then chdir(dir) end
  if not compiled() then
    return assert(loadScript(dir .. "COMPILE/compile.lua"))(), nil, true
  end
  assert(loadScript(dir .. "rf2.lua"))()
  rf2.radio = rf2.executeScript("radios")
  local execute = rf2.executeScript
  rf2.executeScript = function(name, ...)
    if name == "ui_init" and apiVersion then -- already read by this widget: skip RF2's request
      return { t = "", f = function() rf2.apiVersion = apiVersion; return true end }
    end
    local skins = CONFIG.tools.rf2Skin and R.rf2Skins()
    local skin = skins and skins[name]
    if skin then return skin(...) end -- widget-style screens (rf2ui.lua)
    return execute(name, ...)
  end
  rf2.mspQueue = rf2.executeScript("MSP/mspQueue")
  rf2.mspHelper = rf2.executeScript("MSP/mspHelper")
  return rf2.executeScript("ui_lvgl_runner")
end

local function stopTool(wgt, message)
  wgt.hosted, wgt.menu = nil, nil
  rf2 = nil -- the RF2 scripts' only global
  collectgarbage()
  if message then wgt.toolMsg = { text = message, at = getTime() } end
  if CONFIG.simulate then -- same log as the alarms (see alert)
    pcall(function()
      local f = io.open("/LOGS/rotorhud_alarms.log", "a")
      if f then io.write(f, string.format("%.2f tool %s\n", getTime() / 100, message or "closed")); io.close(f) end
    end)
  end
end

local MENU_ITEMS = {
  { key = "rf2",  label = "Rotorflight settings" },
  { key = "batt", label = "Battery profile" },
  { key = "view", label = "View FC settings" },
  { key = "erase", label = "Erase blackbox" },
  { key = "history", label = "Flight history" },
  { key = "settings", label = "Settings" },
}

-- Whether a menu item can be used now, and why not.
local function menuItemState(wgt, t, connected, key)
  if key == "rf2" then
    return connected, "needs the model connected"
  elseif key == "settings" or key == "history" then
    return true, ""
  elseif key == "view" then
    return connected, "needs the model connected"
  elseif key == "erase" then
    if wgt.erase then return false, "erasing" end
    local bb = wgt.blackbox
    return connected and bb ~= nil and bb.supported and bb.total > 0, "needs blackbox info from the FC"
  end
  return connected and t.battProfile ~= nil, "needs BAT# from the FC"
end

local function openMenuItem(wgt, t, connected, key)
  local ok, why = menuItemState(wgt, t, connected, key)
  if not ok then wgt.toolMsg = { text = "Not available: " .. why, at = getTime() }; return end
  if key == "erase" then -- first tap arms it for 3 s (the menu shows the question), second erases
    local now = getTime()
    if wgt.menu and wgt.menu.eraseAt and now - wgt.menu.eraseAt <= 300 then
      wgt.menu, wgt.erase = nil, { phase = "send", since = now, tries = 0 }
    elseif wgt.menu then
      wgt.menu.eraseAt = now
    end
    return
  end
  wgt.menu = nil
  if key == "batt" then
    wgt.bp = { phase = "pick", sel = t.battProfile, since = getTime() }
    return
  end
  if key == "settings" then
    wgt.settings = { group = SET.groups[1] }
    return
  end
  if key == "history" then
    wgt.history, wgt.histCache = true, nil
    return
  end
  if key == "view" then
    wgt.infoView, wgt.fc = 1, {}
    if CONFIG.simulate then wgt.fc[FC.pages[1].cmd] = FC.sim[FC.pages[1].cmd] end
    return
  end
  local okStart, run, err, compiling = pcall(startRf2Lvgl, wgt.fcApi)
  if not okStart then
    stopTool(wgt, "Could not start: " .. tostring(run))
  elseif not run then
    stopTool(wgt, err)
  else
    wgt.hosted = { kind = key, run = run, compiling = compiling }
  end
end

-- ============================== REFRESH ===================================

local function refresh(wgt, event, touchState)
  -- Theme: Settings, else the radio-side "Theme" option (0/1/2)
  do
    local idx = USER.theme
    if idx == nil then idx = (wgt.options and wgt.options.Theme) or nil end
    if idx ~= nil then
      idx = math.floor(idx)
      if idx < 0 or idx > 2 then idx = 0 end
      COLOR = COLOR_THEMES[THEME_NAMES[idx + 1]] or COLOR_THEMES.color
    end
    R.COLOR = COLOR
  end

  local t0 = getTime()
  local t, connected
  if wgt.hosted and wgt.lastTickT and (wgt.tickSkip or 0) < 4 then
    -- a hosted tool needs the frame time: the trackers/alarms run every
    -- 5th frame (the custom sensors are paused anyway, see rfTelemetryPump)
    wgt.tickSkip = (wgt.tickSkip or 0) + 1
    t, connected = wgt.lastTickT, wgt.lastTickC
  else
    wgt.tickSkip = 0
    t, connected = tick(wgt)
    wgt.lastTickT, wgt.lastTickC = t, connected
  end
  local t1 = getTime()
  ensureModelImage(wgt)
  local armed = t.armFlags ~= nil and math.floor(t.armFlags) % 2 == 1
  return R.LV.refresh(wgt, t, connected, armed, event, touchState, t0, t1)
end

-- ============================== EXPORTS ===================================

R.COLOR = COLOR
R.battLandPct = battLandPct
R.HIST = HIST
R.create, R.update, R.refresh, R.background = create, update, refresh, background
R.ARMD_ARM_SWITCH_AT_POWERUP = ARMD_ARM_SWITCH_AT_POWERUP
R.CHART_DIVS = CHART_DIVS
R.CONFIG = CONFIG
R.FC = FC
R.MENU_ITEMS = MENU_ITEMS
R.SET = SET
R.SETTINGS = SETTINGS
R.TAB_LABEL_H = TAB_LABEL_H
R.TIME_STEPS = TIME_STEPS
R.USER = USER
R.bpChoose = bpChoose
R.bpStep = bpStep
R.caution = caution
R.chartAxis = chartAxis
R.critical = critical
R.decodeArmd = decodeArmd
R.fitFontMeasured = fitFontMeasured
R.flightSampleStats = flightSampleStats
R.fmt = fmt
R.fmtTime = fmtTime
R.fmtUnit = fmtUnit
R.getChargeColor = getChargeColor
R.getGovColor = getGovColor
R.getTxBatteryPct = getTxBatteryPct
R.isTelemetryConnected = isTelemetryConnected
R.isWhole = isWhole
R.menuItemState = menuItemState
R.openMenuItem = openMenuItem
R.playEffect = playEffect
R.playPattern = playPattern
R.stopTool = stopTool
R.textWidth = textWidth
R.tick = tick
R.toSentenceCase = toSentenceCase
R.voiceSetDir = voiceSetDir

return R
