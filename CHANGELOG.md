# Changelog

## [1.17.2] - 2026-08-07

### Changed

- AUTO BATTLER: a Pokémon with no usable moves (all PP spent) now
  Struggles like vanilla Gen 1 instead of skipping the turn with the
  "is incapable of using its power!" message — the same action shape the
  engine's own no-PP path and trainer AI use, recoil included.  The
  incapability message can no longer appear in normal play.

## [1.17.1] - 2026-08-07

### Fixed

- AUTO BATTLER no longer spams "is incapable of using its power!": the
  move grouping now classifies Gen 1 self-targeting moves (stat boosts,
  recovery, Substitute, Splash, Transform, Conversion, Mist, Light
  Screen, Reflect, Focus Energy) as the Palace's Defense category via
  their effect field.  The extractor omits the ROM target data Emerald's
  GetBattlePalaceMoveGroup groups by, which left Defense structurally
  empty — every Defense roll (and Support rolls on all-attack movesets)
  hit the empty-category 50% incapability roll and wasted the turn.  An
  empty category now falls back to a usable move instead; the Emerald
  turn-skip remains available to callers that explicitly ask for it.

## [1.17.0] - 2026-08-07

### Added

- AUTO BATTLER: when enabled, the player's Pokémon chooses its own move
  using the Pokémon Emerald Battle Palace's Attack / Defense / Support
  category probabilities, including the below-half-HP table and the
  category-missing fallback. The selected category is passed through Gen 1's
  normal AI scoring. Because Gen 1 has no Nature field, a transparent
  approximate Palace style is derived from the four Gen 1 DVs and stat EXP.
  Trainer AI, items, switching, and forced multi-turn actions remain
  unchanged. Ships OFF.
- MAP LOCATION: entering a new area shows its name in the AUTO-REPEL
  toast style (non-modal, fades out on its own), with the town map's
  names and a corrected name for the Route 10 PokeCenter (the town map
  data calls it "ROCK TUNNEL").  Ships ON.

### Notes

- The Emerald source keeps the original Palace category table in
  `src/battle_script_commands.c` and the chooser in
  `src/battle_gfx_sfx_util.c`; the Gen 1 port preserves those thresholds but
  maps each mon's DV/stat-EXP spread to an approximate style. Emerald does
  not define a DV-to-Nature mapping, so this part is intentionally a mod
  design approximation. Emerald's exact static target metadata is not
  exposed by the current Gen 1 extractor, so move grouping uses the closest
  available target/effect representation. The low-HP profile latches until
  switch-out. An empty selected category follows Emerald's random fallback,
  50% incapability roll, and incapability message; turning the toggle off
  preserves the originally selected Gen 1 action.

- The engine's existing `battle.enemy_action` hook remains trainer-side;
  AUTO BATTLER is installed through a guarded player-side `BattleState.update`
  wrapper, while items, switches, link battles, and locked multi-turn actions
  remain on their existing paths. The wrapper marks its own resolution to
  avoid selecting twice if the battle update is re-entered by a caller.

## [1.16.4] - 2026-08-07

### Fixed

- Start menu compatibility with Gen1 Modern UI: the auto-repel toast wrapped
  `OverworldState.draw`, which Gen1 Modern UI's `presentationStack` treats as
  proof that the released overworld renderer was replaced — disabling its
  overworld presenter, and with it every menu layered over the overworld
  (StartMenu included). The toast now draws through the additive
  `OverworldState.drawUI` overlay seam, which Gen1 Modern UI explicitly
  sanctions for location banners, so the stock `draw` (and its identity)
  survives untouched and the Start menu opens normally. No Gen1 Modern UI
  change is required — QoL Toggles also leaves `Game:gamepadpressed`
  dispatch untouched, so the engine opens the native Start menu on
  controller START with Gen1 Modern UI enabled.

## [1.16.1] - 2026-08-07

### Fixed

