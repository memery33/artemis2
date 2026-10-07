"""The shipped flyby bundle keeps the golden audio clock."""

import json
from pathlib import Path

TIMELINE = Path(__file__).resolve().parents[1] / "demo" / "data" / "timeline.json"


def test_shipped_window_keeps_a000033_and_does_not_invent_a_photographer():
    document = json.loads(TIMELINE.read_text())
    segment = next(row for row in document["segments"] if row["nasa_id"] == "art002a000033")
    assert segment["start"] == "2026-04-06T19:46:14.576Z"
    assert segment["track"] == "pcd2"
    line = next(row for row in document["lines"] if row["utc"] == "2026-04-06T19:46:14.978Z")
    assert line["speaker"] == "Hansen"
    assert "photographer" not in document["attribution"]["photos"].lower() or "no per-person" in document["attribution"]["photos"].lower()
    assert document["pointing"]["available"] is False
    assert any(frame["footprint_trust"] == "control_hull" for frame in document["frames"])
    assert all("NASA/Artemis II Crew" in frame["credit"] for frame in document["frames"])
    # Hertzsprung's 0,0 coordinate is not plotted as a real site.
    hertz = [row for row in document["targets"] if row["name"].startswith("Hertzsprung")]
    assert hertz and hertz[0]["geographic"] is False
