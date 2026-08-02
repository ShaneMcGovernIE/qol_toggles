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

T.eq(#rows, 10, "ten toggles in the submenu")
T.eq(rows[1].id, "poison_save", "toggle 1: poison survival")
T.eq(rows[2].id, "catch_heal", "toggle 2: full-heal capture")
T.eq(rows[3].id, "repel", "toggle 3: infinite repel")
T.eq(rows[4].id, "field_moves_all", "toggle 4: learnable field moves")
T.eq(rows[5].id, "badgeless_moves", "toggle 5: badgeless field moves")
T.eq(rows[6].id, "always_catch", "toggle 6: always catch")
T.eq(rows[7].id, "perfect_dvs", "toggle 7: perfect DVs")
T.eq(rows[8].id, "exp_mult", "toggle 8: EXP x2")
T.eq(rows[9].id, "instant_flee", "toggle 9: instant flee")
T.eq(rows[10].id, "heal_map_change", "toggle 10: heal on map change")

-- ship defaults: everything on except INFINITE REPEL and the cheat-y ones
T.eq(ex.defaultFor("poison_save"), true, "POISON SAVE ships ON")
T.eq(ex.defaultFor("catch_heal"), true, "FULL HEAL CATCH ships ON")
T.eq(ex.defaultFor("repel"), false, "INFINITE REPEL ships OFF")
T.eq(ex.defaultFor("field_moves_all"), true, "FIELD MOVES ALL ships ON")
T.eq(ex.defaultFor("badgeless_moves"), false, "BADGELESS MOVES ships OFF")
T.eq(ex.defaultFor("always_catch"), false, "ALWAYS CATCH ships OFF")
T.eq(ex.defaultFor("perfect_dvs"), false, "PERFECT DVS ships OFF")
T.eq(ex.defaultFor("exp_mult"), false, "EXP x2 ships OFF")
T.eq(ex.defaultFor("instant_flee"), false, "INSTANT FLEE ships OFF")
T.eq(ex.defaultFor("heal_map_change"), false, "HEAL ON MAP CHANGE ships OFF")
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

-- ------------------------------------------------ BADGELESS MOVES

do
  local known = { species = "FIXMON_A", moves = { { id = "FLY" } } }
  local pm = {
    party = { known }, index = 1, battle = false, submenu = nil, tmhm = nil,
    game = { data = { pokemon = {} }, save = { party = { known },
                                               inventory = {} } },
  }
  local seenBadges
  local function stubUpdate(self)
    seenBadges = {}
    for k in pairs(self.game.save.inventory) do seenBadges[#seenBadges + 1] = k end
  end

  bucket.badgeless_moves = true
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seenBadges, 5, "all five HM badges are visible to the list builder")
  local remaining = 0
  for _ in pairs(pm.game.save.inventory) do remaining = remaining + 1 end
  T.eq(remaining, 0, "injected badges are removed after the update")

  pm.game.save.inventory.SOULBADGE = 1
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seenBadges, 5, "an owned badge is kept, the other four injected")
  T.eq(pm.game.save.inventory.SOULBADGE, 1, "the owned badge survives")
  remaining = 0
  for _ in pairs(pm.game.save.inventory) do remaining = remaining + 1 end
  T.eq(remaining, 1, "only the owned badge remains after the update")
  pm.game.save.inventory.SOULBADGE = nil

  bucket.badgeless_moves = false
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seenBadges, 0, "toggle OFF: no badge injection")
end

-- ------------------------------------------------ FIELDMOVE ELIGIBILITY

do
  local flyer = { learnset = { { level = 1, move = "FIX_TACKLE" } },
                  tmhm = { "FLY" } }
  local known = { species = "FIXMON_A", moves = { { id = "FLY" } } }
  local learner = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local ctx = { save = { party = { known, learner }, inventory = {} },
                data = { pokemon = { FIXFLYER = flyer } } }
  local vanilla = function() return nil end -- vanilla: badge gate fails

  bucket.badgeless_moves = true
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), known,
    "BADGELESS: a known FLY counts without the badge")
  bucket.badgeless_moves = false

  bucket.field_moves_all = true
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), nil,
    "FIELD MOVES ALL alone: the Thunder Badge gate still applies")
  ctx.save.inventory.THUNDERBADGE = 1
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), known,
    "FIELD MOVES ALL: with the badge, the known mon wins")
  ctx.save.party = { learner }
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), learner,
    "FIELD MOVES ALL: with the badge, a learner counts without knowing FLY")
  ctx.save.inventory.THUNDERBADGE = nil
  bucket.field_moves_all = false
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), nil,
    "toggles OFF: the vanilla (badge-blocked) answer stands")
