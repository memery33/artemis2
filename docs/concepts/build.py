#!/usr/bin/env python3
"""Regenerate the Orion Window concept screens.

    python3 docs/concepts/build.py
    python3 docs/concepts/build.py --render

Reads demo/data/timeline.json and the bundled Horizons table. Writes HTML
under docs/concepts/{cinematic,mission,smithsonian}/. With --render, also
writes the 3x PNGs beside the HTML.

The scrubber is linear from the flyby window open (19:33:00.000 UTC) through
the parabola-vertex closest approach. Nothing on the screens is interpolated
except spacecraft position between the one-minute Horizons samples, which is
the same linear segment the app uses.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
TIMELINE = ROOT / "demo" / "data" / "timeline.json"
HORIZONS = ROOT / "ios" / "ArtemisIIWindow" / "Resources" / "horizons_orion_moon.json"
LROC = "../../../ios/ArtemisIIWindow/Resources/lroc_color_2k.jpg"
IMG = "../../../demo/data/images"
RADIUS_KM = 1737.4
MISSION_START = "2026-04-01T22:35:12Z"
WINDOW_START = "2026-04-06T19:33:00.000Z"
WINDOW_END = "2026-04-06T19:48:30.000Z"
PLAYHEAD = "2026-04-06T19:36:05.938Z"
CAB_START = "2026-04-06T22:36:03.000Z"

CREDIT = "Credit: NASA/Artemis II Crew"
ENDORSEMENT = "This app is not affiliated with or endorsed by NASA."
MAP_CREDIT = (
    "The globe uses the NASA SVS CGI Moon Kit 2025 LROC color map, file lroc_color_2k.jpg, "
    "2048 by 1024, public domain. Credit: NASA/Goddard Space Flight Center Scientific "
    "Visualization Studio, Lunar Reconnaissance Orbiter Camera, Arizona State University, "
    "and Noah Petro (NASA/GSFC), visualization by Ernie Wright. SVS 4720. The map is "
    "centered on 0° longitude and is an aesthetic rendering, not a photograph and not "
    "the flyby lighting."
)
SCIENCE = (
    "Plateau known for its volcanic diversity and the bright Aristarchus crater, "
    "looking for color, albedo, and texture variations across the plateau and surrounding mare."
)
SCIENCE_SOURCE = (
    "Guide to the Artemis II Lunar Targeting Plan, NASA Science. "
    "Science and Operational Focus for Aristarchus Plateau."
)
POINTING = (
    "No per-window attitude. The NAIF SPICE bundle is delayed and no CK/FK/SCLK is public. "
    "Footprints are georeferenced Nikon frames, not a window boresight."
)


def parse(iso: str) -> datetime:
    return datetime.fromisoformat(iso.replace("Z", "+00:00"))


def iso_z(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f").rstrip("0").rstrip(".") + "Z"


def clock(iso: str, millis: bool = True) -> str:
    text = iso[11:23] if millis else iso[11:19]
    if not millis:
        return iso[11:19]
    frac = iso[19:23] if len(iso) > 19 and iso[19] == "." else ""
    base = iso[11:19]
    if frac in ("", ".000"):
        return base
    return (base + frac).rstrip("0")


def km(value: float) -> str:
    return f"{value:,.2f} km"


def deg(value: float, lat: bool = False) -> str:
    hemi = ("N", "S") if lat else ("E", "W")
    side = hemi[0] if value >= 0 else hemi[1]
    return f"{abs(value):.3f}° {side}"


def met(moment: datetime, mission: datetime) -> str:
    seconds = (moment - mission).total_seconds()
    days = int(seconds // 86400)
    rem = seconds - days * 86400
    hours = int(rem // 3600)
    rem -= hours * 3600
    minutes = int(rem // 60)
    secs = rem - minutes * 60
    return f"{days:02d}:{hours:02d}:{minutes:02d}:{secs:06.3f}"


def closest_approach(samples: list[dict]) -> dict:
    ranges = [row["rangeKm"] for row in samples]
    index = min(range(len(samples)), key=lambda i: ranges[i])
    before, middle, after = ranges[index - 1], ranges[index], ranges[index + 1]
    curvature = (before + after) / 2 - middle
    slope = (after - before) / 2
    vertex = max(-1.0, min(1.0, -slope / (2 * curvature)))
    step = (parse(samples[index + 1]["t"]) - parse(samples[index - 1]["t"])).total_seconds() / 2
    moment = datetime.fromtimestamp(parse(samples[index]["t"]).timestamp() + vertex * step, tz=timezone.utc)
    distance = curvature * vertex * vertex + slope * vertex + middle
    return {
        "moment": moment,
        "iso": iso_z(moment),
        "rangeKm": distance,
        "altitudeKm": distance - RADIUS_KM,
        "vertex": vertex,
    }


def interp(samples: list[dict], moment: datetime) -> dict:
    for left, right in zip(samples, samples[1:]):
        a, b = parse(left["t"]), parse(right["t"])
        if a <= moment <= b:
            span = (b - a).total_seconds()
            portion = 0 if span == 0 else (moment - a).total_seconds() / span
            x = left["x"] + (right["x"] - left["x"]) * portion
            y = left["y"] + (right["y"] - left["y"]) * portion
            z = left["z"] + (right["z"] - left["z"]) * portion
            distance = math.sqrt(x * x + y * y + z * z)
            lon = math.degrees(math.atan2(y, x))
            if lon < 0:
                lon += 360
            lat = math.degrees(math.asin(max(-1, min(1, z / distance))))
            return {"rangeKm": distance, "altitudeKm": distance - RADIUS_KM, "lon": lon, "lat": lat, "x": x, "y": y, "z": z}
    raise KeyError(moment.isoformat())


# Crop of the SVS map that keeps the sub-observer track in one piece.
# East longitude runs from the western nearside (340° E) across the limb
# to the farside approach (150° E). Latitude 48° N to 42° S.
LON_LEFT = 340.0
LON_RIGHT = 150.0
LAT_TOP = 48.0
LAT_BOTTOM = -42.0
TRACK_MAP = OUT / "mission" / "lroc-track.jpg"


def crop_xy(lon: float, lat: float) -> tuple[float, float]:
    east = lon % 360.0
    x = (LON_LEFT - east) / (LON_LEFT - LON_RIGHT) * 1000.0
    y = (LAT_TOP - lat) / (LAT_TOP - LAT_BOTTOM) * 500.0
    return x, y


def write_track_map() -> None:
    import numpy as np
    from PIL import Image

    source = np.asarray(Image.open(ROOT / "ios/ArtemisIIWindow/Resources/lroc_color_2k.jpg"))
    height, width = source.shape[:2]
    out_w = 1400
    out_h = round(out_w * (LAT_TOP - LAT_BOTTOM) / (LON_LEFT - LON_RIGHT))
    columns = np.linspace(LON_LEFT, LON_RIGHT, out_w)
    signed = ((columns + 180.0) % 360.0) - 180.0
    x = np.clip(np.rint((signed + 180.0) / 360.0 * (width - 1)).astype(int), 0, width - 1)
    rows = np.linspace(LAT_TOP, LAT_BOTTOM, out_h)
    y = np.clip(np.rint((90.0 - rows) / 180.0 * (height - 1)).astype(int), 0, height - 1)
    TRACK_MAP.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(source[y][:, x]).save(TRACK_MAP, quality=92)


def track_segments(samples: list[dict], start: datetime, end: datetime) -> list[str]:
    segments: list[list[tuple[float, float]]] = [[]]
    previous: tuple[float, float] | None = None
    for row in samples:
        moment = parse(row["t"])
        if moment < start or moment > end:
            continue
        place = interp(samples, moment)
        point = crop_xy(place["lon"], place["lat"])
        if previous is not None and abs(point[0] - previous[0]) > 500:
            segments.append([])
        segments[-1].append(point)
        previous = point
    # The vertex can fall between samples. Append the interpolated end if the
    # last kept sample is earlier.
    end_place = interp(samples, end)
    end_point = crop_xy(end_place["lon"], end_place["lat"])
    if segments[-1] and abs(segments[-1][-1][0] - end_point[0]) > 500:
        segments.append([end_point])
    elif segments[-1]:
        segments[-1].append(end_point)
    else:
        segments[-1].append(end_point)
    return [
        " ".join(f"{x:.2f},{y:.2f}" for x, y in segment)
        for segment in segments
        if len(segment) > 1
    ]


def load() -> dict:
    timeline = json.loads(TIMELINE.read_text())
    horizons = json.loads(HORIZONS.read_text())
    samples = horizons["samples"]
    approach = closest_approach(samples)
    mission = parse(MISSION_START)
    play = parse(PLAYHEAD)
    start = parse(WINDOW_START)
    end = approach["moment"]
    span = (end - start).total_seconds()
    window_seconds = (parse(WINDOW_END) - start).total_seconds()

    def frac(iso: str) -> float:
        return (parse(iso) - start).total_seconds() / span

    lines = timeline["lines"]
    frames = timeline["frames"]
    quote = next(row for row in lines if row["utc"] == PLAYHEAD)
    aristarchus = next(row for row in lines if row["utc"] == "2026-04-06T19:33:02.700Z")
    albedo = next(row for row in lines if row["utc"] == "2026-04-06T19:38:52.750Z")
    dwell = next(row for row in lines if row["utc"] == "2026-04-06T19:36:08.882Z")
    hansen = next(row for row in lines if row["utc"] == "2026-04-06T19:33:23.114Z")
    reiner = next(row for row in lines if row["utc"] == "2026-04-06T19:40:57.609Z")
    hero = next(row for row in frames if row["nasa_id"] == "art002e009806")
    cabin = next(row for row in frames if row["nasa_id"] == "art002e041348")
    reiner_frame = next(row for row in frames if row["nasa_id"] == "art002e009951")
    play_state = interp(samples, play)
    open_state = interp(samples, start)
    approach_state = interp(samples, end)
    return {
        "timeline": timeline,
        "samples": samples,
        "approach": approach,
        "approach_state": approach_state,
        "play": play_state,
        "open": open_state,
        "span": span,
        "window_seconds": window_seconds,
        "frac": frac,
        "met_play": met(play, mission),
        "met_open": met(start, mission),
        "met_approach": met(end, mission),
        "lines": lines,
        "frames": frames,
        "quote": quote,
        "aristarchus": aristarchus,
        "albedo": albedo,
        "dwell": dwell,
        "hansen": hansen,
        "reiner": reiner,
        "hero": hero,
        "cabin": cabin,
        "reiner_frame": reiner_frame,
        "segments": track_segments(samples, start, end),
        "obs_pct": 100.0 * window_seconds / span,
    }


def e(text: str) -> str:
    return html.escape(text, quote=True)


# --- rulers -----------------------------------------------------------------

def tick_rows(data: dict) -> tuple[list[dict], list[dict]]:
    start = parse(WINDOW_START)
    end = data["approach"]["moment"]
    lines = []
    for row in data["lines"]:
        moment = parse(row["utc"])
        if start <= moment <= end:
            lines.append(row)
    frames = []
    for row in data["frames"]:
        moment = parse(row["utc"])
        if start <= moment <= end:
            frames.append(row)
    return lines, frames


def vertical_rail(data: dict) -> str:
    """Full-height linear ruler. Dense events keep their true tick; names that
    would collide step down the empty coast and keep a leader to the tick."""
    lines, frames = tick_rows(data)
    frac = data["frac"]
    top, height = 28.0, 796.0

    def y_of(iso: str) -> float:
        return top + frac(iso) * height

    ticks = []
    for row in lines:
        ticks.append(f'<i class="tk line" style="top:{y_of(row["utc"]):.2f}px"></i>')
    for row in frames:
        if row.get("instrument") == "cab2":
            continue
        ticks.append(f'<i class="tk photo" style="top:{y_of(row["utc"]):.2f}px"></i>')
    ticks.append(f'<i class="tk span" style="top:{y_of(WINDOW_START):.2f}px;height:{(frac(WINDOW_END) - frac(WINDOW_START)) * height:.2f}px"></i>')
    ticks.append(f'<i class="tk head" style="top:{y_of(PLAYHEAD):.2f}px"></i>')
    ticks.append(
        f'<i class="tk span cabspan" style="top:{y_of(CAB_START):.2f}px;height:{(frac("2026-04-06T22:44:33.000Z") - frac(CAB_START)) * height:.2f}px"></i>'
    )

    early = [
        (WINDOW_START, "19:33:00", "Window opens"),
        ("2026-04-06T19:33:02.700Z", "19:33:02", "Aristarchus"),
        ("2026-04-06T19:35:52.140Z", "19:35:52", "art002e009806"),
        (PLAYHEAD, "19:36:05", "Wiseman"),
        ("2026-04-06T19:38:52.750Z", "19:38:52", "Albedo"),
        ("2026-04-06T19:40:57.609Z", "19:40:57", "Reiner Gamma"),
        (WINDOW_END, "19:48:30", "Window closes"),
    ]
    late = [
        (CAB_START, "22:36:03", "Cab Cam 2"),
        (data["approach"]["iso"], "23:00:46", "Closest approach"),
    ]
    labels = []
    cursor = 108.0
    for iso, when, name in early:
        tick = y_of(iso)
        label = max(tick, cursor)
        labels.append((tick, label, when, name, iso == PLAYHEAD))
        cursor = label + 46.0
    for iso, when, name in late:
        tick = y_of(iso)
        labels.append((tick, tick - 18, when, name, False))

    leaders = []
    notes = []
    for tick, label, when, name, current in labels:
        if abs(label - tick) > 3:
            leaders.append(
                f'<svg class="leader" style="top:{min(tick, label):.2f}px;height:{abs(label - tick) + 8:.2f}px" '
                f'viewBox="0 0 20 {abs(label - tick) + 8:.2f}" preserveAspectRatio="none">'
                f'<path d="M18 2 L4 {abs(label - tick) + 2:.2f}" /></svg>'
                if label > tick
                else ""
            )
        klass = "lb now" if current else "lb"
        notes.append(
            f'<div class="{klass}" style="top:{label:.2f}px"><b>{e(when)}</b><span>{e(name)}</span></div>'
        )
    hours = []
    for hour, minute in ((20, 0), (21, 0), (22, 0), (23, 0)):
        iso = f"2026-04-06T{hour:02d}:{minute:02d}:00.000Z"
        if parse(iso) >= data["approach"]["moment"]:
            continue
        y = y_of(iso)
        if 430 < y < 760:
            hours.append(f'<div class="hour" style="top:{y:.2f}px">{hour:02d}:00</div>')
            ticks.append(f'<i class="tk hour" style="top:{y:.2f}px"></i>')
    return "\n".join(ticks + leaders + notes + hours)


def horizontal_marks(data: dict, mode: str) -> str:
    lines, frames = tick_rows(data)
    start = parse(WINDOW_START)
    if mode == "obs":
        span = data["window_seconds"]

        def pct(iso: str) -> float:
            return 100.0 * (parse(iso) - start).total_seconds() / span
    else:
        def pct(iso: str) -> float:
            return 100.0 * data["frac"](iso)

    parts = ['<i class="base"></i>']
    if mode == "all":
        parts.append(f'<i class="band" style="left:0;width:{data["obs_pct"]:.4f}%"></i>')
    source_lines = lines if mode == "obs" else []
    source_frames = frames if mode == "obs" else [row for row in frames if row.get("instrument") == "cab2" or parse(row["utc"]) <= parse(WINDOW_END)]
    if mode == "all":
        source_frames = frames
        source_lines = []
    for row in source_lines:
        parts.append(f'<i class="mk line" style="left:{pct(row["utc"]):.4f}%"></i>')
    for row in source_frames:
        kind = "cab" if row.get("instrument") == "cab2" else "frame"
        if mode == "all" and row.get("instrument") != "cab2" and parse(row["utc"]) > parse(WINDOW_END):
            continue
        parts.append(f'<i class="mk {kind}" style="left:{pct(row["utc"]):.4f}%"></i>')
    parts.append(f'<i class="mk play" style="left:{pct(PLAYHEAD):.4f}%"></i>')
    if mode == "all":
        parts.append(f'<i class="mk approach" style="left:{pct(data["approach"]["iso"]):.4f}%"></i>')
        parts.append(f'<i class="mk cabmark" style="left:{pct(CAB_START):.4f}%"></i>')
    named = []
    if mode == "obs":
        named = [
            ("2026-04-06T19:33:02.700Z", "19:33:02", "Aristarchus", "above"),
            ("2026-04-06T19:35:52.140Z", "19:35:52", "art002e009806", "below"),
            (PLAYHEAD, "19:36:05.938", "Wiseman", "above"),
            ("2026-04-06T19:38:52.750Z", "19:38:52", "Albedo", "below"),
            ("2026-04-06T19:40:57.609Z", "19:40:57", "Reiner Gamma", "above"),
            (WINDOW_END, "19:48:30", "Window closes", "below"),
        ]
    else:
        named = [
            (WINDOW_START, "19:33:00", "Window", "below"),
            (CAB_START, "22:36:03", "Cab Cam 2", "above"),
            (data["approach"]["iso"], "23:00:46", "Closest approach", "above"),
        ]
    for iso, when, name, side in named:
        anchor = "end" if pct(iso) > 88 else "start" if pct(iso) < 8 else "mid"
        parts.append(
            f'<div class="nm {side} {anchor}" style="left:{pct(iso):.4f}%"><b>{e(when)}</b>{e(name)}</div>'
        )
    return "\n".join(parts)


def spine(data: dict) -> str:
    lines, frames = tick_rows(data)
    frac = data["frac"]
    top, height = 36.0, 780.0

    def y_of(iso: str) -> float:
        return top + frac(iso) * height

    ticks = [f'<i class="spine-rule"></i>']
    ticks.append(
        f'<i class="spine-span" style="top:{y_of(WINDOW_START):.2f}px;height:{(frac(WINDOW_END) - frac(WINDOW_START)) * height:.2f}px"></i>'
    )
    for row in lines:
        ticks.append(f'<i class="spine-tk" style="top:{y_of(row["utc"]):.2f}px"></i>')
    for row in frames:
        if row.get("instrument") == "cab2":
            continue
        ticks.append(f'<i class="spine-ph" style="top:{y_of(row["utc"]):.2f}px"></i>')
    ticks.append(
        f'<i class="spine-cab" style="top:{y_of(CAB_START):.2f}px;height:{(frac("2026-04-06T22:44:33.000Z") - frac(CAB_START)) * height:.2f}px"></i>'
    )
    ticks.append(f'<i class="spine-play" style="top:{y_of(PLAYHEAD):.2f}px"></i>')
    chapters = [
        ("I", WINDOW_START, "Window opens"),
        ("II", "2026-04-06T19:33:02.700Z", "Aristarchus"),
        ("III", "2026-04-06T19:35:52.140Z", "art002e009806"),
        ("IV", PLAYHEAD, "Wiseman"),
        ("V", "2026-04-06T19:38:52.750Z", "Albedo"),
        ("VI", "2026-04-06T19:40:57.609Z", "Reiner Gamma"),
        ("VII", WINDOW_END, "Window closes"),
        ("VIII", CAB_START, "Cab Cam 2"),
        ("IX", data["approach"]["iso"], "Closest approach"),
    ]
    cursor = 72.0
    notes = []
    for numeral, iso, name in chapters:
        tick = y_of(iso)
        if frac(iso) < 0.12:
            label = max(tick - 8, cursor)
            cursor = label + 52
        else:
            label = tick - 16
        notes.append(
            f'<div class="ch" style="top:{label:.2f}px"><em>{numeral}</em><b>{e(clock(iso, False))}</b><span>{e(name)}</span></div>'
        )
        if abs(label + 8 - tick) > 6:
            notes.append(f'<i class="ch-lead" style="top:{tick:.2f}px"></i>')
    return "\n".join(ticks + notes)


# --- pages ------------------------------------------------------------------

SHELL = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
{css}
</style>
</head>
<body>
{body}
</body>
</html>
"""


