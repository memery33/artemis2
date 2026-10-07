from pathlib import Path

from artemis2.export import export_tables
from artemis2.index import index_tree

FIXTURES = Path(__file__).parent / "fixtures"


def test_csv_export_roundtrip(tmp_path: Path):
    db = tmp_path / "catalog.sqlite"
    index_tree(FIXTURES, db)
    written = export_tables(db, tmp_path / "csv", kind="csv")
    text = Path(written[0]).read_text(encoding="utf-8")
    assert "art002e009600" in text
    audio = (tmp_path / "csv" / "audio.csv").read_text(encoding="utf-8")
    assert "2026-04-06T19:46:14.576Z" in audio
