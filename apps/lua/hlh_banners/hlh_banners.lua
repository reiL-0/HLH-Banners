-- HLH Banners: a Custom Shaders Patch Lua app. Draws the race-control banners as capsules (an icon badge + a text panel) in a window the driver moves. Its window has none of the game's frame (the
-- manifest uses the official NO_BACKGROUND / NO_TITLE_BAR / AUTO_RESIZE flags). The app knows no server: it draws the lines a game script sends it (HLH.Banners.lines, see CONTRACT.md) and answers with its
-- language and a heartbeat. Without lines it can run a demo of every kind of banner. DRAFT: written from the CSP Lua documentation; none of it has run in the game yet, and the settings window
-- lists which game functions exist so the first session tells what works.
--   banner kinds: "info" folds its text to the icon after 5 s, "action" keeps it while it applies, "sticky" stays until the script stops sending it.
-- The text is drawn as pictures of letters (font/, a monospace face rendered by tools/make_glyphs.py), not with DirectWrite: the game builds a DirectWrite text the first time it sees it, which made
-- the text arrive late and apart from the animation (measured in the game); a picture that is already loaded is drawn at once, and its width is exact, so the text unfolds with the panel.

local KEY_LINES, KEY_LANG, KEY_ALIVE = "HLH.Banners.lines", "HLH.Banners.lang", "HLH.Banners.alive"

local function safe(f, ...)
  local ok, r = pcall(f, ...)
  if ok then return r end
  return nil
end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