CINE_CSS = r"""
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 393px; height: 852px; overflow: hidden; background: #050505; }
body { color: #F3EFE6; font-family: Inter, "Noto Sans", sans-serif; -webkit-font-smoothing: antialiased; }
.screen { position: relative; width: 393px; height: 852px; overflow: hidden; background: #050505; }
img.bleed { position: absolute; inset: 0; width: 393px; height: 852px; object-fit: cover; object-position: 36% 42%; }
.scrim { position: absolute; inset: 0; background: linear-gradient(180deg, rgba(5,5,5,0.35) 0%, rgba(5,5,5,0.05) 22%, rgba(5,5,5,0) 42%, rgba(5,5,5,0.55) 68%, rgba(5,5,5,0.88) 100%); }
.kicker { font-weight: 500; font-size: 10px; letter-spacing: 0.22em; text-transform: uppercase; color: #C6A36A; }
.serif { font-family: "Noto Serif Display", "Noto Serif", serif; font-weight: 400; }
.dim { color: #B7B0A4; }
.plate { display: block; width: 393px; height: 262px; object-fit: cover; object-position: center; }
.rule { width: 28px; height: 1px; background: #C6A36A; border: 0; }
.cue { position: absolute; left: 0; right: 0; bottom: 18px; display: flex; flex-direction: column; align-items: center; gap: 7px; color: #C6A36A; }
.cue svg { display: block; }
.cue span { font-size: 9px; letter-spacing: 0.18em; font-weight: 500; }
.micro { position: relative; width: 168px; height: 1px; background: rgba(243,239,230,0.28); }
.micro .obs { position: absolute; left: 0; top: 0; height: 1px; background: #C6A36A; }
.micro .now { position: absolute; top: -3px; width: 1px; height: 7px; background: #C6A36A; }
.rail { position: absolute; top: 0; right: 0; bottom: 0; width: 156px; background: linear-gradient(90deg, rgba(5,5,5,0) 0%, #050505 18%); }
.tk { position: absolute; right: 18px; height: 1px; background: rgba(243,239,230,0.55); }
.tk.line { width: 7px; background: rgba(243,239,230,0.38); }
.tk.photo { width: 16px; right: 18px; background: #C6A36A; }
.tk.cab { background: #F3EFE6; }
.tk.span { width: 2px; right: 36px; background: rgba(198,163,106,0.85); height: 40px; }
.tk.cabspan { right: 28px; width: 2px; background: rgba(243,239,230,0.85); }
.tk.head { width: 28px; height: 2px; right: 12px; background: #C6A36A; }
.tk.hour { width: 10px; background: rgba(243,239,230,0.7); }
.lb { position: absolute; right: 40px; width: 108px; text-align: right; }
.lb b, .lb span { display: block; }
.lb b { font-size: 10px; font-weight: 500; letter-spacing: 0.04em; color: #F3EFE6; font-variant-numeric: tabular-nums; }
.lb span { margin-top: 1px; font-size: 10px; color: #B7B0A4; }
.lb.now b, .lb.now span { color: #C6A36A; }
.hour { position: absolute; right: 36px; font-size: 9px; letter-spacing: 0.14em; color: rgba(243,239,230,0.55); font-variant-numeric: tabular-nums; }
.leader { position: absolute; right: 28px; width: 16px; overflow: visible; }
.leader path { fill: none; stroke: rgba(198,163,106,0.45); stroke-width: 1; }
.sheet { position: absolute; left: 0; right: 156px; bottom: 0; height: 318px; padding: 16px 18px 22px; background: #0C0C0B; border-top: 1px solid rgba(198,163,106,0.45); }
.grab { width: 28px; height: 1px; background: rgba(198,163,106,0.8); margin-bottom: 14px; }
.transport { display: flex; align-items: center; justify-content: space-between; margin-top: 16px; }
.skip, .pause { background: none; border: 0; color: #F3EFE6; font-family: Inter, sans-serif; }
.skip { font-size: 12px; letter-spacing: 0.14em; font-weight: 500; }
.pause { width: 52px; height: 52px; border: 1px solid #C6A36A; border-radius: 50%; display: grid; place-items: center; }
"""


