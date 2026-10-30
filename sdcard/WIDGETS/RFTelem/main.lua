--[[
  Rotorflight Telemetry Dashboard Widget for EdgeTX (Color LCD)
  ----------------------------------------------------------------
  Dashboard-style layout inspired by the Rotorflight/RFSuite home screen:
  top status chips, big RC-volt/RPM/flight-timer readouts, a color-coded
  battery bar, a status/warning list, a throttle bar, and a model-name
  footer.

  INSTALL:
    Copy this file to:  /WIDGETS/RFTelem/main.lua   (on your radio's SD card)
    Then on the radio: go to a Widget screen -> long-press an empty zone ->
    "Add Widget" -> choose "RF Telem". For the full dashboard layout, use a
    large zone (ideally a full-screen "Layout: 1 zone" widget screen) -
    smaller zones fall back to a compact RPM + governor view.

  TARGET SCREEN:
    Sizing (padding, icon size, row proportions) is tuned for the
    RadioMaster TX16S MK3's 800x480 5" screen, used full-screen (roughly
    800x440 once the top status bar is subtracted). It will still scale
    to other zone sizes via percentages, but expect more/less breathing
    room on a meaningfully smaller or larger color screen.

  TARGET FIRMWARE:
    Developed and tuned against EdgeTX v2.12.0 "Queen Anne's Revenge"
    (edgetx-tx16smk3 build). The font-size measurements in FONT_SPECS,
    the getTime()/100 tick conversion, and the lcd.drawBitmap notes
    elsewhere in this file are all specific to how this exact
    firmware/hardware combination renders things - a different EdgeTX
    version or radio model may render fonts/bitmaps differently, in
    which case those constants would need re-measuring (see the
    diagnostic widget approach: draw sample text at each font flag and
    read lcd.sizeText(), if available, rather than guessing).

  TELEMETRY REQUIREMENTS:
    - Receiver/link must be CRSF (ExpressLRS or TBS Crossfire).
    - Discover telemetry sensors first: Telemetry page -> "Discover new sensors".
    - Sensor names below match the radio's Telemetry Sensors page:
        Governor State, Headspeed, Battery Voltage, Battery Cell Voltage,
        Battery Cell Count, Battery Current, ESC Temp, Battery Charge Level,
        Throttle Control, BEC Voltage, Rates Profile, Arming Disable Flags

  IF YOUR SENSOR NAMES OR VALUE RANGES DIFFER:
    Open the Telemetry screen on your radio, note the exact sensor names,
    and edit the candidate name lists in CONFIG.sensors below. If a value
    looks scaled wrong (e.g. throttle showing as -100..100 instead of
    0..100), adjust the corresponding formatting/normalization in
    readTelemetry() - marked with CALIBRATE comments.

  MODEL PICTURE:
    If a file named exactly like the model (as set in Model Setup ->
    Model name) exists in /IMAGES as .png or .bmp, it's shown in the
    right-hand panel (with the model name below it). E.g. a model
    named "SAB RAW 500" looks for /IMAGES/SAB RAW 500.png, then .bmp.
    If neither exists, it falls back to whatever picture is assigned
    in Model Setup. No image found -> just the model name is shown.

    IMPORTANT - pre-size the image yourself: lcd.drawBitmap's scale
    parameter does not reliably resize images on this radio, so the
    picture is drawn at its native pixel size (1:1), not scaled to
    fit. Make the file EXACTLY 186x46px (CONFIG.modelImageW/H - the
    space above the name strip in the footer card on 800x480): shrink
    the picture to fit, then center it on a transparent 186x46 canvas.
    Anything larger overflows the card.

  TX BATTERY ICON FILES:
    The top bar's TX16S battery icon uses 5 pre-colored PNGs (10/25/50/
    75/100%). Copy txbatt_10.png, txbatt_25.png, txbatt_50.png,
    txbatt_75.png, and txbatt_100.png into /IMAGES on the SD card. If
    they're missing, it silently falls back to a plain drawn rectangle
    gauge instead - nothing breaks, it just looks plainer.

  TERMINOLOGY:
    "Bank" follows Rotorflight's own usage (rotorflight.org/docs) - it
    means the active Rate/PID profile, the same concept V-bar systems
    call "bank switching". "Motor" here just means "is the rotor turning",
    derived from headspeed/governor state - it isn't a literal RPM sensor.
    "Volt" is the main pack voltage (Battery Voltage); "Rc volt" is the
    receiver/BEC voltage (BEC Voltage) - two different sensors, both
    shown side by side. "Current" shows live pack current plus this
    session's peak draw as a small "max" sub-line underneath - unlike
    the flight timer, this peak persists across flights (it only clears
    on radio power-cycle or script reload). The "Max Amp/Min Volt" chip
    (top row) shows the same idea for the whole session: highest current
    and lowest voltage seen since power-on. The "Armed"/"Disarmed" badge
    next to Headspeed reads the "Arming Flags" sensor's bit 0 -
    confirmed values are 0/2 = disarmed, 1/3 = armed. Separately, the
    "Arming Disable Flags" sensor (t.armd) triggers a full warning
    screen (replacing the whole dashboard, same idea as the standby
    screen) immediately whenever it's nonzero - no debounce/minimum
    sustain time. The value 67108872 has been specifically confirmed
    to mean the arm switch was already ON when the FC powered up
    (shown as its own message); any other nonzero value shows a
    generic "Arming disabled" message with the raw code.

  RECONNECT BEHAVIOR:
    If the telemetry link drops and comes back (checked via the "RSSI"
    fixed source, falling back to the Signal sensor), the widget clears
    its accumulated state - peak current, min voltage, flight timer,
    and the sensor-id cache - before showing anything again. This
    avoids carrying stale numbers from before the link drop into what
    looks like a fresh session. The model picture and TX battery icons
    are untouched, since they don't depend on the model's telemetry.

  FLIGHT LOG (post-flight, while disconnected):
    Only shown after a real flight - i.e. the link has to have actually
    been connected first. On radio power-up, before any connection has
    happened yet, the plain "Waiting for connection" standby screen is
    what shows, not an empty flight log. Once the link drops (aircraft
    powered off) after being connected, a flight log screen appears in
    place of the dashboard: max headspeed, max current, capacity used,
    battery remaining, min voltage, and max ESC temp. Capacity used and
    battery remaining are tracked as running max/min (peak consumption,
    lowest remaining %) rather than "whatever's most recent" - many FCs
    reset consumed capacity to 0 on disarm, which happens before the
    telemetry link actually drops, so a plain latch would show that
    post-reset 0 instead of the real flight's numbers. None of these
    trackers are cleared until the *next* reconnect. The log switches
    to the plain standby screen either by tapping the touchscreen (only
    delivered when this widget is full-screen - EdgeTX doesn't send
    touch events to widgets sharing a zone with others) or
    automatically after CONFIG.flightLogTimeoutSec (60s by default),
    whichever comes first. The log shows again fresh the next time the
    link drops after a connection.

  THEME:
    CONFIG.theme below is "color" by default. Set it to "mono" for a
    grayscale look on the SAME color-LCD widget - status is then shown by
    brightness (dim = nominal, bright = caution) instead of hue, except
    red/danger, which stays red as in every theme. Note this is still a Color LCD widget: a genuinely monochrome
    radio (e.g. X9D, X7 - 128x64, no lcd.RGB) needs a completely different
    script written against the classic mono Telemetry Screen Lua API;
    this file won't run there as-is.

    Set it to "cyan" for a black/white basis with every non-danger
    accent (governor/motor state, battery fill, throttle bar, the
    headspeed panel's border, etc.) unified to one cyan-blue, instead
    of the default's mix of green/amber/blue. Red/danger states (low
    voltage, the arm-switch warning screen) are left red on purpose in
    every theme - that's a safety signal, not a style choice.
]]

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
  flightLogTimeoutSec = 60,

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

  -- 5-step TX battery icon images (body+fill already drawn in the PNG,
  -- color-coded red/orange/yellow/green by level). Place these files in
  -- /IMAGES on the SD card. The percentage from getTxBatteryPct() picks
  -- the closest tier at or below its value.
  txBatteryIconPaths = {
    { max = 10,  path = "/IMAGES/txbatt_10.png" },
    { max = 25,  path = "/IMAGES/txbatt_25.png" },
    { max = 50,  path = "/IMAGES/txbatt_50.png" },
    { max = 75,  path = "/IMAGES/txbatt_75.png" },
    { max = 100, path = "/IMAGES/txbatt_100.png" },
  },

  -- "color" (default), "mono", or "cyan":
  --   "mono" swaps every status color for a shade of gray, so state is
  --   shown by brightness instead of hue.
  --   "cyan" is a black/white basis with every non-danger accent
  --   unified to one cyan-blue (see the CYAN THEME note near the top
  --   of this file) - red/danger states are left alone on purpose.
  theme = "color",

  -- Transmitter (TX16S) battery voltage range for the top bar's battery
  -- icon, in volts. Defaults assume a 2S Li-ion pack (the TX16S MK3's
  -- stock setup) - adjust to match your radio's actual Battery Range
  -- setting under Radio Setup, if you've calibrated it differently.
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
    voiceSets   = { "no7", "ryusei", "takehiro", "himari", "voidoll", "zundamon" },
    voiceLabels = { "No.7", "Ryusei", "Takehiro", "Himari", "Voidoll", "Zundamon" }, -- standby screen
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
    escCaution  = 80,    -- deg C
    escCritical = 90,
    escHyst     = 5,
    becCritical = 6.0,   -- V
    becHyst     = 0.3,
    flightTimeSec = 0,   -- >0: one "flight time" call when the timer passes it
    -- Haptic patterns: { duration, pause } per pulse, passed to playHaptic.
    -- UNVERIFIED on TX16S MK3: whether it has a vibration motor at all, and
    -- whether playHaptic's units are ms or 10ms - tune on the radio.
    hapticCaution  = { { 30, 0 } },
    hapticCritical = { { 60, 30 }, { 60, 30 }, { 60, 0 } },
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

