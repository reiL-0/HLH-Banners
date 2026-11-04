# Contract between a game script and the app

The app is a **renderer**. It is installed once and works with any server (any league, any hosting client) whose CSP script speaks this contract. It knows nothing about servers:
no server address, no server id, no token, no account, and it never opens a connection to the Internet. Everything about *which* server, *which* driver and *what to say* belongs to the script
that the server hands to the game (the hub), which already knows its server, the driver's slot and name, and the driver's token.

## script -> app: `POST http://127.0.0.1:28761/tick` (every ~150 ms; also the heartbeat)
Header `X-HLH-Init: 1`, JSON body (an empty body = heartbeat only):

```json
{"v": 1, "lines": [{"id": "flag", "img": "flag-yellow", "kind": "info", "c": [1, 0.757, 0.027], "title": "AMARILLA", "sub": "PRECAUCION EN PISTA", "ev": "12"}]}
```
- `id`: the place of the banner (`flag`, `owed`, `winner`...): one capsule per id; two lines with the same id = the newest wins.
- `img`: an icon name, looked up in the app's own `icons/` folder (letters, digits, dashes; never a path or URL).
- `kind`: `info` (the text folds to the icon after 5 s), `action` (the text stays while it applies), `sticky` (stays until the script stops sending it, i.e. until the session restarts).
- `c`: the badge/border colour. `title`, `sub`: the text, **already in the driver's language**. `ev`: changes when the same banner happens again (a new cut): the capsule opens again.
- The lines are **personal**: the script sends only what applies to this driver (their give-back, their cut counter, a flag for everybody...). The app does not filter or identify anyone.

## app -> script: the answer
`{"render_age_ms": 40, "lang": "auto", "v": 1}`
- `render_age_ms`: how long ago the app last drew. The script keeps drawing the banners itself unless this is small (the app can be hidden, closed or crashed).
- `lang`: `auto` | `es` | `en`, the driver's choice in the app. `auto` = the script uses its own (the account's language, else Spanish); otherwise the script asks its server for that language.
- `v`: the contract version. An app that does not know the script's version answers 409 and the script draws by itself.

## What the script may NOT make the app do
Open a file named by it, build a URL, run anything, write anything. A line that does not pass `ipc.validate_lines` is refused whole (400) and changes nothing on the screen.
