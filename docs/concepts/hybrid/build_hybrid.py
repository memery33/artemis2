#!/usr/bin/env python3
"""Hero hybrid: cinematic window, map only when a crater opens.

    python3 docs/concepts/hybrid/build_hybrid.py --render
    python3 docs/concepts/hybrid/build_hybrid.py --motion

Portrait iPhone 17, 393×852 CSS px, rendered at 3×.
"""

from __future__ import annotations

import argparse
import html
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build  # noqa: E402

OUT = Path(__file__).resolve().parent
IMG = "../../../demo/data/images"
MAP = "../mission/lroc-track.jpg"

CREDIT = "Credit: NASA/Artemis II Crew"
ENDORSEMENT = "This app is not affiliated with or endorsed by NASA."
SCIENCE_A = (
    "Plateau known for its volcanic diversity and the bright Aristarchus crater, "
    "looking for color, albedo, and texture variations across the plateau and surrounding mare."
)
SOURCE_A = (
    "Guide to the Artemis II Lunar Targeting Plan, NASA Science. "
    "Science and Operational Focus for Aristarchus Plateau."
)
SCIENCE_R = "Set of bright lunar swirls near highland-mare boundary. Future CLPS landing site."
SOURCE_R = (
    "Guide to the Artemis II Lunar Targeting Plan, NASA Science. "
    "Science and Operational Focus for Reiner Gamma."
)
POINTING = "Footprints are georeferenced Nikon frames, not a window boresight."
PLAYHEAD = "2026-04-06T19:36:05.938Z"
REINER_AT = "2026-04-06T19:42:45.140Z"
QUOTE = "All right, Aristarchus, very, very, very bright."
ALBEDO = "It's weird that Aristarchus is so white and albedo, but its rays are so dim, so muted."
HANSEN_A = "Plateau is known for its volcanic diversity and the bright Aristarchus Crater."
GLOVER_R = "Reiner Gamma time, Reiner Gamma."
WISEMAN_R = (
    "All right, starting the recording for Reiner Gamma, which, as Jacob taught me, "
    "is important to me because that is the background of the weekly updates."
)
HANSEN_R = "The albedo of Reiner Gamma is about a 7 compared to Aristarchus which would be about a 10"
NEXT = "Wiseman: Why does the ring from Glushko crisscross?"


def e(text: str) -> str:
    return html.escape(text, quote=True)


