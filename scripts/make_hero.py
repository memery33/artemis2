#!/usr/bin/env python3
"""README hero: the Moon through the cone window, with one real crew line.

Opens on a lunar frame. art002e016183 is a cabin interior and is not used.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "demo" / "data"
GIF = ROOT / "docs" / "hero.gif"
STILL = ROOT / "docs" / "hero-still.png"
CABIN = {"art002e016183"}


def font(path: str, size: int) -> ImageFont.ImageFont:
    return ImageFont.truetype(path, size)


def rounded_mask(size, radius) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def metal(size, light, dark) -> Image.Image:
    image = Image.new("RGB", size, dark)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        shade = tuple(int(light[c] * (1 - t) + dark[c] * t) for c in range(3))
        draw.line([(0, y), (size[0], y)], fill=shade)
    return image


def place_round(canvas: Image.Image, image: Image.Image, box, radius) -> None:
    x0, y0, x1, y1 = box
    image = image.resize((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    canvas.paste(image, (x0, y0), rounded_mask(image.size, radius))


def cover(photo: Image.Image, size, shift=(0.0, 0.0)) -> Image.Image:
    photo = photo.convert("RGB")
    scale = max(size[0] / photo.width, size[1] / photo.height) * 1.08
    resized = photo.resize((int(photo.width * scale), int(photo.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2 + int(shift[0] * size[0])
    top = (resized.height - size[1]) // 2 + int(shift[1] * size[1])
    left = max(0, min(left, resized.width - size[0]))
    top = max(0, min(top, resized.height - size[1]))
    return resized.crop((left, top, left + size[0], top + size[1]))


def compose(photo: Image.Image, caption: str, speaker: str, size, shift=(0.0, 0.0), moon: float = 0.7) -> Image.Image:
    w, h = size
    wall = metal(size, (104, 110, 120), (28, 31, 38))
    # Sunlit Moon darkens the cabin wall. The shade is not a second photograph.
    if moon > 0:
        shade = Image.new("RGB", size, (8, 9, 12))
        wall = Image.blend(wall, shade, min(0.38, moon * 0.34))
    draw = ImageDraw.Draw(wall)
    # Landscape rounded opening, the shape in NASA image jsc2022e045980.
    # Three steps: thermal retainer, pressure pane, innermost acrylic lip.
    outer = (int(w * 0.08), int(h * 0.08), int(w * 0.92), int(h * 0.90))
    place_round(wall, metal((outer[2] - outer[0], outer[3] - outer[1]), (168, 174, 184), (48, 52, 60)), outer, int(h * 0.08))
    mid = (outer[0] + int(w * 0.028), outer[1] + int(h * 0.045), outer[2] - int(w * 0.028), outer[3] - int(h * 0.055))
    place_round(wall, metal((mid[2] - mid[0], mid[3] - mid[1]), (28, 32, 38), (10, 11, 14)), mid, int(h * 0.055))
    inner = (mid[0] + int(w * 0.016), mid[1] + int(h * 0.028), mid[2] - int(w * 0.016), mid[3] - int(h * 0.032))
    place_round(wall, metal((inner[2] - inner[0], inner[3] - inner[1]), (150, 158, 168), (40, 44, 50)), inner, int(h * 0.04))
    opening = (inner[0] + int(w * 0.012), inner[1] + int(h * 0.02), inner[2] - int(w * 0.012), inner[3] - int(h * 0.022))
    ow, oh = opening[2] - opening[0], opening[3] - opening[1]
    glass = cover(photo, (ow, oh), shift).convert("RGBA")
    sheen = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.polygon([(0, 0), (int(ow * 0.46), 0), (0, int(oh * 0.62))], fill=(255, 255, 255, 26))
    vig = Image.new("L", (ow, oh), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse((-int(ow * 0.08), -int(oh * 0.05), int(ow * 1.08), int(oh * 1.08)), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(radius=max(8, oh // 10)))
    dark = Image.new("RGBA", (ow, oh), (0, 0, 0, 150))
    # Invert the ellipse so the center stays clear.
    inv = Image.eval(vig, lambda p: 255 - p)
    dark.putalpha(inv)
    glass = Image.alpha_composite(glass, sheen)
    glass = Image.alpha_composite(glass, dark)
    place_round(wall, glass.convert("RGB"), opening, int(h * 0.03))
    draw = ImageDraw.Draw(wall)
    if speaker or caption:
        small = font("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", max(11, h // 48))
        body = font("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", max(16, h // 32))
        cx = (opening[0] + opening[2]) // 2
        base = opening[3] - int(oh * 0.12)
        if speaker:
            draw.text((cx, base - int(h * 0.045)), speaker.upper(), fill=(255, 255, 255, 180), anchor="mm", font=small)
        if caption:
            draw.text((cx, base), caption, fill=(245, 245, 245), anchor="mm", font=body)
    return wall


def luminance(photo: Image.Image) -> float:
    g = photo.convert("L")
    hist = g.histogram()
    total = sum(hist) or 1
    return sum(i * n for i, n in enumerate(hist)) / total / 255


def main() -> None:
    timeline = json.loads((DEMO / "timeline.json").read_text())
    lunar = [frame for frame in timeline["frames"] if frame["nasa_id"] not in CABIN and frame.get("view") != "cabin"]
    # Prefer sunlit frames so the loop opens on the Moon, not a dark exposure.
    ranked = sorted(lunar, key=lambda frame: luminance(Image.open(DEMO / frame["file"])), reverse=True)
    picks = []
    for frame in ranked:
        if frame["nasa_id"] not in {row["nasa_id"] for row in picks}:
            picks.append(frame)
        if len(picks) == 3:
            break
    if len(picks) < 2:
        sys.exit("need lunar frames")
    line = next(row for row in timeline["lines"] if row["text"] == "It's got greenish hues.")
    speaker = line["speaker"]
    caption = line["text"]
    still = compose(Image.open(DEMO / picks[0]["file"]), caption, speaker, (1280, 720), moon=luminance(Image.open(DEMO / picks[0]["file"])))
    STILL.parent.mkdir(parents=True, exist_ok=True)
    still.save(STILL, optimize=True)
    tmp = ROOT / "build" / "hero_seq"
    if tmp.exists():
        for old in tmp.glob("*.png"):
            old.unlink()
    tmp.mkdir(parents=True, exist_ok=True)
    paths = []
    size = (960, 540)
    photos = [Image.open(DEMO / frame["file"]) for frame in picks]
    moons = [luminance(photo) for photo in photos]
    # Open on the Moon with the crew line, then a short drift into the next frame.
    sequence = []
    for index, photo in enumerate(photos):
        for step in range(7):
            shift = ((step - 3) * 0.008, step * 0.004)
            sequence.append((photo, moons[index], shift, True))
        if index < len(photos) - 1:
            nxt = photos[index + 1]
            for step in range(1, 5):
                blend = Image.blend(photo.convert("RGB"), nxt.convert("RGB").resize(photo.size), step / 5)
                sequence.append((blend, moons[index] * (1 - step / 5) + moons[index + 1] * step / 5, (0.01, 0.01), True))
    for i, (photo, moon, shift, show) in enumerate(sequence):
        path = tmp / f"f{i:03d}.png"
        compose(photo, caption if show else "", speaker if show else "", size, shift, moon).save(path, optimize=True)
        paths.append(path)
    palette = tmp / "palette.png"
    subprocess.check_call(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-framerate", "8", "-i", str(tmp / "f%03d.png"),
            "-vf", "palettegen=max_colors=96:stats_mode=diff",
            str(palette),
        ]
    )
    subprocess.check_call(
        [
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-framerate", "8", "-i", str(tmp / "f%03d.png"),
            "-i", str(palette),
            "-lavfi", "paletteuse=dither=bayer:bayer_scale=3",
            "-loop", "0",
            str(GIF),
        ]
    )
    print(STILL, STILL.stat().st_size)
    print(GIF, GIF.stat().st_size, "frames", len(paths), "opens", picks[0]["nasa_id"])


if __name__ == "__main__":
    main()
