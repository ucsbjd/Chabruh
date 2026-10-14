"""Real crops on top, rendered frames below, same side-on camera. Usage: python compare_sheet.py <refs_dir> <name> <render_dir> <picks> <out>"""
import sys

import cv2
import numpy as np
from PIL import Image

sys.argv, args = ["x", "a", "b", "1", "c", "d"], sys.argv[1:]
refs, name, rdir, picks, out = args[0], args[1], args[2], [int(x) for x in args[3].split(",")], args[4]
ns = {}
exec(open("check_frames.py").read().replace("\nmain()\n", "\n"), ns)
top, bot = [], []
for j, i in enumerate(picks):
    r = cv2.cvtColor(cv2.imread(f"{refs}/{name}/f_{i:02d}.png"), cv2.COLOR_BGR2RGB)
    top.append(cv2.resize(r, (240, 240)))
    img = np.asarray(Image.open(f"{rdir}/c_{j:02d}.png").convert("RGBA"), dtype=np.float32) / 255
    bot.append(cv2.resize(ns["preview"](img).astype(np.uint8)[110:410, 60:360], (240, 240)))
sheet = np.concatenate([np.concatenate(top, 1), np.concatenate(bot, 1)], 0)
cv2.imwrite(out, cv2.cvtColor(sheet, cv2.COLOR_RGB2BGR))
