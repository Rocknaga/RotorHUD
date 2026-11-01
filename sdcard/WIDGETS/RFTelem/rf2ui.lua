-- RF Telem: Rotorflight settings in the widget's style. Replaces the five
-- screen modules of RF2's lvgl UI (LVGL/mainMenu, page, messageBox,
-- popupMenu, waitMessage); RF2 keeps reading, writing and saving.
-- Loaded by core.lua (R.rf2Skins) the first time RF2 is opened; returns the
-- name -> module table for RF2's executeScript. Adapted from
-- rotorflight-lua-scripts (GPL-3.0).
local R, LV = ...
local COLOR = setmetatable({}, { __index = function(_, k) return R.COLOR[k] end }) -- current theme
local CONFIG, textWidth, playPattern, playEffect, FC = R.CONFIG, R.textWidth, R.playPattern, R.playEffect, R.FC

-- MIDSIZE when every text fits the width, else the default font for all
-- (one size per group, so tiles/buttons don't mix sizes).
local function rf2Font(w, texts)
  for i = 1, #texts do
    if textWidth(texts[i], MIDSIZE) > w then return 0 end
  end
  return MIDSIZE
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

-- ---------------------------- RF2 in widget style -------------------------
-- The hosted RF2 lvgl UI (ui_lvgl_runner) keeps its logic - MSP reads and
-- writes, Save (EEPROM), page loading - and builds its screens through
-- five modules: LVGL/mainMenu, page, messageBox, popupMenu, waitMessage.
-- LV.rf2Skin replaces them with these (CONFIG.tools.rf2Skin): the widget's
-- header and colors, the page as cards of large tiles (rf2CardModel, as
-- in the lcd skin) in a scrolling box, and a bottom edit sheet with a
-- slider, -10/-1/+1/+10, choice buttons, OK and Cancel. Editing follows
-- RF2's LVGL/page.lua: numbers call field:change(newValue, page) before
-- the value is set, choices set it and call field:postEdit(page).
LV.rf2 = {}

function LV.rf2.value(f)
  if f.t and string.sub(f.t, 1, 1) == "[" and not f.data then return (string.gsub(f.t, "[%[%]]", "")) end
  local d = f.data
  if not d or d.value == nil then return "---" end
  local v = d.value
  if type(v) == "number" then
    if type(d.table) == "table" and d.table[v] ~= nil then return tostring(d.table[v]) .. (d.unit or "") end
    if d.scale and d.scale > 1 then -- keep the field's resolution: 5.0 s, 1.80, 12.5
      v = string.format("%." .. ((d.scale >= 100) and 2 or 1) .. "f", v / d.scale)
    elseif d.scale then
      v = string.format("%d", math.floor(v / d.scale))
    else
      v = string.format("%d", math.floor(v))
    end
  end
  return tostring(v) .. (d.unit or "")
end

-- header: Back, title / subtitle, action buttons on the right
function LV.rf2.header(k, title, subtitle, back, actions)
  local x, y, h = LV.ICON + 4, 8, 52
  LV.rect(k, x, y, LCD_W - 12 - x, h, COLOR.chip, 8)
  LV.button(k, x + 6, y + 4, 110, h - 8, "< Back", back, MIDSIZE)
  local right = LCD_W - 12 - 6
  for i = #(actions or {}), 1, -1 do
    local a = actions[i]
    right = right - a.w
    LV.button(k, right, y + 4, a.w, h - 8, a.text, a.press, MIDSIZE, a.extra)
    right = right - 8
  end
  local tx = x + 6 + 110 + 14
  local tw = right - 8 - tx
  LV.text(k, tx, y + (subtitle and 17 or h / 2), tw, title or "", LV.fitFont(title or "", tw, MIDSIZE), COLOR.white)
  if subtitle then LV.text(k, tx, y + 40, tw, subtitle, SMLSIZE, COLOR.dim) end
  LV.touchBadge(k)
end

function LV.rf2.mainMenu()
  local t = {}
  t.show = function(menu)
    local k = {}
    LV.rect(k, 0, 0, LCD_W, LCD_H, COLOR.bg)
    LV.rf2.header(k, "Rotorflight settings", nil, function() if menu.back then menu.back() end end)
    local cols, gap, th = 3, 8, 64
    local tw = math.floor((LCD_W - 24 - (cols - 1) * gap) / cols)
    local kids, texts = {}, {}
    for i, item in ipairs(menu.items) do texts[i] = item.text end
    local font = rf2Font(tw - 20, texts) -- one size for every tile
    for i, item in ipairs(menu.items) do
      local cx, cy = ((i - 1) % cols) * (tw + gap), math.floor((i - 1) / cols) * (th + gap)
      LV.button(kids, cx, cy, tw, th, item.text, function() if item.click then item.click(i) end end, font)
    end
    k[#k + 1] = { type = "box", x = 12, y = LV.Y1, w = LCD_W - 24, h = LCD_H - LV.Y1 - 6,
      scrollDir = lvgl.SCROLL_VER, scrollBar = true, children = kids }
    lvgl.clear()
    lvgl.build(k)
  end
  return t
end

-- modal card appended over the current screen; closing rebuilds the screen
function LV.rf2.modal(title, text, buttons)
  local k = {}
  LV.rect(k, 0, 0, LCD_W, LCD_H, COLOR.bg, nil, { opacity = 160 })
  local mw = 560
  local mh = 70 + (text and 110 or 0) + #buttons * 68
  local mx, my = math.floor((LCD_W - mw) / 2), math.floor((LCD_H - mh) / 2)
  LV.rect(k, mx, my, mw, mh, COLOR.accent, 8)
  LV.rect(k, mx + 2, my + 2, mw - 4, mh - 4, COLOR.panel, 7)
  LV.text(k, mx + 20, my + 32, mw - 40, title or "", MIDSIZE, COLOR.white)
  local y = my + 64
  if text then
    local ly = y + 12
    for line in string.gmatch(text, "([^\n]+)") do
      LV.text(k, mx + 20, ly, mw - 40, line, 0, COLOR.white)
      ly = ly + 30
    end
    y = y + 110
  end
  for _, b in ipairs(buttons) do
    LV.button(k, mx + 20, y, mw - 40, 60, b.text, b.press, MIDSIZE)
    y = y + 68
  end
  lvgl.build(k)
end

function LV.rf2.messageBox()
  return { show = function(title, text)
    LV.rf2.savePending = nil -- RF2's save warning / error: not "Saved"
    LV.rf2.modal(title, text, { { text = "OK", press = function() if LV.rf2.redraw then LV.rf2.redraw() end end } })
  end }
end

function LV.rf2.popupMenu()
  return { show = function(menu)
    local buttons = {}
    for i, item in ipairs(menu.items) do
      buttons[#buttons + 1] = { text = item.text, press = function()
        if LV.rf2.redraw then LV.rf2.redraw() end
        if item.click then item.click(i) end
      end }
    end
    buttons[#buttons + 1] = { text = "Cancel", press = function() if LV.rf2.redraw then LV.rf2.redraw() end end }
    LV.rf2.modal(menu.title or "Menu", nil, buttons)
  end }
end

function LV.rf2.waitMessage()
  local t = {}
  t.setWaitMessage = function(title, message, back)
    if message ~= t.message or not t.shown then t.message, t.title, t.back, t.shown = message, title, back, false end
  end
  t.clearWaitMessage = function()
    if not t.message then return end
    t.message, t.shown = nil, false
  end
  t.updateWaitMessage = function()
    if not t.message or t.shown then return end
    t.shown = true
    local k = {}
    LV.rect(k, 0, 0, LCD_W, LCD_H, COLOR.bg)
    LV.rf2.header(k, t.title ~= "" and t.title or "Rotorflight settings", nil, function() if t.back then t.back() end end)
    LV.text(k, 12, LCD_H / 2, LCD_W - 24, t.message, DBLSIZE, COLOR.white, CENTER)
    lvgl.clear()
    lvgl.build(k)
  end
  return t
end

-- One page: cards of tiles in a scrolling box; tap a tile to edit it.
function LV.rf2.page()
  local t = {}
  local page, editing, saving, oldValue
  local CHOICE_COLS = 3

  local function close(commit)
    local f = editing and page.fields[editing]
    if f and not commit and oldValue ~= nil then f.data.value = oldValue end
    editing, oldValue = nil, nil
    t.show(page)
  end

  local function setNumber(f, v)
    local d = f.data
    local mult = d.mult or 1
    v = math.max(d.min or 0, math.min(d.max or 255, v))
    v = math.floor(v / mult + 0.5) * mult
    if f.change then f:change(v, page) end
    d.value = v
  end

  local function editSheet(k, f)
    local d = f.data
    local y0 = 196
    LV.rect(k, 0, LV.Y1, LCD_W, LCD_H - LV.Y1, COLOR.bg, nil, { opacity = 150 })
    LV.rect(k, 0, y0, LCD_W, LCD_H - y0, COLOR.panel)
    LV.rect(k, 0, y0, LCD_W, 3, COLOR.accent)
    local name = f.t or (page.skinName and page.skinName[editing]) or ""
    local section = page.skinSection and page.skinSection[editing]
    if section and f.t then name = section .. " - " .. name end -- e.g. "HSI Offset Gain - Pitch"
    LV.text(k, 20, y0 + 30, 300, name, LV.fitFont(name, 300, MIDSIZE), COLOR.dim)
    LV.text(k, 320, y0 + 30, 300, function() return LV.rf2.value(f) end, DBLSIZE, COLOR.white, CENTER)
    LV.button(k, LCD_W - 12 - 130, y0 + 10, 130, 48, "Cancel", function() close(false) end, MIDSIZE)
    local by = y0 + 70
    if type(d.table) == "table" then
      -- every choice as a button (scrolls when there are many)
      local keys = {}
      for key, _ in pairs(d.table) do
        if type(key) == "number" and key >= (d.min or 0) and (d.max == nil or key <= d.max) then keys[#keys + 1] = key end
      end
      table.sort(keys)
      local bw = math.floor((LCD_W - 24 - (CHOICE_COLS - 1) * 8) / CHOICE_COLS)
      local kids = {}
      for i, key in ipairs(keys) do
        local label = tostring(d.table[key])
        LV.button(kids, ((i - 1) % CHOICE_COLS) * (bw + 8), math.floor((i - 1) / CHOICE_COLS) * 64, bw, 56, label,
          function()
            d.value = key
            if f.postEdit then f:postEdit(page) end
            close(true)
          end, LV.fitFont(label, bw - 12, MIDSIZE),
          { color = function() return d.value == key and COLOR.accent or COLOR.barBg end })
      end
      k[#k + 1] = { type = "box", x = 12, y = by, w = LCD_W - 24, h = LCD_H - by - 8,
        scrollDir = lvgl.SCROLL_VER, scrollBar = true, children = kids }
    elseif type(d.value) == "number" then
      local mult = d.mult or 1
      local lo, hi = math.floor((d.min or 0) / mult), math.floor((d.max or 255) / mult)
      LV.text(k, 20, by + 16, 200, LV.rf2.value({ data = { value = d.min or 0, scale = d.scale, unit = d.unit } }), SMLSIZE, COLOR.dim)
      LV.text(k, LCD_W - 220, by + 16, 200, LV.rf2.value({ data = { value = d.max or 255, scale = d.scale, unit = d.unit } }),
        SMLSIZE, COLOR.dim, RIGHT)
      if hi > lo then
        k[#k + 1] = { type = "slider", x = 30, y = by + 40, w = LCD_W - 60, min = lo, max = hi, color = COLOR.accent,
          get = function() return math.floor((d.value or 0) / mult) end,
          set = function(v) setNumber(f, v * mult) end }
      end
      local steps = { { "-10", -10 }, { "-1", -1 }, { "+1", 1 }, { "+10", 10 } }
      local sy = by + 110
      for i, s in ipairs(steps) do
        LV.button(k, 12 + (i - 1) * 140, sy, 130, 64, s[1], function() setNumber(f, (d.value or 0) + s[2] * mult) end, MIDSIZE)
      end
      LV.button(k, LCD_W - 12 - 210, sy, 210, 64, "OK", function() close(true) end, MIDSIZE, { color = COLOR.accent })
    else
      k[#k + 1] = { type = "textEdit", x = 20, y = by + 20, w = LCD_W - 260, value = tostring(d.value or ""),
        length = d.max or 10, set = function(s) d.value = s end }
      LV.button(k, LCD_W - 12 - 210, by + 10, 210, 64, "OK", function() close(true) end, MIDSIZE, { color = COLOR.accent })
    end
  end

  t.show = function(p)
    page = p
    local sp = LV.rf2.savePending
    if sp and page.isReady and sp.page ~= page and sp.title == page.title then
      LV.rf2.savePending, LV.rf2.savedAt = nil, getTime() -- reloaded after the save: it went through
      playEffect(nil, "saved")                -- beep (Settings > Voice > Sound effects)
      playPattern(CONFIG.alarm.hapticSaved)   -- and vibration (Settings > Voice > Vibration)
    elseif sp and getTime() - sp.at > 1000 then
      LV.rf2.savePending = nil -- no reload within 10 s: say nothing
    end
    local k = {}
    LV.rect(k, 0, 0, LCD_W, LCD_H, COLOR.bg)
    local actions = {}
    if page.isReady and not page.readOnly then
      actions[#actions + 1] = { text = "Save", w = 120, press = function()
        if saving then return end
        saving = true
        -- RF2 reloads the page once the FC has written its EEPROM; a
        -- warning / error comes as a messageBox instead (see show below)
        LV.rf2.savePending = { page = page, title = page.title, at = getTime() }
        page:write()
      end, extra = { color = COLOR.accent, text = function() return saving and "Saving" or "Save" end } }
    end
    actions[#actions + 1] = { text = "Menu", w = 110, press = function()
      LV.rf2.modal("Menu", nil, {
        { text = "Reload", press = function() if rf2.reloadPage then rf2.reloadPage() end end },
        { text = "Reboot FC", press = function()
          rf2.mspQueue:add({ command = 68, processReply = function() end, simulatorResponse = {} }) -- MSP_REBOOT
          t.show(page)
        end },
        { text = "Cancel", press = function() t.show(page) end },
      })
    end }
    LV.rf2.header(k, page.title, not page.isReady and "Reading from the FC..." or nil,
      function() if page.back then page.back() end end, actions)
    saving = false

    local fields = page.fields or {}
    if page.isReady and #fields > 0 then
      local model = rf2CardModel(page)
      page.skinName, page.skinSection = model.name, {}
      for _, c in ipairs(model.cards) do
        for _, it in ipairs(c.items) do
          if it.i and c.title then page.skinSection[it.i] = c.title.t end
        end
      end
      local kids = {}
      local dx = -10 -- the box starts at x 10
      for _, c in ipairs(model.cards) do
        LV.rect(kids, 10 + dx, c.y, RF2_CARD_W, c.h, COLOR.panel, 6)
        if c.title then LV.text(kids, 22 + dx, c.y + 20, 500, c.title.t, 0, COLOR.accent) end
        if c.kind == "table" then
          for ci, col in ipairs(c.cols) do
            LV.text(kids, c.cellX + (ci - 1) * (c.cellW + 6) + dx, c.headY + 12, c.cellW,
              col.a.t .. (col.b and (" " .. col.b.t) or ""), SMLSIZE, COLOR.dim, CENTER)
          end
          for _, row in ipairs(c.rows) do
            if row.head then LV.text(kids, 24 + dx, row.y + RF2_CELL_H / 2, 100, row.head.t, 0, COLOR.white) end
          end
        end
        for _, it in ipairs(c.items) do
          if it.rect then
            local q = it.rect
            LV.rect(kids, q[1] + dx, q[2], q[3], q[4], COLOR.barBg, 4)
            LV.text(kids, q[1] + 14 + dx, q[2] + 41, q[3] - 20, function() return tostring(it.l.t) end, MIDSIZE, COLOR.dim)
          end
        end
      end
      for i, f in ipairs(fields) do
        local q = model.pos[i]
        if q then
          local x, y, w, h = q[1] + dx, q[2], q[3], q[4]
          local isBtn = f.t and string.sub(f.t, 1, 1) == "[" and not f.data
          local editable = not f.readOnly and (isBtn or (f.data and f.data.value ~= nil))
          if editable then
            LV.button(kids, x, y, w, h, "", function()
              if isBtn then
                if f.preEdit then f.preEdit(f, page) end
                return
              end
              editing, oldValue = i, f.data.value
              t.show(page)
            end, 0, { color = COLOR.barBg })
          else
            LV.rect(kids, x, y, w, h, COLOR.barBg, 4)
          end
          if isBtn then
            LV.text(kids, x, y + h / 2, w, LV.rf2.value(f), LV.fitFont(LV.rf2.value(f), w - 16, MIDSIZE), COLOR.accent, CENTER)
          elseif h >= RF2_TILE_H then
            local name = f.t or model.name[i] or ""
            LV.text(kids, x + 14, y + 13, w - 20, name, SMLSIZE, COLOR.dim)
            LV.text(kids, x + 14, y + 41, w - 20, function() return LV.rf2.value(f) end, MIDSIZE,
              f.readOnly and COLOR.dim or COLOR.white)
          else
            LV.text(kids, x, y + h / 2, w, function() return LV.rf2.value(f) end, MIDSIZE,
              f.readOnly and COLOR.dim or COLOR.white, CENTER)
          end
        end
      end
      k[#k + 1] = { type = "box", x = 10, y = LV.Y1, w = LCD_W - 20, h = LCD_H - LV.Y1 - 4,
        scrollDir = lvgl.SCROLL_VER, scrollBar = true, children = kids }
    else
      LV.text(k, 12, LCD_H / 2, LCD_W - 24, page.isReady and "Nothing on this page" or "Reading from the FC...",
        MIDSIZE, COLOR.dim, CENTER)
    end
    if editing and fields[editing] then editSheet(k, fields[editing]) end
    -- "Saved" banner for 2.5 s after a save went through
    local savedVis = function() return LV.rf2.savedAt ~= nil and getTime() - LV.rf2.savedAt < 250 end
    LV.rect(k, 120, LCD_H / 2 - 50, LCD_W - 240, 100, COLOR.green, 10, { visible = savedVis })
    LV.text(k, 120, LCD_H / 2, LCD_W - 240, "Saved to the FC", DBLSIZE, COLOR.black, CENTER, { visible = savedVis })
    lvgl.clear()
    lvgl.build(k)
    LV.rf2.redraw = function() t.show(page) end
  end
  return t
end

LV.rf2.SKIN = {
  ["LVGL/mainMenu"] = LV.rf2.mainMenu,
  ["LVGL/page"] = LV.rf2.page,
  ["LVGL/messageBox"] = LV.rf2.messageBox,
  ["LVGL/popupMenu"] = LV.rf2.popupMenu,
  ["LVGL/waitMessage"] = LV.rf2.waitMessage,
}

return LV.rf2.SKIN
