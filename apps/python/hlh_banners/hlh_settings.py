# The driver's settings, shared by the two apps (the banners window and the settings window) through one small file next to the banners app. Pure (no AC imports): tested on a desktop.
# Python 3.3 compatible.
import os
import time

SCALES = (0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0)   # the size of everything the banners draw
VOLUMES = (100, 70, 40, 0)                        # the radio call; 0 = off
LANGS = ("auto", "es", "en")
ORIGINS = ("rel", "abs")   # where the drawing starts: the window's own corner ("rel", what the game seems to expect) or the window's place on the screen ("abs", in case it does not)
DEFAULTS = {"lang": "auto", "scale": 1.25, "sound": 100, "demo": False, "move": False, "test": 0, "origin": "rel"}
# demo: every kind of banner in a loop, for trying things; move: shows a placeholder so the driver can drag the window where the banners should go; test: a counter, +1 = play the call once


def load(path):
    """The settings in the file; anything missing or not allowed is the default (a hand-edited file cannot break the banners)."""
    out = dict(DEFAULTS)
    try:
        import configparser
        c = configparser.ConfigParser()
        c.read(path)
        get = lambda k: c.get("app", k, fallback=None)
        if get("lang") in LANGS:
            out["lang"] = get("lang")
        if get("origin") in ORIGINS:
            out["origin"] = get("origin")
        try:
            if float(get("scale")) in SCALES:
                out["scale"] = float(get("scale"))
        except (TypeError, ValueError):
            pass
        try:
            if int(get("sound")) in VOLUMES:
                out["sound"] = int(get("sound"))
        except (TypeError, ValueError):
            pass
        for k in ("demo", "move"):
            out[k] = get(k) == "on"
        try:
            out["test"] = max(0, min(int(get("test")), 10 ** 9))
        except (TypeError, ValueError):
            pass
    except Exception:
        pass
    return out


def save(path, s):
    """Writes the whole file at once (a temporary file, then a rename: the other app never reads half of it)."""
    import configparser
    c = configparser.ConfigParser()
    c["app"] = {"lang": s["lang"], "scale": str(s["scale"]), "sound": str(s["sound"]), "demo": "on" if s["demo"] else "off", "move": "on" if s["move"] else "off", "test": str(s["test"]), "origin": s["origin"]}
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        c.write(f)
    for attempt in range(4):   # (on Windows the rename fails for a moment if the other app is reading the file right now)
        try:
            os.replace(tmp, path)
            return
        except OSError:
            if attempt == 3:
                raise
            time.sleep(0.05)


def cycle(values, current):
    """The next value of the list after `current` (the first one if it is not there)."""
    return values[(values.index(current) + 1) % len(values)] if current in values else values[0]
