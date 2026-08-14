# QoL Toggles Two-Column Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the QoL Toggles single-column submenu with a paginated retro 2×2 card grid while preserving toggle behavior, persistence, help, and generation filtering, then install the verified mod into the local game copy.

**Architecture:** Keep `TOGGLES` and `mod.exports.toggleRows` as the source of truth. Add pure card-label, card-geometry, and grid-navigation helpers plus a private QoL card renderer in `main.lua`; do not modify the shared `OptionRows` renderer. The menu will keep an absolute selected row index, derive its page and slot from that index, and use A for activation while directional buttons navigate.

**Tech Stack:** Lua/LuaJIT, the existing Gen 1/Gen 2 headless modkit, `Font.drawBox`/`Font.draw`, existing `Theme` glyphs, and the local LÖVE mod directories under `~/Library/Application Support`.

## Global Constraints

- Use the 160×144 Game Boy canvas and two 10×7 tile cards at `(0,0)`, `(10,0)`, `(0,7)`, and `(10,7)`.
- Wrap card labels to eight glyph columns and fit every visible label within three lines.
- Preserve every internal toggle ID, including `b_to_run`, and preserve options persistence.
- Preserve Gen 1/Gen 2 filtering and the existing START/P help popup behavior.
- Do not alter the shared `OptionRows` renderer or other menus.
- Write failing tests before production code for each new helper/behavior.
- Do not stage `options.lua`, `options.lua.bak`, or `options.lua.tmp` from the repository root.
- The primary installed-game copy is `/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles`; mirror the verified `main.lua` into `/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles` as the second current install, leaving the older `pokemon-love2d-upscale` copy untouched.

---

### Task 1: Add failing card-grid helper and navigation tests

**Files:**
- Modify: `tests/qol_toggles_test.lua` near the existing submenu/ticker tests

**Interfaces:**
- The tests will require `ex.cardLabelLines(label) -> string[]`.
- The tests will require `ex.cardGeometry(slot) -> { x, y, w, h }`.
- The tests will require `ex.gridMove(index, action, total) -> integer`.

- [ ] **Step 1: Write the failing tests**

Add assertions for the pure seams:

```lua
local lines = ex.cardLabelLines("FULL HEAL CATCH")
T.same(lines, { "FULL", "HEAL", "CATCH" },
       "card labels wrap at the card width")
T.same(ex.cardGeometry(1), { x = 0, y = 0, w = 10, h = 7 },
       "top-left card geometry")
T.same(ex.cardGeometry(4), { x = 10, y = 7, w = 10, h = 7 },
       "bottom-right card geometry")
T.eq(ex.gridMove(1, "right", 34), 2, "right moves across the top row")
T.eq(ex.gridMove(1, "left", 34), 1, "left stops at the left card")
T.eq(ex.gridMove(1, "down", 34), 3, "down moves to the bottom row")
T.eq(ex.gridMove(3, "down", 34), 5, "down advances to the next page")
T.eq(ex.gridMove(33, "down", 34), 35, "last page reaches CANCEL")
T.eq(ex.gridMove(35, "up", 34), 34, "CANCEL moves to the final toggle")
T.eq(ex.gridMove(35, "down", 34), 1, "CANCEL wraps to the first toggle")
```

Also assert that every Gen 1 row has 1–3 card lines, every line is at most eight glyph columns wide, and every Gen 2 row produced by `ex2.toggleRows(...)` satisfies the same limit.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
QOL_TOGGLES_ROOT=. LUA_PATH='/Users/shanemcgovern/dev/gen1recomp-dev/?.lua;/Users/shanemcgovern/dev/gen1recomp-dev/?/init.lua;;' luajit tests/qol_toggles_test.lua
```

Expected: failure because the new card helper exports do not exist yet.

- [ ] **Step 3: Commit the red tests**

```bash
git add tests/qol_toggles_test.lua
git commit -m "Add QoL card grid regression tests"
```

---

### Task 2: Implement pure card data and navigation helpers

**Files:**
- Modify: `main.lua` near the existing ticker helpers and `toggleRows` export

**Interfaces:**
- Produce `cardLabelLines`, `cardGeometry`, and `gridMove` exports for the headless suite.
- Add `row.cardLines` without changing `row.id`, `row.label`, `row.help`, `row.value`, or `row.step`.

- [ ] **Step 1: Add fixed grid constants and label wrapping**

Define `CARD_COLUMNS = 2`, `CARD_PAGE_SIZE = 4`, `CARD_WIDTH = 10`, `CARD_HEIGHT = 7`, and `CARD_LABEL_COLUMNS = 8`. Use the engine's `TextBox.paginate(label, CARD_LABEL_COLUMNS)[1]`, trim trailing spaces from each returned line, and return `{ "" }` for a nil/empty label. Keep the helper pure after the font/text modules are loaded.

- [ ] **Step 2: Add geometry and navigation helpers**

Implement:

```lua
local function cardGeometry(slot)
  local col = (slot - 1) % 2
  local row = math.floor((slot - 1) / 2)
  return { x = col * 10, y = row * 7, w = 10, h = 7 }
