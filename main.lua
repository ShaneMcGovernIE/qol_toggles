-- QoL Toggles: an OPTIONS -> USEFUL TOGGLES submenu with nine switches,
-- each persisted in options.lua:
--   POISON SAVE      a poisoned party member survives at 1 HP and its
--                    poison subsides: "X's poison has subsided!"
--   FULL HEAL CATCH  every captured Pokémon (party or PC) is fully
--                    healed -- HP, status, and all PP
--   INFINITE REPEL   no wild walking encounters (grass, surf, caves)
--                    while the switch is on
--   FIELD MOVES ALL  a species that can learn a field move (level-up or
--                    TM/HM) gets the out-of-battle option without
--                    knowing it
--   BADGELESS MOVES  FLY/SURF/CUT/STRENGTH/FLASH work without their
--                    badges (the list and the usage-time gates both)
--   ALWAYS CATCH     every ball catches, Master Ball style
--   PERFECT DVS      caught Pokémon get 15s across the board
--   EXP x2           double battle EXP
--   INSTANT FLEE     wild battles always escape on the first try
--
-- The submenu is a registry screen and the OPTIONS row joins through the
-- ui.options.rows hook.  The behaviors hook engine seams: the poison tick
-- (OverworldState.applyFieldPoison), the pokemon.caught event,
-- encounter.roll, PartyMenu.update (phantom moves + badge injection),
-- fieldmove.eligibility, Catching.attempt, exp.gain and battle.run.

local Game = require("src.core.Game")

local TOGGLES = {
  { key = "poison_save", label = "POISON SAVE", default = true },
  { key = "catch_heal", label = "FULL HEAL CATCH", default = true },
  { key = "repel", label = "INFINITE REPEL", default = false },
  { key = "field_moves_all", label = "FIELD MOVES ALL", default = true },
  { key = "badgeless_moves", label = "BADGELESS MOVES", default = false },
  { key = "always_catch", label = "ALWAYS CATCH", default = false },
  { key = "perfect_dvs", label = "PERFECT DVS", default = false },
  { key = "exp_mult", label = "EXP x2", default = false },
  { key = "instant_flee", label = "INSTANT FLEE", default = false },
  { key = "heal_map_change", label = "HEAL ON MAP CHANGE", default = false },
  { key = "quick_ssanne", label = "QUICK S.S. ANNE", default = false },
}

