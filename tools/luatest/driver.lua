-- EdgeTX API stubs + scenario driver for RotorHUD (CONFIG.simulate = true).
-- ARGS: "full" -> widget full screen (lvgl buttons built), "ui" -> full + taps
--       through Menu / Settings / FC pages / flight-log Close (see UI below),
--       "mute" -> Mute source active 30..60s, "bg" -> background() only 40..60s,
--       "draw" -> report out-of-screen draw calls, "voiceN" -> Voice option N,
--       "droplink" / "lowbatt" / "native" / "armdthr" / "fallback" -> scenario patches.
NOW = 0
selOpt, swOpt = nil, nil
local opts = {}
for a in string.gmatch(ARGS or "", "%S+") do opts[a] = true end

-- Lua 5.2 (EdgeTX) truncates non-integers for %d; Lua 5.3 raises. Emulate 5.2.
do
  local orig = string.format
  string.format = function(fmt, ...)
    local args = table.pack(...)
    local i = 0
    for spec in fmt:gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*(%a)") do
      i = i + 1
      if (spec == "d" or spec == "i" or spec == "x" or spec == "X") and type(args[i]) == "number" then
        args[i] = math.floor(args[i])
      end
    end
    return orig(fmt, table.unpack(args, 1, args.n))
  end
end

local oprint = print
print = function(...) oprint(string.format("%7.2fs", NOW / 100), ...) end

LEFT, RIGHT, CENTER, VCENTER = 0, 0x10, 0x20, 0x40
SMLSIZE, MIDSIZE, DBLSIZE, XXLSIZE = 0x300, 0x400, 0x500, 0x600
VALUE, SOURCE, BOOL, COLOR_T = 0, 1, 2, 3
EVT_TOUCH_TAP = 0x1000
SOLID = 0
local FONT = { [SMLSIZE] = { 10, 23 }, [MIDSIZE] = { 19, 42 }, [DBLSIZE] = { 25, 55 }, [XXLSIZE] = { 51, 93 } }
local function fontOf(flags) return FONT[(flags or 0) & 0xF00] or { 12, 27 } end

local issues, draws = {}, 0
local function chk(kind, x, y, w, h, extra)
  draws = draws + 1
  if not opts.draw then return end
  if x < -1 or y < -1 or x + (w or 0) > 801 or y + (h or 0) > 481 then
    issues[#issues + 1] = string.format("%s off-screen x=%d y=%d w=%d h=%d %s", kind, x, y, w or 0, h or 0, extra or "")
  end
end
lcd = {
  -- EdgeTX keeps the color in the upper 16 bits of the flags word
  RGB = function(r, g, b) return (((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)) << 16 end,
  drawFilledRectangle = function(x, y, w, h) chk("rect", x, y, w, h) end,
  drawText = function(x, y, text, flags)
    local f = fontOf(flags); local tw = #tostring(text) * f[1]
    local left = x
    if (flags or 0) & RIGHT ~= 0 then left = x - tw elseif (flags or 0) & CENTER ~= 0 then left = x - tw / 2 end
    chk("text", left, y - f[2] / 2, tw, f[2], tostring(text))
  end,
  drawBitmap = function() end,
  drawLine = function(x1, y1, x2, y2) chk("line", math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1), math.abs(y2 - y1)) end,
  sizeText = function(text, flags) local f = fontOf(flags); return #tostring(text) * f[1], f[2] end,
  loadBitmap = function() return nil end,
}
-- "cpu": near-zero-cost lcd stubs, so the instruction count is mostly the
-- widget's own Lua (on the radio lcd.* are C functions).
if opts.cpu then
  local function noop() end
  lcd.drawFilledRectangle, lcd.drawText, lcd.drawBitmap, lcd.drawLine = noop, noop, noop, noop
  lcd.sizeText = function(text, flags) return #text * 12, 27 end
end
Bitmap = { open = function() return nil end }
LCD_W, LCD_H = 800, 480
-- EdgeTX's Lua has no string methods ("s:match()" fails there, measured in
-- the simulator): take them away here too, so such calls fail in the tests
do
  local meta = getmetatable("")
  local lib = meta.__index
  meta.__index = function(_, k)
    local info = debug.getinfo(2, "S")
    local src = info and info.source or ""
    if string.find(src, "WIDGETS", 1, true) or src == "main.lua" then
      error("string method '" .. tostring(k) .. "' used - EdgeTX's Lua has none", 2)
    end
    return lib[k]
  end
