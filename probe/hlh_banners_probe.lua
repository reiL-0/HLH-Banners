-- PROBE (throwaway): does a game SCRIPT reach the HLH Banners app? It plays the part of the hub: every 150 ms it broadcasts, with ac.broadcastSharedEvent, the lines it "composed" (a yellow flag for 6 s,
-- then none for 6 s, in the language the app announces), and it listens for the app's heartbeat (HLH.Banners.alive) and language (HLH.Banners.lang). Its window says what arrived.
-- Run it as an app (apps/lua) first. The same file as an online script of a test server (probe/hlh_banners_probe.lua) tells if a SERVER script can talk to the app too: the answer can differ.
local clock, nextAt, sent, aliveAt, lang, lastErr = 0, 0, 0, nil, "auto", nil
local KEY_LINES, KEY_ALIVE, KEY_LANG = "HLH.Banners.lines", "HLH.Banners.alive", "HLH.Banners.lang"
local hasBroadcast = type(ac.broadcastSharedEvent) == "function"
local hasListen = type(ac.onSharedEvent) == "function"

local function lines(l)   -- the text in the language the app announces ("auto" = the script's own, Spanish here)
  local title, sub = "AMARILLA", "PRECAUCION EN PISTA"
  if l == "en" then title, sub = "YELLOW", "CAUTION ON TRACK" end
  return "id=flag;img=flag-yellow;kind=info;c=1,0.757,0.027;title=" .. title .. ";sub=" .. sub .. ";ev=1"
end

if hasListen then
  pcall(ac.onSharedEvent, KEY_ALIVE, function(data) aliveAt = clock end)
  pcall(ac.onSharedEvent, KEY_LANG, function(data) if type(data) == "string" then lang = data end end)
end

function script.update(dt)
  clock = clock + (dt or 0)
  if clock < nextAt or not hasBroadcast then return end
  nextAt = clock + 0.15
  local ok, err = pcall(ac.broadcastSharedEvent, KEY_LINES, (clock % 12) < 6 and lines(lang) or "")
  if ok then sent = sent + 1 else lastErr = tostring(err) end
end

local function report()
  return {
    "probe v3: sends the lines with ac.broadcastSharedEvent (" .. (hasBroadcast and "exists" or "MISSING") .. "), listens with ac.onSharedEvent (" .. (hasListen and "exists" or "MISSING") .. ")",
    "sent: " .. sent .. (lastErr and (" | error: " .. lastErr) or ""),
    "heartbeat from the app: " .. (aliveAt and string.format("%.1f s ago", clock - aliveAt) or "NOTHING YET (is HLH Banners enabled and its banners window open?)"),
    "language the app announced: " .. lang,
  }
end

function script.drawUI()
  ui.transparentWindow("hlh_banners_probe", vec2(20, 160), vec2(1000, 90), function() for _, t in ipairs(report()) do ui.text(t) end end)
end
