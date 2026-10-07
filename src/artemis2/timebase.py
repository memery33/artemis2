"""UTC parsing and the PCD audio clock.

PCD M4A files store the end of the recording, at whole-second resolution.
The start used for sync is that embedded end time minus the exact duration
(Data User Guide §5.4.1). Transcript ``utc`` values are already absolute and
are not recomputed from the floored ``audio_time`` column.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone

# "2026-04-06T19:48:30Z", "2026-04-06 19:46:14.978", "06 Apr 2026 18:00:00.000000"
_ISO = re.compile(
    r"^(?P<y>\d{4})-(?P<mo>\d{2})-(?P<d>\d{2})"
    r"(?:[T ](?P<h>\d{2}):(?P<mi>\d{2}):(?P<s>\d{2})(?:\.(?P<f>\d+))?)?Z?$"
)
_MON = re.compile(
    r"^(?P<d>\d{1,2})\s+(?P<mon>[A-Za-z]{3})\s+(?P<y>\d{4})"
    r"(?:\s+(?P<h>\d{2}):(?P<mi>\d{2}):(?P<s>\d{2})(?:\.(?P<f>\d+))?)?$"
)
_MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}


def round_ms(dt: datetime) -> datetime:
    """Round to the nearest millisecond, half away from zero on the fraction."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    ms = int(dt.microsecond / 1000.0 + 0.5)
    base = dt.replace(microsecond=0)
    if ms >= 1000:
        return base + timedelta(seconds=1)
    return base + timedelta(milliseconds=ms)


def parse_utc(value: str | None) -> tuple[datetime | None, str]:
    """Parse a transcript or label time.

    Returns ``(datetime, status)`` with status ``ok``, ``date_only``, or
    ``malformed``. Date-only values are returned at 00:00:00 UTC so callers
    can see the day, but they are not a clock time and must not drive sync.
    """
    if value is None:
        return None, "malformed"
    text = str(value).strip()
    if not text or text.lower() in {"nat", "none", "null"}:
        return None, "malformed"
    match = _ISO.match(text)
    if match:
        return _from_parts(match, date_only=match.group("h") is None)
    match = _MON.match(text)
    if match:
        month = _MONTHS.get(match.group("mon").lower())
        if month is None:
            return None, "malformed"
        return _finish(
            int(match.group("y")),
            month,
            int(match.group("d")),
            match.group("h"),
            match.group("mi"),
            match.group("s"),
            match.group("f"),
        )
    return None, "malformed"


def _from_parts(match: re.Match[str], date_only: bool) -> tuple[datetime | None, str]:
    return _finish(
        int(match.group("y")),
        int(match.group("mo")),
        int(match.group("d")),
        match.group("h"),
        match.group("mi"),
        match.group("s"),
        match.group("f"),
        force_date_only=date_only,
    )


def _finish(
    year: int,
    month: int,
    day: int,
    hour: str | None,
    minute: str | None,
    second: str | None,
    frac: str | None,
    force_date_only: bool = False,
) -> tuple[datetime | None, str]:
    try:
        if hour is None or force_date_only:
            return datetime(year, month, day, tzinfo=timezone.utc), "date_only"
        micro = 0
        if frac:
            micro = int((frac + "000000")[:6])
        return (
            datetime(year, month, day, int(hour), int(minute), int(second), micro, tzinfo=timezone.utc),
            "ok",
        )
    except ValueError:
        return None, "malformed"


def format_utc(dt: datetime, millis: bool = True) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    dt = dt.astimezone(timezone.utc)
    if millis:
        return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def audio_start(end_time: datetime, duration_s: float) -> datetime:
    """Start = embedded end time − exact duration, rounded to a millisecond."""
    if end_time.tzinfo is None:
        end_time = end_time.replace(tzinfo=timezone.utc)
    return round_ms(end_time - timedelta(seconds=float(duration_s)))


def audio_time_seconds(value: str | None) -> float | None:
    """``hh:mm:ss`` offsets. These are floored to a whole second in the CSVs."""
    if not value:
        return None
    parts = value.strip().split(":")
    if len(parts) != 3:
        return None
    try:
        hours, minutes, seconds = (int(part) for part in parts)
    except ValueError:
        return None
    if minutes < 0 or seconds < 0 or seconds >= 60 or minutes >= 60:
        return None
    return hours * 3600 + minutes * 60 + seconds


def loop_pieces(rows: list[dict]) -> list[dict]:
    """Split a voice-loop transcript into piecewise UTC segments.

    Loop files are not one continuous recording. ``audio_time`` cannot be
    added to a single file start. A new piece begins when ``utc - audio_time``
    jumps by more than 30 seconds.
    """
    pieces: list[dict] = []
    current: list[dict] = []
    epoch: datetime | None = None
    for row in rows:
        utc = row.get("utc")
        audio_s = row.get("audio_s")
        if utc is None or audio_s is None or row.get("status") != "ok":
            continue
        implied = utc - timedelta(seconds=float(audio_s))
        if epoch is not None and abs((implied - epoch).total_seconds()) > 30:
            pieces.append(_close_piece(current, epoch))
            current = []
        if not current:
            epoch = implied
        current.append(row)
    if current and epoch is not None:
        pieces.append(_close_piece(current, epoch))
    return pieces


def _close_piece(rows: list[dict], epoch: datetime) -> dict:
    return {
        "implied_start": format_utc(round_ms(epoch)),
        "utc_start": format_utc(rows[0]["utc"]),
        "utc_end": format_utc(rows[-1]["utc"]),
        "audio_start_s": rows[0]["audio_s"],
        "audio_end_s": rows[-1]["audio_s"],
        "n": len(rows),
    }
