# Volumio Remote (iPhone / iPad)

A small iOS app with a home screen widget for a Volumio player. The widget's buttons work in place (iOS 17 interactive widgets): play/pause, previous, next, mute, volume −/+ and a 10-step volume bar you can tap. It shows cover art, title, artist, album and play state. Large, medium and small sizes.

You install it on your own phone from Xcode. Nothing goes through the App Store.

## One-time setup

1. **Xcode iOS platform:** Xcode › Settings › Components, install **iOS** (about 8 GB). Without it Xcode can't build for a phone.
2. **Your Apple ID in Xcode:** Xcode › Settings › Accounts › + › Apple ID. A free account works.
3. **Developer Mode on the phone:** connect the phone by cable (or the same Wi-Fi after the first time), then on the phone go to Settings › Privacy & Security › Developer Mode, turn it on and restart.

## Install

1. Open `VolumioRemote/VolumioRemote.xcodeproj`.
2. Select the **VolumioRemote** project in the sidebar. For both targets, **VolumioRemote** and **VolumioRemoteWidget**, open *Signing & Capabilities* and pick your team ("Your Name (Personal Team)").
   If Xcode says the bundle identifier isn't available, change `VOLUMIO_BUNDLE_PREFIX` in Build Settings (project level is easiest) to something unique, e.g. `se.yourname`.
3. Pick your iPhone as the run destination at the top and press **⌘R**.
4. The first time, the phone says the developer isn't trusted: Settings › General › VPN & Device Management › your Apple ID › Trust.
5. In the app, enter the player's address (e.g. `192.168.1.40`), tap **Connect**, and tap **Allow** when iOS asks for Local Network access.

## Add the widget

1. Long-press the home screen › Edit › Add Widget › **Volumio Remote**, and pick the large size.
2. Long-press the widget › **Edit Widget** › Address, and enter the same address as in the app.

## Good to know

- **Free Apple ID:** the app stops launching after 7 days. Connect the phone and press ⌘R again to renew it (the widget and its settings stay). A paid developer account makes it one year.
- **Refresh:** taps update the widget right away. Otherwise iOS refreshes it on its own schedule, every few minutes while playing.
- **Home network only:** away from home the widget shows "Can't reach …" with a Try again button.
- Local Network permission belongs to the app. If the widget can't reach the player but the app can, check Settings › Privacy & Security › Local Network › Volumio Remote.

## Layout

- `App/`: the app (address field, now playing, controls).
- `Widget/`: the widget extension (timeline provider and views).
- `Shared/`: compiled into both: `VolumioClient` (REST client) and the App Intents (`PlayerConfigIntent` for widget settings, `PlayerCommandIntent` for buttons).
- `Config/`: Info.plists, kept outside the synchronized folders.
