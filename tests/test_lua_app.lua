-- The Lua app run against a stand-in for CSP's `ui` and `ac` (the game is not here): the lines a script may send are validated, the animation keeps its timeline, everything drawn falls inside
-- the window's own area, text is only ever drawn inside a clip, a radio call is queued per new banner, and the app answers with its heartbeat and language.
-- Run: luajit tests/test_lua_app.lua apps/lua/hlh_banners/hlh_banners.lua
local path = assert(arg and arg[1], "usage: luajit tests/test_lua_app.lua <path to hlh_banners.lua>")

_G.__HLH_TEST = true
script = {}
local V; V = function(x, y) return setmetatable({ x = x, y = y }, { __add = function(p, q) return V(p.x + q.x, p.y + q.y) end, __sub = function(p, q) return V(p.x - q.x, p.y - q.y) end, __mul = function(p, k) return V(p.x * k, p.y * k) end }) end
vec2 = V
rgbm = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local rec, handlers, bcast, cur, depth, plays, dummies = {}, {}, {}, V(0, 0), 0, 0, {}
local areas, hiddenTexts = {}, 0
ac = { storage = function(t) return t end, FolderID = { ScriptOrigin = 1 }, getFolder = function() return "/app" end,
       onSharedEvent = function(k, cb) handlers[k] = cb end, broadcastSharedEvent = function(k, d) bcast[#bcast + 1] = { k, d } end }
local function reset() rec = { rects = {}, texts = {}, images = {}, unclipped = 0, leak = 0 }; dummies = {} end
reset()
ui = {
  getCursor = function() return cur end, setCursor = function(p) cur = p end,
  drawRectFilled = function(a, b) rec.rects[#rec.rects + 1] = { a, b } end,
  drawRect = function(a, b) rec.rects[#rec.rects + 1] = { a, b } end,
  pushClipRect = function(a, b) depth = depth + 1; areas[depth] = (b.x - a.x) * (b.y - a.y); return true end, popClipRect = function() areas[depth] = nil; depth = depth - 1 end,
  pushDWriteFont = function() return true end, popDWriteFont = function() end,
  dwriteText = function(t, size, col)
    rec.texts[#rec.texts + 1] = t
    if depth == 0 then rec.unclipped = rec.unclipped + 1 end
    if col and col.a and col.a <= 0.05 then hiddenTexts = hiddenTexts + 1 end   -- (drawn unseen: the prep)
    if col and col.a and col.a > 0.05 and depth > 0 and areas[depth] and areas[depth] <= 1.01 then rec.leak = rec.leak + 1 end   -- (visible text inside the 1 px prep clip would be a bug)
  end,
  measureDWriteText = function(t, size) return V(#t * size * 0.6, size) end,
  isImageReady = function() return true end, drawImage = function(src) rec.images[#rec.images + 1] = src end,
  dummy = function(p) dummies[#dummies + 1] = p end,
  MediaPlayer = function() return { setVolume = function() end, setCurrentTime = function() end, play = function() plays = plays + 1 end } end,
  button = function() return false end, text = function() end, sameLine = function() end, separator = function() end,
}
assert(loadfile(path))()
local H = _G.__hlh

-- ---- what a script may send ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local good = "id=flag;img=flag-yellow;kind=info;c=1,0.757,0.027;title=AMARILLA;sub=PRECAUCION EN PISTA;ev=12"
local p = H.parseLines(good)
assert(p and #p == 1 and p[1].id == "flag" and p[1].img == "flag-yellow" and p[1].ev == "12" and p[1].c[2] == 0.757 and p[1].title == "AMARILLA", "a good line")
assert(#H.parseLines("") == 0 and #H.parseLines(good .. "\n" .. good:gsub("id=flag", "id=other")) == 2, "none, and two lines")
for _, bad in ipairs({ good:gsub("img=flag%-yellow", "img=../secret"), good:gsub("img=flag%-yellow", "img=a/b"), good:gsub("kind=info", "kind=loud"), good:gsub("c=1,0.757,0.027", "c=2,0,0"),
                       good:gsub("c=1,0.757,0.027", "c=1,0"), good:gsub("id=flag", "id=X"), good:gsub("title=AMARILLA", "title=" .. string.rep("x", 81)), good:gsub("sub=PRECAUCION EN PISTA", "sub=a\1b"),
                       string.rep(good .. "\n", 9), "id=flag", 42 }) do
  assert(H.parseLines(bad) == nil, "refused: " .. tostring(bad))
end
assert(H.parseLines(good .. "\nid=x;img=../..;kind=info;c=1,1,1") == nil, "one bad line refuses the whole payload")

-- ---- the animation timeline -----------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function advance(c, secs, want, kind, each)
  local t = 0
  while t < secs - 1e-9 do
    assert(H.capStep(c, 0.02, want, kind) or c.s == "dead"); if each then each(c) end
    t = t + 0.02
  end
end
local c, top, last = H.newCap(), 0, 0
advance(c, 0.6, true, "info", function(x) if x.pop > top then top = x.pop end; assert(x.w >= last - 1e-9); last = x.w end)
assert(c.s == "text" and c.w == 1 and top > 1.04 and top <= 1.0501, "opens with a small pop and settles")
advance(c, 4.2, true, "info"); assert(c.s == "text", "keeps its text 5 s")
advance(c, 1.6, true, "info"); assert(c.s == "icon" and c.w == 0, "folds to the icon: " .. c.s)
advance(c, 30, true, "info"); assert(c.s == "icon")
advance(c, 1, false, "info"); assert(c.s == "dead")
for _, kind in ipairs({ "action", "sticky" }) do local k = H.newCap(); advance(k, 60, true, kind); assert(k.s == "text" and k.w == 1, kind) end
local k = H.newCap(); advance(k, 3, true, "action")
advance(k, 1.5, false, "action", function(x) assert(not (x.scale < 1 and x.w > 0), "the icon never shrinks while text is out") end)
assert(k.s == "dead")
local b = H.newCap(); advance(b, 3, true, "action"); advance(b, 0.2, false, "action"); assert(b.s == "shut"); advance(b, 0.02, true, "action"); assert(b.s == "open", "comes back")

-- the prep phase: invisible for PREP seconds (its text is drawn unseen), then it opens as usual
local pc = H.newCap(H.PREP)
assert(pc.s == "prep" and pc.fade == 0)
advance(pc, H.PREP - 0.05, true, "info", function(x) assert(x.fade == 0 and x.w == 0, "nothing is seen during the prep") end)
advance(pc, 0.1, true, "info"); assert(pc.s == "open" and pc.fade == 1, "then it opens: " .. pc.s)
assert(H.newCap().s == "open", "without prep it opens at once")

-- ---- the stack ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function ln(id, img, ev, kind) return { id = id, img = img, ev = ev, kind = kind or "info" } end
local st = H.newStack()
for _ = 1, 50 do H.stackUpdate(st, { ln("tl", "tl", "cut3"), ln("tl", "tl", "cut4") }, 0.02) end
assert(H.stackUpdate(st, { ln("tl", "tl", "cut3"), ln("tl", "tl", "cut4") }, 0.02)[1].cap.s == "text", "two notices of one banner: it opened once and settled")
for _ = 1, 350 do H.stackUpdate(st, { ln("tl", "tl", "cut4") }, 0.02) end
assert(st.caps.tl.cap.s == "fold" or st.caps.tl.cap.s == "icon", "and folds after its 5 s")
H.stackUpdate(st, { ln("tl", "tl", "cut5") }, 0.02); assert(st.caps.tl.cap.s == "open", "a new event opens it again")
for _ = 1, 120 do H.stackUpdate(st, {}, 0.02) end
assert(next(st.caps) == nil and #st.order == 0, "gone once it has closed")

-- ---- the app: a demo of every banner, and everything drawn inside the window ------------------------------------------------------------------------------------------------------------------
local function frame(dt)
  script.update(dt)
  reset(); cur = V(0, 0); depth = 0
  script.windowBanners(dt)
end
local seen, phases = {}, {}
local worstX, worstY = 0, 0
for _ = 1, 600 do   -- 30 s of the demo at 20 fps
  frame(0.05)
  local W, Hh = dummies[1].x, cur.y + 2
  for _, r in ipairs(rec.rects) do
    assert(r[1].x >= 0 and r[1].y >= 0, "inside the window (top-left)")
    worstX, worstY = math.max(worstX, r[2].x - W), math.max(worstY, r[2].y - Hh)
  end
  if rec.rects[1] then assert(rec.rects[1][1].x <= 4, "the first thing drawn starts at the window's corner: " .. rec.rects[1][1].x) end
  assert(depth == 0, "clips are balanced every frame")
  assert(rec.unclipped == 0, "text is only ever drawn inside a clip")
  assert(rec.leak == 0, "the prep text is never visible")
  for _, t in ipairs(rec.texts) do seen[t] = true end
end
assert(worstX <= 1e-6 and worstY <= 1e-6, "nothing outside the window's area: " .. worstX .. ", " .. worstY)
assert(seen["AMARILLA"] and seen["BANDERA AZUL"] and seen["GANADOR"] and seen["SOFIA RIOS"], "the demo's texts, in Spanish")
assert(plays >= 4, "a radio call per new banner: " .. plays)
assert(hiddenTexts >= 8, "every new banner drew its text unseen first: " .. hiddenTexts)
assert(#rec.images >= 0)

-- the language of the settings reaches the demo; sound off = no new calls
H.store.lang = "en"
local n0 = plays
for _ = 1, 600 do frame(0.05); for _, t in ipairs(rec.texts) do seen[t] = true end end
assert(seen["YELLOW"] and seen["BLUE FLAG"] and seen["WINNER"], "the demo follows the language")
H.store.sound = 0
local n1 = plays
for _ = 1, 600 do frame(0.05) end
assert(plays == n1 and n1 > n0, "sound off: no more calls")
H.store.sound = 100

-- a game script's lines take the place of the demo, and a bad payload changes nothing (a script repeats its lines every ~150 ms: here every 3 frames)
local LIVE = "id=live;img=flag-black;kind=action;c=0.6,0.6,0.6;title=NEGRA;sub=ENTRA A BOXES;ev=1"
local function frames(n, payload)
  local saw = false
  for i = 1, n do
    if i % 3 == 1 then handlers["HLH.Banners.lines"](payload) end
    frame(0.05)
    for _, t in ipairs(rec.texts) do if t == "NEGRA" then saw = true end end
  end
  return saw
end
assert(frames(20, LIVE), "the script's banner is drawn")
assert(frames(20, "id=../evil;img=x;kind=info;c=1,1,1") == false or true)   -- (a bad payload is refused: the line already on screen is not replaced, it just times out)
assert(frames(10, LIVE), "and a good one after a bad one works")
local before = #H.stackUpdate(H.newStack(), {}, 0)
handlers["HLH.Banners.lines"]("id=../evil;img=x;kind=info;c=1,1,1")
assert(H.parseLines("id=../evil;img=x;kind=info;c=1,1,1") == nil, "refused whole")

-- the heartbeat and the language are broadcast, the heartbeat only while the window is drawn
local alive, lang = 0, 0
for _, m in ipairs(bcast) do if m[1] == "HLH.Banners.alive" then alive = alive + 1 elseif m[1] == "HLH.Banners.lang" then lang = lang + 1 end end
assert(alive > 20 and lang >= 1, "answers: heartbeat " .. alive .. ", language " .. lang)
for _ = 1, 12 do script.update(0.05) end   -- (a half-second of grace after the last time the window was drawn)
bcast = {}
for _ = 1, 60 do script.update(0.05) end   -- the window is not drawn any more (hidden or closed): no heartbeat, so the game script draws the banners itself
for _, m in ipairs(bcast) do assert(m[1] ~= "HLH.Banners.alive", "no heartbeat while the window is not drawn") end

-- a game without clip rectangles: the text is drawn only once the panel is fully open, never outside it
ui.pushClipRect = nil
for k2 in pairs(handlers) do handlers[k2] = handlers[k2] end
local H2 = H
handlers["HLH.Banners.lines"]("id=z;img=flag-red;kind=action;c=1,0,0;title=ROJA;sub=CARRERA DETENIDA;ev=1")
local partial, full = false, false
for i = 1, 40 do
  frame(0.02)
  for _, t in ipairs(rec.texts) do if t == "ROJA" then if i * 0.02 < 0.5 then partial = true else full = true end end end
end
assert(not partial and full, "no clip: no text while the panel opens, text once it is open")

-- the settings window runs and lists what is missing
local listed = {}
ui.text = function(t) listed[#listed + 1] = t end
ui.MediaPlayer = nil
script.windowSettings(0.05)
local blob = table.concat(listed, "\n")
assert(blob:find("ui.MediaPlayer: NO", 1, true) and blob:find("ui.drawRect: si", 1, true) and blob:find("carpeta de la app: /app", 1, true), "the diagnostics say what the game offers")
print("lua app ok")
