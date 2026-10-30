-- EdgeTX API stubs + scenario driver for RFTelem (CONFIG.simulate = true).
-- ARGS: "mute" -> Mute source active 30..60s, "bg" -> background() only 40..60s,
--       "draw" -> report out-of-screen draw calls, "voiceN" -> Voice option N,
--       "droplink" / "lowbatt" / "native" / "armdthr" / "fallback" -> scenario patches.
NOW = 0
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
getTime = function() return NOW end
local muteVal = 0
getValue = function(src)
  if src == "tx-voltage" then return 7.9 end
  if src == 999 then return muteVal end
  -- "close": Close switch pressed for 0.5s at 90s (flight log is up 75..135s)
  if src == 998 then return (opts.close and NOW >= 9000 and NOW < 9050) and 1024 or -1024 end
  return 0
end
getFieldInfo = function() return nil end
getDateTime = function() return { year = 2026, mon = 10, day = 30, hour = 1, min = 2 } end
model = { getInfo = function() return { name = "S2 Ultra", bitmap = "" } end }
playFile = function(p) print("PLAY " .. p) end
local haptics = 0
playHaptic = function(d, p) haptics = haptics + 1 end

local src = MAIN_SRC:gsub("simulate = false,", "simulate = true,", 1)
local function patch(from, to)
  local n; src, n = src:gsub(from, to, 1)
  assert(n == 1, "patch failed: " .. from)
end
if opts.droplink then patch("if s < 5 or s >= 75 then", "if s < 5 or s >= 60 then") end
if opts.lowbatt then patch("t%.charge   = lerp%(99, 25, f%)", "t.charge   = lerp(99, 5, f)") end
if opts.native then patch("nativeBackup = false,", "nativeBackup = true,") end
-- ARMD with real reasons: THROTTLE (bit 7) + ANGLE (bit 8) + ARM_SWITCH (bit 26)
if opts.armdthr then patch("t%.armd = 67108872", "t.armd = 67108864 + 128 + 256") end
-- Governor FALLBACK (no headspeed signal) for 6s mid-flight
if opts.fallback then
  patch('t%.armFlags, t%.gov = 1, "ACTIVE"', 't.armFlags, t.gov = 1, (s > 50 and s < 56) and "FALLBACK" or "ACTIVE"')
end
local chunk = assert(load(src, "main.lua"))
local widget = chunk()
-- "voiceN" -> Voice option N (alarm voice set)
-- "landNN" -> BattLand option NN (landing alarm %)
local voiceOpt, landOpt = 0, 20
for a in pairs(opts) do
  local n = a:match("^voice(%d+)$")
  if n then voiceOpt = tonumber(n) end
  local l = a:match("^land(%d+)$")
  if l then landOpt = tonumber(l) end
end
local wgt = widget.create({ x = 0, y = 0, w = 800, h = 480 },
  { Theme = 0, Mute = 999, Voice = voiceOpt, Close = 998, BattLand = landOpt })

-- Lua instructions per refresh() (EdgeTX aborts a frame with "CPU limit"
-- past a fixed instruction budget). Counted in blocks of 100 via a hook;
-- the max per screen type is printed at the end.
local instr, maxInstr, lastInstr = 0, {}, {}
debug.sethook(function() instr = instr + 100 end, "", 100)

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
    local st = wgt.lastScreenType or "?"
    if instr > (maxInstr[st] or 0) then maxInstr[st] = instr end
    lastInstr[st] = instr
    if wgt.lastScreenType and screens[#screens] ~= wgt.lastScreenType then
      screens[#screens + 1] = wgt.lastScreenType
      print("SCREEN " .. wgt.lastScreenType)
    end
  end
end
debug.sethook()
oprint(string.format("haptic pulses: %d, draw calls: %d", haptics, draws))
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
