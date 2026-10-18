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


def test_open_controls_sit_below_the_corner_clock():
    script = r"""
const { hudTopPad } = require("./demo/logic.js");
const cases = [
  { clockBottom: 42, hudTop: 0, base: 18, gap: 10 },
  { clockBottom: 8, hudTop: 0, base: 18, gap: 10 },
  { clockBottom: 90, hudTop: 0, base: 18, gap: 12 },
  { clockBottom: NaN, hudTop: 0, base: 18, gap: 10 },
];
console.log(JSON.stringify(cases.map((row) => ({
  clockBottom: Number.isFinite(row.clockBottom) ? row.clockBottom : null,
  hudTop: row.hudTop,
  base: row.base,
  gap: row.gap,
  pad: hudTopPad(row.clockBottom, row.hudTop, row.base, row.gap),
  missing: !Number.isFinite(row.clockBottom),
}))));
"""
    rows = _node(script)
    for row in rows:
        if row["missing"]:
            assert row["pad"] == row["base"]
            continue
        content_top = row["hudTop"] + row["pad"]
        assert content_top >= row["clockBottom"] + row["gap"] - 1e-6
        assert row["pad"] >= row["base"]


def test_cab_crossfade_is_complete_at_the_real_capture_time():
    script = r"""
const { crossfade, holdMotion, HOLD_FADE_MS } = require("./demo/logic.js");
const current = Date.parse("2026-04-06T22:39:03.000Z");
const next = Date.parse("2026-04-06T22:39:33.000Z");
const samples = [-1, 0, HOLD_FADE_MS, HOLD_FADE_MS / 2, 1].map((delta) => {
  const now = delta < 0 ? current : next - (HOLD_FADE_MS - delta);
  const row = crossfade(now, current, next, HOLD_FADE_MS);
  return { delta, now, mix: row.mix, dominant: row.dominant };
});
const at = crossfade(next, current, next, HOLD_FADE_MS);
const before = crossfade(next - 1, current, next, HOLD_FADE_MS);
const early = crossfade(next - HOLD_FADE_MS - 1000, current, next, HOLD_FADE_MS);
const shortGap = crossfade(current + 1500, current, current + 2000, HOLD_FADE_MS);
const start = holdMotion(0, 0, 0, 0, 0, 0);
const end = holdMotion(1, 0, 0, 0, 0, 0);
console.log(JSON.stringify({
  fadeMs: HOLD_FADE_MS,
  at, before, early, shortGap,
  scale0: start.scale,
  scale1: end.scale,
  delta: end.scale - start.scale,
}));
"""
    row = _node(script)
    assert row["fadeMs"] == 4000
    assert row["at"]["mix"] == 1
    assert row["at"]["dominant"] == "next"
    assert row["before"]["mix"] < 1
    assert row["before"]["dominant"] == "next"
    assert row["early"]["mix"] == 0
    assert row["early"]["dominant"] == "current"
    # A shorter gap still finishes on the incoming frame's own timestamp.
    assert abs(row["shortGap"]["mix"] - 0.75) < 1e-9
    assert row["shortGap"]["dominant"] == "next"
    assert row["scale0"] >= 1
    assert abs(row["delta"] - 0.035) < 1e-9
    assert row["delta"] <= 0.04


def test_on_glass_credit_names_the_affiliation():
    text = (ROOT / "demo" / "app.js").read_text()
    assert text.count("not affiliated with NASA") == 2
    assert "Independent viewer, not a NASA product" not in text
    assert 'credit.textContent = ""' not in text


