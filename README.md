# Dynamic Island for Mac

The iPhone's Dynamic Island for the MacBook notch.

[![Latest release](https://img.shields.io/github/v/release/Achitsak/dynamic-island-mac?color=black)](https://github.com/Achitsak/dynamic-island-mac/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Universal](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-universal-black)
[![License: MIT](https://img.shields.io/badge/license-MIT-black)](LICENSE)

## Features

- **Now Playing** – artwork, waveform, playback controls and scrubbing for any
  app in Control Center
- **Timer** – start from the island or the menu bar; runs alongside Now Playing
- **Charging** – input power, battery level and time to full
- **Alerts** – volume, brightness, charging, low battery and Bluetooth devices
- **Any display** – scales with the notch at every resolution; draws its own
  island on displays without one
- **Lightweight** – 0% CPU and about 20 MB of memory at idle

## Requirements

- macOS 14 Sonoma or later
- A Mac with Apple Silicon or Intel (designed for MacBooks with a notch)

## Installation

1. Download **DynamicIsland.zip** from the
   [latest release](https://github.com/Achitsak/dynamic-island-mac/releases/latest).
2. Unzip it and move **Dynamic Island.app** to your **Applications** folder.
3. The app is not notarized, so remove the quarantine flag once:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Dynamic Island.app"
   ```

   Alternatively, open the app, then click **Open Anyway** in
   **System Settings → Privacy & Security**.
4. Open **Dynamic Island**. It launches at login from then on; this can be
   turned off in Settings.

Bluetooth access is requested on first launch and is used only for device
alerts.

## Usage

| Action                   | Result                  |
| ------------------------ | ----------------------- |
| Hover or click the notch | Expand the island       |
| Right-click the notch    | Settings, Quit          |
| Menu bar icon            | Timers, demo, Settings  |

## Building from source

Requires Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/Achitsak/dynamic-island-mac.git
cd dynamic-island-mac
./build.sh run       # build and launch
./build.sh install   # install to /Applications and launch
./build.sh dist      # universal release zip in build/
```

Run with `--demo`, or choose **Play Demo** from the menu bar icon, to cycle
through every state.

## How Now Playing works

Since macOS 15.4, the private MediaRemote framework only responds to
Apple-signed processes. As found by
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), a small
library loaded into the Apple-signed `/usr/bin/perl` can still read it.
`MediaBridge/MediaBridge.m` streams now playing updates as JSON lines and takes
playback commands on stdin. If Apple closes this path, only Now Playing is
affected.

## Project structure

```
Sources/DynamicIsland/
  App/          entry point, menu bar item
  Island/       window, shape, layout and state
  Activities/   compact, expanded and alert views
  Services/     now playing, battery, volume, brightness, Bluetooth, timer
  Support/      settings, artwork colours
MediaBridge/    MediaRemote helper (Objective-C)
scripts/        app icon renderer
build.sh
```

## Notes

- Uses private frameworks, so it can't be distributed on the Mac App Store.
- Tested on Apple Silicon. Intel builds are included but untested.
- Not affiliated with Apple.

## License

[MIT](LICENSE)
