"""PDS4 label and transcript parsers.

Namespace prefixes differ across products, so elements are matched on local
name. Geometry is reduced to a footprint before anything is written to the
catalog; the raw control-point cloud stays in memory only for that reduction.
"""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass, field
from pathlib import Path

from lxml import etree

from artemis2.geometry import as_lonlat, assess_axes, footprint_polygon
from artemis2.speakers import normalize_speaker
from artemis2.timebase import audio_time_seconds, format_utc, parse_utc

_FILENAME = re.compile(
    r"^(?P<nasa>art002(?:[eam]\d+|_\d{4}-\d{2}-\d{2}))_(?P<inst>[A-Za-z0-9]+)_(?P<ptype>[A-Za-z0-9-]+)_v\d+\."
)


@dataclass
class ImageProduct:
    path: str
    lid: str = ""
    product_class: str = ""
    file_name: str = ""
    nasa_id: str = ""
    instrument: str = ""
    product_type: str = ""
    title: str = ""
    start_utc: str = ""
    start_status: str = ""
    stop_utc: str = ""
    flight_day: int | None = None
    activity_id: str = ""
    target_id: str = ""
    secondary_targets: list[str] = field(default_factory=list)
    create_utc: str = ""
    label_duration_s: float | None = None
    lines: int | None = None
    samples: int | None = None
    focal_length_mm: float | None = None
    n_control_points: int = 0
    has_geometry: bool = False
    axis_swapped: bool | None = None
    footprint_trust: str = "none"
    footprint_lonlat: list[list[float]] = field(default_factory=list)
    kind: str = "other"  # image, audio, document


@dataclass
class TranscriptRow:
    path: str
    nasa_id: str
    instrument: str
    audio_time: str
    audio_s: float | None
    utc: str
    utc_status: str
    speaker_raw: str
    speaker: str
    role: str
    text: str


def ids_from_filename(name: str) -> tuple[str, str, str]:
    match = _FILENAME.match(Path(name).name)
    if not match:
        return "", "", ""
    return match.group("nasa"), match.group("inst").lower(), match.group("ptype").lower()


def _local(element) -> str:
    return etree.QName(element).localname


def _text(element, name: str) -> str:
    for child in element.iter():
        if _local(child) == name and child.text and child.text.strip():
            return child.text.strip()
    return ""


def _float(value: str) -> float | None:
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_label(path: str | Path) -> ImageProduct:
    path = Path(path)
    tree = etree.parse(str(path))
    root = tree.getroot()
    product = ImageProduct(path=str(path), product_class=_text(root, "product_class"), title=_text(root, "title"))
    product.lid = _text(root, "logical_identifier")
    product.file_name = _text(root, "file_name") or path.name
    nasa_id, instrument, product_type = ids_from_filename(product.file_name)
    if not nasa_id:
        nasa_id, instrument, product_type = ids_from_filename(path.name)
    product.nasa_id = nasa_id
    product.instrument = instrument
    product.product_type = product_type
    description = _text(root, "description")
    inst_match = re.search(r"instance_id=([A-Za-z0-9]+)", description)
    if inst_match and not product.instrument:
        product.instrument = inst_match.group(1).lower()

    start_raw = _direct_time(root, "start_date_time")
    stop_raw = _direct_time(root, "stop_date_time")
    start, start_status = parse_utc(start_raw)
    stop, _stop_status = parse_utc(stop_raw)
    product.start_status = start_status
    product.start_utc = format_utc(start) if start and start_status == "ok" else ""
    product.stop_utc = format_utc(stop) if stop and _stop_status == "ok" else ""
    fd = _text(root, "flight_day_number")
    product.flight_day = int(fd) if fd.isdigit() else None
    product.activity_id = _first(root, "activity_id")
    targets = _all(root, "target_id")
    # The first target_id inside Observational_Intent is the primary. Later
    # ones are secondary. Moon as the observation target is a different element
    # (Target_Identification/name) and is not target_id.
    product.target_id = targets[0] if targets else ""
    product.secondary_targets = targets[1:]
    create, _ = parse_utc(_text(root, "create_date"))
    product.create_utc = format_utc(create, millis=False) if create else ""
    product.label_duration_s = _float(_text(root, "duration_seconds"))
    product.lines, product.samples = _array_size(root)
    product.focal_length_mm = _float(_text(root, "focal_length"))
    controls, corners = _pixels(root)
    product.n_control_points = len(controls)
    axis = assess_axes(product.lines, product.samples, controls + corners)
    product.axis_swapped = axis["names_swapped_vs_display_axes"] if (controls or corners) else None
    ring, trust = footprint_polygon(corners, controls)
    product.footprint_trust = trust
    product.footprint_lonlat = as_lonlat(ring)
    product.has_geometry = trust != "none"
    if product.label_duration_s is not None or product.create_utc:
        product.kind = "audio"
    elif product.lines or product.samples or product_type in {"src", "raw", "prc"}:
        product.kind = "image"
    elif product.product_class == "Product_Document" or product_type in {"ann"}:
        product.kind = "document"
    return product


