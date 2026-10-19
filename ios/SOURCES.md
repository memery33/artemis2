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

## Moon map

NASA SVS CGI Moon Kit, ID 4720, file `lroc_color_2k.jpg`, 2048 by 1024, centered on 0° longitude with east to the right. https://svs.gsfc.nasa.gov/4720/

SceneKit shows that image center toward +Z. The moon node is yawed +90° about Y so +Z lands on MOON_ME +X (0° east). A −90° yaw would put the prime meridian on −X, which is 180° longitude.
