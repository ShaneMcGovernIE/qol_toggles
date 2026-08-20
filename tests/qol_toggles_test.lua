-- Standalone: luajit mods/qol_toggles/tests/qol_toggles_test.lua
-- Loads the mod through the real headless loader and asserts the TOGGLES
-- submenu rows, the poison 1-HP clamp, the capture full-heal, and the
-- infinite-repel hook.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
local Game = require("src.core.Game")
local vanillaGamepadDispatch = Game.gamepadpressed
-- captured before the mod loads so the suite can assert the INSTANT TEXT
-- wrap is installed over the shared TextBox typewriter
local TextBoxModule = require("src.render.TextBox")
local vanillaTextBoxUpdate = TextBoxModule.update
Data:load()
-- the ROM-derived cache has no FIX_* species or moves, but this suite
-- builds real mons through Pokemon.new(Data, "FIXMON_A", ...): register
-- the fixture rows so those constructions resolve
do
  local fixture = require("tests.fixture_data").load()
  for id, def in pairs(fixture.pokemon) do Data.pokemon[id] = def end
  for id, def in pairs(fixture.moves) do Data.moves[id] = def end
end
-- the headless loader never boots Game:load, so the stack the mod's UI
-- seams read (menuIsTop, battleTop, the dialogue pushes) is minted here
local StateStack = require("src.core.StateStack")
Game.stack = setmetatable({ states = {} }, { __index = StateStack })
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

-- Pass the repository root as the first argument when the suite is launched
-- outside the engine checkout.  Keeping the test runner free of environment
-- lookups
-- makes the repository-wide sandbox audit match the shipped mod scan.
local loadRoot = arg and arg[1]

-- ------------------------------------------------ Gen 2 load gate
-- Runs FIRST: a fresh fixture dataset (not the shared Data) so the gen2
-- registries do not collide with the gen1 load below, and the mod's install
-- guards are cleared afterwards so the gen1 entry chunk re-runs in full.

