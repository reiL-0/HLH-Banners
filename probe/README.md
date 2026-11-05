# Probe (draft that doubles as the first version of the app)

What the first game sessions showed: the GL drawing and the animation work; AC labels cannot be put over our drawing or clipped, so the text is drawn as glyph quads; `winsound` plays.
Still open: everything marked below. The pure parts are tested on a desktop (`python3 tests/test_*.py`); what the game's calls really do is what these sessions find out.

## Install (on the PC where you play)
The `apps/` folder of this repository has the same layout as `<AC>/apps/` (`<AC>` = `steamapps/common/assettocorsa`). Replace/copy these folders (delete the old `hlh_banners` first so no old file stays):

1. `apps/python/hlh_banners` -> `<AC>/apps/python/hlh_banners`   (the banners: no buttons, its window is only as big as the banners)
2. `apps/python/hlh_banners_settings` -> `<AC>/apps/python/hlh_banners_settings`   (a small window with buttons; open it, set things, close it)
3. `apps/lua/hlh_banners_probe` -> `<AC>/apps/lua/hlh_banners_probe`   (only to test the link with a CSP script; needs Custom Shaders Patch)

Download: https://github.com/reiL-0/HLH-Banners/archive/refs/heads/staging.zip

In the game (a practice session alone is enough) enable **HLH Banners** and **HLH Banners settings** in the app bar.

## What to do and look at
| What | Question | Good answer |
|---|---|---|
| Settings: **Mover banderas: on** | A grey banner "ARRASTRA AQUI" appears. Drag it where you want the flags. Does it move **exactly with the mouse**, without jumping to strange places? Move it near the edges of the screen too. Then turn it off. | Follows the mouse; the banners stay there |
| Settings: **Demo: on** | Four banners over 26 s (yellow folds to the icon after 5 s, blue keeps its text, track limits, winner stays). Does the text show inside the capsule, readable and sharp? Does each new banner make a radio sound, one after another, never on top of each other? | Yes |
| Settings: **Calibrar: on** | Draws marks in two ways at once and says what the game reports: the window's own corner (RED, GREEN, BLUE squares, "REL POS x,y") and the window's place on the screen (YELLOW, MAGENTA, CYAN squares, "ABS ..."), each with the yellow flag icon, plus a line "INI ok L=en D=on" (what the banners app found in the settings file). **Take a screenshot with it on**, and another after dragging the window somewhere else. Which squares are inside the window? Are they coloured? Is the text readable? | Tells me where the game puts the drawing |
| Settings: status line | The last line of the settings window says what it saved (`OK lang=en demo=on en hlh_banners`) or the error. If you press **Idioma** and the line says OK but the banners keep the old language, tell me what the calibration line `INI ... L=` says. | OK, and the banners follow |
| Settings: **Origen** | Leave it on **rel**. Only if the banners still do not follow the window when you drag it, or their colours (border, background, coloured square) are missing, press it to **abs** and tell me which of the two works. | rel works |
| Settings: **Tamano** | Cycles 75 % ... 300 %. Is the text sharp at the sizes you would use? Does the window keep the banners in place when the size changes (it grows downwards from its corner)? | Sharp up to the size you need |
| Settings: **Idioma** | auto / es / en. Does the demo text change language straight away? Is the choice kept after restarting AC? | Yes |
| Settings: **Sonido** | 100 / 70 / 40 % / off. Is 100 % loud enough? Does "off" stop everything, also what was queued? | Yes |
| Settings: **Probar audio** | One burst and a beep | Yes |
| closing AC | Does `hlh_banners/probe_result.txt` end with `shutdown: port released`? | Yes |

While the Lua probe app is enabled its yellow flag takes the place of the demo's (it is the script's line; it asks the app for the language, so **Idioma** changes its text too). To see only the demo, close the Lua app.

Then send `hlh_banners/probe_result.txt` and what you saw. A screenshot of the demo and one dragging the banners helps a lot.

## The CSP side
The Lua app `hlh_banners_probe` sends a yellow flag for 6 s and nothing for 6 s, every 150 ms. With the demo **off** the capsule must open, fold at 5 s and close by itself, and make its radio sound once per appearance.
Its small window must say `tick 200 {"render_age_ms": ..., "lang": "auto", "v": 1}` and `echo ... "sha256": "2cf24dba..."` (SHA-256 of "hello"). The answer can differ when the same probe runs as an online script of a test server
(`probe/hlh_banners_probe.lua`): the permissions of a server script are not the same as an app's.
If the Lua app does not show in the app bar, tell me: its manifest was written from memory of how CSP apps are described.

## If something fails
- `import socket FAIL` in `probe_result.txt`: copy a 32-bit Python 3.3 `Lib` into `hlh_banners/stdlib/`.
- Text too small/blurry: pick a bigger size; at 250 % and above the app uses a sharper set of letters.
- The window jumps when dragged: say where it ends up compared to where you dropped it (the window is now only as big as the banners, which should fix it).
