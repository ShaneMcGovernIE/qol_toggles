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
T.neq(row, nil, "the QOL TOGGLES row joins the options menu")
T.eq(row.label, "QOL TOGGLES", "row label")

-- ------------------------------------------------ the submenu toggles

local state = {}
local rows = ex.toggleRows(
  function(k) return state[k] end,
  function(k, v) state[k] = v end)

T.eq(#rows, 18, "eighteen toggles in the submenu")
T.eq(rows[1].id, "poison_save", "toggle 1: poison survival")
T.eq(rows[2].id, "catch_heal", "toggle 2: full-heal capture")
T.eq(rows[3].id, "repel", "toggle 3: infinite repel")
T.eq(rows[4].id, "field_moves_all", "toggle 4: learnable field moves")
T.eq(rows[5].id, "badgeless_moves", "toggle 5: badgeless field moves")
T.eq(rows[6].id, "hm_item_required", "toggle 6: HM item gate")
T.eq(rows[7].id, "unlimited_tms", "toggle 7: unlimited TMs")
T.eq(rows[8].id, "forgettable_hms", "toggle 8: forgettable HMs")
T.eq(rows[9].id, "always_catch", "toggle 9: always catch")
T.eq(rows[10].id, "perfect_dvs", "toggle 10: perfect DVs")
T.eq(rows[11].id, "exp_mult", "toggle 11: EXP x2")
T.eq(rows[12].id, "catch_exp", "toggle 12: catch gives EXP")
T.eq(rows[13].id, "instant_flee", "toggle 13: instant flee")
T.eq(rows[14].id, "remember_cursor", "toggle 14: remember battle cursor")
T.eq(rows[15].id, "heal_map_change", "toggle 15: heal on map change")
T.eq(rows[16].id, "quick_ssanne", "toggle 16: quick S.S. Anne")
T.eq(rows[17].id, "last_item", "toggle 17: last item in battle")
T.eq(rows[18].id, "free_great_ball", "toggle 18: free Great Ball bonus")

-- ship defaults: everything on except INFINITE REPEL and the cheat-y ones
T.eq(ex.defaultFor("poison_save"), true, "POISON SAVE ships ON")
T.eq(ex.defaultFor("catch_heal"), true, "FULL HEAL CATCH ships ON")
T.eq(ex.defaultFor("repel"), false, "INFINITE REPEL ships OFF")
T.eq(ex.defaultFor("field_moves_all"), true, "FIELD MOVES ALL ships ON")
T.eq(ex.defaultFor("badgeless_moves"), false, "BADGELESS MOVES ships OFF")
T.eq(ex.defaultFor("hm_item_required"), true, "HM ITEM REQUIRED ships ON")
T.eq(ex.defaultFor("unlimited_tms"), true, "UNLIMITED TMs ships ON")
T.eq(ex.defaultFor("forgettable_hms"), true, "FORGETTABLE HMs ships ON")
T.eq(ex.defaultFor("always_catch"), false, "ALWAYS CATCH ships OFF")
T.eq(ex.defaultFor("perfect_dvs"), false, "PERFECT DVS ships OFF")
T.eq(ex.defaultFor("exp_mult"), false, "EXP x2 ships OFF")
T.eq(ex.defaultFor("catch_exp"), false, "CATCH GIVES EXP ships OFF")
T.eq(ex.defaultFor("instant_flee"), false, "INSTANT FLEE ships OFF")
T.eq(ex.defaultFor("remember_cursor"), true, "REMEMBER CURSOR ships ON")
T.eq(ex.defaultFor("heal_map_change"), false, "HEAL ON MAP CHANGE ships OFF")
T.eq(ex.defaultFor("quick_ssanne"), false, "QUICK S.S. ANNE ships OFF")
T.eq(ex.defaultFor("last_item"), false, "LAST ITEM (M) ships OFF")
T.eq(ex.defaultFor("free_great_ball"), false, "POKEBALL BONUS ships OFF")
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
    game = { data = { pokemon = { FIXFLYER = flyer } },
             save = { inventory = { HM_FLY = 1 } } },
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

do
  -- HM ITEM REQUIRED: the phantom HM slots need the item held (no CUT on
  -- the Cascade Badge alone -- the HM is on the S.S. Anne); DIG has no
  -- HM item and always shows
  local flyer = { learnset = { { level = 1, move = "FIX_TACKLE" } },
                  tmhm = { "FLY", "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local pm = {
    party = { mon }, index = 1, battle = false, submenu = nil, tmhm = nil,
    game = { data = { pokemon = { FIXFLYER = flyer } },
             save = { inventory = {} } },
  }
  local seen
  local function stubUpdate(self)
    seen = {}
    for _, mv in ipairs(self.party[1].moves) do seen[#seen + 1] = mv.id end
  end

  bucket.field_moves_all = true
  bucket.hm_item_required = true
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 2, "no HM_FLY held: one phantom slot, not two")
  T.eq(seen[2], "DIG", "the item-less DIG slot still shows")

  pm.game.save.inventory.HM_FLY = 1
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 3, "holding HM_FLY brings the FLY slot back")
  T.eq(seen[2], "FLY", "FLY sits ahead of DIG once allowed")
  pm.game.save.inventory.HM_FLY = nil

  bucket.hm_item_required = false
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 3, "toggle OFF: the item gate lifts")
  bucket.field_moves_all = false
  bucket.hm_item_required = nil
