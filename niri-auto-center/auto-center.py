#!/usr/bin/env python3
"""Auto-center daemon for niri: watches niri's event stream and centers the focused window.

Runs `niri msg action center-window` whenever window focus changes.
"""

import argparse
import json
import logging
import os
import signal
import subprocess
import threading
import time

# ─── Configuration (overridable via CLI args) ───
DEBOUNCE_SECONDS = 0.1
NIRI_TIMEOUT = 5
RECONNECT_DELAY = 2.0
CONFIG_FILE: str = ""

# ─── Logging ───
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s auto-center: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("auto-center")

# ─── State ───
_focused_window_id: int | None = None      # id of currently focused window
_focused_workspace_id: int | None = None   # workspace of focused window
_focused_layout_pos: tuple | None = None   # (col, row) layout position
_debounce_timer: threading.Timer | None = None
_lock = threading.Lock()


# ─── Niri IPC ───
def _extract_layout_pos(window: dict) -> tuple | None:
    """Extract (col, row) from a window's layout if available."""
    result: tuple | None = None
    layout = window.get("layout")
    if isinstance(layout, dict):
        pos = layout.get("pos_in_scrolling_layout")
        if isinstance(pos, list) and len(pos) >= 2 and all(isinstance(v, (int, float)) for v in pos):
            result = (int(pos[0]), int(pos[1]))
    return result


def niri_action(*args) -> None:
    """Run a niri msg action command."""
    try:
        result = subprocess.run(
            ["niri", "msg", "action", *args],
            capture_output=True, timeout=NIRI_TIMEOUT,
        )
        if result.returncode != 0:
            log.debug("niri action %s rc=%d: %s", args, result.returncode, result.stderr.strip())
    except subprocess.TimeoutExpired:
        log.warning("niri action %s timed out", args)
    except OSError as exc:
        log.error("niri action %s error: %s", args, exc)


