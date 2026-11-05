# The AC-facing file run against a stand-in for `ac` and `acsys` (the game itself is not here): the local server answers the hub's heartbeat with the lines, refuses what a web page could send,
# and the drawing walks the whole demo (every kind of banner opening, folding and closing) without an error. What the real calls DO is for the first session in the game.
import http.client
import json
import os
import sys
import tempfile
import time
from unittest import mock

HERE = os.path.join(os.path.dirname(__file__), "..", "apps", "python", "hlh_banners")
sys.path.insert(0, HERE)

fake_ac = mock.MagicMock()
fake_ac.getPosition.return_value = (100.0, 100.0)
counter = iter(range(1, 10000))
fake_ac.addLabel.side_effect = lambda *a: next(counter)
fake_ac.addButton.side_effect = lambda *a: next(counter)
fake_ac.newApp.return_value = 1
fake_ac.newTexture.return_value = 5
sys.modules["ac"] = fake_ac
sys.modules["acsys"] = mock.MagicMock()
import hlh_banners as app  # noqa: E402

app.RESULT = os.path.join(tempfile.mkdtemp(), "probe_result.txt")
app.INI = os.path.join(tempfile.mkdtemp(), "hlh_banners.ini")


def post(path, body=b"", headers=None, host="127.0.0.1:28761"):
    c = http.client.HTTPConnection("127.0.0.1", 28761, timeout=5)
    h = {"Host": host, "X-HLH-Init": "1"}
    h.update(headers or {})
    c.request("POST", path, body=body, headers=h)
    r = c.getresponse()
    out = (r.status, json.loads(r.read().decode()))
    c.close()
    return out


def test_the_app_end_to_end_against_a_stand_in():
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
    assert app.state["lines"][0]["id"] == "flag", "and it changes nothing"
    assert post("/tick", json.dumps({"v": 2, "lines": []}).encode())[0] == 409 and app.state["lines"][0]["id"] == "flag", "another version of the contract: refused, nothing changes"
    assert post("/tick", host="evil.com")[0] == 403 and post("/tick", headers={"Origin": "https://evil.com"})[0] == 403, "what a web page could send is refused"
    c = http.client.HTTPConnection("127.0.0.1", 28761, timeout=5)
    c.request("POST", "/tick", headers={"Host": "127.0.0.1:28761"})   # (no custom header: a browser cannot add it without a preflight)
    assert c.getresponse().status == 403
    r = post("/echo", b"aGVsbG8=")
    assert r[0] == 200 and r[1]["sha256"].startswith("2cf24dba"), "the base64 round trip"
    # the drawing: the live lines first, then the demo timeline end to end
    app.on_render(0.016)
    assert app.state["last_render"] > 0 and post("/tick")[1]["render_age_ms"] >= 0, "it reports that it has drawn"
    app.state["lines_at"] = 0.0
    app.on_demo()
    seen = set()
    for _ in range(int(30 / 0.05)):
        app.on_render(0.05)
        seen.update(e["cap"].s for e in app.stack.caps.values())
    assert {"open", "text", "fold", "icon", "shut", "close"} <= seen, "the demo shows every phase: " + str(sorted(seen))
    assert fake_ac.glBegin.called and fake_ac.glQuadTextured.called, "capsules and icons are drawn"
    letters = [c.args[0] for c in fake_ac.newTexture.call_args_list if os.sep + "font" + os.sep in c.args[0]]
    assert any(p.endswith("0041.png") for p in letters) and len(set(letters)) > 10, "the text is drawn as glyph quads: " + str(len(set(letters)))
    import socket, threading
    slow = socket.create_connection(("127.0.0.1", 28761), timeout=5)
    slow.sendall(b"POST /tick HTTP/1.1\r\nHost: 127.0.0.1:28761\r\n")   # a client that never finishes its request
    assert post("/tick")[0] == 200, "a slow client does not hold up the hub's heartbeat"
    app.on_lang(); app.on_lang(); app.on_lang()
    assert app.state["lang"] == "auto" and "lang" in open(app.INI).read(), "the language cycles and is kept"
    done = threading.Thread(target=app.acShutdown)
    done.start(); done.join(5)
    assert not done.is_alive(), "the game's shutdown does not wait for a stuck connection"
    slow.close()
    assert "port released" in open(app.RESULT).read()


if __name__ == "__main__":
    test_the_app_end_to_end_against_a_stand_in()
    print("ok")
