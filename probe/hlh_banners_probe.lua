-- PROBE (throwaway): can a CSP script talk to the HLH Banners app on 127.0.0.1? Run it as a script in any AC session (apps/lua or an online script, ONE of them: the answer can differ).
-- Every 150 ms it POSTs /tick with the lines it "composed" (a yellow flag for 6 s, then none for 6 s, in a loop): the app must draw the capsule, fold it, and close it.
-- On screen: what the app answered (render_age_ms: how long ago it last drew; lang: the language picked in the app) and the base64 round trip on /echo, once.
local URL, HDR = "http://127.0.0.1:28761", { ["X-HLH-Init"] = "1" }
local function lines(lang)   -- the script composes the text in the language the driver chose in the app (the answer's `lang`); "auto" = its own (Spanish here)
  local title, sub = "AMARILLA", "PRECAUCION EN PISTA"
  if lang == "en" then title, sub = "YELLOW", "CAUTION ON TRACK" end
  return '{"v":1,"lines":[{"id":"flag","img":"flag-yellow","kind":"info","c":[1,0.757,0.027],"title":"' .. title .. '","sub":"' .. sub .. '","ev":"1"}]}'
end
local OFF = '{"v":1,"lines":[]}'
local lang = "auto"
local shown, nextAt, echoed, t0 = "waiting", 0, false, os.clock()

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
    shown = err and ("tick error: " .. tostring(err)) or ("tick " .. tostring(resp and (resp.status or resp.code)) .. " " .. tostring(resp and resp.body))
  end)
  if not echoed then
    echoed = true
    post("/echo", "aGVsbG8=", function(err, resp) shown = shown .. " | echo " .. tostring(err or (resp and resp.body)) end)   -- "hello"
  end
end

function script.drawUI()
  ui.transparentWindow("hlh_banners_probe", vec2(20, 160), vec2(900, 30), function() ui.text(shown) end)
end
