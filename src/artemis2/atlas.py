"""Client for the PDS Cartography & Imaging Sciences Atlas IV API.

Listing uses ``POST /api/search/atlas/_search``. Bytes use
``GET /api/data/atlas:pds4:artemis2:artemis2:/<bundle>/<path>``. Browse
derivatives append ``:md`` (512 px) or ``:lg`` (1024 px) and are WebP.
The suffix is only valid on PNG and JPEG products. Applied to a TIFF it is
ignored and the full file comes back, so thumbnail downloads are capped.

The public AWS API Gateway in the Atlas front end denies anonymous callers
and is not used. Queries send ``terms`` lists in batches of 40 because the
WAF rejects large bodies.
"""

from __future__ import annotations

import hashlib
import time
from pathlib import Path
from typing import Iterator

import httpx

SEARCH_URL = "https://pds-imaging.jpl.nasa.gov/api/search/atlas/_search"
DATA_PREFIX = "https://pds-imaging.jpl.nasa.gov/api/data/"
URI_PREFIX = "atlas:pds4:artemis2:artemis2:"
GEO_PREFIX = "https://pds-geosciences.wustl.edu/artemis2/"
USER_AGENT = "artemis2/0.1 (PDS research client; contact via the GitHub repo)"
THUMB_SUFFIXES = {".png", ".jpg", ".jpeg"}
MAX_THUMB_BYTES = 3_000_000
TERMS_BATCH = 40

LEVEL_COLLECTION = {
    "artemis2_crew_camera": {
        "browse": "browse",
        "prc": "data_processed",
        "raw": "data_raw",
        "src": "data_source",
    },
    "artemis2_orion_camera": {
        "browse": "browse_source",
        "raw": "data_raw_image",
        "src": "data_video",
    },
    "artemis2_mission_audio": {
        "browse": "data_audio_pcd",
        "raw": "data_audio_pcd",
        "src": "data_audio_pcd",
    },
}


class AtlasError(RuntimeError):
    pass


class SizeGuard(AtlasError):
    """Raised when a download would exceed the configured byte cap."""


def chunks(items: list, size: int = TERMS_BATCH) -> Iterator[list]:
    if size < 1:
        raise ValueError("batch size must be positive")
    for start in range(0, len(items), size):
        yield items[start : start + size]


def product_uri(path_or_uri: str) -> str:
    text = path_or_uri.strip()
    if text.startswith("atlas:"):
        return text
    if text.startswith("urn:nasa:pds:"):
        raise AtlasError("pass an archive path or an atlas: URI, not a bare LID")
    return URI_PREFIX + "/" + text.lstrip("/")


def data_url(path_or_uri: str, thumb: str | None = None) -> str:
    uri = product_uri(path_or_uri)
    if thumb:
        if thumb not in {"md", "lg"}:
            raise AtlasError(f"unknown thumbnail size {thumb!r}")
        name = uri.rsplit("/", 1)[-1]
        suffix = Path(name).suffix.lower()
        if suffix not in THUMB_SUFFIXES:
            raise AtlasError(
                f"refusing :{thumb} on {name}; the resize suffix is only applied to PNG and JPEG"
            )
        return DATA_PREFIX + uri + f":{thumb}"
    return DATA_PREFIX + uri


def check_budget(total_bytes: int, max_bytes: int, confirmed: bool) -> None:
    if total_bytes > max_bytes and not confirmed:
        raise SizeGuard(
            f"download is {total_bytes / 1e9:.2f} GB and the cap is {max_bytes / 1e9:.2f} GB. "
            "Pass --yes to proceed. Processed TIFFs alone are about 1.7 TB."
        )


