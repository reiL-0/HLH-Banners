import os
import sys
import tempfile
from unittest import mock

HERE = os.path.join(os.path.dirname(__file__), "..", "apps", "python")
sys.path.insert(0, os.path.join(HERE, "hlh_banners"))
import hlh_settings as hs  # noqa: E402


def test_the_settings_survive_a_round_trip_and_garbage_is_the_default():
    p = os.path.join(tempfile.mkdtemp(), "x.ini")
    assert hs.load(p) == hs.DEFAULTS, "no file: the defaults"
    s = dict(hs.DEFAULTS, lang="en", scale=2.0, sound=40, demo=True, move=True, test=3)
    hs.save(p, s)
    assert hs.load(p) == s and not os.path.exists(p + ".tmp")
    open(p, "w").write("[app]\nlang = klingon\nscale = 99\nsound = loud\ndemo = maybe\ntest = -5\n")
    got = hs.load(p)
    assert got["lang"] == "auto" and got["scale"] == 1.25 and got["sound"] == 100 and got["demo"] is False and got["test"] == 0, got
    open(p, "w").write("not an ini at all \x00\x01")
    assert hs.load(p) == hs.DEFAULTS, "a broken file never breaks the banners"


def test_cycling():
    assert hs.cycle(hs.LANGS, "auto") == "es" and hs.cycle(hs.LANGS, "en") == "auto" and hs.cycle(hs.LANGS, "zz") == "auto"
    seen, v = [], 100
    for _ in range(4):
        v = hs.cycle(hs.VOLUMES, v)
        seen.append(v)
    assert seen == [70, 40, 0, 100]


def test_the_settings_app_writes_what_the_banners_app_reads():
    fake = mock.MagicMock()
    ids = iter(range(1, 100))
    fake.addButton.side_effect = lambda *a: next(ids)
    sys.modules["ac"] = fake
    sys.path.insert(0, os.path.join(HERE, "hlh_banners_settings"))
    import hlh_banners_settings as sa
    sa.INI = os.path.join(tempfile.mkdtemp(), "hlh_banners.ini")
    sa.acMain(0)
    click = {call.args[0]: call.args[1] for call in fake.addOnClickedListener.call_args_list}   # button id -> handler
    by_key = {k: click[b] for k, b in sa.buttons.items()}
    by_key["lang"](); by_key["scale"](); by_key["sound"](); by_key["move"](); by_key["demo"](); by_key["audio"]()
    got = hs.load(sa.INI)
    assert got["lang"] == "es" and got["scale"] == 1.5 and got["sound"] == 70 and got["move"] and got["demo"] and got["test"] == 1, got
    by_key["move"]()
    assert hs.load(sa.INI)["move"] is False
    ext = hs.load(sa.INI)
    ext["lang"], ext["scale"] = "en", 3.0   # changed outside this window (by hand, or by another copy of it)
    hs.save(sa.INI, ext)
    by_key["sound"]()
    got = hs.load(sa.INI)
    assert got["lang"] == "en" and got["scale"] == 3.0 and got["sound"] == 40, "a press changes only its own setting: %r" % got
    # a rename that fails once (the other app is reading the file) is tried again
    real = os.replace
    calls = []
    def flaky(a, b):
        calls.append(1)
        if len(calls) < 3:
            raise PermissionError("in use")
        real(a, b)
    with mock.patch.object(os, "replace", flaky):
        hs.save(sa.INI, dict(hs.DEFAULTS, lang="es"))
    assert len(calls) == 3 and hs.load(sa.INI)["lang"] == "es", "retried, then written"


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