def test_phone_gate_swipe_and_small_image_plan():
    script = r"""
const logic = require("./demo/logic.js");
const rows = {
  gateDesktop: logic.gateLabel(false),
  gateTouch: logic.gateLabel(true),
  touchCoarse: logic.isTouchDevice(true, false, false),
  touchHover: logic.isTouchDevice(false, true, false),
  touchPoints: logic.isTouchDevice(false, 5, false),
  finePointer: logic.isTouchDevice(false, false, true),
  fineWins: logic.isTouchDevice(true, true, true),
  mouse: logic.isTouchDevice(false, false, false),
  swipeLeft: logic.swipeWindow(-80, 10, 48),
  swipeRight: logic.swipeWindow(80, 4, 48),
  swipeShort: logic.swipeWindow(47, 0, 48),
  swipeVertical: logic.swipeWindow(10, 90, 48),
  swipeDiagonal: logic.swipeWindow(60, 60, 48),
  swipeNone: logic.swipeWindow(null, 0, 48),
  full: logic.variantFile("images/art002e009611.webp", false),
  small: logic.variantFile("images/art002e009611.webp", true),
  already: logic.variantFile("images/art002e009611.720.webp", true),
  audio: logic.variantFile("audio/art002a000021.m4a", true),
  missing: logic.variantFile(null, true),
  narrow: logic.wantsSmallImage(true, false, "4g"),
  wifi: logic.wantsSmallImage(false, false, "4g"),
  save: logic.wantsSmallImage(false, true, "4g"),
  threeG: logic.wantsSmallImage(false, false, "3g"),
  twoG: logic.wantsSmallImage(false, false, "2g"),
  slow: logic.wantsSmallImage(false, false, "slow-2g"),
  emptyNet: logic.wantsSmallImage(false, false, ""),
  deskPrefetch: logic.prefetchBeforeTap(false),
  cellPrefetch: logic.prefetchBeforeTap(true),
  foldFull: logic.wantsSmallImage(true, false, "4g", true),
  fold3x: logic.wantsSmallImage(true, false, "4g", true, 3),
  fold1x: logic.wantsSmallImage(true, false, "4g", true, 1),
  foldSave: logic.wantsSmallImage(true, true, "4g", true),
  foldSlow: logic.wantsSmallImage(false, false, "3g", true),
  modeFold: logic.screenMode(890, 626, true),
  modeFoldShape: logic.screenMode(890, 626),
  modeFoldFine: logic.screenMode(890, 626, false),
  modeDeskShape: logic.screenMode(1024, 768),
  modeDeskFine: logic.screenMode(1024, 768, false),
  modeDeskCoarse: logic.screenMode(1024, 768, true),
  modeClosed: logic.screenMode(466, 678),
  modePhone: logic.screenMode(390, 844),
  modeSide: logic.screenMode(844, 390),
  modeDesk: logic.screenMode(1280, 720),
};
console.log(JSON.stringify(rows));
"""
    row = _node(script)
    assert row["gateDesktop"] == "Click or press any key to look out the window"
    assert row["gateTouch"] == "Tap to begin"
    assert row["touchCoarse"] is True
    assert row["touchHover"] is True
    assert row["touchPoints"] is False
    assert row["finePointer"] is False
    assert row["fineWins"] is False
    assert row["mouse"] is False
    assert row["swipeLeft"] == "3"
    assert row["swipeRight"] == "2"
    assert row["swipeShort"] is None
    assert row["swipeVertical"] is None
    assert row["swipeDiagonal"] is None
    assert row["swipeNone"] is None
    assert row["full"] == "images/art002e009611.webp"
    assert row["small"] == "images/art002e009611.720.webp"
    assert row["already"] == "images/art002e009611.720.webp"
    assert row["audio"] == "audio/art002a000021.m4a"
    assert row["missing"] is None
    assert row["narrow"] is True
    assert row["wifi"] is False
    assert row["save"] is True
    assert row["threeG"] is True
    assert row["twoG"] is True
    assert row["slow"] is True
    assert row["emptyNet"] is False
    assert row["deskPrefetch"] == {"opener": True, "otherWindow": True, "audio": True}
    assert row["cellPrefetch"] == {"opener": True, "otherWindow": False, "audio": False}
    assert row["foldFull"] is False
    assert row["fold3x"] is False
    assert row["fold1x"] is True
    assert row["foldSave"] is True
    assert row["foldSlow"] is True
    assert row["modeFold"] == "fold"
    assert row["modeFoldShape"] == "desktop"
    assert row["modeFoldFine"] == "desktop"
    assert row["modeDeskShape"] == "desktop"
    assert row["modeDeskFine"] == "desktop"
    assert row["modeDeskCoarse"] == "fold"
    assert row["modeClosed"] == "phone"
    assert row["modePhone"] == "phone"
    assert row["modeSide"] == "phone"
    assert row["modeDesk"] == "desktop"


