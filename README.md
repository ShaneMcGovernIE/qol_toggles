# QoL Toggles

Adds a QOL TOGGLES row to OPTIONS that opens a submenu with quality-of-life switches, each persisted with your save. Works on Red/Blue/Yellow **and Gold**: the toggles with a Gen 2 home are ported to Gold's second engine, and the Gen 1-cart-only ones (S.S. Anne, Game Corner, dark caves, Dramatic Shape camera, battle items, marts, TM/HM-learn) drop out of the list on a Gold boot instead of doing nothing.

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
  the dark, DIG only on its tilesets).  The field-move submenu keeps the
  cart's own eight-row limit, so a Pokémon that can learn many field
  moves never pushes rows off the screen — the extras simply don't fit,
  exactly like a full moveset on the cart.
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
- **PERFECT DVS** — caught and scripted-gift Pokémon (the starter, the
  Celadon Eevee, Game Corner prizes, fossils) get 15s across the board,
  the gen 1 maximum, with their stats recomputed to match.
- **EXP MULT** — battle EXP scaled by a selectable multiplier: 0x (earn
  nothing), 1.5x, 2x, 3x or 4x.  The "gained N EXP" text shows the
  scaled amount; fractions floor the way the cart floors EXP splits.
  OFF is vanilla.  (The old fixed EXP x2 toggle becomes this selector;
  a save that already set it keeps its 2x.)
- **MONEY MULT** — battle earnings scaled the same way: 0x, 1.5x, 2x, 3x
  or 4x.  Covers trainer prize money and Pay Day; the victory and
  "picked up" texts show the scaled figure, and at 0x the prize line is
  dropped entirely — no "You got ¥0" box — and Pay Day is cancelled.
  OFF is vanilla.
- **CATCH GIVES EXP** — capturing a wild Pokémon pays out the same EXP
  its defeat would: split among the mons that fought, with stat exp,
  traded boosts, level-ups and the "gained N EXP" announcement.
- **INSTANT FLEE** — wild battles always escape on the first try (RUN
  menu and the faint dialogue's NO branch).
- **REMEMBER CURSOR** — the battle FIGHT/BAG/PKMN/RUN cursor stays where
  you left it across turns: use BAG to heal one turn, and the cursor is
  still on BAG the next.  OFF restores the vanilla fresh-FIGHT default
  every turn.
- **B FOR QUICK FLEE** — press B at the root of the battle menu and the cursor
  jumps straight to RUN; A then confirms the escape.  (Vanilla B does
  nothing there, so nothing is taken away.)  It never fires in the old
  man's demo battle (Gold's tutorial), a Safari battle (Gold's Bug
  Contest), a link or spectated battle, a trainer battle, or while a
  locked action like Thrash or recharge owns the turn.  Works on Red and
  Gold alike — Gold's battle screen keeps the active Pokémon on its battle
  model, which the toggle now reads too.
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
- **NO ENCOUNTER DUPES** — a wild roll never gives the same species
  twice in a row: the roll is re-rolled until it differs (best effort —
  an area with a single species still yields it).  Session-scoped.
- **INSTANT FISH** — the rod always bites on the first try: the
  candidate group is picked uniformly instead of running the engine's
  rejection loop (bite odds size/(size+4)).  A map with no fishing
  group at all still says "Not even a nibble!" — there is nothing to
  conjure — and the Old Rod's always-catch is unchanged.
- **HEAL AFTER BATTLE** — every battle that ends (win, run, catch,
  loss) fully heals the party: HP, status, and all PP.
- **TURN AWAY (NURSE)** — after a Pokécenter nurse heals you, you turn
  away from the counter, so an A-mash walks you off instead of locking
  you back into her dialogue.  The Elm's-lab and Hall-of-Fame heal
  machines are untouched.
- **QUICK NURSE** — talking to a Pokécenter nurse heals instantly: no
  welcome dialogue, no yes/no, no machine animation, and you turn away
  automatically, so tapping A again just walks you off.  The nurse still
  turns to face you, the center is remembered as the last-heal point
  (blackouts and ESCAPE ROPE land there as usual), and the Pewter
  Pikachu sleep scene keeps its vanilla dialogue — it is a story beat,
  not a heal.  Works on Red and Gold alike.
- **AUTO-REPEL** — when a repel wears off, the strongest repel in the
  bag (MAX > SUPER > plain) is used automatically and announced by an
  on-screen toast — the usual "effect wore off" text is skipped when a
  refill happens, and with nothing left to use it just wears off.  The
  toast never blocks — you keep walking while it fades out on its own.
- **BULK MART** — mart quantity prompts (BUY and SELL) open at 10
  instead of 1, still capped by money and bag space.  The mod
  manager's own numeric option boxes are never touched.
- **BULK COINS** — the Celadon Game Corner clerk greets you, asks
  "Would you like to purchase some COINS?", and offers 50, 500 or
  9,999 coins at a time (¥1000 / ¥10000 / ¥199980 — the vanilla
  20¥-per-coin rate) instead of the fixed 50.  Tiers that would
  overflow the 9,999 coin cap drop out of the list, and a **CUSTOM**
  row opens a four-box digit picker (up/down cycles each digit 0–9,
  left/right moves between boxes) for any amount from 1 to 9,999.
  With the toggle OFF the clerk is exactly vanilla.
