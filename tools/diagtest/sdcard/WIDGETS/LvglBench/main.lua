--[[
  LvglBench - speed check of an lvgl widget (EdgeTX 2.11+ colour radios)
  -----------------------------------------------------------------------
  ONE-TIME USE TOOL, companion to DrawBench. DrawBench showed that an lcd
  widget (redrawn completely every frame) tops out near 9-11 fps on the
  TX16S MK3. An lvgl widget keeps its objects and redraws only what
  changed; this measures how fast that is, before RotorHUD is rebuilt on it.

  USE: put "LvglBench" in place of RotorHUD on the same screen, wait about
  25 s until the results table shows, take a screenshot.

  The scene is roughly a busy dashboard: full-screen background, 24 rounded
  panels, 96 labels (MIDSIZE / small) and a bar. Each test runs 5 s (1st
  second discarded) and changes a different amount every frame:
    static   - nothing changes
    10 text  - 10 labels change every frame
    all text - all 48 value labels change every frame
    big+bar  - one XXLSIZE number and a bar width change every frame
  fps = refresh() calls per second (the widget's update rate, which also
  includes the time lvgl spends redrawing what changed).
]]

local TESTS = { "static", "10 text", "all text", "big+bar" }
local TEST_TICKS, WARMUP_TICKS = 500, 100

local function create(zone, options)
  return { zone = zone, test = 1, results = {}, frame = 0, built = false }
end

local function build(wgt)
  local W, H = wgt.zone.w, wgt.zone.h
  local bg, panel, bar = lcd.RGB(0x0E, 0x0F, 0x11), lcd.RGB(0x1C, 0x1E, 0x22), lcd.RGB(0x2A, 0x2D, 0x32)
  local white, dim, accent = lcd.RGB(0xF2, 0xF2, 0xF3), lcd.RGB(0x8A, 0x8D, 0x93), lcd.RGB(0x4C, 0x9A, 0xE8)
  local kids = {
    { type = "rectangle", x = 0, y = 0, w = W, h = H, color = bg, filled = true },
  }
  for k = 0, 23 do
    local x, y = 8 + (k % 4) * 198, 40 + math.floor(k / 4) * 66
    kids[#kids + 1] = { type = "rectangle", x = x, y = y, w = 190, h = 60, color = panel, filled = true, rounded = 6 }
    kids[#kids + 1] = { type = "label", x = x + 10, y = y + 2, text = "Label " .. k, font = SMLSIZE, color = dim }
    local n = k * 2
    kids[#kids + 1] = { type = "label", x = x + 10, y = y + 20, font = MIDSIZE, color = white,
      text = function()
        local t = wgt.test
        if t == 3 or (t == 2 and n < 20) then return tostring(wgt.frame + n) end
        return "Val " .. n
      end }
    kids[#kids + 1] = { type = "label", x = x + 110, y = y + 30, font = SMLSIZE, color = dim,
      text = function()
        if wgt.test == 3 then return tostring(wgt.frame % 100) end
        return "u" .. (n + 1)
      end }
  end
  kids[#kids + 1] = { type = "rectangle", x = 8, y = H - 40, w = W - 16, h = 30, color = bar, filled = true }
  kids[#kids + 1] = { type = "rectangle", x = 8, y = H - 40, w = 200, h = 30, color = accent, filled = true,
    size = function() return (wgt.test == 4) and (20 + (wgt.frame * 7) % (W - 40)) or 200, 30 end }
  kids[#kids + 1] = { type = "label", x = W - 260, y = 0, font = XXLSIZE, color = white,
    text = function() return (wgt.test == 4) and tostring(1000 + wgt.frame % 9000) or "2105" end }
  kids[#kids + 1] = { type = "label", x = 8, y = 4, font = SMLSIZE, color = white,
    text = function() return "LvglBench " .. math.min(wgt.test, #TESTS) .. "/" .. #TESTS .. "  " .. (TESTS[wgt.test] or "") end }
  lvgl.clear()
  lvgl.build(kids)
end

local function showResults(wgt)
  local white, dim, accent = lcd.RGB(0xF2, 0xF2, 0xF3), lcd.RGB(0x8A, 0x8D, 0x93), lcd.RGB(0x4C, 0x9A, 0xE8)
  local kids = {
    { type = "rectangle", x = 0, y = 0, w = wgt.zone.w, h = wgt.zone.h, color = lcd.RGB(0x0E, 0x0F, 0x11), filled = true },
    { type = "label", x = 10, y = 8, text = "LvglBench results - zone " .. wgt.zone.w .. "x" .. wgt.zone.h, color = accent },
    { type = "label", x = 10, y = 44, text = "test", color = dim },
    { type = "label", x = 200, y = 44, text = "fps", color = dim },
    { type = "label", x = 300, y = 44, text = "Lua ms/frame", color = dim },
  }
  for k, r in ipairs(wgt.results) do
    local y = 44 + k * 40
    kids[#kids + 1] = { type = "label", x = 10, y = y, text = TESTS[k], color = white }
    kids[#kids + 1] = { type = "label", x = 200, y = y, color = white,
      text = string.format("%d.%d", math.floor(r.fps10 / 10), r.fps10 % 10) }
    kids[#kids + 1] = { type = "label", x = 300, y = y, text = tostring(r.ms), color = white }
  end
  lvgl.clear()
  lvgl.build(kids)
end

local function update(wgt, options)
  wgt.built = false
end

local function refresh(wgt, event, touchState)
  if lvgl == nil then return end
  if wgt.test > #TESTS then
    if not wgt.shown then showResults(wgt); wgt.shown = true end
    return
  end
  if not wgt.built then build(wgt); wgt.built = true end
  local t0 = getTime()
  wgt.frame = wgt.frame + 1
  if not wgt.start then wgt.start, wgt.n, wgt.busy, wgt.first = t0, 0, 0, nil end
  local elapsed = t0 - wgt.start
  if elapsed >= WARMUP_TICKS then
    if not wgt.first then wgt.first = t0 end
    wgt.n, wgt.busy, wgt.last = wgt.n + 1, wgt.busy + (getTime() - t0), t0
  end
  if elapsed >= TEST_TICKS then
    local span = math.max((wgt.last or t0) - (wgt.first or t0), 1)
    wgt.results[wgt.test] = { fps10 = math.floor((wgt.n - 1) * 1000 / span), ms = math.floor(wgt.busy * 10 / math.max(wgt.n, 1)) }
    wgt.test, wgt.start = wgt.test + 1, nil
  end
end

return { name = "LvglBench", options = {}, create = create, update = update, refresh = refresh, useLvgl = true }
