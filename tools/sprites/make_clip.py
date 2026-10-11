"""Turns a folder of captured frames into the MP4 that Kling's motion control wants as its motion reference.

Usage:
    python tools/sprites/make_clip.py frames_dir clip.mp4 [--fps 12]

The frames (any PNG or JPG, sorted by file name) are cropped of the browser scrollbar strip, scaled to 1280x720
and encoded at 24 fps (each frame repeated to fill), H.264, which is what Kling accepts. Keep the clip 3 to 10
seconds long: Kling's motion control needs at least 3, and a clip with a camera cut or a zoom jump in it
confuses the result, so cut the footage at shot changes first. Needs: pillow, imageio_ffmpeg.
"""
import argparse
import os
import subprocess
import tempfile

import imageio_ffmpeg
from PIL import Image

SCROLLBAR = 14   # pixels of the pane's scrollbar on the right edge of a screenshot


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames_dir")
    parser.add_argument("out")
    parser.add_argument("--fps", type=float, default=12.0, help="how fast the captured frames were taken, per second of the source video")
    args = parser.parse_args()

    names = sorted(n for n in os.listdir(args.frames_dir) if n.lower().endswith((".png", ".jpg", ".jpeg")))
    if len(names) / args.fps < 3.0:
        print(f"warning: {len(names)} frames at {args.fps} fps is {len(names) / args.fps:.1f} s; Kling needs at least 3 s")
    with tempfile.TemporaryDirectory() as tmp:
        for i, name in enumerate(names):
            image = Image.open(os.path.join(args.frames_dir, name)).convert("RGB")
            image = image.crop((0, 0, image.width - SCROLLBAR, int((image.width - SCROLLBAR) * 9 / 16)))
            image.resize((1280, 720), Image.LANCZOS).save(os.path.join(tmp, f"f{i:04d}.png"))
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-framerate", str(args.fps), "-i", os.path.join(tmp, "f%04d.png"),
                        "-vf", "fps=24,format=yuv420p", "-c:v", "libx264", "-crf", "16", "-movflags", "+faststart", args.out],
                       check=True, capture_output=True)
    print(f"{len(names)} frames -> {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