class AtlasClient:
    def __init__(self, min_interval: float = 1.0, timeout: float = 75.0):
        self.min_interval = min_interval
        self._last = 0.0
        self._client = httpx.Client(
            timeout=timeout,
            follow_redirects=True,
            headers={"User-Agent": USER_AGENT},
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "AtlasClient":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _pace(self) -> None:
        wait = self.min_interval - (time.monotonic() - self._last)
        if wait > 0:
            time.sleep(wait)
        self._last = time.monotonic()

    def search(self, body: dict, attempts: int = 3) -> dict:
        last: Exception | None = None
        for attempt in range(attempts):
            self._pace()
            try:
                response = self._client.post(SEARCH_URL, json=body)
            except httpx.HTTPError as exc:
                last = exc
                time.sleep(2 + attempt * 3)
                continue
            if response.status_code in {429, 500, 502, 503, 504}:
                last = AtlasError(f"search HTTP {response.status_code}")
                time.sleep(2 + attempt * 4)
                continue
            if response.status_code == 403:
                raise AtlasError(
                    "Atlas returned 403. The WAF rejects large query bodies; "
                    "terms lists must stay at or under 40 values."
                )
            response.raise_for_status()
            return response.json()
        raise AtlasError(f"search failed: {last}")

    def iter_hits(
        self,
        *,
        bundle: str | None = None,
        collection: str | None = None,
        name_prefix: str | None = None,
        instrument: str | None = None,
        start: str | None = None,
        end: str | None = None,
        page_size: int = 40,
        limit: int | None = None,
    ) -> Iterator[dict]:
        filters: list[dict] = [{"term": {"archive.fs_type": "file"}}]
        if bundle:
            filters.append({"term": {"archive.bundle_id": bundle}})
        if collection:
            filters.append({"term": {"archive.collection_id": collection}})
        if instrument:
            filters.append({"term": {"gather.common.instrument": instrument}})
        if name_prefix:
            filters.append({"prefix": {"archive.name": name_prefix}})
        if start or end:
            span: dict = {}
            if start:
                span["gte"] = start
            if end:
                span["lte"] = end
            filters.append({"range": {"gather.time.start_time": span}})
        body: dict = {
            "size": page_size,
            "query": {"bool": {"filter": filters}},
            "sort": [{"archive.name": "asc"}],
            "_source": [
                "uri",
                "archive.name",
                "archive.size",
                "archive.md5",
                "archive.bundle_id",
                "archive.collection_id",
                "archive.parent_uri",
                "gather.time.start_time",
                "gather.common.instrument",
                "gather.pds_archive.file_name",
                "gather.pds_archive.product_id",
                "gather.flyby_missions.flight_day_number",
            ],
        }
        yielded = 0
        search_after = None
        while True:
            if search_after is not None:
                body["search_after"] = search_after
            payload = self.search(body)
            hits = payload.get("hits", {}).get("hits", [])
            if not hits:
                return
            for hit in hits:
                yield hit
                yielded += 1
                if limit is not None and yielded >= limit:
                    return
            search_after = hits[-1].get("sort")
            if not search_after or len(hits) < page_size:
                return

    def download(
        self,
        path_or_uri: str,
        dest: Path,
        *,
        thumb: str | None = None,
        expected_md5: str | None = None,
        max_bytes: int | None = None,
    ) -> Path:
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        url = data_url(path_or_uri, thumb)
        cap = MAX_THUMB_BYTES if thumb else max_bytes
        tmp = dest.with_suffix(dest.suffix + ".part")
        last: Exception | None = None
        for attempt in range(3):
            self._pace()
            try:
                with self._client.stream("GET", url) as response:
                    if response.status_code in {429, 500, 502, 503, 504}:
                        last = AtlasError(f"GET HTTP {response.status_code}")
                        time.sleep(2 + attempt * 4)
                        continue
                    response.raise_for_status()
                    digest = hashlib.md5()
                    size = 0
                    with tmp.open("wb") as handle:
                        for chunk in response.iter_bytes():
                            size += len(chunk)
                            if cap is not None and size > cap:
                                tmp.unlink(missing_ok=True)
                                raise SizeGuard(
                                    f"{url} exceeded {cap} bytes. "
                                    "Thumbnail requests are capped so a missed :md/:lg suffix "
                                    "cannot pull a full TIFF."
                                )
                            digest.update(chunk)
                            handle.write(chunk)
                if expected_md5 and not thumb and digest.hexdigest() != expected_md5.lower():
                    tmp.unlink(missing_ok=True)
                    raise AtlasError(
                        f"md5 mismatch for {dest.name}: got {digest.hexdigest()} expected {expected_md5}"
                    )
                tmp.replace(dest)
                return dest
            except SizeGuard:
                raise
            except httpx.HTTPError as exc:
                last = exc
                time.sleep(2 + attempt * 3)
        raise AtlasError(f"download failed for {url}: {last}")


def collection_for(bundle: str, level: str) -> str | None:
    return LEVEL_COLLECTION.get(bundle, {}).get(level)
