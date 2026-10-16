"""Contact sheets for judging the riding against the footage (docs/balance.md).

A capture made with snaps (tools/capture.ps1 -Snaps ... -Carve 3) also writes <out>-track.json with where the surfer is on
screen and the rider's state in each snap. This crops every snap around him and labels it with that state, and with
--ref puts the matching footage crops above chosen moments.

Usage:
  python ride_sheet.py <capture base, without .png> <out.jpg> [--cols 8]
  python ride_sheet.py <capture base> <out.jpg> --ref <crop dir> "label:ref_frame:game_frame" ...
The crop dir is one written by extract_move.py (f_00.png ...); storyboardimages/jbay_refs/ride_cycle is the J-Bay ride
from 0 to 4.1 s at 10 frames a second (bottom turn, climb, top turn, down again).
"""
import argparse
import json

from PIL import Image, ImageDraw

TILE = 300


def crop_surfer(base, frame, info, size):
    im = Image.open(f"{base}-{frame}.png").convert("RGB")
    half = info["tall"] * 1.1
    cx, cy = info["x"], info["y"] - info["tall"] * 0.45
    return im.crop((int(cx - half), int(cy - half), int(cx + half), int(cy + half))).resize((size, size), Image.LANCZOS)


def label(tile, info, frame):
    d = ImageDraw.Draw(tile)
    d.text((4, 3), f"{frame / 60:.2f}s {info['move']}", fill=(255, 255, 0))
    d.text((4, 15), f"heading {info['theta']:.0f} turn {info['omega']:.1f} lean {info['carve']:.0f}", fill=(255, 255, 0))
    d.text((4, 27), f"load {info['load']:.1f}g crouch {info['crouch']:.2f} u {info['u']:.2f}", fill=(255, 255, 0))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("out")
    parser.add_argument("pairs", nargs="*")
    parser.add_argument("--cols", type=int, default=8)
    parser.add_argument("--ref")
    args = parser.parse_intermixed_args()
    track = {t["frame"]: t for t in json.load(open(args.base + "-track.json"))}
    if args.ref:
        pairs = [p.rsplit(":", 2) for p in args.pairs]
        sheet = Image.new("RGB", (TILE * len(pairs), TILE * 2 + 22), (20, 20, 20))
        draw = ImageDraw.Draw(sheet)
        for k, (text, ref_frame, game_frame) in enumerate(pairs):
            ref = Image.open(f"{args.ref}/f_{int(ref_frame):02d}.png").convert("RGB").resize((TILE, TILE), Image.LANCZOS)
            game = crop_surfer(args.base, int(game_frame), track[int(game_frame)], TILE)
            label(game, track[int(game_frame)], int(game_frame))
            sheet.paste(ref, (k * TILE, 22))
            sheet.paste(game, (k * TILE, 22 + TILE))
            draw.text((k * TILE + 6, 5), text, fill=(255, 255, 0))
    else:
        frames = sorted(track)
        rows = (len(frames) + args.cols - 1) // args.cols
        sheet = Image.new("RGB", (TILE * args.cols, TILE * rows))
        for k, frame in enumerate(frames):
            tile = crop_surfer(args.base, frame, track[frame], TILE)
            label(tile, track[frame], frame)
            sheet.paste(tile, ((k % args.cols) * TILE, (k // args.cols) * TILE))
    sheet.save(args.out, quality=88)
    print(sheet.size)


if __name__ == "__main__":
    main()