CSS = r"""
@font-face { font-family: Fraunces; src: url("fonts/Fraunces.ttf") format("truetype"); font-weight: 100 900; font-style: normal; }
@font-face { font-family: Fraunces; src: url("fonts/Fraunces-Italic.ttf") format("truetype"); font-weight: 100 900; font-style: italic; }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 393px; height: 852px; overflow: hidden; background: #070605; }
body { font-family: Inter, "Noto Sans", sans-serif; color: #F7F3EA; -webkit-font-smoothing: antialiased; }
.screen { position: relative; width: 393px; height: 852px; overflow: hidden; background: #070605; }
.display { font-family: Fraunces, "Noto Serif Display", serif; font-optical-sizing: auto; }
.photo { position: absolute; inset: 0; width: 393px; height: 852px; object-fit: cover; }
.bloom { position: absolute; inset: -8%; width: 116%; height: 116%; object-fit: cover; filter: blur(28px) saturate(1.15); opacity: 0.38; mix-blend-mode: screen; pointer-events: none; }
.glass { position: absolute; inset: 0; pointer-events: none; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.16), inset 0 0 90px rgba(0,0,0,0.42); background:
  radial-gradient(120% 90% at 50% 38%, transparent 42%, rgba(0,0,0,0.38) 100%),
  linear-gradient(180deg, rgba(255,255,255,0.16), rgba(255,255,255,0) 16%); }
.glass i { position: absolute; inset: 10px; border: 1px solid rgba(255,255,255,0.08); border-radius: 28px; }
.scrim { position: absolute; left: 0; right: 0; bottom: 0; height: 420px; pointer-events: none; background: linear-gradient(180deg, rgba(7,6,5,0) 0%, rgba(7,6,5,0.28) 28%, rgba(7,6,5,0.72) 68%, rgba(7,6,5,0.88) 100%); }
.island { position: absolute; z-index: 40; top: 11px; left: 133.5px; width: 126px; height: 37px; border-radius: 19px; background: #000; }
.status { position: absolute; z-index: 40; top: 18px; left: 22px; font-weight: 600; font-size: 16px; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
.home { position: absolute; z-index: 40; left: 129.5px; bottom: 8px; width: 134px; height: 5px; border-radius: 3px; background: rgba(247,243,234,0.78); }
.kicker { font-weight: 600; font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: #E6C48A; }
.dim { color: #C9C2B4; }
.cta { display: inline-flex; align-items: center; justify-content: center; height: 50px; padding: 0 28px; border-radius: 25px; background: #F7F3EA; color: #141210; font-weight: 600; font-size: 17px; letter-spacing: -0.01em; box-shadow: 0 14px 36px rgba(0,0,0,0.38); }
.cue { position: absolute; z-index: 5; left: 0; right: 0; bottom: 28px; display: flex; flex-direction: column; align-items: center; gap: 8px; }
.grab { width: 36px; height: 4px; border-radius: 2px; background: rgba(247,243,234,0.72); }
.micro { position: relative; width: 148px; height: 2px; border-radius: 1px; background: rgba(247,243,234,0.28); }
.micro b { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 1px; background: #E6C48A; }
.micro i { position: absolute; top: -3px; width: 2px; height: 8px; border-radius: 1px; background: #F7F3EA; }
.panel { position: absolute; z-index: 6; left: 0; right: 0; bottom: 0; height: 430px; padding: 14px 132px 42px 20px;
  background: linear-gradient(180deg, rgba(255,255,255,0.16), rgba(255,255,255,0.04) 18%, rgba(12,10,8,0.18)), rgba(14,12,10,0.52);
  -webkit-backdrop-filter: blur(28px) saturate(1.35); backdrop-filter: blur(28px) saturate(1.35);
  border-top: 1px solid rgba(255,255,255,0.32); box-shadow: 0 -20px 50px rgba(0,0,0,0.28); }
.rail { position: absolute; z-index: 7; top: 0; right: 0; bottom: 0; width: 128px; pointer-events: none;
  background: linear-gradient(90deg, rgba(7,6,5,0) 0%, rgba(7,6,5,0.35) 28%, rgba(7,6,5,0.55) 100%); }
.tk { position: absolute; right: 14px; height: 1px; }
.tk.line { width: 6px; background: rgba(247,243,234,0.4); }
.tk.photo { width: 12px; background: #E6C48A; }
.tk.span { width: 2px; right: 26px; background: #E6C48A; box-shadow: 0 0 8px rgba(230,196,138,0.8); }
.tk.head { width: 22px; height: 2px; right: 10px; background: #F7F3EA; box-shadow: 0 0 10px rgba(230,196,138,0.95); }
.tk.cab { width: 2px; right: 20px; background: rgba(247,243,234,0.9); }
.lb { position: absolute; right: 36px; width: 88px; text-align: right; text-shadow: 0 1px 8px rgba(0,0,0,0.7); }
.lb b, .lb span { display: block; }
.lb b { font-size: 11px; font-weight: 600; font-variant-numeric: tabular-nums; }
.lb span { font-size: 11px; color: #C9C2B4; }
.lb.now b, .lb.now span { color: #E6C48A; }
.hour { position: absolute; right: 30px; font-size: 10px; letter-spacing: 0.12em; color: rgba(247,243,234,0.55); font-variant-numeric: tabular-nums; }
.map { position: relative; overflow: hidden; background: #1a1814; border-radius: 16px;
  box-shadow: 0 24px 54px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.38), inset 0 0 0 1px rgba(255,255,255,0.2); }
.map img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
.map svg { position: absolute; inset: 0; width: 100%; height: 100%; }
.map .shade { position: absolute; inset: 0; background: radial-gradient(90% 90% at 50% 48%, transparent 46%, rgba(0,0,0,0.22) 100%); pointer-events: none; }
.shadow { text-shadow: 0 2px 22px rgba(0,0,0,0.62); }
"""

SHELL = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>{title}</title><style>{css}</style></head><body>{body}</body></html>"""


def chrome(status: str) -> str:
    return f'<div class="island"></div><div class="status">{e(status)}</div><div class="home"></div>'


def photo_layers(src: str, alt: str, position: str) -> str:
    return f"""
