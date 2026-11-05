# The banners app run against a stand-in for `ac`, `acsys` and `winsound` (the game is not here): the local server answers the hub's heartbeat with the lines, refuses what a web page could send,
# the window is only as big as the banners on screen, every new banner asks for one radio call, the language of the settings file reaches the text, and the drawing walks the whole demo.
# What the real calls DO is for the game.
import http.client
import json
import os
import socket
import sys
import tempfile
import threading
import time
from unittest import mock

HERE = os.path.join(os.path.dirname(__file__), "..", "apps", "python", "hlh_banners")
sys.path.insert(0, HERE)

fake_ac = mock.MagicMock()
fake_ac.getPosition.return_value = (100.0, 100.0)
fake_ac.newApp.return_value = 1
fake_ac.newTexture.return_value = 5
played = []
fake_winsound = mock.MagicMock()
fake_winsound.SND_FILENAME, fake_winsound.SND_ASYNC = 1, 2
fake_winsound.PlaySound.side_effect = lambda *a: played.append(time.time())
sys.modules["ac"] = fake_ac
sys.modules["acsys"] = mock.MagicMock()
sys.modules["winsound"] = fake_winsound
import hlh_banners as app  # noqa: E402
import hlh_settings as hs  # noqa: E402

TMP = tempfile.mkdtemp()
app.RESULT, app.INI, app.WAV = os.path.join(TMP, "probe_result.txt"), os.path.join(TMP, "hlh_banners.ini"), os.path.join(TMP, "hlh_beep.wav")


def post(path, body=b"", headers=None, host="127.0.0.1:28761"):
    c = http.client.HTTPConnection("127.0.0.1", 28761, timeout=5)
    h = {"Host": host, "X-HLH-Init": "1"}
    h.update(headers or {})
    c.request("POST", path, body=body, headers=h)
    r = c.getresponse()
    out = (r.status, json.loads(r.read().decode()))
    c.close()
    return out


def settings(**change):
    s = dict(hs.DEFAULTS)
    s.update(change)
    hs.save(app.INI, s)
    settings.n += 1
    os.utime(app.INI, (time.time() + settings.n, time.time() + settings.n))   # (a different mtime each time, as a later write has)
    app.state["ini_check"] = 0.0


settings.n = 0


def frames(seconds, dt=0.05):
    for _ in range(int(seconds / dt)):
        app.on_render(dt)


