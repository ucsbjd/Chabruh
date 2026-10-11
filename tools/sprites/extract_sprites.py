"""Turns a Kling motion-control video of the surfer on a flat lilac background into sprite frames.

Usage:
    python tools/sprites/extract_sprites.py clip.mp4 out_dir [--fps 12] [--name cutback]

Steps: cut the video into frames with the ffmpeg that ships inside the imageio_ffmpeg package, key the flat
background out to transparency (colour distance from the background colour sampled at the frame corners,
with a soft edge and a little de-spill), crop every frame to the same box (the union of all the figures, so
the motion inside the frame is kept), scale to a common height, and write PNGs plus a meta.json that holds the
foot/board anchor and frame size. Needs: pillow, numpy, imageio_ffmpeg.
"""
import argparse
import json
import os
import subprocess
import tempfile

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageFilter

KEY_NEAR = 38.0     # colour distance (0-441) below which a pixel is fully background
KEY_FAR = 84.0      # ...and above which it is fully figure; in between is a soft edge
TARGET_HEIGHT = 360  # sprite height in pixels (the surfer is about 0.26 of the screen: ~280 px at 1080p)


def cut_frames(video, folder, fps):
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ffmpeg, "-y", "-i", video, "-vf", f"fps={fps}", os.path.join(folder, "f%04d.png")],
                   check=True, capture_output=True)
    return sorted(f for f in os.listdir(folder) if f.endswith(".png"))


def background_colour(image):
    a = np.asarray(image.convert("RGB")).astype(float)
    corners = np.concatenate([a[:12, :12].reshape(-1, 3), a[:12, -12:].reshape(-1, 3),
                              a[-12:, :12].reshape(-1, 3), a[-12:, -12:].reshape(-1, 3)])
    return np.median(corners, axis=0)


def key(image, bg):
    rgb = np.asarray(image.convert("RGB")).astype(float)
    distance = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    alpha = np.clip((distance - KEY_NEAR) / (KEY_FAR - KEY_NEAR), 0.0, 1.0)
    # De-spill: where the edge is half transparent, pull the colour away from the background colour.
    safe = np.maximum(alpha, 0.25)[..., None]
    rgb = np.clip(bg + (rgb - bg) / safe, 0, 255)
    rgb = np.where(alpha[..., None] < 1.0, rgb, np.asarray(image.convert("RGB")).astype(float))
    out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def remove_wake(image):
    """Drops Kling's own lilac spray speckle (light, low-saturation violet) so the game can draw its own spray."""
    hsv = np.asarray(image.convert("RGB").convert("HSV")).astype(float)
    hue, sat, val = hsv[..., 0] * 360.0 / 255.0, hsv[..., 1] / 255.0, hsv[..., 2] / 255.0
    wake = (hue > 235) & (hue < 295) & (sat < 0.62) & (val > 0.48)
    pixels = np.asarray(image).copy()
    pixels[..., 3] = np.where(wake, 0, pixels[..., 3])
    alpha = Image.fromarray(pixels[..., 3])
    # An opening (shrink then grow) removes the leftover lone specks but keeps the figure.
    alpha = alpha.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
    pixels[..., 3] = np.minimum(pixels[..., 3], np.asarray(alpha))
    return Image.fromarray(pixels, "RGBA")


def figure_box(image):
    mask = np.asarray(image)[..., 3] > 40
    rows = np.where(mask.sum(axis=1) > 3)[0]
    cols = np.where(mask.sum(axis=0) > 3)[0]
    return cols.min(), rows.min(), cols.max(), rows.max()


def anchor_of(image, box):
    """The board's centre: the middle of the lowest tenth of the figure, at its bottom edge."""
    left, top, right, bottom = box
    band = np.asarray(image)[..., 3][int(bottom - (bottom - top) * 0.10):bottom + 1] > 40
    columns = np.where(band.sum(axis=0) > 0)[0]
    return (columns.min() + columns.max()) / 2.0, float(bottom)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video")
    parser.add_argument("out_dir")
    parser.add_argument("--fps", type=float, default=12.0)
    parser.add_argument("--name", default="clip")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        names = cut_frames(args.video, tmp, args.fps)
        frames = [Image.open(os.path.join(tmp, n)).convert("RGB") for n in names]
        bg = background_colour(frames[0])
        keyed = [remove_wake(key(f, bg)) for f in frames]

    # Register every frame on its board: find each figure's anchor, then paste onto one shared canvas so the
    # anchor lands on the same pixel in every frame.
    boxes = [figure_box(k) for k in keyed]
    anchors = [anchor_of(k, b) for k, b in zip(keyed, boxes)]
    pad = 8
    reach_left = max(a[0] - b[0] for a, b in zip(anchors, boxes)) + pad
    reach_right = max(b[2] - a[0] for a, b in zip(anchors, boxes)) + pad
    reach_up = max(a[1] - b[1] for a, b in zip(anchors, boxes)) + pad
    reach_down = pad
    canvas = (int(reach_left + reach_right), int(reach_up + reach_down))
    scale = TARGET_HEIGHT / canvas[1]
    size = (round(canvas[0] * scale), TARGET_HEIGHT)
    anchor_out = (reach_left * scale, reach_up * scale)

    for i, (k, a) in enumerate(zip(keyed, anchors)):
        sheet = Image.new("RGBA", canvas, (0, 0, 0, 0))
        sheet.alpha_composite(k, (int(round(reach_left - a[0])), int(round(reach_up - a[1]))))
        sheet.resize(size, Image.LANCZOS).save(os.path.join(args.out_dir, f"{args.name}_{i:02d}.png"), optimize=True)
    meta = {"name": args.name, "frames": len(keyed), "fps": args.fps, "size": list(size),
            "anchor": [round(float(anchor_out[0]), 1), round(float(anchor_out[1]), 1)], "background": [float(x) for x in bg]}
    with open(os.path.join(args.out_dir, f"{args.name}.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print(f"{len(keyed)} frames, {size[0]}x{size[1]} each, anchor {meta['anchor']}, background {bg.round().tolist()}")


if __name__ == "__main__":
    main()