end
```

Implement `gridMove(index, action, total)` with these exact rules:

- `CANCEL` is `total + 1`.
- left/right stay inside the current two-card row.
- up subtracts two when possible; on the first page's top row it moves to `CANCEL`.
- down adds two when a real row exists; otherwise it moves to `CANCEL`.
- up from `CANCEL` selects the last toggle; down from `CANCEL` selects the first toggle.
- total zero returns the `CANCEL` index without throwing.

- [ ] **Step 3: Attach card lines and exports**

Add `row.cardLines = cardLabelLines(label)` in `toggleRows`, export the three helpers, and keep the existing ticker fields for compatibility with the shared ticker tests even though the QoL submenu will no longer draw through `OptionRows`.

- [ ] **Step 4: Run the focused suite to verify it passes**

Run the full command from Task 1. Expected: the new helper, geometry, and wrapping assertions pass; existing behavior tests remain green.

- [ ] **Step 5: Commit the helper implementation**

```bash
git add main.lua tests/qol_toggles_test.lua
git commit -m "Add QoL card grid helpers"
```

---

### Task 3: Add the private 2×2 card renderer and drawing tests

**Files:**
- Modify: `main.lua` inside the QoL submenu implementation
- Modify: `tests/qol_toggles_test.lua` near the existing menu/help rendering tests

**Interfaces:**
- Produce a private `drawCardGrid(game, rows, index)` path used only by `QolTogglesMenu:draw`.
- Continue using existing `Theme.cursor`, `Theme.moreArrow`, and `Font.drawBox` primitives.

- [ ] **Step 1: Write drawing regression tests**

Wrap `Font.drawBox`, `Font.draw`, and `Font.drawCode` in the headless test, call the registered `QolTogglesMenu:draw()` with a selected row, and assert:

- four card boxes are drawn at `(0,0,10,7)`, `(10,0,10,7)`, `(0,7,10,7)`, and `(10,7,10,7)` on the first page;
- the selected card receives the cursor at its left interior edge;
- card label lines and `ON`/`OFF` are horizontally centered within the card;
- a later-page marker is drawn when the selected rows are on a page before the final page;
- `CANCEL` is centered on the footer row.

- [ ] **Step 2: Run the test to verify it fails**

Run the full QoL command. Expected: the assertions fail because the submenu still calls `OptionRows.draw` and emits full-width row boxes.

- [ ] **Step 3: Implement the private card renderer**

Add helpers that:

1. Fill the 160×144 canvas white.
2. Draw only the four valid rows for the selected page.
3. Draw each `Font.drawBox` using `cardGeometry(slot)`.
4. Draw each `row.cardLines` centered at the card's label rows and draw the row's existing value centered below them.
5. Draw `Theme.cursor` at the selected card's left edge.
6. Draw `Theme.moreArrow` at the footer edge when another page exists.
7. Draw centered `CANCEL` and the cursor when `index == #rows + 1`.
8. Restore the final graphics color to white, matching `OptionRows.draw`.

- [ ] **Step 4: Route `QolTogglesMenu:draw` through the card renderer**

Replace the normal `OptionRows.draw` call with the private card renderer. Leave the existing help overlay after the base draw so the popup still blanks the underlying screen and uses the selected row's existing help text.

- [ ] **Step 5: Run the drawing tests to verify they pass**

Run the full QoL command and confirm the card geometry, centering, cursor, marker, and footer assertions pass.

- [ ] **Step 6: Commit the renderer**

```bash
git add main.lua tests/qol_toggles_test.lua
git commit -m "Render QoL toggles as a two-column card grid"
```

---

