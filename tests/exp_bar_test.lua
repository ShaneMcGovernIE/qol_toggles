-- Standalone unit test for Battle EXP Bar logic
-- Can be executed directly with: lua tests/exp_bar_test.lua

local function assertEq(actual, expected, desc)
  if actual ~= expected then
    error(string.format("FAIL: %s (expected %s, got %s)", desc, tostring(expected), tostring(actual)), 2)
  end
  print(string.format("PASS: %s", desc))
end

local function assertNear(actual, expected, eps, desc)
  if math.abs(actual - expected) > (eps or 1e-6) then
    error(string.format("FAIL: %s (expected %s, got %s)", desc, tostring(expected), tostring(actual)), 2)
  end
  print(string.format("PASS: %s", desc))
end

print("=== Testing Battle EXP Bar Calculations ===")

-- Mock minimal environment
local mod = {
  hooks = { wrap = function() end },
  events = { on = function() end, emit = function() end },
  exports = {},
  storage = {},
  save = { get = function(_, _, def) return def end },
  log = { warn = function() end },
}

-- Replicate pure calculation functions
local EXP_BAR_X = 80
local EXP_BAR_RIGHT = 147
local EXP_BAR_WIDTH = 67
local EXP_BAR_Y = 89
local EXP_BAR_HEIGHT = 2
local EXP_BAR_SPEED = 40

local function expForLevel(growthRate, level, growthRatesData)
  local n = math.max(1, math.min(100, tonumber(level) or 1))
  local rate = tostring(growthRate or ""):lower()
  if rate == "fast" or (rate:find("fast") and not rate:find("medium")) then
    return math.floor(4 * n * n * n / 5)
  elseif rate == "slow" or (rate:find("slow") and not rate:find("medium")) then
    return math.floor(5 * n * n * n / 4)
  elseif rate:find("medium") and rate:find("slow") then
    if n <= 1 then return 0 end
    return math.floor(1.2 * n * n * n - 15 * n * n + 100 * n - 140)
  else
    return n * n * n
  end
end

local function expBarProgress(mon, data)
  if not (mon and mon.species) then return 0, 0, 0, 0 end
  local pokemonData = data and data.pokemon
  local def = pokemonData and pokemonData[mon.species]
  local growthRate = (def and def.growthRate) or (mon.def and mon.def.growthRate) or "Medium Fast"
  local growthRates = data and data.growth_rates
  local level = mon.level or 1
  local cap = (data and data.constants and data.constants.levelCap) or 100

  if level >= cap then
    return 0, 0, 1.0, EXP_BAR_WIDTH
  end

  local curLevelExp = expForLevel(growthRate, level, growthRates)
  local nextLevelExp = expForLevel(growthRate, level + 1, growthRates)
  local needed = nextLevelExp - curLevelExp
  if needed <= 0 then return 0, 0, 0, 0 end

  local curExp = mon.exp or curLevelExp
  local progress = math.max(0, math.min(needed, curExp - curLevelExp))
  local fraction = progress / needed
  local filledPixels = math.floor(fraction * EXP_BAR_WIDTH)
  return progress, needed, fraction, filledPixels
end

local function expBarPixels(battle)
  local mon = battle and battle.player and battle.player.mon
  if not mon then return 0 end
  local _, _, _, pixels = expBarProgress(mon, battle.data)
  return pixels
end

local function updateExpBar(battle, dt)
  local mon = battle and battle.player and battle.player.mon
  if not mon then
    battle._qolExpBarState = nil
    return
  end

  local targetPixels = expBarPixels(battle)
  local state = battle._qolExpBarState
  if not state or state.mon ~= mon then
    battle._qolExpBarState = {
      mon = mon,
      level = mon.level or 1,
      pixels = targetPixels,
    }
    return
  end

  local step = (dt or (1 / 60)) * EXP_BAR_SPEED
  local currentLevel = mon.level or 1

  if currentLevel > state.level then
    if state.pixels < EXP_BAR_WIDTH then
      state.pixels = math.min(EXP_BAR_WIDTH, state.pixels + step)
    else
      state.level = state.level + 1
      state.pixels = 0
    end
  elseif currentLevel < state.level then
    state.level = currentLevel
    state.pixels = targetPixels
  else
    if state.pixels < targetPixels then
      state.pixels = math.min(targetPixels, state.pixels + step)
    elseif state.pixels > targetPixels then
      state.pixels = math.max(targetPixels, state.pixels - step)
    end
  end
