# Changelog

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
