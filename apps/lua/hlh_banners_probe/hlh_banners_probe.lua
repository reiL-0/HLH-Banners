-- PROBE (throwaway), as a CSP Lua app: can a CSP script talk to the HLH Banners Python app on 127.0.0.1?
-- Every 150 ms it POSTs /tick with the lines it "composed" (a yellow flag for 6 s, then none for 6 s): the Python app must draw the capsule, fold it at 5 s and close it.
-- The window shows what the app answered (render_age_ms, lang) and the base64 round trip on /echo (once).
local URL, HDR = "http://127.0.0.1:28761", { ["X-HLH-Init"] = "1" }
local ON = '{"v":1,"lines":[{"id":"flag","img":"flag-yellow","kind":"info","c":[1,0.757,0.027],"title":"AMARILLA","sub":"PRECAUCION EN PISTA","ev":"1"}]}'
local OFF = '{"v":1,"lines":[]}'
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
  post("/tick", ((t - t0) % 12) < 6 and ON or OFF, function(err, resp)
    shown = err and ("tick error: " .. tostring(err)) or ("tick " .. tostring(resp and (resp.status or resp.code)) .. " " .. tostring(resp and resp.body))
  end)
  if not echoed then
    echoed = true
    post("/echo", "aGVsbG8=", function(err, resp) shown = shown .. " | echo " .. tostring(err or (resp and resp.body)) end)   -- "hello"
  end
end

function script.windowMain(dt)
  ui.text(shown)
end