end

local function drawExpBar(battle, graphics)
  local mon = battle and battle.player and battle.player.mon
  if not mon then return end

  local state = battle._qolExpBarState
  local pixels = (state and state.mon == mon and state.pixels)
                 or expBarPixels(battle)
  pixels = math.max(0, math.min(EXP_BAR_WIDTH, math.floor(pixels or 0)))
  if pixels <= 0 then return end

  local x = EXP_BAR_RIGHT - pixels
  local y = EXP_BAR_Y

  graphics.setColor(0, 0, 0, 1)
  graphics.rectangle("fill", x, y, pixels, EXP_BAR_HEIGHT)
end

-- Run assertions
assertEq(expForLevel("Fast", 1), 0, "Fast level 1")
assertEq(expForLevel("Fast", 5), 100, "Fast level 5")
assertEq(expForLevel("Medium Fast", 5), 125, "Medium Fast level 5")
assertEq(expForLevel("Slow", 5), 156, "Slow level 5")
assertEq(expForLevel("Medium Slow", 5), 135, "Medium Slow level 5")

local data = {
  pokemon = {
    PIKACHU = { species = "PIKACHU", growthRate = "Medium Fast" },
    CHARMANDER = { species = "CHARMANDER", growthRate = "Medium Slow" },
  },
  constants = { levelCap = 100 },
}

local mon = { species = "PIKACHU", level = 5, exp = 125 }
local p, n, f, px = expBarProgress(mon, data)
assertEq(p, 0, "Progress at level start is 0")
assertEq(n, 91, "Needed exp from lvl 5 to 6 is 91")
assertEq(f, 0, "Fraction is 0")
assertEq(px, 0, "Pixels is 0")

mon.exp = 170
p, n, f, px = expBarProgress(mon, data)
assertEq(p, 45, "Progress exp is 45")
assertNear(f, 45 / 91, 1e-6, "Fraction matches")
assertEq(px, math.floor(45 / 91 * 67), "33 pixels matches math.floor(45/91 * 67)")

mon.level = 100
p, n, f, px = expBarProgress(mon, data)
assertEq(f, 1.0, "Level 100 fraction is 1.0")
assertEq(px, 67, "Level 100 pixels is 67")

-- Test battle target
local battle = { data = data, player = { mon = { species = "PIKACHU", level = 5, exp = 170 } } }
assertEq(expBarPixels(battle), 33, "Battle pixel target")

-- Test animation
updateExpBar(battle, 0.1)
assertEq(battle._qolExpBarState.pixels, 33, "Initialized state pixels")

battle.player.mon.exp = 200 -- target = math.floor(75/91 * 67) = 55
updateExpBar(battle, 0.25) -- dt = 0.25, step = 10
assertEq(battle._qolExpBarState.pixels, 43, "Animated step 10px")

-- Test level up
battle.player.mon.level = 6
battle.player.mon.exp = 220
battle._qolExpBarState.pixels = 63
battle._qolExpBarState.level = 5
updateExpBar(battle, 0.25) -- step = 10, hits 67
assertEq(battle._qolExpBarState.pixels, 67, "Fills to max 67 on level up")
updateExpBar(battle, 0.1)
assertEq(battle._qolExpBarState.level, 6, "Level increments")
assertEq(battle._qolExpBarState.pixels, 0, "Resets to 0")

-- Test draw
local drawCalls = {}
local mockGraphics = {
  setColor = function(...) drawCalls.color = { ... } end,
  rectangle = function(...) drawCalls.rect = { ... } end,
}
battle._qolExpBarState.pixels = 33
drawExpBar(battle, mockGraphics)
assertEq(drawCalls.color[1], 0, "Draw color black R")
assertEq(drawCalls.color[4], 1, "Draw color alpha 1")
assertEq(drawCalls.rect[1], "fill", "Draw mode fill")
assertEq(drawCalls.rect[2], 114, "Draw X 114 (147 - 33)")
assertEq(drawCalls.rect[3], 89, "Draw Y 89")
assertEq(drawCalls.rect[4], 33, "Draw width 33")
assertEq(drawCalls.rect[5], 2, "Draw height 2")

print("=== All EXP Bar standalone tests passed successfully! ===")
