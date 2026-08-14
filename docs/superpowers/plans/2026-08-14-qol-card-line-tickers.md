# QoL Card-Line Tickers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make overflowing text in the QoL Toggles 2×2 cards ticker-scroll per logical line without splitting words, while leaving help-popup and other menu rendering unchanged.

**Architecture:** Keep the existing 10×7 card grid and row data as the source of truth. Replace the card label helper's hard glyph-boundary wrapping with whole-word packing that allows an overlong single word to remain on one logical line. Add per-line ticker metadata to toggle rows and draw only those lines with the existing glyph-safe ticker helper clipped to the card's 64-pixel interior.

**Tech Stack:** Lua/LuaJIT, the existing Gen1Recomp `Font` and `TextBox` modules, headless QoL tests, and the existing local game mod directories.

## Global Constraints

- Apply the change only to labels rendered inside the QoL 2×2 card grid.
- Never split a word across logical card-label lines.
- Judge every logical line independently against the 64-pixel card interior.
- Keep fitting lines centered and static; ticker-scroll only overflowing lines.
- Reuse the existing `tickerOffset`, `drawTickerLabel`, and `row.tick` timing.
- Preserve card values, cursor placement, navigation, persistence, generation filtering, help popup behavior, and non-card ticker behavior.
- Keep all shipped card labels within the existing three-line card height.
- Do not stage `options.lua`, `options.lua.bak`, or `options.lua.tmp`.
- Install only to the two active non-upscale targets after verification; leave the upscale target untouched.

---

### Task 1: Add red tests for whole-word lines and per-line ticker metadata

**Files:**
- Modify: `tests/qol_toggles_test.lua` near the existing card-helper assertions and card renderer test

**Interfaces:**
- Existing `ex.cardLabelLines(label) -> string[]` remains available.
- Toggle rows gain `row.cardTickers`, an array indexed like `row.cardLines`; each entry is either `nil` or `{ overflow = number }`.

- [ ] **Step 1: Add the failing helper and row assertions**

Add these assertions alongside the existing card-label checks:

```lua
T.same(ex.cardLabelLines("BADGELESS MOVES"),
       { "BADGELESS", "MOVES" },
       "card labels keep an overlong word intact")

local badgelessRow
for _, row in ipairs(rows) do
  if row.id == "badgeless_moves" then badgelessRow = row end
end
T.neq(badgelessRow, nil, "BADGELESS MOVES row exists")
if badgelessRow then
  T.neq(badgelessRow.cardTickers, nil,
        "toggle rows expose per-line card ticker metadata")
end
if badgelessRow and badgelessRow.cardTickers then
  T.eq(badgelessRow.cardLines[1], "BADGELESS",
       "the long word remains one card line")
  T.eq(badgelessRow.cardLines[2], "MOVES",
       "the following word remains its own card line")
  T.neq(badgelessRow.cardTickers[1], nil,
        "the overlong card line gets ticker metadata")
  T.eq(badgelessRow.cardTickers[2], nil,
       "the fitting card line stays static")
end
```

Change the existing per-line width assertion from a character-count limit to
the actual card pixel budget, allowing only explicitly tickered lines to be
over budget:

```lua
local cardLineWidth = 64
for _, row in ipairs(rows) do
  for i, line in ipairs(row.cardLines) do
    local width = require("src.render.Font").width(line)
    T.check(width <= cardLineWidth
              or (row.cardTickers and row.cardTickers[i] ~= nil),
            "card line fits or ticks (" .. row.id .. ": " .. line .. ")")
  end
end
```

- [ ] **Step 2: Add the failing renderer assertion**

Add a focused renderer case using a one-row `helpMenu.rows` fixture. Wrap
`Font.drawCode`, call `helpMenu:draw()` with the long line selected, and assert
that the ticker glyphs for the first line stay inside the left card's interior:

```lua
local savedCardRows = helpMenu.rows
helpMenu.rows = {
  {
    label = "BADGELESS MOVES",
    cardLines = { "BADGELESS", "MOVES" },
    cardTickers = { { overflow = 8 }, nil },
    tick = 0,
    value = function() return "OFF" end,
  },
}
helpMenu.index = 2 -- CANCEL, so the card itself has no cursor glyph at y=8
local tickerCodes = {}
local savedCardDrawCode = Font.drawCode
Font.drawCode = function(code, x, y)
  if y == 8 and x >= 8 and x < 72 then
    tickerCodes[#tickerCodes + 1] = { code = code, x = x, y = y }
  end
  return savedCardDrawCode(code, x, y)
end
helpMenu:draw()
Font.drawCode = savedCardDrawCode
helpMenu.rows = savedCardRows
T.eq(#tickerCodes, 8, "the long card line draws eight clipped glyphs")
for _, drawn in ipairs(tickerCodes) do
  T.check(drawn.x >= 8 and drawn.x + 8 <= 72,
          "card ticker glyph stays inside the card interior")
end
```

- [ ] **Step 3: Run the suite to verify the new tests fail for the missing behavior**

Run from the mod workspace:

```sh
QOL_TOGGLES_ROOT=. LUA_PATH='/Users/shanemcgovern/dev/gen1recomp-dev/?.lua;/Users/shanemcgovern/dev/gen1recomp-dev/?/init.lua;;' luajit tests/qol_toggles_test.lua
```

Expected failure: the current helper splits the overlong word and rows do not
yet expose `cardTickers`; the renderer assertion must also fail until Task 3.

- [ ] **Step 4: Commit the red tests**

```sh
git add tests/qol_toggles_test.lua
git commit -m "Add card line ticker regression tests"
```

---

### Task 2: Implement whole-word card-label packing and ticker metadata

