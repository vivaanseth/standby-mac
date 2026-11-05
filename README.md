# Standby

iPhone-style StandBy for your MacBook. It runs in the menu bar. When the built-in display isn't being used, it turns into a StandBy screen with widgets, photos, or a large clock.

![Widgets](screenshots/01-widgets.png)

- **With an external display:** Standby covers only the MacBook screen. You keep working on the other display. The built-in display counts as "in use" when you move the pointer on it, click, scroll, or type into a window that sits on it.
- **When nothing is in use:** once there's no input anywhere, external displays get their own Standby too: the same widgets, photos and clocks, swipeable with two fingers, opening on the Clock by default so the two screens complement each other. **Sky** (a live view of the sky where you are) and plain black are alternatives. Any input brings the external display back, and the built-in display stays in Standby until you use it. With the lid closed, this works as a screen saver on the external display.
- **With no external display:** it works like a screen saver, after your Mac has been idle for a while.

## Build and install

Requires macOS 14+ and Xcode (or the Command Line Tools).

```bash
./build.sh            # builds build/Standby.app
./build.sh install    # also copies it to /Applications and launches it
```

The first time you launch it, Settings opens. After that, use the menu bar icon (a clock) or press **⌃⌥⌘S** to show or hide Standby at any time.

## Using it

| | |
|---|---|
| Change view (Widgets / Photos / Clock) | two-finger swipe left/right, click-drag, or ← → |
| Flip a widget stack or clock style | two-finger swipe up/down on it, or ↑ ↓ (⇧↑↓ for the right stack) |
| Wake | click, or any other key; pointer movement too if enabled |

## Settings

- **General:** idle delays (separate for external-display and screen-saver modes), wake behavior, "only when connected to power", whether to pause for videos and calls, open at login, menu bar icon, keyboard shortcut.
- **Views:** which views appear and which one opens first, 12/24-hour time, °C/°F, weather city.
- **Widgets:** 1–6 Smart Stacks in a Grid, Hero, Spotlight, Strip, or Wave layout. Each stack holds any of 17 widgets: Clock, Calendar, Up Next, Date, Digital Clock, World Clock, Weather, Batteries, Photos, Moon, Sunrise & Sunset, Flip Clock, Word Clock, Time Rings, Countdown, Note, and Mac Activity. You can reorder them, Smart Rotate them, set the Countdown and Note, choose World Clock cities, and show or hide widget backgrounds.
- **Clock:** Digital, Analog, World, Solar, and Float faces. Each can be turned on or off, reordered, and recolored.
- **Photos:** any folder (subfolders included), how often photos change, shuffle, slow zoom, and where the time sits.
- **External:** what external displays show when nothing is in use, after how long, and whether to act as a screen saver with the lid closed.
- **Display:** brightness, Night Mode (red, on a schedule or always on), and burn-in protection.

## Notes

- No special permissions are needed. Calendar access is requested only if you turn on the Up Next widget.
- Weather comes from [Open-Meteo](https://open-meteo.com). Nothing is sent until you choose a city, and then only that city's coordinates are sent.
- If macOS turns off the display or starts its own screen saver before Standby kicks in, adjust **System Settings → Lock Screen** to allow more time, or enable "Keep the display awake while Standby is showing".
- Scriptable (e.g. from Shortcuts): `Standby.app/Contents/MacOS/Standby --show | --hide | --toggle`.
- `Standby --render <dir>` writes PNGs of every screen without opening any windows.

## Screenshots

| | |
|---|---|
| ![Digital clock](screenshots/07-clock-digital.png) | ![Float clock](screenshots/11-clock-float.png) |
| ![World clock](screenshots/09-clock-world.png) | ![Night mode](screenshots/12-night.png) |
| ![Creative widgets](screenshots/26-new-a.png) | ![External display](screenshots/ext-standby-clock-digital.png) |

## Credits

World map from [Natural Earth](https://www.naturalearthdata.com) (public domain). Weather by [Open-Meteo](https://open-meteo.com).

Standby is an independent project inspired by StandBy on iPhone. It isn't affiliated with or endorsed by Apple.
