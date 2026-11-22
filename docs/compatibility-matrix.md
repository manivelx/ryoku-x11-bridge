# RXB X11 compatibility matrix

Legend: Direct candidate = Quickshell/X11 API likely covers it; Adapter = implement with i3/X11 service; Replacement = replace Wayland backend while preserving original UI where possible; Gated = do not expose until proven.

| Feature | X11/i3 strategy | Class | Acceptance evidence |
|---|---|---|---|
| QML rendering | Quickshell QtQuick X11 | Direct candidate | Full shell loads on target Qt/driver |
| User config isolation | RYOKU_CONFIG_HOME + RXB-only Quickshell path | Adapter | Existing XDG/Quickshell config unchanged; RXB settings persist separately |
| App-wide theming | Gated while RXB safety flag is set | Gated | Requires an explicit per-session app-config adapter |
| Lock/greeter management | XSecureLock when installed, otherwise PAM-backed i3lock; upstream qylock/greeter mutations disabled | Adapter, security acceptance pending | Xvfb verifies locker process startup/idempotency; real PAM auth, input grabs, VT switching, multi-monitor coverage and crash recovery remain target checks |
| Panels and bars | Quickshell X11 windows + i3 struts/stacking | Adapter | Stacking, struts, focus and multi-monitor |
| Popups and overlays | Quickshell X11 windows | Adapter | Placement, transient behavior, dismissal |
| Workspaces/monitors | Quickshell i3 integration | Direct candidate | Real workspace/output events |
| Windows/focus/tree | i3 GET_TREE + window events | Adapter | Floating, tiled, nested containers |
| Window/workspace actions | i3 IPC | Adapter | Semantic action tests |
| Keybindings | Pinned Ryoku catalogue + RXB-owned i3 include | Partial adapter | Compatible shipped actions generated at session start and settings apply; unsupported actions remain visible; user.conf remains untouched |
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
| Window previews | Live capture surfaces gated off; window identity/state still comes from i3 tree | Gated | Implement and validate a per-window X11 capture adapter before enabling previews |
| Overview | Original QML + i3 state + capture adapter | Replacement | Navigation and previews |
| WlrLayershell | X11 window hints/struts | Replacement | Per-surface behavior validated |
| Foreign-toplevel | i3 GET_TREE | Replacement | Task list, titles, app identity |
| Global shortcuts | i3 bindings or XGrabKey | Adapter/gated | Conflicts and focus semantics |
| Session lock | XSecureLock or i3lock + PAM; process identity scoped to the current X display | Replacement/partial | Xvfb start/idempotency/exit smoke; real PAM authentication, grabs, VT switching and recovery pending |
| PAM UI | Quickshell PAM API | Partial | Not itself a secure lock |
| Hyprland plugins | No i3 equivalent | Gated | Disable and explain |
| Wayfire-specific features | No i3 equivalent | Gated | Disable and explain |
| Blur/transparency | Existing Picom + QtQuick alpha | Unverified | Do not alter Picom config |
| Suspend/lock handoff | Suspend, hibernate and automatic suspend are disabled on X11; explicit warning, no direct systemctl/loginctl call | Gated/fail-closed | Keep disabled until a secure X11 lock-before-suspend protocol and resume/crash tests are proven |

For each row track: source inspected, adapter implemented, build passed, unit tests passed, Xephyr/Xvfb passed, real X11 hardware passed, user confirmed. Never infer hardware success from a virtual test or secure locking from fullscreen QML.

## Evidence fields

Use the following evidence states per feature; do not collapse them into a single "done" label.

| Evidence field | Meaning |
|---|---|
| Source inspected | Relevant pinned upstream source/API has been read and the intended behavior identified |
| Adapter implemented | RXB code exists; this alone does not imply it works at runtime |
| Build passed | The exact current branch commit passed the relevant build |
| Unit tests passed | The exact current branch commit passed its unit/regression tests |
| Xephyr/Xvfb passed | The feature was exercised in an isolated X11 server |
| Real X11 hardware passed | The feature was exercised on the target CachyOS + GT 740 / NVIDIA 470 machine |
| User confirmed | The owner reviewed the behavior and accepted it |

Current detailed evidence is tracked in [roadmap.md](roadmap.md).