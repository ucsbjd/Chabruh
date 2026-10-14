"""Draws the two flat decals the character uses (white on black), so the Blender script can map them on:
  tattoo.png: a shaka hand over a curling wave, for the back
  palm.png:   a palm tree, for the shorts
Usage: python make_decals.py <out_dir>
"""
import math
import sys

from PIL import Image, ImageDraw

S = 512


def tattoo(path):
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    # Palm and the three folded fingers.
    d.rounded_rectangle((200, 210, 330, 340), 30, fill=255)
    for i, x in enumerate((205, 243, 281)):
        d.rounded_rectangle((x, 160 - (i == 1) * 6, x + 40, 240), 18, fill=255)
    # Thumb out to the left, little finger out to the right: the shaka.
    d.polygon([(205, 300), (140, 255), (118, 222), (146, 208), (215, 255)], fill=255)
    d.polygon([(325, 230), (385, 150), (412, 160), (402, 192), (350, 275)], fill=255)
    d.ellipse((115, 214, 150, 244), fill=255)
    d.ellipse((380, 144, 416, 172), fill=255)
    # The wave curling under it: a few thick arcs and spray dots.
    for r, a0, a1 in ((120, 160, 330), (86, 175, 310), (52, 190, 290)):
        d.arc((256 - r, 400 - r, 256 + r, 400 + r), a0, a1, fill=255, width=16)
    for x, y, rr in ((120, 330, 9), (150, 300, 6), (400, 330, 9), (372, 292, 6), (330, 360, 7)):
        d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)
    im.save(path)


def palm(path):
    im = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(im)
    d.polygon([(250, 500), (282, 500), (292, 300), (266, 250), (258, 300)], fill=255)  # trunk
    top = (272, 236)
    for ang, ln in ((-160, 150), (-125, 160), (-90, 120), (-55, 160), (-20, 150), (10, 110), (-190, 110)):
        a = math.radians(ang)
        tip = (top[0] + math.cos(a) * ln, top[1] + math.sin(a) * ln * 0.8 + ln * 0.25)
        mid = (top[0] + math.cos(a) * ln * 0.5, top[1] + math.sin(a) * ln * 0.5 - 22)
        d.polygon([top, mid, tip, (mid[0], mid[1] + 36)], fill=255)
    d.polygon([(160, 500), (400, 500), (340, 470), (210, 470)], fill=255)  # a little island
    im.save(path)


palm(f"{sys.argv[1]}/palm.png")
print("decals written")
