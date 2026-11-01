-- lvgl stub for the headless harness, modelled on EdgeTX 2.12
-- (radio/src/lua/api_colorlcd_lvgl.cpp, lua_lvgl_widget.cpp):
--  * unknown property names are an error ("Invalid property"), as there
--  * controls (button and later types) are skipped unless full screen
--  * function properties are called every frame (LVSTUB.frame), like the
--    widget's callRefs, so their Lua errors and cost show up here
--  * objects outside the 800x480 screen are reported (boxes clip their
--    children, which are only checked against the box)
-- LVSTUB.press(text) runs the press() of the visible button with that text.
local M = { full = false, objs = {}, issues = {}, builds = 0 }

local BASE = { type = 1, name = 1, children = 1, x = 1, y = 1, w = 1, h = 1, color = 1, opacity = 1,
  visible = 1, size = 1, pos = 1, floating = 1 }
local OBJECT = { flexFlow = 1, flexPad = 1, borderPad = 1, active = 1 }
local TYPES = {
  label = { align = 1, text = 1, font = 1 },
  rectangle = { filled = 1, thickness = 1, rounded = 1 },
  circle = { radius = 1, filled = 1, thickness = 1 },
  line = { pts = 1, thickness = 1, rounded = 1, dashGap = 1, dashWidth = 1 },
  image = { file = 1, fill = 1, object = true },
  box = { align = 1, scrollBar = 1, scrollDir = 1, scrollTo = 1, scrolled = 1, object = true },
  button = { cornerRadius = 1, textColor = 1, press = 1, text = 1, font = 1, checked = 1, longpress = 1,
    object = true, control = true },
  slider = { min = 1, max = 1, get = 1, set = 1, object = true, control = true },
  textEdit = { value = 1, length = 1, set = 1, object = true, control = true },
}
local FUNCS = { "text", "color", "visible", "size", "pos", "font", "pts", "get", "textColor", "active" }

local function issue(s)
  if not M.seen then M.seen = {} end
  if not M.seen[s] then M.seen[s] = true; M.issues[#M.issues + 1] = s end
end

local function walk(list, ox, oy, clip)
  for _, o in ipairs(list) do
    local spec = TYPES[o.type]
    if not spec then error("lvgl stub: bad type " .. tostring(o.type), 3) end
    for k in pairs(o) do
      if not BASE[k] and not spec[k] and not (spec.object and OBJECT[k]) then
        error("lvgl stub: invalid property '" .. k .. "' on " .. o.type, 3)
      end
    end
    if spec.control and not M.full then goto continue end
    do
      local x, y = (o.x or 0) + ox, (o.y or 0) + oy
      local w = (type(o.w) == "number") and o.w or 0
      local h = (type(o.h) == "number") and o.h or 0
      if o.type == "circle" then x, y, w, h = x - (o.radius or 0), y - (o.radius or 0), 2 * (o.radius or 0), 2 * (o.radius or 0) end
      if not clip and o.type ~= "line" and (x < 0 or y < 0 or x + w > 800 or y + h > 480) then
        issue(string.format("%s off-screen x=%d y=%d w=%d h=%d %s", o.type, x, y, w, h,
          type(o.text) == "string" and o.text or ""))
      end
      M.objs[#M.objs + 1] = o
      if o.children then walk(o.children, x, y, o.type == "box" or clip) end
    end
    ::continue::
  end
end

M.lvgl = {
  clear = function() M.objs = {} end,
  build = function(t) M.builds = M.builds + 1; walk(t, 0, 0, false) end,
  isFullScreen = function() return M.full end,
  isAppMode = function() return true end,
  exitFullScreen = function() M.full = false end,
  SCROLL_OFF = 0, SCROLL_HOR = 1, SCROLL_VER = 2, SCROLL_ALL = 3,
}

-- every function property, as EdgeTX does each frame
function M.frame()
  for _, o in ipairs(M.objs) do
    for _, k in ipairs(FUNCS) do
      local f = o[k]
      if type(f) == "function" and k ~= "active" then f() end
    end
  end
end

-- the text a button shows now
local function buttonText(o)
  if type(o.text) == "function" then return o.text() end
  return o.text
end

function M.press(text)
  for i = #M.objs, 1, -1 do -- topmost first
    local o = M.objs[i]
    if o.type == "button" and buttonText(o) == text and (o.visible == nil or o.visible()) then
      o.press()
      return true
    end
  end
  return false
end

function M.texts()
  local out = {}
  for _, o in ipairs(M.objs) do
    if o.type == "label" or o.type == "button" then
      local s = (o.type == "button") and buttonText(o) or (type(o.text) == "function" and o.text() or o.text)
      if (o.visible == nil or o.visible()) and s and s ~= "" then out[#out + 1] = s end
    end
  end
  return out
end

return M
