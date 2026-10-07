import sqlite3
from pathlib import Path

from typer.testing import CliRunner

from artemis2.atlas import SizeGuard, check_budget, chunks, data_url
from artemis2.cli import app
from artemis2.doctor import doctor
from artemis2.index import index_tree
from artemis2.sync import build_timeline

FIXTURES = Path(__file__).parent / "fixtures"
RUNNER = CliRunner()


def test_index_sync_and_doctor(tmp_path: Path):
    db = tmp_path / "catalog.sqlite"
    counts = index_tree(FIXTURES, db)
    assert counts["audio"] >= 5
    assert counts["images"] == 1
    assert counts["lines"] > 100
    assert counts["targets"] == 39

    timeline = build_timeline(str(db), "2026-04-06T19:33:00Z", "2026-04-06T19:48:30Z")
    audio = [row for row in timeline["audio"] if row["nasa_id"] == "art002a000033"]
    assert len(audio) == 1
    assert audio[0]["exact_start"] == "2026-04-06T19:46:14.576Z"
    assert audio[0]["track"] == "pcd2"
    hansen = [row for row in timeline["lines"] if row["nasa_id"] == "art002a000033" and row["speaker"] == "Hansen"]
    assert hansen
    assert hansen[0]["utc"] == "2026-04-06T19:46:14.978Z"
    # The Orientale frame is 18:19 UTC, outside this window.
    assert timeline["images"] == []

    wider = build_timeline(str(db), "2026-04-06T18:00:00Z", "2026-04-06T19:00:00Z")
    assert wider["images"][0]["nasa_id"] == "art002e009600"
    assert wider["images"][0]["footprint_trust"] == "control_hull"
    assert wider["images"][0]["axis_swapped"] is True

    report = doctor(db_path=db)
    by_id = {item["id"]: item for item in report["checks"]}
    assert by_id["a000033"]["ok"] is True
    assert "19:46:14.576" in by_id["a000033"]["detail"]
    assert by_id["axes"]["ok"] is True
    assert by_id["hertzsprung"]["ok"] is True
    assert by_id["orphan-a000052"]["ok"] is True
    assert by_id["oe2-date"]["ok"] is True
    assert any(item["id"] == "loop-pieces" for item in report["checks"])
    assert any(item["id"].startswith("dup-") for item in report["checks"])

    conn = sqlite3.connect(db)
    activities = dict(conn.execute("SELECT nasa_id, activity_id FROM audio WHERE nasa_id IN ('art002a000001','art002a000003')"))
    conn.close()
    assert activities["art002a000001"] != activities["art002a000003"]


def test_cli_doctor_and_sync(tmp_path: Path):
    db = tmp_path / "catalog.sqlite"
    indexed = RUNNER.invoke(app, ["index", str(FIXTURES), "--out", str(db)])
    assert indexed.exit_code == 0, indexed.output
    synced = RUNNER.invoke(
        app,
        ["sync", "--catalog", str(db), "--start", "2026-04-06T19:46:00Z", "--end", "2026-04-06T19:48:30Z"],
    )
    assert synced.exit_code == 0, synced.output
    assert "19:46:14.576" in synced.output
    documented = RUNNER.invoke(app, ["doctor", str(FIXTURES)])
    assert documented.exit_code == 0, documented.output
    assert "footprint-axes" in documented.output
    assert "spice-delayed" in documented.output


def test_atlas_guards_and_thumbnail_url():
    assert [len(part) for part in chunks(list(range(100)), 40)] == [40, 40, 20]
    url = data_url("artemis2_crew_camera/browse/fd06/art002e009600_nkd5015_prc_v01.png", "lg")
    assert url.endswith("art002e009600_nkd5015_prc_v01.png:lg")
    try:
        data_url("artemis2_crew_camera/data_processed/fd06/art002e009600_nkd5015_prc_v01.tif", "md")
    except Exception as exc:
        assert "TIFF" in str(exc) or "tif" in str(exc).lower()
    else:
        raise AssertionError("thumbnail suffix on a TIFF must be refused")
    try:
        check_budget(int(2e9), int(0.5e9), confirmed=False)
    except SizeGuard:
        pass
    else:
        raise AssertionError("size guard should trip")
    check_budget(int(2e9), int(0.5e9), confirmed=True)
