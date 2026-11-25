# VolumioBar

A macOS menu bar app (SwiftUI `MenuBarExtra`, window style) that discovers Volumio players on the LAN over Bonjour and shows a stacked volume slider for each one. The main target is a miniDSP SHD Studio running Volumio, but any Volumio 2/3 player works.

## Status

- Written in a chat session without access to a Swift compiler. The syntax was checked with tree-sitter, but the app has **never been built**. Expect a few compile errors on the first build and fix them.
- No tests yet.

## Build

```sh
xcodebuild -project VolumioBar.xcodeproj -scheme VolumioBar -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/VolumioBar.app
```

- Xcode 16+ project (objectVersion 77) with a file-system-synchronized `VolumioBar/` folder. New `.swift` files in that folder are picked up automatically, so don't edit project.pbxproj to add sources.
- `Config/Info.plist` is kept outside the synchronized folder on purpose, so it isn't copied as a resource. Build settings merge it (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE`).
- Deployment target macOS 14 (uses `@Observable`, `MainActor.assumeIsolated`, `onChange(of:){ _, new in }`).
- Swift language mode 5, minimal concurrency checking. Signing: "Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`, manual, no team). No App Sandbox.

## Volumio facts (verified against volumio3-backend and Volumio2 source)

- Bonjour: service type `_Volumio._tcp`, port 3000. TXT keys `volumioName`, `UUID` (`app/plugins/system_controller/volumiodiscovery`).
- REST is under `/api/v1` on port 3000 (port 80 works too). CORS is open.
  - `GET /api/v1/getState` gives `status`, `title`, `artist`, `albumart`, `volume`, `dbVolume`, `mute`, `disableVolumeControl`, `service`, ...
  - `GET /api/v1/commands/?cmd=volume&volume=<int|plus|minus|mute|unmute|toggle>`
  - `GET /api/v1/commands/?cmd=toggle|play|pause|stop|next|prev`
  - `GET /api/v1/getSystemInfo` gives `id` (same as the UUID), `name`, ...
- `disableVolumeControl` is true only when the mixer is "None" and no volume-override plugin is active. Volumio then ignores volume commands, so the slider is disabled in that case. On the SHD, volume goes through miniDSP's override plugin.
- Volumio also has a socket.io API (what its web UI uses). It's undocumented and unstable, so it isn't used here yet. Polling is used instead.

## Architecture

- `BonjourBrowser`: `NWBrowser` for `_Volumio._tcp`. Each result is resolved to IPv4 by opening a throwaway `NWConnection` (IP version forced to v4) and reading `currentPath.remoteEndpoint`. Callbacks arrive on the main queue.
- `DeviceStore` (`@MainActor @Observable`): discovered players are keyed by UUID, and manual players by `manual:host:port` (saved in UserDefaults `manualHosts`). A manual player is hidden once Bonjour finds the same UUID. Polls every 1.5 s while the panel window is key, and every 30 s otherwise.
- `VolumioDevice` (`@MainActor @Observable`): per-player state. Volume sends are coalesced to one request in flight at a time. For 1.5 s after a local change, incoming polls don't overwrite volume and mute, so the slider doesn't jump.
- `VolumioAPI`: URLSession REST client with lenient JSON decoding (numbers may arrive as strings or null).
- `ContentView` / `DeviceRow`: the UI. `$device.sliderVolume` is a computed get/set property, used instead of `Binding(get:set:)` to avoid closure isolation issues.

## Ideas for next steps

- Global hotkeys or media keys for the volume of a chosen player
- socket.io push updates instead of polling
- Show the volume or mute state in the menu bar icon
- A WidgetKit widget with +/−/mute buttons (App Intents)
