# Probe (draft that doubles as the first version of the app)

Answers the open questions before the real app is finished. **Nothing here has run inside Assetto Corsa yet.**
The pure parts are tested on a desktop (`python3 tests/test_capsule.py`, `test_guard.py`, `test_app_smoke.py`); what the game's calls really do is what this session finds out.

## Install (on the PC where you play)
The `apps/` folder of this repository has the same layout as `<AC>/apps/` (`<AC>` = `steamapps/common/assettocorsa`). Copy its two folders:

1. `apps/python/hlh_banners` -> `<AC>/apps/python/hlh_banners`  (with its `icons/` folder inside)
2. `apps/lua/hlh_banners_probe` -> `<AC>/apps/lua/hlh_banners_probe`  (this one needs Custom Shaders Patch)

Download: https://github.com/reiL-0/HLH-Banners/archive/refs/heads/staging.zip (unzip it, copy the two folders).

In the game: start a practice session (alone is enough), open the app bar on the right of the screen and enable **HLH Banners probe** (the Python one, a window with four buttons) and **HLH Banners probe** (the Lua one, a small window with text).
If `probe_result.txt` says `import socket FAIL`, copy a 32-bit Python 3.3 `Lib` into `hlh_banners/stdlib/`.
Playing on Linux with Proton: the same folders, inside the Proton prefix's game folder; `Audio` (winsound) may not work there, and that is a valid answer to note.

## What to look at (write down what you see; then send `apps/python/hlh_banners/probe_result.txt`)
| Button / thing | Question | Good answer |
|---|---|---|
| **Demo: on** | Does the capsule draw: rounded border, coloured badge, the icon, the pop, the text unfolding, folding, the closing in two steps? Four banners over 26 s: yellow (folds to the icon after 5 s), blue (keeps its text), track limits, winner (stays). | Looks like the preview (https://claude.ai/artifact/EdFFyHPdqXMJdrTCfH3fLf) |
| the text | AC apps cannot clip or measure text. While the panel opens, is the text visible outside the capsule? Is the real width close to the estimate (the text should not touch the right edge)? | If it spills, we need another way (see below) |
| **Mascara: on** | Does a plain quad drawn in the render callback hide the text label behind it? | Text cut at the panel's edge = the text can be clipped |
| **Audio** | Do you hear a short burst of noise and a beep (winsound on a generated wav)? | Yes, and not too quiet |
| **Idioma** | Cycles auto / es / en; is it kept after restarting AC? (`hlh_banners.ini`) | Kept |
| closing AC | Does `probe_result.txt` end with `shutdown: port released`? | Yes |

## The CSP side
The Lua app is `apps/lua/hlh_banners_probe` (installed above). Later, `probe/hlh_banners_probe.lua` is the same probe as an online script of a test server: the answer can differ between the two.
It sends a yellow flag for 6 s and nothing for 6 s, every 150 ms. With the demo **off**, the capsule must open, fold at 5 s, and close by itself. The text under the CSP window must say
`tick 200 {"render_age_ms": ..., "lang": "auto", "v": 1}` and `echo ... "sha256": "2cf24dba..."` (SHA-256 of "hello").
Hide the app (the AC app bar): `render_age_ms` must keep growing while the answer stays 200 (that is why the hub looks at it, not at the 200).

## If the text cannot be clipped
Plan B, in this order: (1) reveal the text only once its panel is fully open and hide it before it folds (the capsule moves, the text fades in/out); (2) draw the texts as small images the hub
renders... not possible from CSP; (3) move the drawing to a CSP Lua app (`apps/lua`, which has clip rectangles and text measure), which the earlier debate preferred.