local function getVoltageColor(perCellVoltage)
  if not perCellVoltage then return COLOR.dim end
  if perCellVoltage >= CONFIG.vCellGood then return COLOR.green
  elseif perCellVoltage >= CONFIG.vCellWarn then return COLOR.yellow
  else return COLOR.red end
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
  local minV, maxV = CONFIG.txBattery.minV, CONFIG.txBattery.maxV
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
-- { bit, short name shown on screen, voice file }
local ARMD_REASONS = {
  { 0,  "NO GYRO",       "armd_nogyro" },
  { 1,  "FAILSAFE",      "armd_failsafe" },
  { 2,  "RX LOSS",       "armd_rxloss" },
  { 3,  "BAD RX",        "armd_badrx" },
  { 4,  "FAILSAFE SW",   "armd_boxfailsafe" },
  { 5,  "GOVERNOR",      "armd_governor" },
  { 6,  "RPM SIGNAL",    "armd_rpmsignal" },
  { 7,  "THROTTLE",      "armd_throttle" },
  { 8,  "ANGLE",         "armd_angle" },
  { 9,  "BOOT GRACE",    "armd_bootgrace" },
  { 10, "NO PREARM",     "armd_noprearm" },
  { 11, "CPU LOAD",      "armd_load" },
  { 12, "CALIBRATING",   "armd_calib" },
  { 13, "CLI",           "armd_cli" },
  { 14, "CMS MENU",      "armd_cms" },
  { 15, "BST",           "armd_bst" },
  { 16, "MSP",           "armd_msp" },
  { 17, "PARALYZE",      "armd_paralyze" },
  { 18, "GPS",           "armd_gps" },
  { 19, "RESCUE SW",     "armd_rescuesw" },
  { 20, "RPM FILTER",    "armd_rpmfilter" },
  { 21, "REBOOT REQ",    "armd_reboot" },
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

local function fmt(value, decimals)
  if value == nil then return "--" end
  if decimals and decimals > 0 then
    return string.format("%." .. decimals .. "f", value)
  end
  return string.format("%d", value)
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

local function getBitmapSize(bmp)
  local ok, w, h = pcall(function()
    if Bitmap and Bitmap.getSize then
      return Bitmap.getSize(bmp)
    elseif lcd and lcd.getBitmapSize then
      return lcd.getBitmapSize(bmp)
    end
    return nil, nil
  end)
  if ok then return w, h end
  return nil, nil
end

local function drawBitmapFit(bmp, x, y, boxW, boxH)
  local w, h = getBitmapSize(bmp)
  if not bmp or not w or not h or w == 0 or h == 0 then return end
  -- lcd.drawBitmap's scale is a PERCENTAGE (50 = half size, 100 =
  -- unchanged) - not a 0-1 ratio. Passing the raw ratio (e.g. 0.3) was
  -- being read as ~0%, which this radio falls back to native 1:1 size
  -- for, and that's what was overflowing the box - multiplying by 100
  -- converts the fitted ratio into the percentage the API expects.
  local ratio = math.min(boxW / w, boxH / h)
  local scalePct = math.floor(ratio * 100)
  pcall(function() lcd.drawBitmap(bmp, x, y, scalePct) end)
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
  wgt.modelBitmap = nil
  for i = 1, #CONFIG.imagePaths do
    local path = string.gsub(CONFIG.imagePaths[i], "{name}", name)
    local bmp = tryLoadBitmap(path)
    if bmp then
      wgt.modelBitmap = bmp
      break
    end
  end
  -- Fall back to the picture assigned in Model Setup (if any), in case the
  -- filename doesn't match the model name exactly.
  if not wgt.modelBitmap and info and info.bitmap and info.bitmap ~= "" then
    wgt.modelBitmap = tryLoadBitmap("/IMAGES/" .. info.bitmap)
  end
end

-- Loads all 5 TX-battery tier icons once and caches them - these are
-- fixed files (not model-specific), so there's no need to re-check on
-- every refresh like ensureModelImage does. A missing file just leaves
-- that tier's slot nil; picking falls back gracefully (see below).
local function ensureTxBatteryIcons(wgt)
  if wgt.txBattIcons then return end
  wgt.txBattIcons = {}
  for i = 1, #CONFIG.txBatteryIconPaths do
    local tier = CONFIG.txBatteryIconPaths[i]
    wgt.txBattIcons[tier.max] = tryLoadBitmap(tier.path)
  end
end

-- Picks the loaded bitmap for the tier at/above the given percentage
-- (10/25/50/75/100), or nil if that tier's file wasn't found.
local function pickTxBatteryIcon(wgt, pct)
  if not wgt.txBattIcons then return nil end
  local tiers = CONFIG.txBatteryIconPaths
  for i = 1, #tiers do
    if pct <= tiers[i].max then
      return wgt.txBattIcons[tiers[i].max]
    end
  end
  return wgt.txBattIcons[100]
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

-- ============================== WIDGET API ================================

local function create(zone, options)
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
    txBattIcons = nil,
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
  }

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

-- ---- Drawing primitives -----------------------------------------------

-- All boxes reserve a small label strip at the top (using SMLSIZE, ~11px)
-- and vertically center the value in whatever height remains, picking the
-- largest font that still fits - this is what keeps things from overflowing
-- when a zone is smaller (or a row proportionally shorter) than expected.
-- Tuned for the TX16S MK3's 800x480 5" screen (roughly 800x440 available
-- once the top status bar is subtracted): a bit more generous than a
-- smaller-screen radio would need, since the extra real estate is there
-- and bigger text/icons read better outdoors on a screen this size.
local LABEL_STRIP = 14

-- Single-row chip: small icon glyph, then label, then value pushed to the
-- right edge - all on one vertically-centered line. This matches the
-- reference layout (icon + "Bank" ... "1") rather than the earlier
-- label-on-top/value-below chip style.
local function drawIconChip(x, y, w, h, iconFn, label, value, valueColor, labelFrac, valueFrac)
  lcd.drawFilledRectangle(x, y, w, h, COLOR.chip)
  -- 16px icons instead of 14px - the TX16S MK3's 5" panel has room to
  -- spare, and slightly bigger icons stay legible at a glance in flight.
  local iconSize = math.min(16, h - 10)
  local iconX, iconY = x + 10, y + h / 2 - iconSize / 2
  if iconFn then iconFn(iconX, iconY, iconSize) end
  local labelX = iconX + iconSize + 8
  -- Reserve less than half the width to each side (with the icon eating
  -- into the label's share) so there's always a visible gap between the
  -- label and the value, even on a narrow chip. A caller with an
  -- unusually long label/value (e.g. "Max Amp/Min Volt") can pass wider
  -- fractions to earn more room instead of shrinking to SMLSIZE.
  local labelMaxW = w * (labelFrac or 0.34) - iconSize
  local valueMaxW = w * (valueFrac or 0.30)
  local labelFont = fitFont(labelMaxW, h, label, MIDSIZE)
  lcd.drawText(labelX, y + h / 2, label, LEFT + VCENTER + labelFont + COLOR.dim)
  -- Values here are always short ("1", "100", "Off") - let them go up to
  -- DBLSIZE when the chip has the room, rather than capping at MIDSIZE
  -- like the (often longer) label next to it.
  local valueFont = fitFont(valueMaxW, h, value, DBLSIZE)
  lcd.drawText(x + w - 10, y + h / 2, value, RIGHT + VCENTER + valueFont + (valueColor or COLOR.white))
end

-- accented=true draws the subtle outlined "featured" card style used for
-- the headspeed panel in the reference mockup (fill + 1px border), so the
-- single most important number reads as the visual anchor of the row.
local function drawBigStat(x, y, w, h, label, value, unit, accented, subText, maxFont, valueMaxW, topReserve, skipBg, labelFont, subTextFont, subTextRight)
  if not skipBg then
    local fill = accented and COLOR.accentPanel or COLOR.panel
    lcd.drawFilledRectangle(x, y, w, h, fill)
    if accented then
      -- Fake a 1px border by drawing a slightly larger border-colored rect
      -- first, filling over it, leaving a 1px ring - EdgeTX Lua has no
      -- built-in outline-rectangle primitive.
      lcd.drawFilledRectangle(x, y, w, h, COLOR.accentBorder)
      lcd.drawFilledRectangle(x + 1, y + 1, w - 2, h - 2, fill)
    end
  end
  -- topReserve lets a caller reserve more than the usual label strip
  -- before the value starts - needed when something else (like extra
  -- status badges) is drawn on top of this same panel, above the value.
  local topH = topReserve or LABEL_STRIP
  if label ~= "" then
    lcd.drawText(x + 10, y + topH / 2, label, LEFT + VCENTER + (labelFont or SMLSIZE) + COLOR.dim)
  end
  -- subText (e.g. "max 18.2a") gets its own thin strip at the bottom, so
  -- the main value still gets the largest font that fits above it.
  local subH = subText and 14 or 0
  local valueAreaH = h - topH - subH
  local text = value .. (unit or "")
  if valueAreaH > 8 then
    -- Cap defaults to DBLSIZE, but a caller with a big enough box (e.g.
    -- the featured headspeed panel) can raise it to XXLSIZE via maxFont.
    -- valueMaxW lets a caller constrain the fitted width to less than
    -- the panel's full width - needed when something else (like the
    -- embedded stat grid) shares the same panel.
    local font = fitFont(valueMaxW or (w - 16), valueAreaH, text, maxFont or DBLSIZE)
    lcd.drawText(x + 10, y + topH + valueAreaH / 2, text,
      LEFT + VCENTER + font + COLOR.white)
  end
  if subText then
    -- VCENTER'd within its own reserved strip at the bottom, instead of
    -- top-anchored at the very edge - that top-anchoring was letting the
    -- text's own line height push it past the panel's bottom border.
    -- subTextRight puts it at the right edge of the fitted value's own
    -- width (valueMaxW) instead of the left, e.g. "rpm" sitting under
    -- the right side of the number rather than under its left edge.
    local subX = subTextRight and (x + 10 + (valueMaxW or (w - 16))) or (x + 10)
    local subAlign = subTextRight and RIGHT or LEFT
    lcd.drawText(subX, y + h - subH / 2, subText, subAlign + VCENTER + (subTextFont or SMLSIZE) + COLOR.muted)
  end
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

local function drawTab(x, y, w, h, label, value, subText, iconFn, markColor)
  local left = x + 8
  if markColor then
    lcd.drawFilledRectangle(x + 2, y + 4, 4, h - 8, markColor)
    left = x + 14
  end
  local ly = y + TAB_LABEL_H / 2 + 1
  local labelX = left
  if iconFn then
    iconFn(left, ly - 5, 10)
    labelX = left + 14
  end
  lcd.drawText(labelX, ly, label, LEFT + VCENTER + SMLSIZE + COLOR.dim)
  -- The min/max/extra note is dropped rather than drawn over the label
  -- when the tab is too narrow for both.
  if subText and labelX + textWidth(label, SMLSIZE) + 10 + textWidth(subText, SMLSIZE) > x + w - 8 then
    subText = nil
  end
  if subText then
    lcd.drawText(x + w - 8, ly, subText, RIGHT + VCENTER + SMLSIZE + COLOR.muted)
  end
  if value then
    local valueH = h - TAB_LABEL_H
    local font = fitFontMeasured(x + w - 8 - left, valueH, value, MIDSIZE)
    lcd.drawText(left, y + TAB_LABEL_H + valueH / 2, value, LEFT + VCENTER + font + COLOR.white)
  end
