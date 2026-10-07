# artemis2

![Orion window during the Aristarchus to Reiner Gamma pass](docs/hero.gif)

A 1280×720 still of the same view is [`docs/hero-still.png`](docs/hero-still.png).

Python toolkit for NASA's Artemis II lunar-science release on the Planetary Data System, and a static replay that puts you at an Orion window for the 6 April 2026 pass from Aristarchus Plateau to Reiner Gamma.

The page plays the crew's real PCD recordings. It does not synthesize cabin noise or any other audio. Photos are the crew's frames, credited **NASA ID …, Credit: NASA/Artemis II Crew**. This is an independent project. It is not a NASA product and NASA does not endorse it.

## Install

Python 3.10 or newer. `ffmpeg` is needed only when exporting trimmed replay audio.

```bash
pip install -e .
artemis2 --help
```

## Commands

| Command | What it does |
|---|---|
| `artemis2 list` | List products from the public Atlas search API. `--sum` prints counts and bytes. |
| `artemis2 fetch` | Download into a local tree. Defaults to browse `:lg` derivatives, refuses `:md`/`:lg` on TIFF/NEF, checks md5 on full files, and stops above `--max-gb` (0.5) unless you pass `--yes`. |
| `artemis2 index DIR` | Parse PDS4 labels, transcripts, inventories, and the target list into SQLite. Add `--parquet DIR` for Parquet. |
| `artemis2 sync` | One UTC timeline for a window. PCD audio start = embedded end time − exact duration. |
| `artemis2 export replay` | `timeline.json`, trimmed audio, resized frames, footprint GeoJSON. Also `export csv` and `export parquet`. |
| `artemis2 doctor` | The known archive quirks. Pass a directory to check the files you have. |

Atlas access is the documented Imaging Node API: `POST /api/search/atlas/_search` and `GET /api/data/atlas:pds4:artemis2:artemis2:/…`. `terms` queries are sent in batches of 40. The anonymous AWS gateway in the Atlas front end is not used.

## The window

`demo/index.html` is a static page (no build step) for **2026-04-06 19:33:00–19:48:30 UTC**.

```bash
cd demo && python -m http.server 8765
```

Click **Look out the window**. The recording is the clock. Move the mouse, or press a key, for the map, the scrubber, the camera-offset slider, and PCD2/PCD3. `f` is fullscreen.

