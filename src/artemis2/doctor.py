"""Report the known Artemis II archive quirks, and check them on local files."""

from __future__ import annotations

import sqlite3
from datetime import timedelta
from pathlib import Path

from artemis2.constants import KNOWN_AUDIO_DUPLICATE_IDS
from artemis2.index import index_tree
from artemis2.labels import parse_transcript_csv
from artemis2.timebase import format_utc, loop_pieces, parse_utc

# Facts from the October 2026 audit. doctor repeats them even when the local
# tree is only a sample, and adds a "seen here" line when the files are present.
STATIC_QUIRKS = [
    {
        "id": "spice-delayed",
        "severity": "gap",
        "summary": "The PDS SPICE bundle (urn:nasa:pds:artemis2_spice) is not released. NAIF has a public trajectory SPK for Orion (NAIF id -24) and no CK, FK, or SCLK, so window pointing cannot be computed.",
    },
    {
        "id": "no-photographer",
        "severity": "note",
        "summary": "Image credit is 'NASA/Artemis II Crew'. Labels have no per-person photographer field. Do not guess who took a frame.",
    },
    {
        "id": "footprint-axes",
        "severity": "data",
        "summary": "In processed Nikon labels, vertical_coordinate_pixel runs along the sample axis and horizontal_coordinate_pixel along the line axis. The names are swapped relative to the display axes. Corner footprints also extrapolate past the control points (label says homography; the guide says affine).",
    },
    {
        "id": "audio-end-time",
        "severity": "data",
        "summary": "PCD M4A embedded time is the end of the recording. Start = end − exact duration. Label start/stop are truncated to whole seconds. art002a000033 starts at 19:46:14.576 UTC, not 19:46:14.",
    },
    {
        "id": "loop-discontinuous",
        "severity": "data",
        "summary": "Voice-loop files are not continuous. Map them through each transcript line's utc column. art002_2026-04-06_oe1 jumps by about 8.5 hours at audio time 06:23:41.",
    },
    {
        "id": "oe2-date",
        "severity": "data",
        "summary": "art002_2026-04-07_oe2 is named 7 April but its label and transcript times are 6 April 2026.",
    },
    {
        "id": "malformed-utc",
        "severity": "data",
        "summary": "Transcript utc values include a malformed '2026-04-06 03:10:201200' and date-only rows. They are kept and excluded from the clock.",
    },
    {
        "id": "duplicate-pcd",
        "severity": "data",
        "summary": "fd04 art002a000001 is byte-identical to art002a000003, and art002a000002 to art002a000004, with different activity_id values. art002a000052_pcd1_src is in the Atlas tree, not the collection inventory, and matches the pcd3 raw file.",
    },
    {
        "id": "missing-video",
        "severity": "data",
        "summary": "Orion video channel2 has no art002m1020961941, although the guide's Table 8 lists it. Channel2 has 10 files and channel1 has 11.",
    },
    {
        "id": "counts",
        "severity": "note",
        "summary": "The archive holds 10,329 crew images per level. The guide's Figure 7 says 10,339. The blog's 'more than 800 gigabytes' does not match the Atlas sum of about 2.57 TB, which includes processed TIFFs.",
    },
    {
        "id": "unreleased",
        "severity": "gap",
        "summary": "Not in the archive: iPhone 17 Pro Max collection, Nikon lens-distortion PDF, HERA radiation data, and the SPICE bundle. The DUG DOI 10.17189/dtpt-2857 does not resolve yet.",
    },
    {
        "id": "target-tags",
        "severity": "note",
        "summary": "activity_id and target_id were not thoroughly verified (Data User Guide Table 17). Hertzsprung Basin is stored at latitude 0, longitude 0 in the outgoing target request.",
    },
    {
        "id": "camera-offset",
        "severity": "note",
        "summary": "Camera clocks were checked against the PCD before each activity. The residual offset is not quantified. Absolute time is uncertain by about 1–2 seconds because the M4A end time has 1-second resolution. sync accepts a per-camera offset.",
    },
    {
        "id": "dcam-time",
        "severity": "note",
        "summary": "DCAM times are best estimates and may be off by 5 minutes or more. OpNav times were reconstructed from the original filename.",
    },
]