<img class="photo" alt="{e(alt)}" src="{src}" style="object-position:{position}">
<img class="bloom" alt="" src="{src}" style="object-position:{position}">
<div class="glass"><i></i></div>
"""


def rail(data: dict) -> str:
    frac = data["frac"]
    top, height = 64.0, 760.0

    def y(iso: str) -> float:
        return top + frac(iso) * height

    lines, frames = [], []
    start = build.parse(build.WINDOW_START)
    end = data["approach"]["moment"]
    for row in data["lines"]:
        if start <= build.parse(row["utc"]) <= end:
            lines.append(row)
    for row in data["frames"]:
        if start <= build.parse(row["utc"]) <= end and row.get("instrument") != "cab2":
            frames.append(row)
    parts = []
    for row in lines:
        parts.append(f'<i class="tk line" style="top:{y(row["utc"]):.2f}px"></i>')
    for row in frames:
        parts.append(f'<i class="tk photo" style="top:{y(row["utc"]):.2f}px"></i>')
    parts.append(
        f'<i class="tk span" style="top:{y(build.WINDOW_START):.2f}px;height:{(frac(build.WINDOW_END)-frac(build.WINDOW_START))*height:.2f}px"></i>'
    )
    parts.append(f'<i class="tk head" style="top:{y(PLAYHEAD):.2f}px"></i>')
    parts.append(
        f'<i class="tk cab" style="top:{y(build.CAB_START):.2f}px;height:{(frac("2026-04-06T22:44:33.000Z")-frac(build.CAB_START))*height:.2f}px"></i>'
    )
    early = [
        (build.WINDOW_START, "19:33:00", "Opens"),
        ("2026-04-06T19:33:02.700Z", "19:33:02", "Aristarchus"),
        ("2026-04-06T19:35:52.140Z", "19:35:52", "009806"),
        (PLAYHEAD, "19:36:05", "Wiseman"),
        ("2026-04-06T19:38:52.750Z", "19:38:52", "Albedo"),
        ("2026-04-06T19:40:57.609Z", "19:40:57", "Reiner Gamma"),
        (build.WINDOW_END, "19:48:30", "Closes"),
    ]
    cursor = 148.0
    for iso, when, name in early:
        tick = y(iso)
        label = max(tick, cursor)
        klass = "lb now" if iso == PLAYHEAD else "lb"
        parts.append(f'<div class="{klass}" style="top:{label:.2f}px"><b>{when}</b><span>{e(name)}</span></div>')
        cursor = label + 40.0
    parts.append('<i style="position:absolute;right:14px;top:64px;bottom:36px;width:1px;background:rgba(247,243,234,0.32)"></i>')
    knot = y(build.WINDOW_START) + (frac(build.WINDOW_END) - frac(build.WINDOW_START)) * height * 0.5
    foot = cursor - 28.0
    drop = foot - knot
    parts.append(
        f'<svg style="position:absolute;right:14px;top:{knot:.1f}px;width:18px;height:{drop:.1f}px" '
        f'viewBox="0 0 18 {drop:.1f}" preserveAspectRatio="none">'
        f'<path d="M18 0 H7 V{drop:.1f}" stroke="rgba(230,196,138,0.9)" fill="none" stroke-width="1.25" vector-effect="non-scaling-stroke"/></svg>'
    )
    for iso, when, name in (
        (build.CAB_START, "22:36:03", "Cab Cam 2"),
        (data["approach"]["iso"], "23:00:46", "Closest"),
    ):
        parts.append(f'<div class="lb" style="top:{y(iso)-16:.2f}px"><b>{when}</b><span>{e(name)}</span></div>')
    for hour in (20, 21, 22):
        iso = f"2026-04-06T{hour:02d}:00:00.000Z"
        yy = y(iso)
        if 470 < yy < 700:
            parts.append(f'<div class="hour" style="top:{yy:.2f}px">{hour:02d}:00</div>')
    return "\n".join(parts)


def map_svg(data: dict, mark: dict, emphasis: str) -> str:
    casing = "\n".join(
        f'<polyline points="{seg}" fill="none" stroke="#F7F3EA" stroke-width="26" stroke-linejoin="round" stroke-linecap="round"/>'
        for seg in data["segments"]
    )
    ink = "\n".join(
        f'<polyline points="{seg}" fill="none" stroke="#1C1916" stroke-width="11" stroke-linejoin="round" stroke-linecap="round"/>'
        for seg in data["segments"]
    )
    marks = []
    for letter, lat, lon in (("A", 23.73, -47.49), ("R", 7.39, -58.96)):
        x, y = build.crop_xy(lon, lat)
        hot = letter == emphasis
        size = 48 if hot else 28
        font = 26 if hot else 18
        fill = "#F7F3EA" if hot else "rgba(247,243,234,0.88)"
        marks.append(
            f'<rect x="{x - size / 2:.1f}" y="{y - size / 2:.1f}" width="{size}" height="{size}" fill="{fill}" stroke="#1C1916" stroke-width="4"/>'
            f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="middle" dominant-baseline="central" fill="#1C1916" '
            f'font-family="Inter, sans-serif" font-size="{font}" font-weight="650">{letter}</text>'
        )
    gold = build.crop_xy(mark["lon"], mark["lat"])
    near = build.crop_xy(data["approach_state"]["lon"], data["approach_state"]["lat"])
    return f"""<svg viewBox="0 0 1000 500" preserveAspectRatio="xMidYMid slice">{casing}{ink}
<circle cx="{near[0]:.1f}" cy="{near[1]:.1f}" r="16" fill="none" stroke="#1C1916" stroke-width="9"/>
<circle cx="{near[0]:.1f}" cy="{near[1]:.1f}" r="16" fill="none" stroke="#F7F3EA" stroke-width="3"/>
<circle cx="{gold[0]:.1f}" cy="{gold[1]:.1f}" r="16" fill="#E6C48A" stroke="#1C1916" stroke-width="4"/>
{''.join(marks)}</svg>"""


def opening() -> str:
    body = f"""
<div class="screen">
  {photo_layers(f"{IMG}/art002e041348.720.webp", "art002e041348, the Moon through Cab Cam 2", "34% 42%")}
  <div class="scrim"></div>
  <div style="position:absolute;z-index:4;left:20px;right:20px;top:72px;display:flex;justify-content:space-between;align-items:baseline">
    <div class="kicker">Orion Window</div>
    <div class="dim" style="font-size:13px">6 April 2026</div>
  </div>
  <div style="position:absolute;z-index:4;left:20px;right:20px;bottom:108px">
    <h1 class="display shadow" style="font-weight:460;font-size:52px;line-height:0.92;letter-spacing:-0.03em;font-variation-settings:'opsz' 144, 'SOFT' 30, 'wght' 460">Aristarchus<br>Plateau to<br>Reiner Gamma</h1>
    <p style="margin-top:16px;font-size:15px;font-variant-numeric:tabular-nums">19:33:00 UTC <span class="dim">· 15 min 30 s</span></p>
    <p class="dim" style="margin-top:10px;font-size:13px;line-height:1.35">art002e041348 · 22:36:03 UTC<br>Cab Cam 2 · Window 3 · {e(CREDIT)}</p>
    <div style="margin-top:28px"><div class="cta">Begin Flyby</div></div>
  </div>
  {chrome("19:33")}