def cine_open(data: dict) -> str:
    cabin = data["cabin"]
    body = f"""
<div class="screen">
  <img class="bleed" alt="art002e041348, the Moon through Cab Cam 2" src="{IMG}/{cabin["file"].split("/")[-1].replace(".webp", ".720.webp")}">
  <div class="scrim"></div>
  <div style="position:absolute;top:54px;left:28px;right:28px;display:flex;justify-content:space-between;align-items:baseline">
    <div class="kicker">Orion Window</div>
    <div class="dim" style="font-size:10px;letter-spacing:0.16em">6 APR 2026</div>
  </div>
  <div style="position:absolute;left:28px;right:28px;bottom:36px">
    <div class="kicker" style="margin-bottom:14px">Window 3</div>
    <h1 class="serif" style="font-size:64px;line-height:0.9;font-weight:400;letter-spacing:-0.03em">Cab Cam 2</h1>
    <div style="margin-top:22px;display:grid;grid-template-columns:1fr 1fr;gap:14px 18px;max-width:320px">
      <div><div class="dim" style="font-size:9px;letter-spacing:0.16em;text-transform:uppercase">UTC</div><div style="margin-top:3px;font-variant-numeric:tabular-nums;font-size:15px">22:36:03.000</div></div>
      <div><div class="dim" style="font-size:9px;letter-spacing:0.16em;text-transform:uppercase">Frame</div><div style="margin-top:3px;font-size:15px">art002e041348</div></div>
      <div><div class="dim" style="font-size:9px;letter-spacing:0.16em;text-transform:uppercase">Lens</div><div style="margin-top:3px;font-size:15px">GoPro · 3 mm</div></div>
      <div><div class="dim" style="font-size:9px;letter-spacing:0.16em;text-transform:uppercase">Target</div><div style="margin-top:3px;font-size:15px">Moon</div></div>
    </div>
    <p class="dim" style="margin-top:18px;max-width:280px;font-size:12px;line-height:1.45">These GoPro frames stay on their label times.</p>
    <p style="margin-top:16px;font-size:10px;letter-spacing:0.08em;color:#F3EFE6">{e(CREDIT)}</p>
  </div>
</div>
"""
    return SHELL.format(title="Cinematic — opening", css=CINE_CSS, body=body)


