"""Shared facts that the CLI, doctor, and demo all have to say the same way."""

PHOTO_CREDIT = "Credit: NASA/Artemis II Crew"

# Checked against PDS4 labels (no photographer, artist, or creator field on the
# sample products) and Data User Guide §1.4 / Table 4 / Table 6.
PHOTO_ATTRIBUTION = (
    "No per-person photo attribution exists in this release. "
    "PDS4 labels carry no photographer field, and the Data User Guide credits "
    "every still as 'NASA/Artemis II Crew'. Table 4 assigns the flyby to "
    "'All crew members' with Window 2 as the primary camera position. "
    "Table 6 assigns PCD tablets to crew members; that is an audio-recorder "
    "assignment, not a camera assignment. Photos in this toolkit are filtered "
    "by camera and by the guide's window configuration, never by a guessed photographer."
)

# DUG Table 6. Audio recorded on the tablet, not photos taken by that person.
PCD_AUDIO_CREW = {
    "pcd2": ("Hansen", "Glover"),
    "pcd3": ("Koch", "Wiseman"),
    "pcd1": ("Wiseman", "Koch"),
    "pcd4": ("Koch",),
    "pcd": (),
}

# DUG Table 4 and §3.3.1. Window hints are configuration notes, not per-frame tags.
CAMERA_WINDOW = {
    "nkd5015": {
        "window": "2",
        "label": "Window 2 · D5-015",
        "detail": (
            "Nikon D5 serial 3500015. During the lunar flyby the Data User Guide "
            "names this body, with the long lens, as the primary camera at Window 2. "
            "Labels do not carry a per-frame window id."
        ),
    },
    "nkd5017": {
        "window": None,
        "label": "D5-017",
        "detail": (
            "Nikon D5 serial 3500017, mostly the short lens. The guide does not "
            "tie this body to one window for the flyby."
        ),
    },
    "nkz9019": {
        "window": None,
        "label": "Z9-019",
        "detail": (
            "Nikon Z9, mostly the 35 mm lens. No per-frame window tag, and the "
            "guide does not assign it to one crew member."
        ),
    },
    "saw2": {"window": None, "label": "SAW Cam 2", "detail": "Exterior solar-array camera."},
    "saw3": {"window": None, "label": "SAW Cam 3", "detail": "Exterior solar-array camera. Primary Orion science camera for the flyby."},
    "saw4": {"window": None, "label": "SAW Cam 4", "detail": "Exterior solar-array camera."},
    "cab2": {
        "window": "3",
        "label": "Cab Cam 2 · Window 3",
        "detail": "GoPro mounted inside Window 3 (Data User Guide §3.3.1).",
    },
    "onav": {"window": None, "label": "OpNav", "detail": "Optical navigation camera. Times were reconstructed from filenames."},
    "dcam": {"window": None, "label": "DCAM", "detail": "Docking camera. Times may be off by 5 minutes or more."},
}

CREW = ("Wiseman", "Glover", "Koch", "Hansen")

DEMO_WINDOW = {
    "start": "2026-04-06T19:33:00Z",
    "end": "2026-04-06T19:48:30Z",
    "label": "Aristarchus Plateau to Reiner Gamma",
}

BUNDLES = {
    "artemis2_crew_camera": "urn:nasa:pds:artemis2_crew_camera",
    "artemis2_orion_camera": "urn:nasa:pds:artemis2_orion_camera",
    "artemis2_mission_audio": "urn:nasa:pds:artemis2_mission_audio",
    "artemis2_mission": "urn:nasa:pds:artemis2_mission",
    "artemis2_spice": "urn:nasa:pds:artemis2_spice",
}

# fd04 pairs that the Atlas md5 audit found byte-identical, with different activity_id values.
KNOWN_AUDIO_DUPLICATE_IDS = (("art002a000001", "art002a000003"), ("art002a000002", "art002a000004"))
