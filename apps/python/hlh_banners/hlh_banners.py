# HLH Banners - DRAFT / PROBE (v0.3). What the first game sessions showed: the GL drawing and the animation work, labels (ac.addLabel) are not seen over our own drawing and cannot be
# clipped (so the text is drawn as textured glyph quads: glyphs.py, font/), and winsound plays. The window is exactly the size of the banners on screen, transparent and without buttons:
# what the driver drags are the banners. The settings (language, size, sound, demo, "move") are in the other app, hlh_banners_settings, and reach this one through hlh_banners.ini.
# The app knows no server (CONTRACT.md). It takes the hub's lines on 127.0.0.1 and reports what works to probe_result.txt.
# The pure parts (capsule.py, ipc.py, guard.py, glyphs.py, hlh_settings.py) are tested on a desktop: tests/. Python 3.3 compatible (no f-strings).
import os
import sys
import time
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
for extra in ("stdlib", "stdlib64"):   # AC's interpreter may need these (copy a matching Python 3.3 stdlib here)
    p = os.path.join(HERE, extra)
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import ac
import acsys

PORT = 28761
RESULT = os.path.join(HERE, "probe_result.txt")
INI = os.path.join(HERE, "hlh_banners.ini")
WAV = os.path.join(HERE, "hlh_beep.wav")
LOCK = threading.Lock()
app = None
server = None
notes = []
state = {"lines": [], "lines_at": 0.0, "last_render": 0.0, "demo_t": 0.0, "ini_mtime": None, "ini_check": 0.0, "size": None}
cfg = {}   # the driver's settings (hlh_settings), refreshed from the file
stack = None
glyphs = None
hlh_settings = None
textures, glyph_tex = {}, {}
POOL = 4   # banners drawn at once
TITLE, SUB = 20.0, 12.0   # the text sizes at 100 % (px)
PAD = 6.0
sounds = {"seen": {}, "pending": [], "next": 0.0}


def note(key, val):
    notes.append("%s: %s" % (key, val))
    try:
        with open(RESULT, "w") as f:
            f.write("\n".join(notes) + "\n")
    except Exception:
        pass


def try_import(name):
    try:
        __import__(name)
        note("import " + name, "ok")
        return True
    except Exception as e:
        note("import " + name, "FAIL " + repr(e))
        return False


def refresh_settings(now):
    """Reads the settings file (the other app writes it) when it changed; checked twice a second."""
    if now < state["ini_check"]:
        return
    state["ini_check"] = now + 0.5
    try:
        mt = os.path.getmtime(INI)
    except OSError:
        mt = None
    if mt == state["ini_mtime"]:
        return
    state["ini_mtime"] = mt
    old = dict(cfg)
    cfg.update(hlh_settings.load(INI))
    if cfg["sound"] == 0:   # sound off: whatever was waiting its turn is dropped, not played later
        del sounds["pending"][:]
    if cfg["sound"] != old.get("sound") and cfg["sound"] > 0:
        try:
            beep_wav(cfg["sound"])
        except Exception as e:
            note("wav", "FAIL " + repr(e))
    if old and cfg["test"] != old.get("test"):   # "Probar audio" in the settings app
        play_sound()