def cine_play(data: dict) -> str:
    hero = data["hero"]
    quote = data["quote"]
    body = f"""
<div class="screen">
  <div style="position:absolute;top:52px;left:24px;right:24px;display:flex;justify-content:space-between;align-items:baseline">
    <div class="kicker">Window 2 · Nikon D5</div>
    <div style="font-variant-numeric:tabular-nums;font-size:12px;letter-spacing:0.04em">19:36:05.938 <span class="dim">UTC</span></div>
  </div>
  <img class="plate" style="position:absolute;top:88px;left:0" alt="{e(hero["nasa_id"])}" src="{IMG}/art002e009806.720.webp">
  <div style="position:absolute;top:358px;left:24px;right:24px;display:flex;justify-content:space-between">
    <div class="dim" style="font-size:10px;letter-spacing:0.08em">400 mm · Aristarchus Plateau</div>
    <div style="font-size:10px;letter-spacing:0.06em">{e(CREDIT)}</div>
  </div>
  <div style="position:absolute;left:24px;right:36px;bottom:78px">
    <div class="rule"></div>
    <div class="kicker" style="margin-top:14px">Wiseman · PCD3 · art002a000021</div>
    <p class="serif" style="margin-top:8px;font-style:italic;font-size:30px;line-height:1.16;letter-spacing:-0.02em">{e(quote["text"])}</p>
    <p class="dim" style="margin-top:12px;font-size:12px;line-height:1.4;max-width:320px">Frame art002e009806 · 19:35:52.140 UTC. The line is 13.798 s after this frame.</p>
  </div>
  <div class="cue">
    <div class="micro"><i class="obs" style="width:{data["obs_pct"]:.3f}%"></i><i class="now" style="left:{100 * data["frac"](PLAYHEAD):.3f}%"></i></div>
    <svg width="11" height="7" viewBox="0 0 11 7" aria-hidden="true"><path d="M1 6 L5.5 1.5 L10 6" fill="none" stroke="#C6A36A" stroke-width="1"/></svg>
    <span>19:36:05</span>
  </div>
</div>
"""
    return SHELL.format(title="Cinematic — playback", css=CINE_CSS, body=body)


