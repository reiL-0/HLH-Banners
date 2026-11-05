"""Renders the glyph textures the app draws its text with (apps/*/hlh_banners/font/<set>/<hex>.png): white on transparent, from the project's own typeface (a monospace one: every
letter advances 0.6 em, so the width of a text is exact and it can be revealed letter by letter). AC apps cannot clip a text label nor put one above their own drawing, so the text is drawn as
textured quads. Two sets, made at twice the size they are drawn at (the app draws them at 20 and 12 px).
Run: python3 tools/make_glyphs.py <path to JetBrainsMono-ExtraBold.ttf>   (needs ImageMagick). The font is JetBrains Mono (SIL Open Font License)."""
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "python", "hlh_banners"))
from glyphs import CHARS, SETS  # noqa: E402  (the set of characters and the sizes are defined once, next to the code that draws them)
OUTS = [os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "python", "hlh_banners", "font"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "lua", "hlh_banners", "font")]
ASCENT = 1.02   # JetBrains Mono: the baseline is 1.02 em below the top of the line (ascender 1020, descender 300 of 1000): every letter is drawn on the SAME baseline, so caps, accents, lowercase and punctuation line up

if __name__ == "__main__":
    font = sys.argv[1]
    for name, pt in SETS.items():
        cw, ch = math.ceil(0.6 * pt), math.ceil(1.32 * pt)
        base = round(ASCENT * pt)
        for c in CHARS:
            for out in OUTS:
                os.makedirs(os.path.join(out, name), exist_ok=True)
            path = os.path.join(OUTS[0], name, "%04x.png" % ord(c))
            # no -gravity: with a pen position (+x+y) the text is drawn with its LEFT BASELINE there; with -gravity NorthWest the ink of each letter was put against the top of the picture
            r = subprocess.run(["magick", "-size", "%dx%d" % (cw, ch), "xc:none", "-font", font, "-pointsize", str(pt), "-fill", "white", "-annotate", "+0+%d" % base, c, path],
                               capture_output=True)
            if r.returncode:
                sys.exit("%r: %s" % (c, r.stderr.decode()))
            for out in OUTS[1:]:
                shutil.copyfile(path, os.path.join(out, name, "%04x.png" % ord(c)))
    # the atlases: ONE picture per set with every letter on a grid (16 columns, 1 px of transparent gutter around each cell, letters in code order). The game seems to limit how many different
    # pictures a window may draw per frame (measured: text from three or four banners at once did not show), so the app draws all its text from these and picks the letter with texture coordinates.
    codes = sorted(ord(c) for c in CHARS)
    for name, pt in SETS.items():
        cw, ch = math.ceil(0.6 * pt), math.ceil(1.32 * pt)
        files = [os.path.join(OUTS[0], name, "%04x.png" % c) for c in codes]
        for out in OUTS:
            r = subprocess.run(["magick", "montage"] + files + ["-background", "none", "-geometry", "%dx%d+1+1" % (cw, ch), "-tile", "16x", os.path.join(out, "atlas-%s.png" % name)], capture_output=True)
            if r.returncode:
                sys.exit("atlas %s: %s" % (name, r.stderr.decode()))
    print(len(CHARS), "glyphs x", len(SETS), "sets, and the atlases")