- Fixed controller START handling so the overworld Start menu remains visible
  when QoL Toggles is enabled.
- Stored the QUICK S.S. ANNE prompt flag per save instead of globally, so
  separate save files no longer share progress.

## [1.16.0] - 2026-08-07

### Added

- BULK COINS: the Celadon Game Corner clerk greets you, asks
  "Would you like to purchase some COINS?" and offers 50, 500 or
  9,999 coins at a time (¥1000 / ¥10000 / ¥199980, the vanilla
  20¥-per-coin rate) instead of the fixed 50, plus a CUSTOM row that
  opens a four-box digit picker (up/down cycles each digit 0-9,
  left/right moves between boxes) for any amount from 1 to 9,999.
  Tiers that would overflow the 9,999 coin cap drop out of the list,
  and with the toggle OFF the clerk is byte-for-byte vanilla.  Ships
  OFF.

## [1.15.0] - 2026-08-07

### Added

- NO ENCOUNTER DUPES: a wild roll never gives the same species twice in
  a row (re-rolled until it differs, best effort on single-species
  areas).  Ships OFF.
- INSTANT FISH: the rod always bites on the first try — the candidate
  group is uniform-picked instead of run through the rejection loop.
  Maps with no fishing group still have nothing to catch; the Old
  Rod's always-catch is unchanged.  Ships OFF.
- HEAL AFTER BATTLE: every battle that ends (win, run, catch, loss)
  fully heals the party — HP, status, all PP.  Ships OFF.
- AUTO-REPEL: a worn-off repel is replaced from the bag automatically,
  strongest first (MAX > SUPER > plain), announced by an on-screen
  toast — the usual "effect wore off" text is skipped when a refill
  happens, and with nothing left it just wears off.  Ships ON.
- BULK MART: mart quantity prompts (BUY and SELL) open at 10 instead
  of 1, still capped by money and bag space; the mod manager's numeric
  option boxes are untouched.  Ships OFF.
- LIGHTS ON: dark caves and tunnels render fully lit, no FLASH needed
  (FLASH itself still works and is harmless).  Ships OFF.
- REMEMBER MOVE: the FIGHT move cursor stays on the last move used
  across turns, the sibling of REMEMBER CURSOR; OFF restores the
  vanilla first-move default.  Ships ON.
- KEEP MONEY: blacking out no longer costs half your money, from
  poison steps or a battle loss.  Ships OFF.
- AUTO CUT: walking into a cut tree cuts it when a party mon knows
  CUT, with exactly the vanilla tileset/block/CUT gates; the player
  stays put while the text and animation play.  FIELD MOVES ALL does
  not extend to auto-cut.  Ships OFF.
- RUN (HOLD B): hold B to move twice as fast on foot; the bike and
  surfing keep their own speeds.  Ships OFF.

## [1.14.0] - 2026-08-06

### Added

- MOUSE CAM LOCK: with Dramatic Shape Voxel Mod installed, the battle
  camera no longer follows the mouse.  Only the mouse steering is cut --
  the right stick, a touch drag and the zoom still work.  The toggle is
  inert (nothing to gate) when Dramatic Shape is absent.

## [1.13.0] - 2026-08-05

### Fixed

- FORGETTABLE HMs did nothing on engine builds v0.1.59..v0.1.63: those
  builds ran the old ChoiceBox forget flow, where MoveLearnMenu never
  sets the `selecting` field the toggle gated on, so the gate-free
  update never engaged and the vanilla "HM techniques can't be
  deleted!" message appeared even with the toggle ON.  The toggle now
  treats a missing `selecting` (old flow) as "forget list live", so
  teaching any move over an HM works on every engine build.

## [1.12.0] - 2026-08-04

### Changed

- The OPTIONS row is renamed from USEFUL TOGGLES to QOL TOGGLES, matching
  the mod's name everywhere (README, mod card, index).

## [1.11.0] - 2026-08-04

### Added