end

-- Label row (name left, value right, both dim/small) with a slim bar
-- underneath - this is the "battery" / "throttle" treatment from the
-- reference mockup, used for both the battery and throttle readouts.
-- Label row (name left, value right, both dim/small) with a slim bar
-- underneath - this is the "battery" / "throttle" treatment from the
-- reference mockup. The label row gets its own fixed-height strip,
-- vertically centered within it, so it always sits clearly above the
-- bar with a visible gap rather than crowding its top edge.
local function drawStatBar(x, y, w, h, label, rightText, pct, barColor, iconFn, textInBar, forceTextColor, maxFont)
  pct = math.max(0, math.min(100, pct or 0))

  if textInBar then
    -- Label/value drawn directly on top of the bar itself (no separate
    -- label strip above). Normally the text color flips dark/light
    -- based on how much of the bar is covered by the fill, but a
    -- caller can pin it to a fixed color via forceTextColor instead.
    local barY, barH = y, h
    lcd.drawFilledRectangle(x, barY, w, barH, COLOR.barBg)
    lcd.drawFilledRectangle(x, barY, math.floor(w * pct / 100), barH, barColor)
    local textColor = forceTextColor or ((pct >= 55) and COLOR.black or COLOR.white)
    local labelX = x + 10
    local labelAvailW = w / 2 - 16
    if iconFn then
      local iconSize = math.min(14, barH - 6)
      iconFn(labelX, y + barH / 2 - iconSize / 2, iconSize)
      labelX = labelX + iconSize + 6
      labelAvailW = labelAvailW - iconSize - 6
    end
    local cap = maxFont or MIDSIZE
    local labelFont = fitFont(labelAvailW, barH, label, cap)
    local rightFont = fitFont(w / 2 - 16, barH, rightText, cap)
    lcd.drawText(labelX, y + barH / 2, label, LEFT + VCENTER + labelFont + textColor)
    lcd.drawText(x + w - 10, y + barH / 2, rightText, RIGHT + VCENTER + rightFont + textColor)
    return
  end

  local labelStripH = 18
  local labelX = x
  local labelAvailW = w / 2 - 10
  if iconFn then
    local iconSize = 12
    iconFn(x, y + labelStripH / 2 - iconSize / 2, iconSize)
    labelX = x + iconSize + 6
    labelAvailW = labelAvailW - iconSize - 6
  end
  -- Label and right-hand value are sized independently, each fitted to
  -- its own available width - a longer combined rightText (e.g.
  -- "0% / 25C") no longer inherits the (possibly larger) font sized for
  -- the short label, which was pushing it out of position/off the edge.
  local labelFont = fitFont(labelAvailW, labelStripH, label, MIDSIZE)
  local rightFont = fitFont(w / 2 - 10, labelStripH, rightText, MIDSIZE)
  lcd.drawText(labelX, y + labelStripH / 2, label, LEFT + VCENTER + labelFont + COLOR.dim)
  lcd.drawText(x + w, y + labelStripH / 2, rightText, RIGHT + VCENTER + rightFont + COLOR.dim)
  local barY = y + labelStripH + 4
  local barH = math.max(4, h - labelStripH - 4)
  lcd.drawFilledRectangle(x, barY, w, barH, COLOR.barBg)
  lcd.drawFilledRectangle(x, barY, math.floor(w * pct / 100), barH, barColor)
end

-- Icon-style battery gauge (body + small nub, like a physical battery
-- symbol) with the percentage printed inside - a quick-glance companion
-- to the detailed bar below it, not a duplicate of it.
local function drawBatteryIcon(x, y, w, h, pct, showText)
  pct = math.max(0, math.min(100, pct or 0))
  local color = getChargeColor(pct)
  local nubW = math.max(2, math.floor(h * 0.18))
  local bodyW = w - nubW - 2
  lcd.drawFilledRectangle(x, y, bodyW, h, COLOR.barBg)
  lcd.drawFilledRectangle(x, y + h * 0.25, nubW, h * 0.5, COLOR.barBg)
  local fillW = math.floor((bodyW - 4) * pct / 100)
  lcd.drawFilledRectangle(x + 2, y + 2, fillW, h - 4, color)
  if showText ~= false then
    local text = fmt(pct, 0) .. "%"
    local font = fitFont(bodyW - 6, h, text, MIDSIZE)
    local textColor = (pct >= 40) and COLOR.black or COLOR.white
    lcd.drawText(x + bodyW / 2, y + h / 2, text, CENTER + VCENTER + font + textColor)
  end
end

-- Bar-chart signal icon (4 ascending bars, lit left-to-right by strength)
-- - a quicker visual read than a bare number, though the number stays in
-- the chip label to its left for anyone who wants the precise value.
local function getSignalColor(pct)
  if not pct then return COLOR.grey end
  if pct >= 80 then return COLOR.green
  elseif pct >= 50 then return COLOR.yellow
  else return COLOR.red end
end

local function drawSignalBars(x, y, w, h, pct)
  local lit = 0
  if pct then
    lit = math.min(4, math.ceil(math.max(0, pct) / 25))
  end
  local litColor = getSignalColor(pct)
  local barCount = 4
  local gap = 3
  local barW = (w - gap * (barCount - 1)) / barCount
  for i = 1, barCount do
    local barH = h * (i / barCount)
    local barX = x + (i - 1) * (barW + gap)
    local barY = y + h - barH
    local color = (i <= lit) and litColor or COLOR.barBg
    lcd.drawFilledRectangle(barX, barY, barW, barH, color)
  end
end

-- Small square "status dot" + label, e.g. "Governor active" - a much
-- quieter way to surface state than a full-width colored banner.
local function drawDotChip(x, y, w, h, label, dotColor)
  lcd.drawFilledRectangle(x, y, w, h, COLOR.chip)
  local dotSize = 6
  local dotX, dotY = x + 10, y + h / 2 - dotSize / 2
  lcd.drawFilledRectangle(dotX, dotY, dotSize, dotSize, dotColor)
  local font = fitFont(w - dotSize - 26, h, label, MIDSIZE)
  lcd.drawText(dotX + dotSize + 8, y + h / 2, label, LEFT + VCENTER + font + COLOR.white)
end

-- Compact warning strip - only takes up space when something actually
-- needs attention, so the dashboard stays quiet the rest of the time.
-- ---- Layouts by zone size ------------------------------------------------

local function drawSmall(wgt, t, w, h)
  lcd.drawFilledRectangle(0, 0, w, h, COLOR.bg)
  local barH = math.min(6, math.floor(h * 0.15))
  lcd.drawFilledRectangle(0, 0, w, barH, getGovColor(t.gov))
  local text = fmt(t.rpm, 0)
  local font = fitFont(w - 16, h - barH - 10, text)
  lcd.drawText(w / 2, barH + (h - barH) / 2 - 6, text, CENTER + VCENTER + font + COLOR.white)
  if h >= 40 then
    lcd.drawText(w / 2, h - 10, "Rpm", CENTER + SMLSIZE + COLOR.dim)
  end
end

local function drawMedium(wgt, t, w, h)
  lcd.drawFilledRectangle(0, 0, w, h, COLOR.bg)
  local bannerH = math.min(20, math.floor(h * 0.22))
  lcd.drawFilledRectangle(0, 0, w, bannerH, getGovColor(t.gov))
  local govText = t.gov and toSentenceCase(t.gov) or "Gov n/a"
  lcd.drawText(w / 2, bannerH / 2, govText,
    CENTER + VCENTER + fitFont(w - 16, bannerH, govText) + COLOR.black)
  local valueAreaH = h - bannerH - 14
  local rpmText = fmt(t.rpm, 0)
  local font = fitFont(w - 16, valueAreaH, rpmText)
  lcd.drawText(w / 2, bannerH + valueAreaH / 2, rpmText, CENTER + VCENTER + font + COLOR.white)
  lcd.drawText(w / 2, h - 10, "Rpm", CENTER + SMLSIZE + COLOR.dim)
end

-- Small decorative icon glyphs for the row-1 chips (EdgeTX Lua has no
-- icon font available, so these are drawn from plain rectangles).
local function bankIconFn(x, y, size)
  local barW = math.max(1, math.floor(size / 5))
  local gap = math.max(1, math.floor(size / 6))
  local heights = { size * 0.5, size * 1.0, size * 0.7 }
  for i = 1, 3 do
    local bx = x + (i - 1) * (barW + gap)
    local bh = heights[i]
    lcd.drawFilledRectangle(bx, y + size - bh, barW, bh, COLOR.dim)
  end
end

local function motorIconFn(running)
  return function(x, y, size)
    -- Small motor housing (hollow square) with a filled center dot that
    -- still carries the on/off color, so the status read-out is kept
    -- but the icon itself looks more like "a motor" than a plain dot.
    local th = 1
    lcd.drawFilledRectangle(x, y, size, th, COLOR.dim)
    lcd.drawFilledRectangle(x, y + size - th, size, th, COLOR.dim)
    lcd.drawFilledRectangle(x, y, th, size, COLOR.dim)
    lcd.drawFilledRectangle(x + size - th, y, th, size, COLOR.dim)
    local color = running and COLOR.green or COLOR.grey
    lcd.drawFilledRectangle(x + size * 0.28, y + size * 0.28, size * 0.44, size * 0.44, color)
  end
end

local function signalIconFn(pct)
  return function(x, y, size)
    drawSignalBars(x, y, size, size, pct)
  end
end

-- Hollow rectangle outline (thin strips on all 4 sides) - used as the
-- base shape for the small battery/clock glyphs below, so they read as
-- "outline" icons distinct from the filled battery gauge used elsewhere.
local function drawHollowRect(x, y, w, h, color)
  local th = 1
  lcd.drawFilledRectangle(x, y, w, th, color)
  lcd.drawFilledRectangle(x, y + h - th, w, th, color)
  lcd.drawFilledRectangle(x, y, th, h, color)
  lcd.drawFilledRectangle(x + w - th, y, th, h, color)