end

do
  -- the pure resolvers gate identically to the wrap
  local flyer = { learnset = { { level = 1, move = "FIX_TACKLE" } },
                  tmhm = { "FLY", "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local learnable = ex.learnableFieldMoves(flyer, mon, {}, true)
  T.eq(#learnable, 1, "learnable without the item: only DIG")
  T.eq(learnable[1], "DIG", "the non-HM move survives the gate")
  T.eq(#ex.learnableFieldMoves(flyer, mon, { HM_FLY = 1 }, true), 2,
    "holding HM_FLY: FLY joins DIG")
  T.eq(#ex.learnableFieldMoves(flyer, mon, {}, false), 2,
    "toggle OFF: no item gate")

  local known = { species = "FIXMON_A", moves = { { id = "FLY" } } }
  T.eq(ex.eligibleMon({ known }, { pokemon = {} }, "FLY", false, {}, true),
    known, "a mon that knows FLY stays eligible with no item")
  T.eq(ex.eligibleMon({ mon }, { pokemon = { FIXFLYER = flyer } }, "FLY",
      true, {}, true), nil, "phantom FLY needs the item held")
  T.eq(ex.eligibleMon({ mon }, { pokemon = { FIXFLYER = flyer } }, "FLY",
      true, { HM_FLY = 1 }, true), mon, "holding HM_FLY grants it")
  T.eq(ex.eligibleMon({ mon }, { pokemon = { FIXFLYER = flyer } }, "FLY",
      true, {}, false), mon, "toggle OFF: no item gate")
end

do
  -- item/script target picker (ether, PP UP, ...): onSwitch reads
  -- mon.moves directly and formats mv.pp, so phantom slots must never
  -- attach -- BagMenu.lua:366 would crash on their nil pp
  local flyer = { learnset = { { level = 1, move = "FIX_TACKLE" } },
                  tmhm = { "FLY", "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local pm = {
    party = { mon }, index = 1, battle = false, submenu = nil, tmhm = nil,
    pickOnly = true,
    game = { data = { pokemon = { FIXFLYER = flyer } },
             save = { inventory = {} } },
  }
  local seen
  local function stubUpdate(self)
    seen = {}
    for _, mv in ipairs(self.party[1].moves) do seen[#seen + 1] = mv.id end
  end

  bucket.field_moves_all = true
  bucket.badgeless_moves = true
  ex.withPhantoms(pm, stubUpdate, 1/60)
  T.eq(#seen, 1, "picker open: no phantom moves on the chosen mon")
  T.eq(seen[1], "FIX_TACKLE", "only the real move is visible to the picker")
  T.eq(#mon.moves, 1, "the moveset is untouched after the update")
  local remaining = 0
  for _ in pairs(pm.game.save.inventory) do remaining = remaining + 1 end
  T.eq(remaining, 0, "picker open: no badge injection")
  bucket.field_moves_all = false
  bucket.badgeless_moves = false
end

-- ------------------------------------------- UNLIMITED TMs / HM FORGET

do
  bucket.unlimited_tms = true
  T.eq(ex.keepTm("learn"), "learnkept",
    "toggle ON: a TM teach keeps the TM (no consume)")
  T.eq(ex.keepTm("learnkept"), "learnkept",
    "toggle ON: an HM teach stays kept")
  T.eq(ex.keepTm("consumed"), "consumed",
    "toggle ON: non-machine results pass through")
  bucket.unlimited_tms = false
  T.eq(ex.keepTm("learn"), "learn",
    "toggle OFF: TMs are single-use again")
  bucket.unlimited_tms = true
end

do
  local function press(btn)
    return { wasPressed = function(_, k) return k == btn end }
  end
  local function menu(input, index, moves)
    local state = {}
    return setmetatable({
      game = { input = input,
               data = { moves = { FLY = { name = "FLY" },
                                  FIX_EMBER = { name = "FIX EMBER", pp = 15 } } } },
      mon = { moves = moves or { { id = "FLY", pp = 5 },
                                 { id = "FIX_TACKLE", pp = 10 } } },
      newMoveId = "FIX_EMBER",
      selecting = true,
      index = index or 1,
      confirmAbandon = function() state.abandoned = true end,
      finish = function(_, learned) state.learned = learned end,
    }, { __index = function() return nil end }), state
  end

  local m, state = menu(press("a"))
  ex.forgetUpdate(m, 1/60)
  T.eq(m.mon.moves[1].id, "FIX_EMBER", "an HM move can be forgotten")
  T.eq(m.forgot, "FLY", "the forgotten move's name is recorded")
  T.eq(m.mon.moves[1].pp, 15, "the new move carries its base PP")
  T.eq(state.learned, true, "finish(true) reports the swap")
  T.eq(#m.mon.moves, 2, "moveset size is unchanged")

  m, state = menu(press("a"), 3) -- the CANCEL row
  ex.forgetUpdate(m, 1/60)
  T.eq(state.abandoned, true, "A on CANCEL abandons the learn")

  m, state = menu(press("b"))
  ex.forgetUpdate(m, 1/60)
  T.eq(state.abandoned, true, "B abandons the learn")

  m = menu(press("up"), 3)
  ex.forgetUpdate(m, 1/60)
  T.eq(m.index, 2, "UP off the bottom wraps to the last move")
  m = menu(press("down"), 2)
  ex.forgetUpdate(m, 1/60)
  T.eq(m.index, 3, "DOWN off the last move lands on CANCEL")

  m = menu(press("a"))
  m.selecting = false
  ex.forgetUpdate(m, 1/60)
  T.eq(m.mon.moves[1].id, "FLY", "no input while not selecting")
end

do
  -- the installed wrap on MoveLearnMenu.update: the vanilla HM gate when
  -- the toggle is OFF, the gate-free forget when it is ON
  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  local function press(btn)
    return { wasPressed = function(_, k) return k == btn end }
  end
  local pushes = 0
  local function fullMenu(input)
    return {
      game = { input = input,
               data = { moves = { FLY = { name = "FLY" },
                                  FIX_EMBER = { name = "FIX EMBER", pp = 15 } } },
               stack = { push = function() pushes = pushes + 1 end } },
      mon = { moves = { { id = "FLY", pp = 5 },
                        { id = "FIX_TACKLE", pp = 10 } } },
      newMoveId = "FIX_EMBER",
      selecting = true,
      index = 1,
      confirmAbandon = function() end,
      finish = function() end,
    }
  end

  bucket.forgettable_hms = false
  pushes = 0
  local m = fullMenu(press("a"))
  MoveLearnMenu.update(m, 1/60)
  T.eq(m.mon.moves[1].id, "FLY", "toggle OFF: the vanilla gate still blocks")
  T.eq(pushes, 1, "toggle OFF: the refusal textbox is shown")

  bucket.forgettable_hms = true
  pushes = 0
  m = fullMenu(press("a"))
  MoveLearnMenu.update(m, 1/60)
  T.eq(m.mon.moves[1].id, "FIX_EMBER", "toggle ON: the HM is forgotten")
  T.eq(pushes, 0, "toggle ON: no refusal textbox")
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
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), nil,
    "HM ITEM REQUIRED: the badge alone can't grant phantom FLY")
  ctx.save.inventory.HM_FLY = 1
  T.eq(Runtime.call("fieldmove.eligibility", vanilla, "FLY", ctx), learner,
    "FIELD MOVES ALL: with the HM and the badge, a learner counts")
  ctx.save.inventory.THUNDERBADGE = nil
  ctx.save.inventory.HM_FLY = nil
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

-- ------------------------------------------------ CATCH GIVES EXP

do
  local vanilla = function() return false end
  bucket.catch_exp = true
  T.eq(Runtime.call("battle.catch_exp", vanilla, {}), true,
       "CATCH GIVES EXP opts the capture into the faint award")
  bucket.catch_exp = false
  T.eq(Runtime.call("battle.catch_exp", vanilla, {}), false,
       "toggle OFF passes through (vanilla catches grant nothing)")
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

-- ------------------------------------------------ REMEMBER CURSOR

do
  local battle = { menuIndex = 3 }
  bucket.remember_cursor = true
  T.eq(ex.applyCursorRemember(battle, true), 3,
    "toggle ON: the ITEM cursor is remembered")
  T.eq(battle.menuIndex, 3, "toggle ON: menuIndex untouched")

  bucket.remember_cursor = false
  battle.menuIndex = 4
  T.eq(ex.applyCursorRemember(battle, false), 1,
    "toggle OFF: the cursor parks on FIGHT")
  T.eq(battle.menuIndex, 1, "toggle OFF: menuIndex reset to 1")

  T.eq(ex.applyCursorRemember(nil, false), nil,
    "a missing battle is a no-op")
  bucket.remember_cursor = true
end

do
  -- the installed turn_ended listener drives the reset at the moment the
  -- next turn's menu opens
  local battle = { menuIndex = 3 }
  bucket.remember_cursor = false
  Runtime.emit("battle.turn_ended", { battle = battle, turn = 2 })
  T.eq(battle.menuIndex, 1, "turn_ended resets the cursor when OFF")
  bucket.remember_cursor = true
  battle.menuIndex = 3
  Runtime.emit("battle.turn_ended", { battle = battle, turn = 3 })
  T.eq(battle.menuIndex, 3, "turn_ended leaves the cursor when ON")
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

-- ------------------------------------------------ QUICK S.S. ANNE

do
  local MapScripts = require("src.script.MapScripts")
  require("data.scripts.init")
  local view = MapScripts.get("VERMILION_CITY")
  T.check(type(view and view.onStep) == "function",
    "the merged Vermilion script has an onStep")

  local pushed = 0
  local stack = { states = {} }
  function stack:push(s) pushed = pushed + 1 end
  local game = {
    data = Data,
    save = { flags = {}, inventory = { S_S_TICKET = 1 } },
    stack = stack,
  }
  local ow = { player = { facing = "down" }, scriptMove = function() end }

  bucket.quick_ssanne = false
  pushed = 0
  view.onStep(game, ow, 18, 30)
  T.check(pushed > 0, "toggle OFF: the ticket prompt still runs")

  bucket.quick_ssanne = true
  bucket.ssanne_prompted = nil
  pushed = 0
  view.onStep(game, ow, 18, 30)
  T.check(pushed > 0, "first pass: the prompt shows once")
  T.eq(bucket.ssanne_prompted, true, "first pass: the prompted flag is stored")

  pushed = 0
  local r2 = view.onStep(game, ow, 18, 30)
  T.eq(r2, true, "later passes: the step is consumed")
  T.eq(pushed, 0, "later passes: no dialogue, no stop")

  game.save.flags.EVENT_SS_ANNE_LEFT = true
  pushed = 0
  view.onStep(game, ow, 18, 30)
  T.check(pushed > 0, "ship left: the set-sail guard still runs")
  game.save.flags.EVENT_SS_ANNE_LEFT = nil

  pushed = 0
  view.onStep(game, ow, 5, 5)
  T.eq(pushed, 0, "other cells are untouched")
  ow.player.facing = "up"
  pushed = 0
  view.onStep(game, ow, 18, 30)
  T.eq(pushed, 0, "facing up is untouched")
  ow.player.facing = "down"
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

-- ------------------------------------------------ LAST ITEM (M)

do
  local Pokemon = require("src.pokemon.Pokemon")
  local ItemEffects = require("src.inventory.ItemEffects")

  -- recording: the installed ItemEffects.use wrap remembers successful
  -- uses and forgets failed uses and TM teaches
  ex.setLastItem(nil)
  local save = { inventory = {}, player = { name = "RED" } }
  local squirt = Pokemon.new(Data, "FIXMON_A", 10)
  squirt.hp = 1
  T.eq(ItemEffects.use(Data, save, "POTION", squirt, nil), "consumed",
    "the potion goes off")
  T.eq(ex.lastItem(), "POTION", "the successful use is remembered")
  ItemEffects.use(Data, save, "FIX_POTION", squirt, nil)
  T.eq(ex.lastItem(), "POTION", "a failed use is not remembered")
  ItemEffects.use(Data, save, "FIX_TM", squirt, nil)
  T.eq(ex.lastItem(), "POTION", "a TM teach is not remembered")
  ex.setLastItem(nil)

  -- useLastItem: a ball throws at the foe, is consumed, and the battle
  -- leaves the menu exactly like the bag flow
  local thrown
  local opened
  local used = 0
  local game = {
    data = Data,
    overworld = nil,
    stack = { push = function() end },
  }
  local battle = {
    game = game,
    save = { inventory = { POKE_BALL = 3 } },
    kind = "wild",
    phase = "menu", afterQueue = "menu",
    throwBall = function(_, id) thrown = id end,
    openItems = function() opened = true end,
    itemUsed = function() used = used + 1 end,
  }
  game.save = battle.save
  ex.setLastItem("POKE_BALL")
  T.eq(ex.useLastItem(battle), true, "a ball takes the turn")
  T.eq(thrown, "POKE_BALL", "the last ball is thrown")
  T.eq(battle.save.inventory.POKE_BALL, 2, "the ball is consumed")
  T.eq(battle.phase, "messages", "the battle leaves the menu")
  T.eq(battle.afterQueue, "menu", "the queue hands back to the menu")
  T.eq(opened, nil, "a stocked ball never opens the bag")

  -- useLastItem: healing opens the vanilla party picker (the party
  -- screen) instead of auto-targeting; the picked mon gets the item, the
  -- turn is spent when the text box closes (the itemUsed callback, like
  -- the bag's showMessages tail)
  local pushed = {}
  local active = Pokemon.new(Data, "FIXMON_A", 10)
  active.hp = 1
  game.stack = { push = function(_, s) pushed[#pushed + 1] = s end }
  battle.save.inventory = { POTION = 2 }
  battle.player = { mon = active }
  local Screens = require("src.ui.Screens")
  local savedPush = Screens.push
  local pickerOpts
  Screens.push = function(_, id, opts)
    pickerOpts = { id = id, opts = opts }
  end
  ex.setLastItem("POTION")
  T.eq(ex.useLastItem(battle), true, "the potion takes the turn")
  T.neq(pickerOpts, nil, "the party screen opens for the target pick")
  T.eq(pickerOpts.id, "PartyMenu", "the party screen is the picker")
  T.eq(pickerOpts.opts.pickOnly, true, "the picker is item-pick mode")
  T.eq(pickerOpts.opts.keepOpen, false, "in battle the picker pops itself")
  T.eq(active.hp, 1, "nothing is healed before a mon is picked")
  T.eq(battle.save.inventory.POTION, 2, "nothing is consumed yet")
  T.eq(battle.phase, "messages", "the battle leaves the menu")
  T.eq(battle.afterQueue, "menu", "the queue hands back to the menu")
  local benched = Pokemon.new(Data, "FIXMON_B", 10)
  benched.hp = 1
  pickerOpts.opts.onSwitch(benched, {})
  T.eq(benched.hp, 21, "the picked mon is healed")
  T.eq(active.hp, 1, "the active battler is not touched")
  T.eq(battle.save.inventory.POTION, 1, "the potion is consumed")
  T.eq(#pushed, 1, "the heal text box is queued")
  T.eq(used, 0, "the turn is spent only when the box closes")
  T.neq(pushed[1].onDone, nil, "the box carries the itemUsed callback")
  pushed[1].onDone()
  T.eq(used, 1, "itemUsed() spends the turn once the text is read")

  -- ETHERs ask for the move first (the bag's move list), then the picked
  -- move is the one that gets the PP
  local etherMon = Pokemon.new(Data, "FIXMON_A", 10)
  etherMon.moves[1].pp = 0
  battle.save.inventory = { ETHER = 1 }
  pickerOpts = nil
  pushed = {}
  ex.setLastItem("ETHER")
  T.eq(ex.useLastItem(battle), true, "the ETHER takes the turn")
  T.neq(pickerOpts, nil, "the party screen opens for an ETHER too")
  pickerOpts.opts.onSwitch(etherMon, {})
  local moveList = pushed[1]
  T.neq(moveList, nil, "the move list is queued")
  T.eq(#moveList.items, #etherMon.moves, "one row per move")
  T.eq(moveList.items[1].right, "0", "the depleted move shows its PP")
  moveList.items[1].value = 1
  local closed = 0
  moveList.onChoose(moveList.items[1], { close = function() closed = closed + 1 end })
  T.eq(closed, 1, "the move list closes after the pick")
  T.eq(etherMon.moves[1].pp, 10, "the picked move gets its PP back")
  T.eq(battle.save.inventory.ETHER, nil, "the ETHER is consumed")
  Screens.push = savedPush
  battle.player = nil

  -- useLastItem: with nothing remembered (or the item gone) the bag
  -- opens so the player can pick the next item
  opened = nil
  ex.setLastItem(nil)
  T.eq(ex.useLastItem(battle), nil, "no last item: no action")
  T.eq(opened, true, "the bag opens so the player can pick one")
  opened = nil
  ex.setLastItem("POKE_BALL")
  T.eq(ex.useLastItem(battle), nil, "an out-of-stock item: no action")
  T.eq(opened, true, "the bag opens when the item is gone")
  ex.setLastItem(nil)
end

-- ------------------------------------------------ POKEBALL BONUS

-- pure math: one free GREAT BALL per ten POKé BALLS, cumulative
T.eq(ex.bonusBalls(0, 10), 1, "a single 10-ball buy unlocks one ball")
T.eq(ex.bonusBalls(0, 20), 2, "a 20-ball buy unlocks two")
T.eq(ex.bonusBalls(9, 1), 1, "a 10th cumulative ball unlocks the first")
T.eq(ex.bonusBalls(10, 1), 0, "the 11th ball is not a new ten")
T.eq(ex.bonusBalls(19, 1), 1, "the 20th cumulative ball unlocks the second")
T.eq(ex.bonusBalls(0, 0), 0, "a zero buy unlocks nothing")
T.eq(ex.bonusBalls(5, 0), 0, "an empty qty unlocks nothing")

-- the clerk's announcement is the requested free-ball message
T.eq(ex.bonusMessage(),
     "Thanks for your\nsupport,\vplease take\nthis free\vGreat Ball!",
     "the free Great Ball message reads as asked")

-- the live Bag.add wrap: buying 10 POKé BALLS while the mart's BUY list
-- is open grants a GREAT BALL, persists the cumulative count in the
-- slot's modData, and queues the clerk's message
do
  local Bag = require("src.inventory.Bag")
  local pushed = {}
  local save = { inventory = {}, money = 5000, bagOrder = {} }
  Game.save = save
  Game.stack = { push = function(_, s) pushed[#pushed + 1] = s end }
  run.loader.modSave = run.loader.modSave or {}
  run.loader.modOptions = run.loader.modOptions or {}
  run.loader.modOptions.qol_toggles = run.loader.modOptions.qol_toggles or {}
  run.loader.modOptions.qol_toggles.free_great_ball = true
  ex.setMartBuyOpen(true)

  T.eq(Bag.add(save, "POKE_BALL", 10, Data), true, "the ball buy lands")
  T.eq(save.inventory.POKE_BALL, 10, "ten POKé BALLS in the bag")
  T.eq(save.inventory.GREAT_BALL, 1, "one free GREAT BALL is granted")
  T.eq(run.loader.modSave.qol_toggles.pokeballs_bought, 10,
       "the cumulative count is stored in the slot's modData")
  T.eq(#pushed, 1, "the clerk's message is queued")
  T.neq(pushed[1].pages, nil, "the pushed state is a real TextBox")

  -- a second 5-ball buy does not cross a ten boundary
  Bag.add(save, "POKE_BALL", 5, Data)
  T.eq(save.inventory.GREAT_BALL, 1, "five more balls earn nothing yet")
  T.eq(run.loader.modSave.qol_toggles.pokeballs_bought, 15,
       "the count keeps accumulating")
  T.eq(#pushed, 1, "no second message below the boundary")

  -- the 5th more (cumulative 20) earns the second ball and its message
  Bag.add(save, "POKE_BALL", 5, Data)
  T.eq(save.inventory.GREAT_BALL, 2, "cumulative twenty unlocks the second")
  T.eq(#pushed, 2, "a second purchase on a boundary announces again")

  -- balls that are not bought never count: with the buy window closed the
  -- wrap is inert even for POKé BALLS
  ex.setMartBuyOpen(false)
  Bag.add(save, "POKE_BALL", 10, Data)
  T.eq(run.loader.modSave.qol_toggles.pokeballs_bought, 20,
       "a non-mart ball add is not counted")
  T.eq(save.inventory.GREAT_BALL, 2, "no bonus outside the buy window")

  -- a full bag blocks the buy, so nothing is counted or granted
  ex.setMartBuyOpen(true)
  local full = { inventory = {}, money = 5000, bagOrder = {} }
  Game.save = full
  for i = 1, 20 do full.inventory["ITEM_" .. i] = 1 end
  T.eq(Bag.add(full, "POKE_BALL", 10, Data), false,
       "a full bag refuses the buy")
  T.eq(full.inventory.GREAT_BALL, nil, "a failed buy earns no bonus")
  T.eq(run.loader.modSave.qol_toggles.pokeballs_bought, 20,
       "a failed buy is not counted")
  Game.save = nil
  Game.stack = nil
end

-- ------- the label ticker for overflowing rows

-- pure offset math: hold at each end, 16px/s between (the MoveRelearn
-- name ticker's pacing)
local to = ex.tickerOffset
T.eq(to(0, 40), 0, "ticker starts at the label head")
T.eq(to(0.5, 40), 0, "start hold keeps the label still")
T.eq(to(1.6 + 0.5, 40), -8, "scrolls out at 16px/s")
T.check(math.abs(to(1.6 + 40 / 16, 40) + 40) < 1e-9,
        "fully scrolled to the label tail")
T.eq(to(1.6 + 2.5 + 0.6, 40), -40, "end hold keeps the tail visible")
T.check(math.abs(to(1.6 * 2 + 2.5 + 0.25, 40) + 36) < 1e-9,
        "scrolls back at 16px/s")
T.eq(to(1.6 * 2 + 2.5 * 2 + 0.1, 40), 0, "the cycle wraps to a new hold")
T.eq(to(5, 0), 0, "a fitting label never scrolls")
T.eq(to(5, nil), 0, "nil overflow never scrolls")

-- the ticker record: long labels overflow the 136px window, short ones fit
T.eq(ex.tickerFor("POISON SAVE"), nil, "a fitting toggle label has no ticker")
T.eq(ex.tickerFor("ON"), nil, "a one-word label has no ticker")
local tf = ex.tickerFor("Crystal Animated Sprites With Shiny Visuals")
T.neq(tf, nil, "an overflowing label ticks")
T.eq(tf.x, 16, "ticker starts at the label's x")
T.eq(tf.w, 136, "ticker clips at the inner right edge (152-16)")
T.check(tf.overflow > 0, "overflow is the pixels past the window")

-- exactly one shipped toggle overflows its window: HEAL ON MAP CHANGE is
-- 18 glyphs = 144px > 136, so it ticks live; every other label fits
for _, row in ipairs(rows) do
  local expected = row.id == "heal_map_change"
  if expected then
    T.neq(row.ticker, nil, "HEAL ON MAP CHANGE ticks (" .. row.label .. ")")
    T.check(row.ticker.overflow == 8,
            "HEAL ON MAP CHANGE overflows by 8px")
  else
    T.eq(row.ticker, nil, "toggle rows fit (" .. row.label .. ")")
  end
end

-- the OptionRows.draw wrap restores ticker-row labels after the vanilla
-- pass, so no row is left blanked even when it ticked
local OptionRows = require("src.ui.OptionRows")
local fakeRow = {
  id = "x", label = "Crystal Animated Sprites With Shiny Visuals",
  ticker = tf, tick = 3,
}
local fakeRows = { fakeRow }
OptionRows.draw({}, fakeRows, 1, 0, "CANCEL", 2)
T.eq(fakeRow.label, "Crystal Animated Sprites With Shiny Visuals",
     "the ticker label is restored after the draw pass")
OptionRows.draw({}, { { id = "plain", label = "POISON SAVE" } }, 1, 0,
                "CANCEL", 2)
T.eq(fakeRow.label, "Crystal Animated Sprites With Shiny Visuals",
     "a later plain draw leaves the ticker row untouched")

-- ------- the per-toggle help boxes (START / P on a row)

-- every shipped toggle has an in-depth explanation, unknown ids have none
for _, spec in ipairs({ -- the ids are stable, from the TOGGLES list
  "poison_save", "catch_heal", "repel", "field_moves_all",
  "badgeless_moves", "hm_item_required", "unlimited_tms",
  "forgettable_hms", "always_catch", "perfect_dvs", "exp_mult",
  "catch_exp", "instant_flee", "remember_cursor", "heal_map_change",
  "quick_ssanne", "last_item", "free_great_ball",
}) do
  local help = ex.helpFor(spec)
  T.check(type(help) == "string" and #help > 0,
          "every toggle has help text (" .. spec .. ")")
end
T.eq(ex.helpFor("not_a_toggle"), nil, "unknown ids have no help")

-- the rows carry the help so the menu can open it without re-looking up
for _, row in ipairs(rows) do
  T.eq(row.help, ex.helpFor(row.id), "the row carries its help (" .. row.id .. ")")
end

-- a latched help request opens the full-screen popup on the menu itself
local pressed = {}
local helpGame = {
  -- method-form stub: wasPressed(self, btn), like the engine's Input
  input = { wasPressed = function(_, b) return pressed[b] == true end },
  stack = { push = function() end },
}
local helpMenu = run.loader.content.screens:get("QolTogglesMenu").new(helpGame)
T.eq(helpMenu._qolTogglesMenu, true, "the menu is tagged for the latch gate")
ex.requestHelp()
helpMenu:update(1 / 60)
T.neq(helpMenu.helpRow, nil, "a help request opens the popup")
T.eq(helpMenu.helpRow.id, "poison_save", "the popup is the cursor's row")
T.eq(helpMenu.helpRow.help, ex.helpFor("poison_save"),
     "the popup carries the row's full help")

-- every help paginates into the popup body box (7 lines of 17 glyphs)
local TextBox = require("src.render.TextBox")
for _, row in ipairs(helpMenu.rows) do
  local lines = TextBox.paginate((row.help or ""):gsub("\v", "\n"), 17)[1]
  T.check(#lines <= 7,
          "help fits the popup box (" .. row.id .. ": " .. #lines .. " lines)")
end

-- the popup persists across updates (the latch is consumed) and B closes it
helpMenu:update(1 / 60)
T.neq(helpMenu.helpRow, nil, "the popup stays open")
pressed.b = true
helpMenu:update(1 / 60)
T.eq(helpMenu.helpRow, nil, "B closes the popup")
pressed.b = nil

-- ------- the slow vertical scroll for over-long descriptions

-- pure offset math: same hold/scroll/hold/scroll-back shape as the label
-- ticker, but slower (8px/s = one line per second)
local vo = ex.vertOffset
T.eq(vo(0, 40), 0, "vertical scroll starts at the head")
T.eq(vo(0.5, 40), 0, "start hold keeps the text still")
T.eq(vo(1.6 + 0.5, 40), -4, "scrolls up at 8px/s")
T.check(math.abs(vo(1.6 + 40 / 8, 40) + 40) < 1e-9,
        "fully scrolled to the tail")
T.eq(vo(1.6 + 5 + 0.6, 40), -40, "end hold keeps the tail visible")
T.check(math.abs(vo(1.6 * 2 + 5 + 0.25, 40) + 38) < 1e-9,
        "scrolls back down at 8px/s")
T.eq(vo(1.6 * 2 + 5 * 2 + 0.1, 40), 0, "the cycle wraps to a new hold")
T.eq(vo(5, 0), 0, "fitting text never scrolls")
T.eq(vo(5, nil), 0, "nil overflow never scrolls")

-- a description taller than the popup box engages the scissored scroll;
-- the scissor is clipped to the body box interior and cleared after
local scissorCalls = {}
local savedScissor = love.graphics.setScissor
love.graphics.setScissor = function(x, y, w, h)
  scissorCalls[#scissorCalls + 1] = { x = x, y = y, w = w, h = h }
end
local tallHelp = "line one\nline two\nline three\nline four\n"
  .. "line five\nline six\nline seven\nline eight\nline nine"
helpMenu.helpRow = { label = "TALL", help = tallHelp }
helpMenu.helpTick = 2 -- mid-scroll (1.6s hold is over)
helpMenu:draw()
love.graphics.setScissor = savedScissor
T.eq(#scissorCalls, 2, "the scroll path scissored and cleared")
T.eq(scissorCalls[1].x, 16, "scissor starts at the body text x")
T.eq(scissorCalls[1].y, 40, "scissor starts at the body text y")
T.eq(scissorCalls[1].w, 136, "scissor is one text column wide")
T.eq(scissorCalls[1].h, 56, "scissor is the seven-row body")
T.eq(scissorCalls[2].x, nil, "scissor was cleared")
pressed.b = true
helpMenu:update(1 / 60)
pressed.b = nil
T.eq(helpMenu.helpRow, nil, "popup closed after the tall draw")

-- a START/P press while the popup is open closes it too, never re-opens it
ex.requestHelp()
helpMenu:update(1 / 60)
T.neq(helpMenu.helpRow, nil, "popup reopened")
ex.requestHelp()
helpMenu:update(1 / 60)
T.eq(helpMenu.helpRow, nil, "START/P while open closes the popup")

-- the popup follows the cursor and draws over the list untouched
helpMenu.index = 3
ex.requestHelp()
helpMenu:update(1 / 60)
T.neq(helpMenu.helpRow, nil, "popup for the moved cursor")
T.eq(helpMenu.helpRow.id, "repel", "the popup follows the cursor")
helpMenu:draw()
T.eq(helpMenu.index, 3, "drawing the popup leaves the cursor alone")
pressed.b = true
helpMenu:update(1 / 60)
pressed.b = nil
T.eq(helpMenu.helpRow, nil, "popup closed again")

run.release()
T.finish("qol_toggles")
