-- Standalone: luajit mods/qol_toggles/tests/qol_toggles_test.lua
-- Loads the mod through the real headless loader and asserts the TOGGLES
-- submenu rows, the poison 1-HP clamp, the capture full-heal, and the
-- infinite-repel hook.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMod("mods/qol_toggles", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local ex = run.loader.exports.qol_toggles
T.neq(ex, nil, "exports reachable")

-- the toggles read through Game.mods (the loader), which the headless
-- harness does not wire by itself
local Game = require("src.core.Game")
Game.mods = run.loader

-- ------------------------------------------------ the OPTIONS row

local function findRow(game)
  local rows = Runtime.call("ui.options.rows", function(_, r) return r end,
    game, { { id = "text_speed" } })
  for _, row in ipairs(rows) do
    if row.id == "qolToggles" then return row end
  end
  return nil
end

local row = findRow({})
T.neq(row, nil, "the USEFUL TOGGLES row joins the options menu")
T.eq(row.label, "USEFUL TOGGLES", "row label")

-- ------------------------------------------------ the submenu toggles

local state = {}
local rows = ex.toggleRows(
  function(k) return state[k] end,
  function(k, v) state[k] = v end)

T.eq(#rows, 4, "four toggles in the submenu")
T.eq(rows[1].id, "poison_save", "toggle 1: poison survival")
T.eq(rows[2].id, "catch_heal", "toggle 2: full-heal capture")
T.eq(rows[3].id, "repel", "toggle 3: infinite repel")
T.eq(rows[4].id, "field_moves_all", "toggle 4: learnable field moves")

-- ship defaults: everything on except INFINITE REPEL
T.eq(ex.defaultFor("poison_save"), true, "POISON SAVE ships ON")
T.eq(ex.defaultFor("catch_heal"), true, "FULL HEAL CATCH ships ON")
T.eq(ex.defaultFor("repel"), false, "INFINITE REPEL ships OFF")
T.eq(ex.defaultFor("field_moves_all"), true, "FIELD MOVES ALL ships ON")
T.eq(ex.defaultFor("bogus"), false, "unknown keys default OFF")

T.eq(ex.enabledCount(function(k) return state[k] end), 0, "stub state starts empty")

for i, r in ipairs(rows) do
  T.eq(r.value(), "OFF", "row " .. i .. " defaults OFF in a bare stub state")
  T.eq(r.step(), true, "row " .. i .. " steps")
  T.eq(r.value(), "ON", "row " .. i .. " shows ON after the step")
  T.eq(r.step(), true, "row " .. i .. " steps back")
  T.eq(r.value(), "OFF", "row " .. i .. " shows OFF again")
end
T.eq(ex.enabledCount(function(k) return state[k] end), 0, "stub state empty again")

-- ------------------------------------------------ POISON SAVE

do
  local atRisk = { species = "FIXMON_A", nickname = "Squirt", status = "PSN", hp = 1 }
  local healthy = { species = "FIXMON_A", status = "PSN", hp = 5 }
  local fainted = { species = "FIXMON_A", status = "PSN", hp = 0 }
  local clean = { species = "FIXMON_A", status = nil, hp = 1 }
  local party = { atRisk, healthy, fainted, clean }

  local subsided = ex.poisonClamp(party, 1)
  T.eq(#subsided, 1, "only the 1-HP poisoned mon subsides")
  T.eq(atRisk.hp, 1, "clamped to 1 HP, never faints")
  T.eq(atRisk.status, nil, "poison cleared when it subsides")
  T.eq(subsided[1], atRisk, "the subsided mon is returned")
  T.eq(healthy.hp, 5, "a mon above the threshold is untouched")
  T.eq(healthy.status, "PSN", "its poison stays")
  T.eq(fainted.hp, 0, "an already-fainted mon is untouched")
  T.eq(clean.status, nil, "a non-poisoned mon is untouched")
end

do
  -- damage 2: a 2-HP mon survives too
  local a = { species = "FIXMON_A", status = "PSN", hp = 2 }
  local b = { species = "FIXMON_B", status = "PSN", hp = 3 }
  local subsided = ex.poisonClamp({ a, b }, 2)
  T.eq(#subsided, 1, "hp <= damage subsides, hp > damage takes the hit")
  T.eq(a.hp, 1, "2 HP clamps to 1")
  T.eq(b.hp, 3, "3 HP is untouched")
end

-- ------------------------------------------------ FULL HEAL CATCH

do
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(Data, "FIXMON_A", 10)
  mon.hp = 1
  mon.status = "PSN"
  mon.moves[1].pp = 0
  T.eq(ex.healCaught(mon), true, "healCaught reports a full heal")
  T.eq(mon.hp, mon.stats.hp, "HP restored to max")
  T.eq(mon.status, nil, "status cleared")
  T.eq(mon.moves[1].pp, Data.moves[mon.moves[1].id].pp, "PP restored")
end

-- ------------------------------------------------ FIELD MOVES ALL

do
  -- a species that can learn FLY by level-up and CUT/SURF by TM
  local def = {
    learnset = { { level = 1, move = "FIX_TACKLE" }, { level = 5, move = "FLY" } },
    tmhm = { "FIX_CUT", "CUT", "SURF" },
  }
  local mon = { species = "FIXMON_A",
                moves = { { id = "FIX_TACKLE" }, { id = "SURF" } } }
  local learnable = ex.learnableFieldMoves(def, mon)
  -- FLY (learnset), CUT (TM); SURF is known -> excluded
  T.eq(#learnable, 2, "learnable-but-unknown field moves")
  T.eq(learnable[1], "FLY", "a learnset move qualifies")
  T.eq(learnable[2], "CUT", "a TM/HM move qualifies")
end

do
  local def = {
    learnset = { { level = 1, move = "FIX_TACKLE" } },
    tmhm = {},
  }
  local mon = { species = "FIXMON_B", moves = { { id = "FIX_TACKLE" } } }
  T.eq(#ex.learnableFieldMoves(def, mon), 0,
    "a species with no field moves gets nothing")
  T.eq(#ex.learnableFieldMoves(nil, mon), 0,
    "a missing species def gets nothing")
end

do
  -- attach/detach round-trip leaves the moveset untouched
  local def = { learnset = {}, tmhm = { "FLY", "DIG" } }
  local mon = { species = "FIXMON_A", moves = { { id = "FIX_TACKLE" } } }
  local added = ex.attachPhantomMoves(mon, def)
  T.eq(#added, 2, "two phantom slots attached")
  T.eq(#mon.moves, 3, "phantoms sit behind the real moves")
  ex.detachPhantomMoves(mon, added)
  T.eq(#mon.moves, 1, "phantoms removed again")
  T.eq(mon.moves[1].id, "FIX_TACKLE", "the real move survives the round-trip")
end

-- ------------------------------------------------ FIELD MOVES ALL wrap

local bucket = run.loader.modOptions.qol_toggles
if not bucket then bucket = {}; run.loader.modOptions.qol_toggles = bucket end

do
  local flyer = { learnset = { { level = 1, move = "FIX_TACKLE" } },
                  tmhm = { "FLY", "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local pm = {
    party = { mon }, index = 1, battle = false, submenu = nil, tmhm = nil,
    game = { data = { pokemon = { FIXFLYER = flyer } } },
  }
  local seen
  local function stubUpdate(self)
    seen = {}
    for _, mv in ipairs(self.party[1].moves) do seen[#seen + 1] = mv.id end
  end

  bucket.field_moves_all = true
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(seen[1], "FIX_TACKLE", "the real move is still first")
  T.eq(seen[2], "FLY", "the phantom FLY slot reaches the vanilla builder")
  T.eq(seen[3], "DIG", "the phantom DIG slot reaches the vanilla builder")
  T.eq(#mon.moves, 1, "phantom slots are removed after the update")

  bucket.field_moves_all = false
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 1, "toggle OFF: no phantom moves")

  bucket.field_moves_all = true
  pm.battle = true
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 1, "in battle: no phantom moves")
  pm.battle = false

  pm.submenu = { { label = "FLY" } }
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 1, "submenu open: no phantom moves")
  pm.submenu = nil
end

-- ------------------------------------------------ INFINITE REPEL

do
  local vanilla = function() return { species = "FIXMON_A", level = 5 } end
  bucket.repel = true
  T.eq(Runtime.call("encounter.roll", vanilla, nil, nil), nil,
    "repel ON suppresses the wild roll")
  bucket.repel = false
  local enc = Runtime.call("encounter.roll", vanilla, nil, nil)
  T.neq(enc, nil, "repel OFF lets the roll through")
  T.eq(enc.species, "FIXMON_A", "the vanilla roll result is passed through")
end

run.release()
T.finish("qol_toggles")
