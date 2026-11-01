--[[
  Rotorflight Telemetry Dashboard Widget for EdgeTX (Color LCD)
  ----------------------------------------------------------------
  License: GNU GPL v3.0 (see LICENSE in the project root). The RF
  TELEMETRY section (CRSF custom telemetry decoder, sensor table and MSP
  framing) is ported from rotorflight-lua-scripts
  (https://github.com/rotorflight/rotorflight-lua-scripts, GPL-3.0).
  This program comes with ABSOLUTELY NO WARRANTY.

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

  -- Official tools hosted full-screen inside the widget (see TOOLS HOST):
  -- Rotorflight's own Lua (installed under /SCRIPTS/RF2/, lcd UI) and the
  -- ExpressLRS Lua tool - the first ELRS path that exists is used.
  perfOverlay = true, -- fps / ms per frame / Lua KB, bottom-right (speed check on the radio)
  -- lvgl widget (EdgeTX 2.11+): only what changes is redrawn - measured
  -- 12-20 fps vs 4-6 fps for the lcd drawing on the TX16S MK3 (LVGL VIEW)
  lvgl = true,
  tools = {
    rf2Dir = "/SCRIPTS/RF2/",
    rf2Skin = true, -- RF2 drawn in this widget's theme with touch (false = RF2's plain lcd look)
    elrs   = { "/SCRIPTS/TOOLS/elrs.lua", "/SCRIPTS/TOOLS/elrsV3.lua",
               "/SCRIPTS/TOOLS/ExpressLRS.lua", "/SCRIPTS/TOOLS/ELRS.lua" },
  },

  -- Battery-profile picker shown right after connecting (see BATTERY
  -- PROFILE below). Labels are free text for the 6 FC profiles, e.g.
  -- "6S 5000" - the widget only sends the profile number.
  batteryProfile = {
    enabled     = true,
    labels      = { "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5", "Profile 6" },
    timeoutSec  = 15,   -- no input this long: keep the current profile
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
    },
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
  wgt.modelBitmap, wgt.modelImagePath = nil, nil
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

-- ============================== USER SETTINGS =============================
-- Settings changed on the radio by touch (Menu > Settings, full screen),
-- kept on the SD card in SET.file as key=value lines and loaded at
-- start. A value set here wins over the matching widget option (Theme,
-- Voice, BattLand) and over CONFIG. To add a setting: one entry in
-- SETTINGS (group = the tab it shows in), with apply() putting the value
-- where the code reads it; the Settings screen (LVGL VIEW) lists it.
local SET = {}
SET.file = "/WIDGETS/RFTelem/settings.txt"
local USER = {}
SET.groups = { "Voice", "Alarms", "Display" }
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
}

-- current value: the user's, else the widget option, else the default
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
    for key, val in string.gmatch(text, "([%w_]+)=([%-%d%.]+)") do
      for _, def in ipairs(SETTINGS) do
        if def.key == key then
          local n = tonumber(val)
          if n then USER[key] = (def.kind == "bool") and (n ~= 0) or n end
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
  end
  USER[def.key] = v
  if def.apply then def.apply(v) end
  SET.save()
end

function SET.text(wgt, def)
  local v = SET.value(wgt, def)
  if def.kind == "bool" then return v and "On" or "Off" end
  if def.kind == "choice" then return def.choices[(v or 0) + 1] or def.choices[1] end
  if v == nil then return "--" end
  return string.format("%." .. (def.decimals or 0) .. "f", v) .. (def.unit or "")
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

-- Touch and keys only reach a widget in full-screen mode, and Lua can't
-- enter it (EdgeTX 2.12 lua/api_colorlcd_lvgl.cpp only has isAppMode /
-- isFullScreen / exitFullScreen). In the "App mode" screen layout a long
-- ENTER press makes the widget full-screen (gui/colorlcd/mainview/
-- view_main.cpp onLongPress) - verified in the 2.12 simulator, where a
-- tile tap then reached the picker; leave with a long RTN press. Returns
-- a hint to show while touch isn't live, else nil (also nil when the lvgl
-- API isn't there to ask).
local function touchHint()
  if not (lvgl and lvgl.isFullScreen) then return nil end
  local ok, full = pcall(lvgl.isFullScreen)
  if not ok or full then return nil end
  local okApp, app = pcall(function() return lvgl.isAppMode and lvgl.isAppMode() end)
  if okApp and app then return "Hold ENTER to enable touch" end
  return "Touch needs full screen (App mode layout)"
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
  lcd.drawText(pad + panelW - 16, sy + 22, touchHint() or "Power on the model",
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
  local voiceIdx = math.floor(USER.voice or (wgt.options and wgt.options.Voice) or 0)
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
    local decimals = (isWhole(d.step) and isWhole(d.bottom)) and 0 or 1
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

-- Battery-profile picker (state in wgt.bp, see BATTERY PROFILE): title
-- strip with the status, the 6 FC profiles as a 3x2 tile grid (current
-- one tagged, highlighted one outlined in the accent color), and a hint
-- strip for the inputs. Tile rects go to wgt.bpTiles for touch.
local function drawBattSelect(wgt, t, y, w, h)
  lcd.drawFilledRectangle(0, y, w, h - y, COLOR.bg)
  local pad, bp, cfg = 12, wgt.bp, CONFIG.batteryProfile
  local panelW = w - pad * 2
  local now = getTime()

  local titleH = 40
  drawChamferedRect(pad, y, panelW, titleH, COLOR.panel, COLOR.bg, 6)
  lcd.drawText(pad + 14, y + titleH / 2, "Battery profile", LEFT + VCENTER + MIDSIZE + COLOR.white)
  local status, statusColor = "Select before flight", COLOR.dim
  if bp.phase == "send" then
    status = "Applying " .. bp.target .. "..."
  elseif bp.phase == "done" then
    if bp.result == "fail" then
      status, statusColor = "No change - FC did not respond", COLOR.red
    else
      status, statusColor = "Profile " .. (t.battProfile or bp.sel) .. " set", COLOR.green
    end
  end
  lcd.drawText(pad + panelW - 14, y + titleH / 2, status, RIGHT + VCENTER + SMLSIZE + statusColor)

  local hintH = 40
  local gridY = y + titleH + pad
  local gridH = h - pad - hintH - pad - gridY
  local gap = 10
  local tileW = math.floor((panelW - gap * 2) / 3)
  local tileH = math.floor((gridH - gap) / 2)
  wgt.bpTiles = {}
  for i = 1, 6 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local tx, ty = pad + col * (tileW + gap), gridY + row * (tileH + gap)
    wgt.bpTiles[i] = { tx, ty, tileW, tileH }
    local selected = (bp.sel == i)
    if selected then
      -- accent, not accentBorder: the latter is a near-background grey in
      -- the color theme and the highlight didn't show in the simulator
      drawChamferedRect(tx, ty, tileW, tileH, COLOR.accent, COLOR.bg, 6)
      drawChamferedRect(tx + 3, ty + 3, tileW - 6, tileH - 6, COLOR.accentPanel, COLOR.accent, 5)
    else
      drawChamferedRect(tx, ty, tileW, tileH, COLOR.panel, COLOR.bg, 6)
    end
    lcd.drawText(tx + 18, ty + tileH / 2 - 12, tostring(i),
      LEFT + VCENTER + DBLSIZE + (selected and COLOR.white or COLOR.dim))
    local label = cfg.labels[i] or ("Profile " .. i)
    local cap = wgt.battCaps and wgt.battCaps[i]
    if cap and cap > 0 then -- FC capacity, after the label if one was set
      label = (label ~= "Profile " .. i) and (label .. "  " .. cap .. "mAh") or (cap .. "mAh")
    end
    lcd.drawText(tx + 18, ty + tileH - 22, label,
      LEFT + VCENTER + fitFontMeasured(tileW - 30, 27, label, SMLSIZE) + (selected and COLOR.white or COLOR.dim))
    if t.battProfile == i then
      lcd.drawText(tx + tileW - 12, ty + 16, "current", RIGHT + VCENTER + SMLSIZE + COLOR.green)
    end
  end

  local hy = h - pad - hintH
  drawChamferedRect(pad, hy, panelW, hintH, COLOR.panel, COLOR.bg, 6)
  local hint
  if bp.phase == "pick" then
    local left = cfg.timeoutSec - math.floor((now - (bp.lastInput or bp.since)) / 100)
    if bp.stepped and bp.srcLast then
      left = cfg.applyIdleSec - math.floor((now - bp.lastInput) / 100)
      hint = "Selector: profile " .. bp.sel .. "  -  applies in " .. math.max(0, left) .. "s  -  move it to change"
    elseif bp.stepped then
      left = cfg.applyIdleSec - math.floor((now - bp.lastInput) / 100)
      hint = "Applies " .. bp.sel .. " in " .. math.max(0, left) .. "s  -  press again for the next"
    elseif touchHint() then
      hint = "Close switch: next profile  -  " .. touchHint() .. "  -  " .. math.max(0, left) .. "s"
    else
      hint = "Tap a profile, or press the Close switch to step  -  keeps current in " .. math.max(0, left) .. "s"
    end
  else
    hint = "Arming closes this screen"
  end
  lcd.drawText(pad + 14, hy + hintH / 2, hint,
    LEFT + VCENTER + fitFontMeasured(panelW - 28, 23, hint, SMLSIZE) + COLOR.dim)
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
  elseif wgt.bp and wgt.bp.phase ~= "wait" then
    screenType = "battselect"
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
  if screenType == "battselect" then
    drawBattSelect(wgt, t, topBarY + topBarH + pad, w, h)
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
  -- The FC's active battery profile (BAT#) rides on the bar label:
  -- "Battery #2", plus its CONFIG label when one was set ("#2 6S 5000").
  -- drawStatBar's fitFont steps the font down if that gets long.
  local battLabel = "Battery"
  if t.battProfile then
    battLabel = "Battery #" .. t.battProfile
    local cap = wgt.battCaps and wgt.battCaps[t.battProfile]
    local custom = CONFIG.batteryProfile.labels[t.battProfile]
    if cap and cap > 0 then
      battLabel = battLabel .. " " .. cap .. "mAh" -- read from the FC (RF TELEMETRY)
    elseif custom and custom ~= "Profile " .. t.battProfile then
      battLabel = battLabel .. " " .. custom
    end
  end
  drawChamferedRect(pad, row3Y, w - pad * 2, row3H, COLOR.panel, COLOR.bg, 8)
  drawStatBar(pad + 12, row3Y + 10, w - pad * 2 - 24, row3H - 18,
    battLabel, battRight, t.charge or 0, getChargeColor(t.charge), batteryLabelIconFn, true, COLOR.white, DBLSIZE)

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
      local f = io.open("/LOGS/rftelem_alarms.log", "a")
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
  if not wgt.fcApi and rt.capTries < 6 then
    if mspRequest(MSP_API_VERSION, {}) then rt.capAskedAt, rt.capTries = now, rt.capTries + 1 end
    return
  end
  if not cfg.readCapacities or wgt.battCaps or rt.capTries >= 12 then return end
  if mspRequest(MSP_BATTERY_CONFIG, {}) then rt.capAskedAt, rt.capTries = now, rt.capTries + 1 end
end

local function newRfTelemetryState(wgt)
  local rt = { count = 0, skip = 0, capTries = 0 }
  rt.onReply = function(cmd, buf, isError)
    if cmd == MSP_BATTERY_CONFIG and not isError then wgt.battCaps = parseBatteryConfig(buf) end
    if (cmd == 112 or cmd == 111 or cmd == 148) and not isError then
      wgt.fc = wgt.fc or {}
      wgt.fc[cmd] = buf
    end
    if cmd == MSP_API_VERSION and not isError and #buf >= 3 then
      wgt.fcApi = buf[2] + buf[3] / 100 + 0.00001 -- as RF2's MSP/mspApiVersion.lua
      rt.capTries = 0
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
    elseif now - (bp.lastInput or bp.since) >= cfg.timeoutSec * 100 then
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
    -- show fresh.
    wgt.showFlightLog = true
  end
  if connected and not wgt.wasConnected then
    resetTelemetryState(wgt)
    t = readTelemetry(wgt) -- re-read with the freshly cleared sensor cache
    bpStart(wgt)
    wgt.battCaps, wgt.fcApi, wgt.rt.capTries, wgt.rt.capAskedAt = nil, nil, 0, nil
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
  bpUpdate(wgt, t, connected)
  rfMspUpdate(wgt, connected)

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
  -- flight log, or steps the battery-profile picker to the next profile.
  -- Polled here, so it works without full-screen mode, which is the only
  -- mode where touch/key events reach a widget.
  local closeOn = sourceActive(wgt.options and wgt.options.Close)
  if closeOn and not wgt.closeWasOn then
    if not connected then
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
  return t, connected
end

-- Called by EdgeTX while the widget is NOT on screen: keep the trackers,
-- flight samples and alarms running.
local function background(wgt)
  tick(wgt)
end

-- ============================== TOOLS HOST ================================
-- The official Rotorflight (RF2) and ExpressLRS Lua tools run inside this
-- widget while it is full-screen, opened from a small menu (ENTER or a tap
-- on standby / dashboard, disarmed only). They are the scripts installed
-- on the SD card, called as-is:
--   RF2:  what /SCRIPTS/RF2/tool.lua does, but always with the lcd UI
--         (ui_lcd.lua) because this widget draws with lcd.*; its run(event)
--         returns 2 on exit. Editing and saving to the FC are RF2's own.
--   ELRS: { init, run(event, touchState) }, non-zero return = exit.
-- While a tool runs, rfTelemetryPump stands down so the tool's own
-- crossfireTelemetryPop gets every reply. Arming, or leaving full-screen
-- (no keys would reach the tool any more), closes it at once.

-- ---------------------------- RF2 GUI skin -------------------------------
-- RF2's lcd UI (ui_lcd.lua) keeps all the logic - MSP reads/writes, Save
-- (EEPROM write), Reload, Reboot, Acc Cal - and draws through six small
-- modules: LCD/shared, waitMessage, messageBox, popupMenu, mainMenu, page.
-- rf2SkinInstall swaps those six for the versions below, which draw in
-- this widget's theme with touch targets (adapted from rotorflight-lua-
-- scripts, GPL-3.0). Touch is turned into what ui_lcd already understands:
-- each frame the modules register tap targets in RF2UI.hits; a tap runs
-- the target's fn and/or hands ui_lcd its key event (ENTER, EXIT, ...).
-- The page layout (x/y of every label and field) is RF2's own 800x480
-- template, moved below the title bar.

local RF2_TOP = 60          -- content starts below the 56px title bar
local RF2_ROW = 30          -- RF2's 800x480 line spacing
local RF2UI = { hits = {}, nHits = 0, fonts = {}, nFonts = 0 }

-- Tap targets live in a pool reused every frame (no per-frame tables or
-- closures: the radio's Lua heap is small and GC work costs frame time).
local function rf2Hit(x, y, w, h, fn, ev, arg)
  local n = RF2UI.nHits + 1
  RF2UI.nHits = n
  local hit = RF2UI.hits[n]
  if not hit then hit = {}; RF2UI.hits[n] = hit end
  hit[1], hit[2], hit[3], hit[4], hit[5], hit[6], hit[7] = x, y, w, h, fn, ev, arg
end

-- MIDSIZE when every text fits the width, else the default font for all
-- (one size per group, so tiles/buttons don't mix sizes).
local function rf2Font(w, texts)
  for i = 1, #texts do
    if textWidth(texts[i], MIDSIZE) > w then return 0 end
  end
  return MIDSIZE
end

local function rf2Button(x, y, w, h, label, bg, fn, ev, active, font, arg)
  drawChamferedRect(x, y, w, h, active and COLOR.accentPanel or COLOR.barBg, bg, 5)
  if active then lcd.drawFilledRectangle(x + 8, y + h - 5, w - 16, 3, COLOR.accent) end
  lcd.drawText(x + w / 2, y + h / 2, label, CENTER + VCENTER + (font or 0) + COLOR.white)
  rf2Hit(x, y, w, h, fn, ev, arg)
end

local function rf2Quit() RF2UI.quit = true end

-- Background + title bar: Back (EXIT), title, page arrows, Menu (the
-- Save / Reload / Reboot / Acc Cal popup that ENTER-long opens).
local function rf2Frame(title, kind, keepBg)
  if not keepBg then lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, COLOR.bg) end
  lcd.drawFilledRectangle(0, 0, LCD_W, RF2_TOP - 4, COLOR.panel)
  lcd.drawFilledRectangle(0, RF2_TOP - 5, LCD_W, 1, COLOR.accentBorder)
  local quit = (kind == "init") and rf2Quit or nil
  rf2Button(8, 6, 104, 44, "< Back", COLOR.panel, quit, EVT_VIRTUAL_EXIT)
  local right = LCD_W - 8
  if kind ~= "init" and EVT_VIRTUAL_ENTER_LONG then
    right = right - 104
    rf2Button(right, 6, 104, 44, "Menu", COLOR.panel, nil, EVT_VIRTUAL_ENTER_LONG)
  end
  if kind == "page" and EVT_VIRTUAL_PREV_PAGE and EVT_VIRTUAL_NEXT_PAGE then
    right = right - 8 - 60
    rf2Button(right, 6, 60, 44, ">", COLOR.panel, nil, EVT_VIRTUAL_NEXT_PAGE)
    right = right - 8 - 60
    rf2Button(right, 6, 60, 44, "<", COLOR.panel, nil, EVT_VIRTUAL_PREV_PAGE)
  end
  local tw = right - 8 - 124
  lcd.drawText(124, RF2_TOP / 2 - 2, title or "",
    LEFT + VCENTER + fitFontMeasured(tw, 44, title or "", MIDSIZE) + COLOR.white)
end

local function rf2Card(w, h, title)
  local x, y = math.floor((LCD_W - w) / 2), math.floor((LCD_H - h) / 2)
  drawChamferedRect(x, y, w, h, COLOR.accent, COLOR.bg, 8)
  drawChamferedRect(x + 2, y + 2, w - 4, h - 4, COLOR.panel, COLOR.accent, 7)
  if title then lcd.drawText(x + 20, y + 28, title, LEFT + VCENTER + MIDSIZE + COLOR.white) end
  return x, y
end

local function rf2Multiline(x, y, text, flags)
  for line in string.gmatch(text or "", "([^\n]+)") do
    lcd.drawText(x, y, line, flags)
    y = y + RF2_ROW
  end
end

local function rf2SkinShared()
  return {
    backgroundFill = COLOR.bg,
    getLineSpacing = function() return RF2_ROW end,
    drawTextMultiline = function(x, y, text) rf2Multiline(x + 16, y, text, COLOR.white) end,
    clipValue = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end,
    forceReload = false,
    textOptions = COLOR.white,
    foregroundColor = COLOR.muted,
    killEnterBreak = false,
    -- only ui_lcd's init screen ("Waiting for connection") calls this
    drawScreenTitle = function(title) rf2Frame(title, "init") end,
    pageStatus = { display = 1, editing = 2, saving = 3, eepromWrite = 4, rebooting = 5 },
  }
end

local function rf2SkinWait(shared)
  local t = { text = nil }
  t.update = function()
    if not t.text then return end
    rf2Hit(0, 0, LCD_W, LCD_H) -- modal: swallow taps while saving
    local x, y = rf2Card(420, 110)
    lcd.drawText(x + 210, y + 55, t.text, CENTER + VCENTER + DBLSIZE + COLOR.white)
  end
  return t
end

local function rf2SkinMessage(shared)
  local msg
  local function close() msg = nil; shared.forceReload = true end
  local function update(event)
    if not msg then return false end
    rf2Frame(msg.title, "msg")
    local x, y = rf2Card(560, 300, msg.title)
    rf2Multiline(x + 24, y + 70, msg.text, COLOR.white)
    rf2Hit(0, 0, LCD_W, LCD_H)
    rf2Button(x + 200, y + 230, 160, 52, "OK", COLOR.panel, close, nil, true, MIDSIZE)
    if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then close() end
    return true
  end
  return { show = function(title, text) msg = { title = title, text = text } end, update = update }
end

local function rf2SkinPopup(shared)
  local t, active = {}, 1
  t.show = function(menu) t.menu, active = menu, 1 end
  t.update = function(event)
    if not t.menu then return false end
    if RF2UI.backdrop then RF2UI.backdrop() end
    local items = t.menu.items
    local rowH = 60
    local x, y = rf2Card(420, 56 + #items * (rowH + 8) + 12, "Menu")
    rf2Hit(0, 0, LCD_W, LCD_H, function() t.menu = nil end) -- tap outside closes
    for i = 1, #items do
      local item = items[i]
      rf2Button(x + 14, y + 56 + (i - 1) * (rowH + 8), 392, rowH, item.text, COLOR.panel,
        function() t.menu = nil; item.click() end, nil, i == active, MIDSIZE)
    end
    if event == EVT_VIRTUAL_EXIT then
      t.menu = nil
    elseif event == EVT_VIRTUAL_PREV then
      active = math.max(1, active - 1)
    elseif event == EVT_VIRTUAL_NEXT then
      active = math.min(#items, active + 1)
    elseif event == EVT_VIRTUAL_ENTER then
      if shared.killEnterBreak then
        shared.killEnterBreak = false
      else
        local item = items[active]
        t.menu = nil
        item.click()
      end
    end
    return true
  end
  return t
end

-- Main menu: the page list as a 3-column grid of tiles.
local function rf2SkinMainMenu(shared, pageFiles, selected)
  local t = {}
  local COLS, TW, TH, GAP = 3, 252, 52, 8
  local firstRow = 0
  local rowsShown = math.floor((LCD_H - RF2_TOP - 6 + GAP) / (TH + GAP))
  local titles = {}
  for i = 1, #pageFiles do titles[i] = pageFiles[i].title end
  local font = rf2Font(TW - 28, titles)
  local function selectPage(i) selected = i end
  local slide = function(ts)
    local dy = ts.slideY or 0
    local maxFirst = math.max(0, math.ceil(#pageFiles / COLS) - rowsShown)
    firstRow = math.max(0, math.min(maxFirst, firstRow - math.floor(dy / (TH + GAP) + 0.5)))
    selected = math.max(selected, firstRow * COLS + 1)
    selected = math.min(selected, (firstRow + rowsShown) * COLS, #pageFiles)
  end
  local function draw()
    rf2Frame("Rotorflight " .. rf2.luaVersion, "main")
    local selRow = math.floor((selected - 1) / COLS)
    if selRow < firstRow then firstRow = selRow end
    if selRow >= firstRow + rowsShown then firstRow = selRow - rowsShown + 1 end
    for i = 1, #pageFiles do
      local row = math.floor((i - 1) / COLS) - firstRow
      if row >= 0 and row < rowsShown then
        local x = 10 + ((i - 1) % COLS) * (TW + GAP)
        local y = RF2_TOP + 4 + row * (TH + GAP)
        local sel = (i == selected)
        drawChamferedRect(x, y, TW, TH, sel and COLOR.accentPanel or COLOR.panel, COLOR.bg, 5)
        if sel then lcd.drawFilledRectangle(x, y + 6, 4, TH - 12, COLOR.accent) end
        local title = pageFiles[i].title
        lcd.drawText(x + 16, y + TH / 2, title, LEFT + VCENTER + font + COLOR.white)
        rf2Hit(x, y, TW, TH, selectPage, EVT_VIRTUAL_ENTER, i)
      end
    end
    RF2UI.backdrop = draw
    RF2UI.slide = slide
  end
  t.update = function(event)
    draw()
    if event == EVT_VIRTUAL_NEXT then
      selected = selected % #pageFiles + 1
    elseif event == EVT_VIRTUAL_PREV then
      selected = (selected - 2) % #pageFiles + 1
    end
  end
  t.getSelectedPageIndex = function() return selected end
  return t
end

-- One RF2 page as cards. RF2 places labels and fields at absolute x/y;
-- rf2CardModel groups them by row: a lone label starts a card (section),
-- a row of labels starts a table (PID gains, rates - column headings,
-- then one row heading + cells per row), fields with their own text are
-- label + value tiles, 3 per row (the dashboard's tab look). Tap a tile
-- to edit it in the panel at the bottom: slider, -10 -1 +1 +10, OK, or one
-- button per choice for short lists. The rotary works as in RF2. Editing
-- rules (limits, mult, change/preEdit/postEdit) are LCD/page.lua's.
local RF2_TILE_H, RF2_CELL_H, RF2_GAP = 62, 46, 8
local RF2_PANEL_Y = 296  -- edit panel top
local RF2_CARD_W = (LCD_W or 800) - 20

local function rf2CardModel(Page)
  local labels, fields = Page.labels or {}, Page.fields or {}
  local model = { fields = Page.fields, nF = #fields, nL = #labels, pos = {}, name = {} }
  local rows = {}
  local function rowAt(y)
    for i = 1, #rows do if math.abs(rows[i].y - y) < 6 then return rows[i] end end
    local r = { y = y, labels = {}, fields = {} }
    rows[#rows + 1] = r
    return r
  end
  for i = 1, #labels do
    local l = labels[i]
    if type(l.t) == "string" and l.t ~= "" then local r = rowAt(l.y); r.labels[#r.labels + 1] = l end
  end
  for i = 1, #fields do local r = rowAt(fields[i].y); r.fields[#r.fields + 1] = i end
  table.sort(rows, function(a, b) return a.y < b.y end)
  local function fx(i) return fields[i].sp or fields[i].x end

  local cards, card = {}, nil
  local function newCard(title, kind)
    card = { title = title, kind = kind, items = {}, cols = {}, rows = {} }
    cards[#cards + 1] = card
  end
  for _, r in ipairs(rows) do
    table.sort(r.labels, function(a, b) return a.x < b.x end)
    table.sort(r.fields, function(a, b) return fx(a) < fx(b) end)
    if #r.fields == 0 and #r.labels >= 2 then
      -- column headings; a second heading row right after adds a 2nd line
      if not (card and card.kind == "table" and #card.rows == 0) then
        if card and #card.items == 0 and #card.rows == 0 then card.kind = "table" else newCard(nil, "table") end
      end
      for _, l in ipairs(r.labels) do
        local col
        for _, c in ipairs(card.cols) do if math.abs(c.x - l.x) < 20 then col = c end end
        if col then col.b = l else card.cols[#card.cols + 1] = { x = l.x, a = l } end
      end
    elseif #r.fields == 0 and card and card.title and card.kind == "items"
           and r.labels[1].x > card.title.x + 5 then
      -- indented text under a heading is a value (e.g. Status: flags, free space)
      card.items[#card.items + 1] = { l = r.labels[1] }
    elseif #r.fields == 0 then
      newCard(r.labels[1], "items")
    elseif card and card.kind == "table" and #card.cols > 0 and not fields[r.fields[1]].t then
      local cells = {}
      for _, i in ipairs(r.fields) do
        local best, bestD = 1, math.huge
        for k, c in ipairs(card.cols) do
          local d = math.abs(c.x - fields[i].x)
          if d < bestD then best, bestD = k, d end
        end
        cells[#cells + 1] = { i = i, col = best }
      end
      local head = r.labels[1]
      for _, cell in ipairs(cells) do
        local col = card.cols[cell.col]
        model.name[cell.i] = (head and head.t or "") .. (col and (" " .. col.a.t) or "")
      end
      card.rows[#card.rows + 1] = { head = head, cells = cells }
    else
      if not card or card.kind == "table" then newCard(nil, "items") end
      local named = true -- every field brings its own text: labels here are values
      for _, i in ipairs(r.fields) do
        if not fields[i].t then named = false end
      end
      if named then
        for _, l in ipairs(r.labels) do card.items[#card.items + 1] = { l = l } end
      end
      for _, i in ipairs(r.fields) do
        card.items[#card.items + 1] = { i = i }
        local head = (not named and r.labels[1]) or card.title
        model.name[i] = head and head.t or nil
      end
    end
  end

  -- layout, relative to the top of the scrolling content
  local y = 0
  local tileW = math.floor((RF2_CARD_W - 20 - 2 * RF2_GAP) / 3)
  for _, c in ipairs(cards) do
    c.y = y
    local h = c.title and 38 or 10
    if c.kind == "items" then
      for k, it in ipairs(c.items) do
        local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
        local rect = { 20 + col * (tileW + RF2_GAP), y + h + row * (RF2_TILE_H + RF2_GAP), tileW, RF2_TILE_H }
        if it.i then model.pos[it.i] = rect else it.rect = rect end
      end
      h = h + math.ceil(#c.items / 3) * (RF2_TILE_H + RF2_GAP)
    else
      local n = math.max(#c.cols, 1)
      local headW = 110
      local cellW = math.floor((RF2_CARD_W - 20 - headW - (n - 1) * 6) / n)
      c.headY, c.cellW, c.cellX = y + h, cellW, 20 + headW
      if #c.cols > 0 then h = h + 28 end
      for r, row in ipairs(c.rows) do
        row.y = y + h + (r - 1) * (RF2_CELL_H + 6)
        for _, cell in ipairs(row.cells) do
          model.pos[cell.i] = { c.cellX + (cell.col - 1) * (cellW + 6), row.y, cellW, RF2_CELL_H }
        end
      end
      h = h + #c.rows * (RF2_CELL_H + 6)
    end
    c.h = h + 4
    y = y + c.h + RF2_GAP
  end
  model.cards, model.height = cards, y
  return model
end

local function rf2SkinPage(shared, Page)
  local t = {}
  local current, scrollY, lastCurrent, lastEditing = 1, 0, nil, false
  local status = shared.pageStatus
  local model

  local function isButton(f) return f.t and string.sub(f.t, 1, 1) == "[" and not f.data end

  local function valueText(f)
    if isButton(f) then return (string.gsub(f.t, "[%[%]]", "")) end
    local val = "---"
    if f.data and f.data.value ~= nil then
      val = f.data.value
      if type(val) == "number" then
        if f.data.scale then val = val / f.data.scale end
        if (f.data.scale or 1) <= 1 then val = math.floor(val) end
      end
      if type(f.data.table) == "table" and f.data.table[val] then val = f.data.table[val] end
    end
    return tostring(val) .. ((f.data and f.data.unit) or "")
  end

  local function setValue(v)
    local f = Page.fields[current]
    if f.data and type(f.data.value) == "number" then
      local mult = f.data.mult or 1
      v = math.max(f.data.min or 0, math.min(f.data.max or 255, v))
      f.data.value = math.floor(v / mult + 0.5) * mult
    end
    if f.change then f:change(Page) end
  end

  local function incValue(inc)
    local f = Page.fields[current]
    if f.data and type(f.data.value) == "number" then
      setValue(f.data.value + inc * (f.data.mult or 1))
    elseif f.change then
      f:change(Page)
    end
  end

  local function requestPage()
    if not Page.reqTS or Page.reqTS + 5 <= rf2.clock() then
      Page.reqTS = rf2.clock()
      if Page.read then Page:read() end
    end
  end

  -- what a tile/cell is called: its own text, else from the card model
  local function selectField(i) current = i end

  local function nameOf(i)
    local f = Page.fields[i]
    if f.t and not isButton(f) then return f.t end
    return model.name[i] or ""
  end

  local function valueFont(text, w)
    local key = text .. "|" .. w
    local f = RF2UI.fonts[key]
    if f then return f end
    if textWidth(text, MIDSIZE) <= w then f = MIDSIZE
    elseif textWidth(text, 0) <= w then f = 0
    else f = SMLSIZE end
    if RF2UI.nFonts > 300 then RF2UI.fonts, RF2UI.nFonts = {}, 0 end
    RF2UI.fonts[key], RF2UI.nFonts = f, RF2UI.nFonts + 1
    return f
  end

  local function drawTile(i, x, y, w, h, editing)
    local f = Page.fields[i]
    local sel = (i == current)
    local value = valueText(f)
    lcd.drawFilledRectangle(x, y, w, h, (sel and editing) and COLOR.accentPanel or COLOR.barBg)
    if sel then lcd.drawFilledRectangle(x, y + 4, 4, h - 8, COLOR.accent) end
    if isButton(f) then
      lcd.drawText(x + w / 2, y + h / 2, value, CENTER + VCENTER + valueFont(value, w - 16) + COLOR.accent)
    elseif h >= RF2_TILE_H then
      lcd.drawText(x + 14, y + 13, nameOf(i), LEFT + VCENTER + SMLSIZE + COLOR.muted)
      lcd.drawText(x + 14, y + 41, value,
        LEFT + VCENTER + valueFont(value, w - 24) + (f.readOnly and COLOR.muted or COLOR.white))
    else
      lcd.drawText(x + w / 2, y + h / 2, value,
        CENTER + VCENTER + valueFont(value, w - 12) + (f.readOnly and COLOR.muted or COLOR.white))
    end
  end

  -- Edit panel: name, value, range; slider or choice buttons; steps + OK.
  local SL_X, SL_W = 20, LCD_W - 40
  local function setFromX(x)
    local f = Page.fields[current]
    if not (f.data and type(f.data.value) == "number") then return end
    local lo, hi = f.data.min or 0, f.data.max or 255
    local frac = math.max(0, math.min(1, (x - SL_X) / SL_W))
    setValue(lo + frac * (hi - lo))
  end

  local CHOICE_STEPS = { { "<", -1 }, { ">", 1 } }
  local NUMBER_STEPS = { { "-10", -10 }, { "-1", -1 }, { "+1", 1 }, { "+10", 10 } }
  local slider = { 0, 0, setFromX }
  local function tapSlider() setFromX(RF2UI.tapX or SL_X) end

  local function drawPanel()
    local f = Page.fields[current]
    local y = RF2_PANEL_Y
    lcd.drawFilledRectangle(0, y, LCD_W, LCD_H - y, COLOR.panel)
    lcd.drawFilledRectangle(0, y, LCD_W, 2, COLOR.accent)
    rf2Hit(0, y, LCD_W, LCD_H - y) -- the panel itself is not "outside"
    local d = f.data or {}
    local value = valueText(f)
    lcd.drawText(20, y + 28, nameOf(current), LEFT + VCENTER + COLOR.muted)
    lcd.drawText(LCD_W / 2, y + 30, value, CENTER + VCENTER + fitFontMeasured(320, 55, value, DBLSIZE) + COLOR.white)
    local choices = type(d.table) == "table" and d.table or nil
    local nChoices = choices and ((d.max or 0) - (d.min or 0) + 1) or 0
    if choices and nChoices <= 6 then
      -- one button per choice, 3 per row, OK on the right
      local bw = math.floor((LCD_W - 130 - 2 * 8) / 3)
      for k = 0, nChoices - 1 do
        local v = (d.min or 0) + k
        local bx = 10 + (k % 3) * (bw + 8)
        local by = y + 62 + math.floor(k / 3) * 58
        local label = tostring(choices[v] or v)
        rf2Button(bx, by, bw, 50, label, COLOR.panel, setValue, nil, d.value == v,
          valueFont(label, bw - 12), v)
      end
    else
      if not choices then
        local lo, hi = d.min or 0, d.max or 255
        local sc = d.scale or 1
        local function num(v)
          v = v / sc
          return isWhole(v) and string.format("%d", math.floor(v)) or tostring(v)
        end
        lcd.drawText(LCD_W - 20, y + 30, num(lo) .. " ... " .. num(hi), RIGHT + VCENTER + SMLSIZE + COLOR.muted)
        local sy = y + 62
        lcd.drawFilledRectangle(SL_X, sy, SL_W, 40, COLOR.barBg)
        local frac = (hi > lo and type(d.value) == "number") and (d.value - lo) / (hi - lo) or 0
        local fw = math.floor(SL_W * math.max(0, math.min(1, frac)))
        lcd.drawFilledRectangle(SL_X, sy, fw, 40, COLOR.accentPanel)
        lcd.drawFilledRectangle(SL_X + math.max(0, fw - 4), sy - 4, 8, 48, COLOR.accent)
        rf2Hit(SL_X - 10, sy - 10, SL_W + 20, 60, tapSlider)
        slider[1], slider[2] = sy - 10, sy + 50
        RF2UI.slider = slider
      end
      local by = y + 118
      local steps = choices and CHOICE_STEPS or NUMBER_STEPS
      for k, s in ipairs(steps) do
        rf2Button(10 + (k - 1) * 128, by, 120, 56, s[1], COLOR.panel, incValue, nil, false, MIDSIZE, s[2])
      end
    end
    rf2Button(LCD_W - 116, y + 118, 106, 56, "OK", COLOR.panel, nil, EVT_VIRTUAL_ENTER, true, MIDSIZE)
  end

  local lastState
  local function backdrop() t.draw(lastState) end
  local function slide(ts)
    local s = RF2UI.slider
    if s and ts.startY and ts.startY >= s[1] and ts.startY <= s[2] then
      s[3](ts.x)
    else
      scrollY = scrollY - (ts.slideY or 0)
    end
  end

  t.draw = function(pageState)
    local editing = (pageState == status.editing)
    lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, COLOR.bg)
    RF2UI.slider = nil
    local fields, labels = Page.fields or {}, Page.labels or {}
    if #fields > 0 then
      if current > #fields then current = #fields end
      if not model or model.fields ~= Page.fields or model.nF ~= #fields or model.nL ~= #labels then
        model = rf2CardModel(Page)
      end
      local top = RF2_TOP + 6
      local bottom = editing and (RF2_PANEL_Y - 6) or (LCD_H - 6)
      local p = model.pos[current]
      if p and (current ~= lastCurrent or editing ~= lastEditing) then -- keep the selection in view
        if top + p[2] - scrollY < top then scrollY = p[2] end
        if top + p[2] + p[4] - scrollY > bottom then scrollY = p[2] + p[4] + top - bottom end
        lastCurrent, lastEditing = current, editing
      end
      scrollY = math.max(0, math.min(scrollY, math.max(0, model.height + top - bottom)))
      local off = top - scrollY
      if editing then rf2Hit(0, RF2_TOP, LCD_W, LCD_H - RF2_TOP, nil, EVT_VIRTUAL_ENTER) end -- tap outside = OK

      for _, c in ipairs(model.cards) do
        local cy = c.y + off
        if cy + c.h > RF2_TOP and cy < bottom then
          drawChamferedRect(10, cy, RF2_CARD_W, c.h, COLOR.panel, COLOR.bg, 6)
          if c.title then lcd.drawText(22, cy + 20, c.title.t, LEFT + VCENTER + COLOR.accent) end
          for _, it in ipairs(c.items) do
            local q = it.rect
            if q then -- read-only text tile
              local y = q[2] + off
              lcd.drawFilledRectangle(q[1], y, q[3], q[4], COLOR.barBg)
              lcd.drawText(q[1] + 14, y + 13, it.name and it.name.t or "", LEFT + VCENTER + SMLSIZE + COLOR.muted)
              local text = tostring(it.l.t)
              lcd.drawText(q[1] + 14, y + 41, text, LEFT + VCENTER + valueFont(text, q[3] - 24) + COLOR.muted)
            end
          end
          if c.kind == "table" then
            for k, col in ipairs(c.cols) do
              local text = col.a.t .. (col.b and (" " .. col.b.t) or "")
              lcd.drawText(c.cellX + (k - 1) * (c.cellW + 6) + c.cellW / 2, c.headY + off + 12, text,
                CENTER + VCENTER + SMLSIZE + COLOR.muted)
            end
            for _, row in ipairs(c.rows) do
              if row.head then
                lcd.drawText(24, row.y + off + RF2_CELL_H / 2, row.head.t, LEFT + VCENTER + COLOR.white)
              end
            end
          end
        end
      end
      for i = 1, #fields do
        local q = model.pos[i]
        if q then
          local y = q[2] + off
          if y + q[4] > RF2_TOP and y < bottom then
            drawTile(i, q[1], y, q[3], q[4], editing)
            if not editing then
              local editable = Page.isReady and not fields[i].readOnly
              rf2Hit(q[1], y, q[3], q[4], selectField, editable and EVT_VIRTUAL_ENTER or nil, i)
            end
          end
        end
      end
      if editing then drawPanel() end
    end
    if Page.init then -- confirm page (Acc Cal): ENTER starts it
      rf2Button(LCD_W / 2 - 110, LCD_H - 72, 220, 56, "Calibrate", COLOR.bg, nil, EVT_VIRTUAL_ENTER, true, MIDSIZE)
    end
    rf2Frame(Page.title, "page", true) -- last, over anything scrolled under it
    if not Page.isReady then -- loading: a strip running under the title bar
      local x = (getTime() * 8) % (LCD_W + 160) - 160
      lcd.drawFilledRectangle(math.max(0, x), RF2_TOP - 5, 160 + math.min(0, x), 3, COLOR.accent)
    end
    lastState = pageState
    RF2UI.backdrop, RF2UI.slide = backdrop, slide
  end

  t.update = function(pageState, event)
    t.draw(pageState)
    local fields = Page.fields
    if pageState == status.display then
      if event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT then
        current = math.max(1, current - 1)
      elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT then
        current = math.min(#fields, current + 1)
      elseif event == EVT_VIRTUAL_ENTER and fields[current] then
        local f = fields[current]
        if Page.isReady and not f.readOnly then
          if not isButton(f) then pageState = status.editing end
          if f.preEdit then f:preEdit(Page) end
        end
      end
    elseif pageState == status.editing then
      if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then
        if fields[current].postEdit then fields[current]:postEdit(Page) end
        pageState = status.display
      elseif event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_INC_REPT then
        incValue(1)
      elseif event == EVT_VIRTUAL_DEC or event == EVT_VIRTUAL_DEC_REPT then
        incValue(-1)
      end
    end
    if Page.timer and (not Page.lastTimeTimerFired or Page.lastTimeTimerFired + 0.5 < rf2.clock()) then
      Page.lastTimeTimerFired = rf2.clock()
      Page:timer()
    end
    if not Page.isReady and pageState == status.display then requestPage() end
    return pageState
  end
  return t
end

local RF2_SKIN = {
  ["LCD/shared"] = rf2SkinShared,
  ["LCD/waitMessage"] = rf2SkinWait,
  ["LCD/messageBox"] = rf2SkinMessage,
  ["LCD/popupMenu"] = rf2SkinPopup,
  ["LCD/mainMenu"] = rf2SkinMainMenu,
  ["LCD/page"] = rf2SkinPage,
  -- API version already read by this widget (wgt.fcApi): skip RF2's own
  -- request; nil = RF2's ui_init as usual
  ["ui_init"] = function()
    if not RF2UI.apiVersion then return nil end
    return { t = "", f = function() rf2.apiVersion = RF2UI.apiVersion; return true end }
  end,
}

local function rf2SkinInstall(apiVersion)
  local execute = rf2.executeScript
  rf2.executeScript = function(name, ...)
    local skin = RF2_SKIN[name]
    local m = skin and skin(...)
    if m ~= nil then return m end
    return execute(name, ...)
  end
  RF2UI.apiVersion = apiVersion
  rf2.radio.yMinLimit = RF2_TOP + 8 -- init screen text below the title bar
  rf2.radio.NoTelem = { LCD_W / 2, LCD_H - 16, "No telemetry", CENTER + VCENTER + SMLSIZE + COLOR.red }
  RF2UI.hits, RF2UI.nHits, RF2UI.backdrop, RF2UI.slide, RF2UI.quit = {}, 0, nil, nil, nil
end

-- Touch -> RF2: taps hit the targets drawn last frame (topmost first),
-- a slide scrolls. Keys pass through unchanged.
local function rf2SkinInput(event, touchState)
  if event == EVT_TOUCH_SLIDE then
    if RF2UI.slide and touchState then RF2UI.slide(touchState) end
    return 0
  elseif event == EVT_TOUCH_FIRST or event == EVT_TOUCH_BREAK then
    return 0
  elseif event ~= EVT_TOUCH_TAP then
    return event
  end
  if not touchState then return 0 end
  local hits = RF2UI.hits
  RF2UI.tapX = touchState.x
  for i = RF2UI.nHits, 1, -1 do
    local h = hits[i]
    if touchState.x >= h[1] and touchState.x < h[1] + h[3]
       and touchState.y >= h[2] and touchState.y < h[2] + h[4] then
      if h[5] then h[5](h[7]) end
      return h[6] or 0
    end
  end
  return 0
end

local function startRf2(apiVersion)
  local dir = CONFIG.tools.rf2Dir
  local compiled = loadScript(dir .. "COMPILE/scripts_compiled.lua")
  if not compiled then return nil, "Rotorflight Lua not found in " .. dir end
  if chdir then chdir(dir) end -- as tool.lua; compile.lua uses relative paths
  if compiled() then
    assert(loadScript(dir .. "rf2.lua"))()
    rf2.radio = rf2.executeScript("radios")
    if CONFIG.tools.rf2Skin then rf2SkinInstall(apiVersion) end
    rf2.mspQueue = rf2.executeScript("MSP/mspQueue")
    rf2.mspHelper = rf2.executeScript("MSP/mspHelper")
    rf2.isTool = true
    return rf2.executeScript("ui_lcd")
  end
  -- First run after installing RF2: its compile step (one file per frame,
  -- returns 1 when done), then refresh opens it again
  return assert(loadScript(dir .. "COMPILE/compile.lua"))(), nil, true
end

-- lvgl widget: RF2's own lvgl UI (ui_lvgl_runner), started as the RfTool
-- widget does; it builds its screens in this widget's lvgl tree.
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
  if apiVersion then -- already read by this widget: skip RF2's request
    local execute = rf2.executeScript
    rf2.executeScript = function(name, ...)
      if name == "ui_init" then
        return { t = "", f = function() rf2.apiVersion = apiVersion; return true end }
      end
      return execute(name, ...)
    end
  end
  rf2.mspQueue = rf2.executeScript("MSP/mspQueue")
  rf2.mspHelper = rf2.executeScript("MSP/mspHelper")
  return rf2.executeScript("ui_lvgl_runner")
end

local function startElrs()
  for _, path in ipairs(CONFIG.tools.elrs) do
    local chunk = loadScript(path)
    if chunk then
      local tool = chunk()
      if tool.init then tool.init() end
      return tool.run
    end
  end
  return nil, "ExpressLRS Lua not found in /SCRIPTS/TOOLS"
end

local function stopTool(wgt, message)
  wgt.hosted, wgt.menu = nil, nil
  rf2 = nil -- the RF2 scripts' only global
  collectgarbage()
  if message then wgt.toolMsg = { text = message, at = getTime() } end
  if CONFIG.simulate then -- same log as the alarms (see alert)
    pcall(function()
      local f = io.open("/LOGS/rftelem_alarms.log", "a")
      if f then io.write(f, string.format("%.2f tool %s\n", getTime() / 100, message or "closed")); io.close(f) end
    end)
  end
end

local MENU_ITEMS = {
  { key = "rf2",  label = "Rotorflight settings" },
  { key = "elrs", label = "ExpressLRS" },
  { key = "batt", label = "Battery profile" },
  { key = "view", label = "View FC settings" },
  { key = "settings", label = "Settings" },
}

-- Whether a menu item can be used now, and why not.
local function menuItemState(wgt, t, connected, key)
  if key == "rf2" then
    return connected, "needs the model connected"
  elseif key == "elrs" and CONFIG.lvgl and lvgl then
    return false, "lcd tool - use SYS > Tools"
  elseif key == "elrs" then
    return crossfireTelemetryPush ~= nil and crossfireTelemetryPush() ~= nil, "no CRSF module"
  elseif key == "settings" then
    return CONFIG.lvgl and lvgl ~= nil, "lvgl display only"
  elseif key == "view" then
    return connected and CONFIG.lvgl and lvgl ~= nil, "needs the model connected"
  end
  return connected and t.battProfile ~= nil, "needs BAT# from the FC"
end

local function openMenuItem(wgt, t, connected, key)
  local ok, why = menuItemState(wgt, t, connected, key)
  if not ok then wgt.toolMsg = { text = "Not available: " .. why, at = getTime() }; return end
  wgt.menu = nil
  if key == "batt" then
    wgt.bp = { phase = "pick", sel = t.battProfile, since = getTime() }
    return
  end
  if key == "settings" then
    wgt.settings = { group = SET.groups[1] }
    return
  end
  if key == "view" then
    wgt.infoView, wgt.fc = 1, {}
    if CONFIG.simulate then wgt.fc[FC.pages[1].cmd] = FC.sim[FC.pages[1].cmd] end
    return
  end
  local okStart, run, err, compiling = pcall(key == "rf2" and ((CONFIG.lvgl and lvgl) and startRf2Lvgl or startRf2) or startElrs, wgt.fcApi)
  if not okStart then
    stopTool(wgt, "Could not start: " .. tostring(run))
  elseif not run then
    stopTool(wgt, err)
  else
    wgt.hosted = { kind = key, run = run, compiling = compiling }
  end
end

-- Menu card over standby / dashboard; row rects go to wgt.menuRects.
local function drawMenu(wgt, t, connected, w, h)
  local mw, rowH = 460, 64
  local mh = 56 + #MENU_ITEMS * (rowH + 8) + 40
  local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
  drawChamferedRect(mx, my, mw, mh, COLOR.accent, COLOR.bg, 8)
  drawChamferedRect(mx + 2, my + 2, mw - 4, mh - 4, COLOR.panel, COLOR.accent, 7)
  lcd.drawText(mx + 20, my + 28, "Menu", LEFT + VCENTER + MIDSIZE + COLOR.white)
  wgt.menuRects = {}
  for i, item in ipairs(MENU_ITEMS) do
    local ry = my + 56 + (i - 1) * (rowH + 8)
    local ok, why = menuItemState(wgt, t, connected, item.key)
    local selected = (wgt.menu.sel == i)
    wgt.menuRects[i] = { mx + 14, ry, mw - 28, rowH }
    drawChamferedRect(mx + 14, ry, mw - 28, rowH, selected and COLOR.accentPanel or COLOR.barBg, COLOR.panel, 5)
    if selected then lcd.drawFilledRectangle(mx + 14, ry + 6, 4, rowH - 12, COLOR.accent) end
    lcd.drawText(mx + 32, ry + (ok and rowH / 2 or 22), item.label,
      LEFT + VCENTER + MIDSIZE + (ok and COLOR.white or COLOR.muted))
    if not ok then lcd.drawText(mx + 32, ry + 48, why, LEFT + VCENTER + SMLSIZE + COLOR.muted) end
  end
  lcd.drawText(mx + mw / 2, my + mh - 20, "Tap or ENTER to open  -  RTN to close",
    CENTER + VCENTER + SMLSIZE + COLOR.dim)
end

-- Short status line (tool errors, "not available") for 3s.
local function drawToolMsg(wgt, w, h)
  local m = wgt.toolMsg
  if not m then return end
  if getTime() - m.at > 300 then wgt.toolMsg = nil; return end
  drawChamferedRect(40, h - 64, w - 80, 44, COLOR.red, COLOR.bg, 6)
  lcd.drawText(w / 2, h - 42, m.text, CENTER + VCENTER + fitFontMeasured(w - 100, 27, m.text, SMLSIZE) + COLOR.white)
end

-- ============================== LVGL VIEW =================================
-- CONFIG.lvgl: the widget is an lvgl widget (EdgeTX 2.11+). Measured on the
-- TX16S MK3 (tools/diagtest DrawBench / LvglBench, 2026-11-01): an lcd
-- widget is redrawn completely every frame and ran at 4-6 fps (EdgeTX alone
-- costs ~75-110 ms per frame, each text ~1 ms); an lvgl widget keeps its
-- objects and redraws what changed: 12-20 fps for a dashboard-sized scene.
-- Each screen is built once (LV.build*) when it changes; labels, colors,
-- sizes and visibility are functions reading LV.v, which LV.update* fills
-- once per frame from the same trackers the lcd screens use. Taps go to
-- lvgl buttons directly (also outside full screen in App mode). The lcd
-- drawing above stays for CONFIG.lvgl = false.
-- Outside full screen, App mode draws the EdgeTX button in the top-left
-- corner: 62x62 px (measured in the simulator). Nothing is placed in
-- LV.ICON x LV.ICON there; rows under it start at LV.Y1.
local LV = { v = {}, ICON = 68, Y1 = 64 }
local LV_LH = { [0] = 27 } -- measured line heights (FONT_SPECS)

function LV.lh(font)
  if not LV_LH[SMLSIZE] then
    LV_LH[SMLSIZE], LV_LH[MIDSIZE], LV_LH[DBLSIZE], LV_LH[XXLSIZE] = 23, 42, 55, 93
  end
  return LV_LH[font or 0] or 27
end

-- dynamic value: a function reading LV.v[key]
function LV.dv(key, default)
  return function()
    local x = LV.v[key]
    if x == nil then return default end
    return x
  end
end

function LV.rect(k, x, y, w, h, color, radius, extra)
  local r = { type = "rectangle", x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h),
    color = color, filled = true, rounded = radius }
  if extra then for key, val in pairs(extra) do r[key] = val end end
  k[#k + 1] = r
  return r
end

-- text vertically centered on cy; align LEFT (x = left edge) / RIGHT /
-- CENTER (x..x+w is the box)
function LV.text(k, x, cy, w, text, font, color, align, extra)
  font = font or 0
  local lh = LV.lh(font)
  local r = { type = "label", x = math.floor(x), y = math.floor(cy - lh / 2), w = math.floor(w), h = lh,
    text = text, font = font, color = color, align = align or LEFT }
  if extra then for key, val in pairs(extra) do r[key] = val end end
  k[#k + 1] = r
  return r
end

function LV.button(k, x, y, w, h, text, press, font, extra)
  local r = { type = "button", x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h),
    text = text, press = press, font = font or 0, color = COLOR.barBg, textColor = COLOR.white, cornerRadius = 6 }
  if extra then for key, val in pairs(extra) do r[key] = val end end
  k[#k + 1] = r
  return r
end

-- drawTab's layout: 18px label row (label left, note right), value below
-- at MIDSIZE; markKey = color stripe on the left edge.
function LV.tab(k, x, y, w, h, label, valueKey, noteKey, markKey)
  local left = x + 8
  if markKey then
    LV.rect(k, x + 2, y + 4, 4, h - 8, COLOR.grey, nil, { color = LV.dv(markKey, COLOR.grey) })
    left = x + 14
  end
  local ly = y + TAB_LABEL_H / 2 + 1
  LV.text(k, left, ly, w - (left - x) - 8, label, SMLSIZE, COLOR.dim)
  if noteKey then
    LV.text(k, x + w / 2, ly, w / 2 - 8, LV.dv(noteKey, ""), SMLSIZE, COLOR.muted, RIGHT)
  end
  LV.text(k, left, y + TAB_LABEL_H + (h - TAB_LABEL_H) / 2, w - (left - x) - 8, LV.dv(valueKey, "--"), MIDSIZE, COLOR.white)
end

-- Largest font up to cap whose measured width fits w (cached per text):
-- an lvgl label wraps instead of overflowing, so long text must shrink.
LV.fits = {}
function LV.fitFont(text, w, cap)
  local key = text .. "|" .. w .. "|" .. cap
  local f = LV.fits[key]
  if f then return f end
  f = SMLSIZE
  for _, cand in ipairs({ DBLSIZE, MIDSIZE, 0 }) do
    if cand <= cap and textWidth(text, cand) <= w then f = cand; break end
  end
  LV.nFits = (LV.nFits or 0) + 1
  if LV.nFits > 200 then LV.fits, LV.nFits = {}, 0 end
  LV.fits[key] = f
  return f
end

-- label that shrinks its font to fit w, kept vertically centered on cy
function LV.fitText(k, x, cy, w, key, default, cap, color, align)
  local function font() return LV.fitFont(LV.v[key] or default, w, cap) end
  LV.text(k, x, cy, w, LV.dv(key, default), cap, color, align, {
    font = font,
    pos = function() return math.floor(x), math.floor(cy - LV.lh(font()) / 2) end })
end

-- bar with label and value written inside it (Battery / Throttle)
function LV.bar(k, x, y, w, h, labelKey, valueKey, pctKey, colorKey, color, font)
  LV.rect(k, x, y, w, h, COLOR.barBg)
  LV.rect(k, x, y, 0, h, color, nil, {
    color = colorKey and LV.dv(colorKey, color) or color,
    size = function() return math.floor(w * math.max(0, math.min(100, LV.v[pctKey] or 0)) / 100), h end })
  -- one font for both texts: the largest up to `font` where they fit side by side
  local avail = w - 24 - 24
  local function shared()
    local a, b = LV.v[labelKey] or "", LV.v[valueKey] or "--"
    local key = a .. "|" .. b .. "|" .. avail .. "|" .. font
    local f = LV.fits[key]
    if f then return f end
    f = SMLSIZE
    for _, cand in ipairs({ DBLSIZE, MIDSIZE, 0 }) do
      if cand <= font and textWidth(a, cand) + textWidth(b, cand) <= avail then f = cand; break end
    end
    LV.nFits = (LV.nFits or 0) + 1
    if LV.nFits > 200 then LV.fits, LV.nFits = {}, 0 end
    LV.fits[key] = f
    return f
  end
  local cy = y + h / 2
  local pos = function(px) return function() return math.floor(px), math.floor(cy - LV.lh(shared()) / 2) end end
  LV.text(k, x + 12, cy, w - 24, LV.dv(labelKey, ""), font, COLOR.white, LEFT, { font = shared, pos = pos(x + 12) })
  LV.text(k, x + 12, cy, w - 24, LV.dv(valueKey, "--"), font, COLOR.white, RIGHT, { font = shared, pos = pos(x + 12) })
end

-- top bar: warnings left, Menu button, date/time, signal bars, TX battery
function LV.topBar(k, wgt, w, withMenu)
  local pad, y, h = 12, 12, 30
  local x = LV.ICON + 4 -- right of the EdgeTX button
  LV.rect(k, x, y, w - pad - x, h, COLOR.chip, 6)
  LV.rect(k, x + 12, y + h / 2 - 4, 8, 8, COLOR.red, nil, { visible = function() return LV.v.warn ~= "" end })
  LV.text(k, x + 26, y + h / 2, 300, LV.dv("warn", ""), SMLSIZE, COLOR.red)
  local bx = w - pad - 12 - 44
  LV.rect(k, bx, y + 6, 40, h - 12, COLOR.dim, 3, { filled = false, thickness = 2 })
  LV.rect(k, bx + 40, y + 11, 4, h - 22, COLOR.dim)
  LV.rect(k, bx + 3, y + 9, 34, h - 18, COLOR.green, 1, {
    color = LV.dv("txColor", COLOR.green),
    size = function() return math.max(1, math.floor(34 * (LV.v.txPct or 0) / 100)), h - 18 end })
  local sx = bx - 12 - 22
  for i = 1, 4 do
    local bh = 4 + i * 4
    LV.rect(k, sx + (i - 1) * 6, y + h - 6 - bh, 4, bh, COLOR.barBg, nil, {
      color = function() return ((LV.v.sig or 0) >= i * 25 - 12) and COLOR.green or COLOR.barBg end })
  end
  LV.text(k, sx - 12 - 170, y + h / 2, 170, LV.dv("clock", ""), SMLSIZE, COLOR.white, RIGHT)
  if withMenu then
    LV.button(k, sx - 12 - 170 - 12 - 90, y + 2, 90, h - 4, "Menu",
      function() if not LV.v.armed then wgt.menu = { sel = 1 } end end, SMLSIZE,
      { visible = function() return not LV.v.armed end })
  end
end

function LV.buildDashboard(k, wgt, w, h)
  local pad = 12
  LV.topBar(k, wgt, w, true)
  -- rows 8px apart; the cluster starts below the EdgeTX button
  local gap = 8
  local clusterY = LV.ICON
  local clusterH = h - 20 - clusterY - gap * 3 - math.floor(h * 0.135) - math.floor(h * 0.18) - math.floor(h * 0.15)
  LV.rect(k, pad, clusterY, w - pad * 2, clusterH, COLOR.accentBorder, 8)
  LV.rect(k, pad + 1, clusterY + 1, w - pad * 2 - 2, clusterH - 2, COLOR.accentPanel, 7)
  local innerPad = 10
  local innerW = w - pad * 2 - innerPad * 2
  local flankW = math.floor(innerW * 0.3)
  local heroW = innerW - flankW * 2 - innerPad * 2
  local cellH = math.floor((clusterH - innerPad * 3) / 2)
  local lx = pad + innerPad
  local y1, y2 = clusterY + innerPad, clusterY + innerPad * 2 + cellH
  local rx = lx + flankW + innerPad + heroW + innerPad
  for _, f in ipairs({ { lx, y1, "Volt", "volt", "voltMin" }, { lx, y2, "Vcel", "vcel" },
                       { rx, y1, "Current", "curr", "currMax" }, { rx, y2, "Bec volt", "bec", "becMin" } }) do
    LV.rect(k, f[1], f[2], flankW, cellH, COLOR.panel, 4)
    LV.tab(k, f[1], f[2], flankW, cellH, f[3], f[4], f[5])
  end
  local hx = lx + flankW + innerPad
  local hy, hh = clusterY + innerPad, clusterH - innerPad * 2
  LV.text(k, hx + 8, hy + TAB_LABEL_H / 2 + 1, heroW / 2, "Headspeed", SMLSIZE, COLOR.dim)
  LV.text(k, hx + heroW / 2, hy + TAB_LABEL_H / 2 + 1, heroW / 2 - 8, LV.dv("rpmMax", ""), SMLSIZE, COLOR.muted, RIGHT)
  local cy = hy + TAB_LABEL_H + (hh - TAB_LABEL_H) / 2
  LV.text(k, hx, cy, heroW, LV.dv("rpm", "--"), XXLSIZE, COLOR.white, CENTER)
  LV.text(k, hx + heroW - 40, cy + 30, 40, "rpm", SMLSIZE, COLOR.dim)

  local midY, midH = clusterY + clusterH + gap, math.floor(h * 0.135)
  local panelW = w - pad * 2
  LV.rect(k, pad, midY, panelW, midH, COLOR.panel, 6)
  local segW = math.floor(panelW / 4)
  local tabs = { { "Arm", "arm", "armColor" }, { LV.dv("govLabel", "Governor"), "gov", "govColor" },
                 { "Flight", "flight" }, { "Profile/Rate", "profile" } }
  for i = 1, 4 do
    local tb = tabs[i]
    local sx = pad + (i - 1) * segW
    local sw = (i == 4) and (panelW - segW * 3) or segW
    if i > 2 then LV.rect(k, sx, midY + 10, 1, midH - 20, COLOR.muted) end
    LV.tab(k, sx + 4, midY + 2, sw - 8, midH - 4, tb[1], tb[2], nil, tb[3])
  end

  local r3y, r3h = midY + midH + gap, math.floor(h * 0.18)
  LV.rect(k, pad, r3y, w - pad * 2, r3h, COLOR.panel, 8)
  LV.bar(k, pad + 12, r3y + 10, w - pad * 2 - 24, r3h - 18, "battLabel", "battValue", "charge", "battColor",
    COLOR.battGood, DBLSIZE)

  local r4y, r4h = r3y + r3h + gap, math.floor(h * 0.15)
  local sideW = math.floor((w - pad * 3) * 0.26)
  local thrW = (w - pad * 3) - sideW
  LV.rect(k, pad, r4y, thrW, r4h, COLOR.panel, 7)
  LV.bar(k, pad + 10, r4y + 8, thrW - 20, r4h - 14, "thrLabel", "thrValue", "thr", nil, COLOR.accent, MIDSIZE)
  local sideX = pad + thrW + pad
  LV.rect(k, sideX, r4y, sideW, r4h, COLOR.panel, 7)
  if CONFIG.showModelImage and wgt.modelImagePath then
    k[#k + 1] = { type = "image", file = wgt.modelImagePath, x = sideX + math.floor((sideW - CONFIG.modelImageW) / 2),
      y = r4y + math.floor((r4h - 20 - CONFIG.modelImageH) / 2), w = CONFIG.modelImageW, h = CONFIG.modelImageH }
  end
  LV.text(k, sideX + 8, r4y + r4h - 10, sideW - 16, LV.dv("model", ""), SMLSIZE, COLOR.dim, CENTER)
end

function LV.buildStandby(k, wgt, w, h)
  local pad, y = 12, 12
  local panelW = w - pad * 2
  local heroH = (h - pad) - y - (pad + 56 + pad + 62)
  local hx = LV.ICON + 4 -- the hero panel starts right of the EdgeTX button
  local heroW = w - pad - hx
  LV.rect(k, hx, y, heroW, heroH, COLOR.accentBorder, 8)
  LV.rect(k, hx + 1, y + 1, heroW - 2, heroH - 2, COLOR.accentPanel, 7)
  local half = math.floor(heroW / 2)
  LV.text(k, hx, y + heroH / 2 - 10, half, LV.dv("hhmm", ""), XXLSIZE, COLOR.white, CENTER)
  LV.text(k, hx, y + heroH - 34, half, LV.dv("date", ""), SMLSIZE, COLOR.dim, CENTER)
  LV.rect(k, hx + half, y + 24, 1, heroH - 48, COLOR.muted)
  local imgY = y + math.floor(heroH * 0.22)
  if CONFIG.showModelImage and wgt.modelImagePath then
    k[#k + 1] = { type = "image", file = wgt.modelImagePath, x = hx + half + math.floor((half - CONFIG.modelImageW) / 2),
      y = imgY, w = CONFIG.modelImageW, h = CONFIG.modelImageH }
  end
  LV.text(k, hx + half + 20, imgY + CONFIG.modelImageH + 48, half - 40, LV.dv("model", ""), DBLSIZE, COLOR.white, CENTER)
  LV.text(k, hx + half, y + heroH - 34, half, "Model", SMLSIZE, COLOR.dim, CENTER)

  local sy, sh = y + heroH + pad, 56
  LV.rect(k, pad, sy, panelW, sh, COLOR.panel, 6)
  LV.text(k, pad + 16, sy + sh / 2, panelW / 2, "Waiting for connection", MIDSIZE, COLOR.white)
  LV.text(k, pad + panelW / 2, sy + sh / 2, panelW / 2 - 16, LV.dv("standbyHint", ""), SMLSIZE, COLOR.dim, RIGHT)
  -- full screen only (a button): covers the hint, which then isn't needed
  LV.rect(k, pad + panelW - 130, sy + 6, 126, sh - 12, COLOR.panel, nil, { visible = function() return LV.v.full end })
  LV.button(k, pad + panelW - 120, sy + 10, 104, sh - 20, "Menu", function() wgt.menu = { sel = 1 } end, 0)

  local ty, tabH = sy + sh + pad, 62
  LV.rect(k, pad, ty, panelW, tabH, COLOR.panel, 6)
  local fracs = { 0.26, 0.30, 0.22 }
  local tabs = { { "TX battery", "txV", "txPctText", "txColor" }, { "Last flight", "lastFlight", "lastUsed" },
                 { "Voice", "voice" }, { "Alarms", "alarms", nil, "alarmsColor" } }
  local tx = pad
  for i = 1, 4 do
    local tb = tabs[i]
    local tw = fracs[i] and math.floor(panelW * fracs[i]) or (pad + panelW - tx)
    if i == 2 or i == 3 then LV.rect(k, tx, ty + 10, 1, tabH - 20, COLOR.muted) end
    LV.tab(k, tx + 2, ty + 1, tw - 4, tabH - 2, tb[1], tb[2], tb[3], tb[4])
    tx = tx + tw
  end
end

function LV.buildArmWarning(k, wgt, w, h, armd)
  LV.topBar(k, wgt, w, false)
  local y = LV.Y1
  local areaH = h - y
  LV.rect(k, 2, y + 2, w - 4, areaH - 4, COLOR.red, 0, { filled = false, thickness = 6 })
  local cy = y + areaH * 0.38
  LV.rect(k, w / 2 - 5, cy - 46, 10, 30, COLOR.red)
  LV.rect(k, w / 2 - 5, cy - 10, 10, 10, COLOR.red)
  if armd == ARMD_ARM_SWITCH_AT_POWERUP then
    LV.text(k, 20, cy + 26, w - 40, "ARM SWITCH WAS ON AT POWER-UP", DBLSIZE, COLOR.red, CENTER)
    LV.text(k, 20, cy + 64, w - 40, "Cycle the switch off and on to arm - cannot fly like this", SMLSIZE, COLOR.white, CENTER)
  else
    LV.text(k, 20, cy + 26, w - 40, "ARMING DISABLED", DBLSIZE, COLOR.red, CENTER)
    local reasons, names = decodeArmd(armd), {}
    for i = 1, #reasons do names[i] = reasons[i][2] end
    local reasonText = (#names > 0) and table.concat(names, " / ") or "unknown"
    LV.text(k, 30, cy + 78, w - 60, reasonText, fitFontMeasured(w - 60, 42, reasonText, MIDSIZE), COLOR.white, CENTER)
    LV.text(k, 20, cy + 114, w - 40, "code " .. fmt(armd, 0), SMLSIZE, COLOR.dim, CENTER)
  end
end

function LV.buildBattSelect(k, wgt, w, h)
  LV.topBar(k, wgt, w, false)
  local pad, y = 12, LV.Y1
  local panelW, cfg = w - pad * 2, CONFIG.batteryProfile
  local titleH = 40
  LV.rect(k, pad, y, panelW, titleH, COLOR.panel, 6)
  LV.text(k, pad + 14, y + titleH / 2, 300, "Battery profile", MIDSIZE, COLOR.white)
  LV.text(k, pad + panelW / 2, y + titleH / 2, panelW / 2 - 14, LV.dv("bpStatus", ""), SMLSIZE, COLOR.dim, RIGHT,
    { color = LV.dv("bpStatusColor", COLOR.dim) })
  local hintH, gap = 40, 10
  local gridY = y + titleH + pad
  local gridH = h - pad - hintH - pad - gridY
  local tileW = math.floor((panelW - gap * 2) / 3)
  local tileH = math.floor((gridH - gap) / 2)
  for i = 1, 6 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local tx, ty = pad + col * (tileW + gap), gridY + row * (tileH + gap)
    LV.rect(k, tx, ty, tileW, tileH, COLOR.accent, 6, {
      visible = function() return wgt.bp ~= nil and wgt.bp.sel == i end })
    local label = cfg.labels[i] or ("Profile " .. i)
    local cap = wgt.battCaps and wgt.battCaps[i]
    if cap and cap > 0 then
      label = (label ~= "Profile " .. i) and (label .. "  " .. cap .. "mAh") or (cap .. "mAh")
    end
    LV.rect(k, tx + 3, ty + 3, tileW - 6, tileH - 6, COLOR.panel, 5) -- the button below is full screen only
    LV.button(k, tx + 3, ty + 3, tileW - 6, tileH - 6, "", function()
      if wgt.bp and wgt.bp.phase == "pick" and wgt.lastT then bpChoose(wgt, wgt.lastT, i) end
    end, 0, { color = COLOR.panel })
    LV.text(k, tx + 18, ty + tileH / 2 - 12, 60, tostring(i), DBLSIZE, COLOR.white)
    LV.text(k, tx + 18, ty + tileH - 22, tileW - 30, label, fitFontMeasured(tileW - 30, 27, label, SMLSIZE), COLOR.dim)
    LV.text(k, tx + tileW / 2, ty + 16, tileW / 2 - 12, "current", SMLSIZE, COLOR.green, RIGHT, {
      visible = function() return LV.v.battProfile == i end })
  end
  local hy = h - pad - hintH
  LV.rect(k, pad, hy, panelW, hintH, COLOR.panel, 6)
  LV.text(k, pad + 14, hy + hintH / 2, panelW - 28, LV.dv("bpHint", ""), SMLSIZE, COLOR.dim)
end

function LV.buildFlightLog(k, wgt, w, h)
  LV.topBar(k, wgt, w, false)
  local pad, y = 12, LV.Y1
  local panelW = w - pad * 2
  local s = wgt.samples
  local titleH = 40
  LV.rect(k, pad, y, panelW, titleH, COLOR.panel, 6)
  LV.text(k, pad + 14, y + titleH / 2, 200, "Flight log", MIDSIZE, COLOR.white)
  LV.text(k, pad + 14 + 170, y + titleH / 2, 300, LV.v.model or "", SMLSIZE, COLOR.dim)
  -- outside full screen there are no buttons: the countdown shows as text
  LV.rect(k, pad + panelW - 8 - 150, y + 5, 150, titleH - 10, COLOR.barBg, 6)
  LV.text(k, pad + panelW - 8 - 150, y + titleH / 2, 150, LV.dv("closeText", "Close"), SMLSIZE, COLOR.white, CENTER)
  LV.button(k, pad + panelW - 8 - 150, y + 5, 150, titleH - 10, "", function()
    wgt.showFlightLog = false
  end, SMLSIZE, { text = LV.dv("closeText", "Close") })

  local stats = flightSampleStats(wgt)
  local power = "--"
  if wgt.maxPower then
    power = (wgt.maxPower >= 1000) and (fmt(wgt.maxPower / 1000, 1) .. "kW") or (fmt(wgt.maxPower, 0) .. "W")
  end
  local rows = {
    { { "Flight time", fmtTime(wgt.flightSeconds) },
      { "Max rpm", wgt.maxHeadspeed and fmt(wgt.maxHeadspeed, 0) or "--", stats.avgRpm and ("avg " .. fmt(stats.avgRpm, 0)) },
      { "Max amps", wgt.maxCurrent and (fmt(wgt.maxCurrent, 1) .. "A") or "--", stats.avgCur and ("avg " .. fmt(stats.avgCur, 0) .. "A") },
      { "Max power", power } },
    { { "Used", wgt.maxCapacity and (fmt(wgt.maxCapacity, 0) .. "mAh") or "--", wgt.minCharge and (fmt(wgt.minCharge, 0) .. "% left") },
      { "Min volt", wgt.minVoltage and (fmt(wgt.minVoltage, 1) .. "v") or "--", wgt.minCellVoltage and ("cell " .. fmt(wgt.minCellVoltage, 2)) },
      { "Min Bec", wgt.minBecVoltage and (fmt(wgt.minBecVoltage, 1) .. "v") or "--" },
      { "Max ESC", wgt.maxEscTemp and (fmt(wgt.maxEscTemp, 0) .. "\194\176C") or "--" } },
  }
  local tabH, rowGap = 62, 8
  local tabW = math.floor(panelW / 4)
  local ty = y + titleH + pad
  for r = 1, 2 do
    LV.rect(k, pad, ty, panelW, tabH, COLOR.panel, 6)
    for i = 1, 4 do
      local tb = rows[r][i]
      local tx = pad + (i - 1) * tabW
      if i > 1 then LV.rect(k, tx, ty + 10, 1, tabH - 20, COLOR.muted) end
      local key = "fl" .. r .. i
      LV.v[key], LV.v[key .. "n"] = tb[2], tb[3] or ""
      LV.tab(k, tx + 2, ty + 1, tabW - 4, tabH - 2, tb[1], key, key .. "n")
    end
    ty = ty + tabH + rowGap
  end

  local gy = ty - rowGap + pad
  local gh = h - pad - gy
  LV.rect(k, pad, gy, panelW, gh, COLOR.panel, 6)
  local rpmB, rpmS = chartAxis(0, stats.maxRpm, true)
  local curB, curS = chartAxis(0, stats.maxCur, true)
  local vB, vS = chartAxis(stats.minV or 0, stats.maxV or 1, false)
  local defs = {
    { series = s.rpm, bottom = rpmB, step = rpmS, color = COLOR.accent, label = "Headspeed",
      note = wgt.maxHeadspeed and ("max " .. fmt(wgt.maxHeadspeed, 0)) },
    { series = s.current, bottom = curB, step = curS, color = COLOR.orange, label = "Current A",
      note = wgt.maxCurrent and ("max " .. fmt(wgt.maxCurrent, 1)) },
    { series = s.voltage, bottom = vB, step = vS, color = COLOR.green, label = "Voltage v",
      note = wgt.minVoltage and ("min " .. fmt(wgt.minVoltage, 1)) },
  }
  local lx, ly = pad + 14, gy + 1 + TAB_LABEL_H / 2 + 1
  for _, d in ipairs(defs) do
    LV.rect(k, lx, ly - 4, 14, 8, d.color)
    lx = lx + 20
    local text = d.label .. (d.note and ("  " .. d.note) or "")
    LV.text(k, lx, ly, textWidth(text, SMLSIZE) + 4, text, SMLSIZE, COLOR.dim)
    lx = lx + textWidth(text, SMLSIZE) + 26
  end
  -- chart: grid, value labels, one polyline per series, time ticks
  local cx, cyTop = pad + 8, gy + TAB_LABEL_H + 16
  local cw, ch = panelW - 16, gh - TAB_LABEL_H - 16 - 28
  local px, pw = cx + 46, cw - 46 - 90
  local base, top = cyTop + ch - 1, ch - 1
  for q = 1, CHART_DIVS do LV.rect(k, px, base - math.floor(q * top / CHART_DIVS), pw, 1, COLOR.barBg) end
  LV.rect(k, px, base, pw, 1, COLOR.muted)
  local n = #s.rpm
  if n < 2 then
    LV.text(k, px, cyTop + ch / 2, pw, "No data", SMLSIZE, COLOR.muted, CENTER)
    return
  end
  local labelX = { px - 46, px + pw + 6, px + pw + 6 + 45 }
  local labelAlign = { RIGHT, LEFT, LEFT }
  for i, d in ipairs(defs) do
    local decimals = (isWhole(d.step) and isWhole(d.bottom)) and 0 or 1
    for q = 0, CHART_DIVS do
      LV.text(k, labelX[i], base - math.floor(q * top / CHART_DIVS), 40, fmt(d.bottom + q * d.step, decimals),
        SMLSIZE, d.color, labelAlign[i])
    end
    local pts, idxStep = {}, n / pw
    local scale = top / (CHART_DIVS * d.step)
    for x = 0, pw - 1, 4 do
      local v = (d.series[math.floor(x * idxStep) + 1] - d.bottom) * scale
      if v < 0 then v = 0 elseif v > top then v = top end
      pts[#pts + 1] = { px + x, base - math.floor(v) }
    end
    k[#k + 1] = { type = "line", pts = pts, color = d.color, thickness = 2 }
  end
  local dur = n * s.interval
  local tStep = TIME_STEPS[#TIME_STEPS]
  for i = 1, #TIME_STEPS do
    if dur / TIME_STEPS[i] <= 3 then tStep = TIME_STEPS[i]; break end
  end
  local tt = 0
  while tt <= dur do
    local tx = px + math.floor(tt / dur * (pw - 1))
    LV.rect(k, tx, cyTop + ch, 1, 4, COLOR.muted)
    LV.text(k, tx - 30, cyTop + ch + 13, 60, fmtTime(tt), SMLSIZE, COLOR.muted, CENTER)
    tt = tt + tStep
  end
end

-- FC settings page (read only): FC.pages[wgt.infoView], parsed from the
-- MSP reply in wgt.fc. Built again whenever that reply changes.
function LV.buildFcView(k, wgt, w, h, t, parsed)
  LV.topBar(k, wgt, w, false)
  local pad, y = 12, LV.Y1
  local panelW = w - pad * 2
  local page = FC.pages[wgt.infoView]
  local titleH = 44
  LV.rect(k, pad, y, panelW, titleH, COLOR.panel, 6)
  LV.text(k, pad + 14, y + titleH / 2, 260, page.title, MIDSIZE, COLOR.white)
  local sub = ""
  if page.cmd == 111 then sub = "Rate profile " .. (t.bank and fmt(t.bank, 0) or "--")
  elseif page.cmd ~= nil then sub = "PID profile " .. (t.pidProfile and fmt(t.pidProfile, 0) or "--") end
  if parsed and parsed.note then sub = sub .. "   " .. parsed.note end
  LV.text(k, pad + 270, y + titleH / 2, 260, sub, SMLSIZE, COLOR.dim)
  LV.text(k, pad + panelW - 214, y + titleH / 2, 200, wgt.infoView .. " / " .. #FC.pages, SMLSIZE, COLOR.muted, RIGHT)
  -- full screen only (buttons): next page / close
  LV.button(k, pad + panelW - 8 - 100 - 8 - 100, y + 6, 100, titleH - 12, "Next", function()
    local n = (wgt.infoView or 0) + 1
    wgt.infoView = (n <= #FC.pages) and n or 1
    wgt.fc = wgt.fc or {}
    wgt.fc[FC.pages[wgt.infoView].cmd] = CONFIG.simulate and FC.sim[FC.pages[wgt.infoView].cmd] or nil
  end, 0)
  LV.button(k, pad + panelW - 8 - 100, y + 6, 100, titleH - 12, "Close", function() wgt.infoView = nil end, 0)

  local hintH = 36
  local cy, ch = y + titleH + pad, h - pad - hintH - pad - (y + titleH + pad)
  LV.rect(k, pad, cy, panelW, ch, COLOR.panel, 6)
  if not parsed then
    LV.text(k, pad, cy + ch / 2, panelW, "Reading from the FC...", MIDSIZE, COLOR.dim, CENTER)
  elseif parsed.kind == "table" then
    local n = #parsed.cols
    local headW, gap, cellH = 150, 8, 58
    local cellW = math.floor((panelW - 28 - headW - (n - 1) * gap) / n)
    local x0, y0 = pad + 14 + headW, cy + 12
    for c = 1, n do
      LV.text(k, x0 + (c - 1) * (cellW + gap), y0 + 12, cellW, parsed.cols[c], SMLSIZE, COLOR.dim, CENTER)
    end
    for r, row in ipairs(parsed.rows) do
      local ry = y0 + 28 + (r - 1) * (cellH + gap)
      LV.text(k, pad + 18, ry + cellH / 2, headW - 10, row[1], LV.fitFont(row[1], headW - 14, MIDSIZE), COLOR.white)
      for c = 1, n do
        local cx = x0 + (c - 1) * (cellW + gap)
        LV.rect(k, cx, ry, cellW, cellH, COLOR.barBg, 4)
        local text = tostring(row[2][c] or "--")
        LV.text(k, cx, ry + cellH / 2, cellW, text, LV.fitFont(text, cellW - 8, MIDSIZE), COLOR.white, CENTER)
      end
    end
  else
    local cols, gap, tileH = 4, 8, 62
    local tileW = math.floor((panelW - 28 - (cols - 1) * gap) / cols)
    for i, it in ipairs(parsed.items) do
      local tx = pad + 14 + ((i - 1) % cols) * (tileW + gap)
      local ty = cy + 12 + math.floor((i - 1) / cols) * (tileH + gap)
      LV.rect(k, tx, ty, tileW, tileH, COLOR.barBg, 4)
      local key = "fcItem" .. i
      LV.v[key] = tostring(it[2] or "--")
      LV.tab(k, tx, ty, tileW, tileH, it[1], key)
    end
  end
  local hy = h - pad - hintH
  LV.rect(k, pad, hy, panelW, hintH, COLOR.panel, 6)
  LV.text(k, pad + 14, hy + hintH / 2, panelW - 28,
    "Read only  -  Page switch: next page  -  edit: full screen > Menu > Rotorflight settings", SMLSIZE, COLOR.dim)
end

-- Settings (full screen only: everything here is a button). Group tabs on
-- the left, the group's SETTINGS on the right; values save at once.
function LV.buildSettings(k, wgt, w, h)
  local pad, y = 12, 12
  local panelW = w - pad * 2
  local titleH = 48
  LV.rect(k, pad, y, panelW, titleH, COLOR.panel, 6)
  LV.text(k, pad + 14, y + titleH / 2, 300, "Settings", MIDSIZE, COLOR.white)
  LV.text(k, pad + 200, y + titleH / 2, 330, "Saved on the SD card (over widget options)", SMLSIZE, COLOR.dim)
  LV.button(k, pad + panelW - 8 - 110, y + 6, 110, titleH - 12, "Close", function() wgt.settings = nil end, 0)
  local cy = y + titleH + pad
  local ch = h - pad - cy
  local tabW = 170
  LV.rect(k, pad, cy, tabW, ch, COLOR.panel, 6)
  for i, g in ipairs(SET.groups) do
    LV.button(k, pad + 8, cy + 8 + (i - 1) * 64, tabW - 16, 56, g, function() wgt.settings.group = g end, MIDSIZE, {
      color = function() return (wgt.settings and wgt.settings.group == g) and COLOR.accent or COLOR.barBg end })
  end
  local rx, rw = pad + tabW + pad, panelW - tabW - pad
  LV.rect(k, rx, cy, rw, ch, COLOR.panel, 6)
  local x0 = rx + 230
  local row = 0
  for _, def in ipairs(SETTINGS) do
    if def.group == wgt.settings.group then
      local ry = cy + 10 + row * 60
      row = row + 1
      local mid = ry + 26
      LV.text(k, rx + 16, mid, 230, def.label, 0, COLOR.white)
      local key = "set_" .. def.key
      if def.kind == "number" then
        LV.button(k, x0, ry, 64, 52, "-", function() SET.set(def, SET.value(wgt, def) - def.step) end, MIDSIZE)
        LV.text(k, x0 + 72, mid, 160, LV.dv(key, ""), MIDSIZE, COLOR.white, CENTER)
        LV.button(k, x0 + 240, ry, 64, 52, "+", function() SET.set(def, SET.value(wgt, def) + def.step) end, MIDSIZE)
      elseif def.kind == "bool" then
        LV.button(k, x0, ry, 200, 52, "", function() SET.set(def, not SET.value(wgt, def)) end, MIDSIZE, {
          text = LV.dv(key, ""),
          color = function() return SET.value(wgt, def) and COLOR.accent or COLOR.barBg end })
        if def.test == "tones" then -- the four effects in a row
          LV.button(k, x0 + 274, ry, 84, 52, "Test", function()
            for _, name in ipairs({ "connect", "caution", "critical", "disconnect" }) do playEffect(wgt, name, true) end
          end, 0)
        end
      elseif #def.choices <= 3 then
        for c, label in ipairs(def.choices) do
          LV.button(k, x0 + (c - 1) * 108, ry, 100, 52, label, function() SET.set(def, c - 1) end, 0, {
            color = function() return SET.value(wgt, def) == c - 1 and COLOR.accent or COLOR.barBg end })
        end
      else
        local n = #def.choices
        LV.button(k, x0, ry, 64, 52, "<", function() SET.set(def, (SET.value(wgt, def) - 1) % n) end, MIDSIZE)
        LV.text(k, x0 + 68, mid, 128, LV.dv(key, ""), 0, COLOR.white, CENTER)
        LV.button(k, x0 + 200, ry, 64, 52, ">", function() SET.set(def, (SET.value(wgt, def) + 1) % n) end, MIDSIZE)
        if def.test then
          LV.button(k, x0 + 274, ry, 84, 52, "Test", function()
            if playFile then playFile(CONFIG.alarm.dir .. voiceSetDir(wgt) .. "/armed.wav") end
          end, 0)
        end
      end
    end
  end
end

-- small zones (not the 800x480 layout): headspeed + pack voltage
function LV.buildSmall(k, wgt, w, h)
  LV.rect(k, 0, 0, w, h, COLOR.bg)
  LV.text(k, 6, h / 2, w / 2, LV.dv("rpm", "--"), (h >= 60) and MIDSIZE or 0, COLOR.white)
  LV.text(k, w / 2, h / 2, w / 2 - 6, LV.dv("volt", "--"), (h >= 60) and MIDSIZE or 0, COLOR.white, RIGHT)
end

-- menu card over standby / dashboard (Rotorflight / ExpressLRS / battery)
function LV.buildMenu(k, wgt, w, h)
  local mw, rowH = 460, 56
  local mh = 56 + #MENU_ITEMS * (rowH + 8) + 56
  local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
  local vis = function() return wgt.menu ~= nil end
  LV.rect(k, mx, my, mw, mh, COLOR.accent, 8, { visible = vis })
  LV.rect(k, mx + 2, my + 2, mw - 4, mh - 4, COLOR.panel, 7, { visible = vis })
  LV.text(k, mx + 20, my + 28, 300, "Menu", MIDSIZE, COLOR.white, LEFT, { visible = vis })
  for i, item in ipairs(MENU_ITEMS) do
    local ry = my + 56 + (i - 1) * (rowH + 8)
    LV.button(k, mx + 14, ry, mw - 28, rowH, item.label, function()
      if wgt.menu and wgt.lastT then openMenuItem(wgt, wgt.lastT, LV.v.connected, item.key) end
    end, MIDSIZE, { visible = vis, textColor = LV.dv("menuColor" .. i, COLOR.white) })
  end
  LV.button(k, mx + mw - 14 - 140, my + mh - 50, 140, 40, "Close", function() wgt.menu = nil end, 0, { visible = vis })
  LV.text(k, mx + 20, my + mh - 30, mw - 200, LV.dv("menuNote", ""), SMLSIZE, COLOR.dim, LEFT, { visible = vis })
end

function LV.buildToolMsg(k, wgt, w, h)
  local vis = function() return LV.v.toolMsg ~= nil end
  LV.rect(k, 40, h - 64, w - 80, 44, COLOR.red, 6, { visible = vis })
  LV.text(k, 50, h - 42, w - 100, LV.dv("toolMsg", ""), SMLSIZE, COLOR.white, CENTER, { visible = vis })
end

function LV.build(wgt, screen, t, parsed)
  local w, h = wgt.zone.w, wgt.zone.h
  local k = {}
  LV.rect(k, 0, 0, w, h, COLOR.bg)
  if screen == "small" then
    LV.buildSmall(k, wgt, w, h)
  elseif screen == "standby" then
    LV.buildStandby(k, wgt, w, h)
  elseif screen == "busy" then
    LV.text(k, 20, h / 2, w - 40, LV.dv("busy", ""), MIDSIZE, COLOR.white, CENTER)
  elseif screen == "armwarning" then
    LV.buildArmWarning(k, wgt, w, h, t.armd)
  elseif screen == "battselect" then
    LV.buildBattSelect(k, wgt, w, h)
  elseif screen == "flightlog" then
    LV.buildFlightLog(k, wgt, w, h)
  elseif screen == "fcview" then
    LV.buildFcView(k, wgt, w, h, t, parsed)
  elseif screen == "settings" then
    LV.buildSettings(k, wgt, w, h)
  else
    LV.buildDashboard(k, wgt, w, h)
  end
  if screen == "standby" or screen == "dashboard" then LV.buildMenu(k, wgt, w, h) end
  if screen ~= "small" then LV.buildToolMsg(k, wgt, w, h) end
  if CONFIG.perfOverlay and screen ~= "small" then
    LV.text(k, w - 304, h - 10, 300, LV.dv("perf", ""), SMLSIZE, COLOR.dim, RIGHT)
  end
  lvgl.clear()
  lvgl.build(k)
end

-- Per-frame values for the labels of the current screen.
function LV.update(wgt, t, screen, connected, armed)
  local v = LV.v
  v.connected, v.armed = connected, armed
  local okFull, full = pcall(lvgl.isFullScreen)
  v.full = okFull and full or false
  local info = model and model.getInfo and model.getInfo()
  v.model = info and info.name or ""
  if wgt.toolMsg and getTime() - wgt.toolMsg.at <= 300 then v.toolMsg = wgt.toolMsg.text
  else wgt.toolMsg, v.toolMsg = nil, nil end
  local ok, dt = pcall(getDateTime)
  if not ok then dt = nil end
  local txPct, txV = getTxBatteryPct()
  v.txPct, v.txColor = txPct or 0, getChargeColor(txPct)

  if screen == "small" then
    v.rpm, v.volt = fmt(t.rpm, 0), fmtUnit(t.voltage, 1, "v")
    return
  end
  if screen == "standby" then
    v.hhmm = dt and string.format("%02d:%02d", dt.hour, dt.min) or ""
    v.date = dt and string.format("%04d/%02d/%02d", dt.year, dt.mon, dt.day) or ""
    v.standbyHint = touchHint() or "Power on the model"
    v.txV = txV and (fmt(txV, 1) .. "v") or "--"
    v.txPctText = txPct and (fmt(txPct, 0) .. "%") or ""
    v.lastFlight = (wgt.flightSeconds or 0) > 0 and fmtTime(wgt.flightSeconds) or "--"
    v.lastUsed = wgt.maxCapacity and (fmt(wgt.maxCapacity, 0) .. "mAh") or ""
    local labels = CONFIG.alarm.voiceLabels
    local voiceIdx = math.floor(USER.voice or (wgt.options and wgt.options.Voice) or 0)
    v.voice = labels[voiceIdx + 1] or labels[1]
    if not CONFIG.alarm.enabled then v.alarms, v.alarmsColor = "Off", COLOR.grey
    elseif wgt.alarmMuted then v.alarms, v.alarmsColor = "Muted", COLOR.orange
    else v.alarms, v.alarmsColor = "On", COLOR.green end
  else
    v.clock = dt and string.format("%04d/%02d/%02d %02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min) or ""
    v.sig = t.signal or 0
    local warnings = {}
    if t.perCellVoltage and t.perCellVoltage < CONFIG.vCellWarn then
      warnings[#warnings + 1] = string.format("Low cell voltage: %.2fv", t.perCellVoltage)
    end
    if t.temp and t.temp >= CONFIG.escTempWarn then
      warnings[#warnings + 1] = string.format("Esc temp high: %d\194\176C", math.floor(t.temp))
    end
    v.warn = (#warnings > 0) and warnings[math.floor(getTime() / 200) % #warnings + 1] or ""
  end

  if screen == "dashboard" then
    v.volt, v.voltMin = fmtUnit(t.voltage, 1, "v"), wgt.minVoltage and ("min " .. fmt(wgt.minVoltage, 1) .. "v") or ""
    v.vcel = fmtUnit(t.perCellVoltage, 2, "v")
    v.curr, v.currMax = fmtUnit(t.current, 1, "A"), wgt.maxCurrent and ("max " .. fmt(wgt.maxCurrent, 1) .. "A") or ""
    v.bec, v.becMin = fmtUnit(t.becV, 1, "v"), wgt.minBecVoltage and ("min " .. fmt(wgt.minBecVoltage, 1) .. "v") or ""
    v.rpm, v.rpmMax = fmt(t.rpm, 0), wgt.maxHeadspeed and ("max " .. fmt(wgt.maxHeadspeed, 0)) or ""
    if t.armFlags ~= nil then
      v.arm, v.armColor = armed and "Armed" or "Disarmed", armed and COLOR.green or COLOR.grey
    else
      v.arm, v.armColor = "N/a", COLOR.muted
    end
    if t.gov then
      v.govLabel, v.gov, v.govColor = "Governor", toSentenceCase(t.gov), getGovColor(t.gov)
    else
      local running = t.rpm and t.rpm > CONFIG.rpmRunningThreshold
      v.govLabel, v.gov, v.govColor = "Motor", running and "On" or "Off", running and COLOR.green or COLOR.grey
    end
    v.flight = fmtTime(wgt.flightSeconds)
    if t.pidProfile and t.bank then v.profile = fmt(t.pidProfile, 0) .. "/" .. fmt(t.bank, 0)
    elseif t.bank then v.profile = fmt(t.bank, 0)
    elseif t.pidProfile then v.profile = fmt(t.pidProfile, 0)
    else v.profile = "--" end
    if t.charge and t.capacity then v.battValue = fmt(t.charge, 0) .. "% / " .. fmt(t.capacity, 0) .. "mAh"
    elseif t.charge then v.battValue = fmtUnit(t.charge, 0, "%")
    elseif t.capacity then v.battValue = fmt(t.capacity, 0) .. "mAh"
    else v.battValue = "--" end
    local battLabel = "Battery"
    if t.battProfile then
      battLabel = "Battery #" .. t.battProfile
      local cap = wgt.battCaps and wgt.battCaps[t.battProfile]
      local custom = CONFIG.batteryProfile.labels[t.battProfile]
      if cap and cap > 0 then battLabel = battLabel .. " " .. cap .. "mAh"
      elseif custom and custom ~= "Profile " .. t.battProfile then battLabel = battLabel .. " " .. custom end
    end
    v.battLabel, v.charge, v.battColor = battLabel, t.charge or 0, getChargeColor(t.charge)
    v.thrLabel, v.thr = "Throttle", t.throttle or 0
    if t.throttle and t.temp then v.thrValue = fmt(t.throttle, 0) .. "% / " .. fmt(t.temp, 0) .. "\194\176C"
    elseif t.throttle then v.thrValue = fmtUnit(t.throttle, 0, "%")
    elseif t.temp then v.thrValue = fmt(t.temp, 0) .. "\194\176C"
    else v.thrValue = "--" end
  elseif screen == "battselect" and wgt.bp then
    local bp, cfg, now = wgt.bp, CONFIG.batteryProfile, getTime()
    v.battProfile = t.battProfile
    v.bpStatus, v.bpStatusColor = "Select before flight", COLOR.dim
    if bp.phase == "send" then
      v.bpStatus = "Applying " .. tostring(bp.target) .. "..."
    elseif bp.phase == "done" then
      if bp.result == "fail" then v.bpStatus, v.bpStatusColor = "No change - FC did not respond", COLOR.red
      else v.bpStatus, v.bpStatusColor = "Profile " .. tostring(t.battProfile or bp.sel) .. " set", COLOR.green end
    end
    if bp.phase == "pick" then
      local left = cfg.timeoutSec - math.floor((now - (bp.lastInput or bp.since)) / 100)
      if bp.stepped then
        left = cfg.applyIdleSec - math.floor((now - bp.lastInput) / 100)
        v.bpHint = "Applies " .. bp.sel .. " in " .. math.max(0, left) .. "s  -  press again for the next"
      else
        v.bpHint = "Tap a profile, or press the Close switch to step  -  keeps current in " .. math.max(0, left) .. "s"
      end
    else
      v.bpHint = "Arming closes this screen"
    end
  elseif screen == "flightlog" then
    local remain = CONFIG.flightLogTimeoutSec
    if wgt.disconnectTime then remain = math.max(0, remain - math.floor((getTime() - wgt.disconnectTime) / 100)) end
    v.closeText = "Close  " .. remain .. "s"
  end

  if screen == "settings" and wgt.settings then
    for _, def in ipairs(SETTINGS) do
      if def.group == wgt.settings.group then v["set_" .. def.key] = SET.text(wgt, def) end
    end
  end
  if wgt.menu then
    local notes = {}
    for i, item in ipairs(MENU_ITEMS) do
      local okItem, why = menuItemState(wgt, t, connected, item.key)
      v["menuColor" .. i] = okItem and COLOR.white or COLOR.muted
      if not okItem then notes[#notes + 1] = item.label .. ": " .. why end
    end
    v.menuNote = notes[1] or ""
  end
end

function LV.screenType(wgt, t)
  if wgt.settings then return "settings" end
  if not isTelemetryConnected(t) then return wgt.showFlightLog and "flightlog" or "standby" end
  if wgt.armWarningActive then return "armwarning" end
  if wgt.bp and wgt.bp.phase ~= "wait" then return "battselect" end
  if wgt.infoView and FC.pages[wgt.infoView] then return "fcview" end
  return "dashboard"
end

-- refresh() for CONFIG.lvgl. Hosted RF2 runs its own lvgl UI (the official
-- ui_lvgl_runner, as the RfTool widget does) and owns the widget's object
-- tree until it returns 2; this screen is rebuilt afterwards.
function LV.refresh(wgt, t, connected, armed, event, touchState, t0, t1)
  local w, h = wgt.zone.w, wgt.zone.h
  wgt.lastT = t
  -- lvgl controls (buttons, RF2's pages) only exist while the widget is
  -- full screen (EdgeTX 2.12 api_colorlcd_lvgl.cpp buildLvgl skips them
  -- otherwise, App mode included): rebuild when that changes
  local okFull, full = pcall(lvgl.isFullScreen)
  full = okFull and full or false
  if wgt.hosted then
    if armed or not full then
      stopTool(wgt, armed and "Tool closed: armed" or nil)
      wgt.lvScreen = nil
    else
      local run, compiling = wgt.hosted.run, wgt.hosted.compiling
      local ok, ret = pcall(run, event or 0, touchState, false)
      if ok and ret == 0 and rf2 and rf2.mspQueue and not rf2.mspQueue:isProcessed() then
        pcall(rf2.mspQueue.processQueue, rf2.mspQueue)
      end
      if not ok then
        stopTool(wgt, "Tool error: " .. tostring(ret))
        wgt.lvScreen = nil
      elseif ret and ret ~= 0 then
        stopTool(wgt)
        wgt.lvScreen = nil
        if compiling then openMenuItem(wgt, t, connected, "rf2") end
      elseif not compiling then
        return -- RF2's own screen
      else
        LV.v.busy = "Compiling Rotorflight Lua - first start only"
        if wgt.lvScreen ~= "busy" then LV.build(wgt, "busy", t); wgt.lvScreen = "busy" end
        return
      end
    end
  end

  if wgt.settings and (armed or not full) then wgt.settings = nil end
  local screen = (h < 160) and "small" or LV.screenType(wgt, t)
  wgt.lastScreenType = screen
  if (armed or (screen ~= "standby" and screen ~= "dashboard")) then wgt.menu = nil end

  -- keys (full screen only): ENTER = menu / pick / close log, RTN closes
  if event and event ~= 0 then
    if wgt.menu then
      if event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK then wgt.menu = nil end
    elseif screen == "battselect" and wgt.bp and wgt.bp.phase == "pick" then
      if event == EVT_VIRTUAL_NEXT then bpStep(wgt, 1)
      elseif event == EVT_VIRTUAL_PREV then bpStep(wgt, -1)
      elseif event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK then bpChoose(wgt, t)
      elseif event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK then wgt.bp = nil end
    elseif screen == "flightlog" and (event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK) then
      wgt.showFlightLog = false
    elseif (screen == "dashboard" or screen == "standby") and not armed
           and (event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK) then
      wgt.menu = { sel = 1 }
    end
  end

  -- fcview: rebuilt when its page or the FC reply changes
  local sub, parsed = nil, nil
  if screen == "fcview" then
    local page = FC.pages[wgt.infoView]
    local buf = wgt.fc and wgt.fc[page.cmd]
    if buf then
      if wgt.fcParsedBuf ~= buf then
        local okP, res = pcall(page.parse, buf)
        wgt.fcParsed, wgt.fcParsedBuf = okP and res or nil, buf
      end
      parsed = wgt.fcParsed
    end
    sub = wgt.infoView .. ":" .. tostring(buf)
  elseif screen == "settings" then
    sub = "set:" .. wgt.settings.group
  end
  if wgt.lvScreen ~= screen or wgt.lvTheme ~= COLOR or wgt.lvW ~= w or wgt.lvH ~= h or wgt.lvFull ~= full
     or wgt.lvSub ~= sub
     or wgt.lvModel ~= wgt.modelImagePath or (screen == "armwarning" and wgt.lvArmd ~= t.armd) then
    LV.update(wgt, t, screen, connected, armed)
    LV.build(wgt, screen, t, parsed)
    wgt.lvSub = sub
    wgt.lvScreen, wgt.lvTheme, wgt.lvW, wgt.lvH, wgt.lvModel, wgt.lvArmd = screen, COLOR, w, h, wgt.modelImagePath, t.armd
    wgt.lvFull = full
  else
    LV.update(wgt, t, screen, connected, armed)
  end
  -- frame timing (same numbers as perfOverlay, shown by a label)
  if CONFIG.perfOverlay then
    local p = wgt.perf
    if not p then p = { n = 0, tick = 0, ui = 0, frame = 0 }; wgt.perf = p end
    if p.last then p.frame = p.frame + (t0 - p.last) end
    p.last = t0
    p.n, p.tick, p.ui = p.n + 1, p.tick + (t1 - t0), p.ui + (getTime() - t1)
    if p.n >= 20 then
      local fps10 = math.floor(p.n * 1000 / math.max(p.frame, 1))
      local okKb, kb = pcall(collectgarbage, "count")
      if not okKb or type(kb) ~= "number" then kb = 0 end
      LV.v.perf = string.format("%d.%d fps  tick %d  lua %d ms  %dk", math.floor(fps10 / 10), fps10 % 10,
        math.floor(p.tick * 10 / p.n), math.floor(p.ui * 10 / p.n), math.floor(kb))
      p.n, p.tick, p.ui, p.frame = 0, 0, 0, 0
    end
  end
end

-- Frame timing (CONFIG.perfOverlay), bottom-right: fps, ms per frame in
-- tick() and in drawing / the hosted tool, Lua heap in KB. getTime() is
-- 10ms, so the times are averages over 20 frames.
local function perfOverlay(wgt, t0, t1)
  if not CONFIG.perfOverlay then return end
  local p = wgt.perf
  if not p then p = { n = 0, tick = 0, ui = 0, frame = 0 }; wgt.perf = p end
  local now = getTime()
  if p.last then p.frame = p.frame + (t0 - p.last) end
  p.last = t0
  p.n, p.tick, p.ui = p.n + 1, p.tick + (t1 - t0), p.ui + (now - t1)
  if p.n >= 20 then
    local fps10 = math.floor(p.n * 1000 / math.max(p.frame, 1))
    local ok, kb = pcall(collectgarbage, "count")
    if not ok or type(kb) ~= "number" then kb = 0 end
    p.text = string.format("%d.%d fps  tick %d  ui %d ms  %dk", math.floor(fps10 / 10), fps10 % 10,
      math.floor(p.tick * 10 / p.n), math.floor(p.ui * 10 / p.n), math.floor(kb))
    p.n, p.tick, p.ui, p.frame = 0, 0, 0, 0
  end
  if p.text then lcd.drawText(wgt.zone.w - 4, wgt.zone.h - 10, p.text, RIGHT + VCENTER + SMLSIZE + COLOR.dim) end
end

local function refresh(wgt, event, touchState)
  -- Apply the radio-side "Theme" widget option (0/1/2), if set -
  -- reassigning the COLOR upvalue here means every helper function
  -- below (all of which read COLOR.xxx) picks up the change for this
  -- frame, without needing to thread a theme parameter through each
  -- one individually.
  do
    local idx = USER.theme
    if idx == nil then idx = (wgt.options and wgt.options.Theme) or nil end
    if idx ~= nil then
      idx = math.floor(idx)
      if idx < 0 or idx > 2 then idx = 0 end
      COLOR = COLOR_THEMES[THEME_NAMES[idx + 1]] or COLOR_THEMES.color
    end
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
  ensureTxBatteryIcons(wgt)
  local armed = t.armFlags ~= nil and math.floor(t.armFlags) % 2 == 1
  if CONFIG.lvgl and lvgl then
    return LV.refresh(wgt, t, connected, armed, event, touchState, t0, t1)
  end
  local w, h = wgt.zone.w, wgt.zone.h

  -- A hosted tool (RF2 / ELRS) owns the screen and the keys until it
  -- exits; arming or leaving full-screen closes it (see TOOLS HOST).
  if wgt.hosted then
    if armed then
      stopTool(wgt, "Tool closed: armed")
    elseif touchHint() then
      stopTool(wgt)
    elseif (event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK) and wgt.hosted.exitAt
           and getTime() - wgt.hosted.exitAt < 100 then
      -- RTN twice within 1s: a way out of screens the tool itself won't
      -- leave by RTN (RF2 "Waiting for connection")
      stopTool(wgt)
    else
      if event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK then wgt.hosted.exitAt = getTime() end
      local skinned = wgt.hosted.kind == "rf2" and rf2 and rf2.radio and CONFIG.tools.rf2Skin
      if skinned then
        event = rf2SkinInput(event or 0, touchState)
        RF2UI.nHits = 0
      end
      local ok, ret = pcall(wgt.hosted.run, event or 0, touchState)
      if skinned and RF2UI.quit then ok, ret = true, 2 end
      if ok and ret == 0 and rf2 and rf2.mspQueue and not rf2.mspQueue:isProcessed() then
        -- RF2 runs its MSP queue once per frame: a second pass sends the
        -- next request right after a reply instead of a frame later
        pcall(rf2.mspQueue.processQueue, rf2.mspQueue)
      end
      perfOverlay(wgt, t0, t1)
      if not ok then
        stopTool(wgt, "Tool error: " .. tostring(ret))
      elseif ret and ret ~= 0 then
        local reopen = wgt.hosted.compiling
        stopTool(wgt)
        if reopen then openMenuItem(wgt, t, connected, "rf2"); return end
      else
        return
      end
    end
    event = 0 -- the key that closed the tool isn't for the dashboard
  end
  local consumed = false

  -- A tap or Enter while showing the flight log dismisses it, in favor of
  -- the standby screen, for the rest of this disconnect - only ever
  -- delivered when the widget is full-screen (see the FLIGHT LOG note
  -- near the top of this file). Elsewhere, the "Close" option's switch
  -- (tick()) or the timeout dismisses it instead.
  if not connected and wgt.showFlightLog and event and event ~= 0 and
     (event == EVT_TOUCH_TAP or event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK) then
    wgt.showFlightLog, consumed = false, true
  end

  -- Battery-profile picker, full-screen inputs: tap a tile = apply it,
  -- rotary = move, Enter = apply the highlighted one, RTN = keep current.
  if connected and wgt.bp and wgt.bp.phase == "pick" and event and event ~= 0 then
    consumed = true
    if event == EVT_TOUCH_TAP and touchState and wgt.bpTiles then
      for i = 1, #wgt.bpTiles do
        local r = wgt.bpTiles[i]
        if touchState.x >= r[1] and touchState.x < r[1] + r[3]
           and touchState.y >= r[2] and touchState.y < r[2] + r[4] then
          bpChoose(wgt, t, i)
        end
      end
    elseif event == EVT_VIRTUAL_NEXT then
      bpStep(wgt, 1)
    elseif event == EVT_VIRTUAL_PREV then
      bpStep(wgt, -1)
    elseif event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK then
      bpChoose(wgt, t)
    elseif event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK then
      wgt.bp = nil
    end
  end

  -- Menu (RF2 / ELRS / battery profile): opened by ENTER or a tap on
  -- standby or the dashboard while disarmed; full-screen only, like all
  -- key/touch input.
  local screen = wgt.lastScreenType
  local menuScreen = (screen == "standby" or screen == "dashboard")
  if wgt.menu then
    if armed or not menuScreen then
      wgt.menu = nil
    elseif event and event ~= 0 and not consumed then
      consumed = true
      local sel = wgt.menu.sel
      if event == EVT_VIRTUAL_NEXT then
        wgt.menu.sel = sel % #MENU_ITEMS + 1
      elseif event == EVT_VIRTUAL_PREV then
        wgt.menu.sel = (sel - 2) % #MENU_ITEMS + 1
      elseif event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK then
        openMenuItem(wgt, t, connected, MENU_ITEMS[sel].key)
      elseif event == EVT_VIRTUAL_EXIT or event == EVT_EXIT_BREAK then
        wgt.menu = nil
      elseif event == EVT_TOUCH_TAP and touchState then
        local hit
        for i, r in ipairs(wgt.menuRects or {}) do
          if touchState.x >= r[1] and touchState.x < r[1] + r[3]
             and touchState.y >= r[2] and touchState.y < r[2] + r[4] then hit = i end
        end
        if hit then
          wgt.menu.sel = hit
          openMenuItem(wgt, t, connected, MENU_ITEMS[hit].key)
        else
          wgt.menu = nil -- tap outside the card
        end
      end
    end
  elseif event and event ~= 0 and not consumed and not armed and menuScreen and h >= 160
         and (event == EVT_VIRTUAL_ENTER or event == EVT_ENTER_BREAK or event == EVT_TOUCH_TAP) then
    wgt.menu = { sel = 1 }
  end

  if h < 60 then
    drawSmall(wgt, t, w, h)
  elseif h < 160 then
    drawMedium(wgt, t, w, h)
  else
    drawLarge(wgt, t, w, h)
    if wgt.menu then drawMenu(wgt, t, connected, w, h) end
    drawToolMsg(wgt, w, h)
    perfOverlay(wgt, t0, t1)
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
-- "BattSel" (optional) picks the battery profile with a multi-position
-- source - a pot or slider cut into 6 bands, applied 3s after connecting.
-- Not for one of the MK3 SW1..SW6 buttons (2-position: only 1 or 6) -
-- use "BattSW" for those. Both work without full-screen mode.
-- "BattSW" (on/off): SW1..SW6 pick the profile, button n = profile n.
-- "BattPrev" (optional) steps the picker back one profile ("Close" steps
-- forward) - meant for a trim button through a logical switch.
local options = {
  { "Theme", VALUE, 0, 0, 2 }, -- 0=color, 1=mono, 2=cyan
  { "Mute", SOURCE, 0 },
  { "Voice", VALUE, 0, 0, 5 },
  { "Close", SOURCE, 0 },
  { "BattLand", VALUE, 20, 10, 50 },
  { "BattSel", SOURCE, 0 },
  { "BattPrev", SOURCE, 0 },
  { "BattSW", BOOL, 0 },
  { "Page", SOURCE, 0 },
}

return {
  name = "RF Telem",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background,
  useLvgl = (CONFIG.lvgl and lvgl ~= nil) or nil,
}
