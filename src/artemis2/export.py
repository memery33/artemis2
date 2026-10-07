"""Export a catalog to CSV, Parquet, or the static flyby bundle."""

from __future__ import annotations

import csv
import json
import sqlite3
import subprocess
from datetime import timedelta
from pathlib import Path

from artemis2.constants import CAMERA_WINDOW, DEMO_WINDOW, PCD_AUDIO_CREW, PHOTO_ATTRIBUTION, PHOTO_CREDIT
from artemis2.index import write_parquet
from artemis2.pointing import SpicePointingUnavailable
from artemis2.sync import build_timeline, clip_to_window
from artemis2.timebase import format_utc, parse_utc

REPLAY_VERSION = 1


def export_tables(db_path: str | Path, out_dir: str | Path, kind: str = "csv") -> list[str]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    if kind == "parquet":
        return write_parquet(db_path, out_dir)
    if kind != "csv":
        raise ValueError("kind must be csv or parquet")
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    written = []
    for table in ("images", "audio", "transcript_lines", "targets"):
        rows = list(conn.execute(f"SELECT * FROM {table}"))
        dest = out_dir / f"{table}.csv"
        with dest.open("w", newline="", encoding="utf-8") as handle:
            if not rows:
                handle.write("")
                written.append(str(dest))
                continue
            writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
            writer.writeheader()
            for row in rows:
                writer.writerow(dict(row))
        written.append(str(dest))
    conn.close()
    return written