def cine_exhibit(data: dict) -> str:
    albedo = data["albedo"]
    hansen = data["hansen"]
    body = f"""
<div class="screen">
  <div style="position:absolute;top:48px;left:24px;right:24px;display:flex;justify-content:space-between">
    <div class="kicker">Exhibit</div>
    <div class="dim" style="font-size:10px;letter-spacing:0.14em">FEATURE 380</div>
  </div>
  <img class="plate" style="position:absolute;top:76px;left:0;height:220px" alt="art002e009806" src="{IMG}/art002e009806.720.webp">
  <div style="position:absolute;top:304px;left:24px;right:24px">
    <h1 class="serif" style="font-size:48px;line-height:0.92;letter-spacing:-0.03em;font-weight:400">Aristarchus</h1>
    <p class="dim" style="margin-top:6px;font-size:13px;letter-spacing:0.16em;text-transform:uppercase">Crater</p>
    <div style="margin-top:16px;display:flex;gap:22px;font-variant-numeric:tabular-nums;font-size:15px">
      <div>23.73° N</div><div>47.49° W</div>
    </div>
    <p class="dim" style="margin-top:6px;font-size:11px;line-height:1.35;max-width:320px">USGS Gazetteer of Planetary Nomenclature, feature 380. Center of the crater. Not a pixel in this frame.</p>
    <p class="serif" style="margin-top:16px;font-size:15px;line-height:1.35">{e(SCIENCE)}</p>
    <p class="dim" style="margin-top:8px;font-size:10px;line-height:1.35">{e(SCIENCE_SOURCE)}</p>
    <p class="serif" style="margin-top:16px;font-style:italic;font-size:16px;line-height:1.3">{e(hansen["text"])}</p>
    <p class="dim" style="margin-top:4px;font-size:10px;letter-spacing:0.08em">HANSEN · 19:33:23.114 UTC · PCD2</p>
    <p class="serif" style="margin-top:14px;font-style:italic;font-size:16px;line-height:1.3">{e(albedo["text"])}</p>
    <p class="dim" style="margin-top:4px;font-size:10px;letter-spacing:0.08em">WISEMAN · 19:38:52.750 UTC · PCD3</p>
    <p class="dim" style="margin-top:14px;font-size:10px;line-height:1.35">art002e009806 · 19:35:52.140 UTC · target Aristarchus Plateau · Window 2 · 400 mm</p>
    <p style="margin-top:8px;font-size:10px">{e(CREDIT)}</p>
    <p class="dim" style="margin-top:8px;font-size:10px;line-height:1.35">{e(ENDORSEMENT)}</p>
  </div>
</div>
"""
    return SHELL.format(title="Cinematic — Aristarchus", css=CINE_CSS, body=body)


def cine_panel(data: dict) -> str:
    quote = data["quote"]
    hero = data["hero"]
    body = f"""
<div class="screen">
  <img alt="{e(hero["nasa_id"])}" src="{IMG}/art002e009806.720.webp" style="position:absolute;top:64px;left:16px;width:214px;height:143px;object-fit:cover">
  <div style="position:absolute;top:214px;left:16px;width:210px">
    <div class="kicker">Now</div>
    <p class="serif" style="margin-top:6px;font-style:italic;font-size:15px;line-height:1.25">{e(quote["text"])}</p>
    <p class="dim" style="margin-top:8px;font-size:10px;line-height:1.35">Wiseman · PCD3<br>art002e009806 is the frame on the clock.</p>
  </div>
  <div class="rail">
    {vertical_rail(data)}
    <div style="position:absolute;top:8px;right:16px;font-size:8px;letter-spacing:0.16em;color:#C6A36A">UTC</div>
  </div>
  <div class="sheet">
    <div class="grab"></div>
    <div style="font-variant-numeric:tabular-nums;font-size:28px;letter-spacing:-0.03em;font-family:'Noto Serif Display',serif">19:36:05.938</div>
    <div class="dim" style="margin-top:2px;font-size:11px;letter-spacing:0.08em">UTC · MET {e(data["met_play"])}</div>
    <div class="transport">
      <div class="skip">−15s</div>
      <div class="pause" aria-label="Pause"><svg width="12" height="14" viewBox="0 0 12 14"><rect x="1" y="0" width="3" height="14" fill="#C6A36A"/><rect x="8" y="0" width="3" height="14" fill="#C6A36A"/></svg></div>
      <div class="skip">+15s</div>
    </div>
    <p class="dim" style="margin-top:14px;font-size:10px;line-height:1.4">Rate 1. The ruler is linear from 19:33:00.000 to 23:00:46.689 UTC. The observation is {data["window_seconds"]:.0f} s, the first {data["obs_pct"]:.1f}% of that length. Names sit clear of the cluster; each tick stays on its time.</p>
  </div>
</div>
"""
    return SHELL.format(title="Cinematic — timeline", css=CINE_CSS, body=body)


MISSION_CSS = r"""
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 852px; height: 393px; overflow: hidden; background: #12110E; }
body { color: #E8E2D6; font-family: "JetBrains Mono", ui-monospace, monospace; -webkit-font-smoothing: antialiased; }
.screen { position: relative; width: 852px; height: 393px; overflow: hidden; background: #12110E; }
.dim { color: #8E887C; }
.gold { color: #D4B483; }
.k { font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: #8E887C; }
.num { font-variant-numeric: tabular-nums; font-weight: 500; letter-spacing: -0.03em; }
.map { position: relative; overflow: hidden; background: #1A1814; border: 1px solid #2C2A26; }
.map img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: fill; }
.map svg { position: absolute; inset: 0; width: 100%; height: 100%; }
.cue { position: absolute; left: 48px; right: 28px; bottom: 10px; height: 18px; border-top: 1px solid #2C2A26; }
.cue i { position: absolute; top: -1px; width: 2px; height: 7px; background: #D4B483; }
.cue span { position: absolute; left: 50%; transform: translateX(-50%); top: -7px; font-size: 9px; letter-spacing: 0.18em; color: #D4B483; background: #12110E; padding: 0 8px; }
.ruler { position: relative; height: 62px; margin: 0 8px; }
.base { position: absolute; left: 0; right: 0; top: 30px; height: 1px; background: #3A362F; }
.band { position: absolute; top: 28px; height: 5px; background: rgba(212,180,131,0.45); }
.mk { position: absolute; top: 24px; width: 1px; height: 12px; background: rgba(232,226,214,0.45); }
.mk.frame { top: 18px; height: 12px; background: #D4B483; }
.mk.line { top: 30px; height: 8px; }
.mk.cab, .mk.cabmark { background: #E8E2D6; height: 16px; top: 22px; }
.mk.play { top: 12px; height: 28px; width: 2px; background: #D4B483; }
.mk.approach { top: 14px; height: 24px; width: 2px; background: #E8E2D6; }
.nm { position: absolute; width: 120px; font-size: 8px; line-height: 1.25; color: #E8E2D6; }
.nm b { display: block; color: #D4B483; font-weight: 500; }
.nm.above { top: 0; }
.nm.below { top: 40px; }
.nm.mid { transform: translateX(-50%); text-align: center; }
.nm.start { text-align: left; }
.nm.end { transform: translateX(-100%); text-align: right; }
.panel { position: absolute; left: 0; right: 0; bottom: 0; height: 214px; background: #0C0B09; border-top: 1px solid #D4B483; padding: 10px 20px 8px 48px; }
"""


def map_svg(data: dict, mark: dict | None = None) -> str:
    mark = data["play"] if mark is None else mark
    casing = "\n".join(
        f'<polyline points="{segment}" fill="none" stroke="#F7F3EB" stroke-width="16" stroke-linejoin="round" stroke-linecap="round"/>'
        for segment in data["segments"]
    )
    paths = "\n".join(
        f'<polyline points="{segment}" fill="none" stroke="#1B1814" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"/>'
        for segment in data["segments"]
    )
    mark_xy = crop_xy(mark["lon"], mark["lat"])
    begin = crop_xy(data["open"]["lon"], data["open"]["lat"])
    near = crop_xy(data["approach_state"]["lon"], data["approach_state"]["lat"])
    sites = [(23.73, -47.49, "A"), (7.39, -58.96, "R")]
    marks = []
    for lat, lon, letter in sites:
        x, y = crop_xy(lon, lat)
        marks.append(
            f'<rect x="{x - 7:.2f}" y="{y - 7:.2f}" width="14" height="14" fill="#F7F3EB" stroke="#1B1814" stroke-width="2"/>'
            f'<text x="{x + 12:.2f}" y="{y - 8:.2f}" fill="#1B1814" font-size="18" font-family="JetBrains Mono, monospace">{letter}</text>'
        )
    return f"""
<svg viewBox="0 0 1000 500" preserveAspectRatio="none">
  {casing}
  {paths}
  <circle cx="{begin[0]:.2f}" cy="{begin[1]:.2f}" r="7" fill="#F7F3EB" stroke="#1B1814" stroke-width="2"/>
  <circle cx="{near[0]:.2f}" cy="{near[1]:.2f}" r="9" fill="none" stroke="#1B1814" stroke-width="2.4"/>
  <circle cx="{mark_xy[0]:.2f}" cy="{mark_xy[1]:.2f}" r="10" fill="#D4B483" stroke="#1B1814" stroke-width="2"/>
  {"".join(marks)}
</svg>
"""


