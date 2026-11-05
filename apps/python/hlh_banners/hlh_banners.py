# HLH Banners - DRAFT / PROBE. Nothing in this file has run inside Assetto Corsa yet: the AC calls below (ac.gl*, ac.newTexture, labels) are written from the API as remembered.
# It draws the capsule banners, takes the hub's lines on 127.0.0.1 and reports what works to probe_result.txt, so the first session in the game answers the open questions:
#   - which stdlib modules the game's Python has (socket, http.server, hashlib, json, winsound...)
#   - does the local server run, and does the CSP script reach it (POST /tick)
#   - GL: the rounded capsule, an alpha PNG icon (glQuadTextured)
#   - TEXT: the first session showed that a label (ac.addLabel) is not seen over our own drawing and cannot be clipped, so the text is drawn as textured glyph quads (glyphs.py, font/):
#     the order of drawing, the exact width and the reveal letter by letter are ours. "Etiqueta" keeps one label on screen, only to learn how the layers are ordered.
#   - AUDIO: "Audio" tries winsound with a generated wav (the radio beep)
# The pure parts (capsule.py, ipc.py, guard.py) are tested on a desktop: tests/. Python 3.3 compatible (no f-strings).
import os
import sys
import time
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
for extra in ("stdlib", "stdlib64"):   # AC's interpreter may need these (copy a matching Python 3.3 stdlib here)
    p = os.path.join(HERE, extra)
    if os.path.isdir(p) and p not in sys.path:
        sys.path.insert(0, p)

import ac
import acsys

PORT = 28761
RESULT = os.path.join(HERE, "probe_result.txt")
INI = os.path.join(HERE, "hlh_banners.ini")
LOCK = threading.Lock()
app = None
server = None
notes = []
state = {"lines": [], "lines_at": 0.0, "last_render": 0.0, "lang": "auto", "demo": False, "demo_t": 0.0, "label": False}
stack = None
glyphs = None
labels, textures, glyph_tex = [], {}, {}
buttons = {}
POOL = 4   # capsules drawn at once
TITLE, SUB = 20, 12   # the sizes the text is drawn at (px)
STEP = 64  # px between capsules


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


# ---- the language the driver picks here (the hub asks the app before it asks the website) -------------------------------------------------------------------------------------
def load_lang():
    try:
        import configparser
        c = configparser.ConfigParser()
        c.read(INI)
        v = c.get("app", "lang")
        if v in ("auto", "es", "en"):
            state["lang"] = v
    except Exception:
        pass


def save_lang():
    try:
        import configparser
        c = configparser.ConfigParser()
        c["app"] = {"lang": state["lang"]}
        with open(INI, "w") as f:
            c.write(f)
    except Exception as e:
        note("save lang", "FAIL " + repr(e))


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
                    except ValueError as e:   # (a ValueError is also what a bad JSON raises: the answer never echoes the body)
                        return self.reply(400, {"error": "lines"})
                    with LOCK:
                        state["lines"], state["lines_at"] = lines, time.time()
                age = int((time.time() - state["last_render"]) * 1000) if state["last_render"] else -1
                return self.reply(200, {"render_age_ms": age, "lang": state["lang"], "v": 1})
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


# ---- drawing: GL only (no clip, no text measure in AC apps) -----------------------------------------------------------------------------------------------------------------
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
            note("glyph %04x" % code, "FAIL " + repr(e))
    return glyph_tex[key]


def draw_text(x, y, text, set_name, size, rgba, reveal):
    """The text as quads, only the letters that fit completely inside `reveal` px (so the panel opens letter by letter and nothing is ever outside it)."""
    gw, gh = glyphs.quad_size(set_name, size)
    ac.glColor4f(*rgba)
    for dx, code in glyphs.layout(text, size, reveal):
        tex = glyph(set_name, code)
        if tex:
            ac.glQuadTextured(x + dx, y, gw, gh, tex)


def draw_capsule(wx, wy, slot, e):
    c, l = e["cap"], e["line"]
    col = l["c"]
    title, sub = l["title"], l["sub"]
    max_w = max(glyphs.width(title, TITLE), glyphs.width(sub, SUB)) + 10   # exact: the face is monospace
    tw = max_w * c.w
    sc, fade = c.scale, c.fade
    W = 12 + 44 + (10 + tw if tw > 1 else 0)
    w, h = W * sc, 56 * sc
    x, y = wx + 8, wy + 8 + slot * STEP + (56 - h) / 2.0
    rrect(x - 2 * sc, y - 2 * sc, w + 4 * sc, h + 4 * sc, 16 * sc, (col[0], col[1], col[2], fade))   # the 2 px border
    rrect(x, y, w, h, 14 * sc, (0.047, 0.047, 0.055, 0.94 * fade))
    bs = 44 * c.pop * sc
    bx, by = x + 6 * sc + (44 * sc - bs) / 2.0, y + (h - bs) / 2.0
    rrect(bx, by, bs, bs, 11 * sc, (col[0], col[1], col[2], fade))
    tex = icon(l["img"])
    if tex:
        ac.glColor4f(1, 1, 1, fade)
        ac.glQuadTextured(bx + bs * 0.14, by + bs * 0.14, bs * 0.72, bs * 0.72, tex)
    if tw > 1 and sc == 1.0:   # the text is drawn last, over the capsule, and only while the capsule is not shrinking (the text is gone before that: w == 0)
        tx = x + 6 + 44 + 10
        draw_text(tx, y + 4, title, "t", TITLE, (1, 1, 1, fade), tw - 4)
        draw_text(tx, y + 33, sub, "s", SUB, (0.68, 0.71, 0.76, fade), tw - 4)


