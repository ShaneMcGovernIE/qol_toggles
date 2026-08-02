# QoL Toggles

Adds a USEFUL TOGGLES row to OPTIONS that opens a submenu with quality-of-life switches, each persisted with your save.

## Try it

```sh
# 1. install: copy the folder into the game's mods/ directory
cp -r mods/qol_toggles <game-dir>/mods/

# 2. run the game, open OPTIONS, and pick USEFUL TOGGLES
love .
```

## The switches

- **POISON SAVE** — when a poisoned party member would faint from
  out-of-battle poison damage, it survives at 1 HP and the poison
  subsides: *"X's poison has subsided!"*
- **FULL HEAL CATCH** — every captured Pokémon is fully healed (HP,
  status, and all PP), whether it joins your party or goes to a PC box.
- **INFINITE REPEL** — no wild encounters while walking through grass,
  surfing, or in caves.  Fishing is unaffected, like the vanilla Repel
  item.
- **FIELD MOVES ALL** — any Pokémon that can learn a field move
  (level-up or TM/HM) can use it out of battle even without knowing it:
  a Pidgey that never learned FLY can still FLY, a Clefable without
  TELEPORT can still TELEPORT.  Badge restrictions still apply — no FLY
  without the Thunder Badge, no SURF without the Soul Badge — and the
  usual context rules hold (FLY/TELEPORT only outdoors, FLASH only in
  the dark, DIG only on its tilesets).
- **BADGELESS MOVES** — the badge gates come off: FLY, SURF, CUT,
  STRENGTH and FLASH all work without their badges.  Pairs with FIELD
  MOVES ALL for a no-badge, no-moveset run.
- **ALWAYS CATCH** — every ball catches, Master Ball style (the ball is
  still consumed).
- **PERFECT DVS** — caught Pokémon get 15s across the board, the gen 1
  maximum, with their stats recomputed to match.
- **EXP x2** — double battle EXP; the "gained N EXP" text shows the
  doubled amount.
- **INSTANT FLEE** — wild battles always escape on the first try (RUN
  menu and the faint dialogue's NO branch).

## Notes

- Each switch is independent and stored with your preferences (options.lua),
  so toggles survive restarts and save files.  POISON SAVE, FULL HEAL
  CATCH and FIELD MOVES ALL ship ON; the rest ship OFF.
- Toggling REPEL applies immediately — you can flip it in the field
  without using an item.
