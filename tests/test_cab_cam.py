"""Cab Cam 2 keeps the label clock. Frames are not slid onto the flyby."""

import json
from pathlib import Path

from artemis2.labels import parse_label

ROOT = Path(__file__).resolve().parents[1]
TIMELINE = ROOT / "demo" / "data" / "timeline.json"
FIXTURE = ROOT / "tests" / "labels" / "art002e041322_cab2_raw_v01.xml"

FLYBY_START = "2026-04-06T19:33:00.000Z"
FLYBY_END = "2026-04-06T19:48:30.000Z"


def test_cab_label_and_shipped_times_stay_on_the_archive_clock():
    label = parse_label(FIXTURE)
    assert label.nasa_id == "art002e041322"
    assert label.instrument == "cab2"
    assert label.start_utc == "2026-04-06T19:34:44.000Z"
    assert label.lines == 3000
    assert label.samples == 4000
    assert label.focal_length_mm == 3.0

    document = json.loads(TIMELINE.read_text())
    cab = [frame for frame in document["frames"] if frame["instrument"] == "cab2"]
    assert [frame["utc"] for frame in cab] == sorted(frame["utc"] for frame in cab)
    assert all(frame["window"] == "3" for frame in cab)
    assert all(frame["presentation"] == "as-is" for frame in cab)
    assert all("NASA/Artemis II Crew" in frame["credit"] for frame in cab)
    assert all((ROOT / "demo" / "data" / frame["file"]).is_file() for frame in cab)

    inside = [frame for frame in cab if FLYBY_START <= frame["utc"] <= FLYBY_END]
    assert [frame["nasa_id"] for frame in inside] == ["art002e041322", "art002e041323"]
    assert inside[0]["utc"] == "2026-04-06T19:34:44.000Z"
    assert inside[1]["utc"] == "2026-04-06T19:42:44.000Z"
    assert inside[0]["look"] == "dark"
    shipped = next(frame for frame in cab if frame["nasa_id"] == "art002e041322")
    assert shipped["utc"] == label.start_utc

    nearest = next(frame for frame in cab if frame["nasa_id"] == "art002e041321")
    assert nearest["utc"] == "2026-04-06T19:26:43.000Z"
    assert nearest["utc"] < FLYBY_START

    run = document["cab_run"]
    assert run["start"] == "2026-04-06T22:36:03.000Z"
    assert run["end"] == "2026-04-06T22:44:33.000Z"
    bright = [frame for frame in cab if frame["look"] == "surface"]
    assert bright[0]["utc"] == run["start"]
    assert bright[-1]["nasa_id"] == "art002e041365"
    assert bright[-1]["utc"] == "2026-04-06T22:44:33.000Z"
    assert all(frame["utc"] > FLYBY_END for frame in bright)

    segment = next(row for row in document["segments"] if row["nasa_id"] == "art002a000045")
    assert segment["track"] == "pcd2"
    assert segment["start"] == "2026-04-06T22:39:11.395Z"
    assert segment["end"] == "2026-04-06T22:44:19.000Z"
    assert (ROOT / "demo" / "data" / segment["file"]).is_file()
    assert run["start"] < segment["start"] < run["end"]

    ids = {row["id"] for row in document["licenses"]}
    assert {"crew_camera", "orion_camera_cab2", "mission_audio", "mission_targets"} <= ids
    assert all("endors" in row["usage"] for row in document["licenses"])