def doctor(root: str | Path | None = None, db_path: str | Path | None = None) -> dict:
    """Return a report. With a directory, index it and annotate quirks that are visible."""
    report: dict = {"quirks": [dict(item) for item in STATIC_QUIRKS], "checks": []}
    if root is None and db_path is None:
        return report
    if root is not None and db_path is None:
        db_path = Path(root) / ".artemis2-doctor.sqlite"
        index_tree(root, db_path)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    report["checks"].extend(_check_audio(conn))
    report["checks"].extend(_check_geometry(conn))
    report["checks"].extend(_check_transcripts(conn))
    report["checks"].extend(_check_duplicates(conn))
    report["checks"].extend(_check_targets(conn))
    report["checks"].extend(_check_inventory(conn))
    conn.close()
    return report


def format_report(report: dict) -> str:
    lines = ["Artemis II data quirks", ""]
    for quirk in report["quirks"]:
        lines.append(f"[{quirk['severity']}] {quirk['id']}")
        lines.append(f"  {quirk['summary']}")
    if report.get("checks"):
        lines.append("")
        lines.append("Local checks")
        for check in report["checks"]:
            flag = "ok" if check.get("ok") else "see"
            lines.append(f"  ({flag}) {check['id']}: {check['detail']}")
    return "\n".join(lines) + "\n"


def _check_audio(conn: sqlite3.Connection) -> list[dict]:
    checks = []
    row = conn.execute("SELECT * FROM audio WHERE nasa_id = 'art002a000033'").fetchone()
    if row is None:
        checks.append({"id": "a000033", "ok": True, "detail": "art002a000033 is not in this tree"})
        return checks
    if not row["exact_start"]:
        checks.append({"id": "a000033", "ok": False, "detail": "label is present but the M4A was not probed"})
        return checks
    ok = row["exact_start"].startswith("2026-04-06T19:46:14.576")
    checks.append(
        {
            "id": "a000033",
            "ok": ok,
            "detail": (
                f"exact start {row['exact_start']} from create {row['create_utc']} "
                f"minus {row['exact_duration_s']} s; label start {row['label_start']}"
            ),
        }
    )
    return checks


def _check_geometry(conn: sqlite3.Connection) -> list[dict]:
    rows = list(conn.execute("SELECT nasa_id, axis_swapped, footprint_trust, n_control_points FROM images WHERE n_control_points > 0"))
    if not rows:
        return [{"id": "axes", "ok": True, "detail": "no georeferenced image label in this tree"}]
    swapped = [row["nasa_id"] for row in rows if row["axis_swapped"]]
    trusts = {}
    for row in rows:
        trusts[row["footprint_trust"]] = trusts.get(row["footprint_trust"], 0) + 1
    return [
        {
            "id": "axes",
            "ok": bool(swapped),
            "detail": f"swapped axis names on {', '.join(swapped) or 'none'}; footprint trust {trusts}",
        }
    ]


