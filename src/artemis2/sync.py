"""One UTC timeline for a window: audio segments, transcript lines, images."""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta

from artemis2.timebase import format_utc, parse_utc


def parse_offsets(text: str | None) -> dict[str, float]:
    """``nkd5015=+0.5,nkz9019=-1`` → seconds added to that camera's timestamps."""
    offsets: dict[str, float] = {}
    if not text:
        return offsets
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise ValueError(f"camera offset {part!r} needs instrument=+seconds")
        instrument, value = part.split("=", 1)
        offsets[instrument.strip().lower()] = float(value)
    return offsets


def build_timeline(
    db_path: str,
    start: str,
    end: str,
    camera_offsets: dict[str, float] | None = None,
) -> dict:
    start_dt, start_status = parse_utc(start)
    end_dt, end_status = parse_utc(end)
    if start_status != "ok" or end_status != "ok" or start_dt is None or end_dt is None:
        raise ValueError(f"window bounds must be full UTC instants, got {start!r} {end!r}")
    offsets = {key.lower(): value for key, value in (camera_offsets or {}).items()}
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    segments = []
    for row in conn.execute("SELECT * FROM audio WHERE exact_start != '' OR label_start != ''"):
        seg_start = _dt(row["exact_start"] or row["label_start"])
        if row["exact_duration_s"]:
            seg_end = seg_start + timedelta(seconds=float(row["exact_duration_s"]))
        elif row["label_stop"]:
            seg_end = _dt(row["label_stop"])
        elif row["label_duration_s"]:
            seg_end = seg_start + timedelta(seconds=float(row["label_duration_s"]))
        else:
            continue
        if seg_end <= start_dt or seg_start >= end_dt:
            continue
        segments.append(
            {
                "nasa_id": row["nasa_id"],
                "instrument": row["instrument"],
                "track": _track(row["instrument"]),
                "exact_start": format_utc(seg_start),
                "exact_end": format_utc(seg_end),
                "label_start": row["label_start"],
                "create_utc": row["create_utc"],
                "exact_duration_s": row["exact_duration_s"],
                "activity_id": row["activity_id"],
                "target_id": row["target_id"],
                "media_path": row["media_path"],
                "timing": "exact" if row["exact_start"] else "label",
            }
        )
    segments.sort(key=lambda item: item["exact_start"])

    lines = []
    for row in conn.execute(
        "SELECT * FROM transcript_lines WHERE utc_status = 'ok' AND utc != '' ORDER BY utc"
    ):
        instant = _dt(row["utc"])
        if instant < start_dt or instant > end_dt:
            continue
        lines.append(
            {
                "utc": format_utc(instant),
                "speaker": row["speaker"],
                "role": row["role"],
                "speaker_raw": row["speaker_raw"],
                "text": row["text"],
                "nasa_id": row["nasa_id"],
                "instrument": row["instrument"],
                "track": _track(row["instrument"]),
            }
        )

    frames = []
    for row in conn.execute("SELECT * FROM images WHERE start_utc != '' ORDER BY start_utc"):
        instant = _dt(row["start_utc"])
        offset = offsets.get((row["instrument"] or "").lower(), 0.0)
        adjusted = instant + timedelta(seconds=offset)
        if adjusted < start_dt or adjusted > end_dt:
            continue
        footprint = json.loads(row["footprint_json"] or "[]")
        frames.append(
            {
                "utc": format_utc(instant),
                "adjusted_utc": format_utc(adjusted),
                "offset_s": offset,
                "nasa_id": row["nasa_id"],
                "instrument": row["instrument"],
                "activity_id": row["activity_id"],
                "target_id": row["target_id"],
                "secondary_targets": [part for part in (row["secondary_targets"] or "").split("|") if part],
                "focal_length_mm": row["focal_length_mm"],
                "has_geometry": bool(row["has_geometry"]),
                "axis_swapped": None if row["axis_swapped"] is None else bool(row["axis_swapped"]),
                "footprint_trust": row["footprint_trust"],
                "footprint": footprint,
                "lines": row["lines"],
                "samples": row["samples"],
            }
        )

    pairs = _nearest_pairs(lines, frames)
    conn.close()
    return {
        "start": format_utc(start_dt),
        "end": format_utc(end_dt),
        "camera_offsets_s": offsets,
        "audio": segments,
        "lines": lines,
        "images": frames,
        "nearest_pairs": pairs,
    }


def clip_to_window(start: datetime, end: datetime, win_start: datetime, win_end: datetime) -> dict | None:
    """Intersection of a recording with the demo window, as a file offset."""
    left = max(start, win_start)
    right = min(end, win_end)
    if right <= left:
        return None
    return {
        "offset_s": (left - start).total_seconds(),
        "duration_s": (right - left).total_seconds(),
        "start": left,
        "end": right,
    }


def _nearest_pairs(lines: list[dict], frames: list[dict], limit: int = 8) -> list[dict]:
    if not lines or not frames:
        return []
    frame_times = [(_dt(frame["adjusted_utc"]), frame) for frame in frames]
    scored = []
    for line in lines:
        instant = _dt(line["utc"])
        best = min(frame_times, key=lambda item: abs((item[0] - instant).total_seconds()))
        delta = (best[0] - instant).total_seconds()
        scored.append((abs(delta), delta, line, best[1]))
    scored.sort(key=lambda item: item[0])
    out = []
    for _abs, delta, line, frame in scored[:limit]:
        out.append(
            {
                "line_utc": line["utc"],
                "speaker": line["speaker"],
                "image_nasa_id": frame["nasa_id"],
                "image_utc": frame["utc"],
                "delta_s": round(delta, 3),
            }
        )
    return out


def _dt(value: str) -> datetime:
    parsed, status = parse_utc(value)
    if parsed is None or status != "ok":
        raise ValueError(f"not a UTC instant: {value!r}")
    return parsed


def _track(instrument: str) -> str:
    instrument = (instrument or "").lower()
    if instrument in {"pcd2", "pcd3", "pcd1", "pcd4", "pcd"}:
        return instrument
    if instrument in {"oe1", "oe2"}:
        return instrument
    return instrument
