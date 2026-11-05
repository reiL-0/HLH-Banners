# HLH Banners

CSP Lua app for Assetto Corsa that draws the Open Paddock Racing League race-control banners
(flags, cautions, give-back notices) in a window the driver can move, with opening/closing animations.

The app ships only a fixed engine. Animations are **data** (a JSON manifest + PNGs) downloaded by the
league's CSP script when the driver joins a race. Downloaded files are never code.

If the app is not installed or not alive, the CSP script keeps drawing the banners itself.

Status: draft (see `probe/README.md`). The app is `apps/lua/hlh_banners`; `apps/python/` is an earlier draft kept as history. Nothing here is production yet.