end

-- ------------------------------------------------ ALWAYS CATCH

do
  local Catching = require("src.battle.Catching")
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(Data, "FIXMON_A", 5)
  local def = Data.pokemon.FIXMON_A
  local rng255 = function() return 255 end

  bucket.always_catch = true
  local caught, shakes = Catching.attempt("POKE_BALL", mon, def, rng255)
  T.eq(caught, true, "ALWAYS CATCH: every ball catches")
  T.eq(shakes, 3, "full three-shake chain")

  bucket.always_catch = false
  caught = Catching.attempt("POKE_BALL", mon, def, rng255)
  T.eq(caught, false, "toggle OFF: the stock roll runs (255 roll > rate 45)")
end

-- ------------------------------------------------ PERFECT DVS

do
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(Data, "FIXMON_A", 10)
  local oldMax = mon.stats.hp
  ex.perfectDVs(mon, Data)
  T.eq(mon.dvs.attack, 15, "attack DV maxed")
  T.eq(mon.dvs.defense, 15, "defense DV maxed")
  T.eq(mon.dvs.speed, 15, "speed DV maxed")
  T.eq(mon.dvs.special, 15, "special DV maxed")
  T.eq(mon.dvs.hp, 15, "hp DV derives to 15")
  T.check(mon.stats.hp >= oldMax, "max DVs never lower max HP")
end

-- ------------------------------------------------ EXP x2

do
  local vanilla = function() return 100 end
  bucket.exp_mult = true
  T.eq(Runtime.call("exp.gain", vanilla, {}), 200, "EXP x2 doubles the gain")
  bucket.exp_mult = false
  T.eq(Runtime.call("exp.gain", vanilla, {}), 100, "toggle OFF passes through")
end

-- ------------------------------------------------ INSTANT FLEE

do
  local vanilla = function() return false end
  bucket.instant_flee = true
  T.eq(Runtime.call("battle.run", vanilla, {}), true,
    "INSTANT FLEE always escapes")
  bucket.instant_flee = false
  T.eq(Runtime.call("battle.run", vanilla, {}), false,
    "toggle OFF passes through")
end

-- ------------------------------------------------ HEAL ON MAP CHANGE

do
  local Pokemon = require("src.pokemon.Pokemon")
  local a = Pokemon.new(Data, "FIXMON_A", 10)
  local b = Pokemon.new(Data, "FIXMON_B", 10)
  a.hp = 1
  a.status = "PSN"
  a.moves[1].pp = 0
  b.hp = 3
  b.status = "BRN"
  b.moves[1].pp = 0
  ex.healParty({ a, b })
  T.eq(a.hp, a.stats.hp, "map-change heal restores HP to max")
  T.eq(a.status, nil, "map-change heal clears status")
  T.eq(a.moves[1].pp, Data.moves[a.moves[1].id].pp, "map-change heal restores PP")
  T.eq(b.hp, b.stats.hp, "a second mon heals too")
  T.eq(b.moves[1].pp, Data.moves[b.moves[1].id].pp, "second mon PP restored")
  ex.healParty(nil)
  ex.healParty({})
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

  -- defensive: a downstream roll that throws (another mod's rate-less
  -- water/grass def) degrades to nil instead of blue-screening the step
  local ok, threw = pcall(function()
    Runtime.call("encounter.roll", function() error("nil rate") end,
                 nil, nil)
  end)
  T.eq(ok, true, "a throwing roll never reaches the caller")
  local suppressed = Runtime.call("encounter.roll",
    function() error("nil rate") end, nil, nil)
  T.eq(suppressed, nil, "the failed roll suppresses to no encounter")
end

run.release()
T.finish("qol_toggles")
