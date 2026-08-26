# Auto Battler Extraction Design

**Date:** 2026-08-26

**Status:** Approved for implementation

## Goal

Extract the AUTO BATTLER option and Battle Palace-style player battle behavior from QoL Toggles into a standalone `auto_battler` mod located at `/Users/shanemcgovern/dev/auto_battler-main`, while leaving QoL Toggles with no active auto-battle UI, runtime code, or exported auto-battle API.

## Existing context

QoL Toggles currently owns three coupled pieces of this feature:

1. The `auto_battler` row in its QOL TOGGLES card grid and the `auto_battler` setting in the `qol_toggles` options bucket.
2. The Palace-style helpers: Gen 1 DV/stat-EXP style mapping, category probability tables, move grouping, usable-move fallback, Struggle handling, and low-HP latching.
3. A guarded `BattleState.update` wrapper that handles both the Gen 1 `resolveTurn` path and the Gen 2 screen `submit` path, including B-to-pause, A-to-resume, and automatic message advancement.

The current checkout also contains unrelated, uncommitted battery-indicator work in `main.lua`, `README.md`, and `tests/qol_toggles_test.lua`. Those changes are outside this extraction and must remain intact.

## Architecture

The new mod will use API 2 with `id = "auto_battler"`, `entry = "main.lua"`, `games = ["gen1", "gen2"]`, and `permissions = ["engine_internals"]`. Its entry file will own all Palace helpers and the generation-aware `BattleState.update` wrapper. The wrapper will call the captured update exactly as the existing implementation does for all ineligible/manual/link/tutorial/contest states.

The new mod will expose one standalone `AUTO BATTLER` row through `ui.options.rows`, so it remains available in the game’s normal OPTIONS screen after leaving the QOL submenu. It will also call `mod.options:define` with a matching `enabled` toggle, giving the standalone mod a native mod-options screen. The gameplay gate will read the new mod’s `enabled` setting and will not read or depend on QoL Toggles at runtime.

The new mod will keep the existing default OFF and the existing behavior: ordinary wild/trainer player turns are automated, link and spectated battles remain manual, B pauses after the current action/message sequence, A on FIGHT resumes automation, empty categories fall back to usable moves, and no-PP Pokémon use Struggle. Gen 1 and Gen 2 detection will follow the current live-data-aware implementation so Crystal does not regress to the Gen 1 contract.

## Settings migration

On first load of the new mod, if its own `enabled` option is absent and the legacy `qol_toggles.auto_battler` value is a boolean, the new mod will copy that value into `auto_battler.enabled`. An explicitly stored new value, including `false`, wins over the legacy value. QoL Toggles will not perform or own this migration; after extraction it will neither read nor write the legacy key. The old key may remain inert in an existing `options.lua` file until normal options cleanup, but it will have no effect.

## QoL Toggles removal

QoL Toggles will remove the AUTO BATTLER row, its Palace helper exports, its auto-battle exports, its BattleState auto wrapper, and all active manifest/card/README descriptions of the feature. Historical changelog entries remain historical; a new changelog entry will identify the extraction. The QoL test suite will retain coverage for QoL-only rows and will assert that the old row/API are absent where practical. Auto-battle-specific tests will move to the standalone mod’s test suite.

## Standalone project contents

The sibling project will include the normal standalone mod files:

- `manifest.json` with the new identity and option metadata.
- `main.lua` with the extracted implementation and option row.
- `README.md` and `mod.card` describing installation, controls, compatibility, and the OFF default.
- `tests/auto_battler_test.lua` containing the moved Palace chooser, fallback, pause/resume, Gen 1, Gen 2, Crystal, and Struggle coverage.
- `.modkitignore` and the standard release workflow copied from the existing standalone mod pattern.

## Compatibility and composition

The standalone wrapper will use its own install guard, distinct from QoL’s other BattleState wrappers. It will preserve `next`-style behavior by capturing the current `BattleState.update` and delegating whenever automation does not take the turn. Loading it alongside QoL Toggles must leave QoL’s last-item, cursor, animation, and other battle wrappers operational.

The new mod will target API 2 and the same Gen 1/Gen 2 engine scope as the extracted implementation. No ROM data, generated game data, or patches will be added.

## Validation

Validation will cover:

- The standalone test suite, including both generation contracts and the legacy-setting migration.
- The existing QoL test suite with its auto-battle tests removed or replaced by absence checks.
- A combined-load regression where both mods are active and their BattleState wrappers coexist.
- `modkit validate --strict`, `modkit lint`, and `modkit pack` for the standalone mod, plus strict validation/lint for QoL Toggles.

The report will distinguish headless/static validation from any in-game verification, which is not available unless a local runtime session is explicitly run.

