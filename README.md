# QoL Toggles

Adds a QOL TOGGLES row to OPTIONS that opens a submenu with quality-of-life switches, each persisted with your save.

## Try it

```sh
# 1. install: copy the folder into the game's mods/ directory
cp -r mods/qol_toggles <game-dir>/mods/

# 2. run the game, open OPTIONS, and pick QOL TOGGLES
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
- **HM ITEM REQUIRED** — the FIELD MOVES ALL extras for HM moves only
  appear once you actually hold the HM item: no CUT on the Cascade Badge
  alone when the CUT HM is still on the S.S. Anne.  (Moves a Pokémon
  already knows are never affected; non-HM moves like DIG and TELEPORT
  have no item to require.)
- **UNLIMITED TMs** — TMs teach their move without breaking.
- **FORGETTABLE HMs** — HM moves can be forgotten when a Pokémon learns
  a new move.
- **ALWAYS CATCH** — every ball catches, Master Ball style (the ball is
  still consumed).
- **PERFECT DVS** — caught Pokémon get 15s across the board, the gen 1
  maximum, with their stats recomputed to match.
- **EXP x2** — double battle EXP; the "gained N EXP" text shows the
  doubled amount.
- **CATCH GIVES EXP** — capturing a wild Pokémon pays out the same EXP
  its defeat would: split among the mons that fought, with stat exp,
  traded boosts, level-ups and the "gained N EXP" announcement.
- **INSTANT FLEE** — wild battles always escape on the first try (RUN
  menu and the faint dialogue's NO branch).
- **REMEMBER CURSOR** — the battle FIGHT/BAG/PKMN/RUN cursor stays where
  you left it across turns: use BAG to heal one turn, and the cursor is
  still on BAG the next.  OFF restores the vanilla fresh-FIGHT default
  every turn.
- **HEAL ON MAP CHANGE** — every map transition (routes, caves, warps,
  connections, even boot) fully heals the party: HP, status, and all
  PP.
- **QUICK S.S. ANNE** — the Vermilion dock sailor prompts for your
  ticket once; after that you walk straight onto the ship with no
  dialogue and no stop.  The ship-sailed guard and the no-ticket
  walk-back still apply.
- **LAST ITEM (M)** — in battle, press M to use the last item you used
  from the bag: balls throw at the foe, healing (potions, status cures,
  revives, ETHERs) opens the party screen so you pick the mon (ETHERs and
  PP UP then ask for the move), and targetless battle items (X items,
  POKé FLUTE, POKé DOLL) work as usual.  A failed use shows the vanilla
  refusal text and does not spend your turn; with nothing remembered the
  bag opens instead.  The M key is rebindable from the Mods Hotkeys
  submenu, like every other mod hotkey.
- **POKEBALL BONUS** — every time you buy your tenth POKé BALL at any
  mart (in one purchase or across several), the clerk throws in a free
  GREAT BALL: *"Thanks for your support, please take this free Great
  Ball."*  Only balls actually bought count — the five from Professor
  Oak and any found on the ground never do.  The counter carries across
  shops and save sessions; the toggle ships OFF.

## Notes

- Each switch is independent and stored with your preferences (options.lua),
  so toggles survive restarts and save files.  POISON SAVE, FULL HEAL
  CATCH, FIELD MOVES ALL, HM ITEM REQUIRED, UNLIMITED TMs, FORGETTABLE
  HMs and REMEMBER CURSOR ship ON; the rest ship OFF.
- Toggling REPEL applies immediately — you can flip it in the field
  without using an item.
- Toggle labels longer than the row's label window scroll as a ticker
  (hold at the start, scroll to the end, hold, scroll back), so a future
  long-named switch stays readable instead of bleeding over the box
  border.
- START on a controller (or P on the keyboard) on any toggle row opens a
  full-screen help popup explaining what that toggle does in depth; B (or
  another START/P) closes it, and B still exits the submenu.  A
  description taller than the popup box scrolls vertically, slowly, so
  nothing is ever cut off.