The page is the inner face of one cone window, not a picture frame floating on a blank page. The opening is the rounded rectangle machined into the crew-module cone panel in NASA image [jsc2022e045980](https://images.nasa.gov/details/jsc2022e045980). Each cone window is three panes — an outer fused-silica thermal pane, a pressure pane, and a redundant pane — and NASA states that the innermost cone-window pane is acrylic ([Orion Windows Provide New Outlook for Spacecraft’s Future](https://www.nasa.gov/missions/artemis/orion/orion-windows-provide-new-outlook-for-spacecrafts-future/); the same three-lite stack is described in [Orion Window Testing Brings Artemis I Closer into View](https://www.nasa.gov/missions/artemis/orion/orion-window-testing-brings-artemis-1-closer-into-view/)). Orion has four of those cone windows plus a side-hatch window and a docking-hatch window. No public dimensioned clear-aperture drawing was found, so the page does not invent millimetres, bolt circles, or seats. The wall is the aluminum cone panel around that opening ([crew module](https://www.nasa.gov/reference/crew-module/)). It is drawn, not a pasted cabin photograph. Pointer movement and device tilt, when the browser provides them, shift the near frame against the view. A bright Moon darkens the wall. `prefers-reduced-motion` turns the drift, parallax, and Ken Burns off.

`art002e016183` is a Z9 frame of a lit card in a dark cabin, not a lunar limb. It is shown for a few seconds beside the window and is never placed in the glass. The other Z9 frames in this set are lunar and stay in the window. Before the first of those, at 19:33:26, the glass fades that real frame up with the clock. It does not invent a picture for the gap. PCD audio is the original mix: voices are not panned by speaker, because each file is two people on one recording, and nothing is synthesized. Subtitles sit low on the glass. A soft plate behind them darkens when the Moon under the line is bright, and stays nearly clear on a dark frame.

Shipped demo media is about 17 MB: browse frames resized to a 1200-pixel long edge, and the five PCD files trimmed to mono 64 kbps AAC. Rebuild it with `python scripts/rebuild_demo.py` after the cache described in that script is filled. `notebooks/replay.ipynb` is the same pipeline.

## Time

PCD M4A files store the **end** of the recording at whole-second resolution (Data User Guide §5.4.1). The start used here is that embedded time minus the exact duration from the file.

`art002a000033` (PCD2, Reiner Gamma) has creation time 19:48:30.000 UTC and duration 135.423771 s, so it starts at **19:46:14.576 UTC**. The label start, 19:46:14Z, is the truncated value. Transcript `utc` on that file matches this start to the millisecond; the `audio_time` column is only the floored second. Tests check both against the real sample.

Voice-loop files are not one continuous recording. `art002_2026-04-06_oe1` jumps by about 8.5 hours at audio time 06:23:41. Loops are mapped piecewise through each line's `utc`. They are not the demo clock.

Camera clocks were checked against the PCD before each activity. The residual is not in the archive. The slider adds seconds to photo timestamps before they are compared with the audio clock. Expect about ±1–2 s of absolute uncertainty.

## Who is speaking, and who held the camera

Transcript speakers are real: Wiseman, Glover, Koch, Hansen, plus CAPCOM, SCIENCE, and Crew. Labels such as `Hansen ` and `Glover [CAPCOM]` are normalized. Switching to a person keeps the same moment, highlights their lines, and selects the PCD that recorded them.

That PCD assignment is Data User Guide Table 6, and it is an audio assignment:

- PCD2 recorded Hansen and Glover.
- PCD3 recorded Koch and Wiseman.

**There is no per-person photo attribution.** The labels have no photographer field. The guide's credit line is the generic "NASA/Artemis II Crew", and Table 4 assigns the flyby to "All crew members." The page therefore does not filter frames by person. It filters by camera:

- **Window 2 · D5-015** (`nkd5015`) — the guide's primary flyby camera, the long lens at Window 2. That is a configuration note, not a per-frame window tag.
- **Z9** (`nkz9019`) — no window is assigned in the labels.
- **Orion cameras** — Cab Cam 2 is mounted inside Window 3; SAW Cam 3 looks in from the solar array. This 15-minute window's shipped frames are crew cameras. SAW Cam 3's still cadence is about one frame every eight minutes, and none of those stills is in the shipped set.

Crew annotations in the release are image-only PDFs with no timestamps. The OneNote sets cover NASA IDs art002e009303–e009560, which are earlier than this window, so the page does not pretend to show someone's notes at 19:46.

## Pointing

The PDS SPICE bundle is delayed. NAIF has published a reconstructed Orion trajectory and no CK, FK, or SCLK, so a window's look direction cannot be computed. `artemis2.pointing.PointingProvider` is the seam: `boresight(utc, window_id)` returns `None` until a kernel-backed provider exists. The map draws LTP targets that have real coordinates, and the footprints of georeferenced frames. Those footprints are not a window boresight.

Hertzsprung Basin is stored at latitude 0, longitude 0 in the outgoing target request. It is not plotted.

## Footprints

On the D5 processed labels, `vertical_coordinate_pixel` runs to 5568 (the sample count) and `horizontal_coordinate_pixel` runs to 3712 (the line count). The display axes in the same label are Sample left-to-right and Line top-to-bottom, so the field names are swapped. A corner at vertical = 5568 cannot be a line index. Plotted the other way, control points fall on the lunar surface in both a full-disk Orientale frame (`art002e009600`) and a 400 mm Reiner Gamma frame (`art002e009943`), and they stay off the black sky.

The corner polygon is a homography extrapolated to the frame (the guide calls the fit affine). On both checked labels that box runs well past the control points, so drawn footprints are the **control-point convex hull** when the corners diverge. Nine shipped frames have no geometry. Target tags were "not thoroughly verified" (guide Table 17) and are shown as tags.

## Data quirks

`artemis2 doctor` prints these, and checks them when the files are local:

- Delayed SPICE bundle; no attitude kernels.
- `art002a000033` start 19:46:14.576 versus a truncated label.
- Discontinuous voice loops; malformed `utc` `2026-04-06 03:10:201200`; three date-only rows.
- `art002_2026-04-07_oe2` is named 7 April and timed 6 April.
- fd04 `art002a000001`/`a000003` and `a000002`/`a000004` share times with different `activity_id` values. `art002a000052_pcd1_src` is outside the collection inventory.
- Orion `channel2` is missing `art002m1020961941`.
- 10,329 archived crew images per level, against 10,339 in the guide's Figure 7. Atlas byte totals are about 2.57 TB, not the blog's "more than 800 gigabytes."
- Still unreleased: iPhone 17 Pro Max collection, lens-distortion PDF, HERA, the SPICE bundle. The Data User Guide DOI does not resolve yet.
- DCAM times may be off by minutes. OpNav times were reconstructed from filenames.

Code follows the archive, not the guide, where they disagree (`_saw3_raw_` rather than `_vid_`).

## Tests

```bash
python -m pytest
```

Fixtures are real sample products, including the `art002a000033` M4A, its label and transcript, the Orientale processed label, both voice-loop CSVs, the fd04 duplicate labels, the PCD inventory, and the outgoing target list.

## Bundles

| Bundle | DOI |
|---|---|
| `urn:nasa:pds:artemis2_crew_camera` | [10.17189/x52v-tb80](https://doi.org/10.17189/x52v-tb80) |
| `urn:nasa:pds:artemis2_orion_camera` | [10.17189/hzev-nq50](https://doi.org/10.17189/hzev-nq50) |
| `urn:nasa:pds:artemis2_mission_audio` | [10.17189/4a29-dz64](https://doi.org/10.17189/4a29-dz64) |
| `urn:nasa:pds:artemis2_mission` | [10.17189/36fx-pd80](https://doi.org/10.17189/36fx-pd80) |

The SPICE DOI 10.17189/7ezn-0294 and the Data User Guide DOI 10.17189/dtpt-2857 were not resolving when this was written. The guide itself is [artemis2_data_user_guide.pdf](https://pds-geosciences.wustl.edu/artemis2/urn-nasa-pds-artemis2_mission/document/artemis2_data_user_guide.pdf) at the Geosciences Node.

Out of scope for v1: radiometry, lens correction, SPICE pointing, Orion video frame extraction, and the unreleased iPhone collection.
