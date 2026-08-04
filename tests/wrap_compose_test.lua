-- Standalone: luajit mods/qol_toggles/tests/wrap_compose_test.lua
-- Regression: QoL Toggles and Mods Hotkeys each wrap OptionRows.draw to
-- ticker overflowing row labels, and both blank/restore the row's label
-- through a shared row._label slot.  Without the ownership guard the inner
-- wrap's restore clobbers the outer wrap's saved label, the row ends up
-- with label = nil, and Font.draw(nil) crashes the frame the row is
-- visible (scrolling the QOL TOGGLES menu onto HEAL ON MAP CHANGE).
--
-- Runs in its own process (not nested inside the qol suite): a fresh
-- dataset inherits the already-merged Data singleton through __index, so
-- a second loadMod in the same process collides on the statuses registry.
-- This file loads BOTH mods in one loader, the in-game setup, and draws
-- the ticker row repeatedly -- the exact sequence that crashed.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local run = T.sdk.loadMods({ "mods/qol_toggles", "mods/mods_hotkeys" })
T.eq(#run.errors, 0, "both ticker mods load together")

local ex = run.loader.exports.qol_toggles
T.neq(ex, nil, "qol exports reachable")

local state = {}
local rows = ex.toggleRows(function(k) return state[k] end,
                          function(k, v) state[k] = v end)
local ticked
for _, row in ipairs(rows) do
  if row.ticker then ticked = row break end
end
T.neq(ticked, nil, "HEAL ON MAP CHANGE ticks")
T.eq(ticked.id, "heal_map_change", "the ticker row is HEAL ON MAP CHANGE")

-- draw the row across several scroll positions, like scrolling the menu
-- down onto the row and wrapping around the list
local OptionRows = require("src.ui.OptionRows")
for i = 1, 4 do
  OptionRows.draw({}, rows, 13 + i, 9 + i, "CANCEL", 16)
end
T.eq(ticked.label, "HEAL ON MAP CHANGE",
     "the ticker label survives repeated draws (no nil restore)")

-- the ticker still advances its offset after the repeated draws
ticked.tick = 3
OptionRows.draw({}, rows, 13, 9, "CANCEL", 16)
T.eq(ticked.label, "HEAL ON MAP CHANGE", "label intact after a tickered draw")

run.release()
T.finish("wrap_compose")
