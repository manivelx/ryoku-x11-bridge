# RXB X11 compatibility matrix

Legend: Direct candidate = Quickshell/X11 API likely covers it; Adapter = implement with i3/X11 service; Replacement = replace Wayland backend while preserving original UI where possible; Gated = do not expose until proven.

| Feature | X11/i3 strategy | Class | Acceptance evidence |
|---|---|---|---|
| QML rendering | Quickshell QtQuick X11 | Direct candidate | Full shell loads on target Qt/driver |
| Panels and bars | Quickshell X11 windows + i3 struts/stacking | Adapter | Stacking, struts, focus and multi-monitor |
| Popups and overlays | Quickshell X11 windows | Adapter | Placement, transient behavior, dismissal |
| Workspaces/monitors | Quickshell i3 integration | Direct candidate | Real workspace/output events |
| Windows/focus/tree | i3 GET_TREE + window events | Adapter | Floating, tiled, nested containers |
| Window/workspace actions | i3 IPC | Adapter | Semantic action tests |
| Keybindings | RXB-owned i3 include | Adapter | No user config overwritten |
| Output state | i3 GET_OUTPUTS | Adapter | Correct output geometry |
| Display mode changes | RandR/XRandR backend | Adapter | Safe mode change and rollback |
| Wallpaper | Quickshell X11 surface + wallpaper backend | Adapter | Correct stacking and monitor coverage |
| Notifications | DBus notification service | Direct candidate | Actions, stacking, replacement |
| Tray | StatusNotifierItem/DBusMenu | Direct candidate | Tray client compatibility |
| Audio/media | PipeWire/MPRIS | Direct candidate | Source/sink and media actions |
| Bluetooth | BlueZ | Direct candidate | Scan, pair, connect, disconnect |
| Network/power | NetworkManager/UPower services | Direct candidate | State and action verification |
| Clipboard | X11 clipboard backend | Adapter | PRIMARY/CLIPBOARD and persistence |
| Capture/recording | X11 capture backend | Replacement | Coordinates, multi-monitor, performance |
| Window previews | X11 capture + i3 tree | Replacement | Correct window identity and refresh |
| Overview | Original QML + i3 state + capture adapter | Replacement | Navigation and previews |
| WlrLayershell | X11 window hints/struts | Replacement | Per-surface behavior validated |
| Foreign-toplevel | i3 GET_TREE | Replacement | Task list, titles, app identity |
| Global shortcuts | i3 bindings or XGrabKey | Adapter/gated | Conflicts and focus semantics |
| Session lock | XSecureLock + PAM | Replacement/gated | Security review and failure tests |
| PAM UI | Quickshell PAM API | Partial | Not itself a secure lock |
| Hyprland plugins | No i3 equivalent | Gated | Disable and explain |
| Wayfire-specific features | No i3 equivalent | Gated | Disable and explain |
| Blur/transparency | Existing Picom + QtQuick alpha | Unverified | Do not alter Picom config |
| Suspend/lock handoff | logind + secure locker | Gated | Lock-before-suspend proven |

For each row track: source inspected, adapter implemented, build passed, unit tests passed, Xephyr/Xvfb passed, real X11 hardware passed, user confirmed. Never infer hardware success from a virtual test or secure locking from fullscreen QML.
