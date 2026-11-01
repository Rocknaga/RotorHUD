-- RF TELEMETRY test: feeds hand-built Rotorflight CRSF frames through the
-- widget's built-in decoder and MSP client, with CONFIG.simulate = false.
-- Usage: node run.js ../../sdcard/WIDGETS/RFTelem/main.lua decoder_test.lua
NOW = 0
local fails = 0
local function check(name, got, want)
  local ok = (type(want) == "number" and type(got) == "number" and math.abs(got - want) < 1e-6) or got == want
  print(string.format("%-28s %-10s got=%s want=%s", name, ok and "ok" or "FAIL", tostring(got), tostring(want)))
  if not ok then fails = fails + 1 end
end

-- EdgeTX stubs (only what the widget touches)
LEFT, RIGHT, CENTER, VCENTER = 0, 0x10, 0x20, 0x40
SMLSIZE, MIDSIZE, DBLSIZE, XXLSIZE = 0x300, 0x400, 0x500, 0x600
VALUE, SOURCE, BOOL = 0, 1, 2
EVT_TOUCH_TAP, SOLID = 0x1000, 0
UNIT_RAW, UNIT_VOLTS, UNIT_AMPS, UNIT_MAH, UNIT_PERCENT, UNIT_CELLS = 0, 1, 2, 3, 4, 5
UNIT_DEGREE, UNIT_RPMS, UNIT_CELSIUS, UNIT_METERS, UNIT_METERS_PER_SECOND, UNIT_G, UNIT_GPS = 6, 7, 8, 9, 10, 11, 12
local function noop() end
lcd = { RGB = function() return 0 end, drawFilledRectangle = noop, drawText = noop, drawBitmap = noop,
        drawLine = noop, sizeText = function(t) return #t * 12, 27 end, loadBitmap = noop }
Bitmap = { open = noop }
LCD_W, LCD_H = 800, 480
lvgl = assert(load(FILES["/luatest/lvglstub.lua"], "lvglstub"))().lvgl
loadScript = function(path)
  local src = FILES[path]
  return src and assert(load(src, path)) or nil
end
getTime = function() return NOW end
getDateTime = function() return { year = 2026, mon = 11, day = 1, hour = 1, min = 2 } end
model = { getInfo = function() return { name = "S2 Ultra", bitmap = "" } end }
playFile, playHaptic = noop, noop

-- Sensors created through setTelemetryValue, readable back by name
local sensors = {}
setTelemetryValue = function(id, sub, inst, value, unit, prec, name)
  if name then sensors[name] = { id = id, raw = value, prec = prec or 0 } end
end
getFieldInfo = function(name) return sensors[name] and { id = name } or nil end
getValue = function(src)
  if src == "RSSI" then return 100 end
  if src == "tx-voltage" then return 7.9 end
  local s = sensors[src]
  return s and s.raw / 10 ^ s.prec or 0
end

-- CRSF queue: the test pushes frames in, the widget pops them
local queue, pushed = {}, {}
crossfireTelemetryPop = function()
  local f = table.remove(queue, 1)
  if f then return f[1], f[2] end
end

-- MSP_BATTERY_CONFIG (32) reply payload, 4.6 layout, little-endian
local CAPS = { 2500, 5000, 3800, 0, 1200, 20000 }
local function batteryConfigReply()
  local b = { 0x88, 0x13, 12, 1, 1, 0x4A, 0x01, 0xA4, 0x01, 0x9A, 0x01, 0x5E, 0x01, 20, 30 }
  for i = 1, 6 do b[#b + 1] = CAPS[i] % 256; b[#b + 1] = math.floor(CAPS[i] / 256) end
  return b
end
local function mspReplyFrames(cmd, payload)
  -- split like the FC: start frame { status 0x30|seq, size, cmd, data... }, continuations { 0x20|seq, data... }
  local frames, seq, pos, first = {}, 0, 1, true
  while first or pos <= #payload do
    local d = { 0xEA, 0xC8 }
    if first then d[#d + 1] = 0x30 + seq; d[#d + 1] = #payload; d[#d + 1] = cmd
    else d[#d + 1] = 0x20 + seq end
    while pos <= #payload and #d < 20 do d[#d + 1] = payload[pos]; pos = pos + 1 end -- small chunks to force continuation
    frames[#frames + 1] = { 0x7B, d }
    seq, first = (seq + 1) % 16, false
  end
  return frames
end
crossfireTelemetryPush = function(cmd, data)
  if cmd == nil then return true end
  pushed[#pushed + 1] = { cmd, data }
  if cmd == 0x7C and data[5] == 32 then
    for _, f in ipairs(mspReplyFrames(32, batteryConfigReply())) do queue[#queue + 1] = f end
  elseif cmd == 0x7C and data[5] == 1 then -- MSP_API_VERSION: protocol 0, API 12.09
    for _, f in ipairs(mspReplyFrames(1, { 0, 12, 9 })) do queue[#queue + 1] = f end
  end
  return true
end

-- Rotorflight custom telemetry frame: { dest, origin, fid, (sid hi, sid lo, value...)... }
local fid = 0
local function customFrame(fields)
  local d = { 0xEA, 0xC8, fid }
  fid = (fid + 1) % 256
  for _, f in ipairs(fields) do
    d[#d + 1] = math.floor(f[1] / 256); d[#d + 1] = f[1] % 256
    for _, byte in ipairs(f[2]) do d[#d + 1] = byte end
  end
  return { 0x88, d }
end

local src = MAIN_SRC
local widget = assert(load(src, "main.lua"))()
local wgt = widget.create({ x = 0, y = 0, w = 800, h = 480 }, { Theme = 0, Voice = 0, BattLand = 20 })

-- Frame 1: Vbat 50.12V, Curr 12.34A, Bat% 87, Hspd 2105, Gov 4 (ACTIVE), Vcel 4.18 (218-200), Thr -5
queue[#queue + 1] = customFrame({
  { 0x1011, { 0x13, 0x94 } }, { 0x1012, { 0x04, 0xD2 } }, { 0x1014, { 87 } },
  { 0x10C0, { 0x08, 0x39 } }, { 0x1205, { 4 } }, { 0x1021, { 218 } }, { 0x1035, { 0xFB } },
})
-- Frame 2: ARM 1, ARMD 67108872, PID# 3, RTE# 2, BAT# 2, EscC 1234, Tesc 61, Vbec 8.21
queue[#queue + 1] = customFrame({
  { 0x1202, { 1 } }, { 0x1203, { 0x04, 0x00, 0x00, 0x08 } }, { 0x1211, { 3 } }, { 0x1212, { 2 } },
  { 0x1214, { 2 } }, { 0x1043, { 0x04, 0xD2 } }, { 0x10A0, { 61 } }, { 0x1081, { 0x03, 0x35 } },
})
-- Frame 3: unknown sid 0x7777 first -> rest must be ignored (rf2tlm breaks too)
queue[#queue + 1] = customFrame({ { 0x7777, { 1, 2 } }, { 0x10C0, { 0, 1 } } })

for step = 0, 200 do -- 10s at 50ms
  NOW = step * 5
  widget.refresh(wgt, 0, nil)
end

check("Vbat", getValue("Vbat"), 50.12)
check("Curr", getValue("Curr"), 12.34)
check("Bat%", getValue("Bat%"), 87)
check("Hspd (not overwritten)", getValue("Hspd"), 2105)
check("Gov", getValue("Gov"), 4)
check("Vcel", getValue("Vcel"), 4.18)
check("Thr (signed)", getValue("Thr"), -5)
check("ARM", getValue("ARM"), 1)
check("ARMD", getValue("ARMD"), 67108872)
check("PID#", getValue("PID#"), 3)
check("RTE#", getValue("RTE#"), 2)
check("BAT#", getValue("BAT#"), 2)
check("EscC", getValue("EscC"), 1234)
check("Tesc", getValue("Tesc"), 61)
check("Vbec", getValue("Vbec"), 8.21)
check("*Cnt frames", getValue("*Cnt"), 3)
check("MSP API version request", pushed[1] and table.concat(pushed[1][2], ","), "200,234,48,0,1,1")
check("API version", wgt.fcApi and math.floor(wgt.fcApi * 100 + 0.5), 1209)
local req = pushed[2]
check("MSP request frame", req and table.concat(req[2], ","), "200,234,49,0,32,32")
for i = 1, 6 do check("capacity " .. i, wgt.battCaps and wgt.battCaps[i], CAPS[i]) end
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
