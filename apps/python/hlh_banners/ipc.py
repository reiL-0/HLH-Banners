# What the CSP script (the hub) may send to the app, validated before anything is drawn. Python 3.3 compatible, no AC imports.
# The hub composes the lines already localized: the app draws text it is given, it never builds a URL or a path from it and never opens a file named by it.
import re

KEY = re.compile(r"^[a-z0-9][a-z0-9\-]{0,39}$")   # an icon name (the icon is looked up in the app's own folder) and a line id
KINDS = ("info", "action", "sticky")
MAX_LINES, MAX_TEXT = 8, 80
CTRL = re.compile(r"[\x00-\x1f\x7f]")


def _text(v, name):
    if not isinstance(v, str) or len(v) > MAX_TEXT or CTRL.search(v):
        raise ValueError("%s: a short text without control characters" % name)
    return v


def validate_lines(obj):
    """{"lines": [{id, img, kind, c: [r,g,b], title, sub, ev?}]} -> the list, or ValueError. Nothing but what is listed gets through."""
    if not isinstance(obj, dict) or not isinstance(obj.get("lines"), list) or len(obj["lines"]) > MAX_LINES:
        raise ValueError("lines: a list of at most %d" % MAX_LINES)
    out = []
    for l in obj["lines"]:
        if not isinstance(l, dict):
            raise ValueError("a line is an object")
        for k in ("id", "img"):
            if not isinstance(l.get(k), str) or not KEY.match(l[k]):
                raise ValueError("%s: letters, digits and dashes only" % k)
        if l.get("kind") not in KINDS:
            raise ValueError("kind")
        c = l.get("c")
        if not (isinstance(c, list) and len(c) == 3 and all(isinstance(x, (int, float)) and not isinstance(x, bool) and 0 <= x <= 1 for x in c)):
            raise ValueError("c: three numbers 0..1")
        ev = l.get("ev")
        if ev is not None and not (isinstance(ev, (str, int)) and not isinstance(ev, bool) and len(str(ev)) <= 32):
            raise ValueError("ev")
        out.append({"id": l["id"], "img": l["img"], "kind": l["kind"], "c": [float(x) for x in c], "title": _text(l.get("title", ""), "title"),
                    "sub": _text(l.get("sub", ""), "sub"), "ev": None if ev is None else str(ev)})
    return out