- **LIGHTS ON** — dark caves and tunnels render fully lit with no FLASH
  needed; FLASH itself still works and is then harmless.
- **REMEMBER MOVE** — the battle FIGHT move cursor stays where you left
  it across turns (the sibling of REMEMBER CURSOR).  OFF restores the
  vanilla first-move default every turn.
- **KEEP MONEY** — blacking out no longer costs half your money,
  whether the party fell to poison steps or a battle.
- **AUTO CUT** — walk into a cut tree and a party mon that knows CUT
  cuts it for you (the tileset, block-swap and CUT gates are exactly
  the vanilla party-menu ones).  The player stays put while the text
  and animation play.  FIELD MOVES ALL does not extend to auto-cut —
  a mon that merely can learn CUT must still use the party menu.
- **RUN (HOLD B)** — hold B to move twice as fast on foot (bike speed
  without the bike); the bike and surfing keep their own speeds, and
  B does nothing it did not already do in the overworld.
- **MOUSE CAM LOCK** — with the Dramatic Shape Voxel Mod installed, the
  battle camera no longer follows the mouse.  Only the mouse steering is
  cut — the right stick, a touch drag and the zoom still work.  The toggle
  is inert (nothing to gate) when Dramatic Shape is absent.
- **AUTO BATTLER** — when ON, your Pokémon chooses its own move in
  Battle Palace style: Emerald's Attack / Defense / Support probabilities
  and low-HP table are used, and the selected category is passed through
  Gen 1's normal AI scoring. Gen 1 has no Natures, so the mod derives an
  approximate style from the four DVs and stat EXP. Items, switching, forced
  moves and trainer AI are unchanged. The low-HP profile latches until that
  Pokémon switches out. When the selected category is empty, a usable move
  from another category is used instead — the turn is never wasted on the
  Emerald "couldn't use its power" skip, because Gen 1's missing target
  data makes empty categories far more common than in Emerald and the skip
  would spam that message. Out of PP entirely, the Pokémon Struggles like
  vanilla Gen 1 (recoil included) instead of skipping the turn. If the
  toggle is switched off, the original player
  action proceeds. Ships OFF. This applies to free player turns in ordinary
  wild/trainer battles; link battles remain synchronized and unchanged.
- **MAP LOCATION** — when ON, entering a new area shows its name in the
  same toast style as AUTO-REPEL's refill banner: a small box near the
  top that fades out on its own while you keep walking.  Names come from
  the town map, with the Route 10 PokeCenter corrected (the town map
  data calls it "ROCK TUNNEL").  Ships ON.
- **RENAME** — the party submenu gains a RENAME row that opens the name
  screen for that Pokémon, so you can rename it on the fly, no Name
  Rater required.  The current nickname pre-fills; an empty or unchanged
  confirm keeps it, exactly the Name Rater's rule.  The row never
  appears in battle or on an egg.  When the submenu's eight-row box is
  already full, the CANCEL row drops first (B still backs out) and then
  the last field-move row gives up its seat, so RENAME is always
  visible.  Works on Red and Gold.
- **MODERN TYPES** — the type chart from Gen VI+ (minus FAIRY, which
  neither generation has) replaces the cart's chart.  On Red/Blue/Yellow
  that fixes the three Gen 1-only quirks: GHOST finally hits PSYCHIC
  super effectively (in Gen 1 the famous pointer bug made it immune),
  BUG stops beating POISON (2x in Gen 1, resisted today) and POISON
  stops beating BUG (2x in Gen 1, neutral today).  On Gold the only
  change is the Gen VI update where STEEL stopped resisting GHOST and
  DARK.  Everything else is already identical, so the toggle just swaps
  those rows.  Works on Red and Gold.  Ships OFF.

## Notes

- The QOL TOGGLES submenu shows four switches at a time in a retro 2×2 card
  grid; use the D-pad to move and A to toggle, while B exits.
- Each switch is independent and stored with your preferences (options.lua),
  so toggles survive restarts and save files.  POISON SAVE, FULL HEAL
  CATCH, FIELD MOVES ALL, HM ITEM REQUIRED, UNLIMITED TMs, FORGETTABLE
  HMs, REMEMBER CURSOR, AUTO-REPEL, REMEMBER MOVE, MAP LOCATION and
  RENAME ship ON; the rest, including AUTO BATTLER, ship OFF.
- Toggling REPEL applies immediately — you can flip it in the field
  without using an item.
- In the 2×2 QOL TOGGLES cards, labels wrap only between whole words. Any
  individual line wider than the card interior ticker-scrolls in place; shorter
  lines stay centered.
- START on a controller (or P on the keyboard) on any toggle row opens a
  full-screen help popup explaining what that toggle does in depth; B (or
  another START/P) closes it, and B still exits the submenu.  A
  description taller than the popup box scrolls vertically, slowly, so
  nothing is ever cut off.