- POKEBALL BONUS: a toggle that, when ON, earns a free GREAT BALL every
  time you buy your tenth POKé BALL at any mart — in one purchase or
  across several, since the counter is cumulative and stored with the
  save.  The clerk announces it: "Thanks for your support, please take
  this free Great Ball."  Only balls actually bought count (Oak's five
  starter balls and found balls never do, because the bonus keys off the
  mart's BUY screen).  Ships OFF.

## [1.10.0] - 2026-08-04

### Added

- LAST ITEM (M): a toggle that, when ON, makes M in battle use the last
  item you used from the bag — balls throw at the foe, healing opens the
  party screen so you pick the mon (ETHERs/PP UP then ask for the move),
  targetless battle items (X items, POKé FLUTE, POKé DOLL) work as usual.
  A failed use shows the vanilla refusal text and does not spend the
  turn; with nothing remembered the bag opens.  M is detected by and
  rebindable from the Mods Hotkeys submenu.  Ships OFF.

## [1.9.1] - 2026-08-03

### Added

- CATCH GIVES EXP: capturing a wild Pokémon pays out the same EXP its
  defeat would — split among the mons that fought, with stat exp, traded
  boosts, level-ups and the "gained N EXP" announcement.  Ships OFF.

## [1.9.0] - 2026-08-03

### Added

- START on a controller (or P on the keyboard) on any toggle row opens a
  full-screen help popup (the Mods Hotkeys capture idiom) with an in-depth
  explanation of what that toggle does.  B or another START/P closes it;
  B still exits the submenu.
- A description taller than the popup box scrolls vertically, slowly
  (one line per second, holding at each end), scissored to the box so it
  never bleeds over the border.

## [1.8.0] - 2026-08-03

### Added

- Toggle labels longer than the row's label window now scroll as a ticker
  (hold at the start, scroll to the end, hold, scroll back — the
  MoveRelearn name ticker) instead of bleeding over the box border.

## [1.7.0] - 2026-08-03

### Changed

- UNLIMITED TMs/HMs splits into two switches: UNLIMITED TMs (TMs teach
  without breaking) and FORGETTABLE HMs (HM moves can be forgotten when
  a Pokémon learns a new move).  Both ship ON.

### Added

- HM ITEM REQUIRED: the FIELD MOVES ALL extras for HM moves (CUT, FLY,
  SURF, STRENGTH, FLASH) only appear once the player holds the HM item
  -- no CUT on the Cascade Badge alone when the CUT HM is still on the
  S.S. Anne.  Applies to the party-menu list and the use-time
  eligibility both; moves a Pokémon already knows are never gated, and
  item-less field moves (DIG, TELEPORT, SOFTBOILED) are unaffected.
  Ships ON.

## [1.6.0] - 2026-08-03

### Added

- REMEMBER CURSOR: the battle FIGHT/BAG/PKMN/RUN cursor stays where it
  was left across turns (use BAG to heal, and the cursor is still on
  BAG next turn).  OFF restores the vanilla fresh-FIGHT default at the
  end of every turn.  Ships ON.

## [1.5.0] - 2026-08-03

### Added

- UNLIMITED TMs/HMs: TMs teach their move without breaking, and HM
  moves can be forgotten when a Pokémon learns a new move.  Ships ON.

## [1.4.1] - 2026-08-03

### Fixed

