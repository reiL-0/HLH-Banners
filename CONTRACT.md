# Contract between a game script and the app

The app is a **renderer**. It is installed once and works with any server (any league, any hosting client) whose CSP script speaks this contract. It knows nothing about servers: no server address, no server
id, no token, no account, and it opens no connection. Everything about *which* server, *which* driver and *what to say* belongs to the script that the server hands to the game (the hub), which already knows its
server, the driver's slot and name, and the driver's token.

The app is a CSP Lua app (`apps/lua/hlh_banners`). Script and app talk through CSP's shared events (`ac.broadcastSharedEvent` / `ac.onSharedEvent`), inside the game: no port, no network. (An earlier draft in
Python used a local HTTP port; `apps/python/` is kept only as history. Its measurements: AC's GL is drawn in the window's own coordinates, `winsound` plays, two apps can share settings through a file.)

## script -> app: event `HLH.Banners.lines` (every ~150 ms; it is also the data's heartbeat)
The data is a string: one banner per line, fields `key=value` separated by `;`:

```
id=flag;img=flag-yellow;kind=info;c=1,0.757,0.027;title=AMARILLA;sub=PRECAUCION EN PISTA;ev=12
```
- `id`: the place of the banner (`flag`, `owed`, `winner`...): one capsule per id; two lines with the same id = the newest wins.
- `img`: an icon name, looked up in the app's own `icons/` folder (letters, digits, dashes; never a path or URL).
- `kind`: `info` (the text folds to the icon after 5 s), `action` (the text stays while it applies), `sticky` (stays until the script stops sending it, i.e. until the session restarts).
- `c`: the badge/border colour, three numbers 0..1. `title`, `sub`: the text, **already in the driver's language** (at most 80 characters, no `;` and no control characters). `ev`: changes when the same banner happens
  again (a new cut): the capsule opens again.
- `grp` (optional): the window the banner belongs to, `flags` (the track's flag, the winner: the main window), `alerts` (urgent and personal: blue flag, danger ahead, give the place back, penalties) or `info`
  (track limits, pit lane, restarts). Without it the app decides by the icon. Each group is a window of the app that the driver moves, scales and switches on by itself; a group whose window is not
  open shows its banners in the main one. Any other value refuses the payload.
- An empty string = no banners. A payload with **one** bad line is refused whole and changes nothing on the screen. If no payload arrives for 1 s the app falls back to its demo or to nothing.
- The lines are **personal**: the script sends only what applies to this driver. The app does not filter or identify anyone.

## app -> script
- `HLH.Banners.alive` (every 0.25 s, **only while the main banners window is being drawn**; the payload lists the windows open, e.g. `flags,alerts`): the script keeps drawing the banners itself unless this beats (the window can be hidden, closed, or the app not installed).
- `HLH.Banners.lang` (every 2 s and when it changes): `auto` | `es` | `en`, the driver's choice in the app's settings window. `auto` = the script uses its own (the account's language, else Spanish);
  otherwise the script asks its server for that language.

## What the script may NOT make the app do
Open a file named by it, build a URL, run anything, write anything. The icon is chosen by name among the files the app ships.

## script -> app: event `HLH.Delta.state` (about every 100 ms while a delta VSC runs; `""` when it is over)
The delta of a VSC in F1 style, for the app's `delta` window: `d=-0.31;n=1;sec=7;tol=0.20;cap=0.80;v=72;res=1110111.....0.......`
- `d`: the delta in seconds (positive = slower than the minimum time of the sector, which is right; negative = faster than allowed); `n`: strikes (two in a row in negative = penalty); `sec`: the sector 1..20;
  `tol`, `cap`: the tolerance and the most credit; `v`: the car's speed in km/h; `res`: 20 characters, one per sector: `1` kept, `0` under the minimum, `.` not driven yet.
- Anything that does not fit (a number out of range, a `res` that is not 20 of `01.`) is refused and the window keeps what it had. Data older than 1 s is not drawn (the window shows its demo, or nothing).