def _direct_time(root, name: str) -> str:
    """First time coordinate, ignoring nil values."""
    for element in root.iter():
        if _local(element) == name and element.text and element.text.strip():
            return element.text.strip()
    return ""


def _first(root, name: str) -> str:
    for element in root.iter():
        if _local(element) == name and element.text and element.text.strip():
            return element.text.strip()
    return ""


def _all(root, name: str) -> list[str]:
    found = []
    for element in root.iter():
        if _local(element) == name and element.text and element.text.strip():
            found.append(element.text.strip())
    return found


def _array_size(root) -> tuple[int | None, int | None]:
    lines = samples = None
    for element in root.iter():
        if _local(element) != "Axis_Array":
            continue
        axis_name = ""
        count = None
        for child in element:
            if _local(child) == "axis_name" and child.text:
                axis_name = child.text.strip()
            elif _local(child) == "elements" and child.text:
                try:
                    count = int(float(child.text))
                except ValueError:
                    count = None
        if axis_name == "Line":
            lines = count
        elif axis_name == "Sample":
            samples = count
    return lines, samples


def _pixels(root) -> tuple[list[dict], list[dict]]:
    controls: list[dict] = []
    corners: list[dict] = []
    for element in root.iter():
        if _local(element) != "Pixel_Intercept":
            continue
        point = _pixel(element)
        if point is None:
            continue
        parent_is_corner = False
        # lxml getparent
        parent = element.getparent()
        while parent is not None:
            if _local(parent) == "Footprint_Vertices":
                parent_is_corner = True
                break
            parent = parent.getparent()
        (corners if parent_is_corner else controls).append(point)
    return controls, corners


def _pixel(element) -> dict | None:
    point: dict = {}
    for child in element.iter():
        name = _local(child)
        if name == "vertical_coordinate_pixel" and child.text:
            point["vertical"] = float(child.text)
        elif name == "horizontal_coordinate_pixel" and child.text:
            point["horizontal"] = float(child.text)
        elif name == "pixel_latitude" and child.text:
            point["lat"] = float(child.text)
        elif name == "pixel_longitude" and child.text:
            point["lon"] = float(child.text)
    if "vertical" not in point and "lat" not in point:
        return None
    return point


def parse_transcript_csv(path: str | Path) -> list[TranscriptRow]:
    path = Path(path)
    nasa_id, instrument, _ptype = ids_from_filename(path.name)
    rows: list[TranscriptRow] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for raw in reader:
            utc_text = (raw.get("utc") or "").strip()
            utc, status = parse_utc(utc_text)
            speaker_raw = raw.get("speaker") or ""
            speaker, role = normalize_speaker(speaker_raw)
            rows.append(
                TranscriptRow(
                    path=str(path),
                    nasa_id=nasa_id,
                    instrument=instrument,
                    audio_time=(raw.get("audio_time") or "").strip(),
                    audio_s=audio_time_seconds(raw.get("audio_time")),
                    utc=format_utc(utc) if utc and status == "ok" else "",
                    utc_status=status,
                    speaker_raw=speaker_raw,
                    speaker=speaker,
                    role=role,
                    text=(raw.get("text") or "").strip(),
                )
            )
    return rows


def parse_inventory(path: str | Path) -> list[str]:
    """Collection inventory: ``P,<lidvid>`` rows. Returns logical identifiers."""
    lids = []
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(",")
        token = parts[-1].strip()
        if token.startswith("urn:"):
            lids.append(token.split("::", 1)[0])
    return lids


def parse_targets(path: str | Path) -> list[dict]:
    import json

    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    targets = []
    for item in payload:
        props = item.get("target_properties") or item
        lat = _maybe_float(props.get("latitude"))
        lon = _maybe_float(props.get("longitude"))
        start, status = parse_utc(str(props.get("start_date_time") or ""))
        targets.append(
            {
                "name": props.get("target_name") or "",
                "ltp_name": props.get("ltp_name") or "",
                "order": str(props.get("order") or ""),
                "latitude": lat,
                "longitude": lon,
                "start_utc": format_utc(start) if start and status == "ok" else "",
                "geographic": lat is not None and lon is not None and not (lat == 0 and lon == 0),
            }
        )
    return targets


def _maybe_float(value) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
