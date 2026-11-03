--[[
  DrawBench - drawing-speed benchmark for EdgeTX colour radios (lcd widgets)
  ---------------------------------------------------------------------------
  ONE-TIME USE TOOL. RotorHUD ran at ~5 fps on the TX16S MK3 (EdgeTX 2.12)
  with 80-100 ms of drawing per frame on every screen, simple or busy. This
  widget finds out which kind of drawing costs that time, so the fix is
  based on numbers, not guesses.

  USE: put "DrawBench" in place of RotorHUD on the same screen (same zone
  size), wait about 50 s until the results table shows, take a screenshot.
  Put RotorHUD back afterwards.

  Each test draws the same thing every frame for 5 s (the 1st second is
  discarded) and records:
    fps - frames per second actually reached
    ms  - time spent inside refresh() per frame (getTime() is 10 ms, so
          this is an average over all frames of the test)
  The "empty" test (one tiny label) is the baseline: what EdgeTX itself
  costs per frame for a full-size lcd widget.
]]

local W, H = 800, 480

local TESTS = {
  { "empty",         "one small label only" },
  { "fill x1",       "1 full-screen fill" },
  { "fill x4",       "4 full-screen fills" },
  { "rect x500",     "500 small rects 20x10" },
  { "chamfer x20",   "20 panels 180x60, 25 rect calls each" },
  { "text x40",      "40 labels, default font" },
  { "mid x40",       "40 labels, MIDSIZE" },
  { "xxl x2",        "2 numbers, XXLSIZE" },
  { "sizeText x40",  "40 lcd.sizeText calls, nothing drawn" },
  { "lua 20k",       "Lua loop, about 20k instructions" },
}
local TEST_TICKS, WARMUP_TICKS = 500, 100 -- getTime() units (10 ms)

local C = {}
local function colors()
  if C.bg then return end
  C.bg = lcd.RGB(0x0E, 0x0F, 0x11)
  C.panel = lcd.RGB(0x1C, 0x1E, 0x22)
  C.bar = lcd.RGB(0x2A, 0x2D, 0x32)
  C.white = lcd.RGB(0xF2, 0xF2, 0xF3)
  C.dim = lcd.RGB(0x8A, 0x8D, 0x93)
  C.accent = lcd.RGB(0x4C, 0x9A, 0xE8)
end

local function chamfer(x, y, w, h, fill, bg)
  lcd.drawFilledRectangle(x, y, w, h, fill)
  for i = 0, 2 do
    local cut = 6 - 2 * i
    lcd.drawFilledRectangle(x + i, y + i, cut, 1, bg)
    lcd.drawFilledRectangle(x + i, y + i, 1, cut, bg)
    lcd.drawFilledRectangle(x + w - i - cut, y + i, cut, 1, bg)
    lcd.drawFilledRectangle(x + w - i - 1, y + i, 1, cut, bg)
    lcd.drawFilledRectangle(x + i, y + h - i - 1, cut, 1, bg)
    lcd.drawFilledRectangle(x + i, y + h - i - cut, 1, cut, bg)
    lcd.drawFilledRectangle(x + w - i - cut, y + h - i - 1, cut, 1, bg)
    lcd.drawFilledRectangle(x + w - i - 1, y + h - i - cut, 1, cut, bg)
  end
end

local sink = 0
local DRAW = {
  function() end,
  function() lcd.drawFilledRectangle(0, 0, W, H, C.bg) end,
  function()
    for k = 1, 4 do lcd.drawFilledRectangle(0, 0, W, H, (k % 2 == 0) and C.panel or C.bg) end
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    for k = 0, 499 do lcd.drawFilledRectangle((k % 25) * 32, 40 + math.floor(k / 25) * 20, 20, 10, C.bar) end
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    for k = 0, 19 do chamfer(10 + (k % 4) * 196, 40 + math.floor(k / 4) * 86, 180, 60, C.panel, C.bg) end
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    for k = 0, 39 do lcd.drawText(10 + (k % 4) * 196, 40 + math.floor(k / 4) * 42, "Sample 1234", C.white) end
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    for k = 0, 39 do lcd.drawText(10 + (k % 4) * 196, 40 + math.floor(k / 4) * 42, "Val 1234", MIDSIZE + C.white) end
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    lcd.drawText(40, 120, "2105", XXLSIZE + C.white)
    lcd.drawText(420, 120, "1234", XXLSIZE + C.white)
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    for k = 1, 40 do
      if lcd.sizeText then sink = sink + (lcd.sizeText("Val " .. k, MIDSIZE) or 0) end
    end
  end,
  function()
    lcd.drawFilledRectangle(0, 0, W, H, C.bg)
    local s = 0
    for k = 1, 4000 do s = s + k % 7 end
    sink = sink + s
  end,
}

local function create(zone, options)
  return { zone = zone, test = 1, results = {} }
end

local function update(wgt, options) end

local function drawResults(wgt)
  lcd.drawFilledRectangle(0, 0, W, H, C.bg)
  lcd.drawText(10, 8, "DrawBench results - zone " .. wgt.zone.w .. "x" .. wgt.zone.h, C.accent)
  lcd.drawText(10, 40, "test", C.dim)
  lcd.drawText(190, 40, "fps", C.dim)
  lcd.drawText(270, 40, "ms/frame", C.dim)
  lcd.drawText(400, 40, "what", C.dim)
  for k, r in ipairs(wgt.results) do
    local y = 40 + k * 36
    lcd.drawText(10, y, TESTS[k][1], C.white)
    lcd.drawText(190, y, string.format("%d.%d", math.floor(r.fps10 / 10), r.fps10 % 10), C.white)
    lcd.drawText(270, y, tostring(r.ms), C.white)
    lcd.drawText(400, y, TESTS[k][2], SMLSIZE + C.dim)
  end
end

local function refresh(wgt, event, touchState)
  colors()
  local t0 = getTime()
  if wgt.test > #TESTS then
    drawResults(wgt)
    return
  end
  if not wgt.start then wgt.start, wgt.n, wgt.busy, wgt.first = t0, 0, 0, nil end
  local elapsed = t0 - wgt.start
  DRAW[wgt.test]()
  lcd.drawText(10, 8, string.format("DrawBench %d/%d  %s", wgt.test, #TESTS, TESTS[wgt.test][1]), SMLSIZE + C.white)
  local t1 = getTime()
  if elapsed >= WARMUP_TICKS then
    if not wgt.first then wgt.first = t0 end
    wgt.n, wgt.busy, wgt.last = wgt.n + 1, wgt.busy + (t1 - t0), t0
  end
  if elapsed >= TEST_TICKS then
    local span = math.max((wgt.last or t0) - (wgt.first or t0), 1)
    wgt.results[wgt.test] = {
      fps10 = math.floor((wgt.n - 1) * 1000 / span),
      ms = math.floor(wgt.busy * 10 / math.max(wgt.n, 1)),
    }
    wgt.test, wgt.start = wgt.test + 1, nil
  end
end

return { name = "DrawBench", options = {}, create = create, update = update, refresh = refresh }
