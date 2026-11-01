---@meta
-- EdgeTX Lua API declarations for lua-language-server (VS Code: sumneko.lua).
--
-- SCOPE: the functions / constants that sdcard/WIDGETS/RFTelem/main.lua and
-- tools/diagtest actually use, plus a few common flags / events (BOLD, INVERS,
-- BLINK, EVT_TOUCH_FIRST/BREAK/SLIDE, EVT_VIRTUAL_ENTER/EXIT) that are NOT used
-- by this project. This is NOT the full EdgeTX API. If you use something new
-- and the editor reports "undefined global", add it below (check the EdgeTX
-- Lua reference for the exact signature first).
-- Constant values are supplied by the firmware, hence "= nil" below.

---------------------------------------------------------------------------
-- Draw flags (combined by "+", a colour from lcd.RGB() is added the same way)
---------------------------------------------------------------------------
---@type integer
LEFT = nil
---@type integer
RIGHT = nil
---@type integer
CENTER = nil
---@type integer
VCENTER = nil
---@type integer
SMLSIZE = nil
---@type integer
MIDSIZE = nil
---@type integer
DBLSIZE = nil
---@type integer
XXLSIZE = nil
---@type integer
BOLD = nil
---@type integer
INVERS = nil
---@type integer
BLINK = nil

---------------------------------------------------------------------------
-- Widget option types (main.lua uses VALUE only; COLOR/SOURCE/BOOL listed
-- because the file's comments refer to them)
---------------------------------------------------------------------------
---@type integer
VALUE = nil
---@type integer
COLOR = nil
---@type integer
SOURCE = nil
---@type integer
BOOL = nil

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
---@type integer
EVT_TOUCH_TAP = nil
---@type integer
EVT_TOUCH_FIRST = nil
---@type integer
EVT_TOUCH_BREAK = nil
---@type integer
EVT_TOUCH_SLIDE = nil
---@type integer
EVT_VIRTUAL_ENTER = nil
---@type integer
EVT_VIRTUAL_EXIT = nil

---------------------------------------------------------------------------
-- Global functions
---------------------------------------------------------------------------

--- Telemetry / source value. Accepts a source name ("Hspd", "tx-voltage", ...)
--- or a numeric field id. Returns nil/0 when the source does not exist.
---@param source string|integer
---@return any
function getValue(source) end

---@class EdgeTxFieldInfo
---@field id integer
---@field name string
---@field desc string
---@field unit integer?

--- Field info for a name; nil when no such sensor/source exists.
---@param name string
---@return EdgeTxFieldInfo?
function getFieldInfo(name) end

--- Time since radio start in 10 ms ticks (1/100 s) - measured on TX16S MK3,
--- EdgeTX 2.12.0. Divide by 100 for seconds.
---@return integer
function getTime() end

---@class EdgeTxDateTime
---@field year integer
---@field mon integer
---@field day integer
---@field hour integer
---@field min integer
---@field sec integer

---@return EdgeTxDateTime
function getDateTime() end

--- Queue a WAV file for playback (absolute SD path, e.g. "/SOUNDS/rf/x.wav").
---@param path string
function playFile(path) end

--- Queue one haptic pulse. Units of duration/pause NOT verified on
--- TX16S MK3 (ms vs 10 ms) - see CONFIG.alarm.
---@param duration integer
---@param pause integer
---@param flags? integer
function playHaptic(duration, pause, flags) end

---------------------------------------------------------------------------
-- model
---------------------------------------------------------------------------
---@class EdgeTxModelInfo
---@field name string
---@field bitmap string? picture assigned in Model Setup (file name inside /IMAGES)

model = {}

---@return EdgeTxModelInfo
function model.getInfo() end

---------------------------------------------------------------------------
-- Bitmap
---------------------------------------------------------------------------
---@class EdgeTxBitmap

Bitmap = {}

---@param path string
---@return EdgeTxBitmap?
function Bitmap.open(path) end

---@param bitmap EdgeTxBitmap
---@return integer width
---@return integer height
function Bitmap.getSize(bitmap) end

---------------------------------------------------------------------------
-- lcd
---------------------------------------------------------------------------
lcd = {}

---@param r integer 0-255
---@param g integer 0-255
---@param b integer 0-255
---@return integer color usable as (part of) a flags argument
function lcd.RGB(r, g, b) end

---@param x integer
---@param y integer
---@param text string
---@param flags integer? alignment | font size | colour
function lcd.drawText(x, y, text, flags) end

---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param flags integer? colour (from lcd.RGB)
function lcd.drawFilledRectangle(x, y, w, h, flags) end

--- scale is a PERCENTAGE (100 = 1:1) - measured on TX16S MK3, EdgeTX 2.12.0.
---@param bitmap EdgeTxBitmap
---@param x integer
---@param y integer
---@param scale integer?
function lcd.drawBitmap(bitmap, x, y, scale) end

--- Pre-2.7 style loader; main.lua tries Bitmap.open first.
---@param path string
---@return EdgeTxBitmap?
function lcd.loadBitmap(path) end

---@param bitmap EdgeTxBitmap
---@return integer width
---@return integer height
function lcd.getBitmapSize(bitmap) end

--- Text extent. Used by tools/diagtest to measure the real font sizes.
---@param text string
---@param flags integer?
---@return integer width
---@return integer height
function lcd.sizeText(text, flags) end

--- Create/update a telemetry sensor (used by the built-in Rotorflight decoder).
function setTelemetryValue(id, subId, instance, value, unit, precision, name) end
--- Pop one received CRSF frame: command, data table (nil when empty).
function crossfireTelemetryPop() end
--- Queue a CRSF frame; no args = buffer free?; nil when no CRSF module.
function crossfireTelemetryPush(command, data) end

--- Straight line. Confirmed working in the Companion 2.12 TX16S MK3
--- simulator (flight-log chart); not yet seen on the radio itself.
---@param pattern integer SOLID / DOTTED
---@param flags integer color
function lcd.drawLine(x1, y1, x2, y2, pattern, flags) end
SOLID = nil
