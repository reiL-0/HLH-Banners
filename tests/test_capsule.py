import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "apps", "python", "hlh_banners"))
import capsule  # noqa: E402
import ipc  # noqa: E402


def advance(c, secs, want, kind, each=None):
    t = 0.0
    while t < secs - 1e-9:
        assert c.step(0.02, want, kind) or c.s == "dead"
        if each:
            each(c)
        t += 0.02


def test_the_timeline_of_an_information_banner():
    c, top, last = capsule.Capsule(), [0], [0]

    def watch(x):
        top[0] = max(top[0], x.pop)
        assert x.w >= last[0] - 1e-9, "the text only unfolds while opening"
        last[0] = x.w
    advance(c, 0.6, True, "info", watch)
    assert c.s == "text" and c.w == 1 and c.pop == 1 and 1.04 < top[0] <= 1.05 + 1e-9, "opens with a small pop and settles"
    advance(c, 4.2, True, "info"); assert c.s == "text", "keeps its text 5 s"
    advance(c, 1.0, True, "info"); assert c.s in ("fold", "icon")
    advance(c, 0.6, True, "info"); assert c.s == "icon" and c.w == 0
    advance(c, 30, True, "info"); assert c.s == "icon", "an icon for as long as it applies"
    advance(c, 1.0, False, "info"); assert c.s == "dead"


def test_instructions_and_the_winner_keep_their_text():
    for kind in ("action", "sticky"):
        c = capsule.Capsule()
        advance(c, 60, True, kind)
        assert c.s == "text" and c.w == 1, kind


def test_removing_folds_the_text_first_then_the_icon_shrinks():
    c = capsule.Capsule()
    advance(c, 3, True, "action")

    def watch(x):
        assert not (x.scale < 1 and x.w > 0), "the icon never shrinks while text is still out"
        assert not (x.fade < 1 and x.w > 0), "nor fades"
    advance(c, 1.5, False, "action", watch)
    assert c.s == "dead"


def test_a_banner_that_comes_back_while_leaving_opens_again():
    c = capsule.Capsule()
    advance(c, 3, True, "action"); advance(c, 0.2, False, "action"); assert c.s == "shut"
    advance(c, 0.02, True, "action"); assert c.s == "open"


def line(i, img, ev=None, kind="info"):
    return {"id": i, "img": img, "ev": ev, "kind": kind}


def test_two_notices_of_the_same_banner_do_not_reopen_it_on_every_frame():
    st = capsule.Stack()
    for _ in range(50):   # the first cut, then a second one: the newest event wins, once
        st.update([line("track-limits", "track-limits", "cut3"), line("track-limits", "track-limits", "cut4")], 0.02)
    e = st.update([line("track-limits", "track-limits", "cut3"), line("track-limits", "track-limits", "cut4")], 0.02)[0]
    assert e["cap"].s == "text", "it opened once and settled: " + e["cap"].s
    for _ in range(int(7 / 0.02)):
        st.update([line("track-limits", "track-limits", "cut4")], 0.02)
    assert st.caps["track-limits"]["cap"].s in ("fold", "icon"), "and folds after its 5 s"


def test_a_new_event_of_a_folded_banner_opens_it_again_and_a_vanished_line_closes():
    st = capsule.Stack()
    for _ in range(int(7 / 0.02)):
        st.update([line("tl", "track-limits", "cut3")], 0.02)
    assert st.caps["tl"]["cap"].s == "icon"
    st.update([line("tl", "track-limits", "cut4")], 0.02)
    assert st.caps["tl"]["cap"].s == "open", "a new cut: the pop says this is new"
    for _ in range(int(2 / 0.02)):
        st.update([], 0.02)
    assert st.caps == {} and st.order == [], "nothing left once it has closed"


def test_the_winner_stays_as_long_as_the_hub_sends_it():
    st = capsule.Stack()
    for _ in range(int(30 / 0.02)):
        st.update([line("winner", "winner", "7", "sticky")], 0.02)
    assert st.caps["winner"]["cap"].s == "text"


def good():
    return {"lines": [{"id": "flag", "img": "flag-yellow", "kind": "info", "c": [1, 0.757, 0.027], "title": "AMARILLA", "sub": "PRECAUCIÓN EN PISTA", "ev": 12}]}


def bad(**change):
    o = good()
    o["lines"][0].update(change)
    return o


def test_the_lines_the_hub_may_send():
    out = ipc.validate_lines(good())
    assert out[0]["id"] == "flag" and out[0]["ev"] == "12" and out[0]["c"] == [1.0, 0.757, 0.027]
    assert ipc.validate_lines({"lines": []}) == []
    for o in (bad(img="../secret"), bad(img="a/b"), bad(img=""), bad(id="X"), bad(kind="loud"), bad(c=[2, 0, 0]), bad(c=[0, 0]), bad(c=[True, 0, 0]), bad(title="x" * 81),
              bad(title="a\nb"), bad(sub=5), bad(ev=[1]), {"lines": [good()["lines"][0]] * 9}, {"lines": "x"}, [], {"lines": [3]}):
        try:
            ipc.validate_lines(o)
        except ValueError:
            continue
        raise AssertionError("accepted: %r" % (o,))


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