def test_the_banners_app_end_to_end_against_a_stand_in():
    app.acMain(0)
    for _ in range(50):   # the server thread starts in the background
        try:
            post("/tick")
            break
        except OSError:
            time.sleep(0.05)
    assert post("/tick") == (200, {"render_age_ms": -1, "lang": "auto", "v": 1}), "a heartbeat is answered with the language and how long ago it drew"
    good = {"lines": [{"id": "flag", "img": "flag-yellow", "kind": "info", "c": [1, 0.757, 0.027], "title": "AMARILLA", "sub": "PRECAUCION", "ev": 1}]}
    assert post("/tick", json.dumps(good).encode())[0] == 200 and app.state["lines"][0]["id"] == "flag", "the hub's lines are taken"
    assert post("/tick", b"not json")[0] == 400 and post("/tick", json.dumps({"lines": [{"id": "../x"}]}).encode())[0] == 400, "garbage is refused"
    assert post("/tick", json.dumps({"v": 2, "lines": []}).encode())[0] == 409 and app.state["lines"][0]["id"] == "flag", "another version of the contract: refused, nothing changes"
    assert post("/tick", host="evil.com")[0] == 403 and post("/tick", headers={"Origin": "https://evil.com"})[0] == 403, "what a web page could send is refused"
    c = http.client.HTTPConnection("127.0.0.1", 28761, timeout=5)
    c.request("POST", "/tick", headers={"Host": "127.0.0.1:28761"})   # (no custom header: a browser cannot add it without a preflight)
    assert c.getresponse().status == 403
    r = post("/echo", b"aGVsbG8=")
    assert r[0] == 200 and r[1]["sha256"].startswith("2cf24dba"), "the base64 round trip"

    # the window is only as big as the banners: one live banner, then none
    settings(scale=1.0, sound=100)
    app.on_render(0.016)
    assert app.cfg["scale"] == 1.0
    one = app.state["size"]
    assert one == app.footprint([{"line": good["lines"][0]}] * 1, 1.0) or one[1] == int(1 * 64 + 12), one
    assert app.state["last_render"] > 0 and post("/tick")[1]["render_age_ms"] >= 0, "it reports that it has drawn"
    assert len(played) == 1, "the live banner asked for one radio call: %d" % len(played)
    # where it draws: the game draws an app's GL in the window's own coordinates, so with the window far from the screen's corner everything must still fall inside the window's rectangle
    import ipc
    fake_ac.getPosition.return_value = (500.0, 300.0)
    app.state["lines"] = ipc.validate_lines(good)
    for origin, lo in (("rel", (0.0, 0.0)), ("abs", (500.0, 300.0))):
        settings(scale=1.0, sound=0, origin=origin)
        app.state["lines_at"] = time.time()
        fake_ac.glVertex2f.reset_mock(); fake_ac.glQuadTextured.reset_mock()
        frames(1.0)
        W, H = app.state["size"]
        xs = [c.args[0] for c in fake_ac.glVertex2f.call_args_list] + [q.args[0] for q in fake_ac.glQuadTextured.call_args_list]
        ys = [c.args[1] for c in fake_ac.glVertex2f.call_args_list] + [q.args[1] for q in fake_ac.glQuadTextured.call_args_list]
        assert xs and min(xs) >= lo[0] and min(ys) >= lo[1], (origin, min(xs), min(ys))
        if origin == "rel":
            ex = [q.args[0] + q.args[2] for q in fake_ac.glQuadTextured.call_args_list]
            ey = [q.args[1] + q.args[3] for q in fake_ac.glQuadTextured.call_args_list]
            assert max(xs + ex) <= W and max(ys + ey) <= H, "everything drawn is inside the window's own rectangle %dx%d: %r %r" % (W, H, max(xs + ex), max(ys + ey))
        else:
            assert max(xs) > 500, "'abs' starts at the window's place on the screen"
    fake_ac.getPosition.return_value = (100.0, 100.0)
    settings(scale=1.0, sound=100, origin="rel")
    app.state["lines_at"] = 0.0   # the hub went quiet
    frames(3)
    assert app.state["size"][1] == 64 + 12 and app.stack.caps == {}, "with nothing on screen: the room of one banner, not a big box: %r" % (app.state["size"],)

    # the demo, in English, at 250 %: four banners over 26 s, each one radio call, the window growing with them, the text drawn as glyphs
    del played[:]
    settings(scale=2.5, sound=100, demo=True, lang="en")
    seen, heights = set(), set()
    for _ in range(int(30 / 0.05)):
        app.on_render(0.05)
        app.state["ini_check"] = 0.0
        seen.update(e["cap"].s for e in app.stack.caps.values())
        heights.add(app.state["size"][1])
    assert app.cfg["lang"] == "en" and app.demo_lines(1)[0]["title"] == "YELLOW" and app.demo_lines(1)[0]["sub"] == "CAUTION ON TRACK", "the demo follows the language of the settings"
    assert {"open", "text", "fold", "icon", "shut", "close"} <= seen, "the demo shows every phase: " + str(sorted(seen))
    assert len(played) >= 4 and all(b - a >= 0.0 for a, b in zip(played, played[1:])), "one radio call per new banner: %d" % len(played)
    assert len(heights) >= 3 and max(heights) > min(heights) * 2, "the window grows and shrinks with the banners: %r" % sorted(heights)
    letters = [c.args[0] for c in fake_ac.newTexture.call_args_list if os.sep + "font" + os.sep in c.args[0]]
    assert any(p.endswith("0041.png") for p in letters) and any(os.sep + "t4" + os.sep in p for p in letters), "the text is drawn as glyph quads, from the sharper set at 250 %"
    settings(scale=2.5, sound=0, demo=True, lang="es")   # sound off: no calls
    n0 = len(played)
    app.state["demo_t"] = 0.0
    frames(10)
    assert len(played) == n0 and app.demo_lines(1)[0]["title"] == "AMARILLA", "no sound when it is off; Spanish again"

    # the "move" placeholder: something to drag, and no sound for it
    settings(scale=1.0, sound=100, demo=False, move=True)
    n0 = len(played)
    frames(2)
    assert "move" in app.stack.caps and len(played) == n0, "the placeholder is there to be dragged and makes no noise"
    settings(scale=1.0, sound=100, move=False)
    frames(3)
    assert "move" not in app.stack.caps
    # "Probar audio" in the settings app: the counter changes
    n0 = len(played)
    settings(scale=1.0, sound=100, test=1)
    frames(0.2)
    assert len(played) == n0 + 1, "the test button plays the call once"

    slow = socket.create_connection(("127.0.0.1", 28761), timeout=5)
    slow.sendall(b"POST /tick HTTP/1.1\r\nHost: 127.0.0.1:28761\r\n")   # a client that never finishes its request
    assert post("/tick")[0] == 200, "a slow client does not hold up the hub's heartbeat"
    done = threading.Thread(target=app.acShutdown)
    done.start(); done.join(5)
    assert not done.is_alive(), "the game's shutdown does not wait for a stuck connection"
    slow.close()
    assert "port released" in open(app.RESULT).read()


if __name__ == "__main__":
    test_the_banners_app_end_to_end_against_a_stand_in()
    print("ok")
