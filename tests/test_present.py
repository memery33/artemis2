"""Label placement and the UTC / Eastern / MET clock."""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TARGETS = [
    ("Glushko Crater", 282.33, 8.11),
    ("Ohm Crater", 246.22, 18.32),
    ("Aristarchus Plateau", 309.26, 26.05),
    ("Reiner Gamma", 301.64, 7.2),
    ("Orientale Basin", 265.33, -19.37),
    ("Vavilov Crater", 221.23, -0.87),
    # The target list repeats a few names. The map keeps one label.
    ("Glushko Crater", 282.33, 8.11),
    ("Reiner Gamma", 301.64, 7.2),
]


def _node(script: str) -> dict:
    completed = subprocess.run(
        ["node", "-e", script],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def test_feature_labels_do_not_overlap_at_several_map_sizes():
    script = r"""
const { project, placeLabels, chooseFont, overlap } = require("./demo/logic.js");
const targets = %s;
const sizes = [[360, 240], [180, 120], [720, 480], [1280, 320], [240, 160]];
const measure = (name, px) => name.length * px * 0.56;
const report = [];
for (const [width, height] of sizes) {
  const names = [...new Set(targets.map((row) => row[0]))];
  const font = chooseFont(names, width, Math.max(11, Math.round(width / 32)), measure);
  const bounds = { x: 2, y: 2, x2: width - 2, y2: height - 2 };
  const anchors = names.map((name) => {
    const row = targets.find((item) => item[0] === name);
    const [x, y] = project(row[1], row[2], width, height);
    return { name, x, y, w: measure(name, font), h: font + 2 };
  });
  const placed = placeLabels(anchors, bounds);
  const hits = [];
  for (let i = 0; i < placed.length; i += 1) {
    for (let j = i + 1; j < placed.length; j += 1) {
      if (overlap(placed[i], placed[j], 2)) hits.push([placed[i].name, placed[j].name]);
    }
  }
  const outside = placed.filter((row) => row.x < bounds.x || row.y < bounds.y || row.x2 > bounds.x2 || row.y2 > bounds.y2);
  const pair = placed.filter((row) => row.name === "Glushko Crater" || row.name === "Reiner Gamma");
  report.push({
    width, height, font,
    count: placed.length,
    hits,
    outside: outside.map((row) => row.name),
    glushkoReiner: pair.length === 2 ? !overlap(pair[0], pair[1], 2) : false,
  });
}
console.log(JSON.stringify(report));
""" % json.dumps(TARGETS)
    report = _node(script)
    assert len(report) == 5
    for row in report:
        assert row["count"] == 6, row
        assert row["hits"] == [], row
        assert row["outside"] == [], row
        assert row["glushkoReiner"] is True, row


def test_clocks_show_utc_and_edt_and_met_from_the_guide():
    script = r"""
const { formatClocks } = require("./demo/logic.js");
const launch = Date.parse("2026-04-01T22:35:12Z");
const flyby = Date.parse("2026-04-06T19:33:00Z");
const cab = Date.parse("2026-04-06T22:36:03Z");
console.log(JSON.stringify({
  flyby: formatClocks(flyby, launch),
  cab: formatClocks(cab, launch),
  bare: formatClocks(flyby, null),
  start: formatClocks(launch, launch),
}));
"""
    clocks = _node(script)
    assert clocks["flyby"]["utc"] == "19:33:00 UTC"
    assert clocks["flyby"]["eastern"] == "15:33:00 EDT"
    # Five days to 22:35:12Z, then back 3h 2m 12s.
    assert clocks["flyby"]["met"] == "116:57:48 MET"
    assert clocks["cab"]["utc"] == "22:36:03 UTC"
    assert clocks["cab"]["eastern"] == "18:36:03 EDT"
    assert clocks["cab"]["met"] == "120:00:51 MET"
    assert clocks["bare"]["met"] is None
    assert clocks["start"]["met"] == "0:00:00 MET"