# ---- the local server -----------------------------------------------------------------------------------------------------------------------------------------------------------
def serve():
    global server
    import base64, hashlib, json
    import socket
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from socketserver import ThreadingMixIn
    import guard
    import ipc

    slots = threading.BoundedSemaphore(8)   # at most 8 connections at once (it is loopback: the hub needs one)

    class S(ThreadingMixIn, HTTPServer):
        """One thread per connection, so a slow client cannot hold up the hub's heartbeat or the game's shutdown (daemon threads are not waited for)."""
        daemon_threads = True

        def handle_error(self, request, client_address):   # (a connection cut by its deadline or by the shutdown is not worth a traceback in the game's log)
            pass

        def process_request(self, request, client_address):
            if not slots.acquire(False):
                return self.shutdown_request(request)
            ThreadingMixIn.process_request(self, request, client_address)

        def process_request_thread(self, request, client_address):
            try:
                ThreadingMixIn.process_request_thread(self, request, client_address)
            finally:
                slots.release()

    class H(BaseHTTPRequestHandler):
        timeout = 5   # (between reads; the whole request also has a deadline: see setup)

        def setup(self):
            BaseHTTPRequestHandler.setup(self)

            def kill():   # a request that drips in slowly is cut after 10 s, whatever it sends
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except Exception:
                    pass
            self._deadline = threading.Timer(10.0, kill)
            self._deadline.daemon = True
            self._deadline.start()

        def finish(self):
            self._deadline.cancel()
            BaseHTTPRequestHandler.finish(self)

        def log_message(self, *a):
            pass

        def reply(self, code, obj):
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def handle_any(self):
            bad = guard.check(self.command, self.headers, PORT)
            if bad:
                return self.reply(bad[0], {"error": bad[1]})
            n = int(self.headers.get("Content-Length"))
            data = self.rfile.read(n) if n else b""
            if self.path == "/tick":   # the heartbeat AND the data: the hub sends the lines it composed (an empty body = only a heartbeat)
                if data:
                    try:
                        obj = json.loads(data.decode("utf-8"))
                        if isinstance(obj, dict) and obj.get("v", 1) != 1:   # a script that speaks another version of the contract: it draws by itself
                            return self.reply(409, {"error": "version"})
                        lines = ipc.validate_lines(obj)
                    except ValueError:   # (a ValueError is also what a bad JSON raises: the answer never echoes the body)
                        return self.reply(400, {"error": "lines"})
                    with LOCK:
                        state["lines"], state["lines_at"] = lines, time.time()
                age = int((time.time() - state["last_render"]) * 1000) if state["last_render"] else -1
                return self.reply(200, {"render_age_ms": age, "lang": cfg.get("lang", "auto"), "v": 1})
            if self.path == "/echo":   # the base64 round trip the pack download will use
                raw = base64.b64decode(data)
                return self.reply(200, {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
            self.reply(404, {"error": "path"})

        do_POST = do_GET = do_OPTIONS = do_PUT = do_DELETE = handle_any

    server = S(("127.0.0.1", PORT), H)
    note("server", "listening on 127.0.0.1:%d" % PORT)
    server.serve_forever()


def thread_main():
    try:
        serve()
    except Exception as e:
        note("server", "FAIL " + repr(e))


# ---- drawing: GL only -----------------------------------------------------------------------------------------------------------------------------------------------------------
def quad(x, y, w, h):
    ac.glBegin(acsys.GL.Quads)
    ac.glVertex2f(x, y)
    ac.glVertex2f(x + w, y)
    ac.glVertex2f(x + w, y + h)
    ac.glVertex2f(x, y + h)
    ac.glEnd()


def rrect(x, y, w, h, r, rgba):
    """A filled rounded rectangle: a cross of two quads and four corner fans."""
    import math
    r = max(0.0, min(r, w / 2.0, h / 2.0))
    ac.glColor4f(*rgba)
    quad(x + r, y, w - 2 * r, h)
    quad(x, y + r, r, h - 2 * r)
    quad(x + w - r, y + r, r, h - 2 * r)
    for cx, cy, a0 in ((x + r, y + r, math.pi), (x + w - r, y + r, 1.5 * math.pi), (x + w - r, y + h - r, 0.0), (x + r, y + h - r, 0.5 * math.pi)):
        ac.glBegin(acsys.GL.Triangles)
        for i in range(6):
            a, b = a0 + i * math.pi / 12, a0 + (i + 1) * math.pi / 12
            ac.glVertex2f(cx, cy)
            ac.glVertex2f(cx + r * math.cos(a), cy + r * math.sin(a))
            ac.glVertex2f(cx + r * math.cos(b), cy + r * math.sin(b))
        ac.glEnd()


def icon(img):
    if img not in textures:
        path = os.path.join(HERE, "icons", "ico-" + img + ".png")   # img passed ipc.KEY: no path separators; only a file that exists
        try:
            textures[img] = ac.newTexture(path) if os.path.isfile(path) else None
        except Exception as e:
            textures[img] = None
            note("texture " + img, "FAIL " + repr(e))
    return textures[img]


def glyph(set_name, code):
    key = (set_name, code)
    if key not in glyph_tex:
        path = os.path.join(HERE, "font", set_name, "%04x.png" % code)   # code comes from glyphs.code_of: a number in the known set
        try:
            glyph_tex[key] = ac.newTexture(path) if os.path.isfile(path) else None
        except Exception as e:
            glyph_tex[key] = None
            note("glyph %s %04x" % (set_name, code), "FAIL " + repr(e))
    return glyph_tex[key]


def draw_text(x, y, text, kind, size, rgba, reveal):
    """The text as quads, only the letters that fit completely inside `reveal` px (so the panel opens letter by letter and nothing is ever outside it)."""
    set_name = glyphs.pick(kind, size)
    gw, gh = glyphs.quad_size(set_name, size)
    ac.glColor4f(*rgba)
    for dx, code in glyphs.layout(text, size, reveal):
        tex = glyph(set_name, code)
        if tex:
            ac.glQuadTextured(x + dx, y, gw, gh, tex)


def full_width(line, k):
    """The width of a banner with its text fully out, borders included."""
    return (12 + 44) * k + 10 * k + max(glyphs.width(line["title"], TITLE * k), glyphs.width(line["sub"], SUB * k)) + 10 * k + 4 * k


def footprint(entries, k):
    """The size of the window: just the banners that are on screen (at least the room of one typical banner, so there is always something to grab when the driver moves them)."""
    w = max([full_width(e["line"], k) for e in entries] + [330 * k])
    return int(w + 2 * PAD), int(max(1, len(entries)) * 64 * k + 2 * PAD)


def draw_capsule(wx, wy, slot, e):
    k = cfg["scale"]
    c, l = e["cap"], e["line"]
    col = l["c"]
    title, sub = l["title"], l["sub"]
    ts, ss = TITLE * k, SUB * k
    max_w = max(glyphs.width(title, ts), glyphs.width(sub, ss)) + 10 * k   # exact: the face is monospace
    tw = max_w * c.w
    sc, fade = c.scale, c.fade
    W = (12 + 44) * k + ((10 * k + tw) if tw > 1 else 0)
    w, h = W * sc, 56 * k * sc
    x, y = wx + PAD + 2 * k, wy + PAD + 2 * k + slot * 64 * k + (56 * k - h) / 2.0
    rrect(x - 2 * k * sc, y - 2 * k * sc, w + 4 * k * sc, h + 4 * k * sc, 16 * k * sc, (col[0], col[1], col[2], fade))   # the 2 px border
    rrect(x, y, w, h, 14 * k * sc, (0.047, 0.047, 0.055, 0.94 * fade))
    bs = 44 * k * c.pop * sc
    bx, by = x + 6 * k * sc + (44 * k * sc - bs) / 2.0, y + (h - bs) / 2.0
    rrect(bx, by, bs, bs, 11 * k * sc, (col[0], col[1], col[2], fade))
    tex = icon(l["img"])
    if tex:
        ac.glColor4f(1, 1, 1, fade)
        ac.glQuadTextured(bx + bs * 0.14, by + bs * 0.14, bs * 0.72, bs * 0.72, tex)
    if tw > 1 and sc == 1.0:   # the text is drawn last, over the capsule, and only while the capsule is not shrinking (the text is gone before that: w == 0)
        tx = x + (6 + 44 + 10) * k
        draw_text(tx, y + 4 * k, title, "t", ts, (1, 1, 1, fade), tw - 4 * k)
        draw_text(tx, y + 33 * k, sub, "s", ss, (0.68, 0.71, 0.76, fade), tw - 4 * k)


# ---- the radio call of every new banner: a queue, so two that arrive together are played one after the other ------------------------------------------------------------------
def beep_wav(volume):
    import math, struct, wave
    rate = 22050
    amp = volume / 100.0
    frames = []
    for i in range(int(rate * 0.14)):   # a short burst of noise...
        frames.append(int(((i * 7919) % 2000 - 1000) * 28 * amp * (1 - i / (rate * 0.14))))
    for i in range(int(rate * 0.10)):   # ...and one beep
        frames.append(int(14000 * amp * math.sin(2 * math.pi * 1250 * i / rate)))
    w = wave.open(WAV, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, v))) for v in frames))
    w.close()