do
  local GameVersion = require("src.core.GameVersion")
  local savedVersion = GameVersion.get and GameVersion.get()
  if GameVersion.set then GameVersion.set("gold") end
  local fresh = require("tests.modkit.fixtures").fresh()
  local run2 = T.sdk.loadMod(loadRoot and "." or "mods/qol_toggles",
    { data = fresh, generation = 2, root = loadRoot })
  T.eq(run2.mod and run2.mod.state, "loaded",
    "loads on gen 2: " .. tostring(run2.mod and run2.mod.skipReason))
  T.eq(#run2.errors, 0, "gen 2 load has no boot errors")
  local ex2 = run2.loader.exports.qol_toggles
  T.neq(ex2, nil, "gen 2 exports reachable")

  -- gen1-tagged toggles (S.S. Anne, Game Corner, dark caves, Dramatic Shape,
  -- last item, auto battler, mart, TM/HM surgery) drop out of the list on a
  -- Gold boot; the rest stay.  gen2 is passed explicitly because the gen1
  -- engine this suite runs on cannot reach the loader's gen2 flag.
  local state = {}
  local rows = ex2.toggleRows(function(k) return state[k] end,
                             function(k, v) state[k] = v end, true)
  local shown = {}
  for _, row in ipairs(rows) do shown[row.id] = true end
  for _, id in ipairs({ "quick_ssanne", "bulk_coins", "lights_on",
                        "mouse_cam_lock", "last_item", "auto_battler",
                        "free_great_ball", "bulk_mart",
                        "forgettable_hms", "exp_bar" }) do
    T.eq(shown[id], nil, "gen 2 hides the gen1-only toggle " .. id)
  end
  T.eq(shown["poison_save"], true, "gen 2 keeps POISON SAVE")
  T.eq(shown["always_catch"], true, "gen 2 keeps ALWAYS CATCH")
  T.eq(shown["map_location"], true, "gen 2 keeps MAP LOCATION")
  T.eq(shown["rename"], true, "gen 2 keeps RENAME")
  T.eq(shown["modern_types"], true, "gen 2 keeps MODERN TYPES")
  T.eq(shown["exp_mult"], true, "gen 2 keeps EXP MULT")
  T.eq(shown["money_mult"], true, "gen 2 keeps MONEY MULT")
  T.eq(shown["quick_nurse"], true, "gen 2 keeps QUICK NURSE")
  T.eq(shown["unlimited_tms"], true, "gen 2 keeps UNLIMITED TMs")
  T.eq(shown["party_scroll"], true, "gen 2 keeps PARTY SCROLL")
  T.eq(shown["instant_text"], true, "gen 2 keeps INSTANT TEXT")
  T.eq(shown["hold_to_scroll"], true, "gen 2 keeps HOLD TO SCROLL")
  T.eq(shown["anim_skip"], true, "gen 2 keeps ANIM SKIP")
  T.eq(ex2.visibleCount(true), #rows,
    "gen 2 visible toggle count matches the shown rows")
  T.eq(ex2.enabledCount(function() return true end, true), #rows,
    "gen 2 enabled count matches the shown rows")
  T.neq(ex2.cardLabelLines, nil, "gen 2 exposes card label wrapping")
  if ex2.cardLabelLines then
    local Font = require("src.render.Font")
    for _, row in ipairs(rows) do
      local lines = ex2.cardLabelLines(row.label)
      T.check(#lines >= 1 and #lines <= 3,
              "gen 2 card label fits three lines (" .. row.id .. ")")
      for i, line in ipairs(lines) do
        T.check(Font.width(line) <= 64
                  or (row.cardTickers and row.cardTickers[i] ~= nil),
                "gen 2 card line fits or ticks (" .. row.id .. ": "
                  .. line .. ")")
      end
    end
  end

  local species = next(fresh.pokemon)
  local g2mon = { species = species, level = 10, statExp = {} }
  local g2stats = ex2.perfectDVs(g2mon, fresh)
  T.eq(g2mon.maxHp, g2stats.hp,
    "gen 2 perfect DVs refresh the mon's max HP")

  -- CATCH GIVES EXP (Gold): the gen 2 engine's Catching.attempt never
  -- receives a battle, so Battle:caught -- the only site that consults
  -- battle.catch_exp -- never runs and a capture pays no EXP.  The mod pays
  -- the award from pokemon.caught via Battle:awardExperience and routes the
  -- emitted events to the battle screen.  Assert the mod-side contract with
  -- a stub battle (the real src/battle/gen2/Battle is only on the engine's
  -- g2 branch, so it cannot be required here): toggle gate, the
  -- caughtHandled latch, and the event hand-off to the screen.
  local savedMods = Game.mods
  local savedStack = Game.stack
  local savedLoaderGame = run2.loader.game
  -- the gen 2 Game facade resolves through Loader:_game(); the headless
  -- gen 1 harness has no Game2 to inject, so point the loader at the real
  -- Game module for this block -- the facade then sees the bucket below
  run2.loader.game = Game
  Game.mods = run2.loader
  run2.loader.modOptions = run2.loader.modOptions or {}
  run2.loader.modOptions.qol_toggles = run2.loader.modOptions.qol_toggles or {}
  local g2bucket = run2.loader.modOptions.qol_toggles

  -- PERFECT DVS GIFTS (Gold): Gold has no give-mon seam of its own, so the
  -- givepoke script.command row arms the latch and the wrapped Mon.new
  -- consumes it.  Drive the same hook the VM raises for every command: the
  -- vanilla here plays runCmd's givepoke arm (givePokeMon -> Mon.new), and
  -- the wrapped constructor must have applied max DVs to the gift.
  g2bucket.perfect_dvs = true
  do
    local Mon = require("src.battle.gen2.Mon")
    local made
    Runtime.call("script.command", function()
      made = Mon.new(fresh, species, 10, {})
      return nil
    end, { vm = {} }, "givepoke", {}, {})
    T.neq(made, nil, "givepoke creates a mon")
    T.eq(made.dvs.attack, 15, "gen 2 gift mon gets max DVs (attack)")
    T.eq(made.dvs.defense, 15, "gen 2 gift mon gets max DVs (defense)")
    T.eq(made.dvs.speed, 15, "gen 2 gift mon gets max DVs (speed)")
    T.eq(made.hp, made.maxHp, "gen 2 gift mon is at full HP at its new max")
  end
  g2bucket.perfect_dvs = false
  do
    -- the rolled DVs are whatever Mon.new draws; OFF must leave them alone.
    -- Inject fixed DVs through opts (the constructor honors opts.dvs) so the
    -- assertion is deterministic: the gift keeps exactly those, not 15s.
    local Mon = require("src.battle.gen2.Mon")
    local made
    local rolled = { attack = 1, defense = 2, speed = 3, special = 4 }
    Runtime.call("script.command", function()
      made = Mon.new(fresh, species, 10, { dvs = rolled })
      return nil
    end, { vm = {} }, "givepoke", {}, {})
    for _, k in ipairs({ "attack", "defense", "speed", "special" }) do
      T.eq(made.dvs[k], rolled[k],
        "toggle OFF: gen 2 gift keeps its rolled DV (" .. k .. ")")
    end
  end

  local g2award = { times = 0, mon = nil }
  local g2screen = { pushed = {} }
  function g2screen:pushAll(events)
    for _, e in ipairs(events) do self.pushed[#self.pushed + 1] = e end
  end

  local mon = { name = "STUBBAT" }
  g2bucket.catch_exp = true
  do
    local battle = {
      events = {},
      awardExperience = function(self, mon2)
        g2award.times = g2award.times + 1
        g2award.mon = mon2
        self.events[#self.events + 1] =
          { kind = "experience", index = 1, amount = 10, text = "stub" }
      end,
    }
    g2screen.battle = battle
    Game.stack = { states = { g2screen } }
    T.eq(ex2.giveCatchExp(battle, mon), true,
      "CATCH GIVES EXP (Gold): the catch pays the faint award")
    T.eq(g2award.times, 1, "Gold catch calls awardExperience exactly once")
    T.eq(g2award.mon, mon, "Gold catch awards with the caught mon")
    T.eq(battle.caughtHandled, true, "Gold catch latches caughtHandled")
    T.eq(#g2screen.pushed, 1, "Gold catch routes the exp event to the screen")
    T.eq(ex2.giveCatchExp(battle, mon), false,
      "caughtHandled keeps a second call from paying twice")
  end

  g2bucket.catch_exp = false
  do
    local battle = {
      events = {},
      awardExperience = function(self, mon2)
        g2award.times = g2award.times + 1
        g2award.mon = mon2
        self.events[#self.events + 1] =
          { kind = "experience", index = 1, amount = 10, text = "stub" }
      end,
    }
    g2screen.battle = battle
    Game.stack = { states = { g2screen } }
    T.eq(ex2.giveCatchExp(battle, mon), false,
      "CATCH GIVES EXP (Gold): toggle OFF pays nothing")
    T.eq(g2award.times, 1, "Gold catch: no award when the toggle is OFF")
    T.eq(battle.caughtHandled, nil, "Gold catch: latch unset when OFF")
  end

  Game.stack = savedStack
  Game.mods = savedMods
  run2.loader.game = savedLoaderGame
  if ex2.clearInstallGuards then ex2.clearInstallGuards() end
  run2.release()
  if GameVersion.set then GameVersion.set(savedVersion or "red") end
end

-- ---------------------------- Gen2 persistence boundary (sandbox update)
-- The mod must not open the loader's raw filesystem.  Its setter uses the
-- public option/write path and mirrors the value through mod.storage when a
-- playthrough is available.  The memfs options.lua below still represents
-- the Gold namespace that the engine's writeOptions owns.

do
  local GameVersion = require("src.core.GameVersion")
  local SaveData = require("src.core.SaveData")
  local savedVersion = GameVersion.get and GameVersion.get()
  local savedMods = Game.mods
  local savedSave = Game.save
  local savedWriteOptions = Game.writeOptions
  if GameVersion.set then GameVersion.set("gold") end
  -- this (Gen 1) engine's GameVersion has no gold, so the mod's GEN2 flag
  -- resolves through Game.mods.generation -- mirror the real boot, where
  -- the loader is assigned before mods run
  Game.mods = { generation = 2 }
  -- Gold's engine carries src.core.Game2 / src.battle.gen2.* etc.; the
  -- GEN2 entry path monkey-patches them at load.  Stub the gold-only
  -- modules so the suite can boot the gold path headless (restored below).
  local goldStubs = {
    ["src.core.Game2"] = { consumeItem = function(self, itemId) return true end },
    ["src.battle.gen2.Catching"] = { attempt = function() return false, 0 end },
    ["src.battle.gen2.Mon"] = { stats = function() return {} end },
    ["src.world.gen2.World"] = {},
    ["src.world.gen2.StepEvents"] = {},
    ["src.world.gen2.Player"] = {},
    ["src.world.gen2.FieldMoves"] = {},
  }
  local savedPreloads = {}
  for k, v in pairs(goldStubs) do
    savedPreloads[k] = package.preload[k]
    package.preload[k] = function() return v end
  end
  local fresh = require("tests.modkit.fixtures").fresh()
  local run2 = T.sdk.loadMod(loadRoot and "." or "mods/qol_toggles",
    { data = fresh, generation = 2, root = loadRoot })
  T.eq(#run2.errors, 0, "gen 2 persistence load has no boot errors")
  local ex2 = run2.loader.exports.qol_toggles
  T.neq(ex2.set, nil, "gen 2 set() is exported")

  -- the live Gold bifurcation: the loader's top-level bucket holds the
  -- mod's stale writes (REPEL off) while the gold namespace holds the
  -- player's real flip (REPEL on)
  local fs = T.sdk.memfs({ ["options.lua"] = [==[
return {
  lastVersion = "red",
  mods = { qol_toggles = true },
  modOptions = {
    qol_toggles = { repel = false, remember_cursor = false },
  },
  gold = {
    battleStyle = "SET",
    modOptions = {
      qol_toggles = { repel = true },
    },
  },
}
]==] })
  run2.loader.fs = fs
  -- same live-game wiring the catch block above needs: the gen 2 Game
  -- facade resolves through Loader:_game(), which this headless gen 1
  -- harness never sets -- without it set() would bail on a nil Game.mods
  local savedLoaderGame = run2.loader.game
  run2.loader.game = Game
  Game.mods = run2.loader
  Game.save = {
    version = "gold",
    meta = { playthroughId = "qol-test" },
    options = {
      battleStyle = "SET",
      modOptions = { qol_toggles = { repel = true } },
    },
  }
  -- Gold's writeOptions persists save.options under the `gold` namespace,
  -- leaving the rest of options.lua (incl. the top-level bucket) intact
  Game.writeOptions = function()
    local opts = SaveData.loadOptions(fs) or {}
    opts.gold = Game.save.options
    SaveData.saveOptions(opts, fs)
  end

  ex2.set("repel", true)
  T.eq(run2.loader.modOptions.qol_toggles.repel, true,
    "set updates the live loader bucket")
  T.eq(Game.save.options.modOptions.qol_toggles.repel, true,
    "set mirrors into the gold save namespace")
  local disk = SaveData.loadOptions(fs)
  T.eq(disk.gold.modOptions.qol_toggles.repel, true,
    "set writes the gold bucket the engine reads at boot")
  T.eq(disk.gold.battleStyle, "SET",
    "set preserves the other gold keys")
  T.eq(disk.modOptions.qol_toggles.remember_cursor, false,
    "set preserves the other toggles")

  Game.mods = savedMods
  Game.save = savedSave
  Game.writeOptions = savedWriteOptions
  run2.loader.game = savedLoaderGame
  if ex2.clearInstallGuards then ex2.clearInstallGuards() end
  run2.release()
  if GameVersion.set then GameVersion.set(savedVersion or "red") end
  for k, v in pairs(savedPreloads) do package.preload[k] = v end
end

local run = T.sdk.loadMod(loadRoot and "." or "mods/qol_toggles",
  { data = Data, root = loadRoot })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local ex = run.loader.exports.qol_toggles
T.neq(ex, nil, "exports reachable")
T.neq(TextBoxModule.update, vanillaTextBoxUpdate,
  "INSTANT TEXT wraps the shared TextBox update")

-- the toggles read through Game.mods (the loader), which the headless
-- harness does not wire by itself
Game.mods = run.loader

-- Controller START belongs to the engine's dispatch path.  QoL's help
-- shortcut must never replace Game:gamepadpressed, or the overworld cannot
-- open StartMenu (notably with Gen1 Modern UI's StartMenu presenter).
T.eq(Game.gamepadpressed, vanillaGamepadDispatch,
  "QoL does not intercept controller dispatch")

-- ------------------------------------------- the auto-repel toast seam

-- Gen1 Modern UI's presentationStack disables the overworld presenter --
-- and every menu layered over it, StartMenu included -- when
-- OverworldState.draw stops being the released renderer.  The toast must
-- wrap the screen-space overlay pass (drawUI) additively and leave the
-- world draw's identity intact.
local OverworldState = require("src.world.OverworldController")
local vanillaDraw = OverworldState.draw
local vanillaDrawUI = OverworldState.drawUI

-- LIGHTS ON must use setMap's normal FLASH-lit path.  A setDark wrapper
-- reloads baked maps in RED++, so this stub makes that recursion observable
-- without constructing the full overworld renderer.
local vanillaSetMap = OverworldState.setMap
local mapEntries = 0
local flashLitDuringEntry
OverworldState.setMap = function(self, mapId)
  mapEntries = mapEntries + 1
  flashLitDuringEntry = Game.save.flashLit
  self.map = { id = mapId }
  self:setDark(not Game.save.flashLit)
end
local saveBeforeLightsTest = Game.save
local dataBeforeLightsTest = Game.data
Game.data = Data
local darkMapsBeforeLightsTest = Game.data.field.darkMaps
Game.save = { flashLit = nil }
-- The fixture data intentionally omits the production dark-map definition;
-- seed only this test map so the LIGHTS ON wrapper's dark-map branch runs.
Game.data.field.darkMaps = { maps = { "ROCK_TUNNEL_1F" } }
run.loader.modOptions = run.loader.modOptions or {}
run.loader.modOptions.qol_toggles = run.loader.modOptions.qol_toggles or {}
run.loader.modOptions.qol_toggles.lights_on = true
run.loader.events:emit("game.ready", { game = Game })
local overworldStub = {
  setDark = function(self, on) self.dark = on end,
}
OverworldState.setMap(overworldStub, "ROCK_TUNNEL_1F")
T.eq(mapEntries, 1, "LIGHTS ON enters a dark map without recursive setMap")
T.eq(flashLitDuringEntry, true,
  "LIGHTS ON borrows FLASH-lit state during dark map entry")
T.eq(overworldStub.dark, false, "LIGHTS ON leaves a dark map lit")
T.eq(Game.save.flashLit, nil, "LIGHTS ON restores the borrowed FLASH flag")
Game.save = saveBeforeLightsTest
Game.data.field.darkMaps = darkMapsBeforeLightsTest
Game.data = dataBeforeLightsTest
OverworldState.setMap = vanillaSetMap

T.eq(OverworldState.draw, vanillaDraw,
  "toast leaves OverworldState.draw identity untouched (modern UI presenter)")
T.neq(OverworldState.drawUI, vanillaDrawUI,
  "toast wraps OverworldState.drawUI additively")

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

T.eq(#rows, 44, "forty-four toggles in the submenu")
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
T.eq(rows[11].id, "exp_mult", "toggle 11: EXP multiplier")
T.eq(rows[11].label, "EXP MULT", "toggle 11: EXP MULT label")
T.eq(rows[11].cycle, true, "toggle 11: EXP MULT is a cycle row")
T.eq(rows[12].id, "money_mult", "toggle 12: money multiplier")
T.eq(rows[12].label, "MONEY MULT", "toggle 12: MONEY MULT label")
T.eq(rows[12].cycle, true, "toggle 12: MONEY MULT is a cycle row")
T.eq(rows[13].id, "catch_exp", "toggle 13: catch gives EXP")
T.eq(rows[14].id, "instant_flee", "toggle 14: instant flee")
T.eq(rows[15].id, "remember_cursor", "toggle 15: remember battle cursor")
T.eq(rows[16].id, "b_to_run", "toggle 16: quick flee")
T.eq(rows[16].label, "B FOR QUICK FLEE", "toggle 16: quick flee label")
T.eq(rows[17].id, "heal_map_change", "toggle 17: heal on map change")
T.eq(rows[18].id, "quick_ssanne", "toggle 18: quick S.S. Anne")
T.eq(rows[19].id, "last_item", "toggle 19: last item in battle")
T.eq(rows[20].id, "free_great_ball", "toggle 20: free Great Ball bonus")
T.eq(rows[21].id, "mouse_cam_lock", "toggle 21: lock Dramatic Shape's mouse camera")
T.eq(rows[22].id, "no_enc_dupes", "toggle 22: no encounter dupes")
T.eq(rows[23].id, "instant_fish", "toggle 23: instant fish")
T.eq(rows[24].id, "heal_battle", "toggle 24: heal after battle")
T.eq(rows[25].id, "turn_away_nurse", "toggle 25: turn away from the nurse")
T.eq(rows[26].id, "quick_nurse", "toggle 26: quick nurse")
T.eq(rows[26].label, "QUICK NURSE", "toggle 26: QUICK NURSE label")
T.eq(rows[27].id, "auto_repel", "toggle 27: auto-repel")
T.eq(rows[28].id, "bulk_mart", "toggle 28: bulk mart")
T.eq(rows[29].id, "bulk_coins", "toggle 29: bulk coins")
T.eq(rows[30].id, "lights_on", "toggle 30: lights on")
T.eq(rows[31].id, "remember_move", "toggle 31: remember move")
T.eq(rows[32].id, "keep_money", "toggle 32: keep money")
T.eq(rows[33].id, "auto_cut", "toggle 33: auto cut")
T.eq(rows[34].id, "run_hold_b", "toggle 34: run (hold B)")
T.eq(rows[35].id, "auto_battler", "toggle 35: Battle Palace auto battler")
T.eq(rows[36].id, "map_location", "toggle 36: map location toast")
T.eq(rows[37].id, "rename", "toggle 37: rename from the party menu")
T.eq(rows[38].id, "modern_types", "toggle 38: modern type chart")
T.eq(rows[39].id, "exp_bar", "toggle 39: battle EXP bar")
T.eq(rows[39].label, "EXP BAR", "toggle 39: EXP BAR label")
T.eq(rows[40].id, "party_scroll", "toggle 40: party scroll")
T.eq(rows[40].label, "PARTY SCROLL", "toggle 40: PARTY SCROLL label")
T.eq(rows[41].id, "instant_text", "toggle 41: instant text")
T.eq(rows[41].label, "INSTANT TEXT", "toggle 41: INSTANT TEXT label")
T.eq(rows[42].id, "hold_to_scroll", "toggle 42: hold to scroll")
T.eq(rows[42].label, "HOLD TO SCROLL", "toggle 42: HOLD TO SCROLL label")
T.eq(rows[43].id, "anim_skip", "toggle 43: anim skip")
T.eq(rows[43].label, "ANIM SKIP", "toggle 43: ANIM SKIP label")
T.eq(rows[44].id, "sand_free", "toggle 44: sand free")
T.eq(rows[44].label, "SAND FREE", "toggle 44: SAND FREE label")

-- ------------------------------------------------ the two-column card grid

T.neq(ex.cardLabelLines, nil, "card label wrapping is exported")
T.neq(ex.cardGeometry, nil, "card geometry is exported")
T.neq(ex.gridMove, nil, "card navigation is exported")
if ex.cardLabelLines and ex.cardGeometry and ex.gridMove then
  T.same(ex.cardLabelLines("FULL HEAL CATCH"), { "FULL", "HEAL", "CATCH" },
         "card labels wrap at the card width")
  T.same(ex.cardGeometry(1), { x = 0, y = 0, w = 10, h = 7 },
         "top-left card geometry")
  T.same(ex.cardGeometry(4), { x = 10, y = 7, w = 10, h = 7 },
         "bottom-right card geometry")
  T.eq(ex.gridMove(1, "right", 35), 2,
       "right moves across the top row")
  T.eq(ex.gridMove(1, "left", 35), 1,
       "left stops at the left card")
  T.eq(ex.gridMove(1, "down", 35), 3,
       "down moves to the bottom row")
  T.eq(ex.gridMove(3, "down", 35), 5,
       "down advances to the next page")
  T.eq(ex.gridMove(35, "down", 35), 36,
       "last page reaches CANCEL")
  T.eq(ex.gridMove(36, "up", 35), 35,
       "CANCEL moves to the final toggle")
  T.eq(ex.gridMove(36, "down", 35), 1,
       "CANCEL wraps to the first toggle")

  local Font = require("src.render.Font")
  for _, row in ipairs(rows) do
    T.neq(row.cardLines, nil, "row has card label lines (" .. row.id .. ")")
    if row.cardLines then
      T.check(#row.cardLines >= 1 and #row.cardLines <= 3,
              "card label fits three lines (" .. row.id .. ")")
      for i, line in ipairs(row.cardLines) do
        T.check(Font.width(line) <= 64
                  or (row.cardTickers and row.cardTickers[i] ~= nil),
                "card line fits or ticks (" .. row.id .. ": " .. line .. ")")
      end
    end
  end

  T.same(ex.cardLabelLines("BADGELESS MOVES"),
         { "BADGELESS", "MOVES" },
         "card labels keep an overlong word intact")
  local badgelessRow
  for _, row in ipairs(rows) do
    if row.id == "badgeless_moves" then badgelessRow = row end
  end
  T.neq(badgelessRow, nil, "BADGELESS MOVES row exists")
  if badgelessRow then
    T.neq(badgelessRow.cardTickers, nil,
          "toggle rows expose per-line card ticker metadata")
    if badgelessRow.cardTickers then
      T.eq(badgelessRow.cardLines[1], "BADGELESS",
           "the long word remains one card line")
      T.eq(badgelessRow.cardLines[2], "MOVES",
           "the following word remains its own card line")
      T.neq(badgelessRow.cardTickers[1], nil,
            "the overlong card line gets ticker metadata")
      T.eq(badgelessRow.cardTickers[2], nil,
           "the fitting card line stays static")
    end
  end
end

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
T.eq(ex.defaultFor("exp_mult"), false, "EXP MULT ships OFF")
T.eq(ex.defaultFor("money_mult"), false, "MONEY MULT ships OFF")
T.eq(ex.defaultFor("catch_exp"), false, "CATCH GIVES EXP ships OFF")
T.eq(ex.defaultFor("instant_flee"), false, "INSTANT FLEE ships OFF")
T.eq(ex.defaultFor("remember_cursor"), true, "REMEMBER CURSOR ships ON")
T.eq(ex.defaultFor("b_to_run"), false, "B FOR QUICK FLEE ships OFF")
T.eq(ex.defaultFor("heal_map_change"), false, "HEAL ON MAP CHANGE ships OFF")
T.eq(ex.defaultFor("quick_ssanne"), false, "QUICK S.S. ANNE ships OFF")
T.eq(ex.defaultFor("last_item"), false, "LAST ITEM (M) ships OFF")
T.eq(ex.defaultFor("free_great_ball"), false, "POKEBALL BONUS ships OFF")
T.eq(ex.defaultFor("mouse_cam_lock"), false, "MOUSE CAM LOCK ships OFF")
T.eq(ex.defaultFor("no_enc_dupes"), false, "NO ENCOUNTER DUPES ships OFF")
T.eq(ex.defaultFor("instant_fish"), false, "INSTANT FISH ships OFF")
T.eq(ex.defaultFor("heal_battle"), false, "HEAL AFTER BATTLE ships OFF")
T.eq(ex.defaultFor("turn_away_nurse"), false, "TURN AWAY (NURSE) ships OFF")
T.eq(ex.defaultFor("auto_repel"), true, "AUTO-REPEL ships ON")
T.eq(ex.defaultFor("bulk_mart"), false, "BULK MART ships OFF")
T.eq(ex.defaultFor("bulk_coins"), false, "BULK COINS ships OFF")
T.eq(ex.defaultFor("lights_on"), false, "LIGHTS ON ships OFF")
T.eq(ex.defaultFor("remember_move"), true, "REMEMBER MOVE ships ON")
T.eq(ex.defaultFor("keep_money"), false, "KEEP MONEY ships OFF")
T.eq(ex.defaultFor("auto_cut"), false, "AUTO CUT ships OFF")
T.eq(ex.defaultFor("run_hold_b"), false, "RUN (HOLD B) ships OFF")
T.eq(ex.defaultFor("auto_battler"), false, "AUTO BATTLER ships OFF")
T.eq(ex.defaultFor("map_location"), true, "MAP LOCATION ships ON")
T.eq(ex.defaultFor("rename"), true, "RENAME ships ON")
T.eq(ex.defaultFor("modern_types"), false, "MODERN TYPES ships OFF")
T.eq(ex.defaultFor("quick_nurse"), false, "QUICK NURSE ships OFF")
T.eq(ex.defaultFor("party_scroll"), true, "PARTY SCROLL ships ON")
T.eq(ex.defaultFor("instant_text"), false, "INSTANT TEXT ships OFF")
T.eq(ex.defaultFor("hold_to_scroll"), false, "HOLD TO SCROLL ships OFF")
T.eq(ex.defaultFor("anim_skip"), false, "ANIM SKIP ships OFF")
T.eq(ex.defaultFor("sand_free"), false, "SAND FREE ships OFF")
T.eq(ex.defaultFor("bogus"), false, "unknown keys default OFF")
-- ------------------------------------------------ HOLD TO SCROLL

-- holdNav is the shared hold-to-repeat helper the toggle drives the generic
-- Gen 1 Menu, both OPTIONS screens and the QOL TOGGLES submenu with.  It
-- never returns on the edge-press frame (the vanilla update moved already),
-- then repeats the held direction after `delay` held frames every `rate`,
-- and cancels on any A/B edge or when the direction releases.
local function holdInput()
  local held = {}
  local pressed
  return {
    edge = function(_, k) pressed = k end,
    setDown = function(_, k) held[k] = true end,
    setUp = function(_, k) held[k] = nil end,
    wasPressed = function(_, k)
      local v = pressed == k
      if v then pressed = nil end
      return v
    end,
    isDown = function(_, k) return held[k] == true end,
  }
end
do
  local menu = { items = { 1, 2, 3 }, index = 1 }
  local input = holdInput()
  input:edge("up")
  T.eq(ex.holdNav(menu, input), nil,
    "holdNav stays silent on the edge-press frame (vanilla already moved)")
  input:setDown("up")
  local fired
  for f = 1, 20 do
    fired = ex.holdNav(menu, input)
    if fired then break end
  end
  T.eq(fired, "up", "holdNav repeats a held Up after the hold delay")
  input:setUp("up")
  T.eq(ex.holdNav(menu, input), nil,
    "holdNav clears when the direction releases")
  input:setDown("down")
  input:edge("down")
  ex.holdNav(menu, input) -- arm the down hold on its edge frame
  input:edge("a")
  T.eq(ex.holdNav(menu, input), nil, "holdNav cancels on an A edge")
end

T.eq(ex.enabledCount(function(k) return state[k] end), 0, "stub state starts empty")

for i, r in ipairs(rows) do
  T.eq(r.value(), "OFF", "row " .. i .. " defaults OFF in a bare stub state")
  T.eq(r.step(), true, "row " .. i .. " steps")
  if r.cycle then
    T.eq(r.value(), "0x", "cycle row " .. i .. " advances to 0x")
    r.step() -- move on so the walk below lands back on OFF
    r.step()
    r.step()
    r.step()
  else
    T.eq(r.value(), "ON", "row " .. i .. " shows ON after the step")
  end
  T.eq(r.step(), true, "row " .. i .. " steps back")
  T.eq(r.value(), "OFF", "row " .. i .. " shows OFF again")
end
T.eq(ex.enabledCount(function(k) return state[k] end), 0, "stub state empty again")

-- ------------------------------------------------ MODERN TYPES

-- the modern-chart builder is pure: the same rows in the same order, only
-- the multipliers that differ swapped, and never any FAIRY rows
do
  local fixtureChart = {
    { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
    { attacker = "BUG", defender = "POISON", multiplier = 20 },
    { attacker = "POISON", defender = "BUG", multiplier = 20 },
    { attacker = "GHOST", defender = "PSYCHIC_TYPE", multiplier = 0 },
    { attacker = "GHOST", defender = "GHOST", multiplier = 20 },
    { attacker = "WATER", defender = "FIRE", multiplier = 20 },
  }
  local modern = ex.modernTypeChart(fixtureChart)
  T.check(#modern >= #fixtureChart, "modern chart keeps every row and adds missing modern matchups")
  T.eq(modern[1].multiplier, 0, "unchanged rows keep their multiplier")
  T.eq(modern[2].multiplier, 5, "BUG>POISON drops to resisted")
  T.eq(modern[3].multiplier, 10, "POISON>BUG drops to neutral")
  T.eq(modern[4].multiplier, 20, "GHOST>PSYCHIC becomes super effective")
  T.eq(modern[5].multiplier, 20, "GHOST>GHOST is unchanged")
  T.eq(modern[6].multiplier, 20, "WATER>FIRE is unchanged")
  local iceOnFireRow = nil
  for _, r in ipairs(modern) do
    if r.attacker == "ICE" and r.defender == "FIRE" then iceOnFireRow = r end
  end
  T.neq(iceOnFireRow, nil, "ICE>FIRE is present in modern chart")
  T.eq(iceOnFireRow and iceOnFireRow.multiplier, 5, "ICE>FIRE is 5 (resisted by Fire)")

  -- the Gen VI Steel change rides the same overrides: no-op rows on a Gen 1
  -- chart (no STEEL there), the real fix on a Gold chart
  local steel = ex.modernTypeChart({
    { attacker = "GHOST", defender = "STEEL", multiplier = 5 },
    { attacker = "DARK", defender = "STEEL", multiplier = 5 },
    { attacker = "FIRE", defender = "STEEL", multiplier = 20 },
  })
  local ghostSteel, darkSteel, fireSteel = nil, nil, nil
  for _, r in ipairs(steel) do
    if r.attacker == "GHOST" and r.defender == "STEEL" then ghostSteel = r end
    if r.attacker == "DARK" and r.defender == "STEEL" then darkSteel = r end
    if r.attacker == "FIRE" and r.defender == "STEEL" then fireSteel = r end
  end
  T.eq(ghostSteel and ghostSteel.multiplier, 10, "GHOST>STEEL becomes neutral")
  T.eq(darkSteel and darkSteel.multiplier, 10, "DARK>STEEL becomes neutral")
  T.eq(fireSteel and fireSteel.multiplier, 20, "FIRE>STEEL stays super effective")
end

-- the live chart follows the toggle: the engine's lookups move to the modern
-- numbers while ON and the vanilla chart is restored on OFF
do
  local TypeChart = require("src.battle.TypeChart")
  -- the harness leaves Game.data unset; point it at the real Data the way
  -- the LIGHTS ON test does, and hand it back afterwards
  local savedData = Game.data
  Game.data = Data
  local liveVanilla = {}
  for _, row in ipairs(Game.data.type_chart.matchups) do
    liveVanilla[#liveVanilla + 1] = { attacker = row.attacker,
      defender = row.defender, multiplier = row.multiplier }
  end
  T.eq(TypeChart.effectiveness("BUG", { "POISON" }), 20,
    "vanilla: BUG is super effective on POISON")
  T.eq(TypeChart.effectiveness("GHOST", { "PSYCHIC_TYPE" }), 0,
    "vanilla: GHOST is immune to PSYCHIC (the Gen 1 bug)")
  T.eq(TypeChart.effectiveness("ICE", { "FIRE" }), 10,
    "vanilla: ICE is neutral against FIRE in Gen 1")

  -- the toggle flips the chart through the exported setter (the same path
  -- the menu's step uses); Game.save / writeOptions stay out of the way so
  -- the persistence side-effects never touch the dev options file
  local savedSave, savedWrite = Game.save, Game.writeOptions
  Game.save, Game.writeOptions = nil, nil
  ex.set("modern_types", true)
  T.eq(run.loader.modOptions.qol_toggles.modern_types, true,
    "set persists the modern_types bucket")
  T.eq(TypeChart.effectiveness("BUG", { "POISON" }), 5,
    "modern: BUG is resisted by POISON")
  T.eq(TypeChart.effectiveness("POISON", { "BUG" }), 10,
    "modern: POISON is neutral on BUG")
  T.eq(TypeChart.effectiveness("GHOST", { "PSYCHIC_TYPE" }), 20,
    "modern: GHOST hits PSYCHIC super effectively")
  T.eq(TypeChart.effectiveness("ICE", { "FIRE" }), 5,
    "modern: FIRE resists ICE")
  T.same(TypeChart.rows("BUG", { "POISON" }), { 5 },
    "modern: TypeChart.rows mirrors the swapped multiplier")
  T.same(TypeChart.rows("ICE", { "FIRE" }), { 5 },
    "modern: TypeChart.rows includes ICE on FIRE at 5")

  ex.set("modern_types", false)
  T.eq(run.loader.modOptions.qol_toggles.modern_types, false,
    "set flips the bucket back")
  T.eq(TypeChart.effectiveness("BUG", { "POISON" }), 20,
    "off again: the vanilla BUG>POISON row is back")
  T.eq(TypeChart.effectiveness("GHOST", { "PSYCHIC_TYPE" }), 0,
    "off again: GHOST is immune to PSYCHIC once more")
  T.eq(TypeChart.effectiveness("ICE", { "FIRE" }), 10,
    "off again: ICE is neutral on FIRE once more")
  local liveAfter = Game.data.type_chart.matchups
  T.eq(#liveAfter, #liveVanilla, "the live chart regains its row count")
  for i, row in ipairs(liveAfter) do
    T.eq(row.attacker, liveVanilla[i].attacker,
      "row " .. i .. " attacker restored")
    T.eq(row.defender, liveVanilla[i].defender,
      "row " .. i .. " defender restored")
    T.eq(row.multiplier, liveVanilla[i].multiplier,
      "row " .. i .. " multiplier restored")
  end
  Game.save, Game.writeOptions = savedSave, savedWrite
  Game.data = savedData
end

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

do
  -- Gold's battle writes "poison"/"toxic" into mon.status (only "psn"/"tox"
  -- are older-save spellings): both must clamp or the POISON SAVE toggle
  -- does nothing on Gen 2.
  local poison = { species = "FIXMON_A", nickname = "Weedle", status = "poison", hp = 1 }
  local toxic = { species = "FIXMON_A", nickname = "Gloom", status = "toxic", hp = 1 }
  local sub = ex.poisonClamp({ poison, toxic }, 1)
  T.eq(#sub, 2, "Gold poison and toxic 1-HP mons both subside")
  T.eq(poison.hp, 1, "poison-status mon keeps 1 HP")
  T.eq(poison.status, nil, "poison status cleared")
  T.eq(toxic.hp, 1, "toxic-status mon keeps 1 HP")
  T.eq(toxic.status, nil, "toxic status cleared")
  T.eq(sub[1], poison, "the poison-status mon is returned")
  T.eq(sub[2], toxic, "the toxic-status mon is returned")
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

do
  -- the cart's four move slots cap a mon's field moves at four, so the
  -- phantom attach path trims to that total (the party-menu box cannot
  -- render more; the Gen 2 counterpart is the cap in submenuRows)
  local def = { learnset = {}, tmhm = { "FLY", "FLASH", "CUT", "SURF",
                                        "STRENGTH", "DIG" } }
  local mon = { species = "FIXMON_A", moves = { { id = "FIX_TACKLE" },
                                                { id = "FLY" } } }
  local added = ex.attachPhantomMoves(mon, def, {}, false)
  T.eq(#added, 3, "one known field move leaves three phantom slots")
  T.eq(#mon.moves, 5, "the moveset grows to four field rows plus tackle")
  T.eq(mon.moves[3].id, "FLASH", "the learnable HMs keep their front seats")
  ex.detachPhantomMoves(mon, added)
  mon.moves[3] = { id = "SURF" }
  added = ex.attachPhantomMoves(mon, def, {}, false)
  T.eq(#added, 2, "two known field moves leave two phantom slots")
  ex.detachPhantomMoves(mon, added)
end

-- ------------------------------------------------ FIELD MOVES ALL wrap

local bucket = run.loader.modOptions.qol_toggles
if not bucket then bucket = {}; run.loader.modOptions.qol_toggles = bucket end

-- The pure chooser and autoBattleAction seam are exercised here; the
-- engine's resolveTurn integration is pinned by the engine battle suite.

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

-- ------------------------------------------------ Gen 2 submenu wrap
-- Gold's PartyMenu builds the field-move submenu from mon.moves, so the
-- wrap installs on ui.party.submenu (GEN2 arm) and its body is exported
-- as submenuRows.  This suite drives the pure export directly because the
-- gen1 engine checkout this runs on has no gen2 modules: a real Gold load
-- of the mod would crash on require("src.core.Game2").

do
  -- canLearn reads Gen 2 learnsets too: levelMoves `{level, move}` rows and
  -- the flat level1Moves id list (Gen 1 only has learnset + tmhm).
  local def = { levelMoves = { { level = 5, move = "FLY" } },
                tmhm = { "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local learnable = ex.learnableFieldMoves(def, mon, { HM_FLY = 1 }, true)
  T.eq(#learnable, 2, "gen 2 levelMoves + tmhm qualify")
  T.eq(learnable[1], "FLY", "a levelMoves row move qualifies")
  T.eq(learnable[2], "DIG", "a tmhm move qualifies")

  local lvl1 = { level1Moves = { "FLY" } }
  T.eq(#ex.learnableFieldMoves(lvl1, mon, { HM_FLY = 1 }, true), 1,
    "a level1Moves entry qualifies")
  T.eq(ex.learnableFieldMoves(lvl1, mon, {}, true)[1], nil,
    "level1Moves FLY still respects the HM item gate")

  local none = { levelMoves = {}, level1Moves = {} }
  T.eq(#ex.learnableFieldMoves(none, mon, { HM_FLY = 1 }, true), 0,
    "a gen 2 def with no field moves gets nothing")
end

do
  -- the wrap body: a learnable-but-unknown FLY (levelMoves) and DIG (tmhm)
  -- get phantom rows in engine order before the fixed STATS option.
  local def = { levelMoves = { { level = 5, move = "FLY" } },
                tmhm = { "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local game = { data = { pokemon = { FIXFLYER = def },
                          moves = { FLY = { name = "FLY" },
                                    DIG = { name = "DIG" } } },
                 save = { inventory = { HM_FLY = 1 } } }
  local function freshItems()
    return { { label = "STATS" }, { label = "SWITCH" } }
  end
  local function vanilla(_, items) return items end

  bucket.field_moves_all = true
  bucket.badgeless_moves = false
  bucket.hm_item_required = true
  local rows = ex.submenuRows(vanilla, game, freshItems(), mon,
                              { battle = false })
  T.eq(#rows, 4, "gen 2 submenu: two phantom rows before STATS")
  T.eq(rows[1].id, "FLY", "FLY phantom is first")
  T.eq(rows[1].label, "FLY", "phantom label resolves from data.moves")
  T.eq(rows[1].fieldMove, true, "phantom rows are tagged fieldMove")
  T.eq(rows[2].id, "DIG", "DIG phantom follows FLY")
  T.eq(rows[3].label, "STATS", "STATS keeps its slot")
  T.eq(rows[4].label, "SWITCH", "SWITCH stays last")

  -- a known move never gets a phantom row
  local knowsFly = { species = "FIXFLYER",
                     moves = { { id = "FIX_TACKLE" }, { id = "FLY" } } }
  rows = ex.submenuRows(vanilla, game, freshItems(), knowsFly,
                        { battle = false })
  T.eq(#rows, 3, "a mon that knows FLY gets only the DIG phantom")
  T.eq(rows[1].id, "DIG", "the unknown move is still offered")
end

do
  -- gate: both toggles off, in battle, and eggs all stay vanilla
  local def = { levelMoves = { { level = 5, move = "FLY" } } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local game = { data = { pokemon = { FIXFLYER = def },
                          moves = { FLY = { name = "FLY" } } },
                 save = { inventory = { HM_FLY = 1 } } }
  local function freshItems()
    return { { label = "STATS" } }
  end
  local function vanilla(_, items) return items end

  bucket.field_moves_all = false
  bucket.badgeless_moves = false
  local rows = ex.submenuRows(vanilla, game, freshItems(), mon,
                              { battle = false })
  T.eq(#rows, 1, "both toggles off: no phantom rows")
  T.eq(rows[1].label, "STATS", "the vanilla list passes through")

  bucket.field_moves_all = true
  rows = ex.submenuRows(vanilla, game, freshItems(), mon, { battle = true })
  T.eq(#rows, 1, "in battle: no phantom rows")
  rows = ex.submenuRows(vanilla, game, freshItems(), mon, {})
  T.eq(#rows, 2, "a nil ctx.battle behaves like the party menu")
  rows = ex.submenuRows(vanilla, game, freshItems(),
                        { species = "FIXFLYER", isEgg = true },
                        { battle = false })
  T.eq(#rows, 1, "an egg gets no phantom rows")

  rows = ex.submenuRows(vanilla, game, freshItems(),
                        { species = "NOPE", moves = {} }, { battle = false })
  T.eq(#rows, 1, "a missing species def stays vanilla")
end

do
  -- HM ITEM REQUIRED gates the phantom HM slots exactly as on Gen 1
  local def = { levelMoves = { { level = 5, move = "FLY" } },
                tmhm = { "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local game = { data = { pokemon = { FIXFLYER = def },
                          moves = { FLY = { name = "FLY" },
                                    DIG = { name = "DIG" } } },
                 save = { inventory = {} } }
  local function freshItems()
    return { { label = "STATS" } }
  end
  local function vanilla(_, items) return items end

  bucket.field_moves_all = true
  bucket.hm_item_required = true
  local rows = ex.submenuRows(vanilla, game, freshItems(), mon,
                              { battle = false })
  T.eq(#rows, 2, "no HM_FLY held: only the item-less DIG phantom")
  T.eq(rows[1].id, "DIG", "DIG has no HM item, so it always shows")

  game.save.inventory.HM_FLY = 1
  rows = ex.submenuRows(vanilla, game, freshItems(), mon, { battle = false })
  T.eq(#rows, 3, "holding HM_FLY brings the FLY phantom back")
  T.eq(rows[1].id, "FLY", "FLY sits ahead of DIG once allowed")
  game.save.inventory.HM_FLY = nil

  bucket.hm_item_required = false
  rows = ex.submenuRows(vanilla, game, freshItems(), mon, { battle = false })
  T.eq(#rows, 3, "toggle OFF: the item gate lifts")
  bucket.hm_item_required = nil
  bucket.field_moves_all = false
end

do
  -- issue #10: Gold's MonSubmenu box caps at eight rows and sizes itself by
  -- the row count, so a mon that can learn more field moves than fit must
  -- not push rows off the top of the screen.  Phantom rows displace the
  -- CANCEL row first (the cart drops it whenever the list is full), then
  -- the tail of the learnable list is trimmed.
  local def = { tmhm = { "FLY", "FLASH", "CUT", "SURF", "STRENGTH", "DIG" } }
  local mon = { species = "FIXFLYER", moves = { { id = "FIX_TACKLE" } } }
  local game = { data = { pokemon = { FIXFLYER = def }, moves = {} },
                 save = { inventory = {} } }
  local function freshItems()
    return { { id = "STATS", label = "STATS" },
             { id = "SWITCH", label = "SWITCH" },
             { id = "MOVE", label = "MOVE" },
             { id = "ITEM", label = "ITEM" },
             { id = "CANCEL", label = "CANCEL" } }
  end
  local function vanilla(_, items) return items end

  bucket.field_moves_all = true
  bucket.hm_item_required = false
  local rows = ex.submenuRows(vanilla, game, freshItems(), mon,
                              { battle = false })
  T.eq(#rows, 8, "the submenu never exceeds the eight-row box")
  T.eq(rows[1].id, "FLY", "the first learnable field move keeps its seat")
  T.eq(rows[4].id, "SURF", "the fourth phantom fills the last field row")
  T.eq(rows[5].id, "STATS", "STATS still follows the phantom rows")
  T.eq(rows[8].id, "ITEM", "CANCEL is displaced; the box ends on ITEM")
  local hasCancel = false
  for _, row in ipairs(rows) do
    if row.id == "CANCEL" then hasCancel = true end
  end
  T.eq(hasCancel, false, "a full list has no CANCEL row (back out with B)")

  -- a shorter learnable list keeps its CANCEL row
  local few = { tmhm = { "FLY", "DIG" } }
  game.data.pokemon.FIXFLYER = few
  rows = ex.submenuRows(vanilla, game, freshItems(), mon, { battle = false })
  T.eq(#rows, 7, "two phantom rows join the five vanilla rows")
  T.eq(rows[7].id, "CANCEL", "CANCEL survives when the list is not full")
  bucket.hm_item_required = nil
  bucket.field_moves_all = false
end

-- ------------------------------------------- RENAME

do
  -- the wrap body: the RENAME row rides the ui.party.submenu chain on
  -- both generations (the same hook the phantom rows use on Gold), so the
  -- pure export drives the row building here.  A field submenu gets the
  -- row; battle submenus and eggs stay vanilla; OFF passes through.
  local mon = { species = "FIXMON_A", nickname = "SPARKY" }
  local game = { data = {}, stack = { push = function() end } }
  local function vanilla(_, items) return items end

  bucket.rename = true
  local function fieldItems()
    return { { label = "STATS" }, { label = "SWITCH" } }
  end
  -- the wrap mutates the list it is handed (the engine builds a fresh one
  -- per submenu open), so every call gets its own fixture
  local rows = ex.submenuRename(vanilla, game, fieldItems(), mon,
                                { battle = false })
  T.eq(#rows, 3, "RENAME appends to the Gen 1 field submenu")
  T.eq(rows[3].id, "RENAME", "the row id is RENAME")
  T.eq(rows[3].label, "RENAME", "the row label is RENAME")
  T.eq(rows[3].fieldMove, nil, "the RENAME row is not a field move")
  T.eq(rows[1].label, "STATS", "the vanilla rows keep their order")

  -- Gold's list carries CANCEL; RENAME slots in before it
  local function goldItems()
    return { { id = "STATS", label = "STATS" },
             { id = "SWITCH", label = "SWITCH" },
             { id = "MOVE", label = "MOVE" },
             { id = "ITEM", label = "ITEM" },
             { id = "CANCEL", label = "CANCEL" } }
  end
  rows = ex.submenuRename(vanilla, game, goldItems(), mon, { battle = false })
  T.eq(#rows, 6, "RENAME joins the five vanilla Gold rows")
  T.eq(rows[5].id, "RENAME", "RENAME sits before CANCEL")
  T.eq(rows[6].id, "CANCEL", "CANCEL stays last when there is room")

  -- the eight-row box: CANCEL drops first, then the last field-move row
  -- (a phantom first, since phantoms sit at the tail of the field run),
  -- so RENAME is always visible
  local function fullWithCancel()
    return { { id = "FLY", label = "FLY", fieldMove = true },
             { id = "DIG", label = "DIG", fieldMove = true },
             { id = "STRENGTH", label = "STRENGTH", fieldMove = true },
             { id = "STATS", label = "STATS" },
             { id = "SWITCH", label = "SWITCH" },
             { id = "MOVE", label = "MOVE" },
             { id = "ITEM", label = "ITEM" },
             { id = "CANCEL", label = "CANCEL" } }
  end
  rows = ex.submenuRename(vanilla, game, fullWithCancel(), mon,
                          { battle = false })
  T.eq(#rows, 8, "a full list drops CANCEL to make room")
  T.eq(rows[8].id, "RENAME", "RENAME ends the trimmed list")
  local hasCancel = false
  for _, row in ipairs(rows) do
    if row.id == "CANCEL" then hasCancel = true end
  end
  T.eq(hasCancel, false, "the full box has no CANCEL row (back out with B)")

  local function fullNoCancel()
    return { { id = "CUT", label = "CUT", fieldMove = true },
             { id = "FLY", label = "FLY", fieldMove = true },
             { id = "SURF", label = "SURF", fieldMove = true },
             { id = "STRENGTH", label = "STRENGTH", fieldMove = true },
             { id = "STATS", label = "STATS" },
             { id = "SWITCH", label = "SWITCH" },
             { id = "MOVE", label = "MOVE" },
             { id = "ITEM", label = "ITEM" } }
  end
  rows = ex.submenuRename(vanilla, game, fullNoCancel(), mon,
                          { battle = false })
  T.eq(#rows, 8, "the box never exceeds eight rows with RENAME")
  T.eq(rows[8].id, "RENAME", "the last field-move row gives up its seat")
  T.eq(rows[1].id, "CUT", "the remaining field moves keep their front seats")
  T.eq(rows[4].id, "STATS", "STATS follows the trimmed field run")

  -- gates: battle, eggs and the OFF toggle all pass the list through
  rows = ex.submenuRename(vanilla, game, fieldItems(), mon, { battle = true })
  T.eq(#rows, 2, "in battle: no RENAME row")
  local egg = { species = "FIXMON_A", isEgg = true }
  rows = ex.submenuRename(vanilla, game, fieldItems(), egg,
                          { battle = false })
  T.eq(#rows, 2, "an egg gets no RENAME row")
  bucket.rename = false
  rows = ex.submenuRename(vanilla, game, fieldItems(), mon,
                          { battle = false })
  T.eq(#rows, 2, "toggle OFF: the vanilla list passes through")
  bucket.rename = true

  -- the rename write: a typed name lands on mon.nickname; an empty or
  -- unchanged confirm keeps the current name (the Name Rater's rule)
  T.eq(ex.applyRename(mon, "BLAZE"), "BLAZE", "applyRename writes the name")
  T.eq(mon.nickname, "BLAZE", "the new nickname is set")
  T.eq(ex.applyRename(mon, ""), "BLAZE", "an empty entry keeps the name")
  T.eq(ex.applyRename(mon, "BLAZE"), "BLAZE",
    "a re-typed copy of the name keeps it")
  T.eq(ex.applyRename({ species = "FIXMON_A" }, "ASH"), "ASH",
    "an un-nicknamed mon gains its first nickname")

  -- the action: the row's onSelect opens the engine naming screen with
  -- the current nickname pre-filled (Gen 1: NICKNAME?, 10 letters), and
  -- Gold's arm hands the same write to World:renameMon
  local pushed
  local Screens = require("src.ui.Screens")
  local vanillaPush = Screens.push
  Screens.push = function(g, id, opts)
    pushed = { id = id, opts = opts }
    return { game = g }
  end
  local row = ex.submenuRename(vanilla, game, fieldItems(), mon,
                               { battle = false })[3]
  T.neq(row.onSelect, nil, "the RENAME row carries an action")
  row.onSelect(mon, game)
  T.neq(pushed, nil, "the naming screen is pushed")
  T.eq(pushed.id, "NamingScreen", "Gen 1 pushes the NamingScreen")
  T.eq(pushed.opts.title, "NICKNAME?", "the screen prompt")
  T.eq(pushed.opts.maxLen, 10, "the 10-letter nickname length")
  T.eq(pushed.opts.default, "BLAZE", "the current nickname pre-fills")
  pushed.opts.onDone("EMBER")
  T.eq(mon.nickname, "EMBER", "confirming applies the typed name")
  pushed.opts.onDone("")
  T.eq(mon.nickname, "EMBER", "an empty confirm keeps the name")
  Screens.push = vanillaPush

  -- Gold: the same action calls world:renameMon with a Name-Rater-shaped
  -- callback; the harness runs on the gen 1 engine, so the branch is
  -- driven with the explicit gen2 flag and a stub world
  local renamedWith, renameCallback
  local goldGame = { stack = { push = function() end },
                     world = { renameMon = function(world, m, onDone)
                       renamedWith = m
                       renameCallback = onDone
                     end } }
  T.eq(ex.openRename(mon, goldGame, true), true,
    "Gold: openRename hands off to world:renameMon")
  T.eq(renamedWith, mon, "the selected mon is the rename target")
  T.neq(renameCallback, nil, "the callback is wired")
  renameCallback("GOLDIE")
  T.eq(mon.nickname, "GOLDIE", "Gold: the typed name is applied")
  renameCallback("")
  T.eq(mon.nickname, "GOLDIE", "Gold: an empty entry keeps the name")
  renameCallback(nil)
  T.eq(mon.nickname, "GOLDIE", "Gold: B keeps the name")
  local worldless = { stack = { push = function() end } }
  T.eq(ex.openRename(mon, worldless, true), false,
    "Gold: no world, no rename")
  T.eq(ex.openRename(nil, goldGame, true), false,
    "no mon, no rename")

  -- the Gen 1 arm pushes the engine naming screen (driven above through
  -- the row action); without a stack there is nothing to push onto
  T.eq(ex.openRename(mon, { stack = nil }, false), false,
    "Gen 1: no stack, no rename")
  bucket.rename = nil
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

do
  -- engine builds v0.1.59..v0.1.63 ran the old ChoiceBox flow: the real
  -- MoveLearnMenu never sets selecting (nil), the forget list is live
  -- whenever the menu is top.  The wrap and forgetUpdate must treat nil
  -- as "forget list live" or the toggle silently dies there and the
  -- vanilla HM gate fires even with FORGETTABLE HMs on.
  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  local function press(btn)
    return { wasPressed = function(_, k) return k == btn end }
  end
  local pushes = 0
  local function oldEngineMenu(input)
    local m = setmetatable({
      game = { input = input,
               data = { moves = { FLY = { name = "FLY" },
                                  FIX_EMBER = { name = "FIX EMBER", pp = 15 } } },
               stack = { push = function() pushes = pushes + 1 end } },
      mon = { moves = { { id = "FLY", pp = 5 },
                        { id = "FIX_TACKLE", pp = 10 } } },
      newMoveId = "FIX_EMBER",
      index = 1,
      confirmAbandon = function() end,
      finish = function() end,
    }, { __index = MoveLearnMenu })
    m.selecting = nil
    return m
  end

  bucket.forgettable_hms = true
  pushes = 0
  local old = oldEngineMenu(press("a"))
  MoveLearnMenu.update(old, 1/60)
  T.eq(old.mon.moves[1].id, "FIX_EMBER",
       "old engine + toggle ON: the HM is forgotten")
  T.eq(pushes, 0, "old engine + toggle ON: no refusal textbox")

  bucket.forgettable_hms = false
  pushes = 0
  old = oldEngineMenu(press("a"))
  MoveLearnMenu.update(old, 1/60)
  T.eq(old.mon.moves[1].id, "FLY",
       "old engine + toggle OFF: no gate-free replacement (vanilla path)")
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

-- PERFECT DVS GIFTS: a scripted gift (the starter, the Celadon Eevee, a
-- Game Corner prize, a fossil) never fires pokemon.caught, so the latch
-- armed by pokemon.before_give must flow into the very next Pokemon.new.
-- Drive the exact engine seam: give_pokemon emits before_give, then calls
-- Pokemon.new synchronously.  The wrapped constructor consumes the latch
-- and applies max DVs, and the latch is one-shot (a plain build right
-- after is untouched, rolled through a fixed rng so the assertion is
-- deterministic).

do
  local Pokemon = require("src.pokemon.Pokemon")
  local giftDVs = bucket.perfect_dvs
  bucket.perfect_dvs = true
  run.loader.events:emit("pokemon.before_give",
    { ctx = {}, species = "FIXMON_A", level = 10 })
  local gift = Pokemon.new(Data, "FIXMON_A", 10)
  T.eq(gift.dvs.attack, 15, "gift mon gets max DVs (attack)")
  T.eq(gift.dvs.defense, 15, "gift mon gets max DVs (defense)")
  T.eq(gift.dvs.speed, 15, "gift mon gets max DVs (speed)")
  T.eq(gift.dvs.special, 15, "gift mon gets max DVs (special)")
  T.eq(gift.hp, gift.stats.hp, "gift mon is at full HP at its new max")
  -- the latch is one-shot: a plain build right after is untouched
  local plain = Pokemon.new(Data, "FIXMON_A", 10, function() return 0 end)
  T.eq(plain.dvs.attack, 0, "gift latch consumed: next mon keeps its roll")
  -- toggle OFF: no latch, gift keeps its roll too
  bucket.perfect_dvs = false
  run.loader.events:emit("pokemon.before_give",
    { ctx = {}, species = "FIXMON_A", level = 10 })
  local off = Pokemon.new(Data, "FIXMON_A", 10, function() return 0 end)
  T.eq(off.dvs.attack, 0, "toggle OFF: gift keeps its rolled DVs")
  bucket.perfect_dvs = giftDVs
end

-- ------------------------------------------------ EXP MULT / MONEY MULT

do
  -- the multiplier helpers are pure: normalize (legacy `true` = 2x),
  -- the value-box labels, the floor scaling, and the cycle walk
  T.eq(ex.normalizeMult(false), false, "OFF stays OFF")
  T.eq(ex.normalizeMult(nil), false, "unset reads OFF")
  T.eq(ex.normalizeMult(true), 2, "the legacy EXP x2 bucket reads 2x")
  T.eq(ex.normalizeMult(1.5), 1.5, "a number passes through")

  T.eq(ex.multLabel(false), "OFF", "label: OFF")
  T.eq(ex.multLabel(0), "0x", "label: 0x")
  T.eq(ex.multLabel(1.5), "1.5x", "label: 1.5x")
  T.eq(ex.multLabel(2), "2x", "label: 2x")
  T.eq(ex.multLabel(3), "3x", "label: 3x")
  T.eq(ex.multLabel(4), "4x", "label: 4x")
  T.eq(ex.multLabel(true), "2x", "label: legacy bucket shows 2x")

  T.eq(ex.scaleValue(100, false), 100, "OFF passes the amount through")
  T.eq(ex.scaleValue(100, 2), 200, "2x doubles")
  T.eq(ex.scaleValue(100, 1.5), 150, "1.5x scales evenly")
  T.eq(ex.scaleValue(7, 1.5), 10, "1.5x floors the fraction (7*1.5=10.5)")
  T.eq(ex.scaleValue(100, 0), 0, "0x earns nothing")
  T.eq(ex.scaleValue(100, 4), 400, "4x quadruples")
  T.eq(ex.scaleValue(nil, 2), 0, "a nil amount scales to 0")

  local cycle = { false, 0, 1.5, 2, 3, 4 }
  T.eq(ex.cycleStep(false, cycle), 0, "cycle: OFF -> 0x")
  T.eq(ex.cycleStep(0, cycle), 1.5, "cycle: 0x -> 1.5x")
  T.eq(ex.cycleStep(1.5, cycle), 2, "cycle: 1.5x -> 2x")
  T.eq(ex.cycleStep(2, cycle), 3, "cycle: 2x -> 3x")
  T.eq(ex.cycleStep(3, cycle), 4, "cycle: 3x -> 4x")
  T.eq(ex.cycleStep(4, cycle), false, "cycle: 4x wraps to OFF")
  T.eq(ex.cycleStep(true, cycle), 3, "cycle: the legacy bucket steps from 2x")
  T.eq(ex.cycleStep(999, cycle), false, "cycle: unknown values land on OFF")

  -- the money seams: the trainer proxy scales baseMoney only (other
  -- fields resolve through the real record), Pay Day scales / cancels,
  -- and the prize line is recognised so 0x can drop it
  local trainer = { baseMoney = 200, name = "YOUNGSTER" }
  local scaled = ex.scaleTrainer(trainer, 3)
  T.neq(scaled, trainer, "an active multiplier shadows the trainer")
  T.eq(scaled.baseMoney, 600, "the proxy carries the scaled base money")
  T.eq(scaled.name, "YOUNGSTER", "other fields resolve through the record")
  T.eq(trainer.baseMoney, 200, "the shared data record is untouched")
  T.eq(ex.scaleTrainer(trainer, false), trainer, "OFF passes the trainer through")
  T.eq(ex.scaleTrainer(trainer, 0).baseMoney, 0, "0x zeroes the prize base")
  local noMoney = { name = "ROCKET" }
  T.eq(ex.scaleTrainer(noMoney, 2), noMoney,
    "a trainer with no base money is untouched")

  T.eq(ex.scalePayDay(100, false), 100, "Pay Day passes through when OFF")
  T.eq(ex.scalePayDay(100, 1.5), 150, "Pay Day scales with the multiplier")
  T.eq(ex.scalePayDay(100, 0), nil, "0x cancels Pay Day entirely")
  T.eq(ex.scalePayDay(nil, 2), nil, "no Pay Day stays none")

  T.eq(ex.isPrizeLine("RED got ¥1200\nfor winning!"), true,
    "the victory prize line is recognised")
  T.eq(ex.isPrizeLine("RED picked up\n¥100!"), false,
    "the Pay Day line is not the prize line")
  T.eq(ex.isPrizeLine("RED got ¥500\nfor winning! Sent some to MOM!"), true,
    "the Gold prize line is recognised too")
  T.eq(ex.isPrizeLine(nil), false, "a nil line is not the prize line")

  -- the rows: A cycles the multiplier instead of flipping ON/OFF, and
  -- the stored value round-trips through the row's setter
  local multState = {}
  local multRows = ex.toggleRows(function(k) return multState[k] end,
                                 function(k, v) multState[k] = v end)
  local expRow = multRows[11]
  T.eq(expRow.value(), "OFF", "EXP MULT starts OFF")
  expRow.step()
  T.eq(multState.exp_mult, 0, "A stores 0x")
  T.eq(expRow.value(), "0x", "the value box shows 0x")
  expRow.step()
  T.eq(multState.exp_mult, 1.5, "A stores 1.5x")
  T.eq(expRow.value(), "1.5x", "the value box shows 1.5x")
  local moneyRow = multRows[12]
  T.eq(moneyRow.value(), "OFF", "MONEY MULT starts OFF")
  moneyRow.step()
  moneyRow.step()
  T.eq(multState.money_mult, 1.5, "MONEY MULT stores its own cycle")
  T.eq(moneyRow.value(), "1.5x", "MONEY MULT shows 1.5x")
end

do
  -- the exp.gain wrap scales the finished amount (the announcement text
  -- rides the same figure): 0x zeroes it, 1.5x floors, and the legacy
  -- `true` bucket still doubles
  local vanilla = function() return 100 end
  local function gain()
    return Runtime.call("exp.gain", vanilla, {})
  end
  bucket.exp_mult = 2
  T.eq(gain(), 200, "2x doubles the gain")
  bucket.exp_mult = 1.5
  T.eq(gain(), 150, "1.5x scales the gain")
  bucket.exp_mult = 3
  T.eq(gain(), 300, "3x triples the gain")
  bucket.exp_mult = 4
  T.eq(gain(), 400, "4x quadruples the gain")
  bucket.exp_mult = 0
  T.eq(gain(), 0, "0x earns no EXP")
  bucket.exp_mult = false
  T.eq(gain(), 100, "OFF passes through")
  bucket.exp_mult = true
  T.eq(gain(), 200, "the legacy EXP x2 bucket still doubles")
  bucket.exp_mult = nil
  T.eq(gain(), 100, "unset passes through (default OFF)")
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

-- ------------------------------------------------ B FOR QUICK FLEE

do
  local function battle(pressedB, over)
    over = over or {}
    local pressed = { b = pressedB or false }
    local input = { wasPressed = function(self, btn)
      return btn == "b" and pressed.b or false
    end }
    local b = {
      menuIndex = over.menuIndex or 2,
      phase = over.phase or "menu",
      demo = over.demo or false,
      safari = over.safari or false,
      ghost = over.ghost or false,
      tutorial = over.tutorial or false,
      contest = over.contest or false,
      kind = over.kind,
      trainer = over.trainer,
      spectating = over.spectating or false,
      menuLockedAction = over.locked and function() return true end or nil,
      game = { input = input },
      -- Gen 1 keeps the active mon on the screen as player.mon; Gold's
      -- screen keeps it on the battle model (battle.player) and has no
      -- .player of its own
      player = over.gen2 and nil or { mon = { hp = over.hp or 10 } },
      battle = over.gen2 and {
        player = { hp = over.hp or 10 }, trainer = over.trainer,
      } or nil,
    }
    return b
  end

  -- toggle ON + B at the menu root parks the cursor on RUN (index 4)
  local b = battle(true)
  T.eq(ex.menuBToRun(b, true), 4, "B at the menu root jumps to RUN")
  T.eq(b.menuIndex, 4, "menuIndex is 4 (RUN)")

  -- no B press: the cursor stays put
  local noB = battle(false, { menuIndex = 3 })
  T.eq(ex.menuBToRun(noB, true), 3, "no B press leaves the cursor")

  -- toggle OFF: even a B press is ignored
  local off = battle(true, { menuIndex = 2 })
  T.eq(ex.menuBToRun(off, false), 2, "toggle OFF ignores B")

  -- not the menu phase (move select backs out on B instead)
  local move = battle(true, { phase = "moveSelect", menuIndex = 1 })
  T.eq(ex.menuBToRun(move, true), 1, "move-select phase is untouched")

  -- excluded menus: demo, safari, link, spectating
  T.eq(ex.menuBToRun(battle(true, { demo = true }), true), 2,
    "demo battle is untouched")
  T.eq(ex.menuBToRun(battle(true, { safari = true }), true), 2,
    "safari battle is untouched")
  T.eq(ex.menuBToRun(battle(true, { kind = "link" }), true), 2,
    "link battle is untouched")
  T.eq(ex.menuBToRun(battle(true, { spectating = true }), true), 2,
    "spectated battle is untouched")

  -- trainer battles: RUN never escapes (both engines refuse it), so the
  -- shortcut is skipped; Gen 1 flags the screen (kind/trainer), Gold's
  -- battle model carries the trainer record
  T.eq(ex.menuBToRun(battle(true, { kind = "trainer" }), true), 2,
    "a Gen 1 trainer battle is untouched")
  T.eq(ex.menuBToRun(battle(true, { trainer = true }), true), 2,
    "a Gen 1 trainer record is untouched")
  T.eq(ex.menuBToRun(battle(true, { gen2 = true, trainer = true }), true), 2,
    "Gold's trainer battle model is untouched")

  -- a locked action (thrash/rage/recharge) keeps the real menu closed
  T.eq(ex.menuBToRun(battle(true, { locked = true }), true), 2,
    "a locked action is untouched")

  -- a fainted active mon opens the forced replacement screen, not RUN
  T.eq(ex.menuBToRun(battle(true, { hp = 0 }), true), 2,
    "a fainted active mon is untouched")

  -- Gold's screen shape (issue #11): the active mon lives on the battle
  -- model, and B still lands on RUN
  T.eq(ex.menuBToRun(battle(true, { gen2 = true }), true), 4,
    "Gold's battle-model player still jumps to RUN")
  T.eq(ex.menuBToRun(battle(true, { gen2 = true, hp = 0 }), true), 2,
    "a fainted Gold mon opens the forced replacement screen instead")
  T.eq(ex.menuBToRun(battle(true, { tutorial = true }), true), 2,
    "the Gold tutorial battle is untouched")
  T.eq(ex.menuBToRun(battle(true, { contest = true }), true), 2,
    "the Gold contest menu is untouched")

  -- a missing battle is a no-op
  T.eq(ex.menuBToRun(nil, true), nil, "a missing battle is a no-op")
end

-- ------------------------------------------------ TURN AWAY (NURSE)

do
  local player = { facing = "up" }
  T.eq(ex.turnAround(player), "down", "facing up flips to down")
  T.eq(player.facing, "down", "the player's facing is rewritten")
  T.eq(ex.turnAround({ facing = "down" }), "up", "facing down flips to up")
  T.eq(ex.turnAround({ facing = "left" }), "right", "facing left flips to right")
  T.eq(ex.turnAround({ facing = "right" }), "left", "facing right flips to left")
  T.eq(ex.turnAround(nil), nil, "no player is a no-op")
  T.eq(ex.turnAround({}), nil, "no facing is a no-op")
  T.eq(ex.turnAround({ facing = "north" }), "down",
    "an unknown facing falls back to down")
end

do
  -- Gen 1: the turn rides finishNurseHeal's farewell callback.  The suite
  -- emits game.ready once after the Gen 1 load (the HEAL ON MAP CHANGE
  -- install), which also installs this wrap; the overworld dialogue itself
  -- needs a booted game (its Game upvalue is set in OverworldState:enter),
  -- so the callback the wrap installs is driven through the pure
  -- afterNurseHeal export instead.
  local OW = require("src.world.OverworldController")
  T.neq(OW._qolTogglesTurnAwayInstalled, nil,
    "the nurse wrap installs on game.ready")
  T.eq(type(OW.finishNurseHeal), "function",
    "finishNurseHeal stays callable")
  Runtime.emit("game.ready", { game = Game })
  T.eq(type(OW.finishNurseHeal), "function",
    "a second game.ready is a guarded no-op")

  local player = { facing = "up" }
  local done = 0
  bucket.turn_away_nurse = true
  local callback = ex.afterNurseHeal(player, function() done = done + 1 end)
  callback()
  T.eq(player.facing, "down", "the player turns away after the heal")
  T.eq(done, 1, "the original onDone still runs")

  player.facing = "up"
  bucket.turn_away_nurse = false
  callback = ex.afterNurseHeal(player, function() done = done + 1 end)
  callback()
  T.eq(player.facing, "up", "toggle OFF leaves the player facing the nurse")
  T.eq(done, 2, "the original onDone runs regardless")
  bucket.turn_away_nurse = nil
end

-- ------------------------------------------------ QUICK NURSE

do
  -- Gen 1: the whole nurse interaction is replaced by quickNurse -- heal
  -- the party, remember this center as the last-heal point, turn the
  -- player away, finish.  The suite's game.ready emit above installed
  -- the wrap on the real OverworldState module; the pure export is
  -- driven here because the live dialogue needs a booted game.
  local OW = require("src.world.OverworldController")
  T.neq(OW._qolTogglesQuickNurseInstalled, nil,
    "the quick-nurse wrap installs on game.ready")
  T.eq(type(OW.nurseHeal), "function", "nurseHeal stays callable")

  local Pokemon = require("src.pokemon.Pokemon")
  local hurt = Pokemon.new(Data, "FIXMON_A", 10)
  hurt.hp = 1
  hurt.status = "PSN"
  hurt.moves[1].pp = 0
  local savedSave = Game.save
  Game.save = { party = { hurt }, usedPokecenter = false }
  local npc = { faced = false }
  function npc:facePlayer() self.faced = true end
  local ow = {
    map = { id = "VIRIDIAN_POKECENTER" },
    player = { cellX = 5, cellY = 6, facing = "up" },
    lastOutdoor = { id = "VIRIDIAN_CITY", x = 3, y = 3 },
  }
  local done = 0
  ex.quickNurse(ow, function() done = done + 1 end, npc)
  T.eq(done, 1, "the caller's onDone runs")
  T.eq(hurt.hp, hurt.stats.hp, "the party is fully healed")
  T.eq(hurt.status, nil, "status is cleared")
  T.eq(hurt.moves[1].pp, Data.moves[hurt.moves[1].id].pp, "PP is restored")
  T.eq(Game.save.usedPokecenter, true, "the center is marked used")
  T.eq(Game.save.lastHeal.map, "VIRIDIAN_POKECENTER",
    "the last-heal record names this center")
  T.eq(Game.save.lastHeal.x, 5, "the last-heal cell X")
  T.eq(Game.save.lastHeal.y, 6, "the last-heal cell Y")
  T.eq(Game.save.lastHeal.outdoor.id, "VIRIDIAN_CITY",
    "the outdoor anchor survives")
  T.eq(ow.player.facing, "down", "the player turns away automatically")
  T.eq(npc.faced, true, "the nurse turns to face the player")
  T.neq(ow.healAnim, nil, "healAnim structure is created")
  T.eq(ow.healAnim.balls, 1, "healAnim configures 1 Pokéball for party of 1")
  T.eq(ow.healAnim.visible, true, "healAnim is visible")

  -- a degenerate call (no live save / no overworld) still finishes
  local done2 = 0
  Game.save = nil
  ex.quickNurse({}, function() done2 = done2 + 1 end, nil)
  T.eq(done2, 1, "a degenerate call still finishes")
  Game.save = savedSave
end

do
  -- Gen 2: the nurse lookup replicates the engine's counter-doubled
  -- CheckFacingObject (nurses stand behind COLL_COUNTER tiles, so the
  -- facing cell is doubled) and matches the shared PokecenterNurseScript
  -- key.  The real gen2 Map/Permissions modules load headless; the world
  -- is a stub.
  local function stubWorld(npc, collision, opts)
    opts = opts or {}
    return {
      player = { cellX = 5, cellY = 6, facing = opts.facing or "up",
                 moving = opts.moving or false },
      vm = {},
      busy = function() return opts.busy or false end,
      map = { cellCollision = function() return collision end },
      npcAt = function() return npc end,
    }
  end
  local nurse = { def = { scriptKey = "PokecenterNurseScript", index = 7 } }
  local mart = { def = { scriptKey = "MartClerkScript" } }

  -- over a counter: the object two cells up is the nurse
  local w = stubWorld(nurse, 0x90)
  T.eq(ex.nurseAt(w), nurse, "the nurse behind the counter is found")
  -- no counter: the facing cell itself
  w = stubWorld(nurse, 0x00)
  T.eq(ex.nurseAt(w), nurse, "the nurse on the facing cell is found")
  -- other NPCs, empty cells, and guards all stay nil
  w = stubWorld(mart, 0x90)
  T.eq(ex.nurseAt(w), nil, "a mart clerk is not a nurse")
  w = stubWorld(nil, 0x90)
  T.eq(ex.nurseAt(w), nil, "no object is not a nurse")
  w = stubWorld(nurse, 0x90, { busy = true })
  T.eq(ex.nurseAt(w), nil, "a busy world is not interrupted")
  w = stubWorld(nurse, 0x90, { moving = true })
  T.eq(ex.nurseAt(w), nil, "a moving player is not interrupted")
  w = stubWorld(nurse, 0x90, { facing = "down" })
  T.eq(ex.nurseAt(w), nurse, "any facing resolves the doubled cell")
  T.eq(ex.nurseAt({}), nil, "a bare world is nil")
  T.eq(ex.nurseAt(nil), nil, "no world is nil")
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
  run.loader.modSave.qol_toggles = {}
  pushed = 0
  view.onStep(game, ow, 18, 30)
  T.check(pushed > 0, "first pass: the prompt shows once")
  T.eq(run.loader.modSave.qol_toggles.ssanne_prompted, true,
    "first pass: the prompted flag is stored in save data")

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

do
  local drawn = {}
  local fakeFont = {
    encode = function() return { 1, 2, 3 } end,
    advanceOf = function() return 8 end,
    drawCode = function(code) drawn[#drawn + 1] = code end,
  }
  ex.drawTickerLabel(fakeFont, "ignored", 4, 16, 0, 16)
  T.eq(#drawn, 1, "ticker omits glyphs that would cross the right edge")
  T.eq(drawn[1], 1, "ticker keeps the fully contained glyph")
end

-- exactly the long labels overflow their window: HEAL ON MAP CHANGE and
-- NO ENCOUNTER DUPES are 18 glyphs = 144px > 136, so they tick live;
-- every other label fits
for _, row in ipairs(rows) do
  local ticks = row.id == "heal_map_change" or row.id == "no_enc_dupes"
  if ticks then
    T.neq(row.ticker, nil, "the long label ticks (" .. row.label .. ")")
    T.check(row.ticker.overflow == 8,
            "it overflows by exactly 8px (" .. row.label .. ")")
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
  "quick_ssanne", "last_item", "free_great_ball", "mouse_cam_lock",
  "no_enc_dupes", "instant_fish", "heal_battle", "turn_away_nurse",
  "auto_repel",
  "bulk_mart", "bulk_coins", "lights_on", "remember_move", "keep_money",
  "auto_cut", "run_hold_b",
  "auto_battler", "map_location", "sand_free",
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

-- card renderer geometry: the submenu paints four 10x7 cards on the first
-- page, centers the card text, and keeps the page marker at the footer edge
do
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  local boxes, texts, codes = {}, {}, {}
  local savedBox = Font.drawBox
  local savedDraw = Font.draw
  local savedDrawCode = Font.drawCode
  Font.drawBox = function(x, y, w, h, fill)
    boxes[#boxes + 1] = { x = x, y = y, w = w, h = h }
    return savedBox(x, y, w, h, fill)
  end
  Font.draw = function(text, x, y)
    texts[#texts + 1] = { text = text, x = x, y = y }
    return savedDraw(text, x, y)
  end
  Font.drawCode = function(code, x, y)
    codes[#codes + 1] = { code = code, x = x, y = y }
    return savedDrawCode(code, x, y)
  end
  helpMenu.index = 1
  helpMenu.helpRow = nil
  helpMenu:draw()
  Font.drawBox = savedBox
  Font.draw = savedDraw
  Font.drawCode = savedDrawCode

  T.eq(#boxes, 4, "first page draws four cards")
  T.same(boxes[1], { x = 0, y = 0, w = 10, h = 7 },
         "top-left card is 10x7")
  T.same(boxes[2], { x = 10, y = 0, w = 10, h = 7 },
         "top-right card is 10x7")
  T.same(boxes[3], { x = 0, y = 7, w = 10, h = 7 },
         "bottom-left card is 10x7")
  T.same(boxes[4], { x = 10, y = 7, w = 10, h = 7 },
         "bottom-right card is 10x7")
  local function hasText(text, x, y)
    for _, drawn in ipairs(texts) do
      if drawn.text == text and drawn.x == x and drawn.y == y then
        return true
      end
    end
    return false
  end
  T.check(hasText("POISON", 16, 8),
          "card label lines are centered in the first card")
  T.check(hasText("ON", 32, 40),
          "card values are centered below the first label")
  local hasCursor, hasMore = false, false
  for _, drawn in ipairs(codes) do
    if drawn.code == Theme.cursor and drawn.x == 8 and drawn.y == 8 then
      hasCursor = true
    end
    if drawn.code == Theme.moreArrow and drawn.x == 144 and drawn.y == 128 then
      hasMore = true
    end
  end
  T.eq(hasCursor, true, "selected card draws the filled cursor")
  T.eq(hasMore, true, "first page draws the later-page marker")
  T.check(hasText("CANCEL", 56, 136),
          "CANCEL is centered on the footer")
end

-- an overflowing card line uses the card-local ticker window, not centered
-- text that can bleed through the border
do
  local Font = require("src.render.Font")
  local savedCardRows = helpMenu.rows
  helpMenu.rows = {
    {
      label = "BADGELESS MOVES",
      cardLines = { "BADGELESS", "MOVES" },
      cardTickers = { { overflow = 8 }, nil },
      tick = 0,
      value = function() return "OFF" end,
    },
  }
  helpMenu.index = 2 -- CANCEL, so the card itself has no cursor at y=8
  helpMenu:update(1)
  T.eq(helpMenu.rows[1].tick, 1,
       "card ticker rows advance their shared ticker clock")
  helpMenu.rows[1].tick = 0
  local tickerCodes = {}
  local savedCardDrawCode = Font.drawCode
  Font.drawCode = function(code, x, y)
    if y == 8 and x > 0 and x < 72 then
      tickerCodes[#tickerCodes + 1] = { code = code, x = x, y = y }
    end
    return savedCardDrawCode(code, x, y)
  end
  helpMenu:draw()
  Font.drawCode = savedCardDrawCode
  helpMenu.rows = savedCardRows
  helpMenu.index = 1
  T.eq(#tickerCodes, 8, "the long card line draws eight clipped glyphs")
  for _, drawn in ipairs(tickerCodes) do
    T.check(drawn.x >= 8 and drawn.x + 8 <= 72,
            "card ticker glyph stays inside the card interior")
  end
end

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

-- ------- two-column card navigation and activation

local savedPop = helpGame.stack.pop
local exitCalls = 0
helpGame.stack.pop = function() exitCalls = exitCalls + 1 end
helpMenu.index = 1
local firstBefore = helpMenu.rows[1].value()
pressed.right = true
helpMenu:update(1 / 60)
pressed.right = nil
T.eq(helpMenu.index, 2, "right selects the second card")
local secondBefore = helpMenu.rows[2].value()
pressed.a = true
helpMenu:update(1 / 60)
pressed.a = nil
T.neq(helpMenu.rows[2].value(), secondBefore, "A toggles the selected card")
helpMenu.rows[2].step() -- restore the setting changed by the test

pressed.left = true
helpMenu:update(1 / 60)
pressed.left = nil
T.eq(helpMenu.index, 1, "left selects the first card")
T.eq(helpMenu.rows[1].value(), firstBefore,
     "directional navigation does not toggle the card")

helpMenu.index = 1
pressed.down = true
helpMenu:update(1 / 60)
pressed.down = nil
T.eq(helpMenu.index, 3, "down moves to the bottom row")
pressed.down = true
helpMenu:update(1 / 60)
pressed.down = nil
T.eq(helpMenu.index, 5, "down advances to the next page")

helpMenu.index = #helpMenu.rows - 1
pressed.down = true
helpMenu:update(1 / 60)
pressed.down = nil
T.eq(helpMenu.index, #helpMenu.rows + 1,
     "down from the partial final page selects CANCEL")
pressed.up = true
helpMenu:update(1 / 60)
pressed.up = nil
T.eq(helpMenu.index, #helpMenu.rows,
     "up from CANCEL selects the final toggle")
helpMenu.index = #helpMenu.rows + 1
pressed.down = true
helpMenu:update(1 / 60)
pressed.down = nil
T.eq(helpMenu.index, 1, "down from CANCEL wraps to the first card")

helpMenu.index = 2
ex.requestHelp()
helpMenu:update(1 / 60)
T.eq(helpMenu.helpRow.id, "catch_heal",
     "help follows the selected card")
pressed.b = true
helpMenu:update(1 / 60)
pressed.b = nil
T.eq(helpMenu.helpRow, nil, "B closes the moved-card popup")

helpMenu.index = #helpMenu.rows + 1
pressed.a = true
helpMenu:update(1 / 60)
pressed.a = nil
T.eq(exitCalls, 1, "A on CANCEL exits the submenu")
helpMenu.index = 1
helpGame.stack.pop = savedPop

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
local Font = require("src.render.Font")
local savedFontDraw = Font.draw
local bodyYs = {}
love.graphics.setScissor = function(x, y, w, h)
  scissorCalls[#scissorCalls + 1] = { x = x, y = y, w = w, h = h }
end
Font.draw = function(text, x, y)
  if x == 16 and y >= 32 and y < 104 then bodyYs[#bodyYs + 1] = y end
  return savedFontDraw(text, x, y)
end
local tallHelp = "line one\nline two\nline three\nline four\n"
  .. "line five\nline six\nline seven\nline eight\nline nine"
helpMenu.helpRow = { label = "TALL", help = tallHelp }
helpMenu.helpTick = 2 -- mid-scroll (1.6s hold is over)
local savedRows = helpMenu.rows
helpMenu.rows = {}
helpMenu:draw()
helpMenu.rows = savedRows
Font.draw = savedFontDraw
love.graphics.setScissor = savedScissor
T.eq(#scissorCalls, 2, "the scroll path scissored and cleared")
T.eq(scissorCalls[1].x, 16, "scissor starts at the body text x")
T.eq(scissorCalls[1].y, 40, "scissor starts at the body text y")
T.eq(scissorCalls[1].w, 136, "scissor is one text column wide")
T.eq(scissorCalls[1].h, 56, "scissor is the seven-row body")
T.eq(scissorCalls[2].x, nil, "scissor was cleared")
T.check(bodyYs[1] < 40, "over-long help text scrolls upward inside the box")
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

-- ------- MOUSE CAM LOCK

-- installMouseCamLock wraps a BattleCam module's mouseOrbit / mousePitch
-- so the toggle can cut the mouse steering; a stub module drives it
-- headless (Dramatic Shape is not loaded here, so the game.ready listener
-- that resolves it is not exercised -- the export is the seam)
local cam = {
  _qolMouseCamLockInstalled = false,
  mouseOrbit = function(dx) return "orbit " .. dx end,
  mousePitch = function(dy) return "pitch " .. dy end,
}
ex.installMouseCamLock(cam)
T.eq(cam._qolMouseCamLockInstalled, true, "install tags the module once")
local orbitBefore = cam.mouseOrbit
ex.installMouseCamLock(cam)
T.eq(cam.mouseOrbit, orbitBefore, "install is idempotent")

-- ships OFF: mouse steering forwards untouched
bucket.mouse_cam_lock = false
T.eq(cam.mouseOrbit(3), "orbit 3", "unlocked: orbit forwards")
T.eq(cam.mousePitch(4), "pitch 4", "unlocked: pitch forwards")

-- ON: the mouse no longer moves the camera, and nothing reaches the vanilla
bucket.mouse_cam_lock = true
T.eq(cam.mouseOrbit(3), false, "locked: orbit is a no-op")
T.eq(cam.mousePitch(4), false, "locked: pitch is a no-op")

-- the gate is read live: flipping back restores steering with no reinstall
bucket.mouse_cam_lock = false
T.eq(cam.mouseOrbit(5), "orbit 5", "unlock after lock: orbit works again")
T.eq(cam.mousePitch(6), "pitch 6", "unlock after lock: pitch works again")
bucket.mouse_cam_lock = nil

-- ------- NO ENCOUNTER DUPES (avoidDupe: the encounter.roll re-roll loop)

do
  local calls = 0
  local enc = ex.avoidDupe(function()
    calls = calls + 1
    return { species = "PIDGEY", level = 3 }
  end, nil, 8)
  T.eq(enc.species, "PIDGEY", "the first encounter is never a dupe")
  T.eq(calls, 1, "no re-roll when there is nothing to avoid")
end

do
  local seq = { "PIDGEY", "RATTATA" }
  local i = 0
  local enc = ex.avoidDupe(function()
    i = i + 1
    return { species = seq[i], level = 3 }
  end, "PIDGEY", 8)
  T.eq(enc.species, "RATTATA", "a different species is accepted")
  T.eq(i, 2, "exactly one re-roll past the dupe")
end

do
  local i = 0
  local enc = ex.avoidDupe(function()
    i = i + 1
    return { species = "PIDGEY", level = 3 }
  end, "PIDGEY", 4)
  T.eq(enc.species, "PIDGEY", "a one-species pool gives up after the attempts")
  T.eq(i, 4, "best effort: exactly max attempts")
end

T.eq(ex.avoidDupe(function() return nil end, "PIDGEY", 3), nil,
     "a nil roll stays nil")

-- ------- INSTANT FISH (fishBite: uniform pick from the rod's group)

for i = 1, 20 do
  local bite = ex.fishBite({ { species = "GOLDEEN", level = 10 },
                             { species = "POLIWAG", level = 10 } })
  T.check(bite.species == "GOLDEEN" or bite.species == "POLIWAG",
          "a bite is always a member of the pool")
  T.eq(bite.level, 10, "the pool's level is kept")
end
T.eq(ex.fishBite({}), nil, "an empty pool has nothing to conjure")
T.eq(ex.fishBite(nil), nil, "a nil pool has nothing to conjure")

-- ------- AUTO-REPEL (strongest repel in the bag, re-armed steps)

do
  local save = { inventory = { MAX_REPEL = 1, SUPER_REPEL = 2, REPEL = 1 } }
  T.eq(ex.autoRepel(save), "MAX_REPEL", "the strongest repel wins")
  local used = ex.applyAutoRepel(save)
  T.eq(used, "MAX_REPEL", "applyAutoRepel uses the strongest")
  T.eq(save.inventory.MAX_REPEL, nil, "the repel is consumed")
  T.eq(save.repelSteps, 250, "MAX_REPEL re-arms 250 steps")
end

do
  local save = { inventory = { REPEL = 3 } }
  T.eq(ex.applyAutoRepel(save), "REPEL", "plain REPEL when it is all there is")
  T.eq(save.repelSteps, 100, "REPEL re-arms 100 steps")
end

do
  local save = { inventory = {} }
  T.eq(ex.applyAutoRepel(save), nil, "no repel in the bag: nothing happens")
  T.eq(save.repelSteps, nil, "steps are untouched")
end

-- ------- AUTO-REPEL toast (the on-screen banner announcing the refill)

T.eq(ex.autoRepelToastText(100), nil, "no toast by default")
ex.setAutoRepelToast("USED MAX REPEL!", 100)
T.eq(ex.autoRepelToastText(100), "USED MAX REPEL!",
     "the toast shows while active")
T.eq(ex.autoRepelToastText(102.4), "USED MAX REPEL!",
     "still up inside the 2.5s window")
T.eq(ex.autoRepelToastText(102.5), nil, "expired toast clears")

-- the refill arms the toast with the item's display name
do
  local save = { inventory = { SUPER_REPEL = 1 } }
  local data = { items = { SUPER_REPEL = { name = "SUPER REPEL" } } }
  local used = ex.autoRepelToastFor(save, data, 200)
  T.eq(used, "SUPER_REPEL", "autoRepelToastFor consumes the refill")
  T.eq(save.repelSteps, 200, "and re-arms the steps")
  T.eq(ex.autoRepelToastText(200), "USED SUPER REPEL!",
       "the toast names the item")
  T.eq(ex.autoRepelToastText(203), nil, "and expires on its own")
end

do
  local save = { inventory = {} }
  T.eq(ex.autoRepelToastFor(save, nil, 300), nil,
       "no repel in the bag: no toast, nothing consumed")
  T.eq(ex.autoRepelToastText(300), nil, "and no toast is armed")
end

-- the pre-refill arms one extra step so vanilla's own decrement lands on
-- the item's exact count (and the wear-off box never fires)
do
  local save = { inventory = { REPEL = 1 } }
  local data = { items = { REPEL = { name = "REPEL" } } }
  local used = ex.refillForStep(save, data, 400)
  T.eq(used, "REPEL", "refillForStep consumes the repel")
  T.eq(save.repelSteps, 101, "one step is added for vanilla's decrement")
  save.repelSteps = save.repelSteps - 1 -- the vanilla onStepComplete decrement
  T.eq(save.repelSteps, 100, "vanilla's decrement lands on REPEL's 100")
  T.eq(ex.autoRepelToastText(400), "USED REPEL!", "the toast is armed")
end

do
  local save = { inventory = {} }
  T.eq(ex.refillForStep(save, nil, 500), nil, "no repel: refillForStep no-ops")
  T.eq(save.repelSteps, nil, "and steps are untouched")
end

-- ------- MAP LOCATION (the area-name toast, AUTO-REPEL banner style)

-- the display name: corrected name, town map name, label split, id
T.eq(ex.locationName(Data, "FIX_TOWN"), "FIX TOWN",
     "the town map name for a known town")
T.eq(ex.locationName(Data, "FIX_ROUTE"), "FIX ROUTE", "town map name 2")
T.eq(ex.locationName(
       { field = { townMap = { locations = {
           ROCK_TUNNEL_POKECENTER = { name = "ROCK TUNNEL" } } } } },
       "ROCK_TUNNEL_POKECENTER"),
     "ROCK TUNNEL POKECENTER",
     "the corrected name beats the town map's misleading entry")
T.eq(ex.locationName({}, "FIX_TOWN", { def = { label = "FixTown" } }),
     "FIX TOWN", "the map label split at case boundaries")
T.eq(ex.locationName({}, "MANSION_1F",
       { def = { label = "PokemonMansion1F" } }),
     "POKEMON MANSION 1F", "digit-letter boundaries split too")
T.eq(ex.locationName({}, "SOME_MAP"), "SOME MAP", "the id as a last resort")

-- the toast rides the AUTO-REPEL banner slot (same draw, same expiry)
T.eq(ex.autoRepelToastText(600), nil, "no location toast by default")
ex.setLocationToast("PALLET TOWN", 600)
T.eq(ex.autoRepelToastText(600), "PALLET TOWN",
     "the toast shows while active")
T.eq(ex.autoRepelToastText(602.5), nil, "and expires like AUTO-REPEL's")

-- short toast layout: centered static box without ticker overflow
do
  local toast = { text = "PALLET TOWN", start = 600, expire = 602.5, duration = 2.5 }
  local layout = ex.toastLayout(toast, 600)
  T.neq(layout, nil, "toastLayout returns layout")
  T.eq(layout.overflow, 0, "PALLET TOWN has 0 overflow")
  T.eq(layout.offset, 0, "offset is 0 (static)")
  T.eq(layout.w, 11 * 8 + 16, "box width is text + 16 padding")
  T.eq(layout.alpha, 1, "full alpha at start")

  local fading = ex.toastLayout(toast, 602.25)
  T.eq(fading.alpha, 0.5, "fades out over the last 0.5s")
end

-- long toast layout (ROCK TUNNEL POKECENTER): ticker scroll and extended duration
do
  ex.setLocationToast("ROCK TUNNEL POKECENTER", 700)
  T.eq(ex.autoRepelToastText(700), "ROCK TUNNEL POKECENTER", "long toast is active")
  T.neq(ex.autoRepelToastText(705), nil, "long toast duration is extended to allow reading full ticker")

  local toast = { text = "ROCK TUNNEL POKECENTER", start = 700, expire = 707, duration = 7 }
  local lStart = ex.toastLayout(toast, 700)
  T.neq(lStart, nil, "layout exists")
  T.eq(lStart.w, 144, "long toast box clamps to max 144px")
  T.eq(lStart.textW, 128, "interior text window is 128px")
  T.eq(lStart.overflow, 48, "22 chars (176px) has 48px overflow over 128px")
  T.eq(lStart.offset, 0, "holds at 0 during initial hold")

  -- at t = 3.1s (1.5s into 3.0s scroll): offset = -24px
  local lScroll = ex.toastLayout(toast, 703.1)
  T.eq(lScroll.offset, -24, "scrolls horizontally across time")

  -- at t = 5.0s (in end hold): offset = -48px
  local lEnd = ex.toastLayout(toast, 705.0)
  T.eq(lEnd.offset, -48, "holds at -48px at the end of the text")
end

-- ------- BULK COINS (the Game Corner clerk's quantity tiers)

do
  local opts = ex.coinOptions(0, false)
  T.eq(#opts, 1, "vanilla: only the 50-coin tier")
  T.eq(opts[1].qty, 50, "50 coins")
  T.eq(opts[1].cost, 1000, "50 coins cost ¥1000")
end

do
  local opts = ex.coinOptions(0, true)
  T.eq(#opts, 3, "bulk: 50 / 500 / 9999")
  T.eq(opts[1].qty, 50, "first tier is 50")
  T.eq(opts[2].qty, 500, "second tier is 500")
  T.eq(opts[2].cost, 10000, "500 coins cost ¥10000")
  T.eq(opts[3].qty, 9999, "third tier is 9999")
  T.eq(opts[3].cost, 199980, "9999 coins cost ¥199980")
end

do
  local opts = ex.coinOptions(500, true)
  T.eq(#opts, 2, "partial room drops the tiers that would overflow")
  T.eq(opts[1].qty, 50, "50 still fits")
  T.eq(opts[2].qty, 500, "500 fits (500 + 500 <= 9999)")
end

do
  local opts = ex.coinOptions(9990, true)
  T.eq(#opts, 0, "a near-full case offers nothing")
end

do
  local save = { money = 1000, coins = 0 }
  T.eq(ex.buyCoins(save, 50), true, "an affordable tier buys")
  T.eq(save.money, 0, "money deducted")
  T.eq(save.coins, 50, "coins granted")
end

do
  local save = { money = 500, coins = 0 }
  T.eq(ex.buyCoins(save, 50), false, "an unaffordable tier refuses")
  T.eq(save.money, 500, "money untouched")
  T.eq(save.coins, 0, "coins untouched")
end

do
  local save = { money = 199980, coins = 9950 }
  T.eq(ex.buyCoins(save, 9999), true, "a bulk buy grants coins")
  T.eq(save.coins, 9999, "clamped to the 9999 cap")
  T.eq(save.money, 0, "the full tier price is charged")
end

do
  local raw = "Welcome to ROCKET\nGAME CORNER!\fDo you need some\ngame coins?\fIt's ¥1000 for 50\ncoins. Would you\n\011like some?"
  T.eq(ex.clerkOffer(raw, false), raw, "vanilla keeps the extracted offer")
  T.eq(ex.clerkOffer(raw, true),
       "Welcome to ROCKET\nGAME CORNER!\fWould you like to\npurchase some\nCOINS?",
       "the bulk path keeps the welcome and re-asks")
  T.eq(ex.clerkOffer("no page break", true),
       "no page break\fWould you like to\npurchase some\nCOINS?",
       "a welcome-less line still gets the question")
end

-- ------- BULK COINS custom picker (the 4-digit quantity popout)

local pickerPressed = {}
local function pickerPress(p, k)
  pickerPressed[k] = true
  p:update(1 / 60)
  pickerPressed[k] = nil
end

local function newPicker(chosen)
  return ex.coinDigitPicker(
    { input = { wasPressed = function(_, k) return pickerPressed[k] == true end },
      stack = { pop = function() end } },
    { unitPrice = 20, onDone = chosen })
end

do
  local chosen
  local p = newPicker(function(q) chosen = q end)
  T.eq(getmetatable(p).isOpaque, true,
       "the picker is opaque (the list beneath is never drawn)")
  T.eq(p:value(), 1111, "the picker starts at 1111")
  pickerPress(p, "up")
  T.eq(p:value(), 2111, "up raises the active digit")
  pickerPress(p, "left")
  T.eq(p.box, 4, "left moves to the next box (wrapping)")
  pickerPress(p, "down")
  T.eq(p:value(), 2110, "down lowers the digit, 1 to 0")
  pickerPress(p, "down")
  T.eq(p:value(), 2119, "down wraps 0 to 9")
  pickerPress(p, "right")
  T.eq(p.box, 1, "right moves back across the boxes")
  pickerPress(p, "up") pickerPress(p, "up") pickerPress(p, "up")
  pickerPress(p, "up") pickerPress(p, "up") pickerPress(p, "up")
  pickerPress(p, "up") pickerPress(p, "up") pickerPress(p, "up")
  T.eq(p:value(), 1119, "nine ups wrap the digit 2 back to 1")
  p.digits = { 9, 9, 9, 9 }
  pickerPress(p, "up")
  T.eq(p.digits[1], 0, "up at 9 wraps to 0")
  p.digits = { 0, 0, 5, 0 }
  T.eq(p:value(), 50, "leading zeroes read as the plain amount")
  p.digits = { 0, 0, 0, 0 }
  pickerPress(p, "a")
  T.eq(chosen, nil, "A at zero is ignored")
  T.eq(p.box, 1, "the picker stays up at zero")
  p.digits = { 1, 2, 3, 4 }
  T.eq(p:value(), 1234, "the value reads the four digits")
  pickerPress(p, "a")
  T.eq(chosen, 1234, "A confirms with the value")
end

do
  local chosen, popped = nil, 0
  local p = ex.coinDigitPicker(
    { input = { wasPressed = function(_, k) return pickerPressed[k] == true end },
      stack = { pop = function() popped = popped + 1 end } },
    { onDone = function(q) chosen = q end })
  pickerPressed.a = true
  p:update(1 / 60)
  pickerPressed.a = nil
  T.eq(popped, 1, "confirm pops the picker")
  pickerPressed.b = true
  p:update(1 / 60)
  pickerPressed.b = nil
  T.eq(popped, 2, "cancel pops the picker")
  T.eq(chosen, nil, "B cancels with nil")
end

-- ------- BATTLE PALACE AUTO BATTLER

-- Gen 1 has no NATURE field.  The mod derives a stable representative
-- Battle Palace nature from the four Gen 1 DVs plus stat EXP, with the
-- Palace's exact probability tables applied after that mapping.
T.eq(ex.palaceNature({ dvs = { attack = 15, defense = 0, speed = 0, special = 0 },
                       statExp = {} }),
     "LONELY", "high Attack / low Defense maps to LONELY")
T.eq(ex.palaceNature({ dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
                       statExp = { speed = 65535 } }),
     "TIMID", "speed stat EXP participates in the mapping")
T.eq(ex.palaceNature({ dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
                       statExp = {} }),
     "HARDY", "an even build maps to a neutral Palace nature")

T.eq(ex.palaceCategory("LONELY", false, 19), "attack",
     "LONELY's high-HP roll can select Attack")
T.eq(ex.palaceCategory("LONELY", false, 20), "defense",
     "LONELY's high-HP roll crosses into Defense at 20")
T.eq(ex.palaceCategory("LONELY", false, 45), "support",
     "LONELY's high-HP roll selects Support after both thresholds")
T.eq(ex.palaceCategory("LONELY", true, 83), "attack",
     "LONELY's low-HP table has its own thresholds")
T.eq(ex.palaceCategory("LONELY", true, 84), "defense",
     "LONELY's low-HP table crosses into Defense at 84")

T.eq(ex.palaceMoveGroup({ id = "FIX_TACKLE", power = 40 }), "attack",
     "damaging moves are Attack moves")
T.eq(ex.palaceMoveGroup({ id = "USER_OR_SELECTED", power = 0,
                          target = "user_or_selected_user" }), "support",
     "zero-power user-or-selected moves are Support in Palace rules")
T.eq(ex.palaceMoveGroup({ id = "USER_OR_SELECTED", power = 40,
                          target = "user_or_selected_user" }), "attack",
     "powered user-or-selected moves are Attack in Palace rules")
T.eq(ex.palaceMoveGroup({ id = "SWORDS_DANCE", power = 0,
                         target = "user" }), "defense",
     "self-targeting moves are Defense moves")
T.eq(ex.palaceMoveGroup({ id = "SWORDS_DANCE", power = 0,
                          effect = "ATTACK_UP2_EFFECT" }), "defense",
     "the real Gen 1 data (no target field) still groups Swords Dance as Defense")
T.eq(ex.palaceMoveGroup({ id = "RECOVER", power = 0,
                          effect = "HEAL_EFFECT" }), "defense",
     "recovery moves are Defense like Emerald's MOVE_TARGET_USER")
T.eq(ex.palaceMoveGroup({ id = "HARDEN", power = 0,
                          effect = "DEFENSE_UP1_EFFECT" }), "defense",
     "stat-up effects are Defense")
T.eq(ex.palaceMoveGroup({ id = "DOUBLE_TEAM", power = 0,
                          effect = "EVASION_UP1_EFFECT" }), "defense",
     "evasion stat-ups are Defense")
T.eq(ex.palaceMoveGroup({ id = "TOXIC", power = 0,
                          target = "selected" }), "support",
     "non-damaging opponent-targeting moves are Support moves")
T.eq(ex.palaceMoveGroup({ id = "TOXIC", power = 0,
                          effect = "POISON_EFFECT" }), "support",
     "the real data shape keeps foe-targeting status as Support")
T.eq(ex.palaceMoveGroup({ id = "COUNTER", power = 0,
                          target = "selected" }), "support",
     "Counter remains Support like the Gen 3 Palace")
T.eq(ex.palaceMoveGroup({ id = "SONICBOOM", power = 1,
                          effect = "SPECIAL_DAMAGE_EFFECT" }), "attack",
     "fixed-damage moves remain Attack moves")

do
  local aiBattle = {
    data = {
      moves = {
        FIX_TACKLE = { id = "FIX_TACKLE", power = 40, type = "NORMAL" },
        FIX_EMBERISH = { id = "FIX_EMBERISH", power = 40, type = "FIRE" },
      },
      type_chart = {
        matchups = {},
        types = { NORMAL = { name = "NORMAL", category = "physical" },
                  FIRE = { name = "FIRE", category = "special" } },
      },
    },
    rng = function(a, b) return 1 end,
    enemyAIMods = {},
  }
  local aiBattler = {
    mon = { dvs = { attack = 15, defense = 0, speed = 0, special = 0 },
            statExp = {}, hp = 100, stats = { hp = 100 } },
    curMoves = { { id = "FIX_TACKLE", pp = 10 },
                 { id = "FIX_EMBERISH", pp = 10 } },
  }
  local target = { mon = { status = nil }, curTypes = { "GRASS" } }
  local picked = ex.palaceChooseMove(aiBattle, aiBattler, target,
                                     { nature = "LONELY", categoryRoll = 0 })
  T.eq(picked.id, "FIX_EMBERISH",
       "a selected category is scored by the normal AI before tie-breaking")
end

do
  local data = { moves = {
    FIX_TACKLE = { id = "FIX_TACKLE", power = 40, type = "NORMAL" },
    SWORDS_DANCE = { id = "SWORDS_DANCE", power = 0, type = "NORMAL",
                     target = "user", effect = "ATTACK_UP2_EFFECT" },
  } }
  local battle = { data = data, rng = function() return 0 end,
                   ruleset = { enemyUnlimitedPP = true } }
  local battler = {
    mon = { dvs = { attack = 15, defense = 0, speed = 0, special = 0 },
            statExp = {}, hp = 20, stats = { hp = 100 }, status = nil },
    curMoves = { { id = "FIX_TACKLE", pp = 10 },
                 { id = "SWORDS_DANCE", pp = 10 } },
  }
  local target = { mon = { status = nil }, curTypes = { "NORMAL" } }
  T.eq(ex.palaceChooseMove(battle, battler, target,
                           { nature = "LONELY", categoryRoll = 0,
                             moveRoll = 1 }).id, "FIX_TACKLE",
       "the auto battler chooses from the nature-selected category")
  battler.mon.hp = 10
  T.eq(ex.palaceChooseMove(battle, battler, target,
                           { nature = "LONELY", categoryRoll = 0,
                             moveRoll = 1 }).id, "FIX_TACKLE",
       "low HP still chooses a usable move from the selected category")
end

do
  -- the Defense category is reachable with real Gen 1 data (no target
  -- field): the stat-up move groups by effect and a Defense roll picks it
  -- instead of falling through to the empty-category fallback
  local data = { moves = {
    FIX_TACKLE = { id = "FIX_TACKLE", power = 40, type = "NORMAL" },
    SWORDS_DANCE = { id = "SWORDS_DANCE", power = 0, type = "NORMAL",
                     effect = "ATTACK_UP2_EFFECT" },
  } }
  local battle = { data = data, rng = function() return 0 end,
                   ruleset = { enemyUnlimitedPP = true } }
  local battler = {
    mon = { dvs = { attack = 0, defense = 15, speed = 0, special = 0 },
            statExp = {}, hp = 100, stats = { hp = 100 }, status = nil },
    curMoves = { { id = "FIX_TACKLE", pp = 10 },
                 { id = "SWORDS_DANCE", pp = 10 } },
  }
  -- BOLD (defense-heavy, thresholds 30/50): roll 40 lands in Defense
  local picked = ex.palaceChooseMove(battle, battler, nil,
    { nature = "BOLD", categoryRoll = 40, moveRoll = 1 })
  T.eq(picked.id, "SWORDS_DANCE",
       "a Defense roll picks the stat-up move grouped by effect")
end

do
  -- The live hook substitutes only the player's action; with the toggle OFF
  -- the existing enemy-action chain remains the source of truth.
  local vanilla = function() return { id = "FIX_SCRATCH", pp = 10 } end
  bucket.auto_battler = false
  local off = ex.autoBattleAction(nil, { id = "FIX_SCRATCH", pp = 10 })
  T.eq(off.id, "FIX_SCRATCH", "AUTO BATTLER OFF delegates to vanilla")
  bucket.auto_battler = true
  local liveData = { moves = {
    FIX_TACKLE = { id = "FIX_TACKLE", power = 40, type = "NORMAL" },
  } }
  local liveBattler = {
    mon = { dvs = { attack = 15, defense = 0, speed = 0, special = 0 },
            statExp = {}, hp = 100, stats = { hp = 100 } },
    curMoves = { { id = "FIX_TACKLE", pp = 10 } },
  }
  local liveBattle = {
    data = liveData, ruleset = { enemyUnlimitedPP = false }, rng = function(a, b)
      return a == 0 and 0 or 1
    end,
    player = liveBattler, enemy = {},
    fightLockedAction = function() return nil end,
  }
  local on = ex.autoBattleAction(liveBattle,
                                 { id = "FIX_SCRATCH", pp = 10 })
  T.eq(on.id, "FIX_TACKLE", "AUTO BATTLER ON supplies the player's action")
  T.eq(ex.autoBattleAction(liveBattle, { id = "FIX_SCRATCH", pp = 10 }).id,
       "FIX_TACKLE", "AUTO BATTLER uses the exported live seam")
  T.eq(ex.autoBattleShouldAct({ phase = "menu", player = liveBattler,
                                enemy = liveBattle.enemy }), true,
       "AUTO BATTLER takes over a free battle menu turn")
  T.eq(ex.autoBattleShouldAct({ phase = "moveSelect", player = liveBattler,
                                enemy = liveBattle.enemy }), false,
       "AUTO BATTLER does not take over the move-selection screen")
  local vanillaUpdate = function() return "vanilla" end
  local menuAction
  local menuBattle = {
    phase = "menu", _qolAutoBattleProbe = true, moveIndex = 1, data = liveData,
    rng = function(a, b) return a == 0 and 0 or 1 end,
    player = liveBattler, enemy = liveBattle.enemy,
    menuLockedAction = function() return nil end,
    fightLockedAction = function() return nil end,
    resolveTurn = function(_, action) menuAction = action end,
  }
  T.eq(ex.autoBattleUpdate(menuBattle, vanillaUpdate, 0), true,
       "the live menu seam consumes the update")
  T.eq(menuAction.id, "FIX_TACKLE",
       "the live menu seam submits the Palace action")
  bucket.auto_battler = false
  T.eq(ex.autoBattleUpdate(menuBattle, vanillaUpdate, 0), "vanilla",
       "the live seam delegates when AUTO BATTLER is OFF")
  T.eq(ex.autoBattleShouldAct({ phase = "menu", player = liveBattler,
                                enemy = liveBattle.enemy }), false,
       "AUTO BATTLER OFF leaves the battle menu alone")
  bucket.auto_battler = false
end

do
  local fallbackBattle = { data = { moves = {
    FIX_TACKLE = { id = "FIX_TACKLE", power = 40 },
    SWORDS_DANCE = { id = "SWORDS_DANCE", power = 0,
                     effect = "ATTACK_UP2_EFFECT", target = "user" },
  } }, rng = function(a, b) return a == 0 and 0 or 1 end }
  local fallbackMon = {
    mon = { dvs = { attack = 15, defense = 0, speed = 0, special = 0 },
            statExp = {}, hp = 100, stats = { hp = 100 } },
    curMoves = { { id = "FIX_TACKLE", pp = 10 } },
  }
  local picked = ex.palaceChooseMove(fallbackBattle, fallbackMon, nil,
                                     { nature = "LONELY", categoryRoll = 99,
                                       fallbackRoll = 1, fallbackChance = 0,
                                       randomWithinCategory = true,
                                       unlimited = false })
  T.eq(picked.id, "FIX_TACKLE", "an empty Palace category falls back to a move")
  local default = ex.palaceChooseMove(fallbackBattle, fallbackMon, nil,
                                      { nature = "LONELY", categoryRoll = 99,
                                        fallbackRoll = 1,
                                        randomWithinCategory = true,
                                        unlimited = false })
  T.eq(default.id, "FIX_TACKLE",
       "the QoL default falls back without the turn-wasting incapability roll")
  local skipped = ex.palaceChooseMove(fallbackBattle, fallbackMon, nil,
                                      { nature = "LONELY", categoryRoll = 99,
                                        fallbackRoll = 1, fallbackChance = 50,
                                        randomWithinCategory = true,
                                        unlimited = false })
  T.eq(skipped, nil,
       "an explicit fallbackChance >= 50 re-enables Emerald's skip")
  bucket.auto_battler = true
  local queued = {}
  local liveFallback = {
    data = fallbackBattle.data,
    player = fallbackMon,
    enemy = { mon = { status = nil }, curTypes = { "NORMAL" } },
    fightLockedAction = function() return nil end,
    rng = function(a, b) return a == 0 and 99 or 1 end,
    say = function(_, text) queued[#queued + 1] = text end,
  }
  fallbackMon.mon.hp = 100
  fallbackMon._qolPalaceLowHp = nil
  liveFallback.player.name = "FIXMON"
  local wait = ex.autoBattleAction(liveFallback,
                                    { id = "FIX_SCRATCH", pp = 10 })
  T.eq(wait.id, "FIX_TACKLE",
       "the live fallback uses a move instead of wasting the turn")
  T.eq(#queued, 0, "no incapability text for the QoL fallback")
  -- the incapability text is now unreachable from the live seam (a mon
  -- with no usable moves gets the vanilla Struggle action instead); it
  -- remains as the explicit-opt-in path (fallbackChance / fallbackIncapable)
  -- that the pure suite pins
  local emptyMon = {
    mon = { dvs = { attack = 15, defense = 0, speed = 0, special = 0 },
            statExp = {}, hp = 100, stats = { hp = 100 } },
    curMoves = { { id = "FIX_SCRATCH", pp = 0 } },
  }
  local emptyBattle = {
    data = fallbackBattle.data, player = emptyMon,
    enemy = { mon = { status = nil }, curTypes = { "NORMAL" } },
    fightLockedAction = function() return nil end,
    rng = function(a, b) return a == 0 and 99 or 1 end,
    say = function(_, text) queued[#queued + 1] = text end,
  }
  local none = ex.autoBattleAction(emptyBattle,
                                   { id = "FIX_SCRATCH", pp = 10 })
  T.eq(none.id, "STRUGGLE", "a mon with no usable moves gets Struggle")
  T.eq(none.struggle, true, "the Struggle action carries the engine's flag")
  T.eq(#queued, 0, "no incapability text on the Struggle path")
  -- the pure chooser hands back the same action shape
  local pure = ex.palaceChooseMove(emptyBattle, emptyMon, nil,
                                   { nature = "LONELY", categoryRoll = 99,
                                     randomWithinCategory = true,
                                     unlimited = false })
  T.eq(pure.id, "STRUGGLE", "palaceChooseMove returns the Struggle action")
  bucket.auto_battler = false
  T.eq(ex.autoBattleAction(liveFallback, { id = "FIX_SCRATCH", pp = 10 }).id,
       "FIX_SCRATCH", "turning AUTO BATTLER off preserves the action")
end

do
  -- The low-HP profile is latched until the battler is replaced, matching
  -- Emerald's palaceFlags behavior rather than recomputing from current HP.
  local latchBattle = { data = { moves = {
    FIX_TACKLE = { id = "FIX_TACKLE", power = 40 },
  } }, rng = function(a, b) return a == 0 and 0 or 1 end }
  local latchMon = {
    mon = { dvs = { attack = 0, defense = 0, speed = 0, special = 0 },
            statExp = {}, hp = 40, stats = { hp = 100 } },
    curMoves = { { id = "FIX_TACKLE", pp = 10 } },
  }
  ex.palaceChooseMove(latchBattle, latchMon, nil,
                      { nature = "LONELY", categoryRoll = 0,
                        randomWithinCategory = true, unlimited = false })
  T.eq(latchMon._qolPalaceLowHp, true, "low HP sets the Palace style latch")
  latchMon.mon.hp = 100
  ex.palaceChooseMove(latchBattle, latchMon, nil,
                      { nature = "LONELY", categoryRoll = 0,
                        randomWithinCategory = true, unlimited = false })
  T.eq(latchMon._qolPalaceLowHp, true,
       "healing does not clear the Palace style latch")
end

-- ------- SAND FREE (battle.enemy_action choke point)

bucket.sand_free = true
do
  local wild = { kind = "wild" }
  local gen1Sand = { id = "SAND_ATTACK", pp = 5 }
  local gen2Sand = "SAND_ATTACK"
  local scratch = { id = "FIX_SCRATCH", pp = 10 }

  T.eq(ex.sandFreeAction(scratch, wild).id, "FIX_SCRATCH",
       "a non-SAND-ATTACK pick passes through untouched")
  T.eq(ex.sandFreeAction(nil, wild), nil,
       "the Gen 2 forced/struggle nil passes through")
  T.eq(ex.sandFreeAction(gen1Sand, wild,
                           function() return scratch end).id,
       "FIX_SCRATCH",
       "a wild SAND-ATTACK roll is re-rolled to another move")
  T.eq(ex.sandFreeAction(gen2Sand, wild,
                           function() return "FIX_SCRATCH" end),
       "FIX_SCRATCH",
       "the Gen 2 bare-id shape re-rolls too")
  T.eq(ex.sandFreeAction(gen1Sand, wild,
                           function() return gen1Sand end).id,
       "STRUGGLE",
       "a wild mon that only knows SAND-ATTACK Struggles instead")
  local struggle = ex.sandFreeAction(gen1Sand, wild,
                                       function() return gen1Sand end)
  T.eq(struggle.struggle, true, "the Struggle fallback carries the flag")
  T.eq(ex.sandFreeAction(gen1Sand, { kind = "trainer" },
                           function() return scratch end).id,
       "SAND_ATTACK", "trainer battles keep their vanilla SAND-ATTACK")
  T.eq(ex.sandFreeAction(gen1Sand, { wild = true },
                           function() return scratch end).id,
       "FIX_SCRATCH", "the Gen 2 wild flag filters too")
  T.eq(ex.sandFreeAction(gen1Sand, { kind = "trainer" }),
       gen1Sand, "a trainer battle without a re-roll passes through")

  -- the installed wrap answers the engine's battle.enemy_action hook:
  -- the vanilla chain (next) is the enemy pick, the wrap re-rolls a wild
  -- SAND-ATTACK by calling it again
  local calls = 0
  local vanilla = function()
    calls = calls + 1
    return calls == 1 and gen1Sand or scratch
  end
  T.eq(Runtime.call("battle.enemy_action", vanilla, wild).id,
       "FIX_SCRATCH",
       "the live battle.enemy_action wrap re-rolls the wild pick")
  T.eq(calls, 2, "the re-roll called the vanilla chain twice")

  bucket.sand_free = false
  T.eq(ex.sandFreeAction(gen1Sand, wild,
                         function() return scratch end).id,
       "SAND_ATTACK", "toggle OFF: the vanilla pick passes through")
  calls = 0
  T.eq(Runtime.call("battle.enemy_action", vanilla, wild).id,
       "SAND_ATTACK", "toggle OFF: the live wrap leaves the pick alone")
  T.eq(calls, 1, "toggle OFF: the vanilla chain ran exactly once")
  bucket.sand_free = false
end

-- ------- RUN (HOLD B) (runFrames halves the per-step frame count)

bucket.run_hold_b = true
T.eq(ex.runFrames(16, { input = { isDown = function() return true end } }),
     8, "B held halves the step frames")
T.eq(ex.runFrames(16, { input = { isDown = function() return false end } }),
     16, "B released keeps walking speed")
T.eq(ex.runFrames(16, { onBike = true,
                        input = { isDown = function() return true end } }),
     16, "the bike keeps its own speed")
T.eq(ex.runFrames(16, { surfing = true,
                        input = { isDown = function() return true end } }),
     16, "surfing keeps its own speed")
T.eq(ex.runFrames(16, nil), 16, "a nil ctx never runs")
bucket.run_hold_b = nil
T.eq(ex.runFrames(16, { input = { isDown = function() return true end } }),
     16, "toggle OFF keeps walking speed")

-- ------- REMEMBER MOVE (applyMoveRemember parks moveIndex when OFF)

local mvBattle = { moveIndex = 3 }
T.eq(ex.applyMoveRemember(mvBattle, false), 1, "OFF parks the move cursor")
mvBattle.moveIndex = 3
T.eq(ex.applyMoveRemember(mvBattle, true), 3, "ON leaves the move cursor")
T.eq(ex.applyMoveRemember(nil, false), nil, "nil battle is safe")

-- ------- KEEP MONEY (snapshot before the halving, restore on blackout)

do
  local save = { money = 500 }
  ex.snapshotMoney(save)
  save.money = 250 -- the blackout halving already ran
  ex.keepMoneyRestore(save)
  T.eq(save.money, 500, "the pre-blackout money is restored")
  ex.keepMoneyRestore(save)
  T.eq(save.money, 500, "the snapshot is consumed, no double restore")
end

-- the world.blacked_out event wires the restore (the mod's own listener)
do
  local save = { money = 880 }
  ex.snapshotMoney(save)
  save.money = 440
  Runtime.emit("world.blacked_out", { save = save })
  T.eq(save.money, 880, "world.blacked_out restores the snapshot")
end

-- ------- HEAL AFTER BATTLE (battle.ended heals the battle's party)

do
  local Pokemon = require("src.pokemon.Pokemon")
  local mon = Pokemon.new(Data, "FIXMON_A", 10)
  mon.hp = 1
  mon.status = "PSN"
  bucket.heal_battle = true
  Runtime.emit("battle.ended",
               { battle = { game = { save = { party = { mon } } } } })
  bucket.heal_battle = nil
  T.eq(mon.hp, mon.stats.hp, "battle.ended heals the party's HP")
  T.eq(mon.status, nil, "status cleared too")
end

-- ------- BULK MART (the mart quantity box opens at 10)

do
  local QuantityBox = require("src.ui.QuantityBox")
  ex.setMartBuyOpen(true)
  bucket.bulk_mart = true
  local box = QuantityBox.new({}, { max = 99 })
  T.eq(box.qty, 10, "a mart BUY box opens at 10")
  local poor = QuantityBox.new({}, { max = 5 })
  T.eq(poor.qty, 5, "clamped by what the player can afford")
  ex.setMartBuyOpen(false)
  ex.setMartSellOpen(true)
  local sell = QuantityBox.new({}, { max = 99 })
  T.eq(sell.qty, 10, "a mart SELL box opens at 10 too")
  ex.setMartSellOpen(false)
  bucket.bulk_mart = nil
  local plain = QuantityBox.new({}, { max = 99 })
  T.eq(plain.qty, 1, "toggle OFF (or outside a mart) starts at 1")
end

-- ------- AUTO CUT (the tryMove wrap: a blocked step into a tree cuts it)

do
  Runtime.emit("game.ready", {})
  local Player = require("src.world.Player")
  local map = {
    id = "FIX_ROUTE",
    def = { tileset = "OVERWORLD" },
    inBounds = function() return true end,
    isWalkableCell = function() return false end,
    isWaterCell = function() return false end,
    cellTile = function() return 0x3d end,
    blockAt = function() return 0x10 end,
    setBlock = function() end,
    renderer = { rebuild = function() end },
  }
  local cutCalls = 0
  local ow = { map = map,
               tryCut = function(_, fx, fy)
                 cutCalls = cutCalls + 1
                 return true
               end }
  local savedStack = Game.stack
  Game.stack = { states = { ow }, push = function() end, pop = function() end }
  local player = {
    cellX = 2, cellY = 2, facing = "right", moving = false,
    inputLocked = false, turnArmed = false, turnTimer = 0,
    stepFrames = 16, bumpFrames = nil,
  }
  bucket.auto_cut = true
  local result = Player.tryMove(player, "right", map, {})
  T.eq(cutCalls, 1, "a blocked step into a tree calls tryCut")
  T.eq(result, nil, "the cut consumes the step")
  local wall = { map = map, tryCut = function() return false end }
  Game.stack = { states = { wall }, push = function() end, pop = function() end }
  result = Player.tryMove(player, "right", map, {})
  T.eq(result, "blocked", "a non-cuttable block stays blocked")
  bucket.auto_cut = nil
  cutCalls = 0
  result = Player.tryMove(player, "right", map, {})
  T.eq(cutCalls, 0, "toggle OFF never calls tryCut")
  T.eq(result, "blocked", "and the step stays blocked")
  Game.stack = savedStack
end

-- ------- BATTLE EXP BAR (Gen 2-style EXP bar in battle)

do
  T.eq(ex.EXP_BAR_X, 80, "EXP bar X coordinate is 80")
  T.eq(ex.EXP_BAR_RIGHT, 147, "EXP bar right coordinate is 147")
  T.eq(ex.EXP_BAR_WIDTH, 67, "EXP bar width is 67")
  T.eq(ex.EXP_BAR_Y, 89, "EXP bar Y coordinate is 89")
  T.eq(ex.EXP_BAR_HEIGHT, 2, "EXP bar height is 2")

  -- Growth rate EXP calculation formulas
  T.eq(ex.expForLevel("Fast", 1), 0, "Fast growth rate at level 1")
  T.eq(ex.expForLevel("Fast", 5), 100, "Fast growth rate at level 5 (4 * 125 / 5)")
  T.eq(ex.expForLevel("Fast", 10), 800, "Fast growth rate at level 10")
  T.eq(ex.expForLevel("Medium Fast", 1), 1, "Medium Fast growth rate at level 1")
  T.eq(ex.expForLevel("Medium Fast", 5), 125, "Medium Fast growth rate at level 5 (5^3)")
  T.eq(ex.expForLevel("Medium Fast", 10), 1000, "Medium Fast growth rate at level 10")
  T.eq(ex.expForLevel("Slow", 1), 1, "Slow growth rate at level 1")
  T.eq(ex.expForLevel("Slow", 5), 156, "Slow growth rate at level 5 (5 * 125 / 4)")
  T.eq(ex.expForLevel("Slow", 10), 1250, "Slow growth rate at level 10")
  T.eq(ex.expForLevel("Medium Slow", 1), 0, "Medium Slow growth rate at level 1")
  T.eq(ex.expForLevel("Medium Slow", 5), 135, "Medium Slow growth rate at level 5")

  -- Progress calculation
  local testData = {
    pokemon = {
      PIKACHU = { species = "PIKACHU", growthRate = "Medium Fast" },
    },
    constants = { levelCap = 100 },
  }
  local monLvl5 = { species = "PIKACHU", level = 5, exp = 125 }
  local prog, needed, frac, pixels = ex.expBarProgress(monLvl5, testData)
  T.eq(prog, 0, "0 progress EXP at start of level 5")
  T.eq(needed, 91, "91 EXP needed from level 5 (125) to level 6 (216)")
  T.eq(frac, 0, "0 fraction at start of level 5")
  T.eq(pixels, 0, "0 pixels at start of level 5")

  monLvl5.exp = 170
  prog, needed, frac, pixels = ex.expBarProgress(monLvl5, testData)
  T.eq(prog, 45, "45 progress EXP (170 - 125)")
  T.check(math.abs(frac - (45 / 91)) < 1e-6, "fraction matches 45/91")
  T.eq(pixels, math.floor(45 / 91 * 67), "33 pixels for ~49.4% progress")

  local monLvl100 = { species = "PIKACHU", level = 100, exp = 1000000 }
  prog, needed, frac, pixels = ex.expBarProgress(monLvl100, testData)
  T.eq(frac, 1.0, "level 100 is 100% full")
  T.eq(pixels, 67, "level 100 renders all 67 pixels")

  -- Target pixels for battle
  local stubBattle = {
    data = testData,
    player = { mon = monLvl5 },
  }
  T.eq(ex.expBarPixels(stubBattle), 33, "battle extracts player mon pixel fill")
  T.same(ex.expBarColor(stubBattle), { 0, 0, 0, 1 }, "default EXP bar color is black")

  -- Animation state updates
  ex.updateExpBar(stubBattle, 0.1)
  T.neq(stubBattle._qolExpBarState, nil, "updateExpBar creates state")
  T.eq(stubBattle._qolExpBarState.pixels, 33, "initializes at target pixels on first see")
  T.eq(stubBattle._qolExpBarState.level, 5, "initializes at current level")

  -- Mon gains EXP in battle
  monLvl5.exp = 200 -- target becomes math.floor(75 / 91 * 67) = 55
  local target = ex.expBarPixels(stubBattle)
  T.eq(target, 55, "new target is 55 pixels")
  stubBattle._qolExpBarState.pixels = 33
  ex.updateExpBar(stubBattle, 0.25) -- dt = 0.25s, speed = 40px/s => step = 10px
  T.eq(stubBattle._qolExpBarState.pixels, 43, "smoothly steps 10px towards target")

  -- Level up animation wrap
  monLvl5.level = 6
  monLvl5.exp = 220 -- level 6 min is 216, level 7 is 343
  stubBattle._qolExpBarState.pixels = 63
  stubBattle._qolExpBarState.level = 5
  ex.updateExpBar(stubBattle, 0.25) -- step = 10px, exceeds 67 -> wraps
  T.eq(stubBattle._qolExpBarState.pixels, 67, "clamps to 67 before level rollover")
  ex.updateExpBar(stubBattle, 0.1)
  T.eq(stubBattle._qolExpBarState.level, 6, "level rolls over to 6")
  T.eq(stubBattle._qolExpBarState.pixels, 0, "pixels reset to 0 for the new level")

  -- Switching mons resets immediately
  local switchedMon = { species = "PIKACHU", level = 10, exp = 1000 }
  stubBattle.player.mon = switchedMon
  ex.updateExpBar(stubBattle, 0.1)
  T.eq(stubBattle._qolExpBarState.mon, switchedMon, "switching mon updates state.mon")
  T.eq(stubBattle._qolExpBarState.level, 10, "switched mon level takes effect immediately")
  T.eq(stubBattle._qolExpBarState.pixels, 0, "switched mon target pixels initialized")

  -- Draw calls
  local drawnRect = nil
  local drawnColor = nil
  local mockLove = {
    graphics = {
      setShader = function() end,
      getColor = function() return 1, 1, 1, 1 end,
      setColor = function(r, g, b, a) drawnColor = { r, g, b, a } end,
      rectangle = function(mode, x, y, w, h)
        drawnRect = { mode = mode, x = x, y = y, w = w, h = h }
      end,
    },
  }
  local savedLove = _G.love
  _G.love = mockLove
  stubBattle._qolExpBarState.pixels = 35
  ex.drawExpBar(stubBattle)
  T.same(drawnColor, { 0, 0, 0, 1 }, "drawExpBar draws in black")
  T.same(drawnRect, { mode = "fill", x = 112, y = 89, w = 35, h = 2 },
         "drawExpBar renders fill from right to left at (112, 89, 35, 2)")
  _G.love = savedLove
end

-- ------------------------------------------------ PARTY SCROLL
do
  local Pokemon = require("src.pokemon.Pokemon")
  local mon1 = Pokemon.new(Data, "FIXMON_A", 10)
  local mon2 = Pokemon.new(Data, "FIXMON_B", 15)
  local mon3 = Pokemon.new(Data, "FIXMON_C", 20)
  local party = { mon1, mon2, mon3 }

  local screen = {
    game = { data = Data, save = { party = party } },
    mon = mon1,
    page = 1,
  }

  -- Up from 1 wraps to 3, preserving page 1
  local ok = ex.summarySwitchMon(screen, -1, party)
  T.eq(ok, true, "Up scrolls backward with wrapping")
  T.eq(screen.mon, mon3, "mon is now mon3")
  T.eq(screen.page, 1, "page is preserved as page 1")

  -- Down from 3 wraps to 1, preserving page 2
  screen.page = 2
  ok = ex.summarySwitchMon(screen, 1, party)
  T.eq(ok, true, "Down scrolls forward with wrapping")
  T.eq(screen.mon, mon1, "mon is now mon1")
  T.eq(screen.page, 2, "page is preserved as page 2")

  -- Down from 1 moves to 2
  ok = ex.summarySwitchMon(screen, 1, party)
  T.eq(ok, true, "Down moves to mon2")
  T.eq(screen.mon, mon2, "mon is now mon2")
  T.eq(screen.page, 2, "page remains page 2")

  -- Up from 2 moves to 1
  ok = ex.summarySwitchMon(screen, -1, party)
  T.eq(ok, true, "Up moves to mon1")
  T.eq(screen.mon, mon1, "mon is now mon1")
  T.eq(screen.page, 2, "page remains page 2")

  -- Degenerate cases
  T.eq(ex.summarySwitchMon(screen, 0, party), false, "delta 0 is rejected")
  T.eq(ex.summarySwitchMon(screen, 1, { mon1 }), false, "single mon party does not switch")
  T.eq(ex.summarySwitchMon(nil, 1, party), false, "nil screen is rejected")
  T.eq(ex.summarySwitchMon(screen, 1, nil), false, "nil party is rejected")
end

-- ------------------------------------------------ ANIM SKIP & AUDIO OVERLAP
do
  -- 1. Active sound tracking and force stopping
  local s1_stopped = false
  local s2_stopped = false
  local s1 = { stop = function() s1_stopped = true end }
  local s2 = { stop = function() s2_stopped = true end }

  ex.setActiveSound(s1)
  ex.setActiveSound(s2)
  ex.stopActiveSound()
  T.eq(s1_stopped, true, "stopActiveSound stops sound 1")
  T.eq(s2_stopped, true, "stopActiveSound stops sound 2")

  -- 2. Sound wrapping audio overlap behavior
  local Sound = require("src.core.Sound")
  local sound1_stopped = false
  local sound1 = { stop = function() sound1_stopped = true end, isPlaying = function() return true end }
  
  -- Toggle ON: playing a new sound force-stops the prior active sound
  ex.set("anim_skip", true)
  ex.setActiveSound(sound1)
  T.eq(sound1_stopped, false, "sound 1 not yet stopped")
  
  -- Simulate next sound playing via Sound.play
  Sound.play(Data, "Press_AB")
  T.eq(sound1_stopped, true, "anim_skip ON: playing next sound force-stops previous active sound")

  -- Toggle OFF: playing a sound does not force-stop previous active sound
  ex.set("anim_skip", false)
  local sound2_stopped = false
  local sound2 = { stop = function() sound2_stopped = true end }
  ex.setActiveSound(sound2)
  Sound.play(Data, "Press_AB")
  T.eq(sound2_stopped, false, "anim_skip OFF: previous sound is not force-stopped")

  -- 3. Battle animation skip on A-press
  local hitApplied = false
  local animFinished = false
  local animBattle = {
    game = {
      input = {
        wasPressed = function(_, k) return k == "a" end,
      },
    },
    animPlaying = true,
    animPlayer = {
      finish = function() animFinished = true end,
    },
    pendingHit = { target = {} },
    applyHitFx = function(_, hit) hitApplied = (hit ~= nil) end,
    resetPicFx = function() end,
    waitFrames = 15,
    fx = { shake = 10, flash = 5 },
  }

  local skipped = ex.skipAnimOrAudio(animBattle)
  T.eq(skipped, true, "skipAnimOrAudio skips active battle animation")
  T.eq(animBattle.animPlaying, false, "animPlaying set to false")
  T.eq(animFinished, true, "animPlayer finish invoked")
  T.eq(hitApplied, true, "pending hit effect applied")
  T.eq(animBattle.pendingHit, nil, "pendingHit cleared")
  T.eq(animBattle.waitFrames, 0, "waitFrames zeroed")
  T.eq(animBattle.fx.shake, nil, "screen shake cleared")
  T.eq(animBattle.fx.flash, nil, "screen flash cleared")

  -- 4. Waiting sound (cry / jingle / fanfare) skip on A-press
  local waitSoundStopped = false
  local cryBattle = {
    game = {
      input = {
        wasPressed = function(_, k) return k == "a" end,
      },
    },
    waitingSound = {
      stop = function() waitSoundStopped = true end,
    },
    waitFrames = 20,
  }

  skipped = ex.skipAnimOrAudio(cryBattle)
  T.eq(skipped, true, "skipAnimOrAudio skips waitingSound hold")
  T.eq(waitSoundStopped, true, "waitingSound force-stopped on A press")
  T.eq(cryBattle.waitingSound, nil, "waitingSound cleared")
  T.eq(cryBattle.waitFrames, 0, "waitFrames zeroed")

  -- 5. Battle message text and prompts fast-forward / advance on A-press
  local lineBegun = false
  local msgBattle = {
    game = {
      input = {
        wasPressed = function(_, k) return k == "a" end,
      },
    },
    phase = "messages",
    codes = { 0x41, 0x42, 0x43, 0x44 },
    shown = { { 0x41 } },
    charIndex = 1,
    charTimer = 2,
    msgPrompt = true,
    msgPromptWait = 3,
    msgPreWait = 3,
  }

  skipped = ex.skipAnimOrAudio(msgBattle)
  T.eq(skipped, true, "skipAnimOrAudio fast-forwards messages")
  T.eq(#msgBattle.shown[1], 4, "text codes filled immediately to end of line")
  T.eq(msgBattle.charTimer, 0, "charTimer reset")
  T.eq(msgBattle.msgPromptWait, 0, "msgPromptWait cleared")
  T.eq(msgBattle.msgPrompt, nil, "msgPrompt dismissed")

  -- 6. Overworld item get fanfare / TextBox skip on A-press
  local itemStopped = false
  local popped = false
  local onDoneCalled = false
  local itemBox = {
    game = {
      input = { wasPressed = function(_, k) return k == "a" end },
      stack = { pop = function() popped = true end },
    },
    done = true,
    auto = { wait = true },
    autoSrc = { stop = function() itemStopped = true end },
    onDone = function() onDoneCalled = true end,
  }

  skipped = ex.skipTextBox(itemBox)
  T.eq(skipped, true, "skipTextBox skips overworld item fanfare")
  T.eq(itemStopped, true, "item fanfare stopped on A-press")
  T.eq(itemBox.auto, nil, "itemBox.auto cleared")
  T.eq(popped, true, "itemBox popped from stack")
  T.eq(onDoneCalled, true, "itemBox onDone called")

  -- 7. Inactive / No A press degenerate checks
  local idleBattle = {
    game = {
      input = {
        wasPressed = function(_, k) return false end,
      },
    },
    animPlaying = true,
  }
  T.eq(ex.skipAnimOrAudio(idleBattle), false, "no A press does not skip")
  T.eq(idleBattle.animPlaying, true, "animPlaying untouched without A press")
  T.eq(ex.skipAnimOrAudio(nil), false, "nil battle rejected")
  T.eq(ex.skipTextBox(nil), false, "nil textbox rejected")
end

run.release()
T.finish("qol_toggles")