</div>"""
    return SHELL.format(title="Hybrid — opening", css=CSS, body=body)


def playback(data: dict) -> str:
    body = f"""
<div class="screen">
  {photo_layers(f"{IMG}/art002e009806.720.webp", "art002e009806", "61% 46%")}
  <div class="scrim"></div>
  <div style="position:absolute;z-index:4;left:20px;right:24px;bottom:78px">
    <div class="kicker">Wiseman · PCD3</div>
    <p class="display shadow" style="margin-top:8px;font-style:italic;font-weight:420;font-size:30px;line-height:1.16;letter-spacing:-0.02em;font-variation-settings:'opsz' 144, 'SOFT' 20, 'wght' 420">{e(QUOTE)}</p>
    <p style="margin-top:12px;font-size:13px;font-variant-numeric:tabular-nums">19:36:05.938 UTC</p>
    <p class="dim" style="margin-top:6px;font-size:12px;line-height:1.35">art002e009806 · 19:35:52.140 UTC · 400 mm<br>{e(CREDIT)}</p>
  </div>
  <div class="cue">
    <div class="micro"><b style="width:{data['obs_pct']:.3f}%"></b><i style="left:{100*data['frac'](PLAYHEAD):.3f}%"></i></div>
    <div class="grab"></div>
  </div>
  {chrome("19:36")}
</div>"""
    return SHELL.format(title="Hybrid — playback", css=CSS, body=body)


def panel(data: dict) -> str:
    body = f"""
<div class="screen">
  {photo_layers(f"{IMG}/art002e009806.720.webp", "art002e009806", "61% 46%")}
  <div class="panel">
    <div class="grab" style="margin:2px auto 16px"></div>
    <div style="font-size:32px;font-weight:560;letter-spacing:-0.03em;font-variant-numeric:tabular-nums">19:36:05.938</div>
    <div class="dim" style="margin-top:2px;font-size:13px">UTC · MET {e(data['met_play'])}</div>
    <div style="margin-top:22px;display:flex;align-items:center;justify-content:space-between;max-width:220px">
      <div style="font-size:15px;font-weight:600;letter-spacing:0.04em">−15s</div>
      <div style="width:56px;height:56px;border-radius:28px;border:1px solid rgba(230,196,138,0.9);display:grid;place-items:center;background:rgba(247,243,234,0.08)">
        <svg width="14" height="16" viewBox="0 0 14 16" aria-label="Pause"><rect x="1" y="0" width="3.5" height="16" rx="0.5" fill="#F7F3EA"/><rect x="9.5" y="0" width="3.5" height="16" rx="0.5" fill="#F7F3EA"/></svg>
      </div>
      <div style="font-size:15px;font-weight:600;letter-spacing:0.04em">+15s</div>
    </div>
    <p class="display" style="margin-top:18px;font-style:italic;font-size:15px;line-height:1.3;font-variation-settings:'opsz' 48, 'wght' 420">{e(QUOTE)}</p>
    <p class="dim" style="margin-top:10px;font-size:11px;line-height:1.4">Rate 1. Linear from 19:33:00.000 to 23:00:46.689 UTC. The bright segment is the observation, {data['window_seconds']:.0f} s, the first {data['obs_pct']:.1f}%.</p>
  </div>
  <div class="rail">{rail(data)}</div>
  {chrome("19:36")}
</div>"""
    return SHELL.format(title="Hybrid — panel", css=CSS, body=body)


def crater(data: dict, *, kind: str) -> str:
    if kind == "aristarchus":
        moment = PLAYHEAD
        status = "19:36"
        photo = "art002e009806.720.webp"
        position = "61% 40%"
        emphasis = "A"
        name = "Aristarchus"
        kicker_label = "Crater · feature 380"
        coords = "23.73° N · 47.49° W"
        gazetteer = (
            "USGS Gazetteer of Planetary Nomenclature, feature 380, crater center. "
            "The targeting plan aims the plateau at 26.05° N, 309.26° E. " + POINTING
        )
        science, source = SCIENCE_A, SOURCE_A
        quote, who = ALBEDO, "Wiseman · 19:38:52.750 UTC"
        other, other_who = HANSEN_A, "Hansen · 19:33:23.114 UTC"
        extra, extra_who = "", ""
        frame = "art002e009806 · 19:35:52.140 UTC · Window 2 · 400 mm"
        state = data["play"]
        title = "Hybrid — Aristarchus"
    else:
        moment = REINER_AT
        status = "19:42"
        photo = "art002e009951.720.webp"
        position = "58% 42%"
        emphasis = "R"
        name = "Reiner Gamma"
        kicker_label = "Albedo feature · 4987"
        coords = "7.39° N · 58.96° W"
        gazetteer = (
            "USGS Gazetteer of Planetary Nomenclature, feature 4987, albedo feature. "
            "The targeting plan aims Reiner Gamma at 7.2° N, 301.64° E. " + POINTING
        )
        science, source = SCIENCE_R, SOURCE_R
        quote, who = WISEMAN_R, "Wiseman · 19:42:18.035 UTC"
        other, other_who = HANSEN_R, "Hansen · 19:47:51.925 UTC"
        extra, extra_who = GLOVER_R, "Glover · 19:40:57.609 UTC"
        frame = "art002e009951 · 19:42:45.140 UTC · Window 2 · 400 mm"
        state = build.interp(data["samples"], build.parse(moment))
        title = "Hybrid — Reiner Gamma"
    mark = state
    body = f"""
