# Attack Shark R1 for macOS

Configure the Attack Shark R1 mouse on macOS without the vendor's Windows software: a small `r1` command-line tool and a native SwiftUI app, **R1 Config**. It talks to the mouse over IOKit HID and needs nothing beyond the Xcode command-line tools.

Unofficial and not affiliated with Attack Shark. The app icon is based on the Attack Shark logo, which belongs to its owner and is not covered by this project's license.

## What it does

- DPI: six stages (100–18000 in steps of 100), active stage, angle snap, ripple control
- Polling rate: 125, 250, 500 or 1000 Hz
- Buttons: middle, both side buttons and the DPI button; side and middle buttons accept mouse actions, media keys or any keyboard shortcut (`cmd+shift+4`, `\`, `f13`…)
- Battery level, live
- Shows whether the mouse is connected, off, or in Bluetooth mode

Settings are stored in the mouse, so they also apply in Bluetooth mode and on other computers.

## Build

```sh
xcode-select --install   # once, if the command-line tools are missing
./build.sh
```

This builds `./r1` and `R1 Config.app` and copies the app to `/Applications`. The app icon comes from `icon.png`; replace it with any square image (1024×1024 is best) to change it.

## Command line

```sh
./r1 battery
./r1 dpi 400 800 1800 3200 6400 12000 --active 3
./r1 polling 1000
./r1 buttons 'forward=cmd+]' 'back=cmd+[' middle=middle-click
./r1 rate      # measures the real report rate; needs Input Monitoring for your terminal
./r1 selftest
```

Run `./r1` with no arguments for the full list of buttons and actions.

## Things to know

- **Connect through the 2.4G dongle or the USB-C cable.** In Bluetooth mode the R1 exposes no configuration channel; the tools detect this and say so.
- **Move the mouse before applying.** A sleeping mouse misses the change even though the dongle accepts it.
- The mouse can't report its settings back, so the app remembers what you last applied.
- The R1's DPI button sits at a different slot of the button map than the X11's and accepts only DPI functions.
- Verified on a real R1 over the dongle: battery, DPI, polling rate and button map. Not yet verified: the `sleep` command, DPI+/DPI− on the DPI button, and the USB-C cable mode.

## Credits

The protocol comes from community reverse-engineering work:

- [jlucaso1/attack-shark-r1](https://github.com/jlucaso1/attack-shark-r1) — DPI, polling, sleep and battery (MIT OR Apache-2.0)
- [akawazak/attack-shark-x11-community-driver](https://github.com/akawazak/attack-shark-x11-community-driver) — button map (MIT)
- [ThachRC/Attack-Shark-R1-Linux](https://github.com/ThachRC/Attack-Shark-R1-Linux) — used to cross-check the DPI checksum

## License

MIT; see [LICENSE](LICENSE), which includes the third-party notices.
