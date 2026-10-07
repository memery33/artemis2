"""Speaker labels from the Lunar Science Team transcripts.

The guide lists Wiseman, Glover, Koch, Hansen, CAPCOM, SCIENCE, and Crew.
The files also contain trailing spaces, ``Glover [CAPCOM]``, and
``[SCIENCE] Wiseman``. Normalization keeps the crew name when one is present
and stores the bracketed role separately. It does not assign a photo to anyone.
"""

from __future__ import annotations

import re

CREW = ("Wiseman", "Glover", "Koch", "Hansen")
_CREW_RE = re.compile(r"\b(Wiseman|Glover|Koch|Hansen)\b", re.IGNORECASE)
_BRACKETS = re.compile(r"\[([^\]]+)\]")


def normalize_speaker(raw: str | None) -> tuple[str, str]:
    """Return ``(speaker, role)``.

    ``speaker`` is a crew surname, ``CAPCOM``, ``SCIENCE``, ``Crew``, or the
    cleaned original text. ``role`` is the bracketed qualifier when one exists.
    """
    if raw is None:
        return "", ""
    text = " ".join(str(raw).split())
    if not text:
        return "", ""
    roles = [part.strip() for part in _BRACKETS.findall(text) if part.strip()]
    role = roles[0] if roles else ""
    crew = _CREW_RE.search(text)
    if crew:
        name = crew.group(1).capitalize()
        # The regex is case-insensitive; restore the canonical spelling.
        name = next(person for person in CREW if person.lower() == name.lower())
        return name, role
    bare = _BRACKETS.sub("", text).strip()
    upper = bare.upper()
    if upper == "CAPCOM":
        return "CAPCOM", role
    if upper == "SCIENCE":
        return "SCIENCE", role
    if upper == "CREW":
        return "Crew", role
    return bare, role