end
LVSTUB = assert(load(FILES["/luatest/lvglstub.lua"], "lvglstub"))()
lvgl = LVSTUB.lvgl
LVSTUB.full = opts.full or opts.ui or false
local tones = 0
playTone = function() tones = tones + 1 end
-- EdgeTX-style io (io.open/io.write(f, ...)/io.read(f, n)/io.close(f)) on an
-- in-memory file system, so settings, history and logs can be checked
MEMFS = {}
-- "settingsoff" / "settingson": a settings.txt saved on the SD before start
-- (Off must load as false: "0" once came back as a truthy 0)
if opts.settingsoff then MEMFS["/WIDGETS/RotorHUD/settings.txt"] = "simple=0\nhaptic=0\n" end
if opts.settingson then MEMFS["/WIDGETS/RotorHUD/settings.txt"] = "simple=1\nhaptic=1\n" end
io = {
  open = function(path, mode)
    mode = mode or "r"
    if mode == "r" and not MEMFS[path] then return nil end
    if mode == "w" or not MEMFS[path] then MEMFS[path] = "" end
    return { path = path, pos = 1 }
  end,
  write = function(f, ...)
    for _, v in ipairs({ ... }) do MEMFS[f.path] = MEMFS[f.path] .. tostring(v) end
  end,
  read = function(f, n)
    local s = MEMFS[f.path]:sub(f.pos, f.pos + n - 1)
    f.pos = f.pos + #s
    return s
  end,
  close = function() end,
}
-- loadScript: the widget folder's files (with the patches below applied)
loadScript = function(path)
  local s = FILES[path]
  if not s then return nil end
  return assert(load(s, path))
end
getTime = function() return NOW end
local muteVal = 0
getValue = function(src)
  if src == "tx-voltage" then return 7.9 end
  if src == 999 then return muteVal end
  -- "selN": BattSel source = 6-pos switch at position N (EdgeTX 6POS values)
  if src == 997 then return ({ -1024, -614, -205, 205, 614, 1024 })[selOpt] or 0 end
  -- "swN": MK3 button SWN on (2-position switches SW1..SW6)
  local swn = type(src) == "string" and src:match("^SW(%d)$")
  if swn then return (tonumber(swn) == swOpt) and 1024 or -1024 end
  -- "bpprev": BattPrev pressed once at 13.0s (picker 12..17s): 1 -> 6
  if src == 996 then return (opts.bpprev and NOW >= 1300 and NOW < 1320) and 1024 or -1024 end
  -- "close": Close switch pressed for 0.5s at 90s (flight log is up 75..135s)
  -- "bpstep": pressed at 13.0s and 13.5s (battery-profile picker, 12..17s)
  if src == 998 then
    if opts.close and NOW >= 9000 and NOW < 9050 then return 1024 end
    if opts.bpstep and ((NOW >= 1300 and NOW < 1320) or (NOW >= 1350 and NOW < 1370)) then return 1024 end
    return -1024
  end
  return 0
end
getFieldInfo = function() return nil end
getDateTime = function() return { year = 2026, mon = 10, day = 30, hour = 1, min = 2 } end
model = { getInfo = function() return { name = "S2 Ultra", bitmap = "" } end }
playFile = function(p) print("PLAY " .. p) end
local haptics = 0
playHaptic = function(d, p)
  haptics = haptics + 1
  if opts.haptics then print(string.format("HAPTIC %d,%d", d, p or 0)) end -- "haptics": each pulse with its time
end

-- patches go to whichever widget file holds the text (main.lua included)
local MAIN_PATH = "/WIDGETS/RotorHUD/main.lua"
FILES[MAIN_PATH] = MAIN_SRC
local function patch(from, to)
  for path, s in pairs(FILES) do
    if path:sub(1, 9) == "/WIDGETS/" then
      local out, n = s:gsub(from, to, 1)
      if n == 1 then FILES[path] = out; return end
    end
  end
  error("patch failed: " .. from)
