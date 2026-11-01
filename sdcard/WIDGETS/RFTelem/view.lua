-- RF Telem screens (lvgl): each screen is built once when it changes and
-- its labels / colors / sizes are functions reading LV.v, filled once per
-- frame by LV.update. Loaded by main.lua with the core module R; returns LV
-- (also R.LV). Buttons exist only while the widget is full screen (EdgeTX).
local R = ...
local COLOR = setmetatable({}, { __index = function(_, k) return R.COLOR[k] end }) -- current theme
local CONFIG, toSentenceCase, getGovColor, getChargeColor, getTxBatteryPct, ARMD_ARM_SWITCH_AT_POWERUP = R.CONFIG, R.toSentenceCase, R.getGovColor, R.getChargeColor, R.getTxBatteryPct, R.ARMD_ARM_SWITCH_AT_POWERUP
local decodeArmd, isWhole, fmt, fmtTime, fmtUnit, SET = R.decodeArmd, R.isWhole, R.fmt, R.fmtTime, R.fmtUnit, R.SET
local USER, SETTINGS, isTelemetryConnected, textWidth, fitFontMeasured, TAB_LABEL_H = R.USER, R.SETTINGS, R.isTelemetryConnected, R.textWidth, R.fitFontMeasured, R.TAB_LABEL_H
local flightSampleStats, CHART_DIVS, chartAxis, TIME_STEPS, playEffect, voiceSetDir = R.flightSampleStats, R.CHART_DIVS, R.chartAxis, R.TIME_STEPS, R.playEffect, R.voiceSetDir
local critical, caution, FC, bpStep, bpChoose, tick = R.critical, R.caution, R.FC, R.bpStep, R.bpChoose, R.tick
local stopTool, MENU_ITEMS, menuItemState, openMenuItem = R.stopTool, R.MENU_ITEMS, R.menuItemState, R.openMenuItem

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
-- LV.ICON x LV.ICON there; the top bar sits beside it (y 8..60) and the
-- rows under it start at LV.Y1.
local LV = { v = {}, ICON = 68, Y1 = 68 }

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
  -- As tall as the EdgeTX button beside it (y 8..60): default-size text,
  -- signal bars and TX battery scaled to the bar.
  local pad, y, h = 12, 8, 52
  local x = LV.ICON + 4
  local cy = math.floor(y + h / 2)
  LV.rect(k, x, y, w - pad - x, h, COLOR.chip, 8)
  -- TX battery: fill level over a light ground, percentage inside in dark text
  local bw, bh = 64, 30
  local bx = w - pad - 14 - bw - 5
  LV.rect(k, bx, cy - bh / 2, bw, bh, COLOR.dim, 4, { filled = false, thickness = 2 })
  LV.rect(k, bx + bw, cy - 7, 5, 14, COLOR.dim)
  LV.rect(k, bx + 4, cy - bh / 2 + 4, bw - 8, bh - 8, COLOR.dim, 2) -- light ground: dark text reads on it
  LV.rect(k, bx + 4, cy - bh / 2 + 4, bw - 8, bh - 8, COLOR.green, 2, {
    color = LV.dv("txColor", COLOR.green),
    size = function() return math.max(1, math.floor((bw - 8) * (LV.v.txPct or 0) / 100)), bh - 8 end })
  LV.text(k, bx, cy, bw, LV.dv("txPctShort", ""), SMLSIZE, COLOR.black, CENTER)
  local sx = bx - 18 - 33
  for i = 1, 4 do
    local barH = 7 * i
    LV.rect(k, sx + (i - 1) * 9, cy + 14 - barH, 6, barH, COLOR.barBg, nil, {
      color = function() return ((LV.v.sig or 0) >= i * 25 - 12) and COLOR.green or COLOR.barBg end })
  end
  local cw = textWidth("23:59", 0) + 6
  local clockX = sx - 18 - cw
  LV.text(k, clockX, cy, cw, LV.dv("clock", ""), 0, COLOR.white, RIGHT)
  local left, right = x + 16, clockX - 16
  if withMenu then
    right = right - 130
    LV.button(k, right, y + 4, 130, h - 8, "Menu",
      function() if not LV.v.armed then wgt.menu = { sel = 1 } end end, 0,
      { visible = function() return not LV.v.armed end })
    right = right - 16
  end
  LV.rect(k, left, cy - 5, 10, 10, COLOR.red, nil, { visible = function() return LV.v.warn ~= "" end })
  LV.fitText(k, left + 18, cy, right - left - 18, "warn", "", 0, COLOR.red)
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
  for _, f in ipairs({ { lx, y1, "Volt", "volt" }, { lx, y2, "Vcel", "vcel" },
                       { rx, y1, "Current", "curr" }, { rx, y2, "Bec volt", "bec" } }) do
    LV.rect(k, f[1], f[2], flankW, cellH, COLOR.panel, 4)
    LV.tab(k, f[1], f[2], flankW, cellH, f[3], f[4], f[5])
  end
  local hx = lx + flankW + innerPad
  local hy, hh = clusterY + innerPad, clusterH - innerPad * 2
  LV.text(k, hx + 8, hy + TAB_LABEL_H / 2 + 1, heroW / 2, "Headspeed", SMLSIZE, COLOR.dim)
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
  -- top bar like the other screens; big clock | model card; a status strip
  LV.topBar(k, wgt, w, true)
  local pad, y = 12, LV.Y1
  local panelW = w - pad * 2
  local sh = 56
  local sy = h - pad - sh
  local heroH = sy - pad - y
  LV.rect(k, pad, y, panelW, heroH, COLOR.accentBorder, 8)
  LV.rect(k, pad + 1, y + 1, panelW - 2, heroH - 2, COLOR.accentPanel, 7)
  local half = math.floor(panelW / 2)
  LV.text(k, pad, y + heroH / 2 - 10, half, LV.dv("hhmm", ""), XXLSIZE, COLOR.white, CENTER)
  LV.text(k, pad, y + heroH - 34, half, LV.dv("date", ""), SMLSIZE, COLOR.dim, CENTER)
  LV.rect(k, pad + half, y + 24, 1, heroH - 48, COLOR.muted)
  local imgY = y + math.floor(heroH * 0.22)
  if CONFIG.showModelImage and wgt.modelImagePath then
    k[#k + 1] = { type = "image", file = wgt.modelImagePath, x = pad + half + math.floor((half - CONFIG.modelImageW) / 2),
      y = imgY, w = CONFIG.modelImageW, h = CONFIG.modelImageH }
  end
  LV.text(k, pad + half + 20, imgY + CONFIG.modelImageH + 48, half - 40, LV.dv("model", ""), DBLSIZE, COLOR.white, CENTER)

  LV.rect(k, pad, sy, panelW, sh, COLOR.panel, 6)
  LV.text(k, pad + 16, sy + sh / 2, panelW / 2, "Waiting for connection", MIDSIZE, COLOR.white)
  LV.text(k, pad + panelW / 2, sy + sh / 2, panelW / 2 - 16, LV.dv("standbyHint", ""), SMLSIZE, COLOR.dim, RIGHT,
    { visible = function() return not LV.v.full end })
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
  local titleH = 52
  LV.rect(k, pad, y, panelW, titleH, COLOR.panel, 6)
  LV.text(k, pad + 14, y + titleH / 2, 200, "Flight log", MIDSIZE, COLOR.white)
  LV.text(k, pad + 14 + 170, y + titleH / 2, 300, LV.v.model or "", SMLSIZE, COLOR.dim)
  -- outside full screen there are no buttons: the countdown shows as text
  LV.rect(k, pad + panelW - 6 - 170, y + 4, 170, titleH - 8, COLOR.barBg, 6)
  LV.text(k, pad + panelW - 6 - 170, y + titleH / 2, 170, LV.dv("closeText", "Close"), 0, COLOR.white, CENTER)
  LV.button(k, pad + panelW - 6 - 170, y + 4, 170, titleH - 8, "", function()
    wgt.showFlightLog = false
  end, MIDSIZE, { text = LV.dv("closeText", "Close") })

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
    local text = d.label
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
  local titleH = 56
  LV.rect(k, pad, y, panelW, titleH, COLOR.panel, 6)
  LV.text(k, pad + 14, y + titleH / 2, 260, page.title, MIDSIZE, COLOR.white)
  local sub = ""
  if page.cmd == 111 then sub = "Rate profile " .. (t.bank and fmt(t.bank, 0) or "--")
  elseif page.cmd ~= nil then sub = "PID profile " .. (t.pidProfile and fmt(t.pidProfile, 0) or "--") end
  if parsed and parsed.note then sub = sub .. "   " .. parsed.note end
  LV.text(k, pad + 270, y + titleH / 2, 270, sub, LV.fitFont(sub, 270, 0), COLOR.accent)
  LV.text(k, pad + panelW - 214, y + titleH / 2, 200, wgt.infoView .. " / " .. #FC.pages, SMLSIZE, COLOR.muted, RIGHT)
  -- full screen only (buttons): next page / close
  LV.button(k, pad + panelW - 6 - 130 - 8 - 130, y + 4, 130, titleH - 8, "Next", function()
    local n = (wgt.infoView or 0) + 1
    wgt.infoView = (n <= #FC.pages) and n or 1
    wgt.fc = wgt.fc or {}
    wgt.fc[FC.pages[wgt.infoView].cmd] = CONFIG.simulate and FC.sim[FC.pages[wgt.infoView].cmd] or nil
  end, MIDSIZE)
  LV.button(k, pad + panelW - 6 - 130, y + 4, 130, titleH - 8, "Close", function() wgt.infoView = nil end, MIDSIZE)

  local cy, ch = y + titleH + pad, h - pad - (y + titleH + pad)
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
end

-- Settings (full screen only: everything here is a button). Group tabs on
-- the left, the group's SETTINGS on the right; values save at once.
function LV.buildSettings(k, wgt, w, h)
  local pad, y = 12, 8
  local panelW = w - pad * 2
  local titleH = 52
  local tx = LV.ICON + 4 -- right of the TOUCH badge
  LV.rect(k, tx, y, w - pad - tx, titleH, COLOR.panel, 6)
  LV.text(k, tx + 14, y + titleH / 2, 200, "Settings", MIDSIZE, COLOR.white)
  LV.button(k, pad + panelW - 8 - 140, y + 4, 140, titleH - 8, "Close", function() wgt.settings = nil end, MIDSIZE)
  local cy = y + titleH + pad
  local ch = h - pad - cy
  local tabW = 170
  LV.rect(k, pad, cy, tabW, ch, COLOR.panel, 6)
  for i, g in ipairs(SET.groups) do
    LV.button(k, pad + 8, cy + 8 + (i - 1) * 72, tabW - 16, 64, g, function() wgt.settings.group = g end, MIDSIZE, {
      color = function() return (wgt.settings and wgt.settings.group == g) and COLOR.accent or COLOR.barBg end })
  end
  local rx, rw = pad + tabW + pad, panelW - tabW - pad
  LV.rect(k, rx, cy, rw, ch, COLOR.panel, 6)
  -- controls 58px tall, rows 64px apart (6 rows fit the Alarms tab)
  local x0 = rx + 190
  local bh = 58
  local row = 0
  for _, def in ipairs(SETTINGS) do
    if def.group == wgt.settings.group then
      local ry = cy + 10 + row * 64
      row = row + 1
      local mid = ry + bh / 2
      LV.text(k, rx + 16, mid, 174, def.label, LV.fitFont(def.label, 170, 0), COLOR.white)
      local key = "set_" .. def.key
      if def.kind == "number" then
        LV.button(k, x0, ry, 96, bh, "-", function() SET.set(def, SET.value(wgt, def) - def.step) end, MIDSIZE)
        LV.text(k, x0 + 100, mid, 156, LV.dv(key, ""), MIDSIZE, COLOR.white, CENTER)
        LV.button(k, x0 + 260, ry, 96, bh, "+", function() SET.set(def, SET.value(wgt, def) + def.step) end, MIDSIZE)
      elseif def.kind == "bool" then
        LV.button(k, x0, ry, 220, bh, "", function() SET.set(def, not SET.value(wgt, def)) end, MIDSIZE, {
          text = LV.dv(key, ""),
          color = function() return SET.value(wgt, def) and COLOR.accent or COLOR.barBg end })
        if def.test == "tones" then -- the four effects in a row
          LV.button(k, x0 + 236, ry, 120, bh, "Test", function()
            for _, name in ipairs({ "connect", "caution", "critical", "disconnect" }) do playEffect(wgt, name, true) end
          end, MIDSIZE)
        end
      elseif #def.choices <= 3 then
        for c, label in ipairs(def.choices) do
          LV.button(k, x0 + (c - 1) * 122, ry, 114, bh, label, function() SET.set(def, c - 1) end, 0, {
            color = function() return SET.value(wgt, def) == c - 1 and COLOR.accent or COLOR.barBg end })
        end
      else
        local n = #def.choices
        LV.button(k, x0, ry, 80, bh, "<", function() SET.set(def, (SET.value(wgt, def) - 1) % n) end, MIDSIZE)
        LV.text(k, x0 + 84, mid, 120, LV.dv(key, ""), 0, COLOR.white, CENTER)
        LV.button(k, x0 + 208, ry, 80, bh, ">", function() SET.set(def, (SET.value(wgt, def) + 1) % n) end, MIDSIZE)
        if def.test then
          LV.button(k, x0 + 296, ry, 96, bh, "Test", function()
            if playFile then playFile(CONFIG.alarm.dir .. voiceSetDir(wgt) .. "/armed.wav") end
          end, MIDSIZE)
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
  -- large targets: 60px rows across a 600px card, Close in the header
  local mw, rowH, gap = 600, 60, 8
  local headH = 60
  local mh = headH + #MENU_ITEMS * (rowH + gap) + 6
  local mx, my = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
  local vis = function() return wgt.menu ~= nil end
  LV.rect(k, mx, my, mw, mh, COLOR.accent, 8, { visible = vis })
  LV.rect(k, mx + 2, my + 2, mw - 4, mh - 4, COLOR.panel, 7, { visible = vis })
  LV.text(k, mx + 20, my + headH / 2 + 2, 300, "Menu", MIDSIZE, COLOR.white, LEFT, { visible = vis })
  LV.button(k, mx + mw - 14 - 150, my + 8, 150, headH - 12, "Close", function() wgt.menu = nil end, MIDSIZE, { visible = vis })
  for i, item in ipairs(MENU_ITEMS) do
    local ry = my + headH + (i - 1) * (rowH + gap)
    LV.button(k, mx + 14, ry, mw - 28, rowH, item.label, function()
      if wgt.menu and wgt.lastT then openMenuItem(wgt, wgt.lastT, LV.v.connected, item.key) end
    end, MIDSIZE, { visible = vis, textColor = LV.dv("menuColor" .. i, COLOR.white) })
  end
end

function LV.buildToolMsg(k, wgt, w, h)
  local vis = function() return LV.v.toolMsg ~= nil end
  LV.rect(k, 40, h - 64, w - 80, 44, COLOR.red, 6, { visible = vis })
  LV.text(k, 50, h - 42, w - 100, LV.dv("toolMsg", ""), SMLSIZE, COLOR.white, CENTER, { visible = vis })
end

-- Full screen = touch and keys reach the widget: a "Touch" badge where
-- the EdgeTX button sits otherwise (top-left, same height as the top bar).
function LV.touchBadge(k)
  local vis = function() return LV.v.full end
  local x, y, w, h = 12, 8, LV.ICON - 16, 52 -- left edge with the panels, 8px to the top bar
  local cx = x + math.floor(w / 2)
  LV.rect(k, x, y, w, h, COLOR.accent, 8, { visible = vis })
  k[#k + 1] = { type = "circle", x = cx, y = y + 17, radius = 11, color = COLOR.white, filled = false,
    thickness = 2, visible = vis }
  k[#k + 1] = { type = "circle", x = cx, y = y + 17, radius = 4, color = COLOR.white, filled = true, visible = vis }
  LV.text(k, x - 4, y + h - 11, w + 8, "Touch", SMLSIZE, COLOR.white, CENTER, { visible = vis })
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
  if screen ~= "small" then
    LV.buildToolMsg(k, wgt, w, h)
    LV.touchBadge(k)
  end
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
  v.txPctShort = txPct and (fmt(txPct, 0) .. "%") or "--"
  v.clock = dt and string.format("%02d:%02d", dt.hour, dt.min) or ""
  if screen == "standby" then
    v.sig, v.warn = 0, ""
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
    v.clock = dt and string.format("%02d:%02d", dt.hour, dt.min) or ""
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
    v.bpStatus, v.bpStatusColor = "", COLOR.dim
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
        v.bpHint = "Profile " .. bp.sel .. " in " .. math.max(0, left) .. "s"
      else
        v.bpHint = (cfg.timeoutSec > 0) and ("Tap or Close switch  -  " .. math.max(0, left) .. "s") or "Tap or Close switch"
      end
    else
      v.bpHint = ""
    end
  elseif screen == "flightlog" then
    local remain = CONFIG.flightLogTimeoutSec
    if wgt.disconnectTime then remain = math.max(0, remain - math.floor((getTime() - wgt.disconnectTime) / 100)) end
    v.closeText = (CONFIG.flightLogTimeoutSec > 0) and ("Close  " .. remain .. "s") or "Close"
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
    sub = wgt.infoView .. ":" .. tostring(buf) .. ":" .. tostring(wgt.fcProf)
  elseif screen == "settings" then
    sub = "set:" .. wgt.settings.group
  end
  if wgt.lvScreen ~= screen or wgt.lvTheme ~= R.COLOR or wgt.lvW ~= w or wgt.lvH ~= h or wgt.lvFull ~= full
     or wgt.lvSub ~= sub
     or wgt.lvModel ~= wgt.modelImagePath or (screen == "armwarning" and wgt.lvArmd ~= t.armd) then
    LV.update(wgt, t, screen, connected, armed)
    LV.build(wgt, screen, t, parsed)
    wgt.lvSub = sub
    wgt.lvScreen, wgt.lvTheme, wgt.lvW, wgt.lvH, wgt.lvModel, wgt.lvArmd = screen, R.COLOR, w, h, wgt.modelImagePath, t.armd
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

R.LV = LV
return LV
