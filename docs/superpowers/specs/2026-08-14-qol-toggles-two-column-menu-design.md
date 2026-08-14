# QoL Toggles Two-Column Menu Design

Date: 2026-08-14

## Goal

Redesign the QoL Toggles submenu from a single-column list into a retro 2×2 card grid matching the supplied mockup. The new layout should make four toggles visible at once while preserving every toggle's behavior, setting key, help text, persistence, and Gen 1/Gen 2 filtering.

## Non-goals

- Do not rename toggle IDs or migrate `options.lua` data.
- Do not change what any toggle does.
- Do not change the parent OPTIONS row.
- Do not change the existing full-screen help popup's behavior.
- Do not alter the shared `OptionRows` renderer used by other menus.

## User experience

The submenu displays four cards in row-major order:

```text
1  2
3  4
```

Each card has a Game Boy-style border, a centered wrapped label, and a centered `ON` or `OFF` value. The selected card uses the existing filled cursor glyph on its left edge. A centered `CANCEL` footer remains below the cards.

The 160×144 canvas uses two 10×7 tile cards:

- left column: `x = 0`
- right column: `x = 10`
- top row: `y = 0`
- bottom row: `y = 7`
- footer: centered on the existing bottom text row

The eight-tile card interior is the label wrapping width. Labels wrap at word boundaries when possible and split an overlong word only when necessary. Lines are centered within the card. The card height allows up to three label lines plus the value line; the test suite must confirm every shipped label fits this limit.

Four toggles form one page. A final page may contain fewer than four cards; empty card slots are not drawn or selectable. A small existing `moreArrow` marker is drawn when a later page exists.

## Navigation

The menu keeps an absolute row index for compatibility with the current help and toggle-row seams, and derives its page and card slot from that index.

- Left/right moves between the two cards in the current row and does not change a toggle value.
- Up/down moves between cards in the same column. Moving down from a populated bottom row advances to the same column on the next page. Moving up from the first row returns to the same column on the previous page when one exists.
- On the first page, up from the top row reaches the footer. On the final page, down from the last populated row reaches `CANCEL`.
- Up from `CANCEL` returns to the final toggle; down from `CANCEL` wraps to the first toggle.
- A toggles the selected card.
- B and START close the menu. The existing keyboard/controller help path still opens the selected row's help popup with P/START.

This separates navigation from activation: the directional pad chooses a card and A changes its setting.

## Implementation structure

The existing `TOGGLES` registry and `mod.exports.toggleRows` remain the source of truth for card data. Each generated row gains layout-only wrapped label lines; its `id`, `help`, `value`, and `step` contracts remain unchanged.

The QoL submenu gets a private card-grid renderer and navigation helpers in `main.lua`. The renderer is used by `QolTogglesMenu:draw` only. The shared Gen 1 `OptionRows` module and the Gen 2 local compatibility renderer remain available for other consumers and retain their current ticker behavior.

The menu state changes from a single-column scroll offset to page/card-derived positioning. Existing `helpRow`, `helpTick`, `onCancel`, and `_qolTogglesMenu` state remain intact. The help popup continues to use the selected row object, so its content and input semantics do not depend on the new layout.

## Edge cases and compatibility

- A Gen 2 boot still filters Gen 1-only toggles before calculating pages.
- A list with 1–3 rows renders only the available cards and still exposes `CANCEL`.
- A partial final page never indexes a missing row.
- Empty or malformed labels degrade to an empty label rather than throwing during draw.
- Existing saved values continue to be read through the same internal IDs, including `b_to_run`.

## Testing

Extend `tests/qol_toggles_test.lua` with:

1. Label wrapping tests asserting line count, maximum line width, centered layout inputs, and the three-line upper bound for every Gen 1 and Gen 2 visible row.
2. Grid navigation tests for left/right row movement, up/down same-column movement, page transitions, partial final pages, and `CANCEL` transitions.
3. Activation tests proving A calls the selected row's existing `step` function while directional navigation does not toggle a value.
4. Drawing tests that capture card box coordinates, selected-card cursor placement, centered labels/values, footer rendering, and the page marker.
5. Existing help-popup tests updated to construct the new menu state and verify help follows the selected card.

Run the full QoL suite, the Lua bytecode compile check, and the existing multi-mod ticker composition test when its `mods_hotkeys` fixture is available.

## Rollout

This is a presentation and input-layout change only. No migration or release-data change is required. The existing internal row IDs and options buckets remain backward-compatible with installed saves and `options.lua` files.
