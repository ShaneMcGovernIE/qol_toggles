-- QoL Toggles: an OPTIONS -> QOL TOGGLES submenu with nine switches,
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
--   HM ITEM REQUIRED the FIELD MOVES ALL phantom slots for HM moves only
--                    appear once the player holds the HM item
--                    (no CUT on the Cascade Badge alone -- the HM is on
--                    the S.S. Anne)
--   UNLIMITED TMs    TMs teach without breaking
--   FORGETTABLE HMs  HM moves can be forgotten when a mon learns a new
--                    move
--   ALWAYS CATCH     every ball catches, Master Ball style
--   PERFECT DVS      caught Pokémon get 15s across the board
--   EXP x2           double battle EXP
--   CATCH GIVES EXP  capturing a wild mon pays out the same EXP its
--                    defeat would (split among the mons that fought)
--   INSTANT FLEE     wild battles always escape on the first try
--   REMEMBER CURSOR  the battle FIGHT/BAG/PKMN/RUN cursor stays where it
--                    was last turn; OFF restores the fresh-FIGHT default
--   LAST ITEM (M)    in battle, M uses the last item used from the bag:
--                    balls throw at the foe, healing asks which mon
--   POKEBALL BONUS   buying 10 POKé BALLS at any mart gets you a free
--                    GREAT BALL
--   NO ENCOUNTER DUPES  a wild roll never gives the same species twice
--                       in a row (rerolls until it differs)
--   INSTANT FISH        the rod always bites on the first try
--   HEAL AFTER BATTLE   every battle ends with the party fully healed
--   AUTO-REPEL          a worn-off repel is replaced from the bag (best
--                       one first)
--   BULK MART           mart quantity prompts open at 10 instead of 1
--   LIGHTS ON           dark caves render fully lit, no FLASH needed
--   REMEMBER MOVE       the FIGHT move cursor stays on the last move
--   KEEP MONEY          blacking out no longer costs half your money
--   AUTO CUT            walking into a cut tree cuts it when a mon knows
--                       CUT
--   RUN (HOLD B)        hold B to move twice as fast on foot
--   MOUSE CAM LOCK   Dramatic Shape's battle camera no longer follows the
--                    mouse (the right stick, a drag and the zoom still work)
--   BULK COINS         the Celadon Game Corner clerk sells 50, 500 or
--                      9,999 coins at a time
--   MAP LOCATION       entering a new area shows its name in a toast
--
-- START on a controller (or P on the keyboard) on any row opens an
-- in-depth explanation of what that toggle does.
--
-- M (the LAST ITEM key) is latched from the raw Game key wraps exactly
-- like the P help key -- so the Mods Hotkeys submenu's static scan finds
-- it, and a rebind re-emits "m" into the same chain -- and consumed by a
-- wrapped BattleState.update while the FIGHT/BAG/PKMN/RUN menu is up.
--
-- The submenu is a registry screen and the OPTIONS row joins through the
-- ui.options.rows hook. The behaviors hook engine seams: the poison tick
-- (OverworldState.applyFieldPoison), the pokemon.caught event,
-- encounter.roll, PartyMenu.update (phantom moves + badge injection),
-- fieldmove.eligibility, Catching.attempt, exp.gain, battle.run,
-- BattleState.update (including the autoBattleUpdate seam for AUTO BATTLER),
-- ItemEffects.use, ShopMenu.new/ListMenu.new (the POKEBALL BONUS buy
-- window) and Bag.add (the bonus grant).

local Game = require("src.core.Game")

-- Ticker pacing (the MoveRelearn name ticker's): hold at each end so the
-- player can read the whole label, scroll at 16px/s (half a second per
-- glyph).
local TICKER_HOLD = 1.6
local TICKER_SPEED = 16

-- Generic hold/scroll/hold/scroll-back cycle, shared by the horizontal
-- label ticker and the popup's vertical help scroll.  Pure (exported for
-- headless tests): horizontal offset for an overflowing label at time t
-- (seconds).  Cycle: hold at 0, scroll out to -overflow, hold, scroll back
-- to 0.  Content that fits (overflow <= 0) is static.
local function scrollOffset(t, overflow, hold, speed)
  if not (overflow and overflow > 0) then return 0 end
  local scroll = overflow / speed
  local cycle = 2 * hold + 2 * scroll
  local p = t % cycle
  if p < hold then return 0 end
  p = p - hold
  if p < scroll then return -p * speed end
  p = p - scroll
  if p < hold then return -overflow end
  p = p - hold
  return -overflow + p * speed
end

local function tickerOffset(t, overflow)
  return scrollOffset(t, overflow, TICKER_HOLD, TICKER_SPEED)
end

-- The popup's vertical help scroll: slower than the label ticker so a
-- line can be read as it passes (8px/s = one line per second), with the
-- same hold at each end.
local VERT_HOLD = 1.6
local VERT_SPEED = 8
local function vertOffset(t, overflow)
  return scrollOffset(t, overflow, VERT_HOLD, VERT_SPEED)
end

-- Label geometry for OptionRows rows: labels start at x=16 (OptionRows.draw)
-- and the engine's text convention pads 8px inside the box, so a label
-- clips at the inner right edge 152.  The GB font is a flat 8px/glyph, so
-- the window is 136px = 17 glyphs.  Labels wider than that ticker.
local LABEL_X = 16
local LABEL_CLIP_W = 152 - LABEL_X

-- The ticker record for a label, or nil when it fits its window.  Pure,
-- so the headless suite can assert the overflow path without drawing.
local function tickerFor(label)
  local w = require("src.render.Font").width(label)
  if w <= LABEL_CLIP_W then return nil end
  return { x = LABEL_X, w = LABEL_CLIP_W, overflow = w - LABEL_CLIP_W }
end

-- Help popups: START on a controller or P on the keyboard opens a
-- full-screen popup (the Mods Hotkeys capture idiom) with an in-depth
-- explanation of the row under the cursor.  P is not a Game Boy
-- button (it never reaches Input:wasPressed), so the presses are latched
-- from the raw Game input wraps and consumed by the menu's update.
-- menuIsTop() gates the latch so a stray P/START while some other state
-- is on top can never fire when the menu opens later.
local helpRequested = false
local function menuIsTop()
  local stack = Game.stack
  local states = stack and stack.states
  local top = states and states[#states]
  return top ~= nil and top._qolTogglesMenu == true
end

-- POKEBALL BONUS: true while a mart's BUY list is open (set by the
-- ShopMenu wrap when the player enters BUY, cleared by the BUY list's
-- cancel).  Only poké balls actually bought at a mart count toward the
-- free GREAT BALL -- Oak's five starter balls and picked-up balls never
-- do, because no script runs while the shop list is on the stack.
local martBuyOpen = false

-- LAST ITEM (M): the item id of the last bag use that succeeded (recorded
-- by the ItemEffects.use wrap below), and the M key's held latch.  The
-- latch is armed only while a battle sits on top of the stack (the
-- BattleState.update wrap tags every battle it sees with _qolBattle), so
-- a press during a text box is dropped and can never leak into the next
-- battle.  mKeyHeld stays true until the key is released, so keyboard
-- auto-repeat (which this chain cannot tell from a fresh press) can never
-- burn a second item while the key is held down.
local lastItemId = nil
local mKeyHeld = false
local function battleTop()
  local stack = Game.stack
  local states = stack and stack.states
  local top = states and states[#states]
  if top and top._qolBattle then return top end
  return nil
end

-- NO ENCOUNTER DUPES: the species of the last wild roll, nil until the
-- first encounter; a roll that repeats it is re-rolled (session-scoped,
-- like lastItemId -- hot reload resets it, which is fine).
local lastEncounterSpecies = nil

-- KEEP MONEY: the pre-blackout money, snapshotted by the wraps right
-- before the two halving sites (afterBattle and the poison-tick
-- blackout) and restored by the world.blacked_out handler.
local blackoutKeepMoney = nil

-- BULK MART: true while a mart's SELL list is open (the mirror of
-- martBuyOpen; the ListMenu wrap sets and clears it).
local martSellOpen = false

-- AUTO-REPEL toast: a transient on-screen banner (drawn by the overworld
-- draw wrap) announcing the repel that was just auto-used.  Non-modal --
-- the player keeps walking while it fades out on its own.
local autoRepelToast = nil
local TOAST_SECONDS = 2.5

-- MAP LOCATION: the last map the player entered (nil until the first
-- entry), so a toast fires only when the area actually changes; the
-- session-scoped mirror of lastEncounterSpecies.
local lastMapId = nil

