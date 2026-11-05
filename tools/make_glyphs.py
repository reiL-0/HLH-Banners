"""Renders the glyph textures the app draws its text with (apps/python/hlh_banners/font/<set>/<hex>.png): white on transparent, from the project's own typeface (a monospace one: every
letter advances 0.6 em, so the width of a text is exact and it can be revealed letter by letter). AC apps cannot clip a text label nor put one above their own drawing, so the text is drawn as
textured quads. Two sets, made at twice the size they are drawn at (the app draws them at 20 and 12 px).
Run: python3 tools/make_glyphs.py <path to JetBrainsMono-ExtraBold.ttf>   (needs ImageMagick). The font is JetBrains Mono (SIL Open Font License)."""
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "python", "hlh_banners"))
from glyphs import CHARS, SETS  # noqa: E402  (the set of characters and the sizes are defined once, next to the code that draws them)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "python", "hlh_banners", "font")

if __name__ == "__main__":
    font = sys.argv[1]
    for name, pt in SETS.items():
        os.makedirs(os.path.join(OUT, name), exist_ok=True)
        cw, ch = math.ceil(0.6 * pt), math.ceil(1.32 * pt)
        for c in CHARS:
            path = os.path.join(OUT, name, "%04x.png" % ord(c))
            r = subprocess.run(["magick", "-size", "%dx%d" % (cw, ch), "xc:none", "-font", font, "-pointsize", str(pt), "-fill", "white", "-gravity", "NorthWest", "-annotate", "+0+0", c, path],
                               capture_output=True)
            if r.returncode:
                sys.exit("%r: %s" % (c, r.stderr.decode()))
    print(len(CHARS), "glyphs x", len(SETS), "sets")