def on_render(delta):
    global stack
    now = time.time()
    state["last_render"] = now
    wx, wy = ac.getPosition(app)
    if state["label"]:   # the layer experiment: a label right where the first capsule's title goes
        ac.setPosition(labels[0], 8 + 6 + 44 + 10, 8 + 4)
        ac.setText(labels[0], "ETIQUETA")
        ac.setFontColor(labels[0], 1, 1, 1, 1)
    else:
        ac.setText(labels[0], "")
    if state["demo"]:
        state["demo_t"] = (state["demo_t"] + delta) % 26.0
    with LOCK:
        live = state["lines"] if now - state["lines_at"] < 1.0 else None
    lines = live if live is not None else (demo_lines(state["demo_t"]) if state["demo"] else [])
    drawn = stack.update(lines, max(0.0, min(delta, 0.1)))
    for slot, e in enumerate(drawn[:POOL]):
        draw_capsule(wx, wy, slot, e)


# ---- the demo: every kind of banner in one timeline ----------------------------------------------------------------------------------------------------------------------------
def demo_lines(t):
    def ln(i, img, kind, c, title, sub, ev):
        return {"id": i, "img": img, "kind": kind, "c": c, "title": title, "sub": sub, "ev": ev}
    out = []
    if 0 <= t < 14:
        out.append(ln("flag", "flag-yellow", "info", [1.0, 0.757, 0.027], "AMARILLA", "PRECAUCION EN PISTA", "a"))   # an information banner: folds to the icon after 5 s
    if 2 <= t < 18:
        out.append(ln("n-blue", "flag-blue", "action", [0.161, 0.475, 1.0], "BANDERA AZUL", "DEJA PASAR AL MAS RAPIDO", "b"))   # an instruction: keeps its text while it applies
    if 4 <= t < 10:
        out.append(ln("track-limits", "track-limits", "info", [0.361, 0.42, 0.753], "LIMITES DE PISTA", "LLEVAS 2/5 - TE QUEDAN 3", "cut2"))
    if 6 <= t < 25:
        out.append(ln("winner", "winner", "sticky", [1.0, 0.835, 0.31], "GANADOR", "SOFIA RIOS", "w"))   # fixed until the session restarts
    return out


# ---- the buttons (probe window) -------------------------------------------------------------------------------------------------------------------------------------------------
def beep_wav():
    import math, struct, wave
    path = os.path.join(HERE, "hlh_beep.wav")
    rate = 22050
    frames = []
    for i in range(int(rate * 0.14)):   # a short burst of noise...
        frames.append(int(((i * 7919) % 2000 - 1000) * 24 * (1 - i / (rate * 0.14))))
    for i in range(int(rate * 0.10)):   # ...and one beep
        frames.append(int(11000 * math.sin(2 * math.pi * 1250 * i / rate)))
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, v))) for v in frames))
    w.close()
    return path


def on_audio(*args):
    try:
        import winsound
        winsound.PlaySound(beep_wav(), winsound.SND_FILENAME | winsound.SND_ASYNC)
        note("audio", "winsound.PlaySound called: did you hear a short burst and a beep?")
    except Exception as e:
        note("audio", "FAIL " + repr(e))


def on_demo(*args):
    state["demo"] = not state["demo"]
    state["demo_t"] = 0.0
    ac.setText(buttons["demo"], "Demo: " + ("on" if state["demo"] else "off"))


def on_label(*args):
    state["label"] = not state["label"]
    ac.setText(buttons["mask"], "Etiqueta: " + ("on" if state["label"] else "off"))
    note("label", "now %s: with the demo on, is the word ETIQUETA seen over the capsule (on top of its dark background) or hidden under it?" % state["label"])


def on_lang(*args):
    state["lang"] = {"auto": "es", "es": "en", "en": "auto"}[state["lang"]]
    ac.setText(buttons["lang"], "Idioma: " + state["lang"])
    save_lang()


def acMain(ac_version):
    global app, stack
    import capsule
    global glyphs
    import glyphs
    note("python", sys.version.replace("\n", " "))
    for m in ("socket", "ssl", "http.server", "hashlib", "binascii", "base64", "json", "threading", "configparser", "winsound", "wave"):
        try_import(m)
    load_lang()
    stack = capsule.Stack()
    app = ac.newApp("HLH Banners probe")
    ac.setSize(app, 520, 330)
    ac.setBackgroundOpacity(app, 0.35)
    lab = ac.addLabel(app, "")   # one label, only for the layer experiment
    ac.setFontSize(lab, 18)
    labels.append(lab)
    for n, (key, text, fn, x) in enumerate((("demo", "Demo: off", on_demo, 8), ("audio", "Audio", on_audio, 138), ("mask", "Etiqueta: off", on_label, 238), ("lang", "Idioma: " + state["lang"], on_lang, 378))):
        b = ac.addButton(app, text)
        ac.setPosition(b, x, 290)
        ac.setSize(b, 120 if key != "audio" else 90, 28)
        ac.addOnClickedListener(b, fn)
        buttons[key] = b
    ac.addRenderCallback(app, on_render)
    t = threading.Thread(target=thread_main)
    t.daemon = True
    t.start()
    return "HLH Banners probe"


def acShutdown():
    try:
        if server:
            server.shutdown()
            server.server_close()   # frees the port
        note("shutdown", "port released")
    except Exception as e:
        note("shutdown", "FAIL " + repr(e))
