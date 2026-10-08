"""Build a SQLite catalog (and optional Parquet) from local PDS4 files."""

from __future__ import annotations

import json
import sqlite3
import subprocess
from pathlib import Path

from artemis2.labels import (
    ImageProduct,
    TranscriptRow,
    parse_inventory,
    parse_label,
    parse_targets,
    parse_transcript_csv,
)
from artemis2.timebase import audio_start, format_utc, parse_utc

SCHEMA = """
CREATE TABLE IF NOT EXISTS images (
    nasa_id TEXT,
    instrument TEXT,
    product_type TEXT,
    lid TEXT,
    file_name TEXT,
    path TEXT,
    start_utc TEXT,
    flight_day INTEGER,
    activity_id TEXT,
    target_id TEXT,
    secondary_targets TEXT,
    lines INTEGER,
    samples INTEGER,
    focal_length_mm REAL,
    n_control_points INTEGER,
    has_geometry INTEGER,
    axis_swapped INTEGER,
    footprint_trust TEXT,
    footprint_json TEXT
);
CREATE TABLE IF NOT EXISTS audio (
    nasa_id TEXT,
    instrument TEXT,
    lid TEXT,
    file_name TEXT,
    path TEXT,
    label_start TEXT,
    label_stop TEXT,
    create_utc TEXT,
    label_duration_s REAL,
    exact_duration_s REAL,
    exact_start TEXT,
    flight_day INTEGER,
    activity_id TEXT,
    target_id TEXT,
    secondary_targets TEXT,
    media_path TEXT
);
CREATE TABLE IF NOT EXISTS transcript_lines (
    nasa_id TEXT,
    instrument TEXT,
    path TEXT,
    audio_time TEXT,
    audio_s REAL,
    utc TEXT,
    utc_status TEXT,
    speaker_raw TEXT,
    speaker TEXT,
    role TEXT,
    text TEXT
);
CREATE TABLE IF NOT EXISTS targets (
    name TEXT,
    ltp_name TEXT,
    order_id TEXT,
    latitude REAL,
    longitude REAL,
    start_utc TEXT,
    geographic INTEGER
);
CREATE TABLE IF NOT EXISTS inventory (
    lid TEXT,
    path TEXT
);
"""


def connect(db_path: str | Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def index_tree(root: str | Path, db_path: str | Path) -> dict:
    root = Path(root)
    db_path = Path(db_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    conn = connect(db_path)
    conn.executescript(SCHEMA)
    counts = {"images": 0, "audio": 0, "lines": 0, "targets": 0, "inventory": 0, "documents": 0}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        name = path.name.lower()
        if name.endswith(".xml"):
            product = parse_label(path)
            if product.kind == "audio":
                _insert_audio(conn, product, root)
                counts["audio"] += 1
            elif product.kind == "image":
                _insert_image(conn, product)
                counts["images"] += 1
            else:
                counts["documents"] += 1
        elif "trn-csv" in name and name.endswith(".csv"):
            for row in parse_transcript_csv(path):
                _insert_line(conn, row)
                counts["lines"] += 1
        elif "inventory" in name and name.endswith(".csv"):
            for lid in parse_inventory(path):
                conn.execute("INSERT INTO inventory (lid, path) VALUES (?, ?)", (lid, str(path)))
                counts["inventory"] += 1
        elif name.endswith(".json") and "target" in name:
            for target in parse_targets(path):
                conn.execute(
                    """INSERT INTO targets
                    (name, ltp_name, order_id, latitude, longitude, start_utc, geographic)
                    VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        target["name"],
                        target["ltp_name"],
                        target["order"],
                        target["latitude"],
                        target["longitude"],
                        target["start_utc"],
                        1 if target["geographic"] else 0,
                    ),
                )
                counts["targets"] += 1
    conn.commit()
    conn.close()
    return counts


def write_parquet(db_path: str | Path, out_dir: str | Path) -> list[str]:
    import pandas as pd

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    conn = connect(db_path)
    written = []
    for table in ("images", "audio", "transcript_lines", "targets"):
        frame = pd.read_sql_query(f"SELECT * FROM {table}", conn)
        dest = out_dir / f"{table}.parquet"
        frame.to_parquet(dest, index=False)
        written.append(str(dest))
    conn.close()
    return written


def _insert_image(conn: sqlite3.Connection, product: ImageProduct) -> None:
    conn.execute(
        """INSERT INTO images VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            product.nasa_id,
            product.instrument,
            product.product_type,
            product.lid,
            product.file_name,
            product.path,
            product.start_utc,
            product.flight_day,
            product.activity_id,
            product.target_id,
            "|".join(product.secondary_targets),
            product.lines,
            product.samples,
            product.focal_length_mm,
            product.n_control_points,
            1 if product.has_geometry else 0,
            None if product.axis_swapped is None else int(product.axis_swapped),
            product.footprint_trust,
            json.dumps(product.footprint_lonlat),
        ),
    )


def _insert_audio(conn: sqlite3.Connection, product: ImageProduct, root: Path) -> None:
    media = _find_media(root, product.file_name)
    exact_duration = None
    exact_start = ""
    create_dt, create_status = parse_utc(product.create_utc)
    if media is not None:
        probed = probe_audio(media)
        exact_duration = probed.get("duration_s")
        end = probed.get("creation_time") or (create_dt if create_status == "ok" else None)
        if end is not None and exact_duration:
            exact_start = format_utc(audio_start(end, exact_duration))
    conn.execute(
        """INSERT INTO audio VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            product.nasa_id,
            product.instrument,
            product.lid,
            product.file_name,
            product.path,
            product.start_utc,
            product.stop_utc,
            product.create_utc,
            product.label_duration_s,
            exact_duration,
            exact_start,
            product.flight_day,
            product.activity_id,
            product.target_id,
            "|".join(product.secondary_targets),
            str(media) if media else "",
        ),
    )


def _insert_line(conn: sqlite3.Connection, row: TranscriptRow) -> None:
    conn.execute(
        """INSERT INTO transcript_lines VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        (
            row.nasa_id,
            row.instrument,
            row.path,
            row.audio_time,
            row.audio_s,
            row.utc,
            row.utc_status,
            row.speaker_raw,
            row.speaker,
            row.role,
            row.text,
        ),
    )


def _find_media(root: Path, file_name: str) -> Path | None:
    if not file_name:
        return None
    direct = root / file_name
    if direct.is_file():
        return direct
    matches = list(root.rglob(file_name))
    return matches[0] if matches else None


def probe_audio(path: Path) -> dict:
    """Duration and embedded creation_time via ffprobe. Empty dict on failure."""
    try:
        completed = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration:format_tags=creation_time",
                "-of",
                "json",
                str(path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}
    payload = json.loads(completed.stdout or "{}")
    fmt = payload.get("format") or {}
    tags = fmt.get("tags") or {}
    duration = fmt.get("duration")
    created, status = parse_utc(tags.get("creation_time"))
    return {
        "duration_s": float(duration) if duration else None,
        "creation_time": created if status == "ok" else None,
    }