-- the out-of-battle moves the party menu can offer (PartyMenu's own list)
local FIELD_MOVES = { "FLY", "FLASH", "CUT", "SURF", "STRENGTH",
                      "SOFTBOILED", "TELEPORT", "DIG" }

-- the HM badges the party menu's list builder and hmBadges gate check
local HM_BADGES = { "THUNDERBADGE", "BOULDERBADGE", "CASCADEBADGE",
                    "SOULBADGE", "RAINBOWBADGE" }

return function(mod)
  local Strings = require("src.core.Strings")
  local OptionRows = require("src.ui.OptionRows")

  -- Toggles ride options.lua's per-mod bucket (the same store the mod
  -- manager writes) instead of the per-save modData: NEW GAME and CONTINUE
  -- replace the save's modData outright, which silently discarded toggles
  -- set from the title screen, and an unsaved session lost them on quit.
  -- options.lua survives both, so a toggle flips once and stays flipped.
  -- the stored value for a key, falling back to the per-toggle default:
  -- everything except INFINITE REPEL ships ON
  mod.exports.defaultFor = function(key)
    for _, spec in ipairs(TOGGLES) do
      if spec.key == key then return spec.default ~= false end
    end
    return false
  end

  local function get(key)
    local loader = Game.mods
    local bucket = loader and loader.modOptions and loader.modOptions[mod.id]
    local v = bucket and bucket[key]
    if v ~= nil then return v end
    return mod.exports.defaultFor(key)
  end

  local function set(key, value)
    local loader = Game.mods
    if not loader then return end
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
    loader.modOptions[mod.id][key] = value
    -- mirror into the active save's options so a session that saves keeps
    -- it; writeOptions persists options.lua (ManagerState:setOption's pair)
    if Game.save and Game.save.options then
      Game.save.options.modOptions = Game.save.options.modOptions or {}
      Game.save.options.modOptions[mod.id] =
        Game.save.options.modOptions[mod.id] or {}
      Game.save.options.modOptions[mod.id][key] = value
    end
    if Game.writeOptions then Game:writeOptions() end
  end

  local function knows(mon, id)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == id then return true end
    end
    return false
  end

  local function canLearn(def, id)
    for _, entry in ipairs(def.learnset or {}) do
      if entry.move == id then return true end
    end
    for _, tm in ipairs(def.tmhm or {}) do
      if tm == id then return true end
    end
    return false
  end

  -- --------------------------------------------------------------- exports

  -- the ON/OFF rows, built against caller-supplied get/set so the submenu
  -- and the headless tests share one implementation
  mod.exports.toggleRows = function(getFn, setFn)
    local rows = {}
    for _, spec in ipairs(TOGGLES) do
      rows[#rows + 1] = {
        id = spec.key,
        label = Strings(spec.label),
        value = function()
          return getFn(spec.key) and Strings("ON") or Strings("OFF")
        end,
        step = function()
          setFn(spec.key, not getFn(spec.key))
          return true
        end,
      }
    end
    return rows
  end

  mod.exports.enabledCount = function(getFn)
    local n = 0
    for _, spec in ipairs(TOGGLES) do
      if getFn(spec.key) then n = n + 1 end
    end
    return n
  end

  -- a poisoned mon at or below the damage threshold survives at 1 HP and
  -- its poison subsides (status cleared); returns the subsided mons so the
  -- caller can queue the message
  mod.exports.poisonClamp = function(party, damage)
    local subsided = {}
    for _, mon in ipairs(party) do
      if mon.status == "PSN" and mon.hp > 0 and mon.hp <= damage then
        mon.hp = 1
        mon.status = nil
        subsided[#subsided + 1] = mon
      end
    end
    return subsided
  end

  -- full heal + PP restore on the caught mon (Pokemon.heal: the same heal
  -- the Pokémon Center and blackouts use)
  mod.exports.healCaught = function(mon)
    require("src.pokemon.Pokemon").heal(mon)
    return mon.hp == mon.stats.hp and mon.status == nil
  end

  -- full heal + PP restore for the whole party (HEAL ON MAP CHANGE)
  mod.exports.healParty = function(party)
    local Pokemon = require("src.pokemon.Pokemon")
    for _, mon in ipairs(party or {}) do
      if mon then Pokemon.heal(mon) end
    end
  end

  -- max DVs on a caught mon: all 15s (hp DV derives to 15 too), stats
  -- recomputed so the mon's actual stats match
  mod.exports.perfectDVs = function(mon, data)
    mon.dvs = { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
    local def = data and data.pokemon and data.pokemon[mon.species]
    if def then
      mon.stats = require("src.pokemon.Stats").calc(def, mon.level,
                                                    mon.dvs, mon.statExp)
    end
    return mon.stats
  end

  -- a party member that counts as knowing a field move for the
  -- fieldmove.eligibility gate: one that knows it, or -- with allMoves --
  -- one whose species can learn it (level-up or TM/HM)
  mod.exports.eligibleMon = function(party, data, moveId, allMoves)
    for _, mon in ipairs(party) do
      if mon and mon.moves then
        for _, mv in ipairs(mon.moves) do
          if mv.id == moveId then return mon end
        end
      end
    end
    if not allMoves then return nil end
    for _, mon in ipairs(party) do
      if mon and mon.moves then
        local def = data and data.pokemon and data.pokemon[mon.species]
        if def and canLearn(def, moveId) then return mon end
      end
    end
    return nil
  end

  -- the field moves this species can learn (level-up or TM/HM) but does
  -- not currently know
  mod.exports.learnableFieldMoves = function(def, mon)
    local out = {}
    for _, id in ipairs(FIELD_MOVES) do
      if def and canLearn(def, id) and not knows(mon, id) then
        out[#out + 1] = id
      end
    end
    return out
  end

  -- append phantom move slots so the vanilla party-menu list builder shows
  -- learnable field moves; returns the added ids for detachPhantomMoves
  mod.exports.attachPhantomMoves = function(mon, def)
    local added = mod.exports.learnableFieldMoves(def, mon)
    for _, id in ipairs(added) do
      mon.moves[#mon.moves + 1] = { id = id }
    end
    return added
  end

  mod.exports.detachPhantomMoves = function(mon, added)
    for _, id in ipairs(added) do
      for i = #mon.moves, 1, -1 do
        if mon.moves[i].id == id then table.remove(mon.moves, i) break end
      end
    end
  end

  -- FIELD MOVES ALL: a species that can learn a field move (level-up or
  -- TM/HM) gets the out-of-battle option even without knowing it.  The
  -- party menu builds its field-move list from mon.moves INLINE in update,
  -- before the ui.party.submenu hook fires, so phantom slots are attached
  -- to the selected mon before the vanilla update runs and detached after.
  -- The vanilla builder then applies every contextual rule untouched: the
  -- badge gates (THUNDERBADGE for FLY, SOULBADGE for SURF, ...),
  -- FLY/TELEPORT outdoors-only, FLASH in the dark, DIG's tileset list.
  -- Selection reads the action off the built item list, never the moveset,
  -- so the phantom slots leave no trace.
  mod.exports.withPhantoms = function(self, nextUpdate, dt)
    -- pickOnly: the menu is an item/script target picker (ether, TM teach,
    -- ...) whose onSwitch reads mon.moves directly -- phantom slots have no
    -- pp and would crash BagMenu's move list
    if self.battle or self.submenu or self.tmhm or self.pickOnly then
      return nextUpdate(self, dt)
    end
    local allMoves = get("field_moves_all")
    local badgeless = get("badgeless_moves")
    if not allMoves and not badgeless then
      return nextUpdate(self, dt)
    end
    local game = self.game
    local party = self.party or (game and game.save and game.save.party)
    local mon = party and party[self.index]
    local added
    if allMoves and mon and mon.moves and game and game.data
       and game.data.pokemon[mon.species] then
      added = mod.exports.attachPhantomMoves(mon,
                                             game.data.pokemon[mon.species])
    end
    -- BADGELESS: fake the HM badges for the list-time gates; the badges
    -- never existed (or were already owned) are removed right after
    local inv = badgeless and game and game.save and game.save.inventory
    local injected = {}
    if inv then
      for _, badge in ipairs(HM_BADGES) do
        if not inv[badge] then
          inv[badge] = 1
          injected[#injected + 1] = badge
        end
      end
    end
    local ok, r1, r2 = pcall(nextUpdate, self, dt)
    if added and #added > 0 then mod.exports.detachPhantomMoves(mon, added) end
    for _, badge in ipairs(injected) do inv[badge] = nil end
    if not ok then error(r1, 0) end
    return r1, r2
  end

  -- one wrap per session; hot reload re-runs entry chunks
  if Game._qolTogglesInstalled then return end
  Game._qolTogglesInstalled = true

  -- QUICK S.S. ANNE: the Vermilion dock sailor (data/scripts/story.lua
  -- onStep, gangway cell 18,30) prompts for the ticket once; every later
  -- pass walks straight through with no dialogue.  The compose chain runs
  -- mod onStep handlers before the base, so returning true consumes the
  -- step silently.  The ship-left guard and the no-ticket walk-back stay
  -- vanilla (there is nothing to board / no ticket to show).
  mod.content.map_scripts:register("VERMILION_CITY", {
    onStep = function(game, ow, x, y)
      if not get("quick_ssanne") then return false end
      if x ~= 18 or y ~= 30 or not ow or not ow.player
         or ow.player.facing ~= "down" then
        return false
      end
      if require("src.script.Flags").get(game.save, "EVENT_SS_ANNE_LEFT") then
        return false
      end
      if get("ssanne_prompted") then return true end
      set("ssanne_prompted", true)
      return false -- one vanilla prompt, then straight through
    end,
  })

  -- ------------------------------------------------------- the OPTIONS row

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    rows = next(game, rows)
    rows[#rows + 1] = {
      id = "qolToggles",
      label = Strings("USEFUL TOGGLES"),
      value = function()
        return Strings("%d/%d ON", mod.exports.enabledCount(get), #TOGGLES)
      end,
      activate = function(g)
        require("src.ui.Screens").push(g, "QolTogglesMenu")
      end,
    }
    return rows
  end)

  -- ---------------------------------------------------------- the submenu

  local QolTogglesMenu = {}
  QolTogglesMenu.__index = QolTogglesMenu
  QolTogglesMenu.isOpaque = true

  -- same MEWMON band as OptionsMenu: the submenu owns the SGB screen
  function QolTogglesMenu:sgbPalettes(game)
    return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
  end

  function QolTogglesMenu:exit()
    if self.game.data then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end

  function QolTogglesMenu:update(dt)
    local input = self.game.input
    local rows = self.rows
    local cancelRow = #rows + 1
    if input:wasPressed("up") then
      self.index = self.index > 1 and self.index - 1 or cancelRow
    elseif input:wasPressed("down") then
      self.index = self.index < cancelRow and self.index + 1 or 1
    elseif input:wasPressed("left") or input:wasPressed("right")
        or input:wasPressed("a") then
      local dir = input:wasPressed("left") and -1 or 1
      local row = rows[self.index]
      if row and row.step then
        row.step(self.game, dir)
      elseif input:wasPressed("a") then -- CANCEL
        self:exit()
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      self:exit()
    end
    self.scroll = OptionRows.clampScroll(self.index, self.scroll or 0,
                                         #rows, cancelRow)
  end

  function QolTogglesMenu:draw()
    OptionRows.draw(self.game, self.rows, self.index, self.scroll or 0,
                    "CANCEL", #self.rows + 1)
  end

  mod.content.screens:register("QolTogglesMenu", { new = function(game, opts)
    opts = opts or {}
    return setmetatable({
      game = game,
      rows = mod.exports.toggleRows(get, set),
      index = 1, scroll = 0,
      onCancel = opts.onCancel,
    }, QolTogglesMenu)
  end })

  -- ---------------------------------------------------------- behaviors

  -- POISON SAVE: wrap the out-of-battle poison tick.  On the tick, at-risk
  -- mons are clamped to 1 HP (status cleared) before the vanilla pass runs,
  -- so vanilla never faints them; the subsided message is queued after.
  mod.events:on("game.ready", function()
    local OverworldState = require("src.world.OverworldController")
    if OverworldState._qolTogglesPoisonInstalled then return end
    OverworldState._qolTogglesPoisonInstalled = true

    local FieldDefaults = require("src.world.FieldDefaults")
    local TextBox = require("src.render.TextBox")
    local vanillaPoison = OverworldState.applyFieldPoison
    OverworldState.applyFieldPoison = function(self)
      if not get("poison_save") then return vanillaPoison(self) end
      local save = Game.save
      local interval = FieldDefaults.world(Game.data, "poisonStepInterval") or 4
      local nextStep = (save.poisonSteps or 0) + 1
      if nextStep % interval ~= 0 then return vanillaPoison(self) end
      local damage = FieldDefaults.world(Game.data, "poisonDamage") or 1
      local subsided = mod.exports.poisonClamp(save.party, damage)
      local stopped = vanillaPoison(self)
      if #subsided == 0 then return stopped end
      local queue = {}
      for _, mon in ipairs(subsided) do
        local name = mon.nickname
                   or (Game.data.pokemon[mon.species] or {}).name or "?"
        queue[#queue + 1] = Strings("%s's poison\nhas subsided!", name)
      end
      local function showNext()
        local msg = table.remove(queue, 1)
        if msg then
          Game.stack:push(TextBox.new(Game, msg, showNext))
        end
      end
      showNext()
      return true
    end
  end)

  -- HEAL ON MAP CHANGE: every setMap (warps, caves, route seams, boot)
  -- fully heals the party -- HP, status, and all PP
  mod.events:on("game.ready", function()
    local OverworldState = require("src.world.OverworldController")
    if OverworldState._qolTogglesHealMapInstalled then return end
    OverworldState._qolTogglesHealMapInstalled = true

    local vanillaSetMap = OverworldState.setMap
    OverworldState.setMap = function(self, mapId, x, y, facing, opts)
      local result = vanillaSetMap(self, mapId, x, y, facing, opts)
      if get("heal_map_change") and Game.save then
        mod.exports.healParty(Game.save.party)
      end
      return result
    end
  end)

  -- PERFECT DVS + FULL HEAL CATCH: storeCaughtMon places the mon (party or
  -- PC) before emitting pokemon.caught, so mutating the payload covers
  -- both.  DVs first (stats recomputed), then the heal reads the new max.
  mod.events:on("pokemon.caught", function(ev)
    if not (ev and ev.mon) then return end
    local data = (ev.game and ev.game.data) or Game.data
    if get("perfect_dvs") then mod.exports.perfectDVs(ev.mon, data) end
    if get("catch_heal") then mod.exports.healCaught(ev.mon) end
  end)

  -- INFINITE REPEL: suppress every walking wild roll (grass, surf, caves);
  -- fishing keeps its own encounter.fishing path, like the Repel item.
  -- Defensive: a downstream roll that throws (e.g. another mod's patch
  -- left a map's water/grass def without a rate) degrades to "no
  -- encounter" instead of blue-screening the game mid-step.
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if get("repel") then return nil end
    local ok, enc = pcall(next, encDef, ctx)
    if ok then return enc end
    mod.log.warn("encounter.roll failed (%s); suppressing the roll",
                 tostring(enc))
    return nil
  end)

  -- FIELD MOVES ALL / BADGELESS MOVES at USE time: the surf mount, the cut
  -- and the hmBadges gate all go through partyKnows, which consults the
  -- fieldmove.eligibility hook.  FIELD MOVES ALL unlocks the MOVE, not its
  -- badge: the hmBadges gate still applies unless BADGELESS MOVES is on.
  -- (Older engine builds have no list-time badge check in the party menu,
  -- so this hook is the only thing standing between a badge-less player
  -- and a free Surf/Cut on those builds.)
  mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    local b = ctx and ctx.save
    if b and b.party
       and (get("badgeless_moves") or get("field_moves_all")) then
      local mon = mod.exports.eligibleMon(b.party, ctx.data, moveId,
                                          get("field_moves_all"))
      if mon then
        if get("badgeless_moves") then return mon end
        local gate = (require("src.world.FieldDefaults")
                      .constant(ctx.data, "hmBadges") or {})[moveId]
        local badge = gate and gate.badge
        if not badge or (b.inventory and b.inventory[badge]) then
          return mon
        end
      end
    end
    return next(moveId, ctx)
  end)

  -- EXP x2: the engine's exp.gain hook returns the raw amount every
  -- participant is paid; doubling it scales the announcement text too
  mod.hooks:wrap("exp.gain", function(next, ctx)
    local gained = next(ctx)
    if get("exp_mult") then return gained * 2 end
    return gained
  end)

  -- INSTANT FLEE: battle.run is the RUN menu + faint-dialogue escape roll
  -- (runRoll); forcing true escapes on the first try
  mod.hooks:wrap("battle.run", function(next, ctx)
    if get("instant_flee") then return true end
    return next(ctx)
  end)

  -- one wrap per session; hot reload re-runs entry chunks
  if Game._qolTogglesPartyMenuInstalled then return end
  Game._qolTogglesPartyMenuInstalled = true

  local PartyMenu = require("src.ui.PartyMenu")
  local vanillaUpdate = PartyMenu.update
  PartyMenu.update = function(self, dt)
    return mod.exports.withPhantoms(self, vanillaUpdate, dt)
  end

  -- ALWAYS CATCH: every ball lands, Master Ball style -- caught with the
  -- full three-shake chain so the ball anim plays out
  local Catching = require("src.battle.Catching")
  local vanillaAttempt = Catching.attempt
  Catching.attempt = function(ball, targetMon, targetDef, rng, rateOverride,
                              opts)
    if get("always_catch") then return true, 3 end
    return vanillaAttempt(ball, targetMon, targetDef, rng, rateOverride,
                          opts)
  end
end
