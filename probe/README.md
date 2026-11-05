# Probe: the Lua app

Decision (2026-11-05): the banners are a **CSP Lua app**. In the Python draft the game's grey frame could not be hidden, labels did not show over our drawing, and text could not be clipped or measured;
the CSP Lua documentation gives the window flags `NO_BACKGROUND`, `NO_TITLE_BAR` and `AUTO_RESIZE` (https://github.com/ac-custom-shaders-patch/acc-lua-sdk/wiki/Lua-apps), and ImGui has clip rectangles and text measure.
**Nothing here has run inside the game yet.** The logic is tested with a stand-in game (`luajit tests/test_lua_app.lua apps/lua/hlh_banners/hlh_banners.lua`); what the game's calls really do is what this session finds out.

## Install (on the PC where you play; needs Custom Shaders Patch)
Delete the old HLH folders first (`apps/python/hlh_banners*`, `apps/lua/hlh_banners_probe`), then copy from this repository's `apps/lua/` to `<AC>/apps/lua/` (`<AC>` = `steamapps/common/assettocorsa`):
1. `hlh_banners`  (the app: two windows, the banners and the settings)
2. `hlh_banners_probe`  (plays the hub's part: sends banners to the app and shows what comes back)

Download: https://github.com/reiL-0/HLH-Banners/archive/refs/heads/staging.zip

In the game (a practice session alone is enough) enable **HLH Banners** (it opens two windows: the frameless banners and "HLH Banners settings") and **HLH Banners probe** in the app bar.

## What to look at
| What | Question | Good answer |
|---|---|---|
| The banners window | With the demo on (default): is there **any grey box or title** around the banners, with the mouse visible or hidden, still or while you move it? Can you move it (drag the banners)? Does it stay where you leave it, also after restarting AC? | No frame at all; moves; remembered |
| The capsule | Rounded border, coloured badge with the flag icon, pop, the text unfolding, folding to the icon after 5 s (yellow, track limits), staying (blue), the winner staying, the two-step closing? Is the text **cut at the panel's edge** while it opens? Typeface (JetBrains Mono) or a plain one? | As in the preview (https://claude.ai/artifact/EdFFyHPdqXMJdrTCfH3fLf) |
| **Before the demo: close the probe** | While **HLH Banners probe** is enabled it sends a yellow flag for 6 s and then nothing, and a script's lines take priority over the demo, so the demo looks stuck on one yellow banner. Disable the probe in the app bar to see the demo (the settings window now warns when a script covers it). | You see the demo |
| Settings window: **Demo** | Cycles off / normal / **varias**. "varias": eight banners of every kind appear one by one over 12 s and stay for a while (40 s loop). The information ones (yellow, track limits, pits closed, white, black and white) fold to their icon after 5 s and stay as icons stacked; blue, give-back and the winner keep their text. How does a pile of icons look? Is it clear which is which? | You judge |
| Settings window: **Tamano** | 75 % ... 300 %: is it sharp and does the window follow the size? | Yes |
| Settings window: **Idioma** | The demo text changes language straight away? Kept after restarting AC? | Yes |
| Settings window: **Sonido / Probar audio** | A short burst and a beep, one per new banner, one after another? (`audio:` in the diagnostics says what happened) | Yes, loud enough |
| Settings window: **Texto** | The text is now drawn as pictures of letters (not DirectWrite, which the game builds late). Does it appear **from the first frame of the unfolding and grow with the panel**, letter by letter? Compare with **Texto: DirectWrite** if you want. `letras cargadas: N / 580` in the diagnostics must reach the total in a few seconds after starting the session. Is it sharp at your size (the sharper set is used above 200 %)? | The text follows the animation |
| Settings window: **Diagnostico** | Which functions say **NO**? (`ui.pushClipRect`, `ui.drawRect`, `ui.measureDWriteText`, `ui.MediaPlayer`, `ac.onSharedEvent`...) | All **si** |
| Probe window | `heartbeat from the app: ... s ago` and `sent: N`. With the probe running, its yellow flag replaces the demo, in the language you picked in the settings | Heartbeat arrives; the language follows |

Then take a screenshot of the banners (with and without the mouse), of the settings window with its diagnostics, and of the probe window.

## The same probe as an online script
`probe/hlh_banners_probe.lua` is the same probe as a script of a test server (a server's script is what the hub will be): does a **server** script reach the app through shared events? The answer can differ from the app one.

## If something fails
- The app does not appear in the app bar: tell me; the manifest was written from the documentation, not from a working example.
- The text is not clipped: the diagnostics will say `ui.pushClipRect: NO`; the app then draws text only once the panel is fully open.
- No icons: `carpeta de la app:` in the diagnostics shows the path the game gave; `None`/`nil` means icons and sound cannot be found.
