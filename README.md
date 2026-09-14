# FB-MANDELBROT-EXPLORER

An interactive Mandelbrot explorer written entirely in COBOL, drawing straight
to the Linux framebuffer (`/dev/fb0`). No libraries, no C, no GPU: one source
file, GnuCOBOL, a console.

It navigates in a low-res preview mode and renders on demand at full
resolution, and it zooms to a half-width of 10⁻³⁰ (about 2 × 10³⁰
magnification) using perturbation theory.

## Requirements

- Linux with a framebuffer console (`/dev/fb0`, 32 bpp, no row padding)
- GnuCOBOL 3.1.2 or later (`apt install gnucobol3` on Debian/Ubuntu)
- root, or write access to `/dev/fb0`

## Build

```sh
cobc -O2 -x -free -fnotrunc -o FB-MANDELBROT-EXPLORER FB-MANDELBROT-EXPLORER.cob
```

`-fnotrunc` is required: it turns integer bookkeeping into native code and
lets the pixel cache use `-1` as an "unset" marker. Don't add `-Wall`; cobc
3.1.2 crashes on the `>>DEFINE` lines with it (the build is warning-free
without it).

The screen size is set by the two `>>DEFINE CONSTANT` lines at the top of the
source (default 1920 × 1080). Change them and rebuild; everything else is sized
from them. Any size works: when a preview block size doesn't divide the
screen, the last row and column of blocks are clipped at the edge.

## Run

From a raw console (not inside a desktop session):

```sh
sudo sh -c 'export COB_TIMEOUT_SCALE=2; setterm -cursor off; ./FB-MANDELBROT-EXPLORER; setterm -cursor on'
```

`COB_TIMEOUT_SCALE=2` makes the keyboard poll cost 10 ms instead of 1 s on
GnuCOBOL builds that read the setting only at start-up; the program also sets
it itself and measures what it got at start-up.

## Controls

| Key | Action |
|---|---|
| Arrow keys or `W` `A` `S` `D` | pan by 15 % of the view |
| `+` or `=` / `-` | zoom in / out (×0.8 / ×1.25) |
| `[` / `]` | halve / double the iteration budget |
| `c` | cycle palette stretch (1×, 2×, 4×, 8×, 16×) |
| `r` | full-resolution render; any key aborts it, or returns to the preview once it's done (`q` there quits) |
| `q` | quit (prints the current location) |

While navigating you see a blocky preview. Its block size adapts between 2 and
12 pixels to keep preview frames at a few hundred milliseconds whatever the
zoom level; if a key arrives while a preview is still rendering, the frame is
dropped and the key acted on immediately. The iteration cap grows
automatically with zoom depth; `[` and `]` scale it if a view looks empty
(needs more) or slow (needs fewer).

## Environment variables

| Variable | Effect |
|---|---|
| `MB_CENTER_X`, `MB_CENTER_Y`, `MB_HALF_WIDTH` | start at this view. Plain decimals (up to 36 places) or `1.5e-20`. `r` and `q` print the current view in exactly this form, so a location can be saved and revisited. |
| `MB_PREVIEW=n` | pin the preview block size (2, 3, 4, 5, 6, 8, 10 or 12) instead of adapting it |
| `MB_DUMP=path` | after every completed frame, write each render pixel's iteration count to this text file (header line, then one count per line, row-major). Used by `tests/verify.py`. |
| `MB_FB=path` | write frames somewhere other than `/dev/fb0`. A plain file works: raw BGRA, width × height × 4 bytes, which e.g. Python/PIL can turn into a PNG. |
| `MB_KEYS=keys` | play these keys instead of reading the keyboard, then quit. `U` `D` `L` `R` stand in for the arrow keys. For testing without a terminal (with `MB_FB`). |
| `MB_POLL=on` / `off` | skip the keyboard-poll calibration and force mid-render interrupts on or off |
| `MB_BRUTE=1` | iterate every pixel, no rectangle subdivision (reference / benchmark) |
| `MB_NOPERTURB=1` | never use perturbation (reference; wrong below half-width 1e-11) |

Example: render a saved spot straight to a file without touching the
framebuffer or keyboard:

```sh
MB_CENTER_X=-1.99999999999999999995 MB_CENTER_Y=0 MB_HALF_WIDTH=1e-24 \
MB_FB=frame.raw MB_KEYS=rq ./FB-MANDELBROT-EXPLORER
```

## How it gets its speed

- **Decimal fixed point instead of floating point.** GnuCOBOL 3.1.2 sends every
  `COMPUTE` through its arbitrary-precision decimal engine, and converting
  `COMP-2` doubles in and out of it costs ~8 µs per iteration of z² + c. The
  same loop on `PIC S9(2)V9(16) COMP-5` (64-bit integers with 16 implied
  decimals) costs ~0.42 µs.
- **Mariani-Silver rectangle subdivision.** Only the borders of rectangles are
  iterated; a rectangle whose border is one colour is filled with a `memcpy`.
- **Mirror symmetry** whenever the real axis runs through the middle of the
  frame — exact in decimal arithmetic, so it survives zooming and horizontal
  panning.
- **Native integer bookkeeping.** With `-fnotrunc`, `ADD`/`SUBTRACT` on `COMP-5`
  and `SET` on `INDEX` items compile to plain C; `COMPUTE` and `MULTIPLY` never
  do, so the per-pixel path uses lookup tables and additions only.
- **Perturbation theory** below a half-width of 1e-9: one reference orbit at 38
  digits (cheap, 2.5 µs per iteration), then every pixel iterates only its
  offset from it in the same 16-decimal arithmetic, with the offset pre-scaled
  by a power of ten so a 64-bit word carries values down to 1e-32. Glitches are
  avoided by rebasing (Zhuoran's method), so a single reference is enough.
  Verified pixel-for-pixel against a 256-bit reference at half-widths 1e-24 and
  1e-28.

## Known limits

- The direct loop is decimal fixed point, not `COMP-2`, on purpose: on
  GnuCOBOL 3.1.2 a `COMPUTE` on doubles goes through the decimal engine with a
  double→decimal→double conversion per operand and measures ~19× slower
  (8 µs vs 0.42 µs per iteration on my machine). Worth re-measuring on newer compilers.
- Rectangle subdivision assumes escape-time bands are connected at pixel
  resolution. Filaments thinner than a pixel that don't touch a rectangle
  border can be filled over; in practice this is a handful of pixels per
  frame. `MB_BRUTE=1` shows the difference.
- Zoom is clamped at half-width 1e-30, where the 36-decimal viewport stops
  resolving the pixel pitch.
- Iteration cap is 50 000. Some famous deep locations want more; those areas
  simply render black.
- The framebuffer is assumed to have no padding between rows
  (`line_length = width × 4`). If your display shows a skewed image, that's
  why; the record size in the `FD` would need adjusting.
- If WASD works but the arrow keys don't, your GnuCOBOL build reports
  different key codes: temporarily `DISPLAY WS-CRT-STATUS` in `HANDLE-KEY`'s
  `WHEN OTHER` branch, press an arrow, and fix the four `COB-SCR-KEY-*` values.