end

-- Chamfered-corner panel: EdgeTX Lua has no true rounded-rectangle
-- primitive (only axis-aligned filled rectangles), so this fakes a
-- softer look by notching each corner with a couple of shrinking
-- background-colored steps - a small stair-step chamfer rather than a
-- smooth curve, but it reads as "less sharp" than a plain rectangle,
-- especially at a glance/in a photo. bgColor should be whatever sits
-- behind the panel (COLOR.bg normally) so the notch actually shows.
local function drawChamferedRect(x, y, w, h, fillColor, bgColor, corner)
  corner = corner or 6
  lcd.drawFilledRectangle(x, y, w, h, fillColor)
  local steps = 3
  for i = 0, steps - 1 do
    local cut = corner - math.floor(corner * i / steps)
    if cut > 0 then
      lcd.drawFilledRectangle(x + i, y + i, cut, 1, bgColor) -- top-left
      lcd.drawFilledRectangle(x + i, y + i, 1, cut, bgColor)
      lcd.drawFilledRectangle(x + w - i - cut, y + i, cut, 1, bgColor) -- top-right
      lcd.drawFilledRectangle(x + w - i - 1, y + i, 1, cut, bgColor)
      lcd.drawFilledRectangle(x + i, y + h - i - 1, cut, 1, bgColor) -- bottom-left
      lcd.drawFilledRectangle(x + i, y + h - i - cut, 1, cut, bgColor)
      lcd.drawFilledRectangle(x + w - i - cut, y + h - i - 1, cut, 1, bgColor) -- bottom-right
      lcd.drawFilledRectangle(x + w - i - 1, y + h - i - cut, 1, cut, bgColor)
    end
  end
end

-- Small "bolt" glyph for Volt - a blocky zigzag stepping right then
-- left, approximating a lightning bolt with only axis-aligned rects.
local function voltIconFn(x, y, size)
  local w = size * 0.55
  local h = size * 0.34
  lcd.drawFilledRectangle(x + size * 0.15, y, w, h, COLOR.dim)
  lcd.drawFilledRectangle(x + size * 0.30, y + size * 0.33, w, h, COLOR.dim)
  lcd.drawFilledRectangle(x + size * 0.10, y + size * 0.66, w, h, COLOR.dim)
end

-- Small "waveform" glyph for Current - three bars forming a peak,
-- suggesting an AC/current waveform.
local function currentIconFn(x, y, size)
  local barW = math.max(1, size / 5)
  local gap = size / 5
  local heights = { size * 0.4, size * 1.0, size * 0.4 }
  for i = 1, 3 do
    local bx = x + (i - 1) * (barW + gap)
    local bh = heights[i]
    lcd.drawFilledRectangle(bx, y + size - bh, barW, bh, COLOR.dim)
  end
end

-- Small hollow battery-cell glyph for Vcel - outline only (no fill/
-- gauge), so it reads as "a cell" rather than "the battery level".
local function vcelIconFn(x, y, size)
  local nubW = size * 0.16
  local bodyW = size - nubW - 1
  drawHollowRect(x, y, bodyW, size, COLOR.dim)
  lcd.drawFilledRectangle(x + bodyW, y + size * 0.3, nubW, size * 0.4, COLOR.dim)
end

-- Small "clock" glyph for Flight - a hollow square with one tick from
-- the center towards the top, standing in for a clock hand.
local function flightIconFn(x, y, size)
  drawHollowRect(x, y, size, size, COLOR.dim)
  lcd.drawFilledRectangle(x + size / 2 - 1, y + size * 0.2, 2, size * 0.35, COLOR.dim)
end

-- Small "rotor head" glyph for Governor - a full-width blade bar over a
-- short mast, the simplest rectangle-only read of a helicopter rotor.
local function governorIconFn(x, y, size)
  lcd.drawFilledRectangle(x, y + size * 0.25, size, 2, COLOR.dim)
  lcd.drawFilledRectangle(x + size / 2 - 2, y + size * 0.15, 4, 4, COLOR.dim)
  lcd.drawFilledRectangle(x + size / 2 - 1, y + size * 0.25, 2, size * 0.75, COLOR.dim)
end

-- Small battery-gauge glyph for the "Battery" bar's label - a mini,
-- unfilled version distinct from the big colored bar right below it.
local function batteryLabelIconFn(x, y, size)
  local nubW = size * 0.16
  local bodyW = size * 1.5 - nubW - 1
  drawHollowRect(x, y, bodyW, size, COLOR.dim)
  lcd.drawFilledRectangle(x + bodyW, y + size * 0.3, nubW, size * 0.4, COLOR.dim)
  -- a small partial fill to suggest charge, without claiming to be exact
  lcd.drawFilledRectangle(x + 2, y + 2, bodyW * 0.5, size - 4, COLOR.dim)
end

-- Small "throttle stick" glyph - a vertical track with a slider partway
-- up, standing in for a throttle lever position.
local function throttleLabelIconFn(x, y, size)
  local trackW = size * 0.3
  local trackX = x + size * 0.5 - trackW / 2
  drawHollowRect(trackX, y, trackW, size, COLOR.dim)
  lcd.drawFilledRectangle(x, y + size * 0.35, size, size * 0.18, COLOR.dim)
end

-- Standby screen, shown below the top bar whenever there's no
-- telemetry link, instead of a dashboard full of "--"/"0" placeholders
-- that could be mistaken for real (if alarming) readings. A simple
-- "searching" ring glyph, a clear status line, and the model name
-- (always known from Model Setup, independent of any telemetry link).
-- One wipe-reveal animation shared by every screen change (standby,
-- flight log, arm warning, dashboard - whichever one is being switched
-- TO). Covers the not-yet-revealed portion of the screen in the
-- background color and shrinks that cover left-to-right, with a
-- bright "scan line" right at the moving edge. Eased (ease-out cubic:
-- fast start, gentle settle) rather than a constant linear speed, so
-- the motion reads as smoother/less mechanical - the actual smoothness
-- is still capped by how often EdgeTX calls refresh(), but the shape
-- of the motion itself is no longer a flat ramp.
local function drawTransitionOverlay(wgt, w, h)
  if not wgt.screenTransitionTime then return end
  local elapsedSec = (getTime() - wgt.screenTransitionTime) / 100
  local durationSec = 0.5
  if elapsedSec >= durationSec then
    wgt.screenTransitionTime = nil
    return
  end
  local t = elapsedSec / durationSec
  local inv = 1 - t
  local eased = 1 - inv * inv * inv -- ease-out cubic
  local revealX = math.floor(w * eased)
  lcd.drawFilledRectangle(revealX, 0, w - revealX, h, COLOR.bg)
  lcd.drawFilledRectangle(math.max(0, revealX - 3), 0, 3, h, COLOR.accent)
end

-- Standby ("Waiting for connection"), built from the dashboard's pieces
-- and filled with what is known without a model link: a big clock and the
-- model card (hero panel), a status strip with a sweeping scan bar so the
-- screen visibly isn't frozen, and tabs for the TX battery, this
-- session's last flight, and the alarm voice / mute state.
local function drawStandby(wgt, y, w, h)
  lcd.drawFilledRectangle(0, y, w, h - y, COLOR.bg)
  local pad = 12
  local panelW = w - pad * 2

  -- Hero: clock (left half) | model card (right half). Takes whatever
  -- height the status strip (56) and tabs (62) below leave over.
  local heroH = (h - pad) - y - (pad + 56 + pad + 62)
  drawChamferedRect(pad, y, panelW, heroH, COLOR.accentBorder, COLOR.bg, 8)
  drawChamferedRect(pad + 1, y + 1, panelW - 2, heroH - 2, COLOR.accentPanel, COLOR.accentBorder, 7)
  local half = math.floor(panelW / 2)
  local leftCx, rightCx = pad + half / 2, pad + half + half / 2
  local ok, dt = pcall(getDateTime)
  if ok and dt then
    lcd.drawText(leftCx, y + heroH / 2 - 10, string.format("%02d:%02d", dt.hour, dt.min),
      CENTER + VCENTER + XXLSIZE + COLOR.white)
    lcd.drawText(leftCx, y + heroH - 34, string.format("%04d/%02d/%02d", dt.year, dt.mon, dt.day),
      CENTER + VCENTER + SMLSIZE + COLOR.dim)
  end
  lcd.drawFilledRectangle(pad + half, y + 24, 1, heroH - 48, COLOR.muted)
  local imgY = y + math.floor(heroH * 0.22)
  if CONFIG.showModelImage and wgt.modelBitmap then
    pcall(function()
      lcd.drawBitmap(wgt.modelBitmap, math.floor(rightCx - CONFIG.modelImageW / 2), imgY)
    end)
  end
  local modelName = (model and model.getInfo and model.getInfo().name) or ""
  lcd.drawText(rightCx, imgY + CONFIG.modelImageH + 48, modelName,
    CENTER + VCENTER + fitFontMeasured(half - 40, 55, modelName, DBLSIZE) + COLOR.white)
  lcd.drawText(rightCx, y + heroH - 34, "Model", CENTER + VCENTER + SMLSIZE + COLOR.dim)

  -- Status strip: "Waiting for connection" + 2s sweeping scan bar
  local sy, sh = y + heroH + pad, 56
  drawChamferedRect(pad, sy, panelW, sh, COLOR.panel, COLOR.bg, 6)
  local dots = string.rep(".", math.floor(getTime() / 50) % 4)
  lcd.drawText(pad + 16, sy + 22, "Waiting for connection" .. dots,
    LEFT + VCENTER + MIDSIZE + COLOR.white)
  lcd.drawText(pad + panelW - 16, sy + 22, "Power on the model",
    RIGHT + VCENTER + SMLSIZE + COLOR.dim)
  local trackX, trackW, trackY = pad + 16, panelW - 32, sy + sh - 9
  lcd.drawFilledRectangle(trackX, trackY, trackW, 3, COLOR.barBg)
  local segW = 120
  local segX = trackX + math.floor((trackW - segW) * ((getTime() % 200) / 200))
  lcd.drawFilledRectangle(segX, trackY, segW, 3, COLOR.accent)

  -- Tabs: TX battery | Last flight | Voice | Alarms
  local ty, tabH = sy + sh + pad, 62
  drawChamferedRect(pad, ty, panelW, tabH, COLOR.panel, COLOR.bg, 6)
  local txPct, txV = getTxBatteryPct()
  local voiceIdx = math.floor((wgt.options and wgt.options.Voice) or 0)
  local labels = CONFIG.alarm.voiceLabels
  local alarmsValue, alarmsColor = "On", COLOR.green
  if not CONFIG.alarm.enabled then
    alarmsValue, alarmsColor = "Off", COLOR.grey
  elseif wgt.alarmMuted then
    alarmsValue, alarmsColor = "Muted", COLOR.orange
  end
  local tabs = {
    { "TX battery", txV and (fmt(txV, 1) .. "v") or "--", txPct and (fmt(txPct, 0) .. "%"),
      batteryLabelIconFn, txPct and getChargeColor(txPct) },
    { "Last flight", (wgt.flightSeconds or 0) > 0 and fmtTime(wgt.flightSeconds) or "--",
      wgt.maxCapacity and (fmt(wgt.maxCapacity, 0) .. "mAh"), flightIconFn },
    { "Voice", labels[voiceIdx + 1] or labels[1], nil, nil },
    { "Alarms", alarmsValue, nil, nil, alarmsColor },
  }
  -- Widths follow the content: "Last flight" + "3800mAh" needs ~220px,
  -- Voice/Alarms values are short.
  local fracs = { 0.26, 0.30, 0.22 }
  local tx = pad
  for i = 1, 4 do
    local tab = tabs[i]
    local tw = fracs[i] and math.floor(panelW * fracs[i]) or (pad + panelW - tx)
    if i > 1 and not tab[5] then lcd.drawFilledRectangle(tx, ty + 10, 1, tabH - 20, COLOR.muted) end
    drawTab(tx + 2, ty + 1, tw - 4, tabH - 2, tab[1], tab[2], tab[3], tab[4], tab[5])
    tx = tx + tw
  end
