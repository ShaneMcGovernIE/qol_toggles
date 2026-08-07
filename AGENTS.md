# QoL Toggles (qol_toggles)

A Lua mod for the Pokémon Gen1Recomp engine (Red/Blue/Yellow recompiled). Adds an
OPTIONS -> QOL TOGGLES row opening a submenu of 29 independent QoL switches
(poison survives at 1 HP, full-heal catches, infinite repel, learnable field
moves, badgeless moves, unlimited TMs, always catch, EXP x2, LAST ITEM (M),
POKEBALL BONUS, no encounter dupes, instant fishing, auto-repel, bulk mart,
lit caves, keep money, auto-cut, hold-B run, ...). Each toggle persists in
options.lua and survives saves. Everything lives in one file (`main.lua`) plus
metadata and tests; the mod is packed into an installable .zip and released by
GitHub Actions on push to main.

## Layout

- `main.lua` — entry (`return function(mod)`), the `TOGGLES` spec table, pure
  logic + test seams as `mod.exports.*`, the submenu screen, and every hook wrap.
- `manifest.json` — `id: qol_toggles`, version, permissions (`engine_internals`).
- `mod.card` — human-facing metadata; never read by the loader's merge.
- `CHANGELOG.md` — keep-a-changelog; heading must match `manifest.version`.
- `tests/` — two headless suites (see below). `.modkitignore` lists them so
  `pack` keeps them out of the shipped archive.
- `README.md`, `IDEA.md` — docs; every new toggle is described in README,
  CHANGELOG and mod.card.

## Dev environment

The mod only runs/tested from inside the engine source tree. On this machine the
engine checkout is `/Users/shanemcgovern/dev/gen1recomp` and
`gen1recomp/mods/qol_toggles` is a symlink to a **separate working copy** at
`/Users/shanemcgovern/dev/Gen1RecompMods/qol_toggles`.

⚠ The two copies can drift: this repo is the git source of truth, but
`gen1recomp/mods/qol_toggles` symlinks to the separate working copy at
`/Users/shanemcgovern/dev/Gen1RecompMods/qol_toggles` — and tests/play
exercise the mounted copy, not this repo. (As of 1.15.0 they are in sync;
the mounted copy previously carried uncommitted work — MOUSE CAM LOCK, a
FORGETTABLE HMs engine-compat fix — that had to be merged back before
syncing.) After editing here, sync before testing, e.g.
`rsync -a --exclude .git --exclude .github /Users/shanemcgovern/dev/qol_toggles/ /Users/shanemcgovern/dev/Gen1RecompMods/qol_toggles/`
and diff (`diff -rq --exclude .git --exclude .github`) before assuming the
copies agree.

## Build & test

Run from the engine root (`cd /Users/shanemcgovern/dev/gen1recomp`). Both suites
run against the engine's fixture dataset — no ROM, no generated data needed:

```sh
POKEPORT_DATA_DIR="$PWD/tests/fixture_data" luajit mods/qol_toggles/tests/qol_toggles_test.lua   # 657/657 checks
POKEPORT_DATA_DIR="$PWD/tests/fixture_data" luajit mods/qol_toggles/tests/wrap_compose_test.lua   # 6/6 checks
```

- `qol_toggles_test.lua` asserts all 29 toggle rows, ship defaults, and the pure
  helpers (`poisonClamp`, `healCaught`, `learnableFieldMoves`, `bonusBalls`,
  `avoidDupe`, `fishBite`, `applyAutoRepel`, `runFrames`, ...), plus event-wired
  behavior (`battle.ended` heal, `world.blacked_out` money restore, the
  tryMove/tryCut auto-cut wrap).
- `wrap_compose_test.lua` loads qol_toggles + mods_hotkeys together and draws the
  ticker row repeatedly — regression for the OptionRows.draw nil-label crash.

Engine mod-gallery gates (CI runs validate + lint):

```sh
python3 tools/modkit.py validate mods/qol_toggles --base imported   # loads the real loader headlessly
python3 tools/modkit.py lint mods/qol_toggles                       # ROM-content gate
python3 tools/modkit.py pack mods/qol_toggles                       # private-require warnings are fatal
```

Play the game: `love .` from the engine root.

## Conventions

- **One file.** Toggle = one entry in `TOGGLES`: `{ key, label, default, help }`.
  Labels >17 glyphs auto-get a ticker; help text paginates at 17 glyphs/line and
  scrolls if taller than the popup.
- **Persistence:** read/write through `get(key)`/`set(key)` which use the
  options.lua per-mod bucket (`Game.mods.modOptions[mod.id]`, mirrored into
  `Game.save.options`). Never per-save modData — NEW GAME/CONTINUE wipe it
  (changelog 1.1.2).
- **Wrap idiom:** engine classes are wrapped via `mod.hooks:wrap("hook.name", fn)`
  (`encounter.roll`, `fieldmove.eligibility`, `exp.gain`, `battle.run`,
  `battle.catch_exp`, `ui.options.rows`); events via `mod.events:on(...)`
  (`game.ready`, `pokemon.caught`, `battle.turn_ended`); the submenu via
  `mod.content.screens:register`; S.S. Anne via `mod.content.map_scripts:register`.
  Direct method patches (`OptionRows.draw`, `ItemEffects.use`,
  `BattleState.update`, `PartyMenu.update`) carry a session guard:
  `if not X._qolTogglesInstalled then X._qolTogglesInstalled = true` — hot reload
  re-runs entry chunks, so each wrap must install once.
- **Testability:** pure logic and test seams are exported (`toggleRows`, `get`
  injected via `toggleRows(getFn, setFn)`, `setLastItem`, `setMartBuyOpen`,
  `requestHelp`) so the headless suite drives them without a live game.
- **Releases:** push to main triggers the release workflow. Version resolution:
  manual input > `[release X.Y.Z]` in the commit message > `manifest.json`
  version (when ahead of every tag) > patch bump. Bumping the manifest is the
  normal way to cut a release; CHANGELOG must carry a matching heading.
- **Commits:** subject prefix `qol_toggles: <imperative summary>`. Docs
  (README/CHANGELOG/mod.card) updated in the same commit as the behavior.
- Engine compat: `engine >=0.1.53 <2.0.0`, `modApi 2` (mod.card).

## Pitfalls

1. **Drifted copies** (see Dev environment) — debug against the wrong copy and
   your fix "doesn't work". `diff` the two `main.lua`s before touching anything.
2. **`POKEPORT_DATA_DIR` is mandatory** for `qol_toggles_test.lua`: without it,
   `Data:load()` dies on `missing generated data module`; pointing it at the real
   ROM cache (`~/Library/Application Support/pokemon-love2d/yellow/data/generated`)
   dies on `unknown species FIXMON_A` — the suite needs the fixture dataset,
   not real data. `luajit tests/run_modkit.lua` alone also fails qol's main suite
   for this reason (wrap_compose passes under it).
3. **Don't hand-edit the archive or the release zip** — the workflow rebuilds
   `dist/qol_toggles-<version>.zip` from `git archive HEAD`; uncommitted work is
   silently excluded. The zip must carry manifest.json at the root (or in a
   single top-level folder) for `MODS > Import mod .zip`.
4. **FORGETTABLE HMs** ships a gate-free copy of `MoveLearnMenu.update` — keep it
   in lockstep with `gen1recomp/src/ui/MoveLearnMenu.lua` or the toggle drifts
   from vanilla behavior.
5. `modkit pack` treats warnings as fatal — anything requiring engine modules
   must stay out of the shipped mod (`.modkitignore` covers `tests/`).