-- ---- the capsule's animation: a state machine advanced by the time between frames (the same as the hub's and the tested Python one) ---------------------------------------------------
-- open (the icon pops 0.4 -> 1.05 -> 1 while the text unfolds to the right) -> text -> [fold: an "info" banner's text folds after 5 s] -> icon -> close (the badge shrinks to 0.2 and fades).
-- A banner removed while its text is out folds the text FIRST (shut), so no text is ever left on its own and the icon only shrinks when the text is gone.
local CAP_T, TEXT_SEC = { open = 0.55, shut = 0.4, close = 0.32 }, 5
local function easeOut(t) t = clamp(t, 0, 1) return 1 - (1 - t) ^ 3 end
local function easeIn(t) t = clamp(t, 0, 1) return t * t end
local function popScale(t) if t < 0.6 then return 0.4 + 0.65 * easeOut(t / 0.6) end return 1.05 - 0.05 * easeOut((t - 0.6) / 0.4) end
local function newCap() return { s = "open", t = 0, age = 0, w = 0, pop = 0.4, scale = 1, fade = 1 } end
local function capStep(c, dt, want, kind)   -- false once the capsule is gone
  c.t = c.t + dt
  if want and (c.s == "shut" or c.s == "close") then c.s, c.t, c.scale, c.fade = "open", 0, 1, 1 end
  local s = c.s
  if s == "open" then
    local p = c.t / CAP_T.open
    c.w, c.pop, c.scale, c.fade = easeOut(p), popScale(p), 1, 1
    if p >= 1 then c.s, c.t, c.age, c.w, c.pop = "text", 0, 0, 1, 1 end
  elseif s == "text" then
    c.w, c.pop, c.age = 1, 1, c.age + dt
    if not want then c.s, c.t = "shut", 0 elseif kind == "info" and c.age >= TEXT_SEC then c.s, c.t = "fold", 0 end
  elseif s == "fold" then
    c.w = 1 - easeIn(c.t / CAP_T.shut)
    if c.t >= CAP_T.shut then c.s, c.t, c.w = "icon", 0, 0 end
  elseif s == "icon" then
    c.w = 0
    if not want then c.s, c.t = "close", 0 end
  elseif s == "shut" then
    c.w = 1 - easeIn(c.t / CAP_T.shut)
    if c.t >= CAP_T.shut then c.s, c.t, c.w = "close", 0, 0 end
  elseif s == "close" then
    local q = easeIn(c.t / CAP_T.close)
    c.w, c.scale, c.fade = 0, 1 - 0.8 * q, 1 - q
    if c.t >= CAP_T.close then c.s = "dead" end
  end
  return c.s ~= "dead"
end

-- ---- the stack: the capsules on screen. A line that is gone keeps its entry while it closes; two lines with the same id (two cuts seconds apart): the newest wins ---------------------------
local function newStack() return { caps = {}, order = {} } end
local function stackUpdate(st, lines, dt)
  local want, ids = {}, {}
  for _, l in ipairs(lines) do
    if not want[l.id] then ids[#ids + 1] = l.id end
    want[l.id] = l
  end
  for _, id in ipairs(ids) do
    local l = want[id]
    local e = st.caps[id]
    if not e then e = { id = id, cap = newCap() }; st.caps[id] = e; st.order[#st.order + 1] = id end
    if e.img ~= l.img or (l.ev and l.ev ~= e.ev) then   -- another banner in the same place, or a new event of it: it opens again
      local fresh = e.img ~= nil
      e.img, e.ev = l.img, l.ev
      if fresh and (e.cap.s == "text" or e.cap.s == "icon" or e.cap.s == "fold") then e.cap = newCap(); e.isNew = true end
      if not fresh then e.isNew = true end
    end
    e.line = l
  end
  for i = #st.order, 1, -1 do
    local e = st.caps[st.order[i]]
    if not capStep(e.cap, dt, want[st.order[i]] ~= nil, e.line.kind) then st.caps[st.order[i]] = nil; table.remove(st.order, i) end
  end
  local out = {}
  for _, id in ipairs(st.order) do out[#out + 1] = st.caps[id] end
  return out
end

-- ---- what a game script may send: one banner per line "id=..;img=..;kind=..;c=r,g,b;title=..;sub=..;ev=.." ----------------------------------------------------------------------------
-- Validated like the Python app's ipc.py: an icon name is letters, digits and dashes only (it is looked up in the app's own folder, never a path or a URL), a short text, nothing else.
local KINDS = { info = true, action = true, sticky = true }
local MAX_LINES, MAX_TEXT = 8, 80
local function parseLines(payload)
  if type(payload) ~= "string" or #payload > 4096 then return nil end
  local out = {}
  for row in (payload .. "\n"):gmatch("([^\n]*)\n") do
    if row ~= "" then
      if #out >= MAX_LINES then return nil end
      local f = {}
      for k, v in row:gmatch("(%a+)=([^;]*)") do f[k] = v end
      local r, g, b = (f.c or ""):match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
      r, g, b = tonumber(r), tonumber(g), tonumber(b)
      local ok = f.id and f.id:match("^[a-z0-9][a-z0-9%-]*$") and #f.id <= 40 and f.img and f.img:match("^[a-z0-9][a-z0-9%-]*$") and #f.img <= 40 and KINDS[f.kind]
        and r and g and b and r <= 1 and g <= 1 and b <= 1 and #(f.title or "") <= MAX_TEXT and #(f.sub or "") <= MAX_TEXT
        and not (f.title or ""):find("%c") and not (f.sub or ""):find("%c") and (f.ev == nil or #f.ev <= 32)
      if not ok then return nil end   -- a payload with one bad line is refused whole
      out[#out + 1] = { id = f.id, img = f.img, kind = f.kind, c = { r, g, b }, title = f.title or "", sub = f.sub or "", ev = f.ev }
    end
  end
  return out
end

-- ---- settings (kept by the game between sessions) ----------------------------------------------------------------------------------------------------------------------------------------
local SCALES, VOLUMES, LANGS, ROWS = { 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0 }, { 100, 70, 40, 0 }, { "auto", "es", "en" }, { 3, 4, 5, 6, 8, 12 }
local DEFAULTS = { lang = "auto", scale = 1.25, sound = 100, demo = 1, glyph = 1, rows = 5, reserve = 1, info = 0 }   -- info: 1 = a line of numbers under the banners (to see what the app and the game do); rows: banners per column before a new column starts; reserve: 1 = the window always has the room of the whole grid (it never has to grow), 0 = it fits what is on screen   -- glyph: 1 = the text as pictures of letters, 0 = DirectWrite (to compare)
local store = safe(ac.storage, DEFAULTS) or DEFAULTS
local function cycle(list, cur) for i, v in ipairs(list) do if v == cur then return list[i % #list + 1] end end return list[1] end

local FOLDER = safe(function() return ac.getFolder(ac.FolderID.ScriptOrigin) end)   -- the app's own folder (icons, typeface, radio sound)
local FONT = FOLDER and ("JetBrains Mono:" .. FOLDER .. "/fonts/JetBrainsMono-ExtraBold.ttf") or nil

-- ---- state ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local clock, demoT = 0, 0
local stack = newStack()
local entries = {}                 -- what is drawn this frame
local incoming, incomingAt = nil, -1e9   -- the lines a game script sent, and when
local drawnAt, aliveAt, langAt, lastLang = -1e9, 0, 0, nil
local calls = { pending = {}, nextAt = 0, seen = {} }   -- the radio calls to play, one after another
local audio = { status = "not tried", player = nil }
local stat = { frames = 0, time = 0, fps = 0, worst = 0, worstNow = 0, created = 0, imgs = 0, imgsLast = 0, winCalls = 0, winRate = 0, delay = nil, delayMax = 0 }   -- measured by the app itself, from the time the game gives it each frame
local seenWin = { need = nil, got = nil, drawn = 0, maxDrawn = 0 }   -- what the banners window asked for and what the game gave it (diagnostics)

local DEMO = {
  es = { flag = { "AMARILLA", "PRECAUCION EN PISTA" }, blue = { "BANDERA AZUL", "DEJA PASAR AL MAS RAPIDO" }, limits = { "LIMITES DE PISTA", "LLEVAS 2/5 - TE QUEDAN 3" }, winner = { "GANADOR", "SOFIA RIOS" } },
  en = { flag = { "YELLOW", "CAUTION ON TRACK" }, blue = { "BLUE FLAG", "LET THE FASTER CAR THROUGH" }, limits = { "TRACK LIMITS", "2/5 - 3 LEFT" }, winner = { "WINNER", "SOFIA RIOS" } },
}
-- "varias" (store.demo == 2): eight banners of every kind, one more each second or two. The information ones fold to their icon 5 s after opening and stay as icons, the instructions and the winner keep
-- their text, so the pile-up and the "only the icon" state are on screen for a long while. A 40 s loop.
local MANY = {   -- id, icon, kind, colour, text key, from s, until s
  { "flag", "flag-yellow", "info", { 1, 0.757, 0.027 }, "yellow", 0, 32 },
  { "track-limits", "track-limits", "info", { 0.361, 0.42, 0.753 }, "limits", 1.5, 33 },
  { "pits", "pits-closed", "info", { 0.937, 0.325, 0.314 }, "pits", 3, 34 },
  { "white", "flag-white", "info", { 0.96, 0.96, 0.96 }, "white", 4.5, 35 },
  { "bw", "flag-bw", "info", { 0.741, 0.741, 0.741 }, "bw", 6, 36 },
  { "n-blue", "flag-blue", "action", { 0.161, 0.475, 1 }, "blue", 8, 30 },
  { "owed", "give-back", "action", { 1, 0.439, 0.263 }, "owed", 10, 31 },
  { "winner", "winner", "sticky", { 1, 0.835, 0.31 }, "winner", 12, 37 },
}
local MANY_TEXT = {
  es = { yellow = { "AMARILLA", "PRECAUCION EN PISTA" }, limits = { "LIMITES DE PISTA", "LLEVAS 2/5 - TE QUEDAN 3" }, pits = { "BOXES CERRADOS", "SOLO CON PERMISO DEL DIRECTOR" }, white = { "BLANCA", "ULTIMA VUELTA" },
         bw = { "NEGRA Y BLANCA", "ADVERTENCIA DE CONDUCTA" }, blue = { "BANDERA AZUL", "DEJA PASAR AL MAS RAPIDO" }, owed = { "DEVUELVE EL PUESTO", "A ANA - 23 S" }, winner = { "GANADOR", "SOFIA RIOS" } },
  en = { yellow = { "YELLOW", "CAUTION ON TRACK" }, limits = { "TRACK LIMITS", "2/5 - 3 LEFT" }, pits = { "PITS CLOSED", "DIRECTOR'S PERMISSION ONLY" }, white = { "WHITE", "LAST LAP" },
         bw = { "BLACK AND WHITE", "CONDUCT WARNING" }, blue = { "BLUE FLAG", "LET THE FASTER CAR THROUGH" }, owed = { "GIVE THE PLACE BACK", "TO ANA - 23 S" }, winner = { "WINNER", "SOFIA RIOS" } },
}
local function manyLines(t)
  local tx = MANY_TEXT[store.lang == "en" and "en" or "es"]
  local out = {}
  for _, m in ipairs(MANY) do
    if t >= m[6] and t < m[7] then out[#out + 1] = { id = m[1], img = m[2], kind = m[3], c = m[4], title = tx[m[5]][1], sub = tx[m[5]][2], ev = m[1] } end
  end
  return out
end

local function demoLines(t)
  local tx = DEMO[store.lang == "en" and "en" or "es"]
  local function ln(id, img, kind, c, key, ev) return { id = id, img = img, kind = kind, c = c, title = tx[key][1], sub = tx[key][2], ev = ev } end
  local out = {}
  if t >= 0 and t < 14 then out[#out + 1] = ln("flag", "flag-yellow", "info", { 1, 0.757, 0.027 }, "flag", "a") end
  if t >= 2 and t < 18 then out[#out + 1] = ln("n-blue", "flag-blue", "action", { 0.161, 0.475, 1 }, "blue", "b") end
  if t >= 4 and t < 10 then out[#out + 1] = ln("track-limits", "track-limits", "info", { 0.361, 0.42, 0.753 }, "limits", "cut2") end
  if t >= 6 and t < 25 then out[#out + 1] = ln("winner", "winner", "sticky", { 1, 0.835, 0.31 }, "winner", "w") end
  return out
end

-- ---- audio: the radio call of every new banner, in a queue so two that arrive together do not overlap -----------------------------------------------------------------------------------
local function playRadio()
  if not FOLDER then audio.status = "no app folder" return end
  local ok, err = pcall(function()
    if not audio.player then audio.player = ui.MediaPlayer(FOLDER .. "/radio.wav") end
    audio.player:setVolume(store.sound / 100)
    pcall(function() audio.player:setCurrentTime(0) end)
    audio.player:play()
  end)
  audio.status = ok and "played" or ("error: " .. tostring(err))
end

local function queueCalls(lines)
  local seen = calls.seen
  local ids = {}
  for _, l in ipairs(lines) do
    ids[l.id] = true
    local key = l.img .. "|" .. tostring(l.ev)
    if seen[l.id] ~= key then
      seen[l.id] = key
      if store.sound > 0 then calls.pending[#calls.pending + 1] = l.id end
    end
  end
  for id in pairs(seen) do if not ids[id] then seen[id] = nil end end
end

-- ---- text as pictures of letters --------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- font/<set>/<code in hex, 4 digits>.png: white letters on transparent, one picture per character, made at twice (t2, s2) or four times (t4, s4) the size they are drawn at. A monospace face: every letter
-- advances 0.6 em, so the width of a text is exact and it can be revealed letter by letter. The same files and layout as the Python draft (glyphs.py).
local ADV, LINE = 0.6, 1.32
local SETS = { t2 = 40, s2 = 24, t4 = 80, s4 = 48 }   -- set -> the pointsize it was rendered at
local KNOWN = {}
for c = 33, 126 do if c ~= 92 then KNOWN[c] = true end end
local function codepoints(s)   -- UTF-8 -> code points (what the manager writes has accents: "LÍMITES", "POSICIÓN")
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local cp, len = 0x3F, 1
    if b < 0x80 then cp = b
    elseif b >= 0xC2 and b < 0xE0 then cp, len = (b - 0xC0) * 64 + ((s:byte(i + 1) or 0x80) - 0x80), 2
    elseif b >= 0xE0 and b < 0xF0 then cp, len = (b - 0xE0) * 4096 + ((s:byte(i + 1) or 0x80) - 0x80) * 64 + ((s:byte(i + 2) or 0x80) - 0x80), 3
    elseif b >= 0xF0 then len = 4 end
    out[#out + 1] = cp
    i = i + len
  end
  return out
end
for _, cp in ipairs(codepoints("áéíóúüñÁÉÍÓÚÜÑ¿¡·°ºªçÇàèìòùâêîôûäëïöÿÀÈÌÒÙÂÊÎÔÛÄËÏÖ€")) do KNOWN[cp] = true end
local cpCache, cpCount = {}, 0
local function codepointsCached(s)   -- a text is decoded once, not on every frame
  local c = cpCache[s]
  if c then return c end
  c = codepoints(s)
  if cpCount > 400 then cpCache, cpCount = {}, 0 end
  cpCache[s], cpCount = c, cpCount + 1
  return c
end
local pathCache = {}
local function glyphCode(cp) if cp == 32 then return nil end return KNOWN[cp] and cp or 0x3F end   -- a space only advances; a letter we have no picture for is a "?"
local function pickSet(kind, size) return size <= SETS[kind .. "2"] and (kind .. "2") or (kind .. "4") end
local function quadSize(set, size) local pt = SETS[set] return math.ceil(ADV * pt) * size / pt, math.ceil(LINE * pt) * size / pt end
local function glyphPath(set, code)   -- the path of a letter's picture, built once
  local t = pathCache[set]
  if not t then t = {}; pathCache[set] = t end
  local p = t[code]
  if not p then p = FOLDER .. "/font/" .. set .. "/" .. string.format("%04x", code) .. ".png"; t[code] = p end
  return p
end
local function glyphWidth(text, size) return #codepointsCached(text) * ADV * size end
-- The letters sit on a common baseline 1.02 em below the top of their picture, capitals 0.73 em tall (measured on the pictures); to put the TOP of the capitals at `capTop` px the picture goes
-- up by the 0.29 em above them. The capitals of the title start 10 px under the capsule's top, the subtitle's 33 px (as DirectWrite drew them).
local ASC, CAP = 1.02, 0.73
local function glyphY(capTop, size) return capTop - (ASC - CAP) * size end

local allGlyphs = {}   -- every picture the app may draw, asked for a few per frame at the start so they are loaded before they are needed
local function listGlyphs()
  if not FOLDER then return end
  local codes = {}
  for c in pairs(KNOWN) do codes[#codes + 1] = c end
  table.sort(codes)
  for _, set in ipairs({ "t2", "s2", "t4", "s4" }) do for _, c in ipairs(codes) do allGlyphs[#allGlyphs + 1] = glyphPath(set, c) end end
end
listGlyphs()
local preload = { i = 0, ready = 0 }
local function preloadStep()
  for _ = 1, 24 do
    preload.i = preload.i + 1
    local p = allGlyphs[preload.i]
    if not p then return end
    if safe(ui.isImageReady, p) then preload.ready = preload.ready + 1 end   -- (asking starts the loading)
  end
end

-- the text at (x, y) as letters; only what falls inside `reveal` px is drawn (a clip rectangle cuts the last, partial letter; without one only whole letters are drawn)
local function drawGlyphText(x, y, text, kind, size, rgba, reveal, clipped)
  local set = pickSet(kind, size)
  local gw, gh = quadSize(set, size)
  local adv = ADV * size
  for i, cp in ipairs(codepointsCached(text)) do
    local gx = x + (i - 1) * adv
    if clipped and gx >= x + reveal or (not clipped) and gx + adv > x + reveal then break end
    local code = glyphCode(cp)
    if code then stat.imgs = stat.imgs + 1; safe(ui.drawImage, glyphPath(set, code), vec2(gx, y), vec2(gx + gw, y + gh), rgba) end
  end
end
local function useGlyphs() return store.glyph == 1 and FOLDER ~= nil end

-- ---- the game's calls: the hook for the script's lines, and the heartbeat/language we answer with -----------------------------------------------------------------------------------------
safe(function()
  ac.onSharedEvent(KEY_LINES, function(data)
    local lines = parseLines(data)
    if lines then incoming, incomingAt = lines, clock end
  end)
end)

local function broadcast(key, data) return safe(function() ac.broadcastSharedEvent(key, data) return true end) end

function script.update(dt)
  local raw = dt or 0
  stat.frames, stat.time, stat.worstNow = stat.frames + 1, stat.time + raw, math.max(stat.worstNow, raw)
  if stat.time >= 1 then stat.fps, stat.worst, stat.winRate, stat.frames, stat.time, stat.worstNow, stat.winCalls = stat.frames / stat.time, stat.worstNow, stat.winCalls / stat.time, 0, 0, 0, 0 end
  dt = clamp(dt or 0, 0, 0.1)
  clock = clock + dt
  local live = incoming and clock - incomingAt < 1.0
  if not live then incoming = nil end
  local lines
  if live then lines = incoming
  elseif store.demo == 1 then demoT = (demoT + dt) % 26; lines = demoLines(demoT)
  elseif store.demo == 2 then demoT = (demoT + dt) % 40; lines = manyLines(demoT)
  else lines = {} end
  queueCalls(lines)
  if #calls.pending > 0 and clock >= calls.nextAt then table.remove(calls.pending, 1); calls.nextAt = clock + 0.4; playRadio() end
  entries = stackUpdate(stack, lines, dt)
  for _, e in ipairs(entries) do if not e.born then e.born = clock end end
  preloadStep()
  if clock - aliveAt >= 0.25 then   -- the script keeps drawing the banners itself unless this beats: the window can be hidden or closed
    aliveAt = clock
    if clock - drawnAt < 0.5 then broadcast(KEY_ALIVE, string.format("%.2f", clock)) end
  end
  if store.lang ~= lastLang or clock - langAt >= 2 then langAt, lastLang = clock, store.lang; broadcast(KEY_LANG, store.lang) end
end

-- ---- drawing: ImGui through CSP's ui.*, inside the window's own area -----------------------------------------------------------------------------------------------------------------------------
local PAD, BADGE, CAPH, GAP, RAD = 6, 44, 56, 10, 14
local TITLE, SUB = 18, 11   -- the sizes DirectWrite used: the face is monospace (0.6 em), so a text is exactly as wide in letters as it was in DirectWrite
local function haveClip() return type(ui.pushClipRect) == "function" and type(ui.popClipRect) == "function" end
local function textWidth(text, size)
  if useGlyphs() then return glyphWidth(text, size) end   -- exact: the face is monospace
  local w = safe(function() return ui.measureDWriteText(text, size).x end)
  return w or (#text * size * 0.62)
end
local function iconPath(img) return FOLDER and (FOLDER .. "/icons/ico-" .. img .. ".png") or nil end

local function fullWidth(l, k) return (PAD * 2 + BADGE + GAP) * k + math.max(textWidth(l.title, TITLE * k), textWidth(l.sub, SUB * k)) + 10 * k + 4 end

local function capWidth(e, k)   -- the width of a capsule as it is drawn right now (an icon alone is narrow, one with its text out is wide)
  local c, l = e.cap, e.line
  local tw = (math.max(textWidth(l.title, TITLE * k), textWidth(l.sub, SUB * k)) + 10 * k) * c.w
  return ((PAD * 2 + BADGE) * k + (tw > 1 and (GAP * k + tw) or 0)) * c.scale + 4
end

local function drawCapsule(e, k, x0)   -- at x0, the top-left of its place in the window (its column and row)
  if not e.firstDraw then e.firstDraw = clock; stat.delay = e.firstDraw - (e.born or clock); stat.delayMax = math.max(stat.delayMax, stat.delay) end   -- (how long a banner waited from its creation to its first drawing)
  local c, l = e.cap, e.line
  local col = l.c
  local textW = math.max(textWidth(l.title, TITLE * k), textWidth(l.sub, SUB * k)) + 10 * k
  local tw = textW * c.w
  local sc, fade = c.scale, c.fade
  local W = (PAD * 2 + BADGE) * k + (tw > 1 and (GAP * k + tw) or 0)
  local w, h = W * sc, CAPH * k * sc
  local p1 = x0 + vec2(2, 2 + (CAPH * k - h) / 2)
  local p2 = p1 + vec2(w, h)
  ui.drawRectFilled(p1, p2, rgbm(0.047, 0.047, 0.055, 0.94 * fade), RAD * k * sc)
  safe(ui.drawRect, p1, p2, rgbm(col[1], col[2], col[3], fade), RAD * k * sc, nil, 2)
  local bs = BADGE * k * c.pop * sc
  local bc = p1 + vec2(PAD * k * sc + BADGE * k * sc / 2, h / 2)
  local b1, b2 = bc - vec2(bs / 2, bs / 2), bc + vec2(bs / 2, bs / 2)
  ui.drawRectFilled(b1, b2, rgbm(col[1], col[2], col[3], fade), 11 * k * sc)
  local ip = iconPath(l.img)
  if ip and safe(ui.isImageReady, ip) then safe(ui.drawImage, ip, b1 + vec2(bs * 0.14, bs * 0.14), b2 - vec2(bs * 0.14, bs * 0.14), rgbm(1, 1, 1, fade)) end
  if tw > 1 and sc == 1 then   -- the text, inside its own clip: nothing is ever drawn outside the panel (without a clip it is drawn only once the panel is fully open)
    local t1 = p1 + vec2((PAD + BADGE + GAP) * k, 0)
    local t2 = vec2(p2.x - 4, p2.y)
    local clipped = haveClip() and safe(ui.pushClipRect, t1, t2, true)
    if useGlyphs() then
      drawGlyphText(t1.x, p1.y + glyphY(10, TITLE) * k, l.title, "t", TITLE * k, rgbm(1, 1, 1, fade), tw - 4 * k, clipped)
      drawGlyphText(t1.x, p1.y + glyphY(33, SUB) * k, l.sub, "s", SUB * k, rgbm(0.68, 0.71, 0.76, fade), tw - 4 * k, clipped)
    elseif clipped or c.w >= 0.999 then
      local pushed = FONT and safe(ui.pushDWriteFont, FONT)
      ui.setCursor(t1 + vec2(0, 5 * k))
      safe(ui.dwriteText, l.title, TITLE * k, rgbm(1, 1, 1, fade))
      ui.setCursor(t1 + vec2(0, 30 * k))
      if l.sub ~= "" then safe(ui.dwriteText, l.sub, SUB * k, rgbm(0.68, 0.71, 0.76, fade)) end
      if pushed then safe(ui.popDWriteFont) end
    end
    if clipped then ui.popClipRect() end
  end
end

function script.windowBanners(dt)
  drawnAt = clock
  stat.winCalls = stat.winCalls + 1
  local k = store.scale
  local x0 = ui.getCursor()
  local rows = math.max(1, store.rows or 5)
  local slot = (CAPH + 8) * k
  local colX, width = 0, 0
  for first = 1, math.max(1, #entries), rows do   -- a column at a time, top to bottom; the next one starts to its right (the banners that do not fit under the others)
    local colW = 0
    for i = first, math.min(first + rows - 1, #entries) do colW = math.max(colW, capWidth(entries[i], k)) end
    for i = first, math.min(first + rows - 1, #entries) do drawCapsule(entries[i], k, x0 + vec2(colX, (i - first) * slot)) end
    colX = colX + colW + (colW > 0 and 10 * k or 0)
    width = colX
  end
  width = math.max(width, 330 * k * (#entries == 0 and 1 or 0), 60 * k)
  local needH = math.min(math.max(1, #entries), rows) * slot
  if store.reserve == 1 then
    -- A banner drawn outside the window's rectangle is cut by the game until the window has grown, so a new banner could open (0.55 s) unseen and appear all at once: the window has the room of the
    -- whole grid from the start (the rows of a column, and as many columns as the most banners a script may send need), and its size does not follow the unfolding text either.
    local fullW = 400 * k
    for _, e in ipairs(entries) do fullW = math.max(fullW, fullWidth(e.line, k)) end
    local cols = math.max(1, math.ceil(MAX_LINES / rows))
    width, needH = cols * fullW + (cols - 1) * 10 * k, rows * slot
  end
  ui.setCursor(x0 + vec2(0, needH))
  ui.dummy(vec2(width, 2))
  stat.imgsLast, stat.imgs = stat.imgs, 0
  if store.info == 1 then   -- numbers under the banners: what the app has, what it draws, how fast the game runs it, what window it asked for and got
    local ws0 = safe(ui.windowSize)
    ui.text(string.format("entradas=%d  fps=%.0f (peor %.0f ms)  llamadas a la ventana=%.0f/s  letras/fotograma=%d  pido %dx%d  tengo %s", #entries, stat.fps, stat.worst * 1000, stat.winRate, stat.imgsLast, width, needH, ws0 and string.format("%dx%d", ws0.x, ws0.y) or "?"))
    ui.text(string.format("retraso creada->dibujada: ultimo %.2f s, maximo %.2f s", stat.delay or 0, stat.delayMax))
    for i, e in ipairs(entries) do   -- one line per banner: where the app puts it and in which state
      local c = e.cap
      ui.text(string.format("%d %-12s %-5s w=%.2f pop=%.2f esc=%.2f op=%.2f  col %d fila %d", i, e.id, c.s, c.w, c.pop, c.scale, c.fade, math.floor((i - 1) / rows), (i - 1) % rows))
    end
  end
  seenWin.need, seenWin.drawn = { width, needH }, #entries   -- (and what the game really gave the window: it can be less than it asked for)
  seenWin.maxDrawn = math.max(seenWin.maxDrawn, #entries)
  local ws = safe(ui.windowSize)
  if ws then seenWin.got = { ws.x, ws.y } end   -- (the window fits its content: the room of the columns of banners that are on screen)
end

-- ---- the settings window ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local WANT = { "ui.pushClipRect", "ui.popClipRect", "ui.drawRect", "ui.drawRectFilled", "ui.drawImage", "ui.isImageReady", "ui.measureDWriteText", "ui.dwriteText", "ui.pushDWriteFont",
               "ui.MediaPlayer", "ui.button", "ac.storage", "ac.onSharedEvent", "ac.broadcastSharedEvent", "ac.getFolder" }
local function has(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    v = type(v) == "table" and v[part] or nil
    if v == nil then return false end
  end
  return true
end

function script.windowSettings(dt)
  ui.text("HLH Banners (el marco de esta ventana se puede mover; la de las banderas tambien)")
  if ui.button("Demo: " .. ({ [0] = "off", "normal", "varias" })[store.demo]) then store.demo = (store.demo + 1) % 3; demoT = 0 end
  ui.sameLine()
  if ui.button("Idioma: " .. store.lang) then store.lang = cycle(LANGS, store.lang) end
  if ui.button("Tamano: " .. math.floor(store.scale * 100 + 0.5) .. "%") then store.scale = cycle(SCALES, store.scale) end
  ui.sameLine()
  if ui.button("Sonido: " .. (store.sound == 0 and "off" or (store.sound .. "%"))) then store.sound = cycle(VOLUMES, store.sound) end
  ui.sameLine()
  if ui.button("Probar audio") then playRadio() end
  if ui.button("Texto: " .. (store.glyph == 1 and "imagenes de letras" or "DirectWrite")) then store.glyph = 1 - store.glyph end
  ui.sameLine()
  if ui.button("Por columna: " .. store.rows) then store.rows = cycle(ROWS, store.rows) end
  ui.sameLine()
  if ui.button("Ventana: " .. (store.reserve == 1 and "reservada" or "ajustada")) then store.reserve = 1 - store.reserve end
  ui.sameLine()
  if ui.button("Info en pantalla: " .. (store.info == 1 and "on" or "off")) then store.info = 1 - store.info end
  if store.demo > 0 and incoming then   -- a script that sends lines (the real hub, or the probe) has priority over the demo: say so, it looks like the demo is broken
    ui.textColored("AVISO: el demo esta tapado: un script (la sonda?) esta mandando lineas. Cierra la sonda para ver el demo.", rgbm(1, 0.78, 0.2, 1))
  end
  ui.separator()
  ui.text("Diagnostico (que ofrece el juego):")
  for _, name in ipairs(WANT) do ui.text("  " .. name .. ": " .. (has(name) and "si" or "NO")) end
  ui.text("carpeta de la app: " .. tostring(FOLDER))
  ui.text("banderas en pantalla: " .. #entries .. " (maximo visto " .. seenWin.maxDrawn .. ") en " .. math.ceil(#entries / math.max(1, store.rows)) .. " columna(s) de " .. store.rows .. " filas como maximo")
  ui.text("la ventana de banderas pide " .. (seenWin.need and string.format("%d x %d", seenWin.need[1], seenWin.need[2]) or "-") .. " px y el juego le da " .. (seenWin.got and string.format("%d x %d", seenWin.got[1], seenWin.got[2]) or "?") .. " px")
  ui.text("audio: " .. audio.status)
  ui.text("letras cargadas: " .. preload.ready .. " / " .. #allGlyphs .. " (preguntadas " .. preload.i .. ")")
  ui.text(string.format("fps medidos por la app: %.0f (peor fotograma %.0f ms)", stat.fps, stat.worst * 1000))
  ui.text("lineas de un script: " .. (incoming and "recibiendo" or "ninguna") .. " | ultima hace " .. (incoming and string.format("%.1f s", clock - incomingAt) or "-"))
end

if _G.__HLH_TEST then _G.__hlh = { stat = stat, glyphY = glyphY, codepoints = codepoints, pickSet = pickSet, quadSize = quadSize, glyphWidth = glyphWidth, capStep = capStep, newCap = newCap, newStack = newStack, stackUpdate = stackUpdate, parseLines = parseLines, store = store, calls = calls, audio = audio,
                                    KEYS = { KEY_LINES, KEY_LANG, KEY_ALIVE }, cycle = cycle, fullWidth = fullWidth, demoLines = demoLines } end
