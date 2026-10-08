"""``artemis2`` command line."""

from __future__ import annotations

from pathlib import Path

import typer

from artemis2 import __version__
from artemis2.atlas import (
    AtlasClient,
    SizeGuard,
    check_budget,
    collection_for,
)
from artemis2.doctor import doctor, format_report
from artemis2.export import export_replay, export_tables
from artemis2.index import index_tree
from artemis2.sync import build_timeline, parse_offsets

app = typer.Typer(add_completion=False, no_args_is_help=True, help="Artemis II PDS toolkit.")


def _version(value: bool) -> None:
    if value:
        typer.echo(__version__)
        raise typer.Exit()


@app.callback()
def main(version: bool = typer.Option(False, "--version", callback=_version, is_eager=True)) -> None:
    """List, fetch, index, and sync the Artemis II lunar-science release."""


@app.command("list")
def list_products(
    bundle: str = typer.Option(None, help="Bundle id, for example artemis2_crew_camera."),
    collection: str = typer.Option(None),
    instrument: str = typer.Option(None, help="gather.common.instrument value, such as nikon_d5."),
    fd: int = typer.Option(None, help="Accepted for filtering client-side on flight_day_number when present."),
    start: str = typer.Option(None, help="UTC lower bound."),
    end: str = typer.Option(None, help="UTC upper bound."),
    limit: int = typer.Option(50),
    sum_: bool = typer.Option(False, "--sum", help="Print counts and bytes instead of rows."),
) -> None:
    """List products from the public Atlas search API."""
    with AtlasClient() as client:
        if sum_:
            filters: list[dict] = [{"term": {"archive.fs_type": "file"}}]
            if bundle:
                filters.append({"term": {"archive.bundle_id": bundle}})
            if collection:
                filters.append({"term": {"archive.collection_id": collection}})
            body = {
                "size": 0,
                "query": {"bool": {"filter": filters}},
                "aggs": {
                    "bytes": {"sum": {"field": "archive.size"}},
                    "collections": {"terms": {"field": "archive.collection_id", "size": 30}},
                },
            }
            payload = client.search(body)
            total = payload["hits"]["total"]["value"]
            nbytes = payload["aggregations"]["bytes"]["value"]
            typer.echo(f"files {total}  bytes {nbytes:.0f}  ({nbytes / 1e9:.3f} GB)")
            for bucket in payload["aggregations"]["collections"]["buckets"]:
                typer.echo(f"  {bucket['key']}  {bucket['doc_count']}")
            return
        count = 0
        for hit in client.iter_hits(
            bundle=bundle,
            collection=collection,
            instrument=instrument,
            start=start,
            end=end,
            limit=limit,
        ):
            source = hit.get("_source", {})
            archive = source.get("archive") or {}
            gather = source.get("gather") or {}
            when = (gather.get("time") or {}).get("start_time", "")
            day = (gather.get("flyby_missions") or {}).get("flight_day_number")
            if fd is not None and day is not None and int(day) != fd:
                continue
            name = archive.get("name") or (gather.get("pds_archive") or {}).get("file_name") or hit.get("_id")
            size = archive.get("size")
            typer.echo(f"{when:24}  {size or 0:12}  {name}")
            count += 1
        typer.echo(f"{count} shown", err=True)


@app.command()
def fetch(
    target: list[str] = typer.Argument(None, help="Archive path, atlas URI, or file name."),
    bundle: str = typer.Option("artemis2_crew_camera"),
    collection: str = typer.Option(None),
    level: str = typer.Option("browse", help="browse, prc, raw, or src. Default is browse."),
    thumb: str = typer.Option("lg", help="md, lg, or none. Default lg derivative of a browse image."),
    labels_only: bool = typer.Option(False),
    start: str = typer.Option(None),
    end: str = typer.Option(None),
    max_gb: float = typer.Option(0.5, help="Refuse to exceed this many gigabytes without --yes."),
    yes: bool = typer.Option(False, "--yes", help="Allow downloads above --max-gb."),
    out: Path = typer.Option(Path("data"), help="Destination root."),
    limit: int = typer.Option(100),
) -> None:
    """Download products. Defaults to browse derivatives, with a size cap."""
    thumb_value = None if thumb in {"none", "full", ""} else thumb
    max_bytes = int(max_gb * 1e9)
    with AtlasClient() as client:
        jobs = _fetch_jobs(
            client,
            target or [],
            bundle=bundle,
            collection=collection or collection_for(bundle, level),
            start=start,
            end=end,
            limit=limit,
            thumb=thumb_value,
            labels_only=labels_only,
        )
        planned = sum(job["bytes"] for job in jobs)
        if not thumb_value and not labels_only:
            check_budget(planned, max_bytes, yes)
        for job in jobs:
            dest = out / job["relative"]
            try:
                client.download(job["uri"], dest, thumb=job.get("thumb"), expected_md5=job.get("md5"), max_bytes=max_bytes)
            except SizeGuard as exc:
                typer.echo(str(exc), err=True)
                raise typer.Exit(2) from exc
            typer.echo(f"{dest}  {dest.stat().st_size}")


