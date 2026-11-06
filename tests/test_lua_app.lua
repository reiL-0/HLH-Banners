-- The Lua app run against a stand-in for CSP's `ui` and `ac` (the game is not here): the lines a script may send are validated, the animation keeps its timeline, everything drawn falls inside
-- the window's own area, text is only ever drawn inside a clip, a radio call is queued per new banner, and the app answers with its heartbeat and language.
-- Run: luajit tests/test_lua_app.lua apps/lua/hlh_banners/hlh_banners.lua
local path = assert(arg and arg[1], "usage: luajit tests/test_lua_app.lua <path to hlh_banners.lua>")

_G.__HLH_TEST = true
script = {}
local V; V = function(x, y) return setmetatable({ x = x, y = y }, { __add = function(p, q) return V(p.x + q.x, p.y + q.y) end, __sub = function(p, q) return V(p.x - q.x, p.y - q.y) end, __mul = function(p, k) return V(p.x * k, p.y * k) end }) end
vec2 = V
rgbm = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local H   -- (the app's exports, filled in once it is loaded; the stand-ins below use it)
local rec, handlers, bcast, cur, depth, plays, dummies, fontDepth = {}, {}, {}, V(0, 0), 0, 0, {}, 0
ac = { storage = function(t) return t end, FolderID = { ScriptOrigin = 1 }, getFolder = function() return "/app" end,
       onSharedEvent = function(k, cb) handlers[k] = cb end, broadcastSharedEvent = function(k, d) bcast[#bcast + 1] = { k, d } end }
local function reset() rec = { rects = {}, texts = {}, images = {}, unclipped = 0, glyphs = {}, unclippedGlyph = 0, sources = {}, nsources = 0 }; dummies = {} end
reset()
ui = {
  getCursor = function() return cur end, setCursor = function(p) cur = p end,
  drawRectFilled = function(a, b) rec.rects[#rec.rects + 1] = { a, b } end,
  drawRect = function(a, b) rec.rects[#rec.rects + 1] = { a, b } end,
  -- like the game's: the push calls return NOTHING. The first version of the app took their return value as "it was pushed" and never popped: the clip rectangles piled up and every banner under a
  -- banner with text was cut away (a video of the game showed each new banner appearing only when an earlier one folded its text).
  pushClipRect = function() depth = depth + 1 end, popClipRect = function() depth = depth - 1 end,
  pushDWriteFont = function() fontDepth = fontDepth + 1 end, popDWriteFont = function() fontDepth = fontDepth - 1 end,
  dwriteText = function(t) rec.texts[#rec.texts + 1] = t; if depth == 0 then rec.unclipped = rec.unclipped + 1 end end,
  measureDWriteText = function(t, size) return V(#t * size * 0.6, size) end,
  isImageReady = function() return true end,
  drawImage = function(src, a, b, col, uv1, uv2)
    rec.images[#rec.images + 1] = src
    if not rec.sources[src] then rec.sources[src] = true; rec.nsources = rec.nsources + 1 end   -- (how many DIFFERENT pictures a frame draws)
    local h = src:match("/font/%w+/(%x+)%.png$")
    local set = src:match("/font/atlas%-(%w+)%.png$")
    local code = (h and tonumber(h, 16)) or (set and uv1 and H.atlasCodeAt(set, uv1.x, uv1.y))
    if code then rec.glyphs[#rec.glyphs + 1] = code; if depth == 0 then rec.unclippedGlyph = rec.unclippedGlyph + 1 end end
  end,
  dummy = function(p) dummies[#dummies + 1] = p end,
  MediaPlayer = function() return { setVolume = function() end, setCurrentTime = function() end, play = function() plays = plays + 1 end } end,
  button = function() return false end, text = function() end, sameLine = function() end, separator = function() end,
}
assert(loadfile(path))()
H = _G.__hlh
local function cpchar(cp) if cp < 128 then return string.char(cp) end return "#" .. cp end
local function frameText() local t = {} for _, cp in ipairs(rec.glyphs) do t[#t + 1] = cpchar(cp) end return table.concat(t) end   -- the letters drawn this frame (spaces only advance)

-- ---- the letters ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local cps = H.codepoints("A\xC3\x8D\xC3\x91\xE2\x82\xAC \xD0\x96")   -- A Í Ñ € (space) Ж
assert(#cps == 6 and cps[1] == 65 and cps[2] == 0xCD and cps[3] == 0xD1 and cps[4] == 0x20AC and cps[5] == 32 and cps[6] == 0x416, "UTF-8 is decoded to code points")
assert(H.pickSet("t", 20) == "t2" and H.pickSet("t", 40) == "t2" and H.pickSet("t", 41) == "t4" and H.pickSet("s", 12) == "s2" and H.pickSet("s", 36) == "s4", "the sharper set for bigger text")
local gw, gh = H.quadSize("t2", 20)
assert(gw == 12 and gh == 26.5 and H.glyphWidth("AMARILLA", 20) == 8 * 0.6 * 20, "exact widths: the face is monospace")
assert(math.abs(H.glyphY(10, 18) + 0.29 * 18 - 10) < 1e-9 and H.glyphY(33, 11) < 33, "the top of the capitals lands where asked: the picture goes up by the room above them")

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

-- custom hold duration (setting): 3 s folds earlier, 10 s keeps text longer
H.store.hold = 3
local c3 = H.newCap(); advance(c3, 0.6, true, "info"); advance(c3, 2.2, true, "info"); assert(c3.s == "text")
advance(c3, 1.5, true, "info"); assert(c3.s == "icon" and c3.w == 0, "folds after 3 s when hold=3")
H.store.hold = 10
local c10 = H.newCap(); advance(c10, 0.6, true, "info"); advance(c10, 6.0, true, "info"); assert(c10.s == "text", "stays open past 5 s when hold=10")
advance(c10, 4.5, true, "info"); assert(c10.s == "icon" and c10.w == 0, "folds after 10 s when hold=10")
assert(H.cycle(H.HOLDS, 3) == 5 and H.cycle(H.HOLDS, 10) == 3, "hold duration cycles through HOLDS")
H.store.hold = 5

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
local seen, phases, allText = {}, {}, ""
local worstX, worstY = 0, 0
for _ = 1, 600 do   -- 30 s of the demo at 20 fps
  frame(0.05)
  local W, Hh = dummies[1].x, cur.y + 2
  for _, r in ipairs(rec.rects) do
    assert(r[1].x >= 0 and r[1].y >= 0, "inside the window (top-left)")
    worstX, worstY = math.max(worstX, r[2].x - W), math.max(worstY, r[2].y - Hh)
  end
  if rec.rects[1] then assert(rec.rects[1][1].x <= 4, "the first thing drawn starts at the window's corner: " .. rec.rects[1][1].x) end
  assert(depth == 0, "clips are balanced every frame: " .. depth)
  assert(fontDepth == 0, "font pushes are balanced every frame: " .. fontDepth)
  assert(rec.unclipped == 0 and rec.unclippedGlyph == 0, "text is only ever drawn inside a clip")
  allText = allText .. "|" .. frameText()
end
assert(worstX <= 1e-6 and worstY <= 1e-6, "nothing outside the window's area: " .. worstX .. ", " .. worstY)
assert(allText:find("AMARILLA", 1, true) and allText:find("BANDERAAZUL", 1, true) and allText:find("GANADOR", 1, true) and allText:find("SOFIARIOS", 1, true), "the demo's texts, as letters, in Spanish")
assert(allText:find("PRECAUCIONENPISTA", 1, true), "both lines of text")
assert(plays >= 4, "a radio call per new banner: " .. plays)
assert(#rec.images >= 0)

-- the "varias" demo: eight banners pile up, the information ones fold to their icon, the instructions and the winner keep their text
H.store.demo = 2
H.store.lang = "es"
for _ = 1, 100 do frame(0.05) end   -- (past the previous demo's banners: the loop restarts at 0)
local maxIcons, folded = 0, false
for _ = 1, 800 do   -- 40 s
  frame(0.05)
  local icons = 0
  for _, src in ipairs(rec.images) do if src:find("/icons/", 1, true) then icons = icons + 1 end end
  maxIcons = math.max(maxIcons, icons)
  local txt = frameText()
  if icons >= 7 and not txt:find("AMARILLA", 1, true) and not txt:find("BOXESCERRADOS", 1, true) and txt:find("BANDERAAZUL", 1, true) and txt:find("GANADOR", 1, true) then folded = true end
end
assert(maxIcons >= 8, "eight banners on screen at once: " .. maxIcons)
assert(folded, "a moment with the information banners as icons only while the instruction and the winner still show their text")
H.store.demo = 1

-- the atlas: a letter's cell, and how many DIFFERENT pictures a frame draws (the game seems to limit them: text from three or four banners at once did not show)
do
  local u1, u2 = H.glyphUV("t2", string.byte("A"))
  assert(u1.x >= 0 and u1.y >= 0 and u2.x <= 1 and u2.y <= 1 and u2.x > u1.x and u2.y > u1.y, "a cell inside the atlas")
  local function codeOf(set, code) local c1 = H.glyphUV(set, code); return H.atlasCodeAt(set, c1.x, c1.y) end
  assert(codeOf("t2", 65) == 65 and codeOf("s2", 0xD1) == 0xD1 and codeOf("t4", string.byte("z")) == string.byte("z") and codeOf("s4", 0x20AC) == 0x20AC, "the letter a cell points at")
  local _, a2 = H.glyphUV("t2", 65)
  local b1 = H.glyphUV("t2", 66)
  assert(b1.x > a2.x, "neighbouring cells do not overlap: there is a gutter between them")
end
local function distinct(mode)
  H.store.glyph, H.store.demo, H.store.rows = mode, 2, 12
  for _ = 1, 100 do frame(0.05) end
  local most = 0
  for _ = 1, 800 do frame(0.05); most = math.max(most, rec.nsources) end
  return most
end
local dAtlas, dSingle = distinct(2), distinct(1)
assert(dAtlas <= 14, "from the atlas a frame draws very few different pictures (2 atlases + the icons): " .. dAtlas)
assert(dSingle > 30, "one picture per letter draws many (what the game could not take): " .. dSingle)
H.store.glyph, H.store.rows, H.store.demo = 2, 5, 1

-- columns: with a few rows the banners that do not fit start a new column to the right; with many rows they are one column
H.store.scale = 1
local function layout(rows)
  H.store.rows, H.store.demo = rows, 2
  local maxH, maxW, maxX, maxN = 0, 0, 0, 0
  for _ = 1, 100 do frame(0.05) end
  for _ = 1, 800 do
    frame(0.05)
    maxH, maxW = math.max(maxH, cur.y), math.max(maxW, dummies[1].x)
    for _, r in ipairs(rec.rects) do maxX = math.max(maxX, r[1].x) end
    local n = 0
    for _, src in ipairs(rec.images) do if src:find("/icons/", 1, true) then n = n + 1 end end
    maxN = math.max(maxN, n)
  end
  return maxH, maxW, maxX, maxN
end
local h3, w3, x3, n3 = layout(3)
assert(h3 <= 3 * 64 + 3, "three rows at most: " .. h3)
assert(x3 > 100 and n3 >= 8, "the rest start a new column to the right, and all eight are drawn: x=" .. x3 .. " n=" .. n3)
local h12, w12, x12, n12 = layout(12)
assert(x12 < 30 and n12 >= 8 and h12 >= 7 * 64, "twelve rows: a single column of eight: x=" .. x12 .. " h=" .. h12)
assert(w3 > w12, "two or three columns are wider than one")
H.store.scale, H.store.rows, H.store.demo = 1.25, 5, 1

-- the window never has to grow: with the room reserved its size is the same on every frame (a banner drawn outside the window is cut by the game until it grows); fitted, it changes with the banners
local function sizes(reserve)
  H.store.reserve, H.store.demo, H.store.rows = reserve, 2, 5
  for _ = 1, 100 do frame(0.05) end
  local seenSizes, n, covered = {}, 0, true
  for _ = 1, 800 do
    frame(0.05)
    local key = math.floor(dummies[1].x) .. "x" .. math.floor(cur.y)
    if not seenSizes[key] then seenSizes[key] = true; n = n + 1 end
    for _, r in ipairs(rec.rects) do if r[2].x > dummies[1].x + 1e-6 or r[2].y > cur.y + 2 then covered = false end end
  end
  return n, covered
end
local nRes, covRes = sizes(1)
assert(nRes == 1 and covRes, "reserved: one size on every frame, and it covers everything drawn: " .. nRes)
local nFit = sizes(0)
assert(nFit > 3, "fitted: the size follows the banners: " .. nFit)
H.store.reserve, H.store.rows, H.store.demo = 1, 5, 1

-- the next column glides to close the gap when a capsule of the first one folds to icon: four fixed banners in two columns of two; the widest (the first) folds its text at ~5.5 s
do
  local capIcon = { cap = { s = "icon", w = 0, scale = 1 }, line = { title = "TEST", sub = "SUB" } }
  local capText = { cap = { s = "text", w = 1, scale = 1 }, line = { title = "TEST", sub = "SUB" } }
  assert(H.capWidth(capIcon, 1) < 70 and H.capWidth(capText, 1) > 100, "capWidth reflects icon vs text")

  H.store.rows, H.store.demo, H.store.scale, H.store.reserve = 2, 0, 1, 1
  local function send(payload) handlers["HLH.Banners.lines"](payload) end
  local EMPTY = ""
  for i = 1, 100 do if i % 3 == 1 then send(EMPTY) end; frame(0.05) end   -- (whatever an earlier scenario left closes)
  local FOUR = "id=a;img=flag-yellow;kind=info;c=1,0.7,0;title=PRECAUCION EN PISTA LARGA;sub=TEXTO LARGO PARA OCUPAR MUCHO ANCHO;ev=1\n"
    .. "id=b;img=flag-blue;kind=action;c=0,0.4,1;title=AZUL;sub=X;ev=1\nid=c;img=flag-red;kind=action;c=1,0,0;title=ROJA;sub=Y;ev=1\nid=d;img=flag-black;kind=action;c=0.5,0.5,0.5;title=NEGRA;sub=Z;ev=1"
  local lo, hi, folded = 1e9, -1e9, false
  for i = 1, 240 do   -- 12 s
    if i % 3 == 1 then send(FOUR) end
    frame(0.05)
    if i * 0.05 > 2 then   -- (after the opening and the first glide)
      local maxX = 0
      for _, r in ipairs(rec.rects) do maxX = math.max(maxX, r[1].x) end
      lo, hi = math.min(lo, maxX), math.max(hi, maxX)
      if i * 0.05 > 6.5 then folded = true end
    end
  end
  assert(folded and hi - lo > 100, "the last column glides to close the gap when the first one's text folds: it moved " .. (hi - lo) .. " px")
  H.store.rows, H.store.demo, H.store.scale = 5, 1, 1.25
  for i = 1, 100 do if i % 3 == 1 then send(EMPTY) end; frame(0.05) end
end

-- the language of the settings reaches the demo; sound off = no new calls
H.store.lang = "en"
local n0 = plays
allText = ""
for _ = 1, 600 do frame(0.05); allText = allText .. "|" .. frameText() end
assert(allText:find("YELLOW", 1, true) and allText:find("BLUEFLAG", 1, true) and allText:find("WINNER", 1, true), "the demo follows the language")
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
    if frameText():find("NEGRA", 1, true) then saw = true end
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

-- a game without clip rectangles: the letters are drawn only whole, growing with the panel, and nothing outside it
ui.pushClipRect = nil
local Q = "id=z;img=flag-red;kind=action;c=1,0,0;title=QQQQ QQQQ QQQQ QQQQ;sub=QQ QQ;ev=1"   -- (Q appears in no other text of the demo: only this banner's letters are counted)
local counts = {}
for i = 1, 40 do
  handlers["HLH.Banners.lines"](Q)
  frame(0.02)
  local n = 0
  for _, cp in ipairs(rec.glyphs) do if cp == 0x51 then n = n + 1 end end
  counts[#counts + 1] = n
end
assert(counts[3] < counts[25] and counts[25] <= counts[40] and counts[40] == 20, "no clip: whole letters appear one after another as the panel opens: " .. table.concat(counts, ","))
-- DirectWrite mode (the switch to compare): without a clip, text only once the panel is fully open
H.store.glyph = 0
local partial, full = false, false
for i = 1, 40 do
  handlers["HLH.Banners.lines"]("id=y;img=flag-black;kind=action;c=0.6,0.6,0.6;title=NEGRA;sub=A BOXES;ev=1")
  frame(0.02)
  for _, t in ipairs(rec.texts) do if t == "NEGRA" then if i * 0.02 < 0.5 then partial = true else full = true end end end
end
assert(not partial and full, "DirectWrite without a clip: no text while the panel opens, text once it is open")
H.store.glyph = 2

-- mixed text: a line whose characters all have a picture is drawn from the pictures (instant, also a counter that changes every second); a line with a character that has none (a name in Cyrillic) is
-- drawn with DirectWrite, only that line; the clip and the font stacks stay balanced
ui.pushClipRect = function() depth = depth + 1 end
H.store.glyph = 2
local MIX = "id=w;img=flag-yellow;kind=action;c=1,1,0;title=\xD0\x98\xD0\x92\xD0\x90\xD0\x9D;sub=TIME 12 \xC3\x91;ev=1"   -- title "ИВАН" (Cyrillic), sub "TIME 12 Ñ"
local sawTitle, codes, dwTitle = false, {}, 0
for i = 1, 60 do
  handlers["HLH.Banners.lines"](MIX)
  frame(0.02)
  assert(depth == 0 and fontDepth == 0, "stacks balanced in a frame with a DirectWrite line")
  for _, t in ipairs(rec.texts) do if t == "\xD0\x98\xD0\x92\xD0\x90\xD0\x9D" then dwTitle = dwTitle + 1 end end
  for _, cp in ipairs(rec.glyphs) do codes[cp] = true end
end
assert(dwTitle > 0, "the Cyrillic title is drawn with DirectWrite")
assert(codes[string.byte("T")] and codes[string.byte("1")] and codes[0xD1], "the sub, whose characters all have a picture, is drawn from the pictures (an accent too)")
assert(not codes[0x3F], "no question marks: a line without pictures goes to DirectWrite whole")
local onlyOk = false
for i = 1, 40 do
  handlers["HLH.Banners.lines"]("id=w;img=flag-yellow;kind=action;c=1,1,0;title=SOF\xC3\x8DA R\xC3\x8DOS;sub=X;ev=2")   -- SOFÍA RÍOS: all have pictures
  frame(0.02)
  for _, t in ipairs(rec.texts) do if t:find("SOF", 1, true) then onlyOk = true end end
end
assert(not onlyOk, "a name whose letters all have pictures never needs DirectWrite")
H.store.glyph = 2

-- the settings window runs and lists what is missing
local listed = {}
ui.text = function(t) listed[#listed + 1] = t end
ui.textColored = function(t) listed[#listed + 1] = t end
ui.MediaPlayer = nil
H.store.demo = 1
handlers["HLH.Banners.lines"]("id=live;img=flag-black;kind=action;c=0.6,0.6,0.6;title=NEGRA;sub=A BOXES;ev=1")
script.update(0.05)
script.windowSettings(0.05)
local blob = table.concat(listed, "\n")
assert(blob:find("AVISO: el demo esta tapado", 1, true), "it says when a script covers the demo")
listed = {}
for _ = 1, 40 do script.update(0.05) end   -- the script goes quiet (more than a second without lines)
script.windowSettings(0.05)
assert(not table.concat(listed, "\n"):find("AVISO", 1, true), "and the warning goes when the script stops")
local blob = table.concat(listed, "\n")
assert(blob:find("ui.MediaPlayer: NO", 1, true) and blob:find("ui.drawRect: si", 1, true) and blob:find("carpeta de la app: /app", 1, true), "the diagnostics say what the game offers")
-- ---- groups: the alerts and the info have their own windows; a group whose window is not open puts its banners in the main one ---------------------------------------------------------------------
H.store.demo = 0
local G = H.groups
local function gframe(dt, open)   -- `open`: the windows drawn this frame
  script.update(dt)
  reset(); cur = V(0, 0); depth = 0
  for _, name in ipairs(open) do script[({ flags = "windowBanners", alerts = "windowAlerts", info = "windowInfo" })[name]](dt) end
end
local ALERT = "id=azul;img=flag-blue;kind=action;c=0.16,0.47,1;title=AZUL;sub=DEJA PASAR;ev=1;grp=alerts"
local INFO = "id=lim;img=track-limits;kind=info;c=0.36,0.42,0.75;title=LIMITES;sub=;ev=1"   -- (no grp: it goes by its icon)
local FLAG = "id=flag;img=flag-yellow;kind=info;c=1,0.757,0.027;title=AMARILLA;sub=;ev=1"
local function feed(payload, frames_, open) for i = 1, frames_ do if i % 3 == 1 then handlers["HLH.Banners.lines"](payload) end gframe(0.05, open) end end
local ALL = ALERT .. "\n" .. INFO .. "\n" .. FLAG
feed("", 6, { "flags", "alerts", "info" })   -- (the windows are drawn once before the banners come: that is how the app knows they are open)
feed(ALL, 12, { "flags", "alerts", "info" })
assert(#G.flags.entries == 1 and G.flags.entries[1].line.id == "flag" and #G.alerts.entries == 1 and G.alerts.entries[1].line.id == "azul" and #G.info.entries == 1 and G.info.entries[1].line.id == "lim", "each banner in the window of its group (by grp, else by its icon)")
alive = 0; bcast = {}
feed(ALL, 12, { "flags", "alerts", "info" })
local payloads = {} for _, b in ipairs(bcast) do if b[1] == "HLH.Banners.alive" then payloads[b[2]] = true end end
assert(payloads["flags,alerts,info"], "the heartbeat says which windows are open")
feed(ALL, 30, { "flags", "info" })   -- the alerts window is closed
assert(#G.alerts.entries == 0 and #G.flags.entries == 2 and #G.info.entries == 1, "a group whose window is closed shows its banners in the main one")
feed(ALL, 30, { "alerts" })   -- the main window is closed too: the heartbeat stops (the script draws them itself)
bcast = {}
feed(ALL, 12, { "alerts" })
for _, b in ipairs(bcast) do assert(b[1] ~= "HLH.Banners.alive", "no heartbeat without the main window") end
assert(H.parseLines(ALERT) and H.parseLines(ALERT)[1].grp == "alerts" and H.parseLines((ALERT:gsub("grp=alerts", "grp=elsewhere"))) == nil and H.parseLines(FLAG)[1].grp == nil, "grp is one of the known groups or absent")
assert(H.groupOf("flag-blue") == "alerts" and H.groupOf("danger-ahead") == "alerts" and H.groupOf("track-limits") == "info" and H.groupOf("flag-yellow") == "flags" and H.groupOf("winner") == "flags", "the default group by icon")

-- ---- the delta window: its own event, validated; drawn inside its own area; a demo while nothing arrives so it can be found and moved ---------------------------------------------------------------
local DOK = "d=-0.31;n=1;sec=7;tol=0.20;cap=0.80;v=72;res=1110111.....0......."
assert(#DOK:match("res=(.*)") == 20, "(the sample is 20 long)")
local pd = H.parseDelta(DOK)
assert(pd and pd.d == -0.31 and pd.n == 1 and pd.sec == 7 and pd.tol == 0.2 and pd.cap == 0.8 and pd.v == 72 and #pd.res == 20, "a good delta payload")
assert(H.parseDelta("") == false, "an empty string says the VSC is over")
for _, bad in ipairs({ DOK:gsub("sec=7", "sec=21"), DOK:gsub("d=%-0.31", "d=abc"), DOK:gsub("n=1", "n=99"), DOK:gsub("res=[01%.]+", "res=11"), DOK:gsub("res=[01%.]+", "res=" .. string.rep("x", 20)), DOK:gsub("v=72", "v=-5"), string.rep("a", 300) }) do
  assert(H.parseDelta(bad) == nil, "refused: " .. tostring(bad):sub(1, 60))
end
assert(H.parseDelta(DOK:gsub("d=%-0.31", "d=nan")) == nil, "no NaN")
local function dframe(dt) script.update(dt); reset(); cur = V(0, 0); depth = 0; script.windowDelta(dt) end
H.store.demo = 0; H.store.lang = "es"
dframe(0.05)
assert(#rec.glyphs == 0 and dummies[1] and dummies[1].x > 100, "no data and no demo: nothing is drawn, but the window keeps its size")
handlers["HLH.Delta.state"](DOK)
dframe(0.05)
local dtext = frameText()
assert(dtext:find("DELTA7/20", 1, true) and dtext:find("-0.31", 1, true) and dtext:find("REDUCE", 1, true) and dtext:find("AVISOS1/2", 1, true), "the number, the sector, the hint and the strikes are drawn: " .. dtext)
local Wd, Hd = dummies[1].x, cur.y + 2
for _, r in ipairs(rec.rects) do assert(r[1].x >= 0 and r[1].y >= 0 and r[2].x <= Wd + 1 and r[2].y <= Hd + 1, "everything inside the window") end
handlers["HLH.Delta.state"]((DOK:gsub("d=%-0.31", "d=0.60")))
dframe(0.05)
assert(frameText():find("+0.60", 1, true) and not frameText():find("REDUCE", 1, true), "positive: slower than the minimum, no warning")
handlers["HLH.Delta.state"]("")
dframe(0.05)
assert(#rec.glyphs == 0, "the VSC is over: the window empties")
H.store.demo = 1
dframe(0.05)
assert(#rec.glyphs > 0 and frameText():find("DELTA", 1, true), "with the demo on, the window shows an example while nothing arrives (so it can be found and moved)")
handlers["HLH.Delta.state"]("garbage")
dframe(0.05)
assert(frameText():find("DELTA", 1, true), "a refused payload changes nothing")

print("lua app ok")
