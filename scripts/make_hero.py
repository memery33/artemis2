#!/usr/bin/env python3
"""Drawn-window hero sequence.

The shipped docs/hero.gif and docs/hero-still.png are captures of the live
page with the controls hidden. This script rebuilds the older composed
sequence if you want that version instead. art002e016183 is a cabin
interior and is not used.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
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
    h, w = size[1], size[0]
    t = np.linspace(0, 1, h)[:, None]
    base = np.empty((h, w, 3), np.float32)
    for c in range(3):
        base[:, :, c] = light[c] * (1 - t) + dark[c] * t
    # Fine grain, not a fastener or panel pattern.
    rng = np.random.default_rng(7)
    base += rng.normal(0, 7, base.shape)
    ys = np.linspace(-1, 1, h)[:, None]
    xs = np.linspace(-1, 1, w)[None, :]
    # Recess corners fall off. The opening is the light source, so the middle stays brighter.
    corner = np.clip(np.abs(xs) * np.abs(ys) - 0.12, 0, 1)
    spill = np.clip(1 - np.sqrt(xs * xs * 0.7 + ys * ys), 0, 1)
    base *= 1 - corner[:, :, None] * 0.45
    base += spill[:, :, None] * 28
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")


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


def opening_box(w: int, h: int):
    """Landscape rounded rectangle filling the frame, cabin only at the edges.

    1.58 matches the cone-panel openings in jsc2022e045980. It is not a
    measured clear aperture. Interior photos that show the bezel
    (art002e004439, art002e004440, art002e009292) have a crew member in the
    glass, so this stays a drawing.
    """
    aspect = 1.58
    oh = int(h * 0.96)
    ow = int(oh * aspect)
    if ow > int(w * 0.98):
        ow = int(w * 0.98)
        oh = int(ow / aspect)
    ox = (w - ow) // 2
    oy = (h - oh) // 2
    return ox, oy, ox + ow, oy + oh


def compose(photo: Image.Image, caption: str, speaker: str, size, shift=(0.0, 0.0), moon: float = 0.7) -> Image.Image:
    w, h = size
    # Dark cabin. The interior frames were shot with the lights off.
    wall = metal(size, (36, 40, 48), (8, 9, 12))
    if moon > 0:
        shade = Image.new("RGB", size, (5, 6, 8))
        wall = Image.blend(wall, shade, min(0.28, moon * 0.22))
    outer = opening_box(w, h)
    # Nearest retainer, drawn and then softened. Inner steps and the glass stay sharp.
    near = metal((outer[2] - outer[0], outer[3] - outer[1]), (78, 84, 94), (18, 20, 24))
    near = near.filter(ImageFilter.GaussianBlur(radius=max(1.2, h / 280)))
    place_round(wall, near, outer, int(h * 0.075))
    pad_x, pad_y = int(w * 0.018), int(h * 0.032)
    mid = (outer[0] + pad_x, outer[1] + pad_y, outer[2] - pad_x, outer[3] - pad_y)
    place_round(wall, metal((mid[2] - mid[0], mid[3] - mid[1]), (22, 25, 30), (8, 9, 12)), mid, int(h * 0.05))
    lip = int(w * 0.01)
    inner = (mid[0] + lip, mid[1] + int(h * 0.016), mid[2] - lip, mid[3] - int(h * 0.018))
    place_round(wall, metal((inner[2] - inner[0], inner[3] - inner[1]), (120, 128, 136), (28, 32, 38)), inner, int(h * 0.034))
    edge = int(w * 0.006)
    opening = (inner[0] + edge, inner[1] + int(h * 0.01), inner[2] - edge, inner[3] - int(h * 0.012))
    ow, oh = opening[2] - opening[0], opening[3] - opening[1]
    glass = cover(photo, (ow, oh), shift).convert("RGBA")
    sheen = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.polygon([(0, 0), (int(ow * 0.46), 0), (0, int(oh * 0.62))], fill=(255, 255, 255, 22))
    vig = Image.new("L", (ow, oh), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse((-int(ow * 0.08), -int(oh * 0.05), int(ow * 1.08), int(oh * 1.08)), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(radius=max(8, oh // 10)))
    dark = Image.new("RGBA", (ow, oh), (0, 0, 0, 140))
    inv = Image.eval(vig, lambda p: 255 - p)
    dark.putalpha(inv)
    glass = Image.alpha_composite(glass, sheen)
    glass = Image.alpha_composite(glass, dark)
    place_round(wall, glass.convert("RGB"), opening, int(h * 0.026))
    if speaker or caption:
        small = font("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", max(11, h // 52))
        body = font("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", max(16, h // 34))
        cx = (opening[0] + opening[2]) // 2
        base = opening[3] - int(oh * 0.1)
        # Dim follows the glyphs. No ellipse across the Moon.
        mask = Image.new("L", wall.size, 0)
        md = ImageDraw.Draw(mask)
        if speaker:
            md.text((cx, base - int(h * 0.04)), speaker.upper(), fill=255, anchor="mm", font=small)
        if caption:
            md.text((cx, base), caption, fill=255, anchor="mm", font=body)
        soft = mask.filter(ImageFilter.GaussianBlur(radius=max(2, h // 180)))
        dim = Image.new("RGBA", wall.size, (0, 0, 0, 0))
        dim.putalpha(soft.point(lambda p: int(p * (0.28 + 0.22 * moon))))
        wall = Image.alpha_composite(wall.convert("RGBA"), dim).convert("RGB")
        draw = ImageDraw.Draw(wall)
        stroke = (0, 0, 0)
        if speaker:
            draw.text(
                (cx, base - int(h * 0.04)),
                speaker.upper(),
                fill=(255, 255, 255),
                anchor="mm",
                font=small,
                stroke_width=2,
                stroke_fill=stroke,
            )
        if caption:
            draw.text(
                (cx, base),
                caption,
                fill=(247, 247, 245),
                anchor="mm",
                font=body,
                stroke_width=2,
                stroke_fill=stroke,
            )
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
