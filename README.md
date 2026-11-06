# Rollcam

A disposable camera for iPhone. Load a roll of 24 or 36 exposures, shoot through a tiny
viewfinder, wind the thumbwheel after every shot, and send the roll to the lab. You can't see a
single photo until the roll comes back developed, with a warm, grainy, light-leaky film look.

- iOS 17 or later, iPhone only
- No account, no server, no third-party code
- Works with a **free** Apple ID (no special entitlements; it uses local notifications only)

## 1. Download the IPA

Every push to `main` is built by GitHub Actions on a Mac and published as an **unsigned IPA**.

1. Open this repository on GitHub and click **Releases** (right-hand side of the page).
2. Open the newest `build-N` release.
3. Under **Assets**, download **`Rollcam.ipa`**.

(The IPA is also attached to each run on the **Actions** tab as an artifact. Artifacts download
as a `.zip`, so you'd have to unzip them first. The Releases page is simpler.)

## 2. Sideload it from Windows with Sideloadly

You need:

- A Windows PC and a USB cable for your iPhone
- An Apple ID. A free one works.
- **iTunes** and **iCloud** installed **from Apple's website**, not the Microsoft Store.
  Sideloadly needs the "classic" versions:
  - iTunes: <https://www.apple.com/itunes/download/win64> (64-bit installer)
  - iCloud: <https://support.apple.com/en-us/103232> (look for the non-Store download link)
  If you already have the Microsoft Store versions, uninstall them first.
- **Sideloadly**: <https://sideloadly.io>

Steps:

1. Plug in the iPhone, unlock it, and tap **Trust** if it asks. Open iTunes once to check that
   it sees the phone, then close it.
2. Open Sideloadly. Your iPhone should appear in the **iDevice** box.
3. Drag `Rollcam.ipa` onto Sideloadly (or click the IPA icon and pick it).
4. Type your Apple ID email and click **Start**. Sign in when asked. If your Apple ID uses
   two-factor authentication, enter the code.
5. On the iPhone, go to **Settings › General › VPN & Device Management**. Tap your Apple ID
   under *Developer App* and choose **Trust**.
6. On iOS 16 and later, also turn on **Settings › Privacy & Security › Developer Mode**. The
   phone restarts.
7. Open Rollcam. Allow camera access. Allow notifications when you first send a roll to the lab.

AltStore works too: open AltStore on the phone, go to **My Apps › +**, and pick the IPA.

### The 7-day limit (free Apple ID)

Apps signed with a free Apple ID **expire after 7 days**. After that, Rollcam won't open until
you re-sign it. To re-sign, plug in the phone and run Sideloadly again with the same IPA and
the same Apple ID. Your rolls and photos are kept. Free accounts can have at most 3 sideloaded
apps at once.

Always re-sign with the **same Apple ID**. Undeveloped photos are encrypted with a key stored
in the iPhone's Keychain, and that key is tied to the signing account. If you switch Apple IDs
while a roll is still at the lab, that roll can't be developed. Rolls that are already
developed aren't affected.

A paid Apple Developer account extends the limit to a year.

## How it works

| | |
|---|---|
| **Viewfinder** | A small 3:2 window, about 28% of the screen width. The print is cropped to exactly what you framed. |
| **Winding** | After each shot, drag the ridged thumbwheel. It clicks for every notch and locks when the film is advanced. The shutter won't fire until then. |
| **Counter** | Counts down the exposures left, like a real film counter. |
| **Flash** | Uses the torch. Front/back camera toggle. Nothing else: no zoom, no editing. |
| **Send to lab** | When the roll is full. Developing takes 24 hours by default. Change it in Settings: 1 h, 12 h, 24 h or 3 days. |
| **Develop early** | In the ⋯ menu. Ends the roll now and throws away the unused exposures. It still takes the normal developing time. |
| **Developed rolls** | Grid, full-screen viewer, share, and **Save all to Photos**. Past rolls stay in the Lab list. |

**Film look** (Core Image, applied once at develop time): warm colour cast, lifted and faded
blacks, film grain, vignette, random light leaks on about 30% of frames, and an optional orange
date stamp. The full-resolution originals stay sealed until the roll is printed. Then the
originals are deleted and only the prints are kept.

**Anti-cheat (light).** Undeveloped frames are AES-GCM encrypted inside the app's sandbox. They
never reach the Photos library or the Files app. Developing time is counted with the phone's
monotonic clock, which keeps running while the phone sleeps and can't be changed in Settings.
Changing the date doesn't speed anything up. If the wall clock goes *backwards* compared with
when you sent the roll, Rollcam detects it and shows a warning on the roll. Only real elapsed
time counts. One known gap: after a reboot, the app has to fall back on the wall clock.

## Building

You don't need a Mac or Xcode. `.github/workflows/build.yml` runs on `macos-latest`:

1. Selects the newest stable Xcode.
2. Runs `brew install xcodegen` and `xcodegen generate` from `project.yml`. No `.xcodeproj` is
   committed.
3. Runs `xcodebuild` for `generic/platform=iOS` with code signing disabled.
4. Zips `Payload/Rollcam.app` into `Rollcam.ipa`.
5. Uploads the IPA as an artifact and publishes it as a `build-N` GitHub Release.

To trigger a build by hand, go to **Actions › Build unsigned IPA › Run workflow**.

## Layout

```
project.yml               XcodeGen spec (bundle id com.ran.rollcam, iOS 17)
Support/Info.plist        camera + photo-library-add usage strings
Rollcam/App               app entry, notification delegate
Rollcam/Camera            AVFoundation session, torch flash, preview layer
Rollcam/Film              Core Image film pipeline
Rollcam/Lab               roll store, lab/develop pipeline, notifications, Photos export
Rollcam/Storage           models, encrypted vault, clock-tamper logic
Rollcam/Views             SwiftUI screens
```