def play_sound():
    try:
        import winsound
        if not os.path.isfile(WAV):
            beep_wav(cfg.get("sound") or 100)
        winsound.PlaySound(WAV, winsound.SND_FILENAME | winsound.SND_ASYNC)
        return True
    except Exception as e:
        note("audio", "FAIL " + repr(e))
        return False


def sound_for(lines, now):
    """A line that is new (its id appeared, or its `ev` changed) asks for one radio call. The calls wait their turn (0.4 s apart)."""
    seen = sounds["seen"]
    ids = set()
    for l in lines:
        ids.add(l["id"])
        key = (l["img"], l.get("ev"))
        if seen.get(l["id"]) != key:
            seen[l["id"]] = key
            if cfg["sound"] > 0:
                sounds["pending"].append(l["id"])
    for i in list(seen):
        if i not in ids:
            del seen[i]
    if sounds["pending"] and now >= sounds["next"]:
        sounds["pending"].pop(0)
        sounds["next"] = now + 0.4
        play_sound()


# ---- the demo and the "move" placeholder, in the language picked in the settings -----------------------------------------------------------------------------------------------
DEMO_TEXT = {
    "es": {"flag": ("AMARILLA", "PRECAUCION EN PISTA"), "blue": ("BANDERA AZUL", "DEJA PASAR AL MAS RAPIDO"), "limits": ("LIMITES DE PISTA", "LLEVAS 2/5 - TE QUEDAN 3"), "winner": ("GANADOR", "SOFIA RIOS"),
           "move": ("ARRASTRA AQUI", "COLOCA LAS BANDERAS DONDE QUIERAS")},
    "en": {"flag": ("YELLOW", "CAUTION ON TRACK"), "blue": ("BLUE FLAG", "LET THE FASTER CAR THROUGH"), "limits": ("TRACK LIMITS", "2/5 - 3 LEFT"), "winner": ("WINNER", "SOFIA RIOS"),
           "move": ("DRAG HERE", "PUT THE FLAGS WHERE YOU WANT")},
}


