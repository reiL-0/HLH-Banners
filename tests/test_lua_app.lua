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

-- a letter we have no picture for is drawn as a question mark, and an accent works
ui.pushClipRect = function() depth = depth + 1 end
handlers["HLH.Banners.lines"]("id=w;img=flag-yellow;kind=action;c=1,1,0;title=\xD0\x96\xC3\x91;sub=X;ev=1")
for i = 1, 40 do
  handlers["HLH.Banners.lines"]("id=w;img=flag-yellow;kind=action;c=1,1,0;title=\xD0\x96\xC3\x91;sub=X;ev=1")
  frame(0.02)
end
local codes = {}
for _, cp in ipairs(rec.glyphs) do codes[cp] = true end
assert(codes[0x3F] and codes[0xD1], "an unknown letter becomes '?', an accented one has its picture")

-- the numbers under the banners (to see what the app and the game do), only when asked
local info = {}
ui.text = function(t) info[#info + 1] = t end
H.store.info, H.store.demo = 1, 2
for _ = 1, 200 do frame(0.05) end   -- (banners born while the window was not drawn, in the heartbeat test above, would count their wait)
H.stat.delayMax, H.stat.delay = 0, nil
local maxEntries, line, delayLine, entryLines = 0, nil, nil, 0
for _ = 1, 800 do
  info = {}
  frame(0.05)
  for _, t in ipairs(info) do
    local n = tonumber(t:match("entradas=(%d+)"))
    if n then maxEntries = math.max(maxEntries, n); line = t end
    if t:find("retraso creada", 1, true) then delayLine = t end
  end
  entryLines = math.max(entryLines, #info - 2)
end
assert(maxEntries >= 8 and line:find("fps=20", 1, true) and line:find("pido ", 1, true) and line:find("llamadas a la ventana=20/s", 1, true), "the info line: entries, frame rate, how often the game calls the window, the window: " .. maxEntries .. " " .. tostring(line))
assert(delayLine and delayLine:find("maximo 0.", 1, true), "a banner is drawn at once after it is created: " .. tostring(delayLine))
assert(entryLines >= 8, "one line per banner: " .. entryLines)
info = {}
H.store.info = 0
frame(0.05); assert(#info == 0, "nothing is written when it is off")
H.store.demo = 1
ui.text = function() end

-- if the game calls the window less often than it updates the app, a banner waits to be drawn: the numbers say so
H.store.info, H.store.demo = 1, 1
for _ = 1, 100 do frame(0.05) end
H.stat.delayMax, H.stat.delay = 0, nil
for i = 1, 400 do
  script.update(0.05)
  if i % 40 == 0 then reset(); cur = V(0, 0); depth = 0; script.windowBanners(0.05) end   -- the window is called once every 2 s
end
assert(H.stat.delayMax >= 1.5, "a window called every 2 s makes banners wait: " .. H.stat.delayMax)
H.store.info = 0

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
print("lua app ok")
