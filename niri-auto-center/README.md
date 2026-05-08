# niri-auto-center

**Auto-center daemon for [niri](https://github.com/YaLTeR/niri) compositor** —
automatically centers the focused window whenever window focus changes.

---

## Features

- **Automatic centering** — watches niri's event stream and centers the focused window on focus change
- **Configurable debounce** — prevents flicker during rapid focus changes (50-1000ms)
- **Smart event filtering** — only reacts to actual focus changes, ignores title/job updates
- **Workspace-aware** — centers whenever you switch workspaces too
- **Theme-aware UI** — all colors follow the active Noctalia theme
- **Hot-reload config** — update settings without restarting the daemon (SIGUSR1)
- **i18n** — English and Indonesian

---

## Usage

### Bar Widget

- Focus-target icon indicator
- Status dot (theme primary = running, theme secondary = starting)
- Left-click toggles enabled/disabled
- Right-click context menu: enable/disable, settings

### Settings

- **Enable Auto-Center** — master on/off switch
- **Response delay** — 50-1000ms slider to control responsiveness
- **Daemon status** — running/error/stopped indicator

---

## Files

| File             | Role                                                       |
| ---------------- | ---------------------------------------------------------- |
| `Main.qml`       | Daemon lifecycle (start/stop/restart), settings bridge     |
| `BarWidget.qml`  | Bar indicator with mode icon and status dot                |
| `Settings.qml`   | Full settings page (toggles, mode buttons, slider, status) |
| `auto-center.py` | Python daemon — core auto-centering logic                  |

---

## Requirements

- [niri](https://github.com/YaLTeR/niri) compositor
- Python 3
- Noctalia Shell >= 4.4.0

## Author

Developed by [litfill](https://github.com/litfill).