def demo_lines(t):
    tx = DEMO_TEXT["en" if cfg["lang"] == "en" else "es"]

    def ln(i, img, kind, c, key, ev):
        return {"id": i, "img": img, "kind": kind, "c": c, "title": tx[key][0], "sub": tx[key][1], "ev": ev}
    out = []
    if 0 <= t < 14:
        out.append(ln("flag", "flag-yellow", "info", [1.0, 0.757, 0.027], "flag", "a"))   # an information banner: folds to the icon after 5 s
    if 2 <= t < 18:
        out.append(ln("n-blue", "flag-blue", "action", [0.161, 0.475, 1.0], "blue", "b"))   # an instruction: keeps its text while it applies
    if 4 <= t < 10:
        out.append(ln("track-limits", "track-limits", "info", [0.361, 0.42, 0.753], "limits", "cut2"))
    if 6 <= t < 25:
        out.append(ln("winner", "winner", "sticky", [1.0, 0.835, 0.31], "winner", "w"))   # fixed until the session restarts
    return out


def move_line():
    tx = DEMO_TEXT["en" if cfg["lang"] == "en" else "es"]["move"]
    return {"id": "move", "img": "flag-yellow", "kind": "sticky", "c": [0.6, 0.6, 0.6], "title": tx[0], "sub": tx[1], "ev": "move"}


def on_render(delta):
    now = time.time()
    state["last_render"] = now
    refresh_settings(now)
    # The game draws an app's GL in the WINDOW's own coordinates (0,0 = its corner): adding the window's place on the screen counted it twice, so the banners moved twice as fast as the window
    # when dragged and their coloured shapes ended outside the window, where the game cuts them. "Origen: abs" in the settings is there in case a game does it the other way.
    wx, wy = (0.0, 0.0) if cfg["origin"] == "rel" else ac.getPosition(app)
    if cfg["demo"]:
        state["demo_t"] = (state["demo_t"] + delta) % 26.0
    with LOCK:
        live = state["lines"] if now - state["lines_at"] < 1.0 else None
    lines = live if live is not None else (demo_lines(state["demo_t"]) if cfg["demo"] else [])
    if cfg["move"]:   # the driver is placing the window: a banner stays so there is something to drag
        lines = lines + [move_line()]
    sound_for([l for l in lines if l["id"] != "move"], now)
    drawn = stack.update(lines, max(0.0, min(delta, 0.1)))[:POOL]
    size = footprint(drawn, cfg["scale"])
    if size != state["size"]:   # the window follows the banners: only the banners are there to grab, and a big empty window never gets pushed around by the screen's edges
        state["size"] = size
        ac.setSize(app, size[0], size[1])
    for slot, e in enumerate(drawn):
        draw_capsule(wx, wy, slot, e)


def acMain(ac_version):
    global app, stack, glyphs, hlh_settings
    import capsule
    import glyphs
    import hlh_settings
    note("python", sys.version.replace("\n", " "))
    for m in ("socket", "ssl", "http.server", "hashlib", "binascii", "base64", "json", "threading", "configparser", "winsound", "wave"):
        try_import(m)
    cfg.update(hlh_settings.load(INI))
    stack = capsule.Stack()
    app = ac.newApp("HLH Banners")
    for call, args in ((ac.setBackgroundOpacity, (app, 0)), (ac.drawBackground, (app, 0)), (ac.drawBorder, (app, 0)), (ac.setTitle, (app, "")), (ac.setIconPosition, (app, 0, -10000))):
        try:
            call(*args)
        except Exception as e:
            note("window", "%s FAIL %r" % (getattr(call, "__name__", call), e))
    size = footprint([], cfg["scale"])
    state["size"] = size
    ac.setSize(app, size[0], size[1])
    try:
        beep_wav(cfg["sound"] or 100)
    except Exception as e:
        note("wav", "FAIL " + repr(e))
    ac.addRenderCallback(app, on_render)
    t = threading.Thread(target=thread_main)
    t.daemon = True
    t.start()
    return "HLH Banners"


def acShutdown():
    try:
        if server:
            server.shutdown()
            server.server_close()   # frees the port
        note("shutdown", "port released")
    except Exception as e:
        note("shutdown", "FAIL " + repr(e))
