"""Clock tests against the real art002a000033 sample and the voice-loop CSVs."""

from datetime import datetime, timedelta, timezone
from pathlib import Path

from artemis2.index import probe_audio
from artemis2.labels import parse_label, parse_transcript_csv
from artemis2.timebase import audio_start, loop_pieces, parse_utc

FIXTURES = Path(__file__).parent / "fixtures"
A33_M4A = FIXTURES / "art002a000033_pcd2_raw_v01.m4a"
A33_XML = FIXTURES / "art002a000033_pcd2_raw_v01.xml"
A33_CSV = FIXTURES / "art002a000033_pcd2_trn-csv_v01.csv"
OE1 = FIXTURES / "art002_2026-04-06_oe1_trn-csv_v01.csv"
OE2_CSV = FIXTURES / "art002_2026-04-07_oe2_trn-csv_v01.csv"
OE2_XML = FIXTURES / "art002_2026-04-07_oe2_raw_v01.xml"


def test_a000033_start_from_embedded_end_and_exact_duration():
    probed = probe_audio(A33_M4A)
    assert probed["duration_s"] is not None
    end = probed["creation_time"]
    assert end == datetime(2026, 4, 6, 19, 48, 30, tzinfo=timezone.utc)
    start = audio_start(end, probed["duration_s"])
    assert start == datetime(2026, 4, 6, 19, 46, 14, 576000, tzinfo=timezone.utc)


def test_label_duration_is_truncated():
    label = parse_label(A33_XML)
    assert label.label_duration_s == 135
    assert label.start_utc.startswith("2026-04-06T19:46:14")
    # Whole-second label duration would land a second later than the real start.
    end, status = parse_utc(label.create_utc)
    assert status == "ok"
    coarse = audio_start(end, 135)
    assert coarse == datetime(2026, 4, 6, 19, 46, 15, tzinfo=timezone.utc)


def test_transcript_utc_matches_exact_start_within_the_floored_second():
    probed = probe_audio(A33_M4A)
    start = audio_start(probed["creation_time"], probed["duration_s"])
    rows = parse_transcript_csv(A33_CSV)
    assert rows[0].speaker == "Hansen"
    assert rows[0].utc == "2026-04-06T19:46:14.978Z"
    assert "Aristarchus" in rows[0].text
    for row in rows:
        assert row.utc_status == "ok"
        utc, status = parse_utc(row.utc)
        assert status == "ok"
        # audio_time is floored, so the true offset sits in [audio_s, audio_s + 1).
        delta = (utc - start).total_seconds() - row.audio_s
        assert 0 <= delta < 1.0


def test_voice_loop_is_piecewise_and_keeps_malformed_rows():
    rows = parse_transcript_csv(OE1)
    malformed = [row for row in rows if row.utc_status == "malformed"]
    assert len(malformed) == 1
    assert malformed[0].audio_time == "03:10:20"
    pieces_input = []
    for row in rows:
        utc, status = parse_utc(row.utc) if row.utc else (None, row.utc_status)
        pieces_input.append({"utc": utc if row.utc_status == "ok" else None, "audio_s": row.audio_s, "status": row.utc_status})
    pieces = loop_pieces(pieces_input)
    assert len(pieces) == 2
    jump = (
        datetime.fromisoformat(pieces[1]["implied_start"].replace("Z", "+00:00"))
        - datetime.fromisoformat(pieces[0]["implied_start"].replace("Z", "+00:00"))
    )
    assert jump > timedelta(hours=8)


def test_oe2_filename_day_disagrees_with_the_clock():
    label = parse_label(OE2_XML)
    assert "2026-04-07" in Path(OE2_XML).name
    assert label.start_utc.startswith("2026-04-06T22:32:21")
    rows = parse_transcript_csv(OE2_CSV)
    dated = [row for row in rows if row.utc_status == "date_only"]
    assert len(dated) == 3
    ok_days = {row.utc[:10] for row in rows if row.utc_status == "ok"}
    assert ok_days == {"2026-04-06"}
