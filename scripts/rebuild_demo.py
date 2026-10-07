#!/usr/bin/env python3
"""Rebuild demo/data from build/cache with the artemis2 library.

Expected layout:

    build/cache/labels/*.xml
    build/cache/audio/*.m4a
    build/cache/transcripts/*trn-csv*.csv
    build/cache/thumbs/*.webp
    build/cache/artemis2_outgoing_target_request.json

Shipped frames are Atlas browse :lg derivatives, letterbox-cropped and
re-encoded as WebP. Audio is the real PCD M4A, trimmed to the window and
transcoded to mono 64 kbps AAC. Nothing is synthesized.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "build" / "cache"
CATALOG = ROOT / "build" / "catalog.sqlite"
DEMO = ROOT / "demo" / "data"


def _stash_cab(hold: Path) -> None:
    """Cab Cam files are not in the crew-camera cache. Keep them across a rebuild."""
    if hold.exists():
        shutil.rmtree(hold)
    patterns = ("images/art002e041*.webp", "audio/art002a000045.m4a")
    for pattern in patterns:
        for path in DEMO.glob(pattern):
            dest = hold / path.relative_to(DEMO)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)


def _restore_cab(hold: Path) -> None:
    if not hold.exists():
        return
    for path in hold.rglob("*"):
        if path.is_file():
            dest = DEMO / path.relative_to(hold)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)


def main() -> None:
    from artemis2.export import bytes_under, export_replay
    from artemis2.index import index_tree

    if not (CACHE / "labels").is_dir():
        sys.exit(f"missing {CACHE / 'labels'}")
    hold = ROOT / "build" / "cab-hold"
    _stash_cab(hold)
    if DEMO.exists():
        shutil.rmtree(DEMO)
    counts = index_tree(CACHE, CATALOG)
    print("index", counts)
    images = CACHE / "png" if any((CACHE / "png").glob("*.png")) else CACHE / "thumbs"
    summary = export_replay(CATALOG, DEMO, image_dir=images, bitrate="64k")
    print(summary)
    # art002e016183 is a cabin interior (lit card, not a lunar limb).
    timeline_path = DEMO / "timeline.json"
    document = json.loads(timeline_path.read_text())
    for frame in document["frames"]:
        if frame["nasa_id"] == "art002e016183":
            frame["view"] = "cabin"
            frame["view_note"] = (
                "Lit card in a dark cabin, not a lunar limb. "
                "Shown beside the window, not through the glass."
            )
    timeline_path.write_text(json.dumps(document, separators=(", ", ": ")))
    _restore_cab(hold)
    from merge_cab_cam import merge

    document = json.loads(timeline_path.read_text())
    merge(document)
    timeline_path.write_text(json.dumps(document, separators=(", ", ": ")))
    total = bytes_under(DEMO)
    print(f"demo/data {total / 1e6:.2f} MB")
    if total > 30_000_000:
        print("warning: demo/data is above the ~30 MB shipped-media budget", file=sys.stderr)


if __name__ == "__main__":
    main()
