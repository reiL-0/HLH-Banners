# Text drawn as textured quads (AC apps cannot clip a label nor put one above their own drawing). The glyphs are a monospace face, so the width of a text is exact and a text can be
# revealed letter by letter. Pure (no AC imports): tested on a desktop. Python 3.3 compatible.
import math

ADV, LINE = 0.6, 1.32   # advance and line height, in em
SETS = {"t": 40, "s": 24}   # glyph set -> the pointsize it was rendered at (tools/make_glyphs.py); the app draws it at half of that
CHARS = [chr(c) for c in range(33, 127) if chr(c) != "\\"] + list("áéíóúüñÁÉÍÓÚÜÑ¿¡·°ºªçÇàèìòùâêîôûäëïöÿÀÈÌÒÙÂÊÎÔÛÄËÏÖ€")
KNOWN = set(ord(c) for c in CHARS)


def code_of(ch):
    """The glyph file of a character: itself when it is in the set, else a '?' (a name in an alphabet we have no glyphs for must not break the line)."""
    return ord(ch) if ord(ch) in KNOWN else 0x3F


def width(text, size):
    return len(text) * ADV * size


def quad_size(set_name, size):
    """Width and height of the quad that draws one glyph of that set at `size` px (the picture is a whole number of pixels, a bit wider than 0.6 em: the advance stays exact)."""
    pt = SETS[set_name]
    return math.ceil(ADV * pt) * size / float(pt), math.ceil(LINE * pt) * size / float(pt)


def layout(text, size, reveal):
    """[(x offset, code)] of the glyphs that fit completely inside `reveal` px, spaces left out (they only advance)."""
    adv = ADV * size
    out = []
    for i, ch in enumerate(text):
        if (i + 1) * adv > reveal:
            break
        if ch != " ":
            out.append((i * adv, code_of(ch)))
    return out
