-- RF Telem - Rotorflight telemetry widget for EdgeTX colour radios
-- (lvgl, EdgeTX 2.11+; built for the TX16S MK3, EdgeTX 2.12).
--
-- This file stays small on purpose: EdgeTX loads every installed widget's
-- main.lua at start-up, used or not. The widget itself loads when an
-- RF Telem widget is created:
--   core.lua   configuration, telemetry decoder, MSP, alarms, settings
--   view.lua   the screens
--   rf2ui.lua  Rotorflight settings screens (only once those are opened)
-- License: GPL-3.0 (see LICENSE).

local DIR = "/WIDGETS/RFTelem/"
local app

local function load()
  if not app then
    app = assert(loadScript(DIR .. "core.lua"))(DIR)
    assert(loadScript(DIR .. "view.lua"))(app)
  end
  return app
end

-- Widget options (the radio's widget settings; Settings in the widget's
-- menu overrides Theme, Voice and BattLand when set there):
--   Theme     0=color, 1=mono, 2=cyan
--   Mute      source: voice alarms silent while > 0 (critical haptic never)
--   Voice     0=No.7, 1=Ryusei, 2=Takehiro, 3=Himari, 4=Voidoll, 5=Zundamon
--   Close     source: a press closes the flight log / steps the picker
--   BattLand  remaining % for "land now" (10-50)
--   BattSel   multi-position source picking the battery profile (6 bands)
--   BattPrev  source: steps the picker back (e.g. a trim via a logical switch)
--   BattSW    on: SW1..SW6 pick battery profile 1..6
--   Page      source: each press opens the next FC settings page (read only)
local options = {
  { "Theme", VALUE, 0, 0, 2 },
  { "Mute", SOURCE, 0 },
  { "Voice", VALUE, 0, 0, 5 },
  { "Close", SOURCE, 0 },
  { "BattLand", VALUE, 20, 10, 50 },
  { "BattSel", SOURCE, 0 },
  { "BattPrev", SOURCE, 0 },
  { "BattSW", BOOL, 0 },
  { "Page", SOURCE, 0 },
}

return {
  name = "RF Telem",
  options = options,
  useLvgl = true,
  create = function(zone, opts) return load().create(zone, opts) end,
  update = function(wgt, opts) load().update(wgt, opts) end,
  refresh = function(wgt, event, touchState) load().refresh(wgt, event, touchState) end,
  background = function(wgt) load().background(wgt) end,
}
