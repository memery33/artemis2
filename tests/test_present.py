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
  const say = document.querySelector('#subs .say');
  return {
    glance: box(glance),
    credit: box(document.getElementById('credit')),
    subs: box(document.getElementById('subs')),
    shown: !glance.hidden && glance.getBoundingClientRect().height > 0,
    say: say ? say.textContent : '',
    font: say ? parseFloat(getComputedStyle(say).fontSize) : 0,
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
                assert row["say"] and row["font"] >= 14, (width, height, row)
            # A wrapped credit is taller than one line. The card has to use that
            # measured box, or its bottom cuts the first line.
            wraps = [(600, 800), (560, 800), (390, 844), (360, 740), (320, 700), (280, 640)]
            for width, height in wraps:
                narrow = browser.new_context(
                    viewport={"width": width, "height": height},
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
                page.wait_for_function("() => !document.getElementById('glance').hidden")
                if page.locator("#play").inner_text().strip() == "Pause":
                    page.click("#play")
                page.wait_for_timeout(200)
                wrapped = page.evaluate(
                    """() => {
                      const credit = document.getElementById('credit');
                      const subs = document.getElementById('subs');
                      const glance = document.getElementById('glance');
                      const box = (el) => {
                        const r = el.getBoundingClientRect();
                        return {x: r.x, y: r.y, w: r.width, h: r.height};
                      };
                      const say = document.querySelector('#subs .say');
                      const win = document.getElementById('window');
                      const range = document.createRange();
                      let lines = 0;
                      const walker = document.createTreeWalker(subs, NodeFilter.SHOW_TEXT);
                      let node;
                      while ((node = walker.nextNode())) {
                        if (!node.textContent.trim()) continue;
                        range.selectNodeContents(node);
                        for (const rect of range.getClientRects()) {
                          if (rect.width > 0 && rect.height > 0) lines += 1;
                        }
                      }
                      return {
                        glance: box(glance),
                        credit: box(credit),
                        subs: box(subs),
                        window: box(win),
                        text: credit.textContent,
                        say: say ? say.textContent : '',
                        font: say ? parseFloat(getComputedStyle(say).fontSize) : 0,
                        lines,
                        shown: !glance.hidden && glance.getBoundingClientRect().height > 0,
                        measured: getComputedStyle(document.getElementById('stage')).getPropertyValue('--credit-measured').trim(),
                      };
                    }"""
                )
                narrow.close()
                assert wrapped["shown"], (width, height, wrapped)
                assert "not affiliated with NASA" in wrapped["text"]
                assert wrapped["credit"]["h"] > 30, (width, height, wrapped)
                assert _overlap_area(wrapped["glance"], wrapped["credit"]) == 0, (width, height, wrapped)
                assert _overlap_area(wrapped["glance"], wrapped["subs"]) == 0, (width, height, wrapped)
                assert _overlap_area(wrapped["subs"], wrapped["credit"]) == 0, (width, height, wrapped)
                assert wrapped["say"] and wrapped["font"] >= 12.6, (width, height, wrapped)
                assert wrapped["measured"].endswith("px")
                assert abs(float(wrapped["measured"][:-2]) - wrapped["credit"]["h"]) < 0.2, (
                    width,
                    height,
                    wrapped,
                )
                if (width, height) in {(360, 740), (320, 700)}:
                    sub = wrapped["subs"]
                    win = wrapped["window"]
                    assert sub["w"] >= 160, (width, height, wrapped)
                    assert wrapped["lines"] <= 3, (width, height, wrapped)
                    assert sub["x"] >= win["x"] - 0.5, (width, height, wrapped)
                    assert sub["y"] >= win["y"] - 0.5, (width, height, wrapped)
                    assert sub["x"] + sub["w"] <= win["x"] + win["w"] + 0.5, (width, height, wrapped)
                    assert sub["y"] + sub["h"] <= win["y"] + win["h"] + 0.5, (width, height, wrapped)
            browser.close()
    finally:
        server.shutdown()


def _inside(inner, outer, slop=0.5):
    return (
        inner["x"] >= outer["x"] - slop
        and inner["y"] >= outer["y"] - slop
        and inner["x"] + inner["w"] <= outer["x"] + outer["w"] + slop
        and inner["y"] + inner["h"] <= outer["y"] + outer["h"] + slop
    )


def test_fine_pointer_subtitle_clears_the_card_across_widths():
    """Every fine-pointer width keeps the subtitle, card, and credit apart.

    The sweep is the structural check: two heights, and widths from 280 to
    1440 in 20px steps, plus the sizes just past the old 600px cutoff.
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
    widths = list(range(280, 1441, 20))
    for extra in (601, 649):
        if extra not in widths:
            widths.append(extra)
    widths.sort()
    heights = (800, 480)
    measure = r"""
() => {
  const box = (el) => {
    const r = el.getBoundingClientRect();
    return {x: r.x, y: r.y, w: r.width, h: r.height};
  };
  const subs = document.getElementById('subs');
  const glance = document.getElementById('glance');
  const range = document.createRange();
  let lines = 0;
  const walker = document.createTreeWalker(subs, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    if (!node.textContent.trim()) continue;
    range.selectNodeContents(node);
    for (const rect of range.getClientRects()) {
      if (rect.width > 0 && rect.height > 0) lines += 1;
    }
  }
  const say = document.querySelector('#subs .say');
  return {
    glance: box(glance),
    credit: box(document.getElementById('credit')),
    subs: box(subs),
    clocks: box(document.getElementById('clocks')),
    window: box(document.getElementById('window')),
    glass: box(document.getElementById('glass')),
    lines,
    font: say ? parseFloat(getComputedStyle(say).fontSize) : 0,
    shown: !glance.hidden && glance.getBoundingClientRect().height > 0,
    mode: document.getElementById('stage').className,
  };
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            context = browser.new_context(
                viewport={"width": 1024, "height": 800},
                has_touch=False,
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
            for height in heights:
                for width in widths:
                    page.set_viewport_size({"width": width, "height": height})
                    page.evaluate(
                        "() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
                    )
                    row = page.evaluate(measure)
                    where = (width, height, row.get("mode"), row)
                    assert row["shown"], where
                    assert _overlap_area(row["glance"], row["credit"]) == 0, where
                    assert _overlap_area(row["glance"], row["subs"]) == 0, where
                    assert _overlap_area(row["subs"], row["credit"]) == 0, where
                    assert row["subs"]["w"] >= 160, where
                    assert row["lines"] <= 3, where
                    assert row["font"] >= 12.6, where
                    sub = row["subs"]
                    if "subs-bezel" in row["mode"]:
                        clock_bottom = row["clocks"]["y"] + row["clocks"]["h"]
                        assert sub["y"] + sub["h"] <= row["glass"]["y"] + 0.5, where
                        assert sub["y"] >= clock_bottom - 0.5, where
                        assert _overlap_area(sub, row["clocks"]) == 0, where
                        assert sub["y"] >= -0.5, where
                        assert sub["y"] + sub["h"] <= height + 0.5, where
                        assert sub["x"] >= -0.5, where
                        assert sub["x"] + sub["w"] <= width + 0.5, where
                    else:
                        assert _inside(sub, row["window"]), where
                        assert _inside(sub, row["glass"]), where
            context.close()
            browser.close()
    finally:
        server.shutdown()


def test_long_quote_stays_inside_the_glass_when_no_card_is_beside():
    """The longest PCD3 line stays whole on a narrow fine-pointer window.

    No cabin card is beside the subtitle. If the glass can hold it in three
    lines, it stays there. Otherwise the whole line sits on the bezel, under
    the clock and inside the viewport. It is never cut.
    """
    import threading
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    from playwright.sync_api import sync_playwright

    full = (
        "All right, I am going to just take [[shutter clicks]] some [[shutter clicks]] "
        "perpendicular [[shutter clicks]] to the window [[shutter clicks]] pictures, "
        "zooming out and zooming out and zooming out."
    )
    handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT / "demo"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    sizes = [(width, 800) for width in range(280, 421, 20)]
    sizes += [(width, 480) for width in (280, 300, 320)]
    measure = r"""
() => {
  const glass = document.getElementById('glass').getBoundingClientRect();
  const subs = document.getElementById('subs');
  const say = subs.querySelector('.say');
  const range = document.createRange();
  const rects = [];
  const walker = document.createTreeWalker(subs, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    if (!node.textContent.trim()) continue;
    range.selectNodeContents(node);
    for (const rect of range.getClientRects()) {
      if (rect.width <= 0 || rect.height <= 0) continue;
      rects.push({x: rect.x, y: rect.y, w: rect.width, h: rect.height, t: node.textContent.slice(0, 24)});
    }
  }
  const sub = subs.getBoundingClientRect();
  const credit = document.getElementById('credit').getBoundingClientRect();
  const clocks = document.getElementById('clocks').getBoundingClientRect();
  return {
    say: say ? say.textContent : '',
    full: say ? (say.dataset.full || '') : '',
    font: say ? parseFloat(getComputedStyle(say).fontSize) : 0,
    rects,
    glass: {x: glass.x, y: glass.y, w: glass.width, h: glass.height},
    subs: {x: sub.x, y: sub.y, w: sub.width, h: sub.height},
    credit: {x: credit.x, y: credit.y, w: credit.width, h: credit.height},
    clocks: {x: clocks.x, y: clocks.y, w: clocks.width, h: clocks.height},
    card: !document.getElementById('glance').hidden,
    bezel: document.getElementById('stage').classList.contains('subs-bezel'),
    scale: getComputedStyle(document.getElementById('stage')).getPropertyValue('--subs-scale').trim(),
  };
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            context = browser.new_context(
                viewport={"width": 360, "height": 800},
                has_touch=False,
                reduced_motion="reduce",
            )
            page = context.new_page()
            page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
            page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
            page.wait_for_function(
                """() => {
                  document.getElementById('enter').click();
                  return document.getElementById('stage').classList.contains('live');
                }"""
            )
            page.evaluate(
                """() => {
                  const scrub = document.getElementById('scrub');
                  const start = Date.parse('2026-04-06T19:33:00Z');
                  const end = Date.parse('2026-04-06T19:48:30Z');
                  const t = Date.parse('2026-04-06T19:46:23.000Z');
                  scrub.value = String(Math.round(((t - start) / (end - start)) * 1000));
                  scrub.dispatchEvent(new Event('input', { bubbles: true }));
                }"""
            )
            page.wait_for_function(
                """() => {
                  const say = document.querySelector('#subs .say');
                  return say && (say.dataset.full || say.textContent || '').includes('perpendicular');
                }"""
            )
            if page.locator("#play").inner_text().strip() == "Pause":
                page.click("#play")
            for width, height in sizes:
                page.set_viewport_size({"width": width, "height": height})
                page.evaluate(
                    "() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
                )
                row = page.evaluate(measure)
                where = (width, height, row)
                assert row["full"].startswith(full[:40]), where
                assert row["say"] == row["full"] == full, where
                assert "…" not in row["say"], where
                assert not row["card"], where
                assert row["font"] >= 12.6, where
                assert _overlap_area(row["subs"], row["credit"]) == 0, where
                assert _overlap_area(row["subs"], row["clocks"]) == 0, where
                clock_bottom = row["clocks"]["y"] + row["clocks"]["h"]
                assert row["subs"]["y"] >= clock_bottom - 0.5, where
                assert row["subs"]["y"] >= -0.5, where
                assert row["subs"]["y"] + row["subs"]["h"] <= height + 0.5, where
                if row["bezel"]:
                    assert row["subs"]["y"] + row["subs"]["h"] <= row["glass"]["y"] + 0.5, where
                else:
                    assert 1 <= len(row["rects"]) <= 3, where
                    assert _inside(row["subs"], row["glass"]), where
                    for rect in row["rects"]:
                        assert _inside(rect, row["glass"]), where
            context.close()
            browser.close()
    finally:
        server.shutdown()


def test_narrow_bezel_keeps_the_whole_quote():
    """Under 320px the longest line is on the bezel, uncut, and clear of the credit.

    The rail is hidden on a fine pointer, so a shortened caption cannot be
    read anywhere else. The speaker sits above the glass, not on its edge.
    """
    import threading
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    from playwright.sync_api import sync_playwright

    full = (
        "All right, I am going to just take [[shutter clicks]] some [[shutter clicks]] "
        "perpendicular [[shutter clicks]] to the window [[shutter clicks]] pictures, "
        "zooming out and zooming out and zooming out."
    )
    handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT / "demo"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    measure = r"""
() => {
  const box = (el) => {
    const r = el.getBoundingClientRect();
    return {x: r.x, y: r.y, w: r.width, h: r.height};
  };
  const subs = document.getElementById('subs');
  const say = subs.querySelector('.say');
  const who = subs.querySelector('.who');
  const glass = document.getElementById('glass');
  return {
    say: say ? say.textContent : '',
    full: say ? (say.dataset.full || '') : '',
    label: subs.getAttribute('aria-label') || '',
    sayOverflow: say ? getComputedStyle(say).overflow : '',
    sayWrap: say ? getComputedStyle(say).overflowWrap : '',
    subs: box(subs),
    who: who ? box(who) : null,
    glass: box(glass),
    credit: box(document.getElementById('credit')),
    clocks: box(document.getElementById('clocks')),
    bezel: document.getElementById('stage').classList.contains('subs-bezel'),
  };
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            context = browser.new_context(
                viewport={"width": 280, "height": 800},
                has_touch=False,
                reduced_motion="reduce",
            )
            page = context.new_page()
            page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
            page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
            page.wait_for_function(
                """() => {
                  document.getElementById('enter').click();
                  return document.getElementById('stage').classList.contains('live');
                }"""
            )
            page.evaluate(
                """() => {
                  const scrub = document.getElementById('scrub');
                  const start = Date.parse('2026-04-06T19:33:00Z');
                  const end = Date.parse('2026-04-06T19:48:30Z');
                  const t = Date.parse('2026-04-06T19:46:23.000Z');
                  scrub.value = String(Math.round(((t - start) / (end - start)) * 1000));
                  scrub.dispatchEvent(new Event('input', { bubbles: true }));
                }"""
            )
            page.wait_for_function(
                """() => {
                  const say = document.querySelector('#subs .say');
                  return say && (say.dataset.full || '').includes('perpendicular');
                }"""
            )
            if page.locator("#play").inner_text().strip() == "Pause":
                page.click("#play")
            for width, height in ((280, 800), (300, 800), (280, 480), (300, 480)):
                page.set_viewport_size({"width": width, "height": height})
                page.evaluate(
                    "() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
                )
                row = page.evaluate(measure)
                where = (width, height, row)
                assert row["bezel"], where
                assert row["say"] == full, where
                assert row["full"] == full, where
                assert "…" not in row["say"], where
                assert "…" not in row["label"], where
                assert full in row["label"], where
                assert row["sayOverflow"] == "visible", where
                assert row["sayWrap"] == "break-word", where
                pad = max(16, width * 0.02)
                assert row["subs"]["x"] >= pad - 0.5, where
                assert row["subs"]["x"] + row["subs"]["w"] <= width - pad + 0.5, where
                assert _overlap_area(row["subs"], row["credit"]) == 0, where
                assert _overlap_area(row["subs"], row["clocks"]) == 0, where
                clock_bottom = row["clocks"]["y"] + row["clocks"]["h"]
                assert row["subs"]["y"] >= clock_bottom - 0.5, where
                assert row["subs"]["y"] >= -0.5, where
                assert row["subs"]["x"] >= -0.5, where
                assert row["subs"]["x"] + row["subs"]["w"] <= width + 0.5, where
                assert row["subs"]["y"] + row["subs"]["h"] <= height + 0.5, where
                glass_top = row["glass"]["y"]
                assert row["subs"]["y"] + row["subs"]["h"] <= glass_top + 0.5, where
                assert row["who"], where
                assert row["who"]["y"] + row["who"]["h"] <= glass_top - 4, where
                if (width, height) == (280, 800):
                    assert row["subs"]["y"] < 230, where
                    assert row["subs"]["h"] > 110, where
            context.close()
            browser.close()
    finally:
        server.shutdown()


def test_no_timeline_quote_is_cut_on_a_narrow_fine_pointer():
    """Every transcript line stays whole from 280px through 600px.

    Heights 800 and 480, fine pointer, including 559px. No ellipsis, no
    clipped line, and every glyph inside the viewport. The subtitle stays
    under the clock and clear of the credit. A line the glass cannot hold
    in three lines sits on the bezel.
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
    widths = list(range(280, 601, 20))
    widths.append(559)
    widths.sort()
    heights = (800, 480)
    check = r"""
() => {
  const area = (a, b) => {
    const x = Math.max(a.x, b.x);
    const y = Math.max(a.y, b.y);
    const right = Math.min(a.x + a.w, b.x + b.w);
    const bottom = Math.min(a.y + a.h, b.y + b.h);
    return right > x && bottom > y ? (right - x) * (bottom - y) : 0;
  };
  const box = (el) => {
    const r = el.getBoundingClientRect();
    return {x: r.x, y: r.y, w: r.width, h: r.height};
  };
  const failures = [];
  const lines = window.__artemisLines || [];
  for (const line of lines) {
    const who = document.createElement("span");
    who.className = "who";
    who.textContent = line.speaker || "Crew";
    const say = document.createElement("span");
    say.className = "say";
    say.dataset.full = line.text;
    say.textContent = line.text;
    const subs = document.getElementById("subs");
    subs.replaceChildren(who, say);
    placeSubs();
    const sub = box(subs);
    const glass = box(document.getElementById("glass"));
    const clocks = box(document.getElementById("clocks"));
    const credit = box(document.getElementById("credit"));
    const glance = document.getElementById("glance");
    const card = box(glance);
    const sayNow = subs.querySelector(".say");
    const clipped = sayNow.scrollHeight > sayNow.clientHeight + 1
      || sayNow.scrollWidth > sayNow.clientWidth + 1;
    const reasons = [];
    if (sayNow.textContent !== line.text) reasons.push("text");
    if (sayNow.textContent.includes("…")) reasons.push("ellipsis");
    if ((subs.getAttribute("aria-label") || "").includes("…")) reasons.push("label");
    if (!subs.getAttribute("aria-label") || !subs.getAttribute("aria-label").includes(line.text)) {
      reasons.push("name");
    }
    if (clipped) reasons.push("clipped");
    if (sub.y < -0.5 || sub.x < -0.5 || sub.y + sub.h > window.innerHeight + 0.5
      || sub.x + sub.w > window.innerWidth + 0.5) reasons.push("viewport");
    if (area(sub, clocks) > 0 || sub.y < clocks.y + clocks.h - 0.5) reasons.push("clock");
    if (area(sub, credit) > 0) reasons.push("credit");
    if (!glance.hidden && card.w > 0 && area(sub, card) > 0) reasons.push("card");
    const bezel = document.getElementById("stage").classList.contains("subs-bezel");
    const range = document.createRange();
    const walker = document.createTreeWalker(subs, NodeFilter.SHOW_TEXT);
    let node;
    let linesN = 0;
    let outside = false;
    let glyphOut = false;
    while ((node = walker.nextNode())) {
      if (!node.textContent.trim()) continue;
      range.selectNodeContents(node);
      for (const rect of range.getClientRects()) {
        if (rect.width <= 0 || rect.height <= 0) continue;
        linesN += 1;
        if (rect.left < -0.5 || rect.top < -0.5
          || rect.right > window.innerWidth + 0.5
          || rect.bottom > window.innerHeight + 0.5) {
          glyphOut = true;
        }
        if (!bezel && (rect.top < glass.y - 0.5 || rect.bottom > glass.y + glass.h + 0.5
          || rect.left < glass.x - 0.5 || rect.right > glass.x + glass.w + 0.5)) {
          outside = true;
        }
      }
    }
    if (glyphOut) reasons.push("glyph");
    if (bezel) {
      if (sub.y + sub.h > glass.y + 0.5) reasons.push("glass");
    } else {
      if (linesN < 1 || linesN > 3) reasons.push("lines");
      if (outside) reasons.push("outside");
    }
    if (reasons.length) {
      failures.push({
        utc: line.utc,
        why: reasons.join(","),
        n: line.text.length,
        head: line.text.slice(0, 48),
      });
      if (failures.length >= 6) break;
    }
  }
  return {count: lines.length, failures};
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            context = browser.new_context(
                viewport={"width": 360, "height": 800},
                has_touch=False,
                reduced_motion="reduce",
            )
            page = context.new_page()
            page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
            page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
            page.wait_for_function(
                """() => {
                  document.getElementById('enter').click();
                  return document.getElementById('stage').classList.contains('live');
                }"""
            )
            page.evaluate(
                """async () => {
                  const doc = await fetch('data/timeline.json').then((res) => res.json());
                  window.__artemisLines = doc.lines.filter((line) => line.text && line.text.trim());
                }"""
            )
            page.evaluate(
                """() => {
                  const scrub = document.getElementById('scrub');
                  const start = Date.parse('2026-04-06T19:33:00Z');
                  const end = Date.parse('2026-04-06T19:48:30Z');
                  const t = Date.parse('2026-04-06T19:46:23.000Z');
                  scrub.value = String(Math.round(((t - start) / (end - start)) * 1000));
                  scrub.dispatchEvent(new Event('input', { bubbles: true }));
                }"""
            )
            page.wait_for_function(
                """() => {
                  const say = document.querySelector('#subs .say');
                  return say && (say.dataset.full || '').includes('perpendicular');
                }"""
            )
            if page.locator("#play").inner_text().strip() == "Pause":
                page.click("#play")
            for height in heights:
                for width in widths:
                    page.set_viewport_size({"width": width, "height": height})
                    row = page.evaluate(check)
                    assert row["count"] > 200, (width, height, row["count"])
                    assert row["failures"] == [], (width, height, row["failures"])
            context.close()
            browser.close()
    finally:
        server.shutdown()


def test_subtitle_moves_when_the_cabin_card_appears():
    """The centered line yields as soon as the card is shown, not on the next quote."""
    import threading
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    from playwright.sync_api import sync_playwright

    handler = partial(SimpleHTTPRequestHandler, directory=str(ROOT / "demo"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    sizes = [(width, 800) for width in (440, 480, 520, 560)]
    sizes += [(width, 480) for width in (380, 440, 500, 560)]
    measure = r"""
() => {
  const box = (el) => {
    const r = el.getBoundingClientRect();
    return {x: r.x, y: r.y, w: r.width, h: r.height};
  };
  const say = document.querySelector('#subs .say');
  return {
    glance: box(document.getElementById('glance')),
    subs: box(document.getElementById('subs')),
    shown: !document.getElementById('glance').hidden,
    say: say ? say.textContent : '',
    font: say ? parseFloat(getComputedStyle(say).fontSize) : 0,
  };
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            context = browser.new_context(
                viewport={"width": 480, "height": 800},
                has_touch=False,
                reduced_motion="reduce",
            )
            page = context.new_page()
            page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
            page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
            page.wait_for_function(
                """() => {
                  document.getElementById('enter').click();
                  return document.getElementById('stage').classList.contains('live');
                }"""
            )

            def seek(iso):
                page.evaluate(
                    """(iso) => {
                      const scrub = document.getElementById('scrub');
                      const start = Date.parse('2026-04-06T19:33:00Z');
                      const end = Date.parse('2026-04-06T19:48:30Z');
                      const t = Date.parse(iso);
                      scrub.value = String(Math.round(((t - start) / (end - start)) * 1000));
                      scrub.dispatchEvent(new Event('input', { bubbles: true }));
                    }""",
                    iso,
                )

            seek("2026-04-06T19:33:03.200Z")
            page.wait_for_function(
                """() => (document.querySelector('#subs .say') || {}).textContent
                  && document.querySelector('#subs .say').textContent.includes('diving back')"""
            )
            if page.locator("#play").inner_text().strip() == "Pause":
                page.click("#play")
            for width, height in sizes:
                page.set_viewport_size({"width": width, "height": height})
                seek("2026-04-06T19:33:03.200Z")
                page.wait_for_function("() => document.getElementById('glance').hidden")
                seek("2026-04-06T19:33:04.500Z")
                page.wait_for_function("() => !document.getElementById('glance').hidden")
                page.evaluate(
                    "() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
                )
                row = page.evaluate(measure)
                where = (width, height, row)
                assert row["shown"], where
                assert "diving back" in row["say"], where
                assert row["font"] >= 14, where
                assert _overlap_area(row["glance"], row["subs"]) == 0, where
            context.close()
            browser.close()
    finally:
        server.shutdown()


def test_fold_transcript_scrolls_clear_of_the_dock():
    """Fold transcript text stays in the rail, including while the window drifts.

    The rail is the open-fold column. Other coarse sizes in that shape get
    the same check. A fine pointer never shows the rail.
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
    # width, height, device scale. All coarse. 890×626 is the open Duo.
    layouts = [
        (890, 626, 1),
        (890, 626, 3),
        (800, 600, 1),
        (1024, 768, 1),
        (1200, 800, 1),
        (624, 520, 1),
    ]
    # Rest, then the corners of the window's drift (look ±10px, float on top).
    drifts = [
        (0, 0, 0),
        (13, 8.5, 0.11),
        (-13, 8.5, -0.11),
        (13, -8.5, 0.11),
        (-13, -8.5, -0.11),
        (13, 0, 0),
        (-13, 0, 0),
        (0, 8.5, 0),
        (0, -8.5, 0),
    ]
    measure = r"""
() => {
  const boxOf = (el) => {
    const r = el.getBoundingClientRect();
    return {x: r.x, y: r.y, w: r.width, h: r.height};
  };
  const clip = (a, b) => {
    const x = Math.max(a.x, b.x);
    const y = Math.max(a.y, b.y);
    const right = Math.min(a.x + a.w, b.x + b.w);
    const bottom = Math.min(a.y + a.h, b.y + b.h);
    if (right - x <= 0 || bottom - y <= 0) return null;
    return {x, y, w: right - x, h: bottom - y};
  };
  const area = (a, b) => {
    const hit = clip(a, b);
    return hit ? hit.w * hit.h : 0;
  };
  const rail = document.getElementById('rail');
  const transcript = document.getElementById('transcript');
  const dock = document.getElementById('dock');
  const railBox = boxOf(rail);
  const transBox = boxOf(transcript);
  const dockBox = boxOf(dock);
  const railStyle = getComputedStyle(rail);
  const transStyle = getComputedStyle(transcript);
  // Line boxes keep their layout position through overflow:auto. That is the
  // plateau line sitting on the Full button. Only a clipping rail removes it.
  // The active line is checked against the transcript scrollport separately.
  const clips = railStyle.overflow === 'hidden' || railStyle.overflow === 'clip';
  const view = clips ? railBox : null;
  const range = document.createRange();
  let textOverlap = 0;
  let textRects = 0;
  const walker = document.createTreeWalker(transcript, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    if (!node.textContent.trim()) continue;
    range.selectNodeContents(node);
    for (const rect of range.getClientRects()) {
      const piece = {x: rect.x, y: rect.y, w: rect.width, h: rect.height};
      const visible = view ? clip(piece, view) : piece;
      if (!visible) continue;
      textRects += 1;
      textOverlap += area(visible, dockBox);
    }
  }
  const now = transcript.querySelector('.now');
  const nowBox = now ? boxOf(now) : null;
  const companion = document.getElementById('companion');
  companion.focus();
  const style = getComputedStyle(companion);
  const pad = (parseFloat(style.outlineWidth) || 0) + (parseFloat(style.outlineOffset) || 0);
  const button = boxOf(companion);
  const ring = {
    x: button.x - pad,
    y: button.y - pad,
    w: button.w + pad * 2,
    h: button.h + pad * 2,
  };
  return {
    shown: getComputedStyle(rail).display !== 'none' && railBox.h > 0,
    dock: getComputedStyle(dock).display !== 'none',
    textOverlap,
    textRects,
    railDock: area(railBox, dockBox),
    nowVisible: !!(nowBox && clip(nowBox, transBox)),
    minHeight: transStyle.minHeight,
    scroll: transcript.scrollTop,
    nowOffset: now ? now.offsetTop : 0,
    clientH: transcript.clientHeight,
    scrollH: transcript.scrollHeight,
    ringInside: area(ring, railBox) > 0 && ring.y >= railBox.y - 0.5 && ring.y + ring.h <= railBox.y + railBox.h + 0.5
      && ring.x >= railBox.x - 0.5 && ring.x + ring.w <= railBox.x + railBox.w + 0.5,
    outline: style.outlineStyle,
  };
}
"""
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="chrome", headless=True)
            for scale in (1, 3):
                group = [item for item in layouts if item[2] == scale]
                if not group:
                    continue
                context = browser.new_context(
                    viewport={"width": group[0][0], "height": group[0][1]},
                    has_touch=True,
                    device_scale_factor=scale,
                    reduced_motion="reduce",
                )
                page = context.new_page()
                page.goto(f"http://127.0.0.1:{port}/", wait_until="domcontentloaded")
                page.evaluate("() => sessionStorage.setItem('artemis2.hint','1')")
                page.wait_for_function(
                    """() => {
                      document.getElementById('enter').click();
                      return document.getElementById('stage').classList.contains('live');
                    }"""
                )
                page.evaluate(
                    """() => {
                      const scrub = document.getElementById('scrub');
                      const start = Date.parse('2026-04-06T19:33:00Z');
                      const end = Date.parse('2026-04-06T19:48:30Z');
                      scrub.value = String(Math.round((60000 / (end - start)) * 1000));
                      scrub.dispatchEvent(new Event('input', { bubbles: true }));
                    }"""
                )
                if page.locator("#play").inner_text().strip() == "Pause":
                    page.click("#play")
                page.wait_for_function("() => document.querySelector('#transcript .now')")
                for width, height, _scale in group:
                    page.set_viewport_size({"width": width, "height": height})
                    page.evaluate(
                        "() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))"
                    )
                    for dx, dy, rot in drifts:
                        page.evaluate(
                            """([x, y, turn]) => {
                              const win = document.getElementById('window');
                              win.style.transform = `translate(calc(-50% + ${x}px), calc(-50% + ${y}px)) rotate(${turn}deg)`;
                            }""",
                            [dx, dy, rot],
                        )
                        row = page.evaluate(measure)
                        where = (width, height, scale, dx, dy, row)
                        assert row["shown"] and row["dock"], where
                        assert row["textRects"] > 0, where
                        assert row["textOverlap"] == 0, where
                        assert row["minHeight"] == "0px", where
                        assert row["railDock"] == 0, where
                        assert row["nowVisible"], where
                        if row["nowOffset"] > row["clientH"]:
                            assert row["scroll"] > 0, where
                        assert row["ringInside"], where
                context.close()
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


def test_milestones_quote_real_timeline_fields():
    script = r"""
const { milestones, coverage, clockOffset, appearance } = require("./demo/logic.js");
const doc = require("./demo/data/timeline.json");
const rows = milestones(doc);
const frame = doc.frames.find((item) => item.nasa_id === "art002e041321");
const now = Date.parse("2026-04-06T19:34:05Z");
const flyby = coverage(doc, "flyby", "pcd3", "3");
console.log(JSON.stringify({
  ids: rows.map((row) => row.id),
  closest: rows.some((row) => /closest/i.test(row.label + row.source)),
  aristarchus: rows.find((row) => row.id === "quote:Aristarchus Plateau"),
  held: rows.find((row) => row.id === "photo:art002e041321"),
  offset: clockOffset(now, Date.parse(frame.utc)),
  appearance: appearance(frame),
  photos: flyby.photos,
  silent: coverage(doc, "flyby", "pcd3", "2").silent,
}));
"""
    row = _node(script)
    assert row["closest"] is False
    assert row["ids"][0] == "photo:art002e041321"
    assert "quote:Aristarchus Plateau" in row["ids"]
    assert "quote:Reiner Gamma" in row["ids"]
    assert "quote:Orientale Basin" in row["ids"]
    assert "audio:art002a000021" in row["ids"]
    assert row["aristarchus"]["label"] == "Wiseman: Alright team, we're diving back into Aristarchus."
    assert row["aristarchus"]["utc"] == "2026-04-06T19:33:02.700Z"
    assert row["aristarchus"]["source"].startswith("lines.utc")
    assert row["held"]["utc"] == "2026-04-06T19:26:43.000Z"
    assert row["held"]["jumpUtc"] == "2026-04-06T19:33:00.000Z"
    assert "bright patch" in row["appearance"]
    assert "nearly black" not in row["appearance"].lower()
    assert row["offset"] == "Photo taken 7 min 22 s before this clock. Not moved to match it."
    assert "2026-04-06T19:34:44.000Z" in row["photos"]
    assert "2026-04-06T19:26:43.000Z" not in row["photos"]
    assert row["silent"][0]["end"] == "2026-04-06T19:33:01.758Z"


def test_cab_cam_prefers_the_nearest_frame_inside_the_span():
    script = r"""
const { visibleCabPair, clockOffset } = require("./demo/logic.js");
const doc = require("./demo/data/timeline.json");
const start = Date.parse(doc.window.start);
const end = Date.parse(doc.window.end);
const at = (iso) => visibleCabPair(doc.frames, Date.parse(iso), start, end, 0);
const clock = at("2026-04-06T19:34:05Z");
const early = at("2026-04-06T19:33:10Z");
const tie = at("2026-04-06T19:38:44Z");
const afterTie = at("2026-04-06T19:38:45Z");
const empty = visibleCabPair(
  doc.frames,
  Date.parse("2026-04-06T19:33:10Z"),
  Date.parse("2026-04-06T19:33:00Z"),
  Date.parse("2026-04-06T19:33:30Z"),
  0,
);
console.log(JSON.stringify({
  clock: clock.current && clock.current.nasa_id,
  clockUtc: clock.current && clock.current.utc,
  clockOutside: clock.outside,
  age: clockOffset(Date.parse("2026-04-06T19:34:05Z"), Date.parse(clock.current.utc)),
  early: early.current && early.current.nasa_id,
  tie: tie.current && tie.current.nasa_id,
  afterTie: afterTie.current && afterTie.current.nasa_id,
  empty: empty.current && empty.current.nasa_id,
  emptyOutside: empty.outside,
  emptyNext: empty.next,
  emptyAge: clockOffset(Date.parse("2026-04-06T19:33:10Z"), Date.parse(empty.current.utc)),
}));
"""
    row = _node(script)
    assert row["clock"] == "art002e041322"
    assert row["clockUtc"] == "2026-04-06T19:34:44.000Z"
    assert row["clockOutside"] is False
    assert row["age"] == "Photo taken 39 s after this clock."
    assert row["early"] == "art002e041322"
    assert row["tie"] == "art002e041322"
    assert row["afterTie"] == "art002e041323"
    assert row["empty"] == "art002e041321"
    assert row["emptyOutside"] is True
    assert row["emptyNext"] is None
    assert "before this clock" in row["emptyAge"]


def test_dark_cab_frame_is_mostly_dark_with_a_middle_patch():
    from PIL import Image

    image = Image.open(ROOT / "demo/data/images/art002e041321.webp").convert("RGB")
    small = image.resize((80, 60))
    pixels = list(small.getdata())
    luminance = [0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in pixels]
    mean = sum(luminance) / len(luminance)
    assert mean < 15

    width, height = image.size
    step = 3
    bright = 0
    counted = 0
    sx = sy = 0
    source = image.convert("L").load()
    for y in range(0, height, step):
        for x in range(0, width, step):
            counted += 1
            if source[x, y] > 40:
                bright += 1
                sx += x
                sy += y
    assert bright > 0
    fraction = bright / counted
    assert fraction < 0.05
    assert 0.4 < (sx / bright) / width < 0.7
    assert 0.4 < (sy / bright) / height < 0.7
