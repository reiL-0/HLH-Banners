# Probe (throwaway)

Answers the open questions before the real app is built.

1. Copy `apps/python/opr_banners/` to `<AC>/apps/python/opr_banners/` and enable "OPR Banners probe" in the in-game app list.
   If the log says `import socket FAIL`, copy a 32-bit Python 3.3 `Lib` into `opr_banners/stdlib/`.
2. Join/start a session: a yellow bar should open from the centre, hold and close (4 s loop).
3. Run `probe/opr_banners_probe.lua` as a CSP script. The text on screen must show `tick 200 {"render_age_ms": ...}`
   and `echo ... "sha256": "2cf24dba..."` (SHA-256 of "hello").
4. Hide the app in the sidebar: `render_age_ms` must keep growing while the answer stays 200.
5. Quit AC: `probe_result.txt` must end with `shutdown: port released`.

Paste `apps/python/opr_banners/probe_result.txt` and what the screen showed.

Host check of the request filter: `python3 tests/test_guard.py`.
