# Sources

## Orion’s Moon-centered path

`ArtemisIIWindow/Resources/horizons_orion_moon.json`

NASA/JPL Horizons API, queried 2026-10-19. https://ssd.jpl.nasa.gov/api/horizons.api

The samples are the apparent sub-observer point of the Moon as seen from Artemis II, plus range, written as Moon-centered cartesian coordinates. Longitude and latitude are in the IAU **MOON_ME** body-fixed frame (Mean Earth / polar axis, east-longitude positive): +X is the 0° east meridian, +Y is 90° east, and +Z is north. This is not a `REF_PLANE=BODY EQUATOR` vector table. That frame is the body equator and node of date, so its +X is the equator node and does not rotate with the Moon.

```
format=text
COMMAND=301
MAKE_EPHEM=YES
EPHEM_TYPE=OBSERVER
CENTER=500@-1024
START_TIME=2026-04-06 18:00
STOP_TIME=2026-04-07 02:00
STEP_SIZE=1 m
QUANTITIES=14,20
ANG_FORMAT=DEG
CSV_FORMAT=YES
CAL_FORMAT=BOTH
OBJ_DATA=NO
```

`CENTER=500@-1024` is the Artemis II spacecraft body center. `COMMAND=301` is the Moon. Quantity 14 is `ObsSub-LON` and `ObsSub-LAT` in degrees, east-positive. Quantity 20 `delta` is the apparent range in astronomical units. The Horizons header for this query prints `1 au = 149597870.700 km` and `Target pole/equ : MOON_ME`. Center radii are 1737.4, 1737.4, 1737.4 km.

```
rangeKm = delta * 149597870.700
x = rangeKm * cos(lat) * cos(lon)
y = rangeKm * cos(lat) * sin(lon)
z = rangeKm * sin(lat)
```

At 2026-04-06 19:40 UT, Horizons prints sub-observer longitude 253.089630°E (−106.910370°) and latitude 1.605780°. At 2026-04-06 23:01 UT, closest approach in this table, it prints 179.492308°E and latitude −2.607641°.

## Sub-solar point

`ArtemisIIWindow/Resources/horizons_sun_moon.json`

NASA/JPL Horizons API, queried 2026-10-19. Same window and same spacecraft center as the path. Quantity 15 is the apparent sub-solar longitude and latitude of the Sun on the Moon, in the IAU **MOON_ME** frame named in the header (`Target pole/equ : MOON_ME`, east-longitude positive).

```
format=text
COMMAND=301
MAKE_EPHEM=YES
EPHEM_TYPE=OBSERVER
CENTER=500@-1024
START_TIME=2026-04-06 18:00
STOP_TIME=2026-04-07 02:00
STEP_SIZE=10 m
QUANTITIES=15
ANG_FORMAT=DEG
CSV_FORMAT=YES
CAL_FORMAT=BOTH
OBJ_DATA=NO
```

The key light points from the Moon’s center toward that sub-solar point:

```
x = cos(lat) * cos(lon)
y = cos(lat) * sin(lon)
z = sin(lat)
```

At 2026-04-06 19:40 UT, Horizons prints `SunSub-LON` 306.562535° and `SunSub-LAT` 1.028083°.

## Shown frames

Window 2 and the crater pages draw only Nikon `nkd5015` frames. Window 3 draws Cab Cam `cab2` frames. Those glass frames are lossy WebP with a 2700 px long edge, written from the PDS browse originals (WebP quality 72). Each one also has a 720 px sibling for a narrow screen. The Nikon browse PNGs are 5568 by 3712:

`https://pds-imaging.jpl.nasa.gov/api/data/atlas:pds4:artemis2:artemis2:/artemis2_crew_camera/browse/fd06/{nasa_id}_nkd5015_prc_v01.png`

Cab Cam frames come from the browse-source JPEGs, 4000 by 3000:

`https://pds-imaging.jpl.nasa.gov/api/data/atlas:pds4:artemis2:artemis2:/artemis2_orion_camera/browse_source/fd05/{nasa_id}_cab2_src_v01.jpg`

The five Z9 files (art002e016183, art002e016184, art002e016187, art002e016188, art002e016193) are in the same image folder. They come from the nkz9019 browse PNGs, 8256 by 5504, resized the same way:

`https://pds-imaging.jpl.nasa.gov/api/data/atlas:pds4:artemis2:artemis2:/artemis2_crew_camera/browse/fd06/{nasa_id}_nkz9019_prc_v01.png`

They are not drawn on the iOS glass. Window 2 ignores `nkz9019`. Before the first `nkd5015` frame, art002e009611 (19:33:59.990Z) stays up, including when Moments seeks to art002e016183 at 19:33:03.910Z. That row names the Z9 file and says it is not the picture on the window.

Those are the URLs the 2700 px derivation fetched. They are not the `:md` or `:lg` Atlas thumbnails, and they are not a 1200-pixel long edge.

The image folder holds 63 full WebP files (8.06 MB) and 63 siblings (0.87 MB), 8.93 MB together. The app’s DemoData copy of `demo/data`, without `footprints.geojson`, is 26.49 MB. The 31.61 MB figure in the project README is a different total: the web `demo/data` directory plus `docs/hero.gif`, `docs/hero-still.png`, `docs/window-view.mp4`, `docs/window3-still.png`, and `docs/window3-view.mp4`.

## Crater map

NASA SVS CGI Moon Kit, ID 4720, file `lroc_color_2k.jpg`, 2048 by 1024, centered on 0° longitude with east to the right. https://svs.gsfc.nasa.gov/4720/ That equirectangular file is the source of the reprojection and is not bundled.

`ArtemisIIWindow/Resources/lroc-track.jpg` is a 1400 by 663 reprojection of that file. Columns in the file run from 340° E to 150° E and rows from 48° N to 42° S. The app mirrors the file so the crater map has north up and west on the left. It is not a new photograph.

## Type

`ArtemisIIWindow/Fonts/Fraunces.ttf` and `Fraunces-Italic.ttf`. Copyright 2018 The Fraunces Project Authors (https://github.com/undercasetype/Fraunces). Licensed under the SIL Open Font License, Version 1.1. The license text is `Fraunces-OFL.txt` beside the files.

`ArtemisIIWindow/Fonts/Inter.ttf`. Copyright 2020 The Inter Project Authors (https://github.com/rsms/inter). Licensed under the SIL Open Font License, Version 1.1. The license text is `Inter-OFL.txt` beside the file.

Fraunces is the display face. Inter is the text face. Both are registered as `UIAppFonts` in the app and the Live Activity extension.
