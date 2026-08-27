-- Standalone: luajit mods/qol_toggles/tests/quick_nurse_gold_test.lua
-- Gold interaction regression: an A press over a counter-backed
-- PokecenterNurseScript must be claimed by QUICK NURSE before the VM starts
-- the vanilla dialogue script.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")
local GameVersion = require("src.core.GameVersion")
local World = require("src.world.gen2.World")
local NPC = require("src.world.gen2.Npc")

local S = require("tests.harness").suite("quick nurse gold")
local check, eq = S.check, S.eq

local savedVersion = GameVersion.get and GameVersion.get()
if GameVersion.set then GameVersion.set("gold") end
local run = T.sdk.loadMod("mods/qol_toggles", {
  data = T.fixtures.fresh(),
  generation = 2,
})
eq(run.mod and run.mod.state, "loaded", "qol_toggles loads on Gold")
eq(#run.errors, 0, "qol_toggles has no Gold load errors")

local loader = run.loader
loader.game = Game
loader.modOptions = loader.modOptions or {}
loader.modOptions.qol_toggles = { quick_nurse = true }
Game.mods = loader
local party = { { hp = 1, maxHp = 20, status = "PSN", moves = {} } }
Game.save = { party = party }

Runtime.emit("game.ready", { game = Game })
check(World._qolTogglesQuickNurseInstalled,
  "Gold installs the QUICK NURSE interaction wrapper")

local map = {
  id = "VIRIDIAN_POKECENTER",
  cellCollision = function(_, x, y)
    return x == 3 and y == 2 and 0x90 or 0x00
  end,
}
local world = World.new(Game)
world.map = map
world.player = { cellX = 2, cellY = 2, facing = "right", moving = false }
world.vm = { running = function() return false end, start = function()
  error("vanilla nurse script should not start")
end }
world.healMachineImage = {}

local nurse = setmetatable({
  cellX = 4, cellY = 2,
  -- Gold's imported Pokecenter objects carry the raw script pointer and the
  -- nurse sprite; the standard-script name is in the map script, not on the
  -- object definition.
  def = { index = 7, scriptKey = "56:5236", sprite = "SPRITE_NURSE" },
}, { __index = NPC })
world.npcs = { nurse }

eq(world:interact(), true, "A press at the Gold nurse is claimed")
eq(world.vm.lastTalked, 8, "Gold records the nurse as LAST_TALKED")
eq(world.talkNpc, nurse, "Gold records the nurse object")
eq(party[1].hp, 20, "QUICK NURSE heals the party")
eq(party[1].status, nil, "QUICK NURSE clears status")
check(world.healAnim ~= nil, "QUICK NURSE starts the heal animation")

run.release()
if GameVersion.set then GameVersion.set(savedVersion or "red") end
S.finish()
