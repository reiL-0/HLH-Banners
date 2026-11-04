-- PROBE (throwaway): can a CSP script POST to the local app? Run as a script on any AC session (apps/lua or an online script).
-- Shows, on screen, the answer to /tick every second and a base64 round trip on /echo once.
local URL, HDR = "http://127.0.0.1:28761", { ["X-OPR-Init"] = "1" }
local shown, nextAt, echoed = "waiting", 0, false

local function post(path, body, cb)
  -- web.post argument order is not certain: try (url, headers, body, cb), then (url, body, cb)
  local ok = pcall(web.post, URL .. path, HDR, body, cb)
  if not ok then ok = pcall(web.post, URL .. path, body, cb) end
  if not ok then shown = "web.post to localhost raised an error" end
end

function script.update(dt)
  local t = os.clock()
  if t < nextAt then return end
  nextAt = t + 1
  post("/tick", "", function(err, resp)
    shown = err and ("tick error: " .. tostring(err)) or ("tick " .. tostring(resp and (resp.status or resp.code)) .. " " .. tostring(resp and resp.body))
  end)
  if not echoed then
    echoed = true
    post("/echo", "aGVsbG8=", function(err, resp) shown = shown .. " | echo " .. tostring(err or (resp and resp.body)) end)   -- "hello"
  end
end

function script.drawUI()
  ui.transparentWindow("opr_banners_probe", vec2(20, 160), vec2(900, 30), function() ui.text(shown) end)
end
