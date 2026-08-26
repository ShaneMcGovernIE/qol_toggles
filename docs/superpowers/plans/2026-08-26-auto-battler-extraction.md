# Auto Battler Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move AUTO BATTLER into a standalone `auto_battler` API 2 mod under `/Users/shanemcgovern/dev/auto_battler-main`, preserving behavior while removing its active UI and runtime ownership from QoL Toggles.

**Architecture:** The sibling mod owns the Palace chooser, live option, and generation-aware `BattleState.update` wrapper. QoL Toggles retains its existing unrelated battle wrappers and no longer exports or reads auto-battle state. The new mod reads its own `enabled` option and performs a one-time legacy-value migration from `qol_toggles.auto_battler` only when the new bucket has no explicit value.

**Tech Stack:** Lua/LuaJIT, LÖVE 2D, Gen 1 Recomp API 2 mod SDK, Python modkit, shared headless test harness.

**Spec:** `docs/superpowers/specs/2026-08-26-auto-battler-extraction-design.md`

## Global Constraints

- Preserve API 2 and the existing `gen1`/`gen2` runtime scope.
- Preserve the existing AUTO BATTLER default OFF and all current Gen 1, Gold, Silver, and Crystal behavior.
- Do not add ROM-derived data, generated game data, or patches.
- Preserve all pre-existing uncommitted battery-indicator changes in the QoL worktree.
- QoL Toggles must not read or write `auto_battler` after extraction.

### Task 1: Scaffold the standalone mod

**Files:**
- Create: `/Users/shanemcgovern/dev/auto_battler-main/manifest.json`
- Create: `/Users/shanemcgovern/dev/auto_battler-main/main.lua`
- Create: `/Users/shanemcgovern/dev/auto_battler-main/README.md`
- Create: `/Users/shanemcgovern/dev/auto_battler-main/mod.card`
- Create: `/Users/shanemcgovern/dev/auto_battler-main/.modkitignore`
- Create: `/Users/shanemcgovern/dev/auto_battler-main/.github/workflows/release.yml`

**Interfaces:**
- Produces mod id `auto_battler` with a boolean `enabled` option and one `AUTO BATTLER` row in the game OPTIONS screen.
- Produces exports `palaceNature`, `palaceCategory`, `palaceMoveGroup`, `palaceChooseMove`, `autoBattleAction`, `autoBattleShouldAct`, `autoBattleObserveInput`, `autoBattleAdvanceMessages`, and `autoBattleUpdate` for the standalone test suite.

- [ ] **Step 1: Create the standalone project directory and base metadata.**

  Use `mkdir -p` only for the exact new project directories, then add a manifest with this shape:

  ```json
  {
    "id": "auto_battler",
    "name": "Auto Battler",
    "version": "0.1.0",
    "api": 2,
    "entry": "main.lua",
    "profile": "content",
    "games": ["gen1", "gen2"],
    "category": "GAMEPLAY",
    "priority": 100,
    "dependencies": [],
    "optional_dependencies": [],
    "conflicts": [],
    "permissions": ["engine_internals"],
    "description": "An optional Battle Palace-style auto battler for player-controlled wild and trainer battles. Gen 1 DVs and stat EXP derive the Palace style; Gen 1 and Gen 2 battle screens are supported, while link and spectated battles remain manual."
  }
  ```

- [ ] **Step 2: Add the standalone project’s documentation and release metadata.**

  Document installation, the OPTIONS row, ON/OFF behavior, B pause, A/FIGHT resume, Struggle behavior, supported games, and the fact that link/spectated/tutorial/contest battles are excluded. Copy the existing release workflow pattern and change its `MOD_ID` values and archive names to `auto_battler`.

