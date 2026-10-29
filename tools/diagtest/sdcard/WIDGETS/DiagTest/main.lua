--[[
  Font / bitmap-scale diagnostic widget for EdgeTX (Color LCD)
  ----------------------------------------------------------------
  ONE-TIME USE TOOL. Not the Rotorflight dashboard - this just measures
  how this specific radio/firmware actually renders things, so future
  layout work can use real numbers instead of guesses (which is what
  caused most of the back-and-forth while building the main widget).

  INSTALL:
    1. Copy scaletest.png into /IMAGES/ on the SD card (same folder
       used for model pictures). It's a 40x40px test image with a red
       border and white gridlines every 10px - its native size is
       exactly known, which is what makes it useful for this test.
    2. Copy this file to /WIDGETS/DiagTest/main.lua
    3. Add it as a widget on a full-screen (1-zone) layout, same as
       the main dashboard widget.
    4. Take ONE clear photo of the screen and send it back - from
       that photo, the ruler ticks and gridlines let the exact pixel
       size of each font and each bitmap-scale attempt be read off
       directly, and the CONFIG.fontSpecs charW/lineH table and the
       drawBitmapFit scale handling in the main widget can be
       corrected to match.
    5. Remove this widget afterwards - it has no ongoing purpose.

  WHAT IT SHOWS:
    - A pixel ruler (ticks every 10px, numbered every 50px) usable as
      a reference scale for anything else on screen.
    - The same sample text ("0123456789") drawn at every font size
      flag (SMLSIZE, MIDSIZE, DBLSIZE, XXLSIZE, and the ~0 default),
      each on its own row, right up against the ruler.
    - If this firmware has lcd.sizeText(text, flags) (some do), its
      reported width/height is printed directly - no photo needed for
      that part, it's an exact number from the radio itself.
    - The scaletest.png bitmap drawn several times with different
      "scale" arguments to lcd.drawBitmap (no scale at all, then 25,
      50, 100, 200 as literal numbers) side by side, each labeled -
      comparing their on-screen size against the ruler (or against
      each other) shows whether scale does anything at all here, and
      if so, whether it behaves like a percentage or gets ignored.
]]

local COLOR = {
  bg = lcd.RGB(0x0E, 0x0F, 0x11),
  white = lcd.RGB(0xF2, 0xF2, 0xF3),
  dim = lcd.RGB(0x8A, 0x8D, 0x93),
  red = lcd.RGB(0xE2, 0x4B, 0x4A),
  green = lcd.RGB(0x5D, 0xCA, 0xA5),
}

local testBitmap = nil
local bitmapLoadTried = false

local function ensureBitmap()
  if bitmapLoadTried then return end
  bitmapLoadTried = true
  local ok, bmp = pcall(function()
    if Bitmap and Bitmap.open then
      return Bitmap.open("/IMAGES/scaletest.png")
    elseif lcd and lcd.loadBitmap then
      return lcd.loadBitmap("/IMAGES/scaletest.png")
    end
    return nil
  end)
  if ok then testBitmap = bmp end
end

-- Draws a horizontal ruler: a baseline, a tick every 10px, and a
-- number every 50px, from x0 to x0+widthPx.
local function drawRuler(x0, y0, widthPx)
  lcd.drawFilledRectangle(x0, y0, widthPx, 1, COLOR.dim)
  local i = 0
  while i <= widthPx do
    local tickH = (i % 50 == 0) and 8 or 4
    lcd.drawFilledRectangle(x0 + i, y0 - tickH, 1, tickH, COLOR.dim)
    if i % 50 == 0 then
      lcd.drawText(x0 + i, y0 + 10, tostring(i), LEFT + SMLSIZE + COLOR.dim)
    end
    i = i + 10
  end
end

local function create(zone, options)
  return { zone = zone, options = options }
end

local function update(wgt, options)
  wgt.options = options
end

local function background(wgt) end

local function refresh(wgt, event, touchState)
  local w, h = wgt.zone.w, wgt.zone.h
  lcd.drawFilledRectangle(0, 0, w, h, COLOR.bg)
  ensureBitmap()

  local sample = "0123456789"
  local fonts = {
    { name = "default(0)", flag = 0 },
    { name = "SMLSIZE", flag = SMLSIZE },
    { name = "MIDSIZE", flag = MIDSIZE },
    { name = "DBLSIZE", flag = DBLSIZE },
    { name = "XXLSIZE", flag = XXLSIZE },
  }

  local rulerX, rulerW = 140, 400
  local y = 14

  lcd.drawText(8, y, "Font size test (sample: " .. sample .. ")", LEFT + SMLSIZE + COLOR.green)
  y = y + 16
  drawRuler(rulerX, y, rulerW)
  y = y + 18

  for i = 1, #fonts do
    local f = fonts[i]
    lcd.drawText(8, y + 14, f.name, LEFT + VCENTER + SMLSIZE + COLOR.dim)

    local sizeOk, sw, sh = pcall(function() return lcd.sizeText(sample, f.flag) end)
    local sizeText = "sizeText: n/a"
    if sizeOk and sw then
      sizeText = "sizeText: " .. tostring(sw) .. "x" .. tostring(sh)
    end
    lcd.drawText(rulerX + rulerW + 12, y + 14, sizeText, LEFT + VCENTER + SMLSIZE + COLOR.green)

    lcd.drawText(rulerX, y, sample, LEFT + f.flag + COLOR.white)
    y = y + 46
  end

  y = y + 8
  lcd.drawText(8, y, "Bitmap scale test (scaletest.png is 40x40 natively)",
    LEFT + SMLSIZE + COLOR.green)
  y = y + 20

  if not testBitmap then
    lcd.drawText(8, y, "scaletest.png not found in /IMAGES - copy it there and reload",
      LEFT + SMLSIZE + COLOR.red)
  else
    local variants = { "no scale arg", "25", "50", "100", "200" }
    local vx = 8
    for i = 1, #variants do
      lcd.drawText(vx, y, variants[i], LEFT + SMLSIZE + COLOR.dim)
      local drawY = y + 16
      if i == 1 then
        pcall(function() lcd.drawBitmap(testBitmap, vx, drawY) end)
      else
        pcall(function() lcd.drawBitmap(testBitmap, vx, drawY, tonumber(variants[i])) end)
      end
      vx = vx + 95
    end
  end
end

return {
  name = "DiagTest",
  options = {},
  create = create,
  update = update,
  refresh = refresh,
  background = background,
}