def mission_top(data: dict, state: dict, eyebrow: str, detail: str, mark: dict | None = None) -> str:
    return f"""
  <div style="position:absolute;top:14px;left:48px;right:24px;display:flex;justify-content:space-between;align-items:baseline">
    <div style="font-size:11px;letter-spacing:0.18em">ORION <span class="dim">FD06</span></div>
    <div class="dim" style="font-size:10px;letter-spacing:0.12em">{e(eyebrow)}</div>
  </div>
  <div class="map" style="position:absolute;top:40px;left:48px;width:468px;height:222px">
    <img alt="LROC color map cropped to the flyby track, SVS 4720" src="lroc-track.jpg">
    {map_svg(data, mark or state)}
  </div>
  <div style="position:absolute;top:268px;left:48px;width:470px;font-size:7.5px;line-height:1.3;color:#8E887C">{e(MAP_CREDIT)} This frame is that map cropped from 340° E to 150° E and 48° N to 42° S. Sub-observer track, Horizons quantity 14, IAU MOON_ME. Squares are USGS gazetteer centers: A Aristarchus, R Reiner Gamma. Not a window boresight.</div>
  <div style="position:absolute;top:40px;left:534px;right:24px">
    <div class="k">Range</div>
    <div class="num" style="font-size:26px;margin-top:2px">{e(km(state["rangeKm"]))}</div>
    <div style="display:flex;gap:18px;margin-top:10px">
      <div><div class="k">Altitude</div><div class="num" style="font-size:14px;margin-top:2px">{e(km(state["altitudeKm"]))}</div></div>
      <div><div class="k">Sub-lon</div><div class="num" style="font-size:14px;margin-top:2px">{e(deg(state["lon"]))}</div></div>
      <div><div class="k">Sub-lat</div><div class="num" style="font-size:14px;margin-top:2px">{e(deg(state["lat"], lat=True))}</div></div>
    </div>
    <p class="dim" style="margin-top:10px;font-size:10px;line-height:1.4">{detail}</p>
  </div>
"""


def mission_open(data: dict) -> str:
    detail = (
        f"Window opens 19:33:00.000 UTC. MET {data['met_open']}. "
        "Aristarchus Plateau to Reiner Gamma, through 19:48:30.000 UTC. "
        "First line is Wiseman at 19:33:02.700."
    )
    body = f"""
<div class="screen">
  {mission_top(data, data["open"], "19:33:00.000 UTC", detail)}
  <div style="position:absolute;left:534px;top:210px;right:24px">
    <div class="k">Closest approach</div>
    <div class="num gold" style="font-size:16px;margin-top:3px">23:00:46.689 UTC</div>
    <div class="dim" style="margin-top:3px;font-size:10px">{e(km(data["approach"]["rangeKm"]))} · altitude {e(km(data["approach"]["altitudeKm"]))}</div>
  </div>
</div>
"""
    # Opening map should mark 19:33, not the later playhead. Override by passing open as the highlighted state:
    # map_svg always draws the playback playhead. For the opening, draw the playhead at window start
    # by temporarily swapping. Handled below in a dedicated svg call — see mission_open_body.
    return SHELL.format(title="Mission — opening", css=MISSION_CSS, body=body)


def mission_play(data: dict) -> str:
    quote = data["quote"]
    detail = (
        f"MET {data['met_play']}. Showing art002e009806, 19:35:52.140 UTC, "
        "target Aristarchus Plateau. Wiseman on PCD3."
    )
    body = f"""
<div class="screen">
  {mission_top(data, data["play"], "19:36:05.938 UTC", detail)}
  <div style="position:absolute;left:534px;top:196px;right:22px">
    <div class="k">PCD3 · Wiseman · 19:36:05.938</div>
    <p style="margin-top:4px;font-size:12px;line-height:1.35;color:#E8E2D6">{e(quote["text"])}</p>
  </div>
  <div class="cue"><i style="left:{100 * data["frac"](PLAYHEAD):.3f}%"></i><span>TIMELINE</span></div>
</div>
"""
    return SHELL.format(title="Mission — playback", css=MISSION_CSS, body=body)


def mission_exhibit(data: dict) -> str:
    albedo = data["albedo"]
    hansen = data["hansen"]
    body = f"""
<div class="screen">
  <div style="position:absolute;top:16px;left:48px;right:24px;display:flex;justify-content:space-between">
    <div style="font-size:11px;letter-spacing:0.18em">ORION <span class="dim">ARISTARCHUS</span></div>
    <div class="dim" style="font-size:10px">USGS FEATURE 380</div>
  </div>
  <img alt="art002e009806" src="{IMG}/art002e009806.720.webp" style="position:absolute;top:44px;left:48px;width:360px;height:240px;object-fit:cover;border:1px solid #2C2A26">
  <div style="position:absolute;top:290px;left:48px;width:360px;display:flex;justify-content:space-between;font-size:8px" class="dim">
    <span>art002e009806 · 19:35:52.140 UTC · 400 mm · Window 2</span>
  </div>
  <div style="position:absolute;top:306px;left:48px;font-size:9px;letter-spacing:0.06em">{e(CREDIT)}</div>
  <div style="position:absolute;top:42px;left:428px;right:22px">
    <div class="k">Crater center</div>
    <div class="num" style="font-size:22px;margin-top:2px">23.73° N</div>
    <div class="num" style="font-size:22px">47.49° W</div>
    <p class="dim" style="margin-top:6px;font-size:10px;line-height:1.35">USGS Gazetteer of Planetary Nomenclature, feature 380. LTP aim for Aristarchus Plateau is a different point: 26.05° N, 309.26° E.</p>
    <p style="margin-top:8px;font-size:11px;line-height:1.35">{e(SCIENCE)}</p>
    <p class="dim" style="margin-top:4px;font-size:9px;line-height:1.35">{e(SCIENCE_SOURCE)}</p>
    <p style="margin-top:8px;font-size:11px;line-height:1.35">{e(hansen["text"])}</p>
    <p class="dim" style="font-size:9px">HANSEN 19:33:23.114 UTC PCD2</p>
    <p style="margin-top:6px;font-size:11px;line-height:1.35">{e(albedo["text"])}</p>
    <p class="dim" style="font-size:9px">WISEMAN 19:38:52.750 UTC PCD3</p>
    <p class="dim" style="margin-top:6px;font-size:9px;line-height:1.35">{e(POINTING)}</p>
    <p style="margin-top:4px;font-size:9px">{e(ENDORSEMENT)}</p>
  </div>
</div>
"""
    return SHELL.format(title="Mission — Aristarchus", css=MISSION_CSS, body=body)