**Files:**
- Modify: `main.lua` near `CARD_LABEL_COLUMNS`, `cardLabelLines`, and `toggleRows`

**Interfaces:**
- Preserve `cardLabelLines(label) -> string[]`.
- Add private `cardLineTickers(lines) -> table` returning an index-aligned table
  whose overflowing entries contain `{ overflow = Font.width(line) - 64 }`.
- Add `row.cardTickers` without changing existing row IDs, labels, help text,
  values, or activation callbacks.

- [ ] **Step 1: Replace hard wrapping with whole-word packing**

Use the loaded `Font` module to measure words in pixels. Keep a candidate word
on the current line only when the candidate line is within 64 pixels; if the
word itself exceeds 64 pixels, emit it as one line so it can ticker-scroll.
Return `{ "" }` for an empty label and trim only separator whitespace introduced
by the packer.

The helper must make these results true:

```lua
cardLabelLines("FULL HEAL CATCH") == { "FULL", "HEAL", "CATCH" }
cardLabelLines("BADGELESS MOVES") == { "BADGELESS", "MOVES" }
```

- [ ] **Step 2: Add per-line ticker metadata**

Define the card interior width once:

```lua
local CARD_LABEL_WIDTH = (CARD_WIDTH - 2) * 8
```

For each logical line, measure `Font.width(line)`. Store `nil` when it fits;
otherwise store `{ overflow = width - CARD_LABEL_WIDTH }`. Attach the resulting
array to each row as `cardTickers` next to `cardLines`.

- [ ] **Step 3: Run the focused test and confirm the data model passes**

Run the same `luajit tests/qol_toggles_test.lua` command. The helper and row
metadata assertions should pass; the renderer clipping assertion may remain
red until Task 3.

- [ ] **Step 4: Commit the data-model implementation**

```sh
git add main.lua
git commit -m "Keep long card words intact"
```

---

### Task 3: Draw overflowing card lines with the existing ticker

**Files:**
- Modify: `main.lua` inside the private `drawCardGrid` path
- Modify: `tests/qol_toggles_test.lua` only if the focused renderer test needs
  an exact call-shape correction after the data-model implementation

**Interfaces:**
- Consume `row.cardLines`, `row.cardTickers`, and `row.tick`.
- Preserve the existing centered static-line and card-value draw positions.

- [ ] **Step 1: Add the per-line draw branch**

Replace the direct `drawCardCentered(line, card, y)` call with this behavior:

```lua
local ticker = row.cardTickers and row.cardTickers[lineIndex]
local y = (card.y + lineIndex) * 8
if ticker then
  drawTickerLabel(Font, line, tickerOffset(row.tick or 0, ticker.overflow),
                  (card.x + 1) * 8, y, CARD_LABEL_WIDTH)
else
  drawCardCentered(line, card, y)
end
```

Set the draw color to black before either branch and restore the existing color
state after the card grid. The ticker window is one tile inside the card border,
so its x/y geometry cannot bleed into the border or neighboring card.

- [ ] **Step 2: Run the full suite and bytecode check**

Run:

```sh
QOL_TOGGLES_ROOT=. LUA_PATH='/Users/shanemcgovern/dev/gen1recomp-dev/?.lua;/Users/shanemcgovern/dev/gen1recomp-dev/?/init.lua;;' luajit tests/qol_toggles_test.lua
luajit -b main.lua /private/tmp/qol_toggles_card_line_tickers.luac
git diff --check
```

Expected: all QoL checks pass, LuaJIT emits bytecode without an error, and the
diff has no whitespace errors.

- [ ] **Step 3: Commit the renderer implementation**

```sh
git add main.lua tests/qol_toggles_test.lua
git commit -m "Ticker overflow in QoL card lines"
```

---

### Task 4: Update documentation and reinstall the verified mod

**Files:**
- Modify: `README.md` in the Notes section
- Verify: `main.lua`, `tests/qol_toggles_test.lua`, and the two installed mod copies

**Interfaces:**
- Document that only overflowing 2×2 card lines ticker and that words remain
  intact.
- Do not change `options.lua*`.

- [ ] **Step 1: Update the user-facing note**

Replace the existing card-label note with:

```markdown
- In the 2×2 QOL TOGGLES cards, labels wrap only between whole words. Any
  individual line wider than the card interior ticker-scrolls in place; shorter
  lines stay centered.
```

- [ ] **Step 2: Run final verification before installation**

Run the full QoL suite, bytecode compilation, and `git diff --check` again after
the README edit. Confirm the working tree contains only the intended tracked
changes plus the pre-existing untracked `options.lua`, `options.lua.bak`, and
`options.lua.tmp`.

- [ ] **Step 3: Commit documentation**

```sh
git add README.md
git commit -m "Document QoL card line tickers"
```

- [ ] **Step 4: Back up the active installed copies**

Before overwriting either target, refresh these backups:

```sh
cp "/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua" /private/tmp/qol_toggles-pokemon-love2d-main.before-card-line-tickers.lua
cp "/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua" /private/tmp/qol_toggles-LOVE-pokemon-love2d-main.before-card-line-tickers.lua
```

- [ ] **Step 5: Copy the verified source into both active targets**

```sh
cp main.lua "/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua"
cp main.lua "/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua"
```

Leave `/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d-upscale/mods/qol_toggles/main.lua` unchanged.

- [ ] **Step 6: Verify byte-for-byte installation**

```sh
shasum -a 256 main.lua \
  "/Users/shanemcgovern/Library/Application Support/pokemon-love2d/mods/qol_toggles/main.lua" \
  "/Users/shanemcgovern/Library/Application Support/LOVE/pokemon-love2d/mods/qol_toggles/main.lua"
```

All three hashes must match before reporting the local installation ready for
testing.
