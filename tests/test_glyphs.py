import os
import sys

HERE = os.path.join(os.path.dirname(__file__), "..", "apps", "python", "hlh_banners")
sys.path.insert(0, HERE)
import glyphs  # noqa: E402


def test_every_glyph_of_the_set_is_on_disk_in_both_sizes():
    for name in glyphs.SETS:
        for code in sorted(glyphs.KNOWN):
            path = os.path.join(HERE, "font", name, "%04x.png" % code)
            assert os.path.isfile(path) and os.path.getsize(path) > 50, "missing glyph " + path + " (run tools/make_glyphs.py)"


def test_the_width_of_a_text_is_exact_and_it_is_revealed_letter_by_letter():
    assert glyphs.width("AMARILLA", 20) == 8 * 0.6 * 20
    full = glyphs.layout("AB C", 20, 1000)
    assert [c for _, c in full] == [ord("A"), ord("B"), ord("C")] and full[2][0] == 3 * 12.0, "spaces advance but draw nothing"
    assert len(glyphs.layout("AMARILLA", 20, 0)) == 0 and len(glyphs.layout("AMARILLA", 20, 12 * 3 + 0.1)) == 3, "only the letters that fit completely"
    last = 0
    for reveal in range(0, 120, 3):   # the panel opening: never fewer letters than a moment before, and none outside the panel
        shown = glyphs.layout("AMARILLA", 20, reveal)
        assert len(shown) >= last and all(x + 12 <= reveal + 1e-9 for x, _ in shown)
        last = len(shown)


def test_a_letter_we_have_no_glyph_for_becomes_a_question_mark_not_an_error():
    assert glyphs.code_of("Ñ") == ord("Ñ") and glyphs.code_of("Ж") == ord("?") and glyphs.code_of("中") == ord("?")
    assert glyphs.layout("Ж", 20, 100) == [(0.0, ord("?"))]


def test_the_quads_keep_the_proportions_of_the_pictures():
    w, h = glyphs.quad_size("t", 20)
    assert (w, h) == (12.0, 26.5), (w, h)   # a 24 x 53 picture drawn at half size
    w, h = glyphs.quad_size("s", 12)
    assert abs(w - 7.5) < 1e-9 and abs(h - 16.0) < 1e-9, (w, h)


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