def mission_panel(data: dict) -> str:
    quote = data["quote"]
    body = f"""
<div class="screen">
  <div style="position:absolute;top:12px;left:48px;right:20px;display:flex;justify-content:space-between;align-items:baseline">
    <div style="font-size:11px;letter-spacing:0.16em">ORION <span class="dim">SCRUB</span></div>
    <div class="num gold" style="font-size:16px">19:36:05.938 <span class="dim">UTC</span></div>
  </div>
  <div class="map" style="position:absolute;top:38px;left:48px;width:250px;height:118px">
    <img alt="LROC color map cropped to the flyby track, SVS 4720" src="lroc-track.jpg">
    {map_svg(data)}
  </div>
  <div style="position:absolute;top:40px;left:312px;right:18px;display:flex;gap:16px">
    <div><div class="k">Range</div><div class="num" style="font-size:16px">{e(km(data["play"]["rangeKm"]))}</div></div>
    <div><div class="k">Altitude</div><div class="num" style="font-size:16px">{e(km(data["play"]["altitudeKm"]))}</div></div>
    <div><div class="k">MET</div><div class="num" style="font-size:16px">{e(data["met_play"])}</div></div>
  </div>
  <p class="dim" style="position:absolute;top:96px;left:312px;right:18px;font-size:10px;line-height:1.35">{e(quote["text"])}<br>Wiseman · PCD3 · art002a000021</p>
  <div class="panel">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
      <div style="display:flex;gap:22px;align-items:center;font-size:12px;letter-spacing:0.12em">
        <span>−15s</span><span class="gold">PAUSE</span><span>+15s</span>
      </div>
      <div class="dim" style="font-size:10px">RATE 1</div>
    </div>
    <div class="k" style="margin:2px 8px 0">Observation · 19:33:00.000–19:48:30.000 · 930 s · linear across this width</div>
    <div class="ruler">{horizontal_marks(data, "obs")}</div>
    <div class="k" style="margin:0 8px">Whole flyby · 19:33:00.000–23:00:46.689 · {data["span"]:.1f} s · linear. Gold band is the observation, {data["obs_pct"]:.1f}% of the ruler.</div>
    <div class="ruler" style="height:48px">{horizontal_marks(data, "all")}</div>
  </div>
</div>
"""
    return SHELL.format(title="Mission — timeline", css=MISSION_CSS, body=body)


SMITH_CSS = r"""
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 393px; height: 852px; overflow: hidden; background: #E6DFD2; }
body { color: #1B1814; font-family: "Noto Serif Display", "Noto Serif", serif; -webkit-font-smoothing: antialiased; }
.screen { position: relative; width: 393px; height: 852px; overflow: hidden; background: #E6DFD2; }
.sans { font-family: Inter, "Noto Sans", sans-serif; }
.dim { color: #5C564C; }
.seal { color: #7C2F2A; }
.mat { background: #F7F3EB; border: 1px solid #1B1814; padding: 8px; }
.mat img { display: block; width: 100%; height: auto; }
.cue { position: absolute; left: 0; right: 0; bottom: 0; height: 36px; display: flex; align-items: flex-end; justify-content: center; }
.tab { background: #D9D0C2; border-top: 1px solid #1B1814; padding: 6px 16px 8px; font-family: Inter, sans-serif; font-size: 9px; letter-spacing: 0.2em; text-transform: uppercase; }
.spine-rule { position: absolute; z-index: 3; left: 28px; top: 24px; bottom: 24px; width: 1px; background: #1B1814; }
.spine-span { position: absolute; z-index: 3; left: 26px; width: 5px; background: #7C2F2A; }
.spine-tk { position: absolute; z-index: 3; left: 24px; width: 9px; height: 1px; background: rgba(27,24,20,0.45); }
.spine-ph { position: absolute; z-index: 3; left: 22px; width: 13px; height: 1px; background: #1B1814; }
.spine-play { position: absolute; z-index: 3; left: 18px; width: 18px; height: 2px; background: #7C2F2A; }
.spine-cab { position: absolute; z-index: 3; left: 27px; width: 3px; background: #1B1814; }
.ch { position: absolute; z-index: 4; left: 40px; width: 118px; }
.ch em { font-style: normal; font-family: Inter, sans-serif; font-size: 9px; letter-spacing: 0.14em; color: #7C2F2A; }
.ch b { display: block; font-weight: 400; font-size: 11px; font-variant-numeric: tabular-nums; }
.ch span { display: block; font-size: 11px; color: #5C564C; }
.sheet { position: absolute; z-index: 1; left: 0; right: 0; bottom: 0; height: 236px; background: #F7F3EB; border-top: 1px solid #1B1814; padding: 14px 20px 16px 168px; }
"""


def smith_open(data: dict) -> str:
    body = f"""
<div class="screen">
  <div style="padding:52px 28px 0">
    <div class="sans" style="font-size:10px;letter-spacing:0.22em;text-transform:uppercase">Orion Window</div>
    <div class="seal sans" style="margin-top:28px;font-size:13px;letter-spacing:0.18em">I</div>
    <h1 style="margin-top:8px;font-size:42px;line-height:0.96;font-weight:400;letter-spacing:-0.03em">Aristarchus<br>Plateau to<br>Reiner Gamma</h1>
    <p class="dim" style="margin-top:16px;font-size:15px">6 April 2026</p>
    <p style="margin-top:4px;font-size:15px;font-variant-numeric:tabular-nums">19:33:00 – 19:48:30 UTC</p>
    <p class="dim sans" style="margin-top:10px;font-size:11px;letter-spacing:0.12em;text-transform:uppercase">Wiseman · Glover · Koch · Hansen</p>
    <figure class="mat" style="margin-top:28px">
      <img alt="art002e009806" src="{IMG}/art002e009806.720.webp">
    </figure>
    <figcaption style="margin-top:10px">
      <div class="sans" style="font-size:10px;letter-spacing:0.16em;text-transform:uppercase">Fig. 1 · art002e009806</div>
      <p class="dim" style="margin-top:4px;font-size:13px;line-height:1.35">19:35:52.140 UTC · Window 2 · Nikon D5 · 400 mm<br>Target Aristarchus Plateau<br>{e(CREDIT)}</p>
    </figcaption>
  </div>
</div>
"""
    return SHELL.format(title="Smithsonian — opening", css=SMITH_CSS, body=body)


def smith_play(data: dict) -> str:
    quote = data["quote"]
    body = f"""
<div class="screen">
  <div style="padding:48px 28px 0">
    <div style="display:flex;justify-content:space-between;align-items:baseline">
      <div class="sans" style="font-size:10px;letter-spacing:0.2em;text-transform:uppercase">At the window</div>
      <div class="sans" style="font-size:11px;font-variant-numeric:tabular-nums">19:36:05.938 UTC</div>
    </div>
    <figure class="mat" style="margin-top:16px">
      <img alt="art002e009806" src="{IMG}/art002e009806.720.webp">
    </figure>
    <p class="dim sans" style="margin-top:8px;font-size:10px;letter-spacing:0.04em">Fig. 2 · art002e009806 · 19:35:52.140 UTC · {e(CREDIT)}</p>
    <p class="dim sans" style="margin-top:22px;font-size:10px;letter-spacing:0.16em;text-transform:uppercase">Wiseman · PCD3</p>
    <blockquote style="margin-top:8px;font-style:italic;font-size:28px;line-height:1.2">{e(quote["text"])}</blockquote>
    <p class="dim" style="margin-top:12px;font-size:13px">art002a000021 · 19:36:05.938 UTC</p>
  </div>
  <div class="cue"><div class="tab">Index</div></div>
</div>
"""
    return SHELL.format(title="Smithsonian — playback", css=SMITH_CSS, body=body)