def _fetch_jobs(client, targets, *, bundle, collection, start, end, limit, thumb, labels_only) -> list[dict]:
    jobs = []
    if targets:
        for item in targets:
            name = item.rstrip("/").rsplit("/", 1)[-1]
            if labels_only and not name.endswith(".xml"):
                item = str(Path(item).with_suffix(".xml"))
                name = item.rsplit("/", 1)[-1]
            suffix = Path(name).suffix.lower()
            use_thumb = thumb if suffix in {".png", ".jpg", ".jpeg"} else None
            relative = name + (f".{use_thumb}.webp" if use_thumb else "")
            jobs.append(
                {
                    "uri": item,
                    "relative": relative,
                    "bytes": 80_000 if use_thumb else 0,
                    "thumb": use_thumb,
                    "md5": None,
                }
            )
        return jobs
    for hit in client.iter_hits(bundle=bundle, collection=collection, start=start, end=end, limit=limit):
        source = hit.get("_source", {})
        archive = source.get("archive") or {}
        uri = source.get("uri") or hit.get("_id")
        name = archive.get("name") or uri.rsplit("/", 1)[-1]
        if labels_only:
            xml = str(Path(name).with_suffix(".xml"))
            jobs.append(
                {
                    "uri": uri.rsplit("/", 1)[0] + "/" + xml if "/" in uri else xml,
                    "relative": xml,
                    "bytes": 400_000,
                    "thumb": None,
                    "md5": None,
                }
            )
            continue
        use_thumb = thumb if Path(name).suffix.lower() in {".png", ".jpg", ".jpeg"} else None
        jobs.append(
            {
                "uri": uri,
                "relative": name + (f".{use_thumb}.webp" if use_thumb else ""),
                "bytes": 80_000 if use_thumb else int(archive.get("size") or 0),
                "thumb": use_thumb,
                "md5": None if use_thumb else archive.get("md5"),
            }
        )
    return jobs


@app.command()
def index(
    directory: Path = typer.Argument(..., help="Local tree of labels, transcripts, inventories, audio."),
    out: Path = typer.Option(Path("catalog.sqlite"), "--out"),
    parquet: Path = typer.Option(None, help="Also write Parquet tables into this directory."),
) -> None:
    """Parse PDS4 labels and inventories into SQLite."""
    counts = index_tree(directory, out)
    typer.echo(f"wrote {out}")
    for key, value in counts.items():
        typer.echo(f"  {key} {value}")
    if parquet:
        written = export_tables(out, parquet, kind="parquet")
        for path in written:
            typer.echo(f"  parquet {path}")


@app.command()
def sync(
    catalog: Path = typer.Option(Path("catalog.sqlite"), "--catalog"),
    start: str = typer.Option("2026-04-06T19:33:00Z"),
    end: str = typer.Option("2026-04-06T19:48:30Z"),
    camera_offset: str = typer.Option("", "--camera-offset", help="nkd5015=+0.5,nkz9019=-1"),
    out: Path = typer.Option(None, help="Write the timeline JSON here."),
) -> None:
    """Build one UTC timeline. Audio start is embedded end time minus exact duration."""
    timeline = build_timeline(str(catalog), start, end, parse_offsets(camera_offset))
    typer.echo(
        f"audio {len(timeline['audio'])}  lines {len(timeline['lines'])}  images {len(timeline['images'])}"
    )
    for segment in timeline["audio"]:
        typer.echo(f"  {segment['track']:6} {segment['exact_start']}  {segment['nasa_id']}  {segment['timing']}")
    if timeline["nearest_pairs"]:
        typer.echo("nearest line/image pairs (image time minus line time, seconds)")
        for pair in timeline["nearest_pairs"]:
            typer.echo(f"  {pair['delta_s']:+8.3f}  {pair['speaker']:10} {pair['image_nasa_id']}")
    if out:
        import json

        out.write_text(json.dumps(timeline, indent=2), encoding="utf-8")
        typer.echo(f"wrote {out}")


@app.command()
def export(
    kind: str = typer.Argument(..., help="replay, csv, or parquet."),
    catalog: Path = typer.Option(Path("catalog.sqlite"), "--catalog"),
    start: str = typer.Option("2026-04-06T19:33:00Z"),
    end: str = typer.Option("2026-04-06T19:48:30Z"),
    out: Path = typer.Option(Path("demo/data"), "--out"),
    images: Path = typer.Option(None, help="Directory of thumbnail images named by NASA id."),
    camera_offset: str = typer.Option("", "--camera-offset"),
    bitrate: str = typer.Option("64k"),
) -> None:
    """Export demo data or flat tables."""
    if kind in {"csv", "parquet"}:
        written = export_tables(catalog, out, kind=kind)
        for path in written:
            typer.echo(path)
        return
    if kind != "replay":
        raise typer.BadParameter("kind must be replay, csv, or parquet")
    summary = export_replay(
        catalog,
        out,
        start=start,
        end=end,
        image_dir=images,
        camera_offsets=parse_offsets(camera_offset),
        bitrate=bitrate,
    )
    for key, value in summary.items():
        typer.echo(f"{key} {value}")


@app.command("doctor")
def doctor_cmd(
    directory: Path = typer.Argument(None, help="Optional local sample or archive tree."),
) -> None:
    """Report known data quirks. Pass a directory to check the files you have."""
    report = doctor(directory)
    typer.echo(format_report(report))