<div class="screen">
  <img class="photo" alt="{e(frame)}" src="{IMG}/{photo}" style="object-position:{position};height:400px">
  <img class="bloom" alt="" src="{IMG}/{photo}" style="object-position:{position};height:440px">
  <div class="glass" style="height:400px;-webkit-mask-image:linear-gradient(#000 55%, transparent);mask-image:linear-gradient(#000 55%, transparent)"><i></i></div>
  <div style="position:absolute;left:0;right:0;top:150px;height:230px;background:linear-gradient(180deg, rgba(7,6,5,0), #070605 78%);pointer-events:none"></div>
  <div class="map" style="position:absolute;left:20px;right:20px;top:196px;height:168px">
    <img alt="" src="{MAP}">
    {map_svg(data, state, emphasis)}
    <div class="shade"></div>
    <div style="position:absolute;z-index:2;top:8px;right:8px;padding:7px 9px 8px;border-radius:10px;background:rgba(12,10,8,0.78)">
      <div class="kicker" style="font-size:9px">Orion</div>
      <div style="margin-top:3px;font-size:12px;font-weight:600;font-variant-numeric:tabular-nums">{e(build.km(state["rangeKm"]))}</div>
      <div class="dim" style="margin-top:1px;font-size:11px;font-variant-numeric:tabular-nums">alt {e(build.km(state["altitudeKm"]))}</div>
    </div>
  </div>
  <div style="position:absolute;left:20px;right:20px;top:376px">
    <div class="kicker">{e(kicker_label)}</div>
    <h2 class="display" style="margin-top:4px;font-size:36px;font-weight:520;line-height:1;letter-spacing:-0.03em;font-variation-settings:'opsz' 72, 'SOFT' 20, 'wght' 520">{e(name)}</h2>
    <p style="margin-top:4px;font-size:15px;line-height:1.2;font-variant-numeric:tabular-nums">{e(coords)}</p>
    <div style="margin-top:10px;display:flex;gap:14px;align-items:center;font-size:11px;color:#C9C2B4">
      <span style="display:inline-flex;align-items:center;gap:6px"><i style="width:8px;height:8px;background:#F7F3EA;display:block"></i>Gazetteer</span>
      <span style="display:inline-flex;align-items:center;gap:6px"><i style="width:8px;height:8px;border-radius:4px;background:#E6C48A;display:block"></i>Orion</span>
      <span style="display:inline-flex;align-items:center;gap:6px"><i style="width:8px;height:8px;border-radius:4px;box-shadow:inset 0 0 0 1.5px #F7F3EA;display:block"></i>Closest</span>
    </div>
    <p class="dim" style="margin-top:10px;font-size:12px;line-height:1.35">{e(gazetteer)}</p>
    <p style="margin-top:10px;font-size:15px;line-height:1.35">{e(science)}</p>
    <p class="dim" style="margin-top:4px;font-size:11px;line-height:1.3">{e(source)}</p>
    <p class="display" style="margin-top:12px;font-style:italic;font-size:16px;line-height:1.3;font-variation-settings:'opsz' 36, 'SOFT' 30, 'wght' 440">{e(quote)}</p>
    <p class="dim" style="margin-top:4px;font-size:11px;letter-spacing:0.08em;text-transform:uppercase">{e(who)}</p>
    <p class="dim" style="margin-top:12px;font-size:11px;line-height:1.35">{e(frame)}<br>{e(CREDIT)}<br>{e(ENDORSEMENT)}</p>
  </div>
  {chrome(status)}
</div>"""
    return SHELL.format(title=title, css=CSS, body=body)


def lockscreen(data: dict) -> str:
    progress = 185.938 / 930.0 * 100.0
    body = f"""