def test_fine_pointer_keeps_the_desktop_layout_and_mouse():
    """A 1024×768 window is the fold shape. Fold still needs a coarse pointer.
    Touch points do not count when the primary pointer is fine."""
    script = r"""
const logic = require("./demo/logic.js");
console.log(JSON.stringify({
  desk1024: logic.screenMode(1024, 768, false),
  desk1024bare: logic.screenMode(1024, 768),
  fold1024: logic.screenMode(1024, 768, true),
  foldOpen: logic.screenMode(890, 626, true),
  foldFine: logic.screenMode(890, 626, false),
  shortFine: logic.screenMode(844, 390, false),
  wideFine: logic.screenMode(800, 600, false),
  coarse: logic.isTouchDevice(true, false, false),
  hoverNone: logic.isTouchDevice(false, true, false),
  touchPoints: logic.isTouchDevice(false, 5),
  fineWithPoints: logic.isTouchDevice(false, false, true),
  fineAndCoarse: logic.isTouchDevice(true, true, true),
}));
"""
    row = _node(script)
    assert row["desk1024"] == "desktop"
    assert row["desk1024bare"] == "desktop"
    assert row["fold1024"] == "fold"
    assert row["foldOpen"] == "fold"
    assert row["foldFine"] == "desktop"
    assert row["shortFine"] == "phone"
    assert row["wideFine"] == "desktop"
    assert row["coarse"] is True
    assert row["hoverNone"] is True
    assert row["touchPoints"] is False
    assert row["fineWithPoints"] is False
    assert row["fineAndCoarse"] is False


def test_transcript_slice_uses_only_real_lines():
    script = r"""
const { transcriptSlice } = require("./demo/logic.js");
const lines = [
  { utc: "2026-04-06T19:40:10.000Z", speaker: "Koch", text: "Earlier.", track: "pcd3" },
  { utc: "2026-04-06T19:40:16.489Z", speaker: "Wiseman", text: "Out the north side, yeah, this is just weird, man.", track: "pcd3" },
  { utc: "2026-04-06T19:40:22.000Z", speaker: "Glover", text: "Other loop.", track: "pcd2" },
  { utc: "2026-04-06T19:40:24.000Z", speaker: "Koch", text: "Next.", track: "pcd3" },
];
const now = Date.parse("2026-04-06T19:40:18.000Z");
const slice = transcriptSlice(lines, now, "pcd3", 25000, 12000);
console.log(JSON.stringify(slice));
"""
    rows = _node(script)
    assert [row["text"] for row in rows] == [
        "Earlier.",
        "Out the north side, yeah, this is just weird, man.",
        "Next.",
    ]
    assert rows[1]["current"] is True
    assert rows[0]["speaker"] == "Koch"
    assert all(row["text"] != "Other loop." for row in rows)


def test_collapsed_map_keeps_readable_labels():
    script = r"""
const { project, placeLabels, chooseFont, overlap } = require("./demo/logic.js");
const targets = [
  ["Glushko Crater", 282.33, 8.11],
  ["Ohm Crater", 246.22, 18.32],
  ["Aristarchus Plateau", 309.26, 26.05],
  ["Reiner Gamma", 301.64, 7.2],
  ["Orientale Basin", 265.33, -19.37],
  ["Vavilov Crater", 221.23, -0.87],
];
const measure = (name, px) => name.length * px * 0.56;
const sizes = [[186, 176, 12], [240, 160, 13]];
const report = sizes.map(([width, height, base]) => {
  const font = chooseFont(targets.map((row) => row[0]), width, base, measure, 0.96);
  const anchors = targets.map((row) => {
    const [x, y] = project(row[1], row[2], width, height);
    return { name: row[0], x, y, w: measure(row[0], font), h: font + 2 };
  });
  const placed = placeLabels(anchors, { x: 4, y: 4, x2: width - 4, y2: height - 4 });
  let hits = 0;
  for (let i = 0; i < placed.length; i += 1) {
    for (let j = i + 1; j < placed.length; j += 1) {
      if (overlap(placed[i], placed[j], 1)) hits += 1;
    }
  }
  return { width, height, font, hits, count: placed.length };
});
console.log(JSON.stringify(report));
"""
    rows = _node(script)
    assert len(rows) == 2
    for row in rows:
        assert row["font"] >= 12
        assert row["hits"] == 0
        assert row["count"] == 6


def _overlap_area(a, b):
    if not a or not b:
        return 0
    width = min(a["x"] + a["w"], b["x"] + b["w"]) - max(a["x"], b["x"])
    height = min(a["y"] + a["h"], b["y"] + b["h"]) - max(a["y"], b["y"])
    if width <= 0 or height <= 0:
        return 0
    return width * height


