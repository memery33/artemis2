#!/usr/bin/env python3
"""Write a 720 px long-edge sibling for each shipped demo WebP.

The sibling is a lanczos downscale of that file. Frames at or under 720 px
are left alone. Nothing is upscaled, and no timestamp is changed.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "demo" / "data" / "images"


def _dims(path: Path) -> tuple[int, int]:
    out = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0",
            str(path),
        ],
        text=True,
    ).strip()
    width, height = out.split(",")
    return int(width), int(height)


def make_narrow(directory: Path = IMAGES) -> int:
    written = 0
    for source in sorted(directory.glob("*.webp")):
        if source.name.endswith(".720.webp"):
            continue
        width, height = _dims(source)
        if max(width, height) <= 720:
            continue
        dest = source.with_name(f"{source.stem}.720.webp")
        if dest.is_file() and dest.stat().st_mtime >= source.stat().st_mtime:
            continue
        subprocess.check_call(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "error",
                "-i",
                str(source),
                "-vf",
                "scale='min(720,iw)':-2:flags=lanczos",
                "-c:v",
                "libwebp",
                "-quality",
                "72",
                str(dest),
            ]
        )
        written += 1
    return written


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else IMAGES
    count = make_narrow(target)
    print(f"narrow webp written {count}")