def smith_exhibit(data: dict) -> str:
    albedo = data["albedo"]
    hansen = data["hansen"]
    body = f"""
<div class="screen">
  <div style="padding:40px 28px 0">
    <div class="seal sans" style="font-size:12px;letter-spacing:0.18em">II</div>
    <h1 style="margin-top:4px;font-size:46px;line-height:0.9;font-weight:400;letter-spacing:-0.03em">Aristarchus</h1>
    <p class="dim" style="margin-top:4px;font-size:15px;font-style:italic">Crater</p>
    <div style="margin-top:10px;display:flex;gap:18px;font-variant-numeric:tabular-nums;font-size:18px">
      <span>23.73° N</span><span>47.49° W</span>
    </div>
    <p class="dim" style="margin-top:4px;font-size:13px;line-height:1.3">USGS Gazetteer of Planetary Nomenclature, feature 380. The lunar targeting plan aims the plateau at 26.05° N, 309.26° E, a different point from the crater center.</p>
    <p style="margin-top:10px;font-size:15px;line-height:1.32">{e(SCIENCE)}</p>
    <p class="dim sans" style="margin-top:4px;font-size:10px;line-height:1.3;letter-spacing:0.02em">{e(SCIENCE_SOURCE)}</p>
    <figure class="mat" style="margin-top:10px;width:250px">
      <img alt="art002e009806" src="{IMG}/art002e009806.720.webp">
    </figure>
    <p class="dim" style="margin-top:6px;font-size:12px;line-height:1.3">art002e009806 · 19:35:52.140 UTC · target Aristarchus Plateau. {e(POINTING)} {e(CREDIT)}</p>
    <blockquote style="margin-top:8px;font-style:italic;font-size:15px;line-height:1.28">{e(albedo["text"])}</blockquote>
    <p class="dim sans" style="margin-top:3px;font-size:10px;letter-spacing:0.08em">WISEMAN · 19:38:52.750 UTC</p>
    <p style="margin-top:6px;font-size:14px;line-height:1.28">{e(hansen["text"])}</p>
    <p class="dim sans" style="margin-top:2px;font-size:10px;letter-spacing:0.08em">HANSEN · 19:33:23.114 UTC</p>
    <p class="dim" style="margin-top:8px;font-size:12px">{e(ENDORSEMENT)}</p>
  </div>
</div>
"""
    return SHELL.format(title="Smithsonian — Aristarchus", css=SMITH_CSS, body=body)


def smith_panel(data: dict) -> str:
    quote = data["quote"]
    body = f"""
<div class="screen">
  {spine(data)}
  <figure class="mat" style="position:absolute;top:48px;left:168px;width:200px">
    <img alt="art002e009806" src="{IMG}/art002e009806.720.webp">
  </figure>
  <p class="dim" style="position:absolute;top:196px;left:168px;width:200px;font-size:12px;line-height:1.3">art002e009806<br>19:35:52.140 UTC<br>{e(CREDIT)}</p>
  <div class="sheet">
    <div class="sans" style="font-size:9px;letter-spacing:0.18em;text-transform:uppercase;color:#7C2F2A">Index</div>
    <div style="margin-top:6px;font-variant-numeric:tabular-nums;font-size:22px">19:36:05.938</div>
    <div class="dim sans" style="font-size:10px;letter-spacing:0.06em">UTC · MET {e(data["met_play"])}</div>
    <p style="margin-top:8px;font-style:italic;font-size:13px;line-height:1.3">{e(quote["text"])}</p>
    <div class="sans" style="margin-top:12px;display:flex;justify-content:space-between;font-size:11px;letter-spacing:0.08em;text-transform:uppercase">
      <span>−15 s</span><span>Pause</span><span>+15 s</span>
    </div>
    <p class="dim sans" style="margin-top:8px;font-size:9px;line-height:1.35;letter-spacing:0.02em">Rate 1. Spine is linear, 19:33:00.000 through 23:00:46.689 UTC. Chapters I–VII are the observation; the ticks stay on the recorded times.</p>
  </div>
</div>
"""
    return SHELL.format(title="Smithsonian — timeline", css=SMITH_CSS, body=body)


def write_html(data: dict) -> list[tuple[str, str, Path]]:
    pages = {
        "cinematic": [
            ("01-opening", cine_open),
            ("02-playback", cine_play),
            ("03-aristarchus", cine_exhibit),
            ("04-timeline", cine_panel),
        ],
        "mission": [
            ("01-opening", mission_open),
            ("02-playback", mission_play),
            ("03-aristarchus", mission_exhibit),
            ("04-timeline", mission_panel),
        ],
        "smithsonian": [
            ("01-opening", smith_open),
            ("02-playback", smith_play),
            ("03-aristarchus", smith_exhibit),
            ("04-timeline", smith_panel),
        ],
    }
    written = []
    for folder, items in pages.items():
        directory = OUT / folder
        directory.mkdir(parents=True, exist_ok=True)
        for name, builder in items:
            path = directory / f"{name}.html"
            path.write_text(builder(data))
            written.append((folder, name, path))
    return written


def render(pages: list[tuple[str, str, Path]]) -> None:
    chrome = "/usr/bin/google-chrome"
    for folder, name, path in pages:
        width, height = (852, 393) if folder == "mission" else (393, 852)
        png = path.with_suffix(".png")
        subprocess.run(
            [
                chrome,
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--no-sandbox",
                "--force-device-scale-factor=3",
                f"--window-size={width},{height}",
                f"--screenshot={png}",
                path.as_uri(),
            ],
            check=True,
            capture_output=True,
        )
        print(png, png.stat().st_size)


def contact_sheets() -> None:
    from PIL import Image, ImageDraw, ImageFont

    font = ImageFont.truetype("/usr/share/fonts/truetype/inter/Inter-Medium.ttf", 42)
    labels = ["Opening", "Playback", "Aristarchus", "Timeline"]
    for folder, bg, fg in (
        ("cinematic", (5, 5, 5), (243, 239, 230)),
        ("mission", (18, 17, 14), (232, 226, 214)),
        ("smithsonian", (230, 223, 210), (27, 24, 20)),
    ):
        images = [Image.open(OUT / folder / f"{name}.png").convert("RGB") for name in ("01-opening", "02-playback", "03-aristarchus", "04-timeline")]
        gap, pad, cap = 28, 36, 72
        width = pad * 2 + gap * 3 + sum(im.width for im in images)
        height = pad + cap + max(im.height for im in images) + pad
        sheet = Image.new("RGB", (width, height), bg)
        draw = ImageDraw.Draw(sheet)
        x = pad
        for im, label in zip(images, labels):
            draw.text((x, pad), label.upper(), fill=fg, font=font)
            sheet.paste(im, (x, pad + cap))
            x += im.width + gap
        dest = OUT / folder / "contact-sheet.png"
        sheet.save(dest, optimize=True)
        print(dest, sheet.size)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    data = load()
    assert data["approach"]["iso"].startswith("2026-04-06T23:00:46"), data["approach"]["iso"]
    write_track_map()
    pages = write_html(data)
    print(f"span {data['span']:.3f}s obs {data['obs_pct']:.2f}% range {data['play']['rangeKm']:.2f}")
    if args.render:
        render(pages)
        contact_sheets()


if __name__ == "__main__":
    main()