- Using an Ether, Max Ether or PP Up on a Pokémon no longer crashes the
  game when FIELD MOVES ALL is on: phantom field-move slots were being
  attached to the target picker's moveset, and the "Which move?" list
  tripped on their missing PP (blue screen, BagMenu "number expected,
  got nil").  Target pickers are now exempt from phantom moves and badge
  injection.

## [1.4.0] - 2026-08-02

### Added

- QUICK S.S. ANNE: the Vermilion dock sailor prompts for the ticket once;
  every later pass onto the gangway walks straight through with no
  dialogue and no stop.  The ship-left guard and the no-ticket walk-back
  stay vanilla.  Ships OFF.

## [1.3.0] - 2026-08-02

### Added

- HEAL ON MAP CHANGE: every map transition (routes, caves, warps,
  connections, boot) fully heals the party — HP, status, and all PP.
  Ships OFF.

## [1.2.2] - 2026-08-02

### Fixed

- FIELD MOVES ALL no longer bypasses badge gates at use time: on engine
  builds without a list-time badge check in the party menu, a mon that
  could learn Surf/Cut could use it without the badge or the HM.  The
  fieldmove.eligibility wrap now applies the hmBadges gate itself
  (FLY/CUT need their badge, SURF needs the Soul Badge, STRENGTH the
  Rainbow Badge, FLASH the Boulder Badge) unless BADGELESS MOVES is on.

## [1.2.1] - 2026-08-02

### Fixed

- Blue screen on Route 13 while surfing: another mod's encounter patch
  can leave a map's water/grass def without a `rate`, which crashed the
  encounter roll mid-step.  The encounter.roll wrap now degrades a
  throwing roll to "no encounter" (logged) instead of crashing the game.

## [1.2.0] - 2026-08-02

### Added

- BADGELESS MOVES: FLY / SURF / CUT / STRENGTH / FLASH work without
  their badges — the party-menu list and the use-time gates both (the
  engine's own fieldmove.eligibility hook, which also lets FIELD MOVES
  ALL surf-mount and cut trees with a mon that only can learn the move).
- ALWAYS CATCH: every ball catches, Master Ball style (full three-shake
  chain).
- PERFECT DVS: caught Pokémon get 15s across the board; stats are
  recomputed to match.
- EXP x2: double battle EXP via the engine's exp.gain hook — the gain
  text shows the doubled amount too.
- INSTANT FLEE: wild battles always escape on the first try, via the
  engine's battle.run hook (RUN menu and the faint dialogue's NO
  branch).
- All five ship OFF by default; the original four keep their defaults.

## [1.1.3] - 2026-08-02

### Changed

- POISON SAVE, FULL HEAL CATCH and FIELD MOVES ALL now ship ON by default;
  INFINITE REPEL still ships OFF.  A stored toggle always wins over the
  default, so existing settings are untouched.

## [1.1.2] - 2026-08-02

### Fixed

- Toggles now persist: they live in options.lua (the mod-options bucket the
  mod manager uses) instead of the per-save modData, which NEW GAME and
  CONTINUE replace outright.  A toggle flipped from the title screen used
  to be silently discarded on start/continue, and an unsaved session lost
  it on quit; both are gone now.

## [1.1.1] - 2026-08-02

### Fixed

- FIELD MOVES ALL actually works: the party menu builds its field-move
  list before the ui.party.submenu hook fires, so the phantom moves are
  now attached to the selected Pokémon before the vanilla update runs
  (wrapping PartyMenu.update instead).  Badge gates and context rules
  still apply exactly as before.

## [1.1.0] - 2026-08-02

### Added

- FIELD MOVES ALL: any Pokémon that can learn a field move (level-up or
  TM/HM) can use it out of battle even without knowing it — Pidgey can FLY,
  Clefable can TELEPORT.  Badge gates and context rules (FLY/TELEPORT
  outdoors, FLASH in the dark, DIG's tilesets) apply exactly as for a known
  move.

### Changed

- The OPTIONS row is now USEFUL TOGGLES, with the on-count shown as a
  running total (e.g. "2/4 ON").

## [1.0.0] - 2026-08-02

### Added

- OPTIONS → TOGGLES submenu with three per-save switches.
- POISON SAVE: poisoned party members survive at 1 HP; the poison subsides with "X's poison has subsided!".
- FULL HEAL CATCH: captured Pokémon are fully healed (HP, status, PP) in the party or a PC box.
- INFINITE REPEL: blocks all wild walking encounters while active.
