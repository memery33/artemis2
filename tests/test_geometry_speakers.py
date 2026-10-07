from datetime import datetime, timedelta, timezone
from pathlib import Path

from artemis2.geometry import assess_axes, display_pixel, footprint_polygon
from artemis2.labels import parse_label, parse_targets
from artemis2.pointing import FixedBoresight, SpicePointingUnavailable
from artemis2.speakers import normalize_speaker
from artemis2.sync import clip_to_window, parse_offsets

FIXTURES = Path(__file__).parent / "fixtures"
IMAGE = FIXTURES / "art002e009600_nkd5015_prc_v01.xml"


def test_pixel_axis_names_are_swapped_on_the_real_label():
    product = parse_label(IMAGE)
    assert product.lines == 3712
    assert product.samples == 5568
    assert product.axis_swapped is True
    assert product.n_control_points > 100
    assert product.footprint_trust == "control_hull"
    assert product.has_geometry
    # A vertical coordinate of 5568 cannot be a line index.
    sample, line = display_pixel(5568, 3712, swapped=True)
    assert (sample, line) == (5568, 3712)
    assert sample > product.lines


def test_unswapped_reading_does_not_fit_the_corner():
    product = parse_label(IMAGE)
    # Reconstruct the corner extremes the assessor saw: vertical max is the sample count.
    axis = assess_axes(product.lines, product.samples, [{"vertical": 5568, "horizontal": 3712, "lat": 0, "lon": 0}])
    assert axis["names_swapped_vs_display_axes"] is True
    assert axis["sample_from"] == "vertical_coordinate_pixel"


def test_control_hull_when_corners_extrapolate():
    corners = [
        {"lat": -50.0, "lon": 220.0},
        {"lat": 10.0, "lon": 220.0},
        {"lat": 10.0, "lon": 300.0},
        {"lat": -50.0, "lon": 300.0},
    ]
    controls = [
        {"lat": -40.0, "lon": 240.0},
        {"lat": -10.0, "lon": 250.0},
        {"lat": -5.0, "lon": 280.0},
        {"lat": -30.0, "lon": 270.0},
    ]
    ring, trust = footprint_polygon(corners, controls)
    assert trust == "control_hull"
    lats = [lat for lat, _lon in ring]
    assert max(lats) < 5
    assert min(lats) > -45


def test_speaker_normalization_from_real_variants():
    assert normalize_speaker("Hansen ") == ("Hansen", "")
    assert normalize_speaker("Hansen [CAPCOM]") == ("Hansen", "CAPCOM")
    assert normalize_speaker("[SCIENCE] Wiseman") == ("Wiseman", "SCIENCE")
    assert normalize_speaker("Glover [CAPCOM]") == ("Glover", "CAPCOM")
    assert normalize_speaker("SCIENCE") == ("SCIENCE", "")
    assert normalize_speaker("") == ("", "")
    assert normalize_speaker(None) == ("", "")


def test_hertzsprung_is_not_geographic():
    targets = parse_targets(FIXTURES / "artemis2_outgoing_target_request.json")
    hertz = [item for item in targets if item["name"].startswith("Hertzsprung")]
    assert hertz and hertz[0]["geographic"] is False
    aristarchus = [item for item in targets if item["name"] == "Aristarchus Plateau"]
    assert aristarchus[0]["latitude"] == 26.05
    assert aristarchus[0]["longitude"] == 309.26
    assert aristarchus[0]["geographic"] is True


def test_pointing_interface_stays_empty_until_spice_exists():
    missing = SpicePointingUnavailable()
    assert missing.available() is False
    assert missing.boresight(datetime(2026, 4, 6, tzinfo=timezone.utc), "2") is None
    fixed = FixedBoresight(7.2, 301.64)
    shot = fixed.boresight(datetime(2026, 4, 6, 19, 46, tzinfo=timezone.utc), "2")
    assert shot.latitude_deg == 7.2
    assert shot.window_id == "2"
    assert shot.source == "fixed"


def test_clip_and_offsets():
    start = datetime(2026, 4, 6, 19, 46, 14, 576000, tzinfo=timezone.utc)
    end = start + timedelta(seconds=135.424)
    window_start = datetime(2026, 4, 6, 19, 33, tzinfo=timezone.utc)
    window_end = datetime(2026, 4, 6, 19, 48, 30, tzinfo=timezone.utc)
    clip = clip_to_window(start, end, window_start, window_end)
    assert clip is not None
    assert clip["offset_s"] == 0
    assert abs(clip["duration_s"] - 135.424) < 1e-6
    assert parse_offsets("nkd5015=+1.5, nkz9019=-0.25") == {"nkd5015": 1.5, "nkz9019": -0.25}