local TOGGLES = {
  { key = "poison_save", label = "POISON SAVE", default = true,
    help = "A poisoned mon\nfated to faint\nfrom the step\nkeeps 1 HP and\nthe poison\nsubsides." },
  { key = "catch_heal", label = "FULL HEAL CATCH", default = true,
    help = "Every caught mon\nis fully healed:\nHP, status and\nall PP, party or\nbox." },
  { key = "repel", label = "INFINITE REPEL", default = false,
    help = "While on, walking\ngives no wild\nencounters, in\ngrass, surf or\ncaves.\vFishing keeps\nits own odds." },
  { key = "field_moves_all", label = "FIELD MOVES ALL", default = true,
    help = "A mon that can\nlearn a field\nmove can use it\nwithout knowing\nit.\vBadge gates and\ncontext rules." },
  { key = "badgeless_moves", label = "BADGELESS MOVES", default = false,
    help = "FLY, SURF, CUT,\nSTRENGTH and\nFLASH work\nwithout their\nbadges." },
  { key = "hm_item_required", label = "HM ITEM REQUIRED", default = true,
    help = "HM move slots only\nappear once you\nhold the HM item.\vMoves a mon\nalready knows are\nnever gated." },
  { key = "unlimited_tms", label = "UNLIMITED TMs", default = true,
    help = "TMs teach their\nmove without\nbeing used up." },
  { key = "forgettable_hms", label = "FORGETTABLE HMs", default = true,
    help = "HM moves can be\nforgotten when a\nmon learns a new\nmove." },
  { key = "always_catch", label = "ALWAYS CATCH", default = false,
    help = "Every ball\ncatches, Master\nBall style.\vThe ball is\nstill consumed." },
  { key = "perfect_dvs", label = "PERFECT DVS", default = false,
    help = "Caught mons get\n15s across the\nboard, the Gen 1\nmaximum, with\nstats recomputed\nto match." },
  { key = "exp_mult", label = "EXP x2", default = false,
    help = "Battle EXP is\ndoubled; the gained\ntext shows the new\namount." },
  { key = "catch_exp", label = "CATCH GIVES EXP", default = false,
    help = "Catching a wild\nmon pays out the\nsame EXP its\ndefeat would,\nsplit among the\nmons that fought." },
  { key = "instant_flee", label = "INSTANT FLEE", default = false,
    help = "Wild battles\nalways escape on\nthe first try,\nfrom the RUN menu\nand the faint\ndialogue both." },
  { key = "remember_cursor", label = "REMEMBER CURSOR", default = true,
    help = "The battle menu\ncursor stays\nwhere you left it\nacross turns.\vOFF restores\nthe fresh FIGHT\ndefault each turn" },
  { key = "heal_map_change", label = "HEAL ON MAP CHANGE", default = false,
    help = "Every map change\nfully heals the\nparty: HP, status\nand all PP." },
  { key = "quick_ssanne", label = "QUICK S.S. ANNE", default = false,
    help = "The dock sailor\nasks for the\nticket once.\vAfter that you\nwalk straight\nonto the ship." },
  { key = "last_item", label = "LAST ITEM (M)", default = false,
    help = "Press M in battle\nto use the last\nitem you used.\vBalls throw at\nthe foe; healing\nasks which\nPOKéMON." },
  { key = "free_great_ball", label = "POKEBALL BONUS", default = false,
    help = "Buy 10 POKé\nBALLS at any\nmart and get a\nfree GREAT\nBALL.\vThe count\ncarries over." },
  { key = "mouse_cam_lock", label = "MOUSE CAM LOCK", default = false,
    help = "Dramatic Shape's\nbattle camera\nstops following\nthe mouse.\vThe stick,\na drag and the\nzoom still work." },
  { key = "no_enc_dupes", label = "NO ENCOUNTER DUPES", default = false,
    help = "A wild roll never\ngives the same\nspecies twice in\na row.\vRerolls until it\ndiffers." },
  { key = "instant_fish", label = "INSTANT FISH", default = false,
    help = "The rod always\nbites, no more\n\"Not even a\nnibble!\" loops." },
  { key = "heal_battle", label = "HEAL AFTER BATTLE", default = false,
    help = "Every battle\nends with the\nparty fully\nhealed: HP,\nstatus, PP." },
  { key = "auto_repel", label = "AUTO-REPEL", default = true,
    help = "When a repel\nwears off, the\nstrongest one in\nthe bag is used\nfor you.\vOut of repels:\nit wears off." },
  { key = "bulk_mart", label = "BULK MART", default = false,
    help = "Mart quantity\nprompts start\nat 10 instead\nof 1.\vStill capped by\nyour money and\nbag space." },
  { key = "bulk_coins", label = "BULK COINS", default = false,
    help = "The Celadon Game\nCorner clerk also\nsells 500 and\n9,999 coins.\vCUSTOM: 4 digit\nboxes, 0-9 each\n(up to 9999)." },
  { key = "lights_on", label = "LIGHTS ON", default = false,
    help = "Dark caves and\ntunnels render\nfully lit.\vNo FLASH\nneeded." },
  { key = "remember_move", label = "REMEMBER MOVE", default = true,
    help = "The FIGHT move\ncursor stays on\nthe last move\nused.\vOFF resets to\nthe first move\neach turn." },
  { key = "keep_money", label = "KEEP MONEY", default = false,
    help = "Blacking out\nno longer costs\nhalf your\nmoney." },
  { key = "auto_cut", label = "AUTO CUT", default = false,
    help = "Walk into a cut\ntree and a mon\nthat knows CUT\ncuts it for\nyou." },
  { key = "run_hold_b", label = "RUN (HOLD B)", default = false,
    help = "Hold B to move\ntwice as fast\non foot.\vNo effect on\nthe bike or\nsurfing." },
  { key = "auto_battler", label = "AUTO BATTLER", default = false,
    help = "Battle Palace\nAI picks moves.\vDVs and stat\nEXP shape its\nstyle." },
  { key = "map_location", label = "MAP LOCATION", default = true,
    help = "Entering a new\narea shows its\nname in a toast\nthat fades out,\nlike AUTO-REPEL." },
}

