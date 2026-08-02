# Changelog

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