end

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

-- One chart for every flight series: each a 2px polyline in its color,
-- scaled to its own 4-division axis (chartAxis) so they share the grid.
-- Value labels: defs[1] on the left, defs[2] and defs[3] side by side on
-- the right, each in its series color. m:ss ticks under the baseline.
--   defs[i] = { series = {...}, bottom = n, step = n, color = c }
-- Point heights are kept in `cache` until the series or geometry change.
-- NOTE: EdgeTX stops refresh() with "CPU limit" when a frame runs too many
-- Lua instructions (a dotted grid once tripped it), so this stays lean.
local function drawFlightChart(x, y, w, h, defs, durationSec, cache)
  local labelL, labelR = 46, 90
  local px, pw = x + labelL, w - labelL - labelR
  local base, top = y + h - 1, h - 1
  for q = 1, CHART_DIVS do
    lcd.drawFilledRectangle(px, base - math.floor(q * top / CHART_DIVS), pw, 1, COLOR.barBg)
  end
  lcd.drawFilledRectangle(px, base, pw, 1, COLOR.muted)

  local n = #defs[1].series
  if n < 2 then
    lcd.drawText(px + pw / 2, y + h / 2, "No data", CENTER + VCENTER + SMLSIZE + COLOR.muted)
    return
  end

  -- Value labels at every grid line
  local labelX = { px - 6, px + pw + 6, px + pw + 6 + labelR / 2 }
  local labelFlag = { RIGHT, LEFT, LEFT }
  for i = 1, #defs do
    local d = defs[i]
    local decimals = (d.step ~= math.floor(d.step) or d.bottom ~= math.floor(d.bottom)) and 1 or 0
    for q = 0, CHART_DIVS do
      lcd.drawText(labelX[i], base - math.floor(q * top / CHART_DIVS), fmt(d.bottom + q * d.step, decimals),
        labelFlag[i] + VCENTER + SMLSIZE + d.color)
    end
  end

  -- Polyline points: one every stepX px, computed once per data set.
  -- 8px (~78 points over ~620px): at 3px the chart alone measured ~26k
  -- Lua instructions per frame in tools/luatest - CPU limit territory.
  local stepX = 8
  local pts = cache and cache.series == defs[1].series and cache.n == n and cache.pw == pw
    and cache.h == h and cache.key == defs[1].step .. "/" .. defs[2].step .. "/" .. defs[3].bottom and cache.pts
  if not pts then
    pts = {}
    local floor, idxStep = math.floor, n / pw
    for i = 1, #defs do
      local d, p, k = defs[i], {}, 0
      local scale = top / (CHART_DIVS * d.step)
      for cx = 0, pw - 1, stepX do
        local v = (d.series[floor(cx * idxStep) + 1] - d.bottom) * scale
        if v < 0 then v = 0 elseif v > top then v = top end
        k = k + 1
        p[k] = base - floor(v)
      end
      pts[i] = p
    end
    if cache then
      cache.series, cache.n, cache.pw, cache.h, cache.pts = defs[1].series, n, pw, h, pts
      cache.key = defs[1].step .. "/" .. defs[2].step .. "/" .. defs[3].bottom
    end
  end

  -- lcd.drawLine isn't verified on this radio; without it, 2x2 dots.
  local line = lcd.drawLine
  for i = 1, #defs do
    local p, color = pts[i], defs[i].color
    if line then
      for k = 2, #p do
        local x1, x2 = px + (k - 2) * stepX, px + (k - 1) * stepX
        line(x1, p[k - 1], x2, p[k], SOLID, color)
        line(x1, p[k - 1] - 1, x2, p[k] - 1, SOLID, color)
      end
    else
      for k = 1, #p do lcd.drawFilledRectangle(px + (k - 1) * stepX, p[k] - 1, 2, 2, color) end
    end
  end

  -- Time ticks under the baseline
  if durationSec and durationSec > 0 then
    local tStep = TIME_STEPS[#TIME_STEPS]
    for i = 1, #TIME_STEPS do
      if durationSec / TIME_STEPS[i] <= 3 then tStep = TIME_STEPS[i]; break end
    end
    local t = 0
    while t <= durationSec do
      local tx = px + math.floor(t / durationSec * (pw - 1))
      lcd.drawFilledRectangle(tx, y + h, 1, 4, COLOR.muted)
      lcd.drawText(tx, y + h + 13, fmtTime(t), CENTER + VCENTER + SMLSIZE + COLOR.muted)
      t = t + tStep
    end
  end
end

-- Post-flight summary, built from the same pieces as the dashboard: a
-- title strip, two rows of four drawTabs (peak/min values, with averages
-- or the matching secondary value on the label row), and three graphs
-- (headspeed, current, pack voltage) over the time the rotor was spinning.
local function drawFlightLog(wgt, y, w, h)
  lcd.drawFilledRectangle(0, y, w, h - y, COLOR.bg)
  local pad = 12
  local panelW = w - pad * 2
  local s = wgt.samples

  -- Title strip
  local titleH = 40
  drawChamferedRect(pad, y, panelW, titleH, COLOR.panel, COLOR.bg, 6)
  lcd.drawText(pad + 14, y + titleH / 2, "Flight log", LEFT + VCENTER + MIDSIZE + COLOR.white)
  local modelName = (model and model.getInfo and model.getInfo().name) or ""
  lcd.drawText(pad + 14 + textWidth("Flight log", MIDSIZE) + 16, y + titleH / 2, modelName,
    LEFT + VCENTER + SMLSIZE + COLOR.dim)
  local remain = CONFIG.flightLogTimeoutSec
  if wgt.disconnectTime then
    remain = math.max(0, remain - math.floor((getTime() - wgt.disconnectTime) / 100))
  end
  -- Close button: tap (full-screen only), Enter, or the "Close" option's
  -- switch all go back to standby (see refresh()/tick()). The countdown
  -- is the auto-close timeout.
  local btnW, btnH = 150, 30
  local btnX, btnY = pad + panelW - 8 - btnW, y + (titleH - btnH) / 2
  drawChamferedRect(btnX, btnY, btnW, btnH, COLOR.barBg, COLOR.panel, 4)
  lcd.drawText(btnX + 14, btnY + btnH / 2, "Close", LEFT + VCENTER + SMLSIZE + COLOR.white)
  lcd.drawText(btnX + btnW - 14, btnY + btnH / 2, remain .. "s", RIGHT + VCENTER + SMLSIZE + COLOR.dim)

  -- Stats: two rows of four tabs
  -- statsFresh: this frame paid for the stats pass, so the charts (their
  -- own column pass) wait one frame - spreading the work keeps each frame
  -- under EdgeTX's "CPU limit"; the wipe transition hides the gap.
  local stats, statsFresh = flightSampleStats(wgt)
  local avgRpm, avgCur = stats.avgRpm, stats.avgCur
  local power = "--"
  if wgt.maxPower then
    power = (wgt.maxPower >= 1000) and (fmt(wgt.maxPower / 1000, 1) .. "kW") or (fmt(wgt.maxPower, 0) .. "W")
  end
  local rows = {
    {
      { "Flight time",  fmtTime(wgt.flightSeconds), nil, flightIconFn },
      { "Max rpm",      wgt.maxHeadspeed and fmt(wgt.maxHeadspeed, 0) or "--",
        avgRpm and ("avg " .. fmt(avgRpm, 0)), governorIconFn },
      { "Max amps",     wgt.maxCurrent and (fmt(wgt.maxCurrent, 1) .. "A") or "--",
        avgCur and ("avg " .. fmt(avgCur, 0) .. "A"), currentIconFn },
      { "Max power",    power, nil, voltIconFn },
    },
    {
      { "Used",         wgt.maxCapacity and (fmt(wgt.maxCapacity, 0) .. "mAh") or "--",
        wgt.minCharge and (fmt(wgt.minCharge, 0) .. "% left"), batteryLabelIconFn },
      { "Min volt",     wgt.minVoltage and (fmt(wgt.minVoltage, 1) .. "v") or "--",
        wgt.minCellVoltage and ("cell " .. fmt(wgt.minCellVoltage, 2)), voltIconFn },
      { "Min Bec",      wgt.minBecVoltage and (fmt(wgt.minBecVoltage, 1) .. "v") or "--", nil, voltIconFn },
      { "Max ESC",      wgt.maxEscTemp and (fmt(wgt.maxEscTemp, 0) .. "\194\176C") or "--", nil, throttleLabelIconFn },
    },
  }
  local tabH, rowGap = 62, 8 -- 62 = 2 border + 18 label row + 42 MIDSIZE
  local tabW = math.floor(panelW / 4)
  local ty = y + titleH + pad
  for r = 1, 2 do
    drawChamferedRect(pad, ty, panelW, tabH, COLOR.panel, COLOR.bg, 6)
    for i = 1, 4 do
      local tab = rows[r][i]
      local tx = pad + (i - 1) * tabW
      if i > 1 then lcd.drawFilledRectangle(tx, ty + 10, 1, tabH - 20, COLOR.muted) end
      drawTab(tx + 2, ty + 1, tabW - 4, tabH - 2, tab[1], tab[2], tab[3], tab[4])
    end
    ty = ty + tabH + rowGap
  end

  -- Graph: headspeed, current and pack voltage in one full-width chart.
  -- Axis scales come from the 1s samples; the legend's max/min come from
  -- the per-frame trackers, so they match the tabs above exactly.
  local gy = ty - rowGap + pad
  local gh = h - pad - gy
  drawChamferedRect(pad, gy, panelW, gh, COLOR.panel, COLOR.bg, 6)
  local rpmBottom, rpmStep = chartAxis(0, stats.maxRpm, true)
  local curBottom, curStep = chartAxis(0, stats.maxCur, true)
  local vBottom, vStep = chartAxis(stats.minV or 0, stats.maxV or 1, false)
  local defs = {
    { series = s.rpm,     bottom = rpmBottom, step = rpmStep, color = COLOR.accent,
      label = "Headspeed", note = wgt.maxHeadspeed and ("max " .. fmt(wgt.maxHeadspeed, 0)) },
    { series = s.current, bottom = curBottom, step = curStep, color = COLOR.orange,
      label = "Current A", note = wgt.maxCurrent and ("max " .. fmt(wgt.maxCurrent, 1)) },
    { series = s.voltage, bottom = vBottom,   step = vStep,   color = COLOR.green,
      label = "Voltage v", note = wgt.minVoltage and ("min " .. fmt(wgt.minVoltage, 1)) },
  }
  -- Legend in the label row: color key + name + max/min, left to right
  local lx, ly = pad + 14, gy + 1 + TAB_LABEL_H / 2 + 1
  for i = 1, #defs do
    local d = defs[i]
    lcd.drawFilledRectangle(lx, ly - 4, 14, 8, d.color)
    lx = lx + 20
    lcd.drawText(lx, ly, d.label, LEFT + VCENTER + SMLSIZE + COLOR.dim)
    lx = lx + textWidth(d.label, SMLSIZE) + 8
    if d.note then
      lcd.drawText(lx, ly, d.note, LEFT + VCENTER + SMLSIZE + COLOR.muted)
      lx = lx + textWidth(d.note, SMLSIZE)
    end
    lx = lx + 26
  end
  -- 16px under the label row so the top value labels (centered on the
  -- top grid line) clear it; 28px at the bottom for the time labels.
  if not statsFresh then
    wgt.chartCache = wgt.chartCache or {}
    drawFlightChart(pad + 8, gy + TAB_LABEL_H + 16, panelW - 16, gh - TAB_LABEL_H - 16 - 28,
      defs, #s.rpm * s.interval, wgt.chartCache)
  end
end

-- A large, hard-to-miss warning screen that takes over the whole
-- dashboard area (same idea as drawStandby) for the one arming-disable
-- condition that's actually confirmed and specific: the arm switch was
-- already on at power-up. This blocks flight entirely, so it gets a
-- full warning screen instead of a single line in the small warnings
-- strip, which would be easy to miss.
local function drawArmSwitchWarning(y, w, h, armdValue)
  local areaH = h - y
  lcd.drawFilledRectangle(0, y, w, areaH, COLOR.bg)

  local cx = w / 2
  local cy = y + areaH * 0.38

  -- A thick red frame around the whole area, so it reads as an alert
  -- even from a glance.
  local frameT = 6
  lcd.drawFilledRectangle(2, y + 2, w - 4, frameT, COLOR.red)
  lcd.drawFilledRectangle(2, y + areaH - frameT - 2, w - 4, frameT, COLOR.red)
  lcd.drawFilledRectangle(2, y + 2, frameT, areaH - 4, COLOR.red)
  lcd.drawFilledRectangle(w - frameT - 2, y + 2, frameT, areaH - 4, COLOR.red)

  -- A simple "!" glyph (bar + dot) in place of a triangle warning icon,
  -- which EdgeTX Lua has no way to draw without arcs/diagonals.
  lcd.drawFilledRectangle(cx - 5, cy - 46, 10, 30, COLOR.red)
  lcd.drawFilledRectangle(cx - 5, cy - 10, 10, 10, COLOR.red)

  -- 67108872 (arm switch already on at power-up) is confirmed on the
  -- radio and gets its own wording; anything else lists the decoded
  -- reasons (ARMD_REASONS) plus the raw code for reference.
  if armdValue == ARMD_ARM_SWITCH_AT_POWERUP then
    lcd.drawText(cx, cy + 26, "ARM SWITCH WAS ON AT POWER-UP",
      CENTER + VCENTER + DBLSIZE + COLOR.red)
    lcd.drawText(cx, cy + 54, "Cycle the switch off and on to arm - cannot fly like this",
      CENTER + VCENTER + SMLSIZE + COLOR.white)
  else
    lcd.drawText(cx, cy + 26, "ARMING DISABLED",
      CENTER + VCENTER + DBLSIZE + COLOR.red)
    local reasons = decodeArmd(armdValue)
    local names = {}
    for i = 1, #reasons do names[i] = reasons[i][2] end
    local reasonText = (#names > 0) and table.concat(names, " / ") or "unknown"
    lcd.drawText(cx, cy + 74, reasonText,
      CENTER + VCENTER + fitFontMeasured(w - 60, 42, reasonText, MIDSIZE) + COLOR.white)
    lcd.drawText(cx, cy + 110, "code " .. fmt(armdValue, 0),
      CENTER + VCENTER + SMLSIZE + COLOR.dim)
  end
end

-- Full dashboard layout, refined to match the reviewed mockup: sentence
-- case labels, a featured (bordered) headspeed card, slim label+bar
-- readouts for battery/throttle, a quiet dot-chip for governor state, and
-- a warnings strip that only appears when something needs attention.
-- Single full-width column throughout - the earlier tall right-side model
-- panel wasted a lot of space whenever no matching picture was found, so
-- the model picture/name is back to a small, unobtrusive corner element.
local function drawLarge(wgt, t, w, h)
  lcd.drawFilledRectangle(0, 0, w, h, COLOR.bg)

  -- 12px base padding - a touch more breathing room, since the TX16S
  -- MK3's 800x480 panel has enough real estate to spare it without
  -- squeezing any row.
  local pad = 12

  -- Which of the 4 screens (standby / flight log / arm warning /
  -- dashboard) to draw. When it differs from last refresh, kick off the
  -- same wipe-reveal animation - one mechanism for every transition.
  local nowConnected = isTelemetryConnected(t)
  local screenType
  if not nowConnected then
    screenType = wgt.showFlightLog and "flightlog" or "standby"
  elseif wgt.armWarningActive then
    screenType = "armwarning"
  else
    screenType = "dashboard"
  end
  if wgt.lastScreenType and wgt.lastScreenType ~= screenType then
    wgt.screenTransitionTime = getTime()
  end
  wgt.lastScreenType = screenType

  -- Standby has no top bar: its own panels already show the clock and the
  -- TX battery, so it uses the whole screen from the top padding down.
  if screenType == "standby" then
    drawStandby(wgt, pad, w, h)
    drawTransitionOverlay(wgt, w, h)
    return
  end

  -- Row 0: top bar - Signal on the left, transmitter (TX16S) battery
  -- icon on the right. The TX battery icon is colour-only (same vivid
  -- green/yellow/red as the model battery bar) - no label, voltage, or
  -- percentage text, just the fill level at a glance.
  local topBarY, topBarH = pad, 30
  drawChamferedRect(pad, topBarY, w - pad * 2, topBarH, COLOR.chip, COLOR.bg, 6)

  local txPct = getTxBatteryPct()
  local txIcon = pickTxBatteryIcon(wgt, txPct or 0)
  -- The PNG tiers are pre-sized to their exact display dimensions
  -- (45x22) - drawn at scale 1 (native size), so there's no dependency
  -- on this radio's lcd.drawBitmap scale-factor behavior, which is what
  -- caused the icon to render oversized and run off the screen edge.
  local txIconW, txIconH = 45, 22
  if not txIcon then
    txIconW, txIconH = 56, topBarH - 10 -- fallback rectangle gauge size
  end
  local txIconX = w - pad - 12 - txIconW
  if txIcon then
    pcall(function() lcd.drawBitmap(txIcon, txIconX, topBarY + (topBarH - txIconH) / 2) end)
  else
    -- Fall back to the drawn rectangle gauge if the PNG tier files
    -- haven't been copied to /IMAGES yet.
    drawBatteryIcon(txIconX, topBarY + 5, txIconW, txIconH, txPct or 0, false)
  end

  -- Right-side group reads left-to-right as Clock -> Signal -> TX
  -- battery, with the battery icon anchored at the far right.
  local sigIconSize = 20
  local sigX = txIconX - 12 - sigIconSize
  signalIconFn(t.signal)(sigX, topBarY + topBarH / 2 - sigIconSize / 2, sigIconSize)

  local clockW = 150
  local clockX = sigX - 12 - clockW
  do
    local ok, dt = pcall(getDateTime)
    if ok and dt then
      local clockText = string.format("%04d/%02d/%02d %02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min)
      lcd.drawText(clockX + clockW / 2, topBarY + topBarH / 2, clockText,
        CENTER + VCENTER + SMLSIZE + COLOR.white)
    end
  end

  -- Right after a disconnect: the flight summary, under the top bar
  -- (standby was handled above, before the top bar).
  if screenType == "flightlog" then
    drawFlightLog(wgt, topBarY + topBarH + pad, w, h)
    drawTransitionOverlay(wgt, w, h)
    return
  end

  -- Warnings, left side of the top bar up to the clock (~500px). Arm and
  -- Motor/Governor status used to sit here; they now live in the status
  -- tabs (row 2). The old strip under the footer only had ~3px left on
  -- 800x480, so it never drew anything. Several warnings rotate every 2s.
  do
    local warnings = {}
    if t.perCellVoltage and t.perCellVoltage < CONFIG.vCellWarn then
      warnings[#warnings + 1] = string.format("Low cell voltage: %.2fv", t.perCellVoltage)
    end
    if t.temp and t.temp >= CONFIG.escTempWarn then
      warnings[#warnings + 1] = string.format("Esc temp high: %d\194\176C", t.temp)
    end
    if #warnings > 0 then
      local idx = math.floor(getTime() / 200) % #warnings + 1
      lcd.drawFilledRectangle(pad + 12, topBarY + topBarH / 2 - 4, 8, 8, COLOR.red)
      lcd.drawText(pad + 26, topBarY + topBarH / 2, warnings[idx],
        LEFT + VCENTER + SMLSIZE + COLOR.red)
    end
  end

  -- Arming Disable Flags nonzero (any reason) -> this blocks flight
  -- entirely, so it gets the same "takes over the dashboard" treatment
  -- as the standby screen, instead of just a line in the small
  -- warnings strip. Triggers immediately, with no debounce/minimum
  -- sustain time (wgt.armWarningActive, computed in updateArmWarning).
  if wgt.armWarningActive then
    drawArmSwitchWarning(topBarY + topBarH + pad, w, h, t.armd)
    drawTransitionOverlay(wgt, w, h)
    return
  end

  -- Row 1: instrument cluster (option C) - Headspeed centered and
  -- large, flanked by Volt/Vcel on the left and Current/Bec volt on
  -- the right, all inside one wide bordered panel.
  -- NOTE ON SIZING: the flank cells are genuinely tight given this
  -- radio's real font metrics (measured via the diagnostic widget -
  -- see FONT_SPECS) - MIDSIZE alone needs ~42px of height, more than
  -- these compact stacked cells have room for once a label and a
  -- min/max subtext share the same box. fitFont automatically falls
  -- back to SMLSIZE there rather than overflow, so the flank numbers
  -- read smaller than the mockup implied; Headspeed itself doesn't
  -- have that problem since it has the whole center column to itself.
  local clusterY, clusterH = topBarY + topBarH + pad, math.floor(h * 0.32)
  drawChamferedRect(pad, clusterY, w - pad * 2, clusterH, COLOR.accentBorder, COLOR.bg, 8)
  drawChamferedRect(pad + 1, clusterY + 1, w - pad * 2 - 2, clusterH - 2, COLOR.accentPanel, COLOR.accentBorder, 7)

  -- Every readout in the cluster and in row 2 is a drawTab: label row on
  -- top (icon + dim label, min/max on the right), value below at up to
  -- MIDSIZE. Flank cells are 30% of the inner width each so "Current" +
  -- "max 80.0A" fit on one label row; Headspeed gets the remaining ~40%
  -- with the number at XXLSIZE and the unit beside it.
  local innerPad = 10
  local innerW = w - pad * 2 - innerPad * 2
  local flankW = math.floor(innerW * 0.3)
  local heroW = innerW - flankW * 2 - innerPad * 2
  local flankCellH = (clusterH - innerPad * 3) / 2
  local currentSub = wgt.maxCurrent and ("max " .. fmt(wgt.maxCurrent, 1) .. "A") or nil
  local voltSub = wgt.minVoltage and ("min " .. fmt(wgt.minVoltage, 1) .. "v") or nil
  local becSub = wgt.minBecVoltage and ("min " .. fmt(wgt.minBecVoltage, 1) .. "v") or nil

  local leftFlankX = pad + innerPad
  local flank1Y = clusterY + innerPad
  local flank2Y = flank1Y + flankCellH + innerPad
  local rightFlankX = leftFlankX + flankW + innerPad + heroW + innerPad
  local flanks = {
    { leftFlankX,  flank1Y, "Volt",     fmtUnit(t.voltage, 1, "v"),        voltSub,    voltIconFn },
    { leftFlankX,  flank2Y, "Vcel",     fmtUnit(t.perCellVoltage, 2, "v"), nil,        vcelIconFn },
    { rightFlankX, flank1Y, "Current",  fmtUnit(t.current, 1, "A"),        currentSub, currentIconFn },
    { rightFlankX, flank2Y, "Bec volt", fmtUnit(t.becV, 1, "v"),           becSub,     voltIconFn },
  }
  for i = 1, #flanks do
    local f = flanks[i]
    drawChamferedRect(f[1], f[2], flankW, flankCellH, COLOR.panel, COLOR.accentPanel, 4)
    drawTab(f[1], f[2], flankW, flankCellH, f[3], f[4], f[5], f[6])
  end

  local heroX = leftFlankX + flankW + innerPad
  do
    local heroY = clusterY + innerPad
    local heroH = clusterH - innerPad * 2
    local maxSub = wgt.maxHeadspeed and ("max " .. fmt(wgt.maxHeadspeed, 0)) or nil
    drawTab(heroX, heroY, heroW, TAB_LABEL_H, "Headspeed", nil, maxSub, governorIconFn)

    local num, unit = fmt(t.rpm, 0), "rpm"
    local numFont = fitFontMeasured(heroW - 60, heroH - TAB_LABEL_H, num, XXLSIZE)
    local numW, unitW = textWidth(num, numFont), textWidth(unit, SMLSIZE)
    local startX = heroX + (heroW - numW - 6 - unitW) / 2
    local cy = heroY + TAB_LABEL_H + (heroH - TAB_LABEL_H) / 2
    lcd.drawText(startX, cy, num, LEFT + VCENTER + numFont + COLOR.white)
    lcd.drawText(startX + numW + 6, cy + 18, unit, LEFT + VCENTER + SMLSIZE + COLOR.dim)
  end

  -- Row 2: status tabs - Arm | Governor | Flight | Profile/Rate, four
  -- equal drawTabs in one panel. Arm and Governor carry a color stripe
  -- on their left edge so state reads by color at a glance; Governor also stands in for the old "Motor On/Off" badge
  -- (falls back to Motor on/off from headspeed if there's no Gov sensor).
  -- Height 13.5% (64px) = label row 18 + MIDSIZE 42 + margin.
  local midY, midH = clusterY + clusterH + pad, math.floor(h * 0.135)
  do
    local panelW = w - pad * 2
    drawChamferedRect(pad, midY, panelW, midH, COLOR.panel, COLOR.bg, 6)
    local segW = math.floor(panelW / 4)

    local armValue, armColor = "N/a", COLOR.muted
    if t.armFlags ~= nil then
      local armed = math.floor(t.armFlags) % 2 == 1
      armValue = armed and "Armed" or "Disarmed"
      armColor = armed and COLOR.green or COLOR.grey
    end

    local govLabel, govValue, govColor = "Governor", nil, nil
    if t.gov then
      govValue, govColor = toSentenceCase(t.gov), getGovColor(t.gov)
    else
      local running = t.rpm and t.rpm > CONFIG.rpmRunningThreshold
      govLabel = "Motor"
      govValue = running and "On" or "Off"
      govColor = running and COLOR.green or COLOR.grey
    end

    local profileRateText
    if t.pidProfile and t.bank then
      profileRateText = fmt(t.pidProfile, 0) .. "/" .. fmt(t.bank, 0)
    elseif t.bank then
      profileRateText = fmt(t.bank, 0)
    elseif t.pidProfile then
      profileRateText = fmt(t.pidProfile, 0)
    else
      profileRateText = "--"
    end

    local tabs = {
      { "Arm",          armValue,                    armColor },
      { govLabel,       govValue,                    govColor },
      { "Flight",       fmtTime(wgt.flightSeconds),  nil, flightIconFn },
      { "Profile/Rate", profileRateText,             nil, bankIconFn },
    }
    for i = 1, 4 do
      local tab = tabs[i]
      local segX = pad + (i - 1) * segW
      local sw = (i == 4) and (panelW - segW * 3) or segW
      if i > 1 and not tab[3] then -- a color stripe already marks the edge
        lcd.drawFilledRectangle(segX, midY + 10, 1, midH - 20, COLOR.muted)
      end
      drawTab(segX + 4, midY + 2, sw - 8, midH - 4, tab[1], tab[2], nil, tab[4], tab[3])
    end
  end

  -- Row 3: battery - one big, prominent bar (unchanged from before).
  local row3Y, row3H = midY + midH + pad, math.floor(h * 0.18)
  local battRight
  if t.charge and t.capacity then
    battRight = fmt(t.charge, 0) .. "% / " .. fmt(t.capacity, 0) .. "mAh"
  elseif t.charge then
    battRight = fmtUnit(t.charge, 0, "%")
  elseif t.capacity then
    battRight = fmt(t.capacity, 0) .. "mAh"
  else
    battRight = "--"
  end
  drawChamferedRect(pad, row3Y, w - pad * 2, row3H, COLOR.panel, COLOR.bg, 8)
  drawStatBar(pad + 12, row3Y + 10, w - pad * 2 - 24, row3H - 18,
    "Battery", battRight, t.charge or 0, getChargeColor(t.charge), batteryLabelIconFn, true, COLOR.white, DBLSIZE)

  -- Row 4: footer - Throttle (left, wide) + model picture/name card
  -- (right). lcd.drawBitmap is confirmed (via the diagnostic widget)
  -- to correctly treat "scale" as a percentage on this radio - but
  -- getBitmapSize() is still not trustworthy for an arbitrary
  -- user-provided file, so the picture is still drawn at native 1:1
  -- size rather than computing a scale from a measured size. Pre-size
  -- the /IMAGES file itself to roughly fit this card (see the MODEL
  -- PICTURE note near the top of this file for the current target).
  local row4Y, row4H = row3Y + row3H + pad, math.floor(h * 0.15)
  local sideW = math.floor((w - pad * 3) * 0.26)
  local thrW = (w - pad * 3) - sideW

  local thrX = pad
  drawChamferedRect(thrX, row4Y, thrW, row4H, COLOR.panel, COLOR.bg, 7)
  do
    local throttleRight
    if t.throttle and t.temp then
      throttleRight = fmt(t.throttle, 0) .. "% / " .. fmt(t.temp, 0) .. "\194\176C"
    elseif t.throttle then
      throttleRight = fmtUnit(t.throttle, 0, "%")
    elseif t.temp then
      throttleRight = fmt(t.temp, 0) .. "\194\176C"
    else
      throttleRight = "--"
    end
    drawStatBar(thrX + 10, row4Y + 8, thrW - 20, row4H - 14, "Throttle", throttleRight,
      t.throttle or 0, COLOR.accent, throttleLabelIconFn, true, COLOR.white)
  end

  local sideX = thrX + thrW + pad
  drawChamferedRect(sideX, row4Y, sideW, row4H, COLOR.panel, COLOR.bg, 7)
  do
    -- Name goes in a fixed-height strip at the BOTTOM of the card (with
    -- its own background fill) instead of beside the image - the name
    -- text's x-position used to assume the image was a square exactly
    -- (row4H - padding) wide, but the real /IMAGES file is usually a
    -- landscape photo much wider than that, so the assumption was wrong
    -- and the name ended up overlapping the (wider-than-expected)
    -- picture. Stacking vertically removes any dependency on the
    -- image's actual width.
    local nameH = 20
    if CONFIG.showModelImage and wgt.modelBitmap then
      local imgX = sideX + math.floor((sideW - CONFIG.modelImageW) / 2)
      local imgY = row4Y + math.floor((row4H - nameH - CONFIG.modelImageH) / 2)
      pcall(function() lcd.drawBitmap(wgt.modelBitmap, imgX, imgY) end)
    end
    local modelName = (model and model.getInfo and model.getInfo().name) or ""
    lcd.drawFilledRectangle(sideX, row4Y + row4H - nameH, sideW, nameH, COLOR.panel)
    lcd.drawText(sideX + sideW / 2, row4Y + row4H - nameH / 2, modelName,
      CENTER + VCENTER + fitFont(sideW - 16, nameH, modelName, MIDSIZE) + COLOR.dim)
  end

  -- Same wipe-reveal used for every other screen change (see
  -- drawTransitionOverlay) - covers arriving at the dashboard from
  -- standby, flight log, or the arm warning screen alike.
  drawTransitionOverlay(wgt, w, h)
end

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
  if not playHaptic then return end
  for i = 1, #pattern do playHaptic(pattern[i][1], pattern[i][2]) end
end

-- Folder of the voice set chosen with the "Voice" option (0-based index
-- into CONFIG.alarm.voiceSets; out of range falls back to the first set).
local function voiceSetDir(wgt)
  local sets = CONFIG.alarm.voiceSets
  local idx = wgt.options and wgt.options.Voice
  idx = idx and math.floor(idx) or 0
  return sets[idx + 1] or sets[1]
end

-- voice: one file name, or a list played in order (e.g. { "batt020", "land" }).
local function alert(wgt, tier, voice)
  local cfg = CONFIG.alarm
  local muted = wgt.alarmMuted
  local files = (type(voice) == "table") and voice or { voice }
  for i = 1, #files do
    local path = cfg.dir .. voiceSetDir(wgt) .. "/" .. files[i] .. ".wav"
    if CONFIG.simulate then
      -- Simulator only: debug output plus /LOGS/rftelem_alarms.log, so a
      -- run can be checked from the SD folder without the debug window.
      local line = string.format("%.2f %s %s%s", getTime() / 100, tier, path, muted and " (muted)" or "")
      print("RFTelem alarm: " .. line)
      pcall(function()
        local f = io.open("/LOGS/rftelem_alarms.log", "a")
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

local function critical(wgt, key, isOn, voice)
  local a = wgt.alarm
  if not isOn then a.lastFire[key] = nil; return end
  local now = getTime()
  if not a.lastFire[key] or now - a.lastFire[key] >= CONFIG.alarm.repeatSec * 100 then
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
  a.prev[key] = value
  if (old ~= nil and old ~= value) or (old == nil and a.sayFirst[key]) then
    a.sayFirst[key] = nil
    fn(value)
  end
end

-- Landing threshold in % from the "BattLand" option (10-50), else CONFIG.
local function battLandPct(wgt)
  local v = wgt.options and wgt.options.BattLand
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
    if connected then
      alert(wgt, "info", "connected")
      a.sayFirst.arm, a.sayFirst.armd, a.sayFirst.bank, a.sayFirst.pid = true, true, true, true
    elseif wgt.alarmLink ~= nil then
      alert(wgt, wgt.wasRunning and "critical" or "info",
        wgt.wasRunning and "telemetry_lost" or "disconnected")
    end
    wgt.alarmLink = connected
  end
  if not connected then return end

  -- Critical
  local cellCrit = not cfg.nativeBackup and running and t.perCellVoltage ~= nil and
    latch(a, "cellCrit", t.perCellVoltage < cfg.cellCritical,
      t.perCellVoltage >= cfg.cellCritical + cfg.cellHyst, cfg.cellSustainSec)
  critical(wgt, "cellCrit", cellCrit, "cell_critical")

  -- "Battery NN%, land now": NN is the threshold rounded to the 5% voice
  -- files (batt005..batt100).
  local battCrit = not cfg.nativeBackup and running and t.charge ~= nil and t.charge <= landPct
  critical(wgt, "battCrit", battCrit,
    { string.format("batt%03d", math.floor(landPct / 5 + 0.5) * 5), "land" })

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

  -- Info. Arm state first, so right after "connected" the order is
  -- arm -> (arming blocked) -> bank -> profile.
  onChange(a, "arm", t.armFlags and (math.floor(t.armFlags) % 2 == 1), function(armed)
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
  onChange(a, "gov", govUpper, function(g)
    if not GOV_CRITICAL[g] then alert(wgt, "info", GOV_VOICE[g]) end -- critical above
  end)
  -- Bank = RTE# (rates profile, the V-bar "bank"), Profile = PID#.
  onChange(a, "bank", t.bank and math.floor(t.bank), function(b) alert(wgt, "info", "bank" .. b) end)
  onChange(a, "pid", t.pidProfile and math.floor(t.pidProfile), function(p) alert(wgt, "info", "profile" .. p) end)

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
end

-- Per-tick state update shared by refresh() and background(): read the
-- sensors, handle connect/disconnect, run every tracker and the alarms.
-- Returns the telemetry table and the link state for drawing.
local function tick(wgt)
  local t = readTelemetry(wgt)

  -- Reconnect detection: if the link just came back after being down,
  -- wipe accumulated state before anything else uses it this frame.
  local connected = isTelemetryConnected(t)
  if wgt.wasConnected and not connected then
    -- Just disconnected after a real connection (not the initial
    -- power-up state) - that's the one moment the flight log should
    -- show fresh.
    wgt.showFlightLog = true
  end
  if connected and not wgt.wasConnected then
    resetTelemetryState(wgt)
    t = readTelemetry(wgt) -- re-read with the freshly cleared sensor cache
  end
  wgt.wasConnected = connected

  local running = updateFlightTimer(wgt, t)
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
  wgt.wasRunning = running and connected

  -- Track when this disconnect started, so the flight log can
  -- auto-dismiss after a timeout - this is what makes the dismiss
  -- behavior work even in a zone that never receives touch events.
  if not connected then
    if not wgt.disconnectTime then
      wgt.disconnectTime = getTime()
    end
    local disconnectedSec = (getTime() - wgt.disconnectTime) / 100
    if disconnectedSec > CONFIG.flightLogTimeoutSec then
      wgt.showFlightLog = false
    end
  else
    wgt.disconnectTime = nil
  end

  -- "Close" option (e.g. the SH momentary button): a press - rising edge,
  -- so a switch already held at disconnect doesn't count - closes the
  -- flight log. Polled here, so it works without full-screen mode, which
  -- is the only mode where touch/key events reach a widget.
  local closeOn = sourceActive(wgt.options and wgt.options.Close)
  if closeOn and not wgt.closeWasOn and not connected then
    wgt.showFlightLog = false
  end
  wgt.closeWasOn = closeOn
  return t, connected
end

-- Called by EdgeTX while the widget is NOT on screen: keep the trackers,
-- flight samples and alarms running.
local function background(wgt)
  tick(wgt)
end

local function refresh(wgt, event, touchState)
  -- Apply the radio-side "Theme" widget option (0/1/2), if set -
  -- reassigning the COLOR upvalue here means every helper function
  -- below (all of which read COLOR.xxx) picks up the change for this
  -- frame, without needing to thread a theme parameter through each
  -- one individually.
  do
    local idx = (wgt.options and wgt.options.Theme) or nil
    if idx ~= nil then
      idx = math.floor(idx)
      if idx < 0 or idx > 2 then idx = 0 end
      COLOR = COLOR_THEMES[THEME_NAMES[idx + 1]] or COLOR_THEMES.color
    end
  end

  local t, connected = tick(wgt)
  ensureModelImage(wgt)
  ensureTxBatteryIcons(wgt)

  -- A tap or Enter while showing the flight log dismisses it, in favor of
  -- the standby screen, for the rest of this disconnect - only ever
  -- delivered when the widget is full-screen (see the FLIGHT LOG note
  -- near the top of this file). Elsewhere, the "Close" option's switch
  -- (tick()) or the timeout dismisses it instead.
  if not connected and event and event ~= 0 and
     (event == EVT_TOUCH_TAP or event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK) then
    wgt.showFlightLog = false
  end

  local w, h = wgt.zone.w, wgt.zone.h

  if h < 60 then
    drawSmall(wgt, t, w, h)
  elseif h < 160 then
    drawMedium(wgt, t, w, h)
  else
    drawLarge(wgt, t, w, h)
  end
end

-- ============================== REGISTER ==================================

-- "Theme" shows up as a plain number (0/1/2) on the radio's own widget
-- edit screen (long-press the widget -> Edit) - EdgeTX widget options
-- have no string/enum picker, only VALUE/COLOR/SOURCE/BOOL, so there's
-- no way to show "color"/"mono"/"cyan" as labelled choices there. The
-- mapping (0=color, 1=mono, 2=cyan) is documented here and in THEME_NAMES
-- above; refresh() reads this option every frame and swaps the active
-- COLOR table accordingly, falling back to CONFIG.theme above if the
-- option is missing (older EdgeTX) or out of range.
-- "Mute" picks any source (e.g. switch SA, or a logical switch): voice
-- alarms are silenced while its value is > 0 (switch down / LS true).
-- Leave it empty for never-muted. The critical haptic is never muted.
-- "Voice" picks the alarm voice set (index into CONFIG.alarm.voiceSets):
-- 0=No.7 announce, 1=Aoyama Ryusei, 2=Kurono Takehiro, 3=Meimei Himari,
-- 4=Voidoll, 5=Zundamon.
-- "Close" picks a source (e.g. the SH momentary button) that closes the
-- flight log when pressed - works even when the widget isn't full-screen.
-- "BattLand" is the remaining-% that triggers the repeating "battery NN%,
-- land now" alarm (10-50, default 20).
local options = {
  { "Theme", VALUE, 0, 0, 2 }, -- 0=color, 1=mono, 2=cyan
  { "Mute", SOURCE, 0 },
  { "Voice", VALUE, 0, 0, 5 },
  { "Close", SOURCE, 0 },
  { "BattLand", VALUE, 20, 10, 50 },
}

return {
  name = "RF Telem",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background,
}