def _check_transcripts(conn: sqlite3.Connection) -> list[dict]:
    checks = []
    malformed = conn.execute("SELECT COUNT(*) AS n FROM transcript_lines WHERE utc_status = 'malformed'").fetchone()["n"]
    date_only = conn.execute("SELECT COUNT(*) AS n FROM transcript_lines WHERE utc_status = 'date_only'").fetchone()["n"]
    checks.append(
        {
            "id": "utc-parse",
            "ok": True,
            "detail": f"{malformed} malformed utc values, {date_only} date-only values excluded from the clock",
        }
    )
    paths = [row["path"] for row in conn.execute("SELECT DISTINCT path FROM transcript_lines")]
    jumps = []
    oe2 = []
    for path in paths:
        rows = []
        for line in parse_transcript_csv(path):
            utc, status = parse_utc(line.utc if line.utc else _raw_utc(line))
            # parse_transcript already classified; rebuild pieces from the file.
        file_rows = _rows_for_pieces(path)
        pieces = loop_pieces(file_rows)
        if len(pieces) > 1:
            jumps.append(f"{Path(path).name}: {len(pieces)} pieces")
        if "2026-04-07_oe2" in path:
            days = set()
            for row in file_rows:
                if row.get("status") == "ok" and row.get("utc") is not None:
                    days.add(row["utc"].strftime("%Y-%m-%d"))
            oe2.append(sorted(days))
    if jumps:
        checks.append({"id": "loop-pieces", "ok": True, "detail": "; ".join(jumps)})
    if oe2:
        named_april_7 = True
        content_days = oe2[0]
        ok = content_days == ["2026-04-06"] or content_days == []
        checks.append(
            {
                "id": "oe2-date",
                "ok": ok and named_april_7,
                "detail": f"filename says 2026-04-07; transcript clock days are {content_days or 'unparsed'}",
            }
        )
    return checks


def _raw_utc(line) -> str:
    return ""


def _rows_for_pieces(path: str) -> list[dict]:
    rows = []
    for line in parse_transcript_csv(path):
        utc, status = parse_utc(line.utc) if line.utc else (None, line.utc_status)
        if line.utc_status != "ok":
            status = line.utc_status
            utc = None
        rows.append({"utc": utc, "audio_s": line.audio_s, "status": line.utc_status if line.utc else status})
    return rows


def _check_duplicates(conn: sqlite3.Connection) -> list[dict]:
    checks = []
    for left, right in KNOWN_AUDIO_DUPLICATE_IDS:
        a = conn.execute("SELECT label_start, activity_id FROM audio WHERE nasa_id = ?", (left,)).fetchone()
        b = conn.execute("SELECT label_start, activity_id FROM audio WHERE nasa_id = ?", (right,)).fetchone()
        if a is None or b is None:
            continue
        same_time = a["label_start"] == b["label_start"] and a["label_start"] != ""
        different = a["activity_id"] != b["activity_id"]
        checks.append(
            {
                "id": f"dup-{left[-6:]}",
                "ok": same_time and different,
                "detail": (
                    f"{left} activity {a['activity_id']!r} and {right} activity {b['activity_id']!r} "
                    f"share label start {a['label_start']}"
                ),
            }
        )
    return checks


def _check_targets(conn: sqlite3.Connection) -> list[dict]:
    try:
        row = conn.execute(
            "SELECT name, latitude, longitude FROM targets WHERE name LIKE 'Hertzsprung%'"
        ).fetchone()
    except sqlite3.OperationalError:
        return []
    if row is None:
        return [{"id": "hertzsprung", "ok": True, "detail": "outgoing target list is not in this tree"}]
    ok = row["latitude"] == 0 and row["longitude"] == 0
    return [
        {
            "id": "hertzsprung",
            "ok": ok,
            "detail": f"{row['name']} is stored at lat {row['latitude']}, lon {row['longitude']} and is not plotted as a real coordinate",
        }
    ]


def _check_inventory(conn: sqlite3.Connection) -> list[dict]:
    try:
        lids = [row["lid"] for row in conn.execute("SELECT lid FROM inventory")]
    except sqlite3.OperationalError:
        return []
    if not lids:
        return []
    orphan = any("art002a000052_pcd1" in lid for lid in lids)
    pcd3 = any("art002a000052_pcd3" in lid for lid in lids)
    return [
        {
            "id": "orphan-a000052",
            "ok": pcd3 and not orphan,
            "detail": "collection inventory lists pcd3 raw and does not list pcd1 src for art002a000052",
        }
    ]


def label_versus_exact(label_start: str, exact_start: str) -> float | None:
    label, label_status = parse_utc(label_start)
    exact, exact_status = parse_utc(exact_start)
    if label_status != "ok" or exact_status != "ok" or label is None or exact is None:
        return None
    return (exact - label).total_seconds()