end
patch("simulate = false,", "simulate = true,")
if opts.droplink then patch("if s < 5 or s >= 75 then", "if s < 5 or s >= 60 then") end
if opts.lowbatt then patch("t%.charge   = lerp%(99, 25, f%)", "t.charge   = lerp(99, 5, f)") end
if opts.native then patch("nativeBackup = false,", "nativeBackup = true,") end
-- "msp": go through the real MSP/CRSF path; the stubbed push logs each
-- frame and then acts as the FC (BAT# follows 0.5s later)
if opts.msp then patch("if CONFIG%.simulate then %-%- no FC", "if false then -- no FC") end
-- ARMD with real reasons: THROTTLE (bit 7) + ANGLE (bit 8) + ARM_SWITCH (bit 26)
if opts.armdthr then patch("t%.armd = 67108872", "t.armd = 67108864 + 128 + 256") end
-- Settings > Display > Simple screen on (light palette, shapes)
if opts.simple then patch("simple = { on = false", "simple = { on = true") end
-- the battery-not-full window: full set above the simulated pack (4.18 V/cell)
if opts.notfull then patch("fullCell = 4%.10", "fullCell = 4.30") end
-- the frame-rate label on (CONFIG.perfOverlay)
if opts.perf then patch("perfOverlay = false", "perfOverlay = true") end
-- the FC's CMS menu open (16384, seen on the radio 2026-11-03): reason + 3 hint lines
if opts.armdcms then patch("t%.armd = 67108872", "t.armd = 16384") end
-- Governor FALLBACK (no headspeed signal) for 6s mid-flight
if opts.fallback then
  patch('t%.armFlags, t%.gov = 1, "ACTIVE"', 't.armFlags, t.gov = 1, (s > 50 and s < 56) and "FALLBACK" or "ACTIVE"')
end
local wgtRef
crossfireTelemetryPush = function(cmd, data)
  if cmd == nil then return true end -- buffer free
  local bytes = {}
  for i = 1, #data do bytes[i] = string.format("%02X", data[i]) end
  print(string.format("CRSF PUSH 0x%02X [%s]", cmd, table.concat(bytes, " ")))
  if wgtRef and cmd == 0x7C and data[5] == 176 then
    wgtRef.simBattPending = { value = data[6] + 1, at = NOW + 50 }
  end
  return true
end

local chunk = assert(load(FILES[MAIN_PATH], "main.lua"))
local widget = chunk()
-- "voiceN" -> Voice option N (alarm voice set)
-- "landNN" -> BattLand option NN (landing alarm %)
local voiceOpt, landOpt = 0, 20
for a in pairs(opts) do
  local sp = a:match("^sel(%d)$")
  if sp then selOpt = tonumber(sp) end
  local sw = a:match("^sw(%d)$")
  if sw then swOpt = tonumber(sw) end
  local n = a:match("^voice(%d+)$")
  if n then voiceOpt = tonumber(n) end
  local l = a:match("^land(%d+)$")
  if l then landOpt = tonumber(l) end
end
local wgt = widget.create({ x = 0, y = 0, w = 800, h = 480 },
  { Theme = 0, Mute = 999, Voice = voiceOpt, Close = 998, BattLand = landOpt,
    BattSel = selOpt and 997 or 0, BattPrev = 996, BattSW = swOpt and 1 or 0 })
wgtRef = wgt

-- Lua instructions per refresh() (EdgeTX aborts a frame with "CPU limit"
-- past a fixed instruction budget). Counted in blocks of 100 via a hook;
-- the max per screen type is printed at the end.
local instr, maxInstr, lastInstr = 0, {}, {}
debug.sethook(function() if not LVSTUB.inC then instr = instr + 100 end end, "", 100)

-- "ui": taps (full screen) at fixed times; each must find its button
local UI_STEPS = {
  { 100, "Menu" }, { 120, "Settings" }, { 140, "Alarms" }, { 150, "+" }, { 160, "Display" },
  { 170, "Mono" }, { 180, "Color" }, { 185, "Flight" }, { 187, "+" }, { 188, "Packs" }, { 193, "edit", "Profile 1", "6S 5000" },
  { 197, "Voice" }, { 205, "Close" },
  { 7320, "Menu" }, { 7340, "View FC settings" }, { 7360, "Next" }, { 7380, "Next" }, { 7400, "Close" },
  { 7410, "Menu" }, { 7420, "Erase blackbox" }, { 7430, "Tap again: erase (25% used)" },
  { 7700, "Close" },
  { 7900, "Menu" }, { 7920, "Flight history" }, { 7950, "Reset" }, { 7960, "Sure?" }, { 8000, "Close" },
}
local uiDone = {}
function UI(now)
  for i, s in ipairs(UI_STEPS) do
    if not uiDone[i] and now >= s[1] then
      uiDone[i] = true
      local ok
      if s[2] == "edit" then ok = LVSTUB.edit(s[3], s[4]) else ok = LVSTUB.press(s[2]) end
      print(string.format("TAP %-18s %s  (screen %s)", s[2], ok and "ok" or "NOT FOUND", tostring(wgt.lastScreenType)))
      if s[2] == "Flight history" then UI_SHOW = now + 10 end
      if s[2] == "Sure?" then UI_RESET = now + 10 end
    end
  end
end

local screens = {}
for step = 0, 145 * 20 do -- 50ms steps over one 140s cycle + a bit
  NOW = step * 5
  muteVal = (opts.mute and NOW >= 3000 and NOW < 6000) and 1024 or 0
  -- "longflight": just before the 75s disconnect, fill the graph samples
  -- to one short of the 400 cap (a long flight's worst case)
  if opts.longflight and NOW == 7400 then
    local s = wgt.samples
    for i = #s.rpm + 1, 399 do
      s.rpm[i], s.current[i], s.voltage[i] = 2100 + i % 7, 40 + i % 30, 50 - i / 50
    end
  end
  if opts.bg and NOW >= 4000 and NOW < 6000 then
    widget.background(wgt)
  else
    instr = 0
    widget.refresh(wgt, 0, nil)
    LVSTUB.frame()
    if opts.ui then UI(NOW) end
    if UI_SHOW and NOW >= UI_SHOW then
      UI_SHOW = nil
      local shown = table.concat(LVSTUB.texts(), " | ")
      print("SHOWN " .. shown)
      -- the flight that ended at 75s must be in the history
      if not string.find(shown, "Flights | 1 |", 1, true) then print("CHECK FAIL: flight history not recorded/read") end
    end
    if UI_RESET and NOW >= UI_RESET then
      UI_RESET = nil
      local shown = table.concat(LVSTUB.texts(), " | ")
      if not string.find(shown, "Flights | 0 |", 1, true) then print("CHECK FAIL: history not reset: " .. shown) end
    end
    -- the erase tapped at 74.3s is done before the link drops at 75s
    if opts.ui and NOW == 7490 and not (wgt.toolMsg and wgt.toolMsg.text == "Blackbox erased"
                                        and wgt.blackbox and wgt.blackbox.used == 0) then
      print("CHECK FAIL: blackbox erase: " .. tostring(wgt.toolMsg and wgt.toolMsg.text))
    end
    if (wgt.fullAlert ~= nil) ~= (FULL_SEEN or false) then -- the battery-not-full window opens / closes
      FULL_SEEN = wgt.fullAlert ~= nil
      print((FULL_SEEN and "FULLALERT open " or "FULLALERT closed ") .. (FULL_SEEN and table.concat(LVSTUB.texts(), " | ") or ""))
    end
    if ARMD_SHOW and NOW >= ARMD_SHOW then
      ARMD_SHOW = nil
      print("SHOWN " .. table.concat(LVSTUB.texts(), " | "))
    end
    local st = wgt.lastScreenType or "?"
    if instr > (maxInstr[st] or 0) then maxInstr[st] = instr end
    lastInstr[st] = instr
    if wgt.lastScreenType and screens[#screens] ~= wgt.lastScreenType then
      screens[#screens + 1] = wgt.lastScreenType
      print("SCREEN " .. wgt.lastScreenType)
      if wgt.lastScreenType == "armwarning" then ARMD_SHOW = NOW + 5 end
    end
  end
end
debug.sethook()
oprint(string.format("haptic pulses: %d, tones: %d, draw calls: %d, lvgl builds: %d", haptics, tones, draws, LVSTUB.builds))
for _, s in ipairs(LVSTUB.issues) do oprint("LVGL " .. s) end
if opts.settingsoff or opts.settingson then
  local sawSimple = false
  for _, sc in ipairs(screens) do if sc == "simple" then sawSimple = true end end
  if sawSimple ~= (opts.settingson == true) then oprint("CHECK FAIL: simple screen from settings.txt: " .. tostring(sawSimple)) end
  if (haptics > 0) ~= (opts.settingson == true) then oprint("CHECK FAIL: vibration from settings.txt: " .. haptics) end
end
if opts.ui then
  local set = MEMFS["/WIDGETS/RotorHUD/settings.txt"] or ""
  if not string.find(set, "pack1=6S 5000\n", 1, true) then oprint("CHECK FAIL: pack name not saved: " .. set) end
end
if opts.files then for path, body in pairs(MEMFS) do oprint("FILE " .. path); oprint(body) end end
-- Includes the stubs' own Lua (real lcd.* calls are C), so read these as
-- relative numbers between versions, not as the radio's real count.
for st, n in pairs(maxInstr) do
  oprint(string.format("Lua instructions/frame  %-11s max %6d  last %6d", st, n, lastInstr[st] or 0))
end
oprint(string.format("flight %.1fs, samples %d, maxPower %.0fW, minCell %.2f",
  wgt.flightSeconds, #wgt.samples.rpm, wgt.maxPower or -1, wgt.minCellVoltage or -1))
local seen = {}
for i = 1, #issues do
  if not seen[issues[i]] then seen[issues[i]] = true; oprint("DRAW " .. issues[i]) end
end