- [ ] **Step 3: Register the standalone option and migration contract.**

  At the start of the new entry function, register the manager schema:

  ```lua
  mod.options:define({
    { key = "enabled", type = "toggle", label = "AUTO BATTLER",
      default = false },
  })
  ```

  Add a helper that returns `mod.options:get("enabled") == true`. The current SDK exposes `define` and `get`, so implement a local persistence helper that mirrors the existing QoL path: update `Game.mods.modOptions`, mirror `Game.save.options.modOptions`, and call `Game:writeOptions()` when available. Before gameplay hooks are installed, inspect the current loader option bucket. If `auto_battler.enabled` is absent and `qol_toggles.auto_battler` is boolean, write the legacy value into the new bucket through that helper. Never overwrite an explicitly stored new value.

### Task 2: Move the Palace implementation and battle hook

**Files:**
- Modify: `/Users/shanemcgovern/dev/auto_battler-main/main.lua`
- Create: `/Users/shanemcgovern/dev/auto_battler-main/tests/auto_battler_test.lua`

**Interfaces:**
- Consumes: `mod.options:define/get`, `mod.hooks:wrap`, `mod.hooks:wrap("ui.options.rows", ...)`, `Game`, `GameVersion`, `Runtime`, and the existing Gen 1/Gen 2 `BattleState` modules.
- Produces: the same move-selection and live battle semantics currently implemented by QoL Toggles.

- [ ] **Step 1: Move the generation detection and required SDK setup.**

  Copy only the live-data-aware `hasGen2Data`/`detectGen2` logic and required imports from QoL Toggles. Keep the Crystal stale-`GameVersion` safeguard and set the local generation once at entry.

- [ ] **Step 2: Move the pure Palace helpers without changing their behavior.**

  Move the `PALACE_STYLES`, stat-EXP contribution, DV/stat-EXP nature mapping, category threshold table, Gen 1 effect classification, move grouping, usable PP filtering, category fallback, low-HP latch, and Struggle action exactly as currently implemented. Keep the public exports listed in Task 1 so all existing assertions can move without changing expected results.

- [ ] **Step 3: Adapt the live action gate to the standalone option.**

  Replace every QoL `get("auto_battler")` check with the standalone `enabled()` helper. Keep all existing eligibility exclusions and both action shapes:

  ```lua
  -- Gen 1 action
  { id = moveId, pp = currentPP, _index = slot }

  -- Gen 2 submitted action
  { kind = "move", move = moveId }
  ```

  Preserve the no-PP `{ id = "STRUGGLE", pp = 1, struggle = true }` path and the current handling of forced moves, link battles, spectating, tutorial/demo, contest/Safari, and dead player Pokémon.

- [ ] **Step 4: Install the standalone `BattleState.update` wrapper.**

  Use a unique guard such as `Game._autoBattlerModInstalled`. Capture the current generation-specific `BattleState.update`, then preserve the current sequence: observe real B/A input, queue one A tap per finished message, auto-submit Gen 2 menu actions, route Gen 1 free menu turns through `autoBattleUpdate`, and delegate to the captured update for every other state. Do not alter QoL’s wrapper guards or call private engine modules beyond the existing supported seams.

- [ ] **Step 5: Add the standalone in-game OPTIONS row.**

  Wrap `ui.options.rows`, call `next(game, rows)` first, append a row with id `auto_battler`, label `AUTO BATTLER`, a value function that returns `ON`/`OFF`, and a step function that persists the negated `enabled()` value through the local loader/save helper and returns `true` when a save is available. Ensure the row works with a missing save the same way other option rows do.

- [ ] **Step 6: Move and retarget the focused tests.**

  Copy the auto-battle-specific sections from `tests/qol_toggles_test.lua` into `tests/auto_battler_test.lua`. Change the loaded mod path to `mods/auto_battler` when run from the engine test checkout, use `auto_battler.enabled` for live settings, and retain coverage for Palace mapping, move grouping, normal-AI scoring, fallback, Struggle, low-HP latching, Gen 1 action submission, Gen 2/Crystal action submission, message advancement, B pause, and A/FIGHT resume.

### Task 3: Remove AUTO BATTLER from QoL Toggles