def export_replay(
    db_path: str | Path,
    out_dir: str | Path,
    start: str = DEMO_WINDOW["start"],
    end: str = DEMO_WINDOW["end"],
    image_dir: str | Path | None = None,
    camera_offsets: dict[str, float] | None = None,
    bitrate: str = "64k",
) -> dict:
    """Write ``timeline.json``, trimmed audio, resized frames, and GeoJSON.

    Audio is transcoded from the real M4A. Nothing is synthesized.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    timeline = build_timeline(str(db_path), start, end, camera_offsets)
    win_start, _ = parse_utc(start)
    win_end, _ = parse_utc(end)
    assert win_start and win_end

    segments = []
    for segment in timeline["audio"]:
        if segment["timing"] != "exact" or not segment.get("media_path"):
            continue
        seg_start, _ = parse_utc(segment["exact_start"])
        seg_end, _ = parse_utc(segment["exact_end"])
        assert seg_start and seg_end
        clip = clip_to_window(seg_start, seg_end, win_start, win_end)
        if clip is None:
            continue
        dest = out_dir / "audio" / f"{segment['nasa_id']}.m4a"
        transcode_clip(segment["media_path"], dest, clip["offset_s"], clip["duration_s"], bitrate)
        segments.append(
            {
                "nasa_id": segment["nasa_id"],
                "track": segment["track"],
                "instrument": segment["instrument"],
                "start": format_utc(clip["start"]),
                "end": format_utc(clip["end"]),
                "file": f"audio/{dest.name}",
                "activity_id": segment["activity_id"],
                "target_id": segment["target_id"],
                "source": "PDS mission_audio M4A, trimmed and transcoded. Not synthesized.",
            }
        )

    index = _image_index(Path(image_dir) if image_dir else None)
    frames = []
    for frame in timeline["images"]:
        source = _match_image(index, frame["nasa_id"])
        if source is None:
            continue
        dest = out_dir / "images" / f"{frame['nasa_id']}.webp"
        prepare_frame(source, dest, frame.get("lines"), frame.get("samples"))
        camera = CAMERA_WINDOW.get(frame["instrument"], {})
        frames.append(
            {
                "utc": frame["utc"],
                "nasa_id": frame["nasa_id"],
                "instrument": frame["instrument"],
                "window": camera.get("window"),
                "camera_label": camera.get("label") or frame["instrument"],
                "camera_detail": camera.get("detail") or "",
                "file": f"images/{dest.name}",
                "credit": f"NASA ID {frame['nasa_id']}, {PHOTO_CREDIT}",
                "activity_id": frame["activity_id"],
                "target_id": frame["target_id"],
                "secondary_targets": frame["secondary_targets"],
                "focal_length_mm": frame["focal_length_mm"],
                "footprint": frame["footprint"],
                "footprint_trust": frame["footprint_trust"],
                "axis_swapped": frame["axis_swapped"],
                "target_tags_unverified": True,
            }
        )

    targets = _targets(db_path)
    features = []
    for frame in frames:
        if frame["footprint"] and frame["footprint_trust"] != "none":
            features.append(
                {
                    "type": "Feature",
                    "properties": {
                        "nasa_id": frame["nasa_id"],
                        "utc": frame["utc"],
                        "trust": frame["footprint_trust"],
                        "instrument": frame["instrument"],
                    },
                    "geometry": {"type": "Polygon", "coordinates": [frame["footprint"]]},
                }
            )
    geojson = {"type": "FeatureCollection", "features": features}
    (out_dir / "footprints.geojson").write_text(json.dumps(geojson), encoding="utf-8")

    pointing = SpicePointingUnavailable()
    document = {
        "version": REPLAY_VERSION,
        "window": {"start": timeline["start"], "end": timeline["end"], "label": DEMO_WINDOW["label"]},
        "attribution": {
            "photos": PHOTO_ATTRIBUTION,
            "credit": PHOTO_CREDIT,
            "endorsement": "Independent open-source viewer. Not a NASA product and not endorsed by NASA.",
        },
        "pointing": {
            "available": pointing.available(),
            "provider": pointing.name,
            "note": (
                "No per-window attitude. The NAIF SPICE bundle is delayed and no CK/FK/SCLK "
                "is public. Footprints are georeferenced Nikon frames, not a window boresight. "
                "A PointingProvider with boresight(utc, window_id) is the drop-in seam."
            ),
        },
        "geometry_note": (
            "Pixel-axis names in the labels are swapped relative to Line/Sample. "
            "Drawn footprints use the control-point convex hull when the homography "
            "corners extrapolate past the matched points."
        ),
        "camera_offsets_s": timeline["camera_offsets_s"],
        "offset_note": (
            "The slider adds seconds to photo timestamps before comparing them with the "
            "audio clock. Clocks were checked against the PCD before each activity; the "
            "residual is undocumented and about ±1–2 s."
        ),
        "pcd_audio_crew": {key: list(value) for key, value in PCD_AUDIO_CREW.items()},
        "segments": segments,
        "lines": timeline["lines"],
        "frames": frames,
        "targets": targets,
        "crew": [
            {"id": "Wiseman", "track": "pcd3"},
            {"id": "Glover", "track": "pcd2"},
            {"id": "Koch", "track": "pcd3"},
            {"id": "Hansen", "track": "pcd2"},
        ],
    }
    (out_dir / "timeline.json").write_text(json.dumps(document), encoding="utf-8")
    return {
        "timeline": str(out_dir / "timeline.json"),
        "segments": len(segments),
        "frames": len(frames),
        "lines": len(document["lines"]),
    }


def transcode_clip(src: str, dest: Path, offset_s: float, duration_s: float, bitrate: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    # -ss after -i keeps the trim on the decoded timeline so the offset stays exact.
    command = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        src,
        "-ss",
        f"{offset_s:.3f}",
        "-t",
        f"{duration_s:.3f}",
        "-ac",
        "1",
        "-ar",
        "48000",
        "-c:a",
        "aac",
        "-b:a",
        bitrate,
        "-movflags",
        "+faststart",
        str(dest),
    ]
    try:
        subprocess.run(command, check=True)
    except FileNotFoundError as exc:
        raise RuntimeError("ffmpeg is required to trim replay audio") from exc


def prepare_frame(src: Path, dest: Path, lines: int | None, samples: int | None) -> None:
    from PIL import Image

    dest.parent.mkdir(parents=True, exist_ok=True)
    image = Image.open(src).convert("RGB")
    image = _crop_letterbox(image, lines, samples)
    # Long edge 1200 keeps a full-screen window sharp enough at a small file size.
    long_edge = max(image.size)
    if long_edge > 1200:
        scale = 1200 / long_edge
        image = image.resize((int(image.width * scale), int(image.height * scale)), Image.Resampling.LANCZOS)
    image.save(dest, "WEBP", quality=76, method=4)


def _crop_letterbox(image, lines: int | None, samples: int | None):
    if not lines or not samples:
        return image
    width, height = image.size
    expected = samples / lines
    actual = width / height
    if abs(actual - expected) < 0.02:
        return image
    # Atlas :lg/:md derivatives are square and letterbox the 3:2 frame.
    content_h = int(round(width * lines / samples))
    if 0 < content_h < height - 2:
        y0 = (height - content_h) // 2
        return image.crop((0, y0, width, y0 + content_h))
    content_w = int(round(height * samples / lines))
    if 0 < content_w < width - 2:
        x0 = (width - content_w) // 2
        return image.crop((x0, 0, x0 + content_w, height))
    return image


def _image_index(directory: Path | None) -> dict[str, Path]:
    if directory is None or not directory.is_dir():
        return {}
    found = {}
    for path in directory.iterdir():
        if path.suffix.lower() not in {".webp", ".jpg", ".jpeg", ".png"}:
            continue
        found[path.stem.split("_")[0] if path.stem.startswith("art002") else path.stem] = path
        # art002e009943_nkd5015_prc → also index the nasa id, which is the first token.
        nasa = path.name.split("_")[0]
        found[nasa] = path
    return found


def _match_image(index: dict[str, Path], nasa_id: str) -> Path | None:
    return index.get(nasa_id)


def _targets(db_path: str | Path) -> list[dict]:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        rows = list(conn.execute("SELECT * FROM targets"))
    except sqlite3.OperationalError:
        rows = []
    conn.close()
    out = []
    for row in rows:
        out.append(
            {
                "name": row["name"],
                "ltp_name": row["ltp_name"],
                "order": row["order_id"],
                "lat": row["latitude"],
                "lon": row["longitude"],
                "geographic": bool(row["geographic"]),
            }
        )
    return out


def bytes_under(path: Path) -> int:
    total = 0
    if path.is_file():
        return path.stat().st_size
    for child in path.rglob("*"):
        if child.is_file():
            total += child.stat().st_size
    return total