def get_focused_window_info() -> tuple[int | None, int | None, tuple | None]:
    """Get (window_id, workspace_id, layout_pos) of the currently focused window."""
    try:
        result = subprocess.run(
            ["niri", "msg", "-j", "focused-window"],
            capture_output=True, text=True, timeout=NIRI_TIMEOUT,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None, None, None
        data = json.loads(result.stdout.strip())
        if not isinstance(data, dict):
            return None, None, None
        win_id = data.get("id")
        ws_id = data.get("workspace_id")
        win = int(win_id) if isinstance(win_id, (int, float)) and win_id >= 0 else None
        ws = int(ws_id) if isinstance(ws_id, (int, float)) and ws_id >= 0 else None
        pos = _extract_layout_pos(data)
        return win, ws, pos
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        log.debug("failed to get focused window: %s", exc)
        return None, None, None


# ─── Core Logic ───
def center_focused() -> None:
    """Center the currently focused window."""
    log.debug("centering focused window")
    niri_action("center-window")


def debounced_center() -> None:
    """Debounce before centering."""
    global _debounce_timer

    with _lock:
        if _debounce_timer is not None:
            _debounce_timer.cancel()
        _debounce_timer = threading.Timer(DEBOUNCE_SECONDS, center_focused)
        _debounce_timer.start()


# ─── Event Processing ───
def _find_focused_in_event(event: dict) -> tuple[int | None, int | None, tuple | None]:
    """Extract (window_id, workspace_id, layout_pos) of the focused window."""
    found_id: int | None = None
    found_ws: int | None = None
    found_pos: tuple | None = None

    # WindowFocusChanged: direct focus change (e.g. keyboard navigation)
    payload = event.get("WindowFocusChanged")
    if isinstance(payload, dict) and isinstance(payload.get("id"), int):
        found_id = payload["id"]

    # WindowOpenedOrChanged: single window update
    payload = event.get("WindowOpenedOrChanged")
    if isinstance(payload, dict):
        window = payload.get("window")
        if isinstance(window, dict) and window.get("is_focused") and isinstance(window.get("id"), int):
            found_id = window["id"]
            ws = window.get("workspace_id")
            if isinstance(ws, int):
                found_ws = ws
            found_pos = _extract_layout_pos(window)

    # WindowsChanged: batch update with all current windows
    payload = event.get("WindowsChanged")
    if isinstance(payload, dict):
        windows = payload.get("windows")
        if isinstance(windows, list):
            for w in windows:
                if isinstance(w, dict) and w.get("is_focused") and isinstance(w.get("id"), int):
                    found_id = w["id"]
                    ws = w.get("workspace_id")
                    if isinstance(ws, int):
                        found_ws = ws
                    found_pos = _extract_layout_pos(w)
                    break

    return found_id, found_ws, found_pos


def should_center(event: dict) -> bool:
    """Determine if an event warrants centering.

    Triggers when:
    - Window focus changes to a different window
    - The same window moves to a different workspace (e.g., Ctrl+Super+U/I)
    - Layout position changes for the focused window (slurp, stack, move column, etc.)
    Handles WindowFocusChanged, WindowOpenedOrChanged, WindowsChanged, WindowClosed.
    """
    global _focused_window_id, _focused_workspace_id, _focused_layout_pos

    # Handle WindowClosed: clear tracked state if the closed window was focused
    if "WindowClosed" in event:
        closed = event["WindowClosed"]
        if isinstance(closed, dict):
            closed_id = closed.get("id")
            if isinstance(closed_id, int) and closed_id == _focused_window_id:
                with _lock:
                    _focused_window_id = None
                    _focused_workspace_id = None
                    _focused_layout_pos = None
        return False

    # Detect focus change, workspace change, or layout change
    new_id, new_ws, new_pos = _find_focused_in_event(event)
    if new_id is None:
        return False

    need_center = False
    with _lock:
        if new_id != _focused_window_id:
            # Focus changed to a different window
            _focused_window_id = new_id
            _focused_workspace_id = new_ws
            _focused_layout_pos = new_pos
            need_center = True
        elif new_ws is not None and new_ws != _focused_workspace_id:
            # Same window moved to a different workspace
            _focused_workspace_id = new_ws
            _focused_layout_pos = new_pos
            need_center = True
        elif new_pos is not None and new_pos != _focused_layout_pos:
            # Same window, same workspace, but layout position changed
            # (slurp, stack, move column right, etc.)
            _focused_layout_pos = new_pos
            need_center = True

    return need_center


def run_event_loop() -> None:
    """Connect to niri event stream and process events."""
    global _focused_window_id, _focused_workspace_id, _focused_layout_pos, _debounce_timer

    with _lock:
        if _debounce_timer is not None:
            _debounce_timer.cancel()
            _debounce_timer = None

    # Initialize with current focused window
    win_id, ws_id, layout_pos = get_focused_window_info()
    _focused_window_id = win_id
    _focused_workspace_id = ws_id
    _focused_layout_pos = layout_pos
    log.info("initial focused window: %s (workspace %s, layout %s)",
             _focused_window_id, _focused_workspace_id, _focused_layout_pos)

    # Center on startup
    center_focused()

    proc = subprocess.Popen(
        ["niri", "msg", "-j", "event-stream"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )

    if proc.stdout is None:
        log.error("failed to open event stream stdout")
        proc.terminate()
        return

    try:
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            if not isinstance(event, dict):
                continue

            if should_center(event):
                debounced_center()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


# ─── CLI ───
def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Auto-center daemon for niri — centers focused windows automatically.",
    )
    parser.add_argument(
        "--debounce", type=float, default=None,
        help=f"debounce delay in seconds (default: {DEBOUNCE_SECONDS})",
    )
    parser.add_argument(
        "--config-file", type=str, default=None,
        help="path to runtime config file for hot-reload via SIGUSR1",
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="enable debug logging",
    )
    return parser.parse_args()


# ─── Hot Reload ───
def reload_config() -> None:
    """Reload configuration from CONFIG_FILE and re-center."""
    global DEBOUNCE_SECONDS

    if not CONFIG_FILE:
        log.warning("no config file configured")
        return

    # Resolve to real path to prevent path traversal
    resolved = os.path.realpath(CONFIG_FILE)
    if not os.path.isfile(resolved):
        log.warning("config file not found: %s", resolved)
        return

    try:
        with open(resolved) as f:
            cfg = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        log.warning("failed to read config file: %s", exc)
        return

    if not isinstance(cfg, dict):
        return

    if "debounceMs" in cfg:
        DEBOUNCE_SECONDS = max(0.05, int(cfg["debounceMs"]) / 1000.0)
        # Note: DEBOUNCE_SECONDS is read by debounced_center() which holds _lock.
        # This signal handler runs in main thread, safe.

    log.info("config reloaded (debounce=%gms)", DEBOUNCE_SECONDS * 1000)

    center_focused()


# ─── Main ───
def main() -> None:
    """Main entry point with reconnection loop."""
    global DEBOUNCE_SECONDS, CONFIG_FILE

    args = parse_args()

    # Apply CLI overrides
    if args.debounce is not None:
        DEBOUNCE_SECONDS = max(0.05, args.debounce)
    if args.config_file:
        CONFIG_FILE = args.config_file
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Handle SIGTERM for graceful shutdown
    def _shutdown(signum, frame):
        t = _debounce_timer
        if t is not None:
            t.cancel()
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, _shutdown)

    # Handle SIGUSR1 for hot config reload
    def _reload(signum, frame):
        reload_config()
    signal.signal(signal.SIGUSR1, _reload)

    log.info("starting (debounce=%gms)", DEBOUNCE_SECONDS * 1000)

    while True:
        try:
            run_event_loop()
            log.warning("event stream ended, reconnecting in %gs", RECONNECT_DELAY)
        except KeyboardInterrupt:
            log.info("shutting down")
            break
        except Exception as exc:
            log.error("event loop crashed: %s, reconnecting in %gs", exc, RECONNECT_DELAY)
        time.sleep(RECONNECT_DELAY)


if __name__ == "__main__":
    main()
