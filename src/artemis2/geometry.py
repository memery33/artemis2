"""Image footprints and the swapped pixel-axis fields.

Processed Nikon labels store ``vertical_coordinate_pixel`` across the sample
axis (1 … samples, 5568 on the D5) and ``horizontal_coordinate_pixel`` across
the line axis (1 … lines, 3712 on the D5). The display direction in the same
label says the horizontal axis is Sample and the vertical axis is Line. The
field names are therefore swapped relative to the display axes.

This was checked on ``art002e009600`` (full disk, Orientale) and
``art002e009943`` (400 mm, Reiner Gamma). Mapping sample = vertical and
line = horizontal puts the control points on the lunar surface. The corner
whose vertical coordinate is 5568 cannot be a line index, because the image
only has 3712 lines.

Footprint corners are a homography extrapolated to the frame. On both checked
labels that extrapolation runs well past the control-point cloud (the guide
calls the fit affine; the label comment calls it a homography). Polygons
drawn by this package use the control-point convex hull when the corner box
is materially larger than the matched points.
"""

from __future__ import annotations

from typing import Iterable, Sequence


def assess_axes(
    lines: int | None,
    samples: int | None,
    points: Sequence[dict],
) -> dict:
    """Decide whether the pixel-axis names are swapped.

    ``points`` should include footprint corners. Corners carry the axis
    extremes even when control points do not reach the edge of the frame.
    """
    vertical = [float(p["vertical"]) for p in points if p.get("vertical") is not None]
    horizontal = [float(p["horizontal"]) for p in points if p.get("horizontal") is not None]
    vmax = max(vertical) if vertical else None
    hmax = max(horizontal) if horizontal else None
    swapped = False
    if lines and samples and vmax is not None and hmax is not None:
        swapped = vmax > lines and vmax <= samples + 1.5 and hmax <= lines + 1.5
    return {
        "lines": lines,
        "samples": samples,
        "vertical_max": vmax,
        "horizontal_max": hmax,
        "names_swapped_vs_display_axes": swapped,
        "sample_from": "vertical_coordinate_pixel" if swapped else "horizontal_coordinate_pixel",
        "line_from": "horizontal_coordinate_pixel" if swapped else "vertical_coordinate_pixel",
        "note": (
            "vertical_coordinate_pixel spans the sample axis and "
            "horizontal_coordinate_pixel spans the line axis. "
            "Display axes in the label are Sample (left to right) and Line (top to bottom)."
            if swapped
            else "Pixel-axis names agree with the line/sample counts, or the label has no corners to check."
        ),
    }


def display_pixel(vertical: float, horizontal: float, swapped: bool) -> tuple[float, float]:
    """Return ``(sample, line)`` with line increasing downward."""
    if swapped:
        return vertical, horizontal
    return horizontal, vertical


def _lon_span(lons: Iterable[float]) -> float:
    values = list(lons)
    if not values:
        return 0.0
    # These longitudes are 0–360 across the western hemisphere and do not
    # cross the branch cut. A wrapped span would be a different dataset.
    return max(values) - min(values)


def _bbox_area(points: Sequence[tuple[float, float]]) -> float:
    if len(points) < 2:
        return 0.0
    lats = [lat for lat, _lon in points]
    lons = [lon for _lat, lon in points]
    return max(0.0, max(lats) - min(lats)) * max(_lon_span(lons), 0.0)


def convex_hull(points: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    """Monotonic-chain hull of ``(lat, lon)`` points, closed, lon-lat order later.

    Returns ``(lat, lon)`` in counter-clockwise order, closed.
    """
    uniq = sorted(set((round(lat, 8), round(lon, 8)) for lat, lon in points))
    if len(uniq) <= 2:
        return list(uniq)
    # Hull in (lon, lat) so x is east.
    xy = sorted((lon, lat) for lat, lon in uniq)

    def cross(o, a, b) -> float:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[tuple[float, float]] = []
    for p in xy:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list[tuple[float, float]] = []
    for p in reversed(xy):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    ring = lower[:-1] + upper[:-1]
    # Back to (lat, lon), closed.
    out = [(lat, lon) for lon, lat in ring]
    if out and out[0] != out[-1]:
        out.append(out[0])
    return out


def footprint_polygon(
    corners: Sequence[dict],
    controls: Sequence[dict],
    *,
    area_ratio: float = 1.35,
) -> tuple[list[tuple[float, float]], str]:
    """Choose a geographic polygon.

    Returns ``([(lat, lon), ... closed], trust)``. ``trust`` is ``corners``
    when the extrapolated frame agrees with the control cloud, ``control_hull``
    when the corners run past the matched points, or ``none``.
    """
    corner_ll = [(float(p["lat"]), float(p["lon"])) for p in corners if _has_ll(p)]
    control_ll = [(float(p["lat"]), float(p["lon"])) for p in controls if _has_ll(p)]
    hull = convex_hull(control_ll) if len(control_ll) >= 3 else []
    if corner_ll and hull:
        corner_area = _bbox_area(corner_ll)
        control_area = _bbox_area(control_ll)
        if control_area > 0 and corner_area > control_area * area_ratio:
            return hull, "control_hull"
        closed = _close(corner_ll)
        return closed, "corners"
    if hull:
        return hull, "control_hull"
    if len(corner_ll) >= 3:
        return _close(corner_ll), "corners"
    return [], "none"


def _has_ll(point: dict) -> bool:
    return point.get("lat") is not None and point.get("lon") is not None


def _close(points: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    out = list(points)
    if out and out[0] != out[-1]:
        out.append(out[0])
    return out


def as_lonlat(ring: Sequence[tuple[float, float]]) -> list[list[float]]:
    """GeoJSON ring: ``[lon, lat]``."""
    return [[lon, lat] for lat, lon in ring]