<div class="screen">
  <img class="photo" alt="" src="{IMG}/art002e009806.720.webp" style="object-position:61% 40%;filter:brightness(0.55) saturate(0.9)">
  <div class="glass"><i></i></div>
  <div style="position:absolute;z-index:4;left:24px;top:78px">
    <div style="font-size:17px;font-weight:560">Monday, April 6</div>
    <div class="display" style="margin-top:2px;font-size:92px;line-height:0.86;font-weight:340;letter-spacing:-0.045em;font-variation-settings:'opsz' 144, 'SOFT' 40, 'wght' 340">19:36</div>
  </div>
  <div style="position:absolute;z-index:4;left:16px;right:16px;bottom:118px;padding:16px 16px 14px;border-radius:24px;background:rgba(16,14,12,0.58);border:1px solid rgba(255,255,255,0.18);-webkit-backdrop-filter:blur(24px) saturate(1.3);backdrop-filter:blur(24px) saturate(1.3);box-shadow:0 16px 40px rgba(0,0,0,0.35)">
    <div class="display" style="font-size:20px;font-weight:520;letter-spacing:-0.02em;font-variation-settings:'opsz' 48, 'wght' 520">Orion Window</div>
    <div style="margin-top:12px;height:5px;border-radius:3px;background:rgba(247,243,234,0.38)"><div style="width:{progress:.2f}%;height:100%;border-radius:3px;background:#F7F3EA;box-shadow:0 0 12px rgba(230,196,138,0.85)"></div></div>
    <p style="margin-top:10px;font-size:15px;line-height:1.3">{e(NEXT)}</p>
    <div style="margin-top:10px;display:flex;justify-content:space-between;align-items:baseline;font-size:13px">
      <span style="font-weight:600">Wiseman</span>
      <span class="dim" style="font-variant-numeric:tabular-nums">at 19:36:05 UTC</span>
    </div>
  </div>
  <div style="position:absolute;z-index:4;left:36px;bottom:54px;width:50px;height:50px;border-radius:25px;background:rgba(247,243,234,0.16);border:1px solid rgba(255,255,255,0.22);display:grid;place-items:center;-webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px)">
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M9 1.5 V8" stroke="#F7F3EA" stroke-width="1.4" stroke-linecap="round"/><path d="M5.5 8.5 h7 l-1.2 6.2 a2 2 0 0 1 -2 1.6 h-0.6 a2 2 0 0 1 -2 -1.6 Z" fill="none" stroke="#F7F3EA" stroke-width="1.3"/></svg>
  </div>
  <div style="position:absolute;z-index:4;right:36px;bottom:54px;width:50px;height:50px;border-radius:25px;background:rgba(247,243,234,0.16);border:1px solid rgba(255,255,255,0.22);display:grid;place-items:center;-webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px)">
    <svg width="20" height="16" viewBox="0 0 20 16" aria-hidden="true"><rect x="1" y="3" width="13" height="11" rx="2" fill="none" stroke="#F7F3EA" stroke-width="1.3"/><path d="M14 6.5 L18.5 4 V12 L14 9.5 Z" fill="none" stroke="#F7F3EA" stroke-width="1.3" stroke-linejoin="round"/></svg>
  </div>
  {chrome("19:36")}
</div>"""
    return SHELL.format(title="Hybrid — Lock Screen", css=CSS, body=body)


def motion_page(data: dict) -> str:
    progress_obs = data["obs_pct"]
    play = 100 * data["frac"](PLAYHEAD)
    body = f"""
<div class="screen" id="stage">
  <img class="photo" id="still" alt="" src="{IMG}/art002e009806.720.webp" style="object-position:61% 42%">
  <img class="bloom" id="bloom" alt="" src="{IMG}/art002e009806.720.webp" style="object-position:61% 42%">
  <div class="glass" id="glass"><i></i></div>
  <div class="scrim" id="scrim"></div>
  <div id="caption" style="position:absolute;z-index:4;left:20px;right:24px;bottom:92px">
    <div class="kicker">Wiseman · PCD3</div>
    <p class="display" style="margin-top:8px;font-style:italic;font-size:28px;line-height:1.15;font-variation-settings:'opsz' 144, 'SOFT' 20, 'wght' 420">{e(QUOTE)}</p>
    <p style="margin-top:10px;font-size:13px;font-variant-numeric:tabular-nums">19:36:05.938 UTC</p>
  </div>
  <div class="cue" id="cue">
    <div class="micro"><b style="width:{progress_obs:.3f}%"></b><i style="left:{play:.3f}%"></i></div>
    <div class="grab"></div>
  </div>
  <div class="panel" id="panel" style="transform:translateY(100%)">
    <div class="grab" style="margin:2px auto 14px"></div>
    <div style="font-size:30px;font-weight:560;letter-spacing:-0.03em;font-variant-numeric:tabular-nums">19:36:05.938</div>
    <div class="dim" style="margin-top:2px;font-size:13px">UTC · MET {e(data['met_play'])}</div>
    <div style="margin-top:18px;display:flex;align-items:center;justify-content:space-between;max-width:210px">
      <div style="font-weight:600">−15s</div>
      <div style="width:52px;height:52px;border-radius:26px;border:1px solid #E6C48A;display:grid;place-items:center"><svg width="12" height="14" viewBox="0 0 12 14"><rect x="1" y="0" width="3" height="14" fill="#F7F3EA"/><rect x="8" y="0" width="3" height="14" fill="#F7F3EA"/></svg></div>
      <div style="font-weight:600">+15s</div>
    </div>
  </div>
  <div class="rail" id="rail" style="opacity:0">{rail(data)}</div>
  <div id="crater" style="position:absolute;z-index:8;inset:0;opacity:0;background:#070605">
    <img class="photo" alt="" src="{IMG}/art002e009806.720.webp" style="object-position:61% 38%;height:400px">
    <div class="glass" style="height:400px;-webkit-mask-image:linear-gradient(#000 55%, transparent);mask-image:linear-gradient(#000 55%, transparent)"><i></i></div>
    <div style="position:absolute;left:0;right:0;top:150px;height:230px;background:linear-gradient(180deg, rgba(7,6,5,0), #070605 78%)"></div>
    <div class="map" style="position:absolute;left:20px;right:20px;top:196px;height:168px">
      <img alt="" src="{MAP}">{map_svg(data, data["play"], "A")}
    </div>
    <div style="position:absolute;left:20px;right:20px;top:380px">
      <div class="kicker">Crater · feature 380</div>
      <div class="display" style="margin-top:4px;font-size:36px;line-height:1;letter-spacing:-0.03em;font-variation-settings:'opsz' 72, 'wght' 520">Aristarchus</div>
      <p style="margin-top:6px;font-size:15px;font-variant-numeric:tabular-nums">23.73° N · 47.49° W</p>
      <p class="display" style="margin-top:14px;font-style:italic;font-size:16px;line-height:1.3;font-variation-settings:'opsz' 36, 'wght' 440">{e(ALBEDO)}</p>
    </div>
  </div>
  {chrome("19:36")}
