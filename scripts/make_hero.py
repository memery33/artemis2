#!/usr/bin/env python3
"""Render the README hero GIF: the Orion window, real frames, one real subtitle."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demo" / "data"
OUT = ROOT / "docs" / "hero.gif"
W, H = 960, 540


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def frame_of(photo: Image.Image, caption: str, speaker: str) -> Image.Image:
    canvas = Image.new("RGB", (W, H), (7, 8, 12))
    draw = ImageDraw.Draw(canvas)
    # Cone-window surround. The opening is a landscape rounded rectangle,
    # matching the machined apertures in NASA image jsc2022e045980.
    outer = (70, 36, 890, 490)
    draw.rounded_rectangle(outer, radius=36, fill=(28, 30, 38))
    draw.rounded_rectangle((88, 52, 872, 468), radius=28, fill=(42, 38, 32))
    draw.rounded_rectangle((100, 64, 860, 456), radius=22, fill=(16, 22, 26))
    opening = (112, 76, 848, 444)
    photo = photo.convert("RGB")
    ow, oh = opening[2] - opening[0], opening[3] - opening[1]
    scale = max(ow / photo.width, oh / photo.height)
    resized = photo.resize((int(photo.width * scale), int(photo.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - ow) // 2
    top = (resized.height - oh) // 2
    crop = resized.crop((left, top, left + ow, top + oh))
    glass = Image.new("RGB", (ow, oh))
    glass.paste(crop, (0, 0))
    # Subtle glass sheen and vignette, drawn, not a second photograph.
    sheen = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.polygon([(0, 0), (int(ow * 0.42), 0), (0, int(oh * 0.55))], fill=(255, 255, 255, 28))
    for y in range(oh):
        edge = abs(y - oh / 2) / (oh / 2)
        shade = int(90 * edge * edge)
        sd.line([(0, y), (ow, y)], fill=(0, 0, 0, shade // 3))
    glass = Image.alpha_composite(glass.convert("RGBA"), sheen).convert("RGB")
    mask = rounded_mask((ow, oh), 16)
    canvas.paste(glass, (opening[0], opening[1]), mask)
    draw.rounded_rectangle((70, 488, 890, 508), radius=6, fill=(18, 19, 24))
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    body = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf", 18)
    if speaker:
        draw.text((W / 2, 386), speaker.upper(), fill=(240, 215, 162), anchor="mm", font=small)
    if caption:
        draw.text((W / 2, 412), caption, fill=(244, 241, 234), anchor="mm", font=body)
    return canvas


def main() -> None:
    timeline = json.loads((DEMO / "timeline.json").read_text())
    frames = timeline["frames"]
    if len(frames) < 2:
        sys.exit("need at least two demo frames")
    # Spread across the window so the GIF shows the view changing.
    picks = [frames[int(i * (len(frames) - 1) / 4)] for i in range(5)]
    line = next((row for row in timeline["lines"] if row["text"].startswith("It's got greenish hues")), None)
    if line is None:
        line = next((row for row in timeline["lines"] if row["speaker"] == "Hansen"), None)
    caption = ""
    speaker = ""
    if line:
        speaker = line["speaker"]
        caption = line["text"]
        if len(caption) > 72:
            caption = caption[:72].rsplit(" ", 1)[0] + "…"
    tmp = ROOT / "build" / "hero_frames"
    tmp.mkdir(parents=True, exist_ok=True)
    paths = []
    for index, frame in enumerate(picks):
        photo = Image.open(DEMO / frame["file"])
        # Hold each still, with a short crossfade blend into the next.
        show = index >= len(picks) - 2
        still = frame_of(photo, caption if show else "", speaker if show else "")
        for hold in range(6):
            path = tmp / f"{index:02d}_{hold:02d}.png"
            still.save(path)
            paths.append(path)
        if index < len(picks) - 1:
            nxt = Image.open(DEMO / picks[index + 1]["file"])
            for step in range(1, 5):
                blend = Image.blend(photo.convert("RGB").resize((640, 360)), nxt.convert("RGB").resize((640, 360)), step / 5)
                # Blend the source photos, then place them in the window.
                # Resize mismatch is handled inside frame_of.
                image = frame_of(blend.resize(photo.size), "", "")
                path = tmp / f"{index:02d}_x{step}.png"
                image.save(path)
                paths.append(path)
    palette = tmp / "palette.png"
    # Rename to a flat sequence.
    seq = ROOT / "build" / "hero_seq"
    if seq.exists():
        for old in seq.glob("*.png"):
            old.unlink()
    seq.mkdir(parents=True, exist_ok=True)
    for i, path in enumerate(paths):
        Image.open(path).save(seq / f"f{i:03d}.png")
    subprocess.check_call(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-framerate", "8", "-i", str(seq / "f%03d.png"),
            "-vf", "palettegen=stats_mode=diff",
            str(palette),
        ]
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-framerate", "8", "-i", str(seq / "f%03d.png"),
            "-i", str(palette),
            "-lavfi", "paletteuse=dither=bayer:bayer_scale=3",
            "-loop", "0",
            str(OUT),
        ]
    )
    print(OUT, OUT.stat().st_size)


if __name__ == "__main__":
    main()
