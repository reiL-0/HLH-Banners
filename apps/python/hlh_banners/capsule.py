# The capsule's animation, advanced by the time between frames (dt). Python 3.3 compatible (AC's interpreter), no AC imports: it runs and is tested on a desktop.
# It is the same machine as capStep in the hub (OPR WP static/csp/opr_hub.lua); tests/test_capsule.py checks the same timeline as the hub's check.
#
# open  : the icon pops 0.4 -> 1.05 -> 1 while the text unfolds to the right
# text  : the text stays (an "action" banner while it applies, a "sticky" one until the session restarts)
# fold  : an "info" banner folds its text to the left after TEXT_SEC s
# icon  : only the badge
# shut  : a banner removed while its text is out folds the text FIRST (no text is ever left on its own)
# close : the badge, alone, shrinks to 0.2 and fades; then the capsule is gone

OPEN, SHUT, CLOSE, TEXT_SEC = 0.55, 0.4, 0.32, 5.0


def ease_out(t):
    t = min(max(t, 0.0), 1.0)
    return 1 - (1 - t) ** 3


def ease_in(t):
    t = min(max(t, 0.0), 1.0)
    return t * t


def pop(t):
    return 0.4 + 0.65 * ease_out(t / 0.6) if t < 0.6 else 1.05 - 0.05 * ease_out((t - 0.6) / 0.4)


class Capsule(object):
    def __init__(self):
        self.s, self.t, self.age = "open", 0.0, 0.0
        self.w, self.pop, self.scale, self.fade = 0.0, 0.4, 1.0, 1.0   # w: how much of the text panel is out (0..1)

    def step(self, dt, want, kind):
        """Advance dt seconds. `want`: the banner is still on. Returns False once the capsule is gone."""
        self.t += dt
        if want and self.s in ("shut", "close"):   # it came back while it was leaving
            self.s, self.t, self.scale, self.fade = "open", 0.0, 1.0, 1.0
        s = self.s
        if s == "open":
            p = self.t / OPEN
            self.w, self.pop, self.scale, self.fade = ease_out(p), pop(p), 1.0, 1.0
            if p >= 1:
                self.s, self.t, self.age, self.w, self.pop = "text", 0.0, 0.0, 1.0, 1.0
        elif s == "text":
            self.w, self.pop, self.age = 1.0, 1.0, self.age + dt
            if not want:
                self.s, self.t = "shut", 0.0
            elif kind == "info" and self.age >= TEXT_SEC:
                self.s, self.t = "fold", 0.0
        elif s == "fold":
            self.w = 1 - ease_in(self.t / SHUT)
            if self.t >= SHUT:
                self.s, self.t, self.w = "icon", 0.0, 0.0
        elif s == "icon":
            self.w = 0.0
            if not want:
                self.s, self.t = "close", 0.0
        elif s == "shut":
            self.w = 1 - ease_in(self.t / SHUT)
            if self.t >= SHUT:
                self.s, self.t, self.w = "close", 0.0, 0.0
        elif s == "close":
            q = ease_in(self.t / CLOSE)
            self.w, self.scale, self.fade = 0.0, 1 - 0.8 * q, 1 - q
            if self.t >= CLOSE:
                self.s = "dead"
        return self.s != "dead"


class Stack(object):
    """The capsules on screen. `update(lines, dt)` takes the lines the hub composed ({id, img, ev, kind, ...}) and returns the entries to draw, in order; a line that is gone keeps its entry
    while it closes. Two lines with the same id (two cuts a few seconds apart): the newest wins, so the capsule does not reopen on every frame."""

    def __init__(self):
        self.caps, self.order = {}, []

    def update(self, lines, dt):
        want, ids = {}, []
        for l in lines:
            if l["id"] not in want:
                ids.append(l["id"])
            want[l["id"]] = l
        for i in ids:
            l = want[i]
            e = self.caps.get(i)
            if e is None:
                e = self.caps[i] = {"id": i, "cap": Capsule(), "img": None, "ev": None}
                self.order.append(i)
            if e["img"] != l["img"] or (l.get("ev") is not None and l.get("ev") != e["ev"]):   # another banner in the same place, or a new event of it: it opens again
                fresh = e["img"] is not None
                e["img"], e["ev"] = l["img"], l.get("ev")
                if fresh and e["cap"].s in ("text", "icon", "fold"):
                    e["cap"] = Capsule()
            e["line"] = l
        for i in list(reversed(self.order)):
            e = self.caps[i]
            if not e["cap"].step(dt, i in want, e["line"].get("kind", "info")):
                del self.caps[i]
                self.order.remove(i)
        return [self.caps[i] for i in self.order]
