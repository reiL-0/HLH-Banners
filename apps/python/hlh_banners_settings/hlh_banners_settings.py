# HLH Banners settings: a small window with buttons, to be used once and closed. It only writes the shared settings file next to the banners app (hlh_banners/hlh_banners.ini); the banners
# window reads it within half a second. The banners window itself has no buttons: what the driver drags is the banners. Python 3.3 compatible.
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DISPLAY = os.path.join(os.path.dirname(HERE), "hlh_banners")   # the banners app's folder, installed beside this one
if DISPLAY not in sys.path:
    sys.path.insert(0, DISPLAY)

import ac
import hlh_settings

INI = os.path.join(DISPLAY, "hlh_banners.ini")
app = None
buttons = {}
state = dict(hlh_settings.DEFAULTS)


def text_of(key):
    s = state
    return {"demo": "Demo: " + ("on" if s["demo"] else "off"),
            "move": "Mover banderas: " + ("on" if s["move"] else "off"),
            "audio": "Probar audio",
            "lang": "Idioma: " + s["lang"],
            "scale": "Tamano: %d%%" % round(s["scale"] * 100),
            "sound": "Sonido: " + ("off" if s["sound"] == 0 else "%d%%" % s["sound"])}[key]


def push():
    try:
        hlh_settings.save(INI, state)
    except Exception as e:
        ac.log("HLH settings: could not save: " + repr(e))
    for k in buttons:
        ac.setText(buttons[k], text_of(k))


def change(edit):
    """One button press: re-read the file first (so a setting changed elsewhere is not overwritten with this window's old copy), change one thing, write it back."""
    state.update(hlh_settings.load(INI))
    edit()
    push()


def on_demo(*a):
    change(lambda: state.update(demo=not state["demo"]))


def on_move(*a):
    change(lambda: state.update(move=not state["move"]))


def on_audio(*a):
    change(lambda: state.update(test=state["test"] + 1))   # the banners window plays the call when it sees the counter change


def on_lang(*a):
    change(lambda: state.update(lang=hlh_settings.cycle(hlh_settings.LANGS, state["lang"])))


def on_scale(*a):
    change(lambda: state.update(scale=hlh_settings.cycle(hlh_settings.SCALES, state["scale"])))


def on_sound(*a):
    change(lambda: state.update(sound=hlh_settings.cycle(hlh_settings.VOLUMES, state["sound"])))


def acMain(ac_version):
    global app
    state.update(hlh_settings.load(INI))
    app = ac.newApp("HLH Banners settings")
    ac.setSize(app, 410, 130)
    for i, (key, fn) in enumerate((("move", on_move), ("demo", on_demo), ("audio", on_audio), ("lang", on_lang), ("scale", on_scale), ("sound", on_sound))):
        b = ac.addButton(app, text_of(key))
        ac.setPosition(b, 10 + (i % 2) * 195, 36 + (i // 2) * 30)
        ac.setSize(b, 185, 26)
        ac.addOnClickedListener(b, fn)
        buttons[key] = b
    return "HLH Banners settings"
