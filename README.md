# pixelscroll.nvim

Pixel-smooth trackpad scrolling for Neovim in the terminal: text glides with
your fingers, the way it does in Zed or a browser, instead of jumping a whole
line at a time.

This is not a scroll *animation* plugin. [neoscroll.nvim] and [cinnamon.nvim]
animate scrolling by moving the view one line at a time, quickly. Every frame
is still a whole-line position. pixelscroll.nvim moves text by fractions of a
line, so a slow two-finger drag tracks your fingers pixel by pixel.

It needs a terminal that can shift part of the screen by pixels. Today that
is one experimental terminal: **Ghostty Smooth**, a fork of Ghostty
([tlpinney/ghostty], branch `smooth-scroll`). Everywhere else the plugin
does nothing, and Neovim scrolls as usual.

## Why terminals scroll in lines

A terminal is a grid of character cells. Programs can only say "put this
character in this cell," so a TUI scrolls by redrawing rows one line over.
Trackpads report movement in pixels, but the terminal turns them into whole
wheel "notches" and the program moves whole lines.

The program can't fake it either. Anything it animates runs on its own
clock, while the terminal draws on the display's, so frames get uneven steps
and visibly stutter. The pixel offset has to live inside the terminal's
renderer.

## How it works

The terminal and the program split the job with a small protocol:

1. **The program declares a scroll region.** Each Neovim window says "my text
   area, these rows and columns, is a scroll view. I'm at line `pos` of
   `max`." The declaration is an APC escape sequence, which terminals that
   don't know it ignore:

   ```
   ESC _ smooth ; id ; top ; bottom ; left ; right ; pos ; max ESC \
   ```

2. **The terminal owns the pixels.** Over a declared region, Ghostty Smooth
   collects the trackpad's pixel movement itself. It draws the region shifted
   up by the leftover fraction of a line, clipped to the region, on its own
   frame clock, so motion is even.

3. **Whole lines become ordinary wheel events.** Each time a full line's worth
   of movement builds up, the terminal sends Neovim one normal mouse-wheel
   event. pixelscroll sets `'mousescroll'` to one line, so Neovim moves
   exactly one line per event and redraws as usual.

4. **The program acknowledges.** Neovim re-declares the region after every
   redraw. When the terminal sees `pos` advance by the lines it asked for, it
   drops them from its offset, so the view never jumps back while Neovim
   catches up.

5. **One spare row.** A window's last row holds the next line of text, and the
   terminal keeps it hidden until the text slides up into it. That's why a
   window shows one line less while pixelscroll is active.

The declaration has to reach the terminal in the same screen update as the
text it describes, or the view would jump for a frame. pixelscroll sends it
with Neovim 0.12's `nvim_ui_send()` from a decoration provider's `on_end`,
which puts it in the TUI's output stream right after the redraw's text, inside
the same synchronized update (`'termsync'`).

## Requirements

- Neovim 0.12 or later (`nvim_ui_send()`).
- Ghostty Smooth: build [tlpinney/ghostty] (branch `smooth-scroll`); see its
  `SMOOTH_SCROLL.md`. It installs as a separate app, "Ghostty Smooth", beside
  the official Ghostty.
- Optional, for [herdr]: the [tlpinney/herdr] fork (branch `smooth-scroll`)
  relays regions from panes to the terminal. Set `SMOOTH_SCROLL=1` there (see
  below).

## Install

lazy.nvim / LazyVim:

```lua
{ "tlpinney/pixelscroll.nvim", lazy = false, opts = {} }
```

Any other way: put it on `'runtimepath'` and call

```lua
require("pixelscroll").setup()
```

In LazyVim it turns off LazyVim's own line-by-line scroll animation
(`snacks.nvim` scroll) while active, since that would fight the pixel
scrolling.

## Usage

There's nothing to do: scroll with the trackpad. pixelscroll asks the terminal
at startup whether it supports regions (`ESC _ smooth;? ESC \`, answered with
`smooth;ok;2`) and only turns on if it does.

| | |
|---|---|
| `:PixelScroll on` / `off` / `toggle` | turn it on or off, e.g. to compare |
| `SMOOTH_SCROLL=1` | force on (needed inside herdr, which doesn't pass the query to the terminal) |
| `SMOOTH_SCROLL=0` | force off |
| `require("pixelscroll").status()` | `"≈ smooth"` while active, for a statusline |

Lualine:

```lua
lualine_x = { function() return require("pixelscroll").status() end },
```

### See the difference

Open the same long file in two Ghostty Smooth windows side by side, one with
pixelscroll and one without (`SMOOTH_SCROLL=0 nvim file`), and drag slowly on
the trackpad in each.

## Limitations

- **One terminal.** Only Ghostty Smooth implements the protocol so far.
- **Wrapped lines and folds.** The position counts buffer lines, not screen
  rows, so a long wrapped line can make one step uneven.
- **Floating windows** over a scrolling window slide with it until the next
  redraw.
- **Mouse wheels** (not trackpads) still move a line per notch; only
  pixel-precise input is smoothed.
- Each window shows **one line less**: the hidden spare row.

## Prior art

As far as I could find, no terminal lets programs pixel-scroll a region.
The nearest pieces:

- [kitty]'s `pixel_scroll` (0.46) smoothly scrolls kitty's own scrollback, but
  explicitly not full-screen programs like Neovim.
- [Textual] uses pixel-precise mouse reporting for smoother scrollbars; text
  still moves by rows.
- Web and mobile terminal front-ends ([webtty], Orca) shift their scrollback by
  pixels and note that mouse-tracking programs can't be scrolled that way.
- xterm.js has a long-open [smooth scrolling issue][xterm-1140].
- DEC terminals had a hardware smooth-scroll mode (`ESC [ ? 4 h`) that eased
  whole-screen line scrolling.
- [Neovide] scrolls Neovim smoothly by being a GUI that draws Neovim's grid
  itself.

## Related

- [tlpinney/ghostty]: the terminal side, with the protocol in `SMOOTH_SCROLL.md`.
- [tlpinney/herdr]: relays regions through the herdr multiplexer.

## License

MIT

[neoscroll.nvim]: https://github.com/karb94/neoscroll.nvim
[cinnamon.nvim]: https://github.com/declancm/cinnamon.nvim
[tlpinney/ghostty]: https://github.com/tlpinney/ghostty/tree/smooth-scroll
[tlpinney/herdr]: https://github.com/tlpinney/herdr/tree/smooth-scroll
[herdr]: https://github.com/herdrdev/herdr
[kitty]: https://sw.kovidgoyal.net/kitty/conf/
[Textual]: https://textual.textualize.io/blog/2025/02/16/smoother-scrolling-in-the-terminal-mdash-a-feature-decades-in-the-making/
[webtty]: https://github.com/jesse23/webtty/pull/47
[xterm-1140]: https://github.com/xtermjs/xterm.js/issues/1140
[Neovide]: https://neovide.dev