### Task 4: Update menu input, activation, help tests, and documentation

**Files:**
- Modify: `main.lua` in `QolTogglesMenu:update` and menu construction
- Modify: `tests/qol_toggles_test.lua` in the menu input/help sections
- Modify: `README.md` in the QoL Toggles overview/features

**Interfaces:**
- `QolTogglesMenu:update(dt)` keeps the existing `helpRequested`, `helpRow`, `helpTick`, `onCancel`, and `_qolTogglesMenu` behavior.
- Directional input calls `mod.exports.gridMove`; only A calls the selected row's `step`.

- [ ] **Step 1: Write failing input tests**

Use the existing `pressed`-table input stub to assert:

```lua
local menu = run.loader.content.screens:get("QolTogglesMenu").new(helpGame)
T.eq(menu.index, 1, "grid starts on the first card")
pressed.right = true
menu:update(1 / 60)
pressed.right = nil
T.eq(menu.index, 2, "right selects the second card")
pressed.a = true
menu:update(1 / 60)
pressed.a = nil
T.eq(state[menu.rows[2].id], true, "A toggles the selected card")
pressed.left = true
menu:update(1 / 60)
pressed.left = nil
T.eq(menu.index, 1, "left navigates without toggling")
```

Add assertions for page transitions, the partial final page, `CANCEL`, and help following the selected row after navigation.

- [ ] **Step 2: Run the test to verify it fails**

Run the full QoL command. Expected: the old update logic toggles on left/right and lacks grid movement, so the new assertions fail.

- [ ] **Step 3: Implement the new input state machine**

Keep the existing popup branch first. In normal mode:

- `up`, `down`, `left`, and `right` update `self.index = mod.exports.gridMove(...)`;
- `a` invokes the selected row's existing `step`, or exits when the selected index is `#rows + 1`;
- `b` exits;
- `start` and the latched P request continue opening/closing help exactly as before.

Remove the old `scroll` clamp call from the normal path, but it is safe to leave a compatibility `scroll = 0` field in the constructed menu state if existing callers inspect it.

- [ ] **Step 4: Update user-facing documentation**

Add a concise README note that QoL Toggles displays four cards per page, uses the directional pad for navigation, and uses A to toggle a card. Do not rename toggle IDs or rewrite historical changelog entries.

- [ ] **Step 5: Run the full suite and commit**

Run:

```bash
QOL_TOGGLES_ROOT=. LUA_PATH='/Users/shanemcgovern/dev/gen1recomp-dev/?.lua;/Users/shanemcgovern/dev/gen1recomp-dev/?/init.lua;;' luajit tests/qol_toggles_test.lua
luajit -b main.lua /private/tmp/qol_toggles_two_column_check.luac
```

Expected: all QoL checks pass and bytecode compilation exits 0.

```bash
git add main.lua README.md tests/qol_toggles_test.lua
git commit -m "Navigate QoL toggle cards with the d-pad"
```

---

### Task 5: Install the verified mod into the local game copies

**Files:**
- Read/verify: `main.lua`, `manifest.json`
- Write: `/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua`
- Write: `/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua`

**Interfaces:**
- The installed copies receive only the verified `main.lua`; repository tests, specs, and untracked options files are not copied into the game.

- [ ] **Step 1: Verify the source before installation**

Run the full QoL suite and bytecode check from Task 4, then compute the source SHA-256:

```bash
shasum -a 256 main.lua
```

- [ ] **Step 2: Back up the two current installed mod files**

Run:

```bash
cp "/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua" \
  /private/tmp/qol_toggles-pokemon-love2d-main.before-grid.lua
cp "/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua" \
  /private/tmp/qol_toggles-LOVE-pokemon-love2d-main.before-grid.lua
```

Do not modify any `options.lua` file.

- [ ] **Step 3: Copy the verified source into both current installed game paths**

Run:

```bash
cp main.lua "/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua"
cp main.lua "/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua"
```

Leave the older `pokemon-love2d-upscale` install unchanged.

- [ ] **Step 4: Verify installed hashes**

Run:

```bash
shasum -a 256 main.lua \
  "/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua" \
  "/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua"
```

Expected: all three hashes match.

- [ ] **Step 5: Check the repository state**

Run `git status -sb` and confirm only the intentional source, test, README, and plan/spec commits exist; `options.lua*` remains untracked and unstaged.