-- the out-of-battle moves the party menu can offer (PartyMenu's own list)
local FIELD_MOVES = { "FLY", "FLASH", "CUT", "SURF", "STRENGTH",
                      "SOFTBOILED", "TELEPORT", "DIG" }

-- the HM badges the party menu's list builder and hmBadges gate check
local HM_BADGES = { "THUNDERBADGE", "BOULDERBADGE", "CASCADEBADGE",
                    "SOULBADGE", "RAINBOWBADGE" }

-- the item each HM field move is owned by (the RomExtractor keys items
-- as HM_<MOVE>); HM ITEM REQUIRED gates the phantom slots on holding it
local HM_ITEMS = {
  CUT = "HM_CUT", FLY = "HM_FLY", SURF = "HM_SURF",
  STRENGTH = "HM_STRENGTH", FLASH = "HM_FLASH",
}

-- MAP LOCATION: display names that correct the town map data -- the town
-- map calls the Route 10 PokeCenter "ROCK TUNNEL", which would be a lie
-- for a location toast; the map's own label is the accurate name
local MAP_LOCATION_NAMES = {
  ROCK_TUNNEL_POKECENTER = "ROCK TUNNEL POKECENTER",
}

return function(mod)
  local Strings = require("src.core.Strings")
  local OptionRows = require("src.ui.OptionRows")
  local Font = require("src.render.Font")

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
  -- and the headless tests share one implementation.  A label wider than
  -- the row's label window gets a ticker (row.tick advanced by the menu's
  -- update) instead of bleeding over the box border.
  mod.exports.toggleRows = function(getFn, setFn)
    local rows = {}
    for _, spec in ipairs(TOGGLES) do
      local label = Strings(spec.label)
      local row = {
        id = spec.key,
        label = label,
        help = spec.help,
        value = function()
          return getFn(spec.key) and Strings("ON") or Strings("OFF")
        end,
        step = function()
          setFn(spec.key, not getFn(spec.key))
          return true
        end,
      }
      local ticker = tickerFor(label)
      if ticker then
        row.ticker = ticker
        row.tick = 0
      end
      rows[#rows + 1] = row
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

  mod.exports.tickerOffset = tickerOffset
  mod.exports.vertOffset = vertOffset
  mod.exports.tickerFor = tickerFor

  -- the in-depth help for a toggle id (START / P on its row), or nil for
  -- an unknown id; the rows carry it so the menu never re-looks it up
  mod.exports.helpFor = function(id)
    for _, spec in ipairs(TOGGLES) do
      if spec.key == id then return spec.help end
    end
    return nil
  end

  -- test seam: latches a help request exactly like the raw input wraps do
  mod.exports.requestHelp = function()
    helpRequested = true
  end

  -- LAST ITEM (M): the item id of the last successful bag use, and the
  -- test seam to set/clear it (the ItemEffects.use wrap is the live writer)
  mod.exports.lastItem = function()
    return lastItemId
  end

  mod.exports.setLastItem = function(id)
    lastItemId = id
  end

  -- POKEBALL BONUS: the free GREAT BALLs qty more POKé BALLS unlock after
  -- count already bought -- one per ten, cumulative across shops and saves
  mod.exports.bonusBalls = function(count, qty)
    qty = qty or 1
    return math.floor((count + qty) / 10) - math.floor(count / 10)
  end

  -- the clerk's "free ball" message, shown once per purchase that unlocks
  -- one or more GREAT BALLs
  mod.exports.bonusMessage = function()
    return "Thanks for your\nsupport,\vplease take\nthis free\vGreat Ball!"
  end

  -- test seam: marks the mart's BUY list open exactly like the ShopMenu
  -- wrap does, so the headless suite can drive the Bag.add bonus
  mod.exports.setMartBuyOpen = function(open)
    martBuyOpen = open
  end

  -- test seam: the SELL-list mirror of setMartBuyOpen (the ListMenu wrap
  -- is the live writer), so the suite can drive the BULK MART qty box
  mod.exports.setMartSellOpen = function(open)
    martSellOpen = open
  end

  -- NO ENCOUNTER DUPES: re-roll a wild encounter until it is not the same
  -- species as the last one (max attempts, then the last roll stands).
  -- Pure: `roll` is any thunk returning an encounter table or nil.
  mod.exports.avoidDupe = function(roll, last, max)
    local lastRoll
    for _ = 1, (max or 8) do
      local enc = roll()
      if not enc then return nil end
      lastRoll = enc
      if enc.species ~= last then return enc end
    end
    return lastRoll
  end

  -- INSTANT FISH: a uniform pick from the rod's candidate group, skipping
  -- the engine's rejection loop (bite odds size/(size+4)); nil when the
  -- map has no fishing group at all (nothing to conjure).
  mod.exports.fishBite = function(candidates)
    if candidates and #candidates > 0 then
      local pick = candidates[math.random(#candidates)]
      return { species = pick.species, level = pick.level }
    end
    return nil
  end

  -- AUTO-REPEL: the strongest repel in the bag (MAX > SUPER > plain), or
  -- nil when there is nothing to use
  mod.exports.autoRepel = function(save)
    local inv = save and save.inventory
    if not inv then return nil end
    for _, id in ipairs({ "MAX_REPEL", "SUPER_REPEL", "REPEL" }) do
      if inv[id] and inv[id] > 0 then return id end
    end
    return nil
  end

  -- consume the auto-repel and re-arm save.repelSteps; returns the item
  -- used, or nil when the bag has none
  mod.exports.applyAutoRepel = function(save)
    local id = mod.exports.autoRepel(save)
    if not id then return nil end
    require("src.inventory.Bag").remove(save, id, 1)
    save.repelSteps = id == "REPEL" and 100
                      or id == "SUPER_REPEL" and 200 or 250
    return id
  end

  -- AUTO-REPEL toast: consume the refill and arm the on-screen banner
  -- that announces it; returns the item used, or nil when the bag has
  -- none.  `now` is the toast clock (love.timer.getTime in game; the
  -- headless suite passes its own so expiry is deterministic).
  mod.exports.setAutoRepelToast = function(text, now)
    autoRepelToast = { text = text,
                       expire = (now or 0) + TOAST_SECONDS }
  end

  mod.exports.autoRepelToastText = function(now)
    if autoRepelToast and autoRepelToast.expire > (now or 0) then
      return autoRepelToast.text
    end
    autoRepelToast = nil
    return nil
  end

  mod.exports.autoRepelToastFor = function(save, data, now)
    local id = mod.exports.applyAutoRepel(save)
    if id then
      local def = data and data.items and data.items[id]
      local name = def and def.name or id
      mod.exports.setAutoRepelToast(Strings("USED %s!", name), now)
      return id
    end
    return nil
  end

  -- MAP LOCATION: the display name for a map -- a corrected name for the
  -- ids whose town-map entry lies (the Route 10 PokeCenter is "ROCK
  -- TUNNEL" there), else the town map's name for the id, else the map's
  -- own label split at case boundaries (FixTown -> FIX TOWN), else the
  -- id itself.  Pure, so the headless suite asserts it.
  mod.exports.locationName = function(data, mapId, map)
    local override = MAP_LOCATION_NAMES[mapId]
    if override then return override end
    local townMap = data and data.field and data.field.townMap
    local locations = townMap and (townMap.locations or townMap)
    local entry = type(locations) == "table" and locations[mapId]
    local name = type(entry) == "table" and entry.name
    local def = map and map.def or (data and data.maps and data.maps[mapId])
    if not name and def and type(def.label) == "string" then
      -- FixTown -> FIX TOWN, CeladonMansion1F -> CELADON MANSION 1F
      name = def.label:gsub("(%l)(%u)", "%1 %2"):gsub("(%l)(%d)", "%1 %2")
    end
    return (name or tostring(mapId):gsub("_", " ")):upper()
  end

  -- MAP LOCATION toast: the same on-screen slot as the AUTO-REPEL banner
  -- (one draw wrap renders both -- the last armed toast wins)
  mod.exports.setLocationToast = function(name, now)
    mod.exports.setAutoRepelToast(name, now)
  end

  -- the onStepComplete pre-refill: autoRepelToastFor plus one extra step
  -- so vanilla's own decrement (repelSteps = repelSteps - 1) lands on the
  -- item's exact count; returns the item used, or nil when there was
  -- nothing to refill with
  mod.exports.refillForStep = function(save, data, now)
    local id = mod.exports.autoRepelToastFor(save, data, now)
    if id and save then save.repelSteps = save.repelSteps + 1 end
    return id
  end

  -- BULK COINS: the Celadon Game Corner clerk's quantity tiers (20¥ per
  -- coin, the vanilla rate).  The 50-coin tier keeps vanilla's gate
  -- (refuse only when the case has < 10 coins of room); the bulk tiers
  -- need real room or the money is wasted on coins the 9999 cap eats.
  local COIN_RATE = 20
  mod.exports.coinOptions = function(coins, bulk)
    local options = {}
    coins = coins or 0
    if coins < 9990 then
      options[#options + 1] = { qty = 50, cost = 50 * COIN_RATE }
    end
    if bulk then
      if coins + 500 <= 9999 then
        options[#options + 1] = { qty = 500, cost = 500 * COIN_RATE }
      end
      if coins + 9999 <= 9999 then
        options[#options + 1] = { qty = 9999, cost = 9999 * COIN_RATE }
      end
    end
    return options
  end

  -- the clerk's offer line: the vanilla flow keeps the extracted text
  -- byte-for-byte; the bulk path keeps the welcome page (up to the first
  -- page break) and re-asks with a yes/no prompt of its own
  mod.exports.clerkOffer = function(raw, bulk)
    if not bulk then return raw end
    local welcome = raw:match("^([^\f]+)") or raw
    return welcome .. "\fWould you like to\npurchase some\nCOINS?"
  end

  -- deduct money and grant coins (clamped to the 9999 cap); false when
  -- the player cannot afford the tier
  mod.exports.buyCoins = function(save, qty)
    local cost = qty * COIN_RATE
    if not save or save.money < cost then return false end
    save.money = save.money - cost
    save.coins = math.min(9999, (save.coins or 0) + qty)
    return true
  end

  -- the CUSTOM picker: four digit boxes (each 1-9, up/down cycles with
  -- wrap), left/right moves the active box; A confirms the 4-digit
  -- amount, B cancels back to the HOW MANY? list.  Opaque so the list
  -- beneath is not drawn at all (no text can peek around the panel),
  -- and the panel itself is a full white sheet (the mod's white-pass
  -- idiom).  Exported so the headless suite can drive it.
  local CoinDigitPicker = {}
  CoinDigitPicker.__index = CoinDigitPicker
  CoinDigitPicker.isOpaque = true

  function CoinDigitPicker.new(game, opts)
    opts = opts or {}
    return setmetatable({
      game = game,
      digits = { 1, 1, 1, 1 },
      box = 1,
      unitPrice = opts.unitPrice,
      onDone = opts.onDone,
    }, CoinDigitPicker)
  end

  function CoinDigitPicker:value()
    return self.digits[1] * 1000 + self.digits[2] * 100
         + self.digits[3] * 10 + self.digits[4]
  end

  function CoinDigitPicker:update(dt)
    local input = self.game.input
    if input:wasPressed("up") then
      self.digits[self.box] = (self.digits[self.box] + 1) % 10
    elseif input:wasPressed("down") then
      self.digits[self.box] = (self.digits[self.box] - 1) % 10
    elseif input:wasPressed("left") then
      self.box = self.box > 1 and self.box - 1 or 4
    elseif input:wasPressed("right") then
      self.box = self.box < 4 and self.box + 1 or 1
    elseif input:wasPressed("a") then
      if self:value() == 0 then return end -- buying 0 coins is meaningless
      self.game.stack:pop()
      if self.onDone then self.onDone(self:value()) end
    elseif input:wasPressed("b") then
      self.game.stack:pop()
      if self.onDone then self.onDone(nil) end
    end
  end

  function CoinDigitPicker:draw()
    local Font = require("src.render.Font")
    local g = love.graphics
    -- full white sheet: covers the HOW MANY? list underneath (opaque,
    -- so the list is not drawn at all) with nothing peeking at the seams
    Font.drawBox(0, 0, 20, 18)
    -- title
    g.setColor(0, 0, 0, 1)
    Font.draw("CUSTOM", 56, 20)
    -- the four digit boxes: 3x3 tiles (24x24), so the glyph sits in the
    -- exact center cell, one tile clear of the border on every side
    for i = 1, 4 do
      local tx = 1 + (i - 1) * 5
      Font.drawBox(tx, 6, 3, 3)
      g.setColor(0, 0, 0, 1)
      Font.draw(tostring(self.digits[i]), (tx + 1) * 8, 56)
      g.setColor(1, 1, 1, 1)
    end
    -- the active box's cursor (the engine's more-arrow glyph)
    g.setColor(0, 0, 0, 1)
    Font.drawCode(0xEE, (1 + (self.box - 1) * 5) * 8 + 8, 72)
    -- the live price, centered
    local price = ("¥%d"):format(self:value() * (self.unitPrice or 0))
    Font.draw(price, math.floor((160 - Font.width(price)) / 2), 88)
    g.setColor(1, 1, 1, 1)
  end

  mod.exports.coinDigitPicker = CoinDigitPicker.new

  -- RUN (HOLD B): halve the per-step frame count (double foot speed)
  -- while B is held, off the bike and off the surfboard
  mod.exports.runFrames = function(frames, ctx)
    if get("run_hold_b") and not (ctx and (ctx.onBike or ctx.surfing))
       and ctx and ctx.input and ctx.input:isDown("b") then
      return frames / 2
    end
    return frames
  end

  -- ---------------------------------------------------- BATTLE PALACE AI

  -- Emerald's Palace table stores cumulative Attack/Defense thresholds for
  -- each nature, with a second table below half HP.  Gen 1 has no nature
  -- byte, so the mod chooses an approximate Palace nature from the
  -- mon's four stored DVs and its stat EXP. This is deliberately a
  -- transparent approximation rather than pretending the original nature
  -- exists. Emerald does not define a DV-to-Nature mapping; Attack/Defense/
  -- Speed/Special are ranked here, and the dominant axis selects the closest
  -- Palace style. Stat EXP affects the rank because it affects the actual
  -- Gen 1 stat calculation.
  local PALACE_STYLES = {
    HARDY   = { 61, 68, 61, 68 }, LONELY  = { 20, 45, 84, 92 },
    BRAVE   = { 70, 85, 32, 92 }, ADAMANT = { 38, 69, 70, 85 },
    NAUGHTY = { 20, 90, 70, 92 }, BOLD    = { 30, 50, 32, 90 },
    DOCILE  = { 56, 78, 56, 78 }, RELAXED = { 25, 40, 75, 90 },
    IMPISH  = { 69, 75, 28, 83 }, LAX     = { 35, 45, 29, 35 },
    TIMID   = { 62, 72, 30, 50 }, HASTY   = { 58, 95, 88, 94 },
    SERIOUS = { 34, 45, 29, 40 }, JOLLY   = { 35, 40, 35, 95 },
    NAIVE   = { 56, 78, 56, 78 }, MODEST  = { 35, 80, 34, 94 },
    MILD    = { 44, 94, 34, 40 }, QUIET   = { 56, 78, 56, 78 },
    BASHFUL = { 30, 88, 30, 88 }, RASH    = { 30, 43, 27, 33 },
    CALM    = { 40, 90, 25, 87 }, GENTLE  = { 18, 88, 90, 95 },
    SASSY   = { 88, 94, 22, 42 }, CAREFUL = { 42, 92, 42, 47 },
    QUIRKY  = { 56, 78, 56, 78 },
  }

  local function statExpValue(v)
    -- Match Stats.calc's contribution: floor(ceil(sqrt(exp))/4).
    return math.floor(math.min(255, math.ceil(math.sqrt(v or 0))) / 4)
  end

  local function palaceStat(mon, key)
    local dvs = mon and mon.dvs or {}
    local exp = mon and mon.statExp or {}
    return (dvs[key] or 0) * 2 + statExpValue(exp[key])
  end

  mod.exports.palaceNature = function(mon)
    local atk = palaceStat(mon, "attack")
    local def = palaceStat(mon, "defense")
    local spd = palaceStat(mon, "speed")
    local spc = palaceStat(mon, "special")
    local values = { attack = atk, defense = def, speed = spd, special = spc }
    local high = "attack"
    for _, key in ipairs({ "defense", "speed", "special" }) do
      if values[key] > values[high] then high = key end
    end
    -- Ties in the weakest axis are resolved toward the conventional nature
    -- for that boosted stat: Speed-only becomes Timid, Attack-only Lonely,
    -- Defense-only Bold, and Special-only Mild.
    local lowOrder = {
      attack = { "defense", "speed", "special" },
      defense = { "attack", "speed", "special" },
      speed = { "attack", "defense", "special" },
      special = { "attack", "defense", "speed" },
    }
    local low = lowOrder[high][1]
    for _, key in ipairs(lowOrder[high]) do
      if values[key] < values[low] then low = key end
    end
    local pair = high .. ":" .. low
    local mapped = {
      ["attack:defense"] = "LONELY", ["attack:speed"] = "ADAMANT",
      ["attack:special"] = "NAUGHTY", ["defense:attack"] = "BOLD",
      ["defense:speed"] = "MODEST", ["defense:special"] = "CALM",
      ["speed:attack"] = "TIMID", ["speed:defense"] = "HASTY",
      ["speed:special"] = "JOLLY", ["special:attack"] = "MILD",
      ["special:defense"] = "GENTLE", ["special:speed"] = "RASH",
    }
    -- If the spread is too small to express a meaningful preference, use
    -- Hardy. Otherwise choose the Gen 3 nature whose raised/lowered axes
    -- match the largest and smallest Gen 1 stat contributions.
    local spread = values[high] - values[low]
    if spread < 4 then return "HARDY" end
    return mapped[pair] or "HARDY"
  end

  mod.exports.palaceCategory = function(nature, lowHp, roll)
    local s = PALACE_STYLES[nature] or PALACE_STYLES.HARDY
    local i = lowHp and 3 or 1
    roll = roll or math.random(0, 99)
    if roll < s[i] then return "attack" end
    if roll < s[i + 1] then return "defense" end
    return "support"
  end

  -- Emerald's GetBattlePalaceMoveGroup classifies by static target and
  -- power only. Gen 1's extractor does not currently expose the ROM target,
  -- so the port uses the closest available representation: the target field
  -- when present, and the Gen 1 effect enum in its place.  This deliberately
  -- does not inspect effects beyond identifying the self-targeting moves:
  -- a non-damaging selected-target move is Support, while a powered
  -- selected-target move is Attack, exactly as Palace does.
  --
  -- The Gen 1 effect constants below are the moves the ROM's target data
  -- would mark MOVE_TARGET_USER (stat boosts, recovery, Substitute, Splash,
  -- Transform, Conversion, Mist, Light Screen, Reflect, Focus Energy) —
  -- Defense, exactly as GetBattlePalaceMoveGroup groups them.  Without this
  -- the extractor's missing target field leaves Defense structurally empty
  -- and every Defense roll falls through to the empty-category fallback.
  local PALACE_DEFENSE_EFFECTS = {
    ATTACK_UP1_EFFECT = true, ATTACK_UP2_EFFECT = true,
    DEFENSE_UP1_EFFECT = true, DEFENSE_UP2_EFFECT = true,
    SPEED_UP1_EFFECT = true, SPEED_UP2_EFFECT = true,
    SPECIAL_UP1_EFFECT = true, SPECIAL_UP2_EFFECT = true,
    EVASION_UP1_EFFECT = true, ACCURACY_UP1_EFFECT = true,
    HEAL_EFFECT = true, SPLASH_EFFECT = true, SUBSTITUTE_EFFECT = true,
    TRANSFORM_EFFECT = true, CONVERSION_EFFECT = true, MIST_EFFECT = true,
    LIGHT_SCREEN_EFFECT = true, REFLECT_EFFECT = true,
    FOCUS_ENERGY_EFFECT = true,
  }

  mod.exports.palaceMoveGroup = function(move)
    if not move then return "attack" end
    local target = move.target
    -- This mirrors GetBattlePalaceMoveGroup exactly where the extractor gives
    -- us the modern target names: USER is Defense; DEPENDS and
    -- OPPONENTS_FIELD are Support; all other targets are Attack iff power is
    -- nonzero, otherwise Support.
    if target == "user" or target == "user_side" then
      return "defense"
    end
    if target == "depends" or target == "opponents_field"
       or target == "field" then
      return "support"
    end
    if target == "user_or_selected_user" or target == "selected"
       or target == "random" or target == "both"
       or target == "foes_and_ally" then
      return (move.power or 0) == 0 and "support" or "attack"
    end
    -- No target in the Gen 1 data: the self-targeting effects above stand
    -- in for MOVE_TARGET_USER.
    if PALACE_DEFENSE_EFFECTS[move.effect] then
      return "defense"
    end
    if move.id == "COUNTER" or move.id == "MIRROR_COAT"
       or move.id == "MIMIC" or move.id == "METRONOME"
       or move.id == "MIRROR_MOVE" or move.id == "NATURE_POWER" then
      return "support"
    end
    -- Gen 1's imported records usually omit target. These fixed-damage
    -- attacks have power 1 in Emerald but may be represented with dummy/zero
    -- power by the Gen 1 extractor, so identify them explicitly.
    if move.id == "DRAGON_RAGE" or move.id == "NIGHT_SHADE"
       or move.id == "PSYWAVE" or move.id == "SEISMIC_TOSS"
       or move.id == "SONICBOOM" then
      return "attack"
    end
    if (move.power or 0) == 0 then return "support" end
    return "attack"
  end

  -- Pure move chooser used by the live auto-battle seam and by the suite.
  -- The first pass preserves the Palace's category probability. If the
  -- category is empty, Emerald falls back to a usable move and applies its
  -- 50% incapability roll; this function returns nil for that skipped turn.
  mod.exports.palaceChooseMove = function(battle, battler, target, opts)
    opts = opts or {}
    local moves, grouped = {}, { attack = {}, defense = {}, support = {} }
    local unlimited = opts.unlimited
    if unlimited == nil then
      unlimited = not battler.isPlayer
                 and battle and battle.ruleset
                 and battle.ruleset.enemyUnlimitedPP or false
    end
    for i, mv in ipairs((battler and battler.curMoves) or {}) do
      if mv.id and (unlimited or (mv.pp or 0) > 0)
         and battler.disabledSlot ~= i then
        local def = battle and battle.data and battle.data.moves[mv.id] or mv
        local copy = { id = mv.id, pp = mv.pp, _index = i }
        local group = mod.exports.palaceMoveGroup(def)
        moves[#moves + 1] = copy
        grouped[group][#grouped[group] + 1] = copy
      end
    end
    if #moves == 0 then
      -- No usable moves (all PP spent / every slot disabled): vanilla Gen 1
      -- engages Struggle -- BattleState's own no-PP path and the trainer AI
      -- both hand resolveTurn this exact action shape, recoil included.  The
      -- mon acts instead of skipping the turn with the Palace incapability
      -- message.
      return { id = "STRUGGLE", pp = 1, struggle = true }
    end
    local rng = opts.rng or (battle and battle.rng) or math.random
    local roll = opts.categoryRoll
    if roll == nil then roll = rng(0, 99) end
    local nature = opts.nature or mod.exports.palaceNature(battler.mon)
    local maxHp = battler.mon.stats and battler.mon.stats.hp or 0
    -- Emerald latches the low-HP style after a switch. Mirror that on the
    -- battler object: healing above half HP does not restore the normal table,
    -- while switching creates a fresh battler and clears the latch.
    if not battler._qolPalaceLowHp and battler.mon.hp > 0
       and battler.mon.hp <= math.floor(maxHp / 2)
       and battler.mon.status ~= "SLP" then
      battler._qolPalaceLowHp = true
    end
    local lowHp = battler._qolPalaceLowHp == true
    local category = mod.exports.palaceCategory(nature, lowHp, roll)
    local selected = grouped[category]
    if #selected > 0 then
      -- Emerald passes the category mask to its ordinary AI rather than
      -- choosing uniformly. Reuse Gen 1's existing scoring layers against
      -- the opponent, restricted to this category; when a headless seam
      -- lacks the target substrate, keep the deterministic random fallback.
      if not opts.randomWithinCategory and target and target.curTypes
         and target.mon and battle and battle.data
         and battle.data.type_chart then
        local TrainerAI = require("src.battle.TrainerAI")
        local proxy = {}
        for k, v in pairs(battler) do proxy[k] = v end
        proxy.curMoves, proxy.disabledSlot, proxy.aiLayer2 = selected, nil, 0
        local aiBattle = {}
        for k, v in pairs(battle or {}) do aiBattle[k] = v end
        aiBattle.player = target
        aiBattle.enemyAIMods = opts.aiMods or { 1, 2, 3 }
        local picked = TrainerAI.chooseMove(proxy, rng, aiBattle)
        if picked then return picked end
      end
      local selectedIndex = opts.moveRoll
      if selectedIndex == nil then selectedIndex = rng(1, #selected) end
      -- The ordinary Gen 1 trainer AI has no separate Palace mask API, so
      -- the pure seam uses its existing scoring only when callers provide a
      -- complete battle target/type substrate. Live battles use the explicit
      -- random tie path below until that mask is made a first-class engine
      -- service; category selection itself remains Palace-faithful.
      return selected[selectedIndex]
    end
    -- Emerald's fallback prefers the sole category that has >=2 usable
    -- moves; otherwise it samples all usable slots. The released Emerald
    -- build has a support-counting bug, so Support is omitted from this
    -- "multiple moves" test unless a caller explicitly asks for the
    -- intended BUGFIX behavior.
    local multiGroups = {}
    for _, group in ipairs({ "attack", "defense", "support" }) do
      local count = #grouped[group]
      if count >= 2 and (group ~= "support" or opts.bugfixSupportCount) then
        multiGroups[#multiGroups + 1] = group
      end
    end
    local fallbackPool = moves
    if #multiGroups == 1 then fallbackPool = grouped[multiGroups[1]] end
    local fallbackIndex = opts.fallbackRoll or rng(1, #fallbackPool)
    local fallback = fallbackPool[fallbackIndex]
    if opts.fallbackIncapable then return nil end
    -- Emerald's released build rolls a 50% chance to skip the turn with
    -- "couldn't use its power!" when the chosen category is empty.  The Gen 1
    -- port's categories are approximations (the extractor omits the target
    -- field Palace groups by), so empty categories are far more common than
    -- in Emerald and the skip would spam the message.  The QoL default
    -- always uses a move; an explicit opts.fallbackChance (0-99) re-enables
    -- the Emerald roll -- >= 50 skips the turn.
    local failRoll = opts.fallbackChance
    if failRoll ~= nil and failRoll >= 50 then return nil end
    return fallback
  end

  mod.exports.autoBattleShouldAct = function(battle)
    if not get("auto_battler") or not battle
       or (battle.phase ~= "menu" and not battle._qolAutoBattleProbe)
       or battle.demo or battle.safari or battle.ghost
       or battle.kind == "link" or battle.spectating
       or not battle.player or not battle.player.mon
       or not battle.enemy or battle.player.mon.hp <= 0 then
      return false
    end
    if battle.menuLockedAction and battle:menuLockedAction(battle.player) then
      return false
    end
    return true
  end

  mod.exports.autoBattleUpdate = function(battle, vanillaUpdate, dt)
    if not mod.exports.autoBattleShouldAct(battle) then
      return vanillaUpdate(battle, dt)
    end
    local player = battle.player
    local proposed = player.curMoves and player.curMoves[battle.moveIndex]
    local action = mod.exports.autoBattleAction(battle, proposed)
    if action == proposed and proposed == nil then
      return vanillaUpdate(battle, dt)
    end
    battle._qolAutoBattleResolving = true
    battle.phase = "messages"
    battle.afterQueue = "menu"
    local ok, result = pcall(battle.resolveTurn, battle, action)
    battle._qolAutoBattleResolving = nil
    if not ok then error(result, 0) end
    return true
  end

  -- Action helper used by the guarded BattleState update wrapper below.
  -- It remains exported so the headless suite can exercise the seam without
  -- fabricating controller input.
  mod.exports.autoBattleAction = function(battle, proposed)
    if not get("auto_battler") or not battle
       or battle.demo or battle.safari or battle.ghost
       or battle.kind == "link" or battle.spectating
       or not battle.player or not battle.player.mon
       or not battle.enemy then
      return proposed
    end
    local locked = battle.fightLockedAction
                   and battle:fightLockedAction(battle.player)
    if locked then return proposed end
    local action = mod.exports.palaceChooseMove(battle, battle.player,
                                                 battle.enemy,
                                                 { unlimited = false })
    if action then return action end
    -- The native Palace prints this message and skips the player's action.
    -- The resolveTurn wrapper treats nil as a lost player turn.
    local say = battle.say or battle.sayNext
    if say and battle.player then
      say(battle, Strings("%s\nis incapable of\nusing its power!",
                          battle.player.name or "POKéMON"))
    end
    return nil
  end

  -- REMEMBER MOVE: the battle object already keeps moveIndex across
  -- turns; with the toggle OFF the end of every turn parks it back on
  -- the first move, the vanilla default
  mod.exports.applyMoveRemember = function(battle, remember)
    if battle and not remember then battle.moveIndex = 1 end
    return battle and battle.moveIndex or nil
  end

  -- KEEP MONEY: snapshot before the halving sites run, restore on the
  -- blackout event (the halving has already happened by then)
  mod.exports.snapshotMoney = function(save)
    if save then blackoutKeepMoney = save.money end
  end

  mod.exports.keepMoneyRestore = function(save)
    if save and blackoutKeepMoney ~= nil then
      save.money = blackoutKeepMoney
      blackoutKeepMoney = nil
    end
  end

  -- LAST ITEM (M) in battle: spend the turn using the last item the bag
  -- used, the way selecting it from BAG would.  Balls throw at the foe
  -- (battle:throwBall); items that need a party target (potions, status
  -- cures, revives, ETHERs) open the vanilla party screen so the player
  -- picks the mon -- ETHERs/PP UP then ask for the move, exactly like the
  -- bag; targetless battle items (X items, POKé FLUTE, POKé DOLL) run
  -- straight on the active battler.  A failed use shows the vanilla
  -- refusal text and does NOT spend the turn, exactly like the bag.  With
  -- nothing recorded (or the item gone) the bag opens normally so the
  -- player can pick the next item.  Returns true when an action was taken.
  mod.exports.useLastItem = function(battle)
    if not (battle and battle.game) then return nil end
    local game = battle.game
    local save = game.save
    local id = lastItemId
    local left = id and save and save.inventory and save.inventory[id]
    if not id or not left or left <= 0 then
      if battle.openItems then battle:openItems() end
      return nil
    end
    local ItemEffects = require("src.inventory.ItemEffects")
    local TextBox = require("src.render.TextBox")
    local function say(msgs, onDone)
      if not msgs or #msgs == 0 then
        if onDone then onDone() end
        return
      end
      game.stack:push(TextBox.new(game, table.concat(msgs, "\f"), onDone))
    end
    -- the battle-use tail, BagMenu's useOn subset: the item lands on the
    -- chosen target, the turn is spent when the text box closes
    local function runUse(target, moveIndex)
      local result, payload, extra = ItemEffects.use(game.data, save, id,
                                                     target, battle, moveIndex,
                                                     game.overworld)
      if result == "consumed" then
        require("src.inventory.Bag").remove(save, id, 1)
        say(payload, function() battle:itemUsed({}) end)
      elseif result == "consumed_escape" then -- POKé DOLL
        require("src.inventory.Bag").remove(save, id, 1)
        say(payload, function()
          battle.pokeDollEscape = true
          battle.result = "run"
          battle.afterQueue = "finish"
          battle.phase = "messages"
        end)
      elseif result == "flute" then
        require("src.core.Sound").play(game.data, "Pokeflute")
        say(payload, function() battle:itemUsed({}) end)
      else -- "failed" (and anything unexpected): text only, turn not spent
        say(payload)
      end
    end
    battle.phase = "messages"
    battle.afterQueue = "menu"
    if ItemEffects.isBall(id) then
      require("src.inventory.Bag").remove(save, id, 1)
      battle:throwBall(id)
      return true
    end
    local def = game.data.items[id]
    -- target-needing items open the vanilla party picker (the party
    -- screen) instead of auto-targeting: potions and status cures reach
    -- any party member, and ETHERs/PP UP ask for the move, just as they
    -- do from BAG.  The picker pops itself before onSwitch (keepOpen
    -- false in battle), so a cancel simply hands back to the battle menu.
    if ItemEffects.needsTarget(id, def) then
      local wantsMove = id == "ETHER" or id == "MAX_ETHER" or id == "PP_UP"
      local opts = {
        pickOnly = true,
        keepOpen = false,
        onSwitch = function(mon, picker)
          if not wantsMove then
            runUse(mon, nil)
            return
          end
          local rows = {}
          for mi, mv in ipairs(mon.moves) do
            local mdef = game.data.moves[mv.id]
            table.insert(rows, {
              value = mi,
              label = mdef and mdef.name or mv.id,
              right = ("%d"):format(mv.pp),
            })
          end
          game.stack:push(require("src.ui.ListMenu").new(game,
            "Which move?", rows, {
            onChoose = function(row, l)
              l:close()
              runUse(mon, row.value)
            end,
          }))
        end,
      }
      if def and def.machine then
        opts.tmhm = { move = def.machine.move, kind = def.machine.kind }
      end
      require("src.ui.Screens").push(game, "PartyMenu", opts)
      return true
    end
    -- targetless battle items (X items, POKé FLUTE, POKé DOLL) run
    -- straight on the active battler
    runUse(nil, nil)
    return true
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
  -- one whose species can learn it.  The allMoves fallback (the phantom
  -- case) honours HM ITEM REQUIRED: HM moves need the item held, like
  -- the party-menu list; a mon that already knows the move is never
  -- gated (it had the HM to learn it).
  mod.exports.eligibleMon = function(party, data, moveId, allMoves,
                                     inventory, requireHm)
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
        if def and canLearn(def, moveId) then
          local item = HM_ITEMS[moveId]
          if not requireHm or not item or (inventory and inventory[item]) then
            return mon
          end
        end
      end
    end
    return nil
  end

  -- the field moves this species can learn (level-up or TM/HM) but does
  -- not currently know; HM moves drop out while HM ITEM REQUIRED is on
  -- and the player does not hold the item
  mod.exports.learnableFieldMoves = function(def, mon, inventory, requireHm)
    local out = {}
    for _, id in ipairs(FIELD_MOVES) do
      if def and canLearn(def, id) and not knows(mon, id) then
        local item = HM_ITEMS[id]
        if not requireHm or not item or (inventory and inventory[item]) then
          out[#out + 1] = id
        end
      end
    end
    return out
  end

  -- append phantom move slots so the vanilla party-menu list builder shows
  -- learnable field moves; returns the added ids for detachPhantomMoves
  mod.exports.attachPhantomMoves = function(mon, def, inventory, requireHm)
    local added = mod.exports.learnableFieldMoves(def, mon, inventory,
                                                  requireHm)
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
                                             game.data.pokemon[mon.species],
                                             game.save and game.save.inventory,
                                             get("hm_item_required"))
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

  -- UNLIMITED TMs: the engine returns "learn" for a TM that teaches a
  -- move -- the signal that consumes it in BagMenu -- and "learnkept" for
  -- HMs (never consumed).  Remapping "learn" -> "learnkept" while the
  -- toggle is on covers every teach path: <4 moves, 4+ moves through the
  -- forget UI, and the battle screen.
  mod.exports.keepTm = function(result)
    if get("unlimited_tms") and result == "learn" then return "learnkept" end
    return result
  end

  -- REMEMBER CURSOR: the battle menu keeps menuIndex on the battle
  -- object, so the FIGHT/BAG/PKMN/RUN cursor already stays put across
  -- turns; with the toggle OFF, the end of every turn parks it back on
  -- FIGHT, the vanilla default.  Returns the cursor's landing position
  -- so tests can assert the call both ways.
  mod.exports.applyCursorRemember = function(battle, remember)
    if battle and not remember then battle.menuIndex = 1 end
    return battle and battle.menuIndex or nil
  end

  -- FORGETTABLE HMs: MoveLearnMenu.update blocks the HM moves through a
  -- module-local HM_MOVES table, so while the toggle is on the wrap below
  -- swaps in this gate-free copy of the same update (the vanilla body
  -- minus the HMCantDeleteText check -- keep it in lockstep with
  -- src/ui/MoveLearnMenu.lua).  The selecting guard is "== false" (not
  -- "not selecting"): engine builds v0.1.59..v0.1.63 ran the old
  -- ChoiceBox flow and never set selecting at all (nil), with the forget
  -- list live whenever the menu is top -- treating nil as "not yet
  -- choosing" would disable the toggle on those builds and the vanilla
  -- HM gate would fire even with FORGETTABLE HMs on.
  mod.exports.forgetUpdate = function(self, dt)
    if self.selecting == false then return end
    local input = self.game.input
    local n = #self.mon.moves + 1 -- moves + CANCEL
    if input:wasPressed("up") then
      self.index = self.index > 1 and self.index - 1 or n
    elseif input:wasPressed("down") then
      self.index = self.index < n and self.index + 1 or 1
    elseif input:wasPressed("b") then
      self:confirmAbandon()
    elseif input:wasPressed("a") then
      if self.index > #self.mon.moves then
        self:confirmAbandon()
      else
        local old = self.mon.moves[self.index]
        local mdef = self.game.data.moves[self.newMoveId]
        self.mon.moves[self.index] = { id = self.newMoveId, pp = mdef.pp }
        self.forgot = self.game.data.moves[old.id].name
        self:finish(true)
      end
    end
  end

  -- one wrap per session; hot reload re-runs entry chunks
  if Game._qolTogglesInstalled then return end
  Game._qolTogglesInstalled = true

  -- Save-scoped flags belong in mod.save, not the global options bucket:
  -- starting another save must get its own S.S. Anne prompt state.
  local function getSaveFlag(key)
    return mod.save:get(key, false) == true
  end

  local function setSaveFlag(key, value)
    mod.save:set(key, value == true)
  end

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
      if getSaveFlag("ssanne_prompted") then return true end
      setSaveFlag("ssanne_prompted", true)
      return false -- one vanilla prompt, then straight through
    end,
  })

  -- BULK COINS: the Celadon Game Corner clerk is a talk script, and talk
  -- entries are single-winner, so this handler replaces the base one for
  -- both clerk text ids (Red's CLERK1 and Yellow's CLERK alias).  The
  -- OFF path below replicates the vanilla flow byte-for-byte -- same
  -- texts, same gates -- and the ON path swaps the fixed 50-coin offer
  -- for a HOW MANY? list of the tiers that fit the coin case.
  local function gameCornerClerk(game, ow, npc, done)
    local TextBox = require("src.render.TextBox")
    local ListMenu = require("src.ui.ListMenu")
    local Font = require("src.render.Font")
    local t = game.data.text
    local function line(suffix, fallback)
      return t["_GameCornerClerk1" .. suffix]
             or t["_GameCornerClerk" .. suffix]
             or fallback
    end
    -- GameCornerDrawCoinBox: the money/coin window stands for the whole
    -- exchange (a draw-only state under the dialogue, redrawn every
    -- frame from the live save)
    local coinBox = { draw = function()
      Font.drawBox(11, 0, 9, 7)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(Strings("MONEY"), 96, 16)
      local money = ("¥%d"):format(game.save.money or 0)
      Font.draw(money, 152 - Font.width(money), 24)
      Font.draw(Strings("COIN"), 96, 32)
      local coins = ("%d"):format(game.save.coins or 0)
      Font.draw(coins, 152 - Font.width(coins), 40)
      love.graphics.setColor(1, 1, 1, 1)
    end }
    game.stack:push(coinBox)
    local function finish()
      game.stack:pop()
      done()
    end
    local offer = line("DoYouNeedSomeGameCoinsText",
                       "Do you need some\ngame coins?\f¥1000 for 50.")
    offer = mod.exports.clerkOffer(offer, get("bulk_coins"))
    game.stack:push(TextBox.new(game, offer, nil, { choice = function(yes)
      if not yes then
        game.stack:push(TextBox.new(game,
          line("PleaseComePlaySometimeText",
               "No? Please come\nplay sometime!"), finish))
        return
      end
      if not game.save.inventory.COIN_CASE then
        game.stack:push(TextBox.new(game,
          line("DontHaveCoinCaseText",
               "You don't have a\nCOIN CASE!"), finish))
        return
      end
      local options = mod.exports.coinOptions(game.save.coins,
                                              get("bulk_coins"))
      if #options == 0 then
        game.stack:push(TextBox.new(game,
          line("CoinCaseIsFullText",
               "Oops! Your COIN\nCASE is full."), finish))
        return
      end
      if #options == 1 then
        -- the vanilla path: one tier, the same money gate and thanks text
        local o = options[1]
        if game.save.money < o.cost then
          game.stack:push(TextBox.new(game,
            line("CantAffordTheCoinsText",
                 "You can't afford\nthe coins!"), finish))
          return
        end
        mod.exports.buyCoins(game.save, o.qty)
        game.stack:push(TextBox.new(game,
          line("ThanksHereAre50CoinsText",
               "Thanks! Here are\nyour 50 coins!"), finish))
        return
      end
      -- the bulk path: pick the tier from a list (the prize counters in
      -- this same room use the same ListMenu idiom), with CUSTOM at the
      -- bottom opening the 4-digit picker
      local items = {}
      for _, o in ipairs(options) do
        items[#items + 1] = {
          value = o,
          label = Strings("%d COINS", o.qty),
          right = ("¥%d"):format(o.cost),
        }
      end
      items[#items + 1] = { value = "custom", label = "CUSTOM" }
      local list
      list = ListMenu.new(game, "HOW MANY?", items, {
        footer = ("COINS %d"):format(game.save.coins or 0),
        onChoose = function(item)
          if item.value == "custom" then
            game.stack:push(mod.exports.coinDigitPicker(game, {
              unitPrice = COIN_RATE,
              onDone = function(qty)
                if not qty then
                  list.footer = ("COINS %d"):format(game.save.coins or 0)
                  return
                end
                local cost = qty * COIN_RATE
                if game.save.money < cost then
                  list.footer = line("CantAffordTheCoinsText",
                                     "You can't afford\nthe coins!")
                  return
                end
                if (game.save.coins or 0) + qty > 9999 then
                  list.footer = line("CoinCaseIsFullText",
                                     "Oops! Your COIN\nCASE is full.")
                  return
                end
                mod.exports.buyCoins(game.save, qty)
                list:close()
                game.stack:push(TextBox.new(game,
                  Strings("Thanks! Here are\nyour %d coins!", qty), finish))
              end,
            }))
            return
          end
          local o = item.value
          if game.save.money < o.cost then
            list.footer = line("CantAffordTheCoinsText",
                               "You can't afford\nthe coins!")
            return
          end
          mod.exports.buyCoins(game.save, o.qty)
          list:close()
          game.stack:push(TextBox.new(game,
            Strings("Thanks! Here are\nyour %d coins!", o.qty), finish))
        end,
        onCancel = finish,
      })
      game.stack:push(list)
    end }))
  end

  mod.content.map_scripts:register("GAME_CORNER", {
    talk = {
      TEXT_GAMECORNER_CLERK1 = gameCornerClerk,
      TEXT_GAMECORNER_CLERK = gameCornerClerk,
    },
  })

  -- ------------------------------------------------------- the OPTIONS row

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    rows = next(game, rows)
    rows[#rows + 1] = {
      id = "qolToggles",
      label = Strings("QOL TOGGLES"),
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
    -- advance the label tickers (the OptionRows.draw wrap reads row.tick)
    for _, row in ipairs(self.rows or {}) do
      if row.ticker then row.tick = (row.tick or 0) + (dt or 0) end
    end
    local input = self.game.input
    -- START is read from the normal input edge here rather than from a raw
    -- Game:gamepadpressed wrapper.  That leaves the engine's controller
    -- dispatch untouched, which is important for the overworld's Start menu.
    local startHelp = input:wasPressed("start")
    if self.helpRow then
      -- popup mode: B closes it, and a START/P press while it is up closes
      -- it too (the latch is consumed here, so it can never re-open the
      -- popup the instant it closes)
      self.helpTick = (self.helpTick or 0) + (dt or 0)
      local close = input:wasPressed("b") or startHelp
      if helpRequested then
        helpRequested = false
        close = true
      end
      if close then self.helpRow = nil end
      return
    end
    -- START (controller) / P (keyboard) on a row opens its full-screen
    -- help popup; the popup owns the frame, so the list input below waits
    if helpRequested or startHelp then
      helpRequested = false
      local row = self.rows[self.index]
      if row and row.help then
        self.helpRow = row
        self.helpTick = 0
        return
      end
    end
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
    if self.helpRow then
      -- full-screen popup, the Mods Hotkeys capture idiom: a white pass
      -- first so the underlying rows can never peek through the box seams
      local Font = require("src.render.Font")
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      -- title box (0,1,20,3): border rows y=8/24, interior row y=16
      Font.drawBox(0, 1, 20, 3)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(self.helpRow.label, 16, 16)
      -- body box (0,4,20,9): border rows y=32/96, interior rows y=40..88,
      -- seven 17-glyph lines (the engine's 8px text pad inside the box)
      Font.drawBox(0, 4, 20, 9)
      love.graphics.setColor(0, 0, 0, 1)
      local TextBox = require("src.render.TextBox")
      local lines = TextBox.paginate(
          (self.helpRow.help or ""):gsub("\v", "\n"), 17)[1]
      -- a description taller than the box scrolls vertically (slowly, so
      -- a line can be read as it passes); the scissor keeps it inside the
      -- box interior so it never bleeds over the border or the hint box
      local overflow = (#lines - 7) * 8
      local dy = 0
      if overflow > 0 then
        dy = -vertOffset(self.helpTick or 0, overflow)
        local g = love.graphics
        if g and g.setScissor then g.setScissor(16, 40, 136, 56) end
      end
      for i, line in ipairs(lines) do
        Font.draw(line, 16, 40 + (i - 1) * 8 + dy)
      end
      if overflow > 0 then
        local g = love.graphics
        if g and g.setScissor then g.setScissor() end
      end
      -- hint box (0,13,20,3): border rows y=104/120, interior row y=112
      Font.drawBox(0, 13, 20, 3)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(Strings("B CLOSES"), 16, 112)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  mod.content.screens:register("QolTogglesMenu", { new = function(game, opts)
    opts = opts or {}
    helpRequested = false -- a stale P/START before the menu opened never fires
    return setmetatable({
      game = game,
      rows = mod.exports.toggleRows(get, set),
      index = 1, scroll = 0,
      onCancel = opts.onCancel,
      helpRow = nil, -- the row whose full-screen help popup is open
      _qolTogglesMenu = true, -- menuIsTop() latch gate (top-state check)
    }, QolTogglesMenu)
  end })

  -- P (keyboard) on a row shows its in-depth help, and M arms the LAST
  -- ITEM battle shortcut while a battle is top.  P and M use raw key input
  -- because they are not Game Boy buttons; START is read by the menu's
  -- normal input edge in QolTogglesMenu:update.  Do not wrap
  -- Game:gamepadpressed here: the engine must receive controller START so
  -- OverworldController can open the native StartMenu, including when Gen1
  -- Modern UI replaces its presenter.
  if not Game._qolTogglesHelpKeysInstalled then
    Game._qolTogglesHelpKeysInstalled = true
    local vanillaKey = Game.keypressed
    Game.keypressed = function(self, key)
      if key == "p" and menuIsTop() then helpRequested = true end
      if key == "m" and not mKeyHeld then
        mKeyHeld = true
        local battle = battleTop()
        if battle then battle._qolLastItemRequest = true end
      end
      return vanillaKey(self, key)
    end
    local vanillaKeyRel = Game.keyreleased
    Game.keyreleased = function(self, key)
      if key == "m" then mKeyHeld = false end
      return vanillaKeyRel(self, key)
    end
  end

  -- LAST ITEM (M): consume the armed request on the battle's own update,
  -- while the FIGHT/BAG/PKMN/RUN menu is actually up (phase "menu" with
  -- afterQueue "menu" -- a locked recharge/rage turn resolves to
  -- "messages", so M can never fire through a forced action).  The toggle
  -- is read at fire time, the request is dropped otherwise, and a stale
  -- request attached to a battle that left the stack simply never fires.
  local BattleState = require("src.battle.BattleState")

  -- AUTO BATTLER: resolveTurn is the player-side action seam in the current
  -- engine. The existing battle.enemy_action hook is trainer-side, so this
  -- direct method wrapper changes only a free player FIGHT action. Items,
  -- switches, and locked multi-turn actions use other paths and remain
  -- vanilla. Guard once because hot reload re-runs the entry chunk.
  if not Game._qolTogglesAutoBattlerInstalled then
    Game._qolTogglesAutoBattlerInstalled = true
    local vanillaUpdate = BattleState.update
    BattleState.update = function(self, dt)
      if not self._qolAutoBattleResolving
         and mod.exports.autoBattleShouldAct(self) then
        return mod.exports.autoBattleUpdate(self, vanillaUpdate, dt)
      end
      return vanillaUpdate(self, dt)
    end
  end

  if not Game._qolTogglesLastItemInstalled then
    Game._qolTogglesLastItemInstalled = true
    local vanillaUpdate = BattleState.update
    BattleState.update = function(self, dt)
      self._qolBattle = true
      local r1, r2 = vanillaUpdate(self, dt)
      if self._qolLastItemRequest then
        self._qolLastItemRequest = nil
        if get("last_item") and self.phase == "menu"
           and self.afterQueue == "menu"
           and not self.demo and not self.safari
           and self.player and self.player.mon
           and self.player.mon.hp > 0 then
          mod.exports.useLastItem(self)
        end
      end
      return r1, r2
    end
  end

  -- Long row labels ticker: OptionRows.draw has no clip (a label wider
  -- than the box bleeds over its border), so the wrap blanks ticker rows
  -- for the vanilla pass and redraws their label itself, scissored to the
  -- label window and offset by the ticker.  Only rows carrying row.ticker
  -- are touched; every other OptionRows user (the OPTIONS menu, the mod
  -- manager, Mods Hotkeys' own wrap) draws exactly as before.  The two
  -- wraps compose because the blank is guarded: the first wrapper to see
  -- the row saves its label and blanks it, and every wrapper after skips,
  -- so the outermost wrapper's restore is always the last write.
  if not OptionRows._qolTogglesTickerInstalled then
    OptionRows._qolTogglesTickerInstalled = true
    local vanillaRowsDraw = OptionRows.draw
    OptionRows.draw = function(game, rows, index, scroll, bottomLabel,
                               bottomRow)
      local ticked = {}
      for slot = 1, OptionRows.VISIBLE do
        local row = rows[(scroll or 0) + slot]
        if row and row.ticker and row._label == nil then
          ticked[#ticked + 1] = { slot = slot, row = row }
          row._label = row.label
          row.label = ""
        end
      end
      vanillaRowsDraw(game, rows, index, scroll, bottomLabel, bottomRow)
      for _, entry in ipairs(ticked) do
        local row = entry.row
        row.label = row._label
        row._label = nil
        local y = ((entry.slot - 1) * 4 + 1) * 8
        local g = love and love.graphics
        if g and g.setScissor then
          g.setScissor(row.ticker.x, y, row.ticker.w, 8)
        end
        Font.draw(row.label, row.ticker.x
            + tickerOffset(row.tick or 0, row.ticker.overflow), y)
        if g and g.setScissor then g.setScissor() end
      end
    end
  end

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
      -- KEEP MONEY: the poison-tick blackout halves money inside the
      -- text-box callback (async), so snapshot before vanilla runs
      if get("keep_money") then mod.exports.snapshotMoney(Game.save) end
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

  -- MOUSE CAM LOCK: Dramatic Shape's staged-battle camera is steered by
  -- the mouse through BattleCam.mouseOrbit / BattleCam.mousePitch --
  -- CamControl wraps love.mousemoved and calls those per event while a
  -- battle is live.  Replacing the two functions with toggle-gated ones
  -- cuts the mouse steering and nothing else: the right stick, a touch
  -- drag and the wheel still reach the camera, because CamControl routes
  -- those through different functions (stickOrbit / dragOrbit / stepZoom).
  -- Exported so the headless suite can drive it on a stub BattleCam;
  -- installed for real by the game.ready listener below, which resolves
  -- the DRAMATIC_SHAPE mod handle.  Without Dramatic Shape the toggle is
  -- inert (nothing to gate), and a session with it absent never wraps.
  mod.exports.installMouseCamLock = function(BattleCam)
    if not BattleCam or BattleCam._qolMouseCamLockInstalled then return end
    BattleCam._qolMouseCamLockInstalled = true
    local vanillaOrbit = BattleCam.mouseOrbit
    BattleCam.mouseOrbit = function(dx)
      if get("mouse_cam_lock") then return false end
      return vanillaOrbit(dx)
    end
    local vanillaPitch = BattleCam.mousePitch
    BattleCam.mousePitch = function(dy)
      if get("mouse_cam_lock") then return false end
      return vanillaPitch(dy)
    end
  end

  -- MOUSE CAM LOCK install: game.ready is where another mod's handle is
  -- resolvable.  Dramatic Shape exposes its lib namespace as
  -- exports.lib (its own V), and BattleCam is one of its lib/ modules.
  -- Guarded so a session without Dramatic Shape never wraps anything; the
  -- toggle stays in the submenu either way, it just has nothing to gate.
  mod.events:on("game.ready", function()
    local ds = mod:find("DRAMATIC_SHAPE")
    if not ds then return end
    local lib = ds.exports and ds.exports.lib
    if not (lib and lib.require) then return end
    local ok, BattleCam = pcall(function() return lib.require("BattleCam") end)
    if ok and BattleCam then mod.exports.installMouseCamLock(BattleCam) end
  end)

  -- LIGHTS ON / AUTO-REPEL / KEEP MONEY / AUTO CUT: overworld seams,
  -- one wrap per session (hot reload re-runs entry chunks)
  mod.events:on("game.ready", function()
    local OverworldState = require("src.world.OverworldController")
    -- LIGHTS ON: setMap arms PaletteFX for a dark map before loading it,
    -- then calls setDark.  Wrapping setDark recursively reloads the map in
    -- RED++'s baked-palette path, so make vanilla setMap take its normal
    -- FLASH-lit branch instead.  The save flag is only borrowed during the
    -- map entry and is restored immediately afterward.
    if not OverworldState._qolTogglesLightsInstalled then
      OverworldState._qolTogglesLightsInstalled = true
      local vanillaSetMap = OverworldState.setMap
      local function isDarkMap(mapId)
        local darkDef = Game.data and Game.data.field
                      and Game.data.field.darkMaps
        for _, darkMapId in ipairs(darkDef and darkDef.maps or {}) do
          if darkMapId == mapId then return true end
        end
        return false
      end
      OverworldState.setMap = function(self, mapId, ...)
        local save = Game.save
        if not (get("lights_on") and save and isDarkMap(mapId)) then
          return vanillaSetMap(self, mapId, ...)
        end
        local previousFlashLit = save.flashLit
        save.flashLit = true
        local result = { pcall(vanillaSetMap, self, mapId, ...) }
        save.flashLit = previousFlashLit
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2)
      end
    end

    -- AUTO-REPEL: refill BEFORE vanilla decrements, so the wear-off box
    -- never fires when there is a repel to take over -- the toast is the
    -- announcement.  The step count is set one higher than the item's
    -- value so vanilla's own decrement lands on the exact count; with
    -- nothing in the bag the step falls through and the vanilla wore-off
    -- box shows as usual.
    if not OverworldState._qolTogglesAutoRepelInstalled then
      OverworldState._qolTogglesAutoRepelInstalled = true
      local vanillaOnStep = OverworldState.onStepComplete
      OverworldState.onStepComplete = function(self)
        if get("auto_repel") and Game.save and Game.save.repelSteps == 1 then
          local now = (love and love.timer and love.timer.getTime)
                      and love.timer.getTime() or os.clock()
          mod.exports.refillForStep(Game.save, Game.data, now)
        end
        return vanillaOnStep(self)
      end
    end

    -- AUTO-REPEL toast draw: a transient banner across the top of the
    -- screen, drawn after the world so it shows wherever the player is
    -- walking; it never takes input and fades out on its own.  White box
    -- with black text -- the engine's palette path renders that idiom
    -- (TextBox and every menu draw the same way); white-on-black does
    -- not survive the pass.
    -- Wrap the overworld's screen-space overlay pass, not its world draw.
    -- Gen1 Modern UI's presentationStack disables the overworld presenter
    -- (and every menu layered over it, StartMenu included) when
    -- OverworldState.draw stops being the released renderer.  drawUI is
    -- the additive seam its own comment sanctions for location banners,
    -- so the toast draws there and the stock draw (and its identity)
    -- survives untouched.
    if not OverworldState._qolTogglesToastInstalled then
      OverworldState._qolTogglesToastInstalled = true
      local vanillaDrawUI = OverworldState.drawUI
      OverworldState.drawUI = function(self)
        vanillaDrawUI(self)
        local now = (love and love.timer and love.timer.getTime)
                    and love.timer.getTime() or os.clock()
        local text = mod.exports.autoRepelToastText(now)
        if not text then return end
        local Font = require("src.render.Font")
        local g = love.graphics
        local w = Font.width(text)
        local bw = w + 16
        local bx = math.floor((160 - bw) / 2)
        -- fade out over the last half second of the window
        local alpha = math.min(1, (autoRepelToast.expire - now) / 0.5)
        g.setColor(1, 1, 1, alpha)
        g.rectangle("fill", bx, 8, bw, 16)
        g.setColor(0, 0, 0, alpha)
        Font.draw(text, bx + 8, 12)
        g.setColor(1, 1, 1, 1)
      end
    end

    -- KEEP MONEY: afterBattle halves money synchronously on a loss, so
    -- the snapshot lands right before vanilla runs; the poison-tick
    -- blackout is snapshotted in the applyFieldPoison wrap above (the
    -- halving there is async, inside the pushed text-box callback).
    if not OverworldState._qolTogglesKeepMoneyInstalled then
      OverworldState._qolTogglesKeepMoneyInstalled = true
      local vanillaAfter = OverworldState.afterBattle
      OverworldState.afterBattle = function(self, result, battle)
        if get("keep_money") and result == "lose" then
          mod.exports.snapshotMoney(Game.save)
        end
        return vanillaAfter(self, result, battle)
      end
    end

    -- AUTO CUT: a step blocked by a cuttable tree cuts it instead of
    -- bonking -- tryCut re-gates on the tileset, the block swap and a
    -- party mon that knows CUT, so this only fires where vanilla CUT
    -- would.  The player stays put while the text + animation play.
    local Player = require("src.world.Player")
    if not Player._qolTogglesAutoCutInstalled then
      Player._qolTogglesAutoCutInstalled = true
      local vanillaTryMove = Player.tryMove
      Player.tryMove = function(self, dir, map, entities)
        local result, why = vanillaTryMove(self, dir, map, entities)
        if result == "blocked" and get("auto_cut") then
          local stack = Game.stack
          local top = stack and stack.states and stack.states[#stack.states]
          if top and top.tryCut then
            local Collision = require("src.world.Collision")
            local tx, ty = Collision.target(self.cellX, self.cellY, dir)
            if top:tryCut(tx, ty) then return nil end
          end
        end
        return result, why
      end
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

  -- REMEMBER CURSOR / REMEMBER MOVE: turn_ended fires when the turn's
  -- actions finish and before the act queue hands back to afterQueue
  -- "menu", so an OFF reset lands exactly as the next turn's menu opens
  mod.events:on("battle.turn_ended", function(ev)
    if ev and ev.battle then
      mod.exports.applyCursorRemember(ev.battle, get("remember_cursor"))
      mod.exports.applyMoveRemember(ev.battle, get("remember_move"))
    end
  end)

  -- HEAL AFTER BATTLE: every battle that ends (win, run, catch, loss)
  -- fully heals the party -- HP, status, and all PP
  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle and get("heal_battle") then
      local save = (ev.battle.game and ev.battle.game.save) or Game.save
      mod.exports.healParty(save and save.party)
    end
  end)

  -- KEEP MONEY: the blackout halving already ran before this event fires;
  -- restore the pre-blackout snapshot taken by the wraps below
  mod.events:on("world.blacked_out", function(ev)
    if ev and ev.save then mod.exports.keepMoneyRestore(ev.save) end
  end)

  -- -------------------------------------------------- MAP LOCATION

  -- a toast naming the area when the player enters a map that is not the
  -- one they just left -- the AUTO-REPEL banner slot (non-modal, fades
  -- out on its own); the boot map counts as the first entry
  mod.events:on("map.entered", function(event)
    if not get("map_location") then return end
    if not (event and event.mapId) then return end
    if event.mapId == lastMapId then return end
    lastMapId = event.mapId
    local now = (love and love.timer and love.timer.getTime)
                and love.timer.getTime() or os.clock()
    mod.exports.setLocationToast(
      mod.exports.locationName(Game.data, event.mapId, event.map), now)
  end)

  -- INFINITE REPEL: suppress every walking wild roll (grass, surf, caves);
  -- fishing keeps its own encounter.fishing path, like the Repel item.
  -- NO ENCOUNTER DUPES: a non-nil roll that repeats the last species is
  -- re-rolled (best effort -- after 8 attempts the last roll stands).
  -- Defensive: a downstream roll that throws (e.g. another mod's patch
  -- left a map's water/grass def without a rate) degrades to "no
  -- encounter" instead of blue-screening the game mid-step.
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    if get("repel") then return nil end
    local enc = mod.exports.avoidDupe(function()
      local ok, rolled = pcall(next, encDef, ctx)
      if not ok then
        mod.log.warn("encounter.roll failed (%s); suppressing the roll",
                     tostring(rolled))
        return nil
      end
      return rolled
    end, get("no_enc_dupes") and lastEncounterSpecies or nil, 8)
    if enc then lastEncounterSpecies = enc.species end
    return enc
  end)

  -- INSTANT FISH: every cast with a candidate group bites immediately --
  -- the group is uniform-picked instead of run through the rejection
  -- loop (bite odds size/(size+4)); a map with no group still has
  -- nothing to catch.  The Old Rod (always-catch) is unaffected.
  mod.hooks:wrap("encounter.fishing", function(next, rod, mapId, candidates)
    if get("instant_fish") then
      local enc = mod.exports.fishBite(candidates)
      if enc then return enc end
    end
    return next(rod, mapId, candidates)
  end)

  -- RUN (HOLD B): double foot speed while B is held (the movement.speed
  -- hook hands out the per-step frame count); the bike and surfing keep
  -- their own speeds
  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    return mod.exports.runFrames(next(frames, ctx), ctx)
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
                                          get("field_moves_all"),
                                          b.inventory,
                                          get("hm_item_required"))
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

  -- CATCH GIVES EXP: BattleState:storeCaughtMon consults the
  -- battle.catch_exp hook before the caught mon joins the party; the
  -- engine's faint path (awardExp) pays participants, stat exp, traded
  -- boosts, level-ups and the "gained N EXP" announcements, and this
  -- wrap opts a capture into exactly that award
  mod.hooks:wrap("battle.catch_exp", function(next, ctx)
    if get("catch_exp") then return true end
    return next(ctx)
  end)

  -- INSTANT FLEE: battle.run is the RUN menu + faint-dialogue escape roll
  -- (runRoll); forcing true escapes on the first try
  mod.hooks:wrap("battle.run", function(next, ctx)
    if get("instant_flee") then return true end
    return next(ctx)
  end)

  -- UNLIMITED TMs / FORGETTABLE HMs: patched once per session like the
  -- PartyMenu wrap below -- the toggle reads through get() at use time.
  -- The same wrap records the last bag item that actually went off (LAST
  -- ITEM (M)); failed uses and TM teaches (learn/learnkept, which only
  -- spend the machine in the field) are never remembered.
  local ItemEffects = require("src.inventory.ItemEffects")
  if not ItemEffects._qolTogglesUnlimitedTmsInstalled then
    ItemEffects._qolTogglesUnlimitedTmsInstalled = true
    local vanillaUse = ItemEffects.use
    ItemEffects.use = function(data, save, itemId, target, battle,
                               moveIndex, ow)
      local result, payload, extra = vanillaUse(data, save, itemId, target,
                                                battle, moveIndex, ow)
      if result ~= "failed" and result ~= "learn" and result ~= "learnkept"
         then
        lastItemId = itemId
      end
      return mod.exports.keepTm(result), payload, extra
    end
  end

  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  if not MoveLearnMenu._qolTogglesHmForgetInstalled then
    MoveLearnMenu._qolTogglesHmForgetInstalled = true
    local vanillaUpdate = MoveLearnMenu.update
    MoveLearnMenu.update = function(self, dt)
      -- selecting ~= false (not selecting): on engine builds v0.1.59..
      -- v0.1.63 MoveLearnMenu never sets selecting (the old ChoiceBox
      -- flow), so a truthy check would keep the vanilla HM gate up no
      -- matter the toggle; nil means "forget list live", exactly the
      -- state this gate-free update is for.
      if get("forgettable_hms") and self.selecting ~= false then
        return mod.exports.forgetUpdate(self, dt)
      end
      return vanillaUpdate(self, dt)
    end
  end

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

  -- POKEBALL BONUS: buying 10 POKé BALLS at any mart (in one or several
  -- purchases -- the counter is cumulative, stored in the slot's modData)
  -- earns a free GREAT BALL, announced by the clerk.  The ShopMenu wrap
  -- marks the mart's BUY list open, the ListMenu wrap clears the mark when
  -- that list closes, and the Bag.add wrap counts poké balls added while
  -- the mark is up -- the only path that runs while a shop list is on the
  -- stack is a real mart purchase.
  local ShopMenu = require("src.ui.ShopMenu")
  local ListMenu = require("src.ui.ListMenu")
  local Bag = require("src.inventory.Bag")
  if not Game._qolTogglesBallBonusInstalled then
    Game._qolTogglesBallBonusInstalled = true

    local vanillaShopNew = ShopMenu.new
    ShopMenu.new = function(game, stock, onQuit)
      local menu = vanillaShopNew(game, stock, onQuit)
      for _, item in ipairs(menu.items or {}) do
        if item.onSelect and item.label == Strings("BUY") then
          local select = item.onSelect
          item.onSelect = function()
            martBuyOpen = true
            return select()
          end
        end
      end
      return menu
    end

    local vanillaListNew = ListMenu.new
    ListMenu.new = function(game, title, items, opts)
      local list = vanillaListNew(game, title, items, opts)
      if martBuyOpen and list.dialogue and title == "BUY" then
        local cancel = list.onCancel
        list.onCancel = function()
          martBuyOpen = false
          if cancel then return cancel() end
        end
      end
      return list
    end

    local vanillaBagAdd = Bag.add
    Bag.add = function(save, id, qty, data)
      local ok = vanillaBagAdd(save, id, qty, data)
      if not ok then return ok end
      if save == Game.save and martBuyOpen and id == "POKE_BALL"
         and get("free_great_ball") then
        local count = mod.save:get("pokeballs_bought") or 0
        local granted = mod.exports.bonusBalls(count, qty or 1)
        mod.save:set("pokeballs_bought", count + (qty or 1))
        if granted > 0 then
          for _ = 1, granted do
            vanillaBagAdd(save, "GREAT_BALL", 1, data)
          end
          local TextBox = require("src.render.TextBox")
          Game.stack:push(TextBox.new(Game,
            Strings(mod.exports.bonusMessage())))
        end
      end
      return ok
    end
  end

  -- BULK MART: the mart quantity prompt (BUY and SELL) opens at 10
  -- instead of 1, still clamped upstream by money and bag space.  The
  -- mod manager's own QuantityBox rows (numeric options) are never
  -- touched: only boxes pushed while a mart list sits on the stack.
  local QuantityBox = require("src.ui.QuantityBox")
  if not Game._qolTogglesBulkMartInstalled then
    Game._qolTogglesBulkMartInstalled = true

    local vanillaListNew = ListMenu.new
    ListMenu.new = function(game, title, items, opts)
      local list = vanillaListNew(game, title, items, opts)
      if list.dialogue and title == "SELL" then
        local cancel = list.onCancel
        list.onCancel = function()
          martSellOpen = false
          if cancel then return cancel() end
        end
        martSellOpen = true
      end
      return list
    end

    local vanillaQtyNew = QuantityBox.new
    QuantityBox.new = function(game, opts)
      local box = vanillaQtyNew(game, opts)
      if (martBuyOpen or martSellOpen) and get("bulk_mart") then
        box.qty = math.min(10, box.max)
      end
      return box
    end
  end
end