**Files:**
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/main.lua`
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/tests/qol_toggles_test.lua`
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/README.md`
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/manifest.json`
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/mod.card`
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/CHANGELOG.md`

**Interfaces:**
- Consumes: no auto-battle API from QoL Toggles.
- Produces: QoL-only toggle rows, exports, docs, and tests; all unrelated battle wrappers continue to load.

- [ ] **Step 1: Remove the toggle definition and active comments.**

  Delete the `auto_battler` entry from `TOGGLES`, remove AUTO BATTLER from the top-level behavior comments, and update row-count/index expectations in the QoL tests so rows after it shift down by one.

- [ ] **Step 2: Delete the Palace helper and live auto-battle blocks.**

  Remove the Palace constants/functions/exports and the guarded auto-battle portion of the `BattleState.update` installation. Keep the shared `BattleState` require if QoL’s last-item, remember-cursor, animation, or other remaining wrappers still need it. Remove only the auto-battle clauses from comments and guard names.

- [ ] **Step 3: Remove auto-battle-specific tests and add absence checks.**

  Delete the moved Palace/Gen 1/Gen 2 auto-battle assertions from the QoL suite. Add assertions that `toggleRows` contains no `auto_battler` row and that `loader.exports.qol_toggles` does not expose `palaceChooseMove` or `autoBattleAction`. Leave all QoL-only test coverage and the existing battery-indicator additions intact.

- [ ] **Step 4: Update active QoL documentation.**

  Remove AUTO BATTLER from the README switch list, ship-default notes, manifest description, and `mod.card` current summary/differences/known notes. Add a top changelog entry stating that AUTO BATTLER moved to the standalone Auto Battler mod; retain older historical entries below it.

### Task 4: Integration coverage and validation

**Files:**
- Create or modify: `/Users/shanemcgovern/dev/auto_battler-main/tests/combined_load_test.lua`
- Modify: `/Users/shanemcgovern/dev/qol_toggles-main/tests/qol_toggles_test.lua`

- [ ] **Step 1: Add legacy migration coverage.**

  Load the standalone mod with `loader.modOptions.qol_toggles.auto_battler = true` and no `auto_battler.enabled` entry; assert the new bucket becomes true. Repeat with an explicit `auto_battler.enabled = false`; assert it remains false.

- [ ] **Step 2: Add combined wrapper coverage.**

  Load both `mods/qol_toggles` and `mods/auto_battler` in one harness. Assert both load without errors, the new mod owns the auto-battle exports, QoL owns no auto-battle exports, and a representative BattleState update reaches the standalone action path while remaining compatible with the existing QoL wrapper chain.

- [ ] **Step 3: Run focused Lua tests.**

  Run the standalone tests from the engine checkout with:

  ```sh
  luajit tests/auto_battler_test.lua
  luajit tests/combined_load_test.lua
  ```

  Run the QoL tests with their existing command and confirm no row/index, stale-generation, or unrelated wrapper regressions.

- [ ] **Step 4: Run modkit checks for both packages.**

  From the engine checkout, run:

  ```sh
  python3 tools/modkit.py validate /Users/shanemcgovern/dev/auto_battler-main --strict --base fixture
  python3 tools/modkit.py lint /Users/shanemcgovern/dev/auto_battler-main
  python3 tools/modkit.py pack /Users/shanemcgovern/dev/auto_battler-main -o /private/tmp/auto_battler.modpkg
  python3 tools/modkit.py validate /Users/shanemcgovern/dev/qol_toggles-main --strict --base fixture
  python3 tools/modkit.py lint /Users/shanemcgovern/dev/qol_toggles-main
  ```

  Report any skipped imported-data or in-game checks explicitly.

- [ ] **Step 5: Review final scope before completion.**

  Run `git diff --check` in the QoL repo and inspect `rg -n 'auto.?battl|palace'` in active QoL source/docs/tests. Historical changelog matches are allowed; active QoL code must contain no auto-battle implementation, option, or export. Confirm the standalone directory contains only intended mod files and no ROM/generated data.
