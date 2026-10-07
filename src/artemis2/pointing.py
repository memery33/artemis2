"""Drop-in pointing interface.

The NAIF PDS SPICE bundle is delayed. Outside PDS, NAIF has published a
reconstructed Orion trajectory SPK (NAIF id −24) and no CK, FK, or SCLK, so
camera and window pointing cannot be computed. This module is the seam where
a later kernel-backed provider replaces the placeholder without changing the
demo's call.

A provider returns a boresight in a named frame, or ``None`` when it cannot.
Image footprints are a separate, already-georeferenced product and are not a
substitute for window attitude.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol


@dataclass(frozen=True)
class Boresight:
    utc: str
    window_id: str
    frame: str
    latitude_deg: float | None
    longitude_deg: float | None
    body: str
    source: str


class PointingProvider(Protocol):
    name: str

    def available(self) -> bool:
        """True only when this provider can answer a boresight query."""

    def boresight(self, utc: datetime, window_id: str) -> Boresight | None:
        """Look direction of one Orion window at one UTC instant."""


class SpicePointingUnavailable:
    """Placeholder until a CK/FK/SCLK set exists.

    ``boresight`` returns ``None``. Callers must not invent a look direction.
    """

    name = "spice-unavailable"

    def available(self) -> bool:
        return False

    def boresight(self, utc: datetime, window_id: str) -> Boresight | None:
        return None


@dataclass
class FixedBoresight:
    """Test double and the shape a future kernel provider should match.

    One constant look direction for every window. Not used for the flyby map.
    """

    latitude_deg: float
    longitude_deg: float
    frame: str = "IAU_MOON"
    body: str = "Moon"
    name: str = "fixed"

    def available(self) -> bool:
        return True

    def boresight(self, utc: datetime, window_id: str) -> Boresight:
        from artemis2.timebase import format_utc

        return Boresight(
            utc=format_utc(utc),
            window_id=window_id,
            frame=self.frame,
            latitude_deg=self.latitude_deg,
            longitude_deg=self.longitude_deg,
            body=self.body,
            source=self.name,
        )
