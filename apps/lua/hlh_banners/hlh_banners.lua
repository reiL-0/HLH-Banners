-- HLH Banners: a Custom Shaders Patch Lua app. Draws the race-control banners as capsules (an icon badge + a text panel) in a window the driver moves. Its window has none of the game's frame (the
-- manifest uses the official NO_BACKGROUND / NO_TITLE_BAR / AUTO_RESIZE flags). The app knows no server: it draws the lines a game script sends it (HLH.Banners.lines, see CONTRACT.md) and answers with its
-- language and a heartbeat. Without lines it can run a demo of every kind of banner. DRAFT: written from the CSP Lua documentation; none of it has run in the game yet, and the settings window
-- lists which game functions exist so the first session tells what works.
--   banner kinds: "info" folds its text to the icon after 5 s, "action" keeps it while it applies, "sticky" stays until the script stops sending it.

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
local SCALES, VOLUMES, LANGS = { 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0 }, { 100, 70, 40, 0 }, { "auto", "es", "en" }
local store = safe(ac.storage, { lang = "auto", scale = 1.25, sound = 100, demo = 1 }) or { lang = "auto", scale = 1.25, sound = 100, demo = 1 }
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

local DEMO = {
  es = { flag = { "AMARILLA", "PRECAUCION EN PISTA" }, blue = { "BANDERA AZUL", "DEJA PASAR AL MAS RAPIDO" }, limits = { "LIMITES DE PISTA", "LLEVAS 2/5 - TE QUEDAN 3" }, winner = { "GANADOR", "SOFIA RIOS" } },
  en = { flag = { "YELLOW", "CAUTION ON TRACK" }, blue = { "BLUE FLAG", "LET THE FASTER CAR THROUGH" }, limits = { "TRACK LIMITS", "2/5 - 3 LEFT" }, winner = { "WINNER", "SOFIA RIOS" } },
}
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

-- ---- the game's calls: the hook for the script's lines, and the heartbeat/language we answer with -----------------------------------------------------------------------------------------
safe(function()
  ac.onSharedEvent(KEY_LINES, function(data)
    local lines = parseLines(data)
    if lines then incoming, incomingAt = lines, clock end
  end)
end)

local function broadcast(key, data) return safe(function() ac.broadcastSharedEvent(key, data) return true end) end

function script.update(dt)
  dt = clamp(dt or 0, 0, 0.1)
  clock = clock + dt
  local live = incoming and clock - incomingAt < 1.0
  if not live then incoming = nil end
  local lines
  if live then lines = incoming
  elseif store.demo == 1 then demoT = (demoT + dt) % 26; lines = demoLines(demoT)
  else lines = {} end
  queueCalls(lines)
  if #calls.pending > 0 and clock >= calls.nextAt then table.remove(calls.pending, 1); calls.nextAt = clock + 0.4; playRadio() end
  entries = stackUpdate(stack, lines, dt)
  if clock - aliveAt >= 0.25 then   -- the script keeps drawing the banners itself unless this beats: the window can be hidden or closed
    aliveAt = clock
    if clock - drawnAt < 0.5 then broadcast(KEY_ALIVE, string.format("%.2f", clock)) end
  end
  if store.lang ~= lastLang or clock - langAt >= 2 then langAt, lastLang = clock, store.lang; broadcast(KEY_LANG, store.lang) end
end

-- ---- drawing: ImGui through CSP's ui.*, inside the window's own area -----------------------------------------------------------------------------------------------------------------------------
local PAD, BADGE, CAPH, GAP, RAD = 6, 44, 56, 10, 14
local TITLE, SUB = 18, 11
local function haveClip() return type(ui.pushClipRect) == "function" and type(ui.popClipRect) == "function" end
local function textWidth(text, size)
  local w = safe(function() return ui.measureDWriteText(text, size).x end)
  return w or (#text * size * 0.62)
end
local function iconPath(img) return FOLDER and (FOLDER .. "/icons/ico-" .. img .. ".png") or nil end

local function fullWidth(l, k) return (PAD * 2 + BADGE + GAP) * k + math.max(textWidth(l.title, TITLE * k), textWidth(l.sub, SUB * k)) + 10 * k + 4 end

local function drawCapsule(e, k)   -- at the cursor; moves the cursor down
  local c, l = e.cap, e.line
  local col = l.c
  local x0 = ui.getCursor()
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
    if clipped or c.w >= 0.999 then
      local pushed = FONT and safe(ui.pushDWriteFont, FONT)
      ui.setCursor(t1 + vec2(0, 5 * k))
      safe(ui.dwriteText, l.title, TITLE * k, rgbm(1, 1, 1, fade))
      ui.setCursor(t1 + vec2(0, 30 * k))
      if l.sub ~= "" then safe(ui.dwriteText, l.sub, SUB * k, rgbm(0.68, 0.71, 0.76, fade)) end
      if pushed then safe(ui.popDWriteFont) end
    end
    if clipped then ui.popClipRect() end
  end
  ui.setCursor(x0 + vec2(0, (CAPH + 8) * k))
end

function script.windowBanners(dt)
  drawnAt = clock
  local k = store.scale
  local x0 = ui.getCursor()
  local width = 330 * k
  for _, e in ipairs(entries) do width = math.max(width, fullWidth(e.line, k)) end
  for _, e in ipairs(entries) do drawCapsule(e, k) end
  ui.setCursor(x0 + vec2(0, math.max(1, #entries) * (CAPH + 8) * k))
  ui.dummy(vec2(width, 2))   -- (the window fits its content: the room of the banners that are on screen, at least one)
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
  if ui.button("Demo: " .. (store.demo == 1 and "on" or "off")) then store.demo = 1 - store.demo end
  ui.sameLine()
  if ui.button("Idioma: " .. store.lang) then store.lang = cycle(LANGS, store.lang) end
  if ui.button("Tamano: " .. math.floor(store.scale * 100 + 0.5) .. "%") then store.scale = cycle(SCALES, store.scale) end
  ui.sameLine()
  if ui.button("Sonido: " .. (store.sound == 0 and "off" or (store.sound .. "%"))) then store.sound = cycle(VOLUMES, store.sound) end
  ui.sameLine()
  if ui.button("Probar audio") then playRadio() end
  ui.separator()
  ui.text("Diagnostico (que ofrece el juego):")
  for _, name in ipairs(WANT) do ui.text("  " .. name .. ": " .. (has(name) and "si" or "NO")) end
  ui.text("carpeta de la app: " .. tostring(FOLDER))
  ui.text("audio: " .. audio.status)
  ui.text("lineas de un script: " .. (incoming and "recibiendo" or "ninguna") .. " | ultima hace " .. (incoming and string.format("%.1f s", clock - incomingAt) or "-"))
end

if _G.__HLH_TEST then _G.__hlh = { capStep = capStep, newCap = newCap, newStack = newStack, stackUpdate = stackUpdate, parseLines = parseLines, store = store, calls = calls, audio = audio,
                                    KEYS = { KEY_LINES, KEY_LANG, KEY_ALIVE }, cycle = cycle, fullWidth = fullWidth, demoLines = demoLines } end
