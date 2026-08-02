-- QoL Toggles: an OPTIONS -> TOGGLES submenu with three switches, each
-- persisted per save via mod.save:
--   POISON SAVE      a poisoned party member survives at 1 HP and its
--                    poison subsides: "X's poison has subsided!"
--   FULL HEAL CATCH  every captured Pokémon (party or PC) is fully
--                    healed -- HP, status, and all PP
--   INFINITE REPEL   no wild walking encounters (grass, surf, caves)
--                    while the switch is on
--
-- The submenu is a registry screen and the OPTIONS row joins through the
-- ui.options.rows hook.  The three behaviors hook engine seams:
--   OverworldState.applyFieldPoison is wrapped on game.ready
--   the pokemon.caught event heals the stored mon
--   the encounter.roll hook suppresses the wild roll

local Game = require("src.core.Game")

local TOGGLES = {
  { key = "poison_save", label = "POISON SAVE", default = true },
  { key = "catch_heal", label = "FULL HEAL CATCH", default = true },
  { key = "repel", label = "INFINITE REPEL", default = false },
  { key = "field_moves_all", label = "FIELD MOVES ALL", default = true },
}

-- the out-of-battle moves the party menu can offer (PartyMenu's own list)
local FIELD_MOVES = { "FLY", "FLASH", "CUT", "SURF", "STRENGTH",
                      "SOFTBOILED", "TELEPORT", "DIG" }

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
    if not get("field_moves_all") or self.battle or self.submenu
       or self.tmhm then
      return nextUpdate(self, dt)
    end
    local game = self.game
    local party = self.party or (game and game.save and game.save.party)
    local mon = party and party[self.index]
    local added
    if mon and mon.moves and game and game.data
       and game.data.pokemon[mon.species] then
      added = mod.exports.attachPhantomMoves(mon,
                                             game.data.pokemon[mon.species])
    end
    local ok, r1, r2 = pcall(nextUpdate, self, dt)
    if added and #added > 0 then mod.exports.detachPhantomMoves(mon, added) end
    if not ok then error(r1, 0) end
    return r1, r2
  end

  -- one wrap per session; hot reload re-runs entry chunks
  if Game._qolTogglesInstalled then return end
  Game._qolTogglesInstalled = true

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

  -- FULL HEAL CATCH: storeCaughtMon places the mon (party or PC) before
  -- emitting pokemon.caught, so healing the payload covers both
  mod.events:on("pokemon.caught", function(ev)
    if not get("catch_heal") then return end
    if ev and ev.mon then mod.exports.healCaught(ev.mon) end
  end)

  -- INFINITE REPEL: suppress every walking wild roll (grass, surf, caves);
  -- fishing keeps its own encounter.fishing path, like the Repel item
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if get("repel") then return nil end
    return next(encDef, ctx)
  end)

  -- one wrap per session; hot reload re-runs entry chunks
  if Game._qolTogglesPartyMenuInstalled then return end
  Game._qolTogglesPartyMenuInstalled = true

  local PartyMenu = require("src.ui.PartyMenu")
  local vanillaUpdate = PartyMenu.update
  PartyMenu.update = function(self, dt)
    return mod.exports.withPhantoms(self, vanillaUpdate, dt)
  end
end