def test_desktop_card_clears_the_credit_and_subtitle():
    """The cabin card misses the credit and the subtitle at every pointer.

    Fine letterbox and large coarse screens share one clearance: the card
    sits on the credit band. Phones and the open Duo keep their own cards.
    """
    import threading
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    from playwright.sync_api import sync_playwright

    handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT / "demo"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    # width, height, coarse pointer, device scale
    sizes = [
        (1024, 768, False, 1),
        (1112, 834, False, 1),
        (1280, 720, False, 1),
        (1280, 800, False, 1),
        (1366, 768, False, 1),
        (1440, 900, False, 1),
        (1366, 1024, True, 1),
        (1400, 900, True, 1),
        (390, 844, True, 1),
        (844, 390, True, 1),
        (890, 626, True, 3),
    ]
    boxes = r"""
() => {
  const box = (el) => {
    const r = el.getBoundingClientRect();
    return {x: r.x, y: r.y, w: r.width, h: r.height};
  };
  const glance = document.getElementById('glance');
  return {
    glance: box(glance),
    credit: box(document.getElementById('credit')),
    subs: box(document.getElementById('subs')),
    shown: !glance.hidden && glance.getBoundingClientRect().height > 0,
  };
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            for width, height, coarse, scale in sizes:
                context = browser.new_context(
                    viewport={"width": width, "height": height},
                    has_touch=coarse,
                    device_scale_factor=scale,
                    reduced_motion="reduce",
                )
                page = context.new_page()
                page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
                page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
                page.click("#enter")
                page.evaluate(
                    """() => {
                      const scrub = document.getElementById('scrub');
                      const start = Date.parse('2026-04-06T19:33:00Z');
                      const end = Date.parse('2026-04-06T19:48:30Z');
                      scrub.value = String(Math.round((8000 / (end - start)) * 1000));
                      scrub.dispatchEvent(new Event('input', { bubbles: true }));
                    }"""
                )
                page.wait_for_function("() => !document.getElementById('glance').hidden")
                if page.locator("#play").inner_text().strip() == "Pause":
                    page.click("#play")
                page.wait_for_timeout(200)
                row = page.evaluate(boxes)
                context.close()
                assert row["shown"], (width, height)
                assert _overlap_area(row["glance"], row["credit"]) == 0, (width, height, row)
                assert _overlap_area(row["glance"], row["subs"]) == 0, (width, height, row)
                assert _overlap_area(row["subs"], row["credit"]) == 0, (width, height, row)
            # A third credit line is taller than the old 3.4em subtitle lift.
            narrow = browser.new_context(
                viewport={"width": 320, "height": 700},
                has_touch=False,
                reduced_motion="reduce",
            )
            page = narrow.new_page()
            page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
            page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
            page.click("#enter")
            page.evaluate(
                """() => {
                  const scrub = document.getElementById('scrub');
                  const start = Date.parse('2026-04-06T19:33:00Z');
                  const end = Date.parse('2026-04-06T19:48:30Z');
                  scrub.value = String(Math.round((8000 / (end - start)) * 1000));
                  scrub.dispatchEvent(new Event('input', { bubbles: true }));
                }"""
            )
            page.wait_for_timeout(300)
            wrapped = page.evaluate(
                """() => {
                  const credit = document.getElementById('credit');
                  const subs = document.getElementById('subs');
                  const box = (el) => {
                    const r = el.getBoundingClientRect();
                    return {x: r.x, y: r.y, w: r.width, h: r.height};
                  };
                  return {
                    credit: box(credit),
                    subs: box(subs),
                    text: credit.textContent,
                    measured: getComputedStyle(document.getElementById('stage')).getPropertyValue('--credit-measured').trim(),
                  };
                }"""
            )
            narrow.close()
            assert "not affiliated with NASA" in wrapped["text"]
            assert wrapped["credit"]["h"] > 45, wrapped
            assert _overlap_area(wrapped["subs"], wrapped["credit"]) == 0, wrapped
            assert wrapped["measured"].endswith("px")
            assert float(wrapped["measured"][:-2]) == wrapped["credit"]["h"] or abs(
                float(wrapped["measured"][:-2]) - wrapped["credit"]["h"]
            ) < 0.2
            browser.close()
    finally:
        server.shutdown()


def test_narrow_webp_variants_are_downscales_of_the_shipped_frames():
    images = ROOT / "demo" / "data" / "images"
    sources = sorted(path for path in images.glob("*.webp") if not path.name.endswith(".720.webp"))
    assert sources

    def dims(path: Path) -> tuple[int, int]:
        out = subprocess.check_output(
            [
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=width,height",
                "-of",
                "csv=p=0",
                str(path),
            ],
            text=True,
        ).strip()
        width, height = out.split(",")
        return int(width), int(height)

    for source in sources:
        variant = images / f"{source.stem}.720.webp"
        assert variant.is_file(), source.name
        assert variant.stat().st_size < source.stat().st_size
        sw, sh = dims(source)
        vw, vh = dims(variant)
        assert max(vw, vh) <= 720
        assert vw <= sw and vh <= sh
        assert max(vw, vh) == min(720, max(sw, sh))
