import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "apps", "python", "hlh_banners"))
import guard

P = 28761
OK = {"Host": "127.0.0.1:%d" % P, "X-HLH-Init": "1", "Content-Length": "10"}


def with_(**kw):
    h = dict(OK)
    h.update(kw)
    return h


def test_guard():
    assert guard.check("POST", OK, P) is None
    assert guard.check("OPTIONS", OK, P)[0] == 403
    assert guard.check("GET", OK, P)[0] == 405
    assert guard.check("POST", with_(Host="evil.com:%d" % P), P)[0] == 403       # DNS rebinding
    assert guard.check("POST", with_(Origin="https://evil.com"), P)[0] == 403
    assert guard.check("POST", with_(**{"Sec-Fetch-Site": "cross-site"}), P)[0] == 403
    assert guard.check("POST", with_(**{"Transfer-Encoding": "chunked"}), P)[0] == 400
    h = dict(OK); del h["X-HLH-Init"]
    assert guard.check("POST", h, P)[0] == 403
    assert guard.check("POST", with_(**{"Content-Length": str(guard.MAX_BODY + 1)}), P)[0] == 413
    assert guard.check("POST", with_(**{"Content-Length": "x"}), P)[0] == 411


if __name__ == "__main__":
    test_guard()
    print("ok")
