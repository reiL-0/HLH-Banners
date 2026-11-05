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
| Settings window: **Tamano** | 75 % ... 300 %: is it sharp and does the window follow the size? | Yes |
| Settings window: **Idioma** | The demo text changes language straight away? Kept after restarting AC? | Yes |
| Settings window: **Sonido / Probar audio** | A short burst and a beep, one per new banner, one after another? (`audio:` in the diagnostics says what happened) | Yes, loud enough |
| Settings window: **Precalentar texto** and **Fuente** | The text used to appear late and not follow the unfolding. With **Precalentar texto: on** (default) a new banner first draws its text unseen for 0.15 s and then opens. Compare on/off with the demo: is the text there from the first frame of the unfolding? Is it late **only the first time each text shows** (the demo repeats every 26 s) or **every time**? Then try **Fuente: del juego**: faster? Look at `fps:` in the diagnostics too. | Text follows the unfolding from the first frame |
| Settings window: **Diagnostico** | Which functions say **NO**? (`ui.pushClipRect`, `ui.drawRect`, `ui.measureDWriteText`, `ui.MediaPlayer`, `ac.onSharedEvent`...) | All **si** |
| Probe window | `heartbeat from the app: ... s ago` and `sent: N`. With the probe running, its yellow flag replaces the demo, in the language you picked in the settings | Heartbeat arrives; the language follows |

Then take a screenshot of the banners (with and without the mouse), of the settings window with its diagnostics, and of the probe window.

## The same probe as an online script
`probe/hlh_banners_probe.lua` is the same probe as a script of a test server (a server's script is what the hub will be): does a **server** script reach the app through shared events? The answer can differ from the app one.

## If something fails
- The app does not appear in the app bar: tell me; the manifest was written from the documentation, not from a working example.
- The text is not clipped: the diagnostics will say `ui.pushClipRect: NO`; the app then draws text only once the panel is fully open.
- No icons: `carpeta de la app:` in the diagnostics shows the path the game gave; `None`/`nil` means icons and sound cannot be found.
