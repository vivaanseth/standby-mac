# Standby

iPhone-style StandBy for your MacBook. It runs in the menu bar. When the built-in display isn't being used, it turns into a StandBy screen with widgets, photos, or a large clock.

- **With an external display:** Standby covers only the MacBook screen. You keep working on the other display. The built-in display counts as "in use" when you move the pointer on it, click, scroll, or type into a window that sits on it.
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
- **Widgets:** two stacks built from Clock, Calendar, Up Next, Date, Digital Clock, World Clock, Weather, Batteries, and Photos. You can reorder them, Smart Rotate them, choose World Clock cities, and show or hide widget backgrounds.
- **Clock:** Digital, Analog, World, Solar, and Float faces. Each can be turned on or off, reordered, and recolored.
- **Photos:** any folder (subfolders included), how often photos change, shuffle, slow zoom, and where the time sits.
- **Display:** brightness, Night Mode (red, on a schedule or always on), and burn-in protection.

## Notes

- No special permissions are needed. Calendar access is requested only if you turn on the Up Next widget.
- Weather comes from [Open-Meteo](https://open-meteo.com). Nothing is sent until you choose a city, and then only that city's coordinates are sent.
- If macOS turns off the display or starts its own screen saver before Standby kicks in, adjust **System Settings → Lock Screen** to allow more time, or enable "Keep the display awake while Standby is showing".
- Scriptable (e.g. from Shortcuts): `Standby.app/Contents/MacOS/Standby --show | --hide | --toggle`.
- `Standby --render <dir>` writes PNGs of every screen without opening any windows.