</div>
<script>
function ease(u) {{ return 1 - Math.pow(1 - Math.min(1, Math.max(0, u)), 3); }}
function apply(ms) {{
  const t = ms / 1000;
  const panel = document.getElementById('panel');
  const rail = document.getElementById('rail');
  const cue = document.getElementById('cue');
  const caption = document.getElementById('caption');
  const crater = document.getElementById('crater');
  const still = document.getElementById('still');
  let open = 0;
  if (t >= 1.3 && t < 3.1) open = ease((t - 1.3) / 1.8);
  else if (t >= 3.1 && t < 4.4) open = 1;
  else if (t >= 4.4 && t < 5.3) open = 1 - ease((t - 4.4) / 0.9);
  let mapIn = 0;
  if (t >= 4.6 && t < 7.0) mapIn = ease((t - 4.6) / 2.4);
  else if (t >= 7.0) mapIn = 1;
  panel.style.transform = 'translateY(' + ((1 - open) * 100) + '%)';
  const cover = Math.min(1, mapIn * 2.5);
  rail.style.opacity = String(open * (1 - cover));
  cue.style.opacity = String((1 - open) * (1 - cover));
  caption.style.opacity = String((1 - Math.min(1, open * 1.2)) * (1 - cover));
  crater.style.opacity = String(mapIn);
  crater.style.transform = 'translateY(' + ((1 - mapIn) * 28) + 'px)';
  still.style.opacity = String(1 - mapIn);
  document.getElementById('glass').style.opacity = String(1 - mapIn);
  document.getElementById('bloom').style.opacity = String(0.38 * (1 - mapIn));
  document.getElementById('scrim').style.opacity = String(1 - mapIn);
  return true;
}}
</script>
"""
    return SHELL.format(title="Hybrid — motion", css=CSS, body=body)


def write_pages(data: dict) -> list[tuple[str, Path, int, int]]:
    pages = {
        "01-opening": opening(),
        "02-playback": playback(data),
        "03-panel": panel(data),
        "04-aristarchus": crater(data, kind="aristarchus"),
        "05-reiner": crater(data, kind="reiner"),
        "06-lock-screen": lockscreen(data),
        "motion": motion_page(data),
    }
    written = []
    for name, html_text in pages.items():
        path = OUT / f"{name}.html"
        path.write_text(html_text)
        written.append((name, path, 393, 852))
    return written


def render(pages: list[tuple[str, Path, int, int]]) -> None:
    chrome = "/usr/bin/google-chrome"
    for name, path, width, height in pages:
        if name == "motion":
            continue
        png = path.with_suffix(".png")
        subprocess.run(
            [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-sandbox",
             "--force-device-scale-factor=3", f"--window-size={width},{height}",
             f"--screenshot={png}", path.as_uri()],
            check=True, capture_output=True,
        )
        print(png.name, png.stat().st_size)


def contact() -> None:
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype("/usr/share/fonts/truetype/inter/Inter-Medium.ttf", 36)
    names = [
        ("01-opening", "Opening"),
        ("02-playback", "Playback"),
        ("03-panel", "Controls"),
        ("04-aristarchus", "Aristarchus"),
        ("05-reiner", "Reiner Gamma"),
        ("06-lock-screen", "Lock Screen"),
    ]
    images = [(Image.open(OUT / f"{n}.png").convert("RGB"), label) for n, label in names]
    gap, pad, cap = 24, 32, 64
    cols = 3
    cell_w = images[0][0].width
    cell_h = images[0][0].height
    width = pad * 2 + gap * (cols - 1) + cell_w * cols
    rows = 2
    height = pad * 2 + cap * rows + gap * (rows - 1) + cell_h * rows
    sheet = Image.new("RGB", (width, height), (7, 6, 5))
    draw = ImageDraw.Draw(sheet)
    for i, (im, label) in enumerate(images):
        c, r = i % cols, i // cols
        x = pad + c * (cell_w + gap)
        y = pad + r * (cell_h + cap + gap)
        draw.text((x, y), label.upper(), fill=(247, 243, 234), font=font)
        sheet.paste(im, (x, y + cap))
    dest = OUT / "contact-sheet.png"
    sheet.save(dest, optimize=True)
    print(dest, sheet.size)


def audit() -> None:
    from PIL import Image
    for name in ("01-opening", "02-playback", "03-panel", "04-aristarchus", "05-reiner", "06-lock-screen"):
        image = Image.open(OUT / f"{name}.png").convert("RGB")
        width, height = image.size
        pixels = image.load()
        lowest = 0
        for y in range(height - 1, -1, -1):
            hit = False
            for x in range(0, width, 3):
                r, g, b = pixels[x, y]
                if r + g + b > 70:
                    # Home indicator sits in the bottom center.
                    if y > height - 50 and 360 < x < 820:
                        continue
                    hit = True
                    break
            if hit:
                lowest = y
                break
        print(f"{name} {width}x{height} lowest-ink {lowest} ({lowest / 3:.0f} css)")


def capture_motion() -> None:
    import asyncio
    import base64
    import json
    import time
    import urllib.request

    import websockets

    port = 9333
    chrome_bin = "/usr/bin/google-chrome"
    proc = subprocess.Popen(
        [
            chrome_bin, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-sandbox",
            f"--remote-debugging-port={port}", "--remote-allow-origins=*",
            "--window-size=393,852", "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        page = None
        for _ in range(60):
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=0.5) as resp:
                    targets = json.load(resp)
                page = next(row for row in targets if row.get("type") == "page")
                break
            except Exception:
                time.sleep(0.2)
        if page is None:
            raise RuntimeError("Chrome did not open a page target")
        asyncio.run(_record(page["webSocketDebuggerUrl"]))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


async def _record(ws_url: str) -> None:
    import base64
    import json
    from pathlib import Path as Fs

    import websockets

    frames = Fs("/tmp/hybrid-frames")
    if frames.exists():
        for old in frames.glob("*.png"):
            old.unlink()
    frames.mkdir(parents=True, exist_ok=True)
    fps = 15
    duration = 8.4
    count = int(duration * fps)
    async with websockets.connect(ws_url, max_size=80 * 1024 * 1024) as ws:
        seq = 0

        async def call(method: str, params: dict | None = None) -> dict:
            nonlocal seq
            seq += 1
            await ws.send(json.dumps({"id": seq, "method": method, "params": params or {}}))
            while True:
                message = json.loads(await ws.recv())
                if message.get("id") == seq:
                    if "error" in message:
                        raise RuntimeError(message["error"])
                    return message.get("result") or {}

        await call("Page.enable")
        await call("Runtime.enable")
        await call("Emulation.setDeviceMetricsOverride", {
            "width": 393,
            "height": 852,
            "deviceScaleFactor": 1,
            "mobile": True,
        })
        await call("Page.navigate", {"url": (OUT / "motion.html").as_uri()})
        await call("Runtime.evaluate", {
            "expression": "document.fonts.ready.then(() => true)",
            "awaitPromise": True,
        })
        clip = {"x": 0, "y": 0, "width": 393, "height": 852, "scale": 3}
        for index in range(count):
            await call("Runtime.evaluate", {
                "expression": f"apply({index / fps * 1000:.1f})",
            })
            shot = await call("Page.captureScreenshot", {"format": "png", "clip": clip})
            (frames / f"{index:04d}.png").write_bytes(base64.b64decode(shot["data"]))
            if index % 15 == 0:
                print("frame", index)
    probe = Fs("/tmp/hybrid-frames/0000.png")
    from PIL import Image
    width, height = Image.open(probe).size
    crop = f"crop={width - (width % 2)}:{height - (height % 2)}:0:0"
    dest = OUT / "motion.mp4"
    subprocess.run(
        [
            "/usr/bin/ffmpeg", "-y", "-framerate", str(fps),
            "-i", str(frames / "%04d.png"),
            "-vf", f"{crop},format=yuv420p",
            "-c:v", "libx264", "-preset", "slow", "-crf", "18",
            "-movflags", "+faststart", str(dest),
        ],
        check=True,
        capture_output=True,
    )
    print(dest, dest.stat().st_size, f"{width}x{height}", f"{duration:.1f}s")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--motion", action="store_true")
    args = parser.parse_args()
    data = build.load()
    assert data["quote"]["text"] == QUOTE
    assert data["albedo"]["text"] == ALBEDO
    assert data["hansen"]["text"] == HANSEN_A
    assert data["reiner"]["text"] == GLOVER_R
    if not (ROOT / "docs/concepts/mission/lroc-track.jpg").exists():
        build.write_track_map()
    pages = write_pages(data)
    if args.render:
        render(pages)
        contact()
        audit()
    if args.motion:
        capture_motion()


if __name__ == "__main__":
    main()
