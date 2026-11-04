# HLH Banners - PROBE. Answers: which stdlib modules the game's Python has, whether a local server runs,
# and whether the 'book' opening can be drawn. Results go to probe_result.txt next to this file.
# Python 3.3 compatible (no f-strings).
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
app = None
server = None
last_render = 0.0
t0 = time.time()
lines = []


def note(key, val):
    lines.append("%s: %s" % (key, val))
    try:
        with open(os.path.join(HERE, "probe_result.txt"), "w") as f:
            f.write("\n".join(lines) + "\n")
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


def serve():
    global server
    import base64, hashlib, json
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import guard

    class H(BaseHTTPRequestHandler):
        timeout = 5

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
            if self.path == "/tick":
                age = int((time.time() - last_render) * 1000) if last_render else -1
                return self.reply(200, {"render_age_ms": age})
            if self.path == "/echo":   # base64 round trip: what the pack download will use
                raw = base64.b64decode(data)
                return self.reply(200, {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
            self.reply(404, {"error": "path"})

        do_POST = do_GET = do_OPTIONS = do_PUT = do_DELETE = handle_any

    server = HTTPServer(("127.0.0.1", PORT), H)
    note("server", "listening on 127.0.0.1:%d" % PORT)
    server.serve_forever()


def thread_main():
    try:
        serve()
    except Exception as e:
        note("server", "FAIL " + repr(e))


def acMain(ac_version):
    global app
    note("python", sys.version.replace("\n", " "))
    for m in ("socket", "ssl", "http.server", "hashlib", "binascii", "base64", "json", "threading"):
        try_import(m)
    app = ac.newApp("HLH Banners probe")
    ac.setSize(app, 360, 80)
    ac.setBackgroundOpacity(app, 0)
    ac.drawBorder(app, 0)
    ac.addRenderCallback(app, on_render)
    t = threading.Thread(target=thread_main)
    t.daemon = True
    t.start()
    return "HLH Banners probe"


def ease(x):   # smoothstep
    return x * x * (3 - 2 * x)


def on_render(delta):
    # the book: two halves open from the middle, hold, close again (4 s loop)
    global last_render
    last_render = time.time()
    ph = ((last_render - t0) % 4.0) / 4.0
    o = ease(ph * 4) if ph < 0.25 else (1.0 if ph < 0.75 else ease((1 - ph) * 4))
    x, y = ac.getPosition(app)
    half = 168 * o
    ac.glColor4f(0.95, 0.78, 0.05, 0.95)
    ac.glBegin(acsys.GL.Quads)
    ac.glVertex2f(x + 168 - half, y + 10)
    ac.glVertex2f(x + 168 + half, y + 10)
    ac.glVertex2f(x + 168 + half, y + 70)
    ac.glVertex2f(x + 168 - half, y + 70)
    ac.glEnd()


def acShutdown():
    try:
        if server:
            server.shutdown()
            server.server_close()   # frees the port
        note("shutdown", "port released")
    except Exception as e:
        note("shutdown", "FAIL " + repr(e))
