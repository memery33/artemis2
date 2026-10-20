# Orion Window

Native iPhone app for the Artemis II Orion flyby. SwiftUI, iOS 18 or later. The home screen name is Orion Window (`CFBundleDisplayName`). The App Store name is Orion Window: Artemis II Flyby. The bundle id stays `com.memery33.artemis2window`. There is no NASA insignia.

The pictures and the crew recording are the files in `demo/data`. The build copies them into the app. They are not duplicated in git, and nothing in the app synthesizes a sound or a picture to fill a gap. `footprints.geojson` is not copied. The minimap reads the timeline’s geographic targets and does not draw footprints.

This is an independent project. It is not affiliated with or endorsed by NASA.

The Xcode project is generated. It is gitignored. These commands are for a Mac with Xcode 27.1 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). This tree was not compiled on Linux.

```bash
cd ios
xcodegen generate
xcodebuild -project ArtemisIIWindow.xcodeproj -scheme ArtemisIIWindow -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ArtemisIIWindowTests test
xcodebuild -project ArtemisIIWindow.xcodeproj -scheme ArtemisIIWindow -configuration Release -destination 'generic/platform=iOS' -archivePath "$PWD/build/ArtemisIIWindow.xcarchive" DEVELOPMENT_TEAM=NHYXW2AY53 archive
xcodebuild -exportArchive -archivePath "$PWD/build/ArtemisIIWindow.xcarchive" -exportPath "$PWD/build/export" -exportOptionsPlist ExportOptions.plist
```

UI tests call `FlybyUILaunch.endActivities()` from tearDown. That terminates Orion Window and relaunches it with `-ui-tests -endActivitiesAndExit`. Both arguments are required. The launch logs `Activity.activities.count`, ends every Live Activity, waits until those ends finish, and exits, so the widget extension is not still running when the next unit-test process starts. If a unit-test run still hangs and an Orion Window widget-extension process from an earlier session is alive, delete Orion Window from the simulator and run the tests again.

Signing is automatic for team `NHYXW2AY53`. If the simulator is not named “iPhone 17”, pick another iPhone simulator. Export uses `app-store-connect` / `upload`, so the archive is sent to App Store Connect. The Apple ID that uploads has to be signed in, and the App Store Connect record for `com.memery33.artemis2window` has to exist. `ITSAppUsesNonExemptEncryption` is false.

## Playback

One `AVAudioEngine` clock. While a real m4a is playing, mission time follows that file. Before the first file, between files, and from 22:36:03 to 22:39:11 on the cab run, the clock advances and the room stays quiet. A missing file stays quiet too.

The session category is `.playback`, mode `.spokenAudio`, policy `.longFormAudio`, with an empty options list, so the silent switch does not mute it and Bluetooth output is the system’s normal playback route. The session becomes active on Tap to begin, not at launch.

While the app is in the background the display link pauses. When a file ends, the next real recording on that track is scheduled to start at its own timestamp. The wait is the gap in the archive, and it is not added to the file clock. Once that file is audible, mission time follows the sample clock, which stops while playback is paused. Pausing then records that sample as the mission time, so resume does not play the gap again. A pause during the wait keeps only the remaining silence. A pause in the quiet between files leaves the clock where it is. If nothing remains in the span, playback pauses and the Now Playing rate is 0. Lock-screen artwork is the 720-pixel sibling of the current frame, decoded off the main thread.

`PrivacyInfo.xcprivacy` declares UserDefaults access for the spatial switch (reason `CA92.1`) and system boot time for `mach_absolute_time()`, which measures the wait before a scheduled file (reason `35F9.1`). The app does not track and collects no data.

Headphones unplugged (`AVAudioSession.routeChangeNotification` reason `oldDeviceUnavailable`) pauses. A newly connected device does not resume. An interruption pauses, and playback resumes from the saved sample only when the interruption ends with `.shouldResume` and the recording was playing. A pause from the headphones, or from the listener, clears that resume. An audio-engine configuration change reconnects the same file on the main thread. If the node is still rendering a positive sample, resume uses that sample and clears the gap arm. A locked gap that has not started yet re-arms the host time still left, not the stale mission clock. An arm that has already come due is cleared. A render of 0 or less is unknown, including the moment the arm comes due, so resume uses mission time clamped to the file. A positive sample still wins.

Now Playing uses the active span’s real label (“Aristarchus Plateau to Reiner Gamma”, or the cab run’s label), artist “NASA/Artemis II Crew”, and the current frame as artwork. That artist is the recording’s credit line. The app is not affiliated with or endorsed by NASA, and About says so next to the same credit. Remote commands are play, pause, toggle, skip ±15 seconds, and the scrubber. Skip and scrub stay inside the flyby window or the cab run, whichever is on screen. `UIBackgroundModes` includes `audio`. Folding the phone does not rebuild the player.

Spatial is off unless the listener turns it on. The switch is stored at `artemis.spatial`. On, the same m4a is positioned with `AVAudioEnvironmentNode`: Window 2 a little to the left, Window 3 a little to the right, reverb off, and the source inside the reference distance so loudness does not change. Off, the player connects straight to the mixer and the file is unmodified. Turning it on reconnects the graph and keeps the same sample. It does not add a bed, a tone, or any other sound.

## Layout

iPhone only, including an open iPhone Duo. The open fold is a regular-width (or at least 840 pt wide) screen, aspect 1.2–1.6, height at least 520 pt, width at most 1200 pt. A phone on its side fails the height test and keeps the phone layout. The phone reads the `.720.webp` sibling. The open fold reads the shipped frame. Window 2 draws a 1.58 rounded bezel because no empty straight-on interior is in the bundle. Window 3 is the 4:3 Cab Cam frame with no bezel drawn over it. The cabin Z9 `art002e016183` is a card for 9 seconds, not a picture on the glass.

The status bar is hidden. The home indicator is not.

## Icon

`Assets.xcassets/AppIcon.appiconset/Icon-1024.png` is a center crop of the earlier 1200×800 derivation of `demo/data/images/art002e016184.webp` (NASA ID art002e016184, Z9, 19:33:26.630Z). The shipped frame is now a 2700-pixel long edge, and this icon was not rebuilt from it, so the 1024×1024 App Store slot is still that older crop. It is not a new photograph. The launch screen is black.
