#!/usr/bin/env python3
"""Merge the checked Cab Cam 2 slice into demo/data/timeline.json.

Times come from the raw PDS4 labels (and match each browse JPEG DateTime).
Nothing here moves a frame onto the 19:33 flyby clock.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIMELINE = ROOT / "demo" / "data" / "timeline.json"

DETAIL = "GoPro mounted inside Window 3 (Data User Guide §3.3.1)."
CREDIT = "Credit: NASA/Artemis II Crew"

# (nasa_id, utc, look, exposure_note)
# Dark rows are the real flyby exposures. They are nearly black, not :md masks.
# Surface rows are the first bright 30 s run that a shipped PCD file overlaps.
CAB_FRAMES = [
    (
        "art002e041321",
        "2026-04-06T19:26:43.000Z",
        "dark",
        "Nearest Cab Cam frame before the flyby window. Label exposure 0.002075 s, ISO 100, compensation −2, spot meter. The browse JPEG is nearly black (mean luminance about 9) with a small bright patch near the middle. Not a :md mask, and not brightened.",
    ),
    (
        "art002e041322",
        "2026-04-06T19:34:44.000Z",
        "dark",
        "Inside the flyby window. Label exposure 0.001942 s, ISO 100, compensation −2, spot meter. The browse JPEG is nearly black (mean luminance about 9) with a small bright patch near the middle. Not a :md mask, and not brightened.",
    ),
    (
        "art002e041323",
        "2026-04-06T19:42:44.000Z",
        "dark",
        "Inside the flyby window. Label exposure 0.002062 s, ISO 100, compensation −2, spot meter. The browse JPEG is nearly black (mean luminance about 9) with a small bright patch near the middle. Not a :md mask, and not brightened.",
    ),
]

for index, utc in enumerate(
    [
        "2026-04-06T22:36:03.000Z",
        "2026-04-06T22:36:33.000Z",
        "2026-04-06T22:37:03.000Z",
        "2026-04-06T22:37:33.000Z",
        "2026-04-06T22:38:03.000Z",
        "2026-04-06T22:38:33.000Z",
        "2026-04-06T22:39:03.000Z",
        "2026-04-06T22:39:33.000Z",
        "2026-04-06T22:40:03.000Z",
        "2026-04-06T22:40:33.000Z",
        "2026-04-06T22:41:03.000Z",
        "2026-04-06T22:41:33.000Z",
        "2026-04-06T22:42:04.000Z",
        "2026-04-06T22:42:33.000Z",
        "2026-04-06T22:43:03.000Z",
        "2026-04-06T22:43:33.000Z",
        "2026-04-06T22:44:03.000Z",
        "2026-04-06T22:44:33.000Z",
    ]
):
    nasa = f"art002e041{348 + index}"
    CAB_FRAMES.append(
        (
            nasa,
            utc,
            "surface",
            "Lunar surface fills this browse JPEG (mean luminance about 65). Shown as photographed, with no drawn window frame. Label exposure is 1/120 s at ISO about 120, compensation −2.",
        )
    )

CAB_RUN = {
    "start": "2026-04-06T22:36:03.000Z",
    "end": "2026-04-06T22:44:33.000Z",
    "label": "Cab Cam 2 · Window 3",
    "note": (
        "These GoPro frames stay on their label times. They were not moved into "
        "19:33:00–19:48:30. art002a000045 (PCD2) overlaps from 22:39:11.395Z to "
        "22:44:19.000Z. No transcript was shipped for that file, so this run has no subtitles. "
        "The clock from 22:36:03 to 22:39:11 is silent."
    ),
}

SEGMENT = {
    "nasa_id": "art002a000045",
    "track": "pcd2",
    "instrument": "pcd2",
    "start": "2026-04-06T22:39:11.395Z",
    "end": "2026-04-06T22:44:19.000Z",
    "file": "audio/art002a000045.m4a",
    "activity_id": "",
    "target_id": "",
    "source": (
        "PDS mission_audio M4A. Embedded creation_time 22:44:19.000Z is the end; "
        "duration 307.604833 s, so the start is 22:39:11.395Z. Transcoded to mono 64 kbps. "
        "Not trimmed into the flyby and not synthesized. No transcript shipped."
    ),
}

GUIDELINES = (
    "NASA images, audio, and related media are generally not subject to copyright in the United States. "
    "Acknowledge NASA as the source. Do not imply that NASA endorses this project. "
    "See https://www.nasa.gov/nasa-brand-center/images-and-media/"
)

LICENSES = [
    {
        "id": "crew_camera",
        "bundle": "urn:nasa:pds:artemis2_crew_camera",
        "doi": "10.17189/x52v-tb80",
        "shipped": True,
        "credit": f"NASA ID <id>, {CREDIT}",
        "usage": (
            f"{GUIDELINES} Shipped stills are Atlas browse derivatives resized to a 1200-pixel long edge. "
            "PDS4 labels carry no photographer field. The Data User Guide credits every still to NASA/Artemis II Crew."
        ),
    },
    {
        "id": "orion_camera_cab2",
        "bundle": "urn:nasa:pds:artemis2_orion_camera",
        "doi": "10.17189/hzev-nq50",
        "shipped": True,
        "credit": f"NASA ID <id>, {CREDIT}",
        "usage": (
            f"{GUIDELINES} Cab Cam 2 is a GoPro HERO4 Black mounted inside Window 3 (Data User Guide §3.3.1). "
            "Shipped files are full browse JPEGs from browse_source/fd05 (the labels say flight day 6), not :md mask derivatives. "
            "Times are label start_date_time values and match the JPEG DateTime. No photographer is named. "
            "Frames stay on those times; they are not shifted into the flyby window."
        ),
    },
    {
        "id": "mission_audio",
        "bundle": "urn:nasa:pds:artemis2_mission_audio",
        "doi": "10.17189/4a29-dz64",
        "shipped": True,
        "credit": "NASA Artemis II crew PCD recordings",
        "usage": (
            f"{GUIDELINES} Flyby clips are the real M4A files, trimmed to the moments that fall in "
            "19:33:00–19:48:30 UTC and transcoded to mono 64 kbps AAC. "
            "art002a000045 is the whole recording, transcoded the same way, and left on "
            "22:39:11.395–22:44:19.000 UTC. Nothing is synthesized."
        ),
    },
    {
        "id": "mission_targets",
        "bundle": "urn:nasa:pds:artemis2_mission",
        "doi": "10.17189/36fx-pd80",
        "shipped": True,
        "credit": "NASA PDS Artemis II mission bundle",
        "usage": (
            f"{GUIDELINES} The outgoing target list supplies map names and coordinates. "
            "Hertzsprung Basin is stored at latitude 0, longitude 0 and is not plotted. "
            "The Data User Guide is cited for window and PCD assignments."
        ),
    },
    {
        "id": "cited_not_shipped",
        "bundle": "",
        "doi": "",
        "shipped": False,
        "credit": "NASA",
        "usage": (
            f"{GUIDELINES} Cited and not shipped as pixels: jsc2022e045980; interior frames "
            "art002e004439, art002e004440, art002e009292, art002e025643, and the other interior IDs in the README; "
            "Cab Cam frame art002e000210 (2026-04-03T00:30:38Z, not the flyby). "
            "NASA.gov articles on the Orion windows are cited the same way."
        ),
    },
]


def cab_frame(nasa_id: str, utc: str, look: str, exposure_note: str) -> dict:
    return {
        "utc": utc,
        "nasa_id": nasa_id,
        "instrument": "cab2",
        "window": "3",
        "camera_label": "Window 3 · Cab Cam 2",
        "camera_detail": DETAIL,
        "file": f"images/{nasa_id}.webp",
        "credit": f"NASA ID {nasa_id}, {CREDIT}",
        "activity_id": "Other",
        "target_id": "Moon",
        "secondary_targets": [],
        "focal_length_mm": 3.0,
        "footprint": [],
        "footprint_trust": "none",
        "axis_swapped": None,
        "target_tags_unverified": True,
        "presentation": "as-is",
        "look": look,
        "exposure_note": exposure_note,
    }


def merge(document: dict) -> dict:
    document["frames"] = [frame for frame in document["frames"] if frame.get("instrument") != "cab2"]
    document["frames"].extend(cab_frame(*row) for row in CAB_FRAMES)
    document["frames"].sort(key=lambda frame: frame["utc"])
    document["segments"] = [row for row in document["segments"] if row.get("nasa_id") != "art002a000045"]
    document["segments"].append(SEGMENT)
    document["segments"].sort(key=lambda row: row["start"])
    document["cab_run"] = CAB_RUN
    document["licenses"] = LICENSES
    return document


def main() -> None:
    document = json.loads(TIMELINE.read_text())
    merge(document)
    TIMELINE.write_text(json.dumps(document, separators=(", ", ": ")), encoding="utf-8")
    images = ROOT / "demo" / "data" / "images"
    missing = [nasa for nasa, *_ in CAB_FRAMES if not (images / f"{nasa}.webp").is_file()]
    if missing:
        raise SystemExit(f"missing webp files: {missing}")


if __name__ == "__main__":
    main()
