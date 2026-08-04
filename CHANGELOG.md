# Changelog

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
