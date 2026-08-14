# QoL Card-Line Ticker Design

## Goal

Keep labels in the QoL Toggles 2×2 card menu readable without splitting words
across lines. Only the card labels are in scope; the full-width help popup and
other menus keep their existing rendering.

## Behavior

- Card labels are packed by whole words into the existing label area.
- Shipped labels remain within the existing three-line card height.
- A word longer than the card's eight-glyph interior remains intact on one
  logical line instead of being split across lines.
- Each logical line is evaluated independently against the card's 64-pixel
  interior width.
- Lines that fit are centered in the card and remain static.
- Lines wider than the interior use a horizontal ticker, clipped to the card
  interior, so the complete line can be read over time without bleeding into
  the border or adjacent card.
- The existing card ticker timing is reused. Lines in the same card share the
  row's ticker clock, while short lines remain centered.
- Card values, cursor placement, navigation, persistence, generation filtering,
  help popup behavior, and non-card ticker behavior are unchanged.

## Implementation shape

The existing card-label helper will return whole-word logical lines. Toggle rows
will retain `row.cardLines` and additionally carry per-line ticker metadata for
the lines whose measured width exceeds the card interior. The private card
renderer will draw each line independently: static lines through the existing
centered draw path and overflowing lines through the existing glyph-safe ticker
draw helper with a card-local clip window.

The card interior is the area one tile inside each 10×7 card: 64 pixels wide,
starting at `(card.x + 1) * 8`. Ticker offsets use the existing
`row.tick`/`tickerOffset` timing so the menu update loop needs no new input or
state behavior.

## Testing

Add regression coverage for:

- `BADGELESS MOVES` producing intact logical words rather than a split word.
- A long single word receiving ticker metadata while a fitting line does not.
- The renderer clipping and drawing a card ticker within its card interior.
- Existing card geometry, centered labels, values, navigation, help, and full
  QoL regression coverage remaining green.

Verification will include the QoL headless suite, LuaJIT bytecode compilation,
`git diff --check`, and byte-for-byte installation checks after copying the
verified `main.lua` to the two active non-upscale local game mod directories.
