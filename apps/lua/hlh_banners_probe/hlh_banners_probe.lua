-- PROBE (throwaway), as a CSP Lua app: can a CSP script talk to the HLH Banners Python app on 127.0.0.1?
-- Every 150 ms it POSTs /tick with the lines it "composed" (a yellow flag for 6 s, then none for 6 s): the Python app must draw the capsule, fold it at 5 s and close it.
-- The window shows what the app answered (render_age_ms, lang) and the base64 round trip on /echo (once).
local URL, HDR = "http://127.0.0.1:28761", { ["X-HLH-Init"] = "1" }
local function lines(lang)   -- the script composes the text in the language the driver chose in the app (the answer's `lang`); "auto" = its own (Spanish here)
  local title, sub = "AMARILLA", "PRECAUCION EN PISTA"
  if lang == "en" then title, sub = "YELLOW", "CAUTION ON TRACK" end
  return '{"v":1,"lines":[{"id":"flag","img":"flag-yellow","kind":"info","c":[1,0.757,0.027],"title":"' .. title .. '","sub":"' .. sub .. '","ev":"1"}]}'
end
local OFF = '{"v":1,"lines":[]}'
local lang = "auto"
local shown, nextAt, echoed, t0 = "waiting for the first answer...", 0, false, os.clock()

local function post(path, body, cb)
  -- web.post's argument order is not certain: try (url, headers, body, cb), then (url, body, cb)
  local ok = pcall(web.post, URL .. path, HDR, body, cb)
  if not ok then ok = pcall(web.post, URL .. path, body, cb) end
  if not ok then shown = "web.post to localhost raised an error" end
end

function script.update(dt)
  local t = os.clock()
  if t < nextAt then return end
  nextAt = t + 0.15
  post("/tick", ((t - t0) % 12) < 6 and lines(lang) or OFF, function(err, resp)
    local l = resp and type(resp.body) == "string" and resp.body:match('"lang":%s*"(%a+)"')
    if l then lang = l end
    shown = err and ("tick error: " .. tostring(err)) or ("probe v2 (follows the language) sending lang=" .. lang .. " | tick " .. tostring(resp and (resp.status or resp.code)) .. " " .. tostring(resp and resp.body))
  end)
  if not echoed then
    echoed = true
    post("/echo", "aGVsbG8=", function(err, resp) shown = shown .. " | echo " .. tostring(err or (resp and resp.body)) end)   -- "hello"
  end
end

function script.windowMain(dt)
  ui.text(shown)
end

-- The frameless window: a capsule drawn with the calls the hub uses (rounded rectangles, a border, a clipped text), to see in the game (a) that the window has no frame at all and
-- (b) that those calls draw what they should. Static: only to look at.
local function safe(f, ...) local ok, r = pcall(f, ...); if ok then return r end return nil end
function script.windowBanner(dt)
  local c = ui.getCursor()
  local W, H = 380, 56
  local col = rgbm(1, 0.757, 0.027, 1)
  local steps = {}
  steps[#steps + 1] = safe(ui.drawRectFilled, c, c + vec2(W, H), rgbm(0.047, 0.047, 0.055, 0.94), 14)
  steps[#steps + 1] = safe(ui.drawRect, c, c + vec2(W, H), col, 14, nil, 2)
  steps[#steps + 1] = safe(ui.drawRectFilled, c + vec2(6, 6), c + vec2(50, 50), col, 11)
  if safe(ui.pushClipRect, c + vec2(60, 0), c + vec2(60 + 200, H), true) then   -- the text inside a clip: only 200 px of it can show
    ui.setCursor(c + vec2(60, 8))
    safe(ui.dwriteText, "AMARILLA - TEXTO MUY LARGO QUE SE RECORTA", 18, rgbm(1, 1, 1, 1))
    ui.setCursor(c + vec2(60, 31))
    safe(ui.dwriteText, "frameless Lua window", 11, rgbm(0.68, 0.71, 0.76, 1))
    ui.popClipRect()
  end
  ui.setCursor(c + vec2(0, H))
  ui.dummy(vec2(W, 4))   -- (keeps the window's size: it fits its content)
end
