# Upstream Ryoku audit

## Pinned source
- Upstream: https://github.com/Ryoku-dev/ryoku
- Audited release: 1.1.0
- Pin: `0bf11741b22f69f22ad2733025671c7d0a5e1a47`
- Upstream release commit: https://github.com/Ryoku-dev/ryoku/commit/0bf11741b22f69f22ad2733025671c7d0a5e1a47
- License: GNU GPL-3.0. Preserve original notices and separately audit third-party assets before redistribution.

## Provider contract

Relevant source locations:
- `ryoku/wm/caps.go` — capability manifest
- `ryoku/wm/state.go` — state/frame structures
- `ryoku/wm/action.go` — semantic action IDs
- `ryoku/wm/client.go` — subprocess protocol and provider discovery
- `ryoku/wm/detect.go` — session/environment detection
- `ryoku/wm/hyprland/*`, `ryoku/wm/niri/*`, `ryoku/wm/wayfire/*` — reference providers

The interface is a subprocess protocol. The i3 provider must match the pinned source's JSON field names, optionality, frame ordering, capability names, action IDs and error semantics. Do not claim a capability until its behavior is implemented and tested. Provider IDs are opaque. Watch must emit a full initial state, a ready frame and subsequent valid newline-delimited frames; reconnect behavior must resynchronize rather than silently leave stale state. Apply preview must be side-effect-free.

## Confirmed X11 and Wayland dependency leads

The original shell tree contains references to:
- `Quickshell.Wayland`, `WlrLayershell` and `WlrKeyboardFocus`
- `WlSessionLock` / `WlSessionLockSurface` in the lock UI
- `ScreencopyView` in overview, dock-preview and capture flows
- `ToplevelManager` / foreign-toplevel paths in taskbar and launcher services
- `Quickshell.Hyprland` in compositor-specific bridges
- Wayland-specific keyboard focus, capture and surface semantics

These references are search leads only. The current RXB repository contains no copied QML tree: the overlay is applied against a pinned checkout during CI/build. A complete inventory must therefore be generated from the pinned upstream source tree, recording each QML file, import, referenced type/property/method, guard condition and feature owner. Search results alone are not proof that an item is safely gated.

## Runtime mapping

| Upstream dependency | X11/i3 approach | State |
|---|---|---|
| Workspaces and monitors | Quickshell i3 integration / provider state | Candidate; runtime proof pending |
| Window tree and focus | i3 IPC GET_TREE and event subscriptions | Implemented in Go provider; real session proof pending |
| Layer-shell panels | Quickshell X11 windows, struts and stacking hints | Adapter required; runtime proof pending |
| Popup/focus grabs | X11 transient windows and keyboard-grab behavior | Adapter required; runtime proof pending |
| Screencopy and previews | X11 capture backend | Not implemented / gated |
| Foreign-toplevel | i3 tree adapter | Provider mapping; UI integration pending |
| Wayland session lock | Dedicated X11 locker with PAM | Separate security boundary; not accepted |
| Hyprland-only integrations | Disable/gate | No i3 equivalent |
| Wayfire-only integrations | Disable/gate | No i3 equivalent |

## Quickshell version constraints

Target runtime: Quickshell 0.3.2 on the user's CachyOS LTS setup. Quickshell documentation and QML modules can drift. The only acceptable compatibility proof is loading the actual RXB-adapted QML against the target installed runtime (or an equivalent pinned build), followed by interaction tests. The current repository CI does not yet provide that full-shell proof.

## Lock and suspend security

The original lock UI depends on compositor-enforced Wayland session-lock semantics. A fullscreen QML window on X11 is not a secure replacement. RXB must keep the secure-lock capability unavailable until a dedicated X11 locker with PAM has passed multi-monitor, grab, crash, PAM failure, VT/session and suspend/resume tests. The visual shell must never handle authentication or be able to dismiss the authoritative lock.

## Hardware constraints

The target machine uses a GeForce GT 740 (Kepler) with proprietary driver 470.256.02 under Xorg, Quickshell 0.3.2 and CachyOS LTS kernel 6.18.64-1-cachyos-lts. Test QtQuick rendering, GLX/EGL selection, Picom interoperability, shader support, 1080p capture cost and monitor redraw without altering the installed driver, kernel or boot configuration. No real-hardware RXB runtime validation has been performed by CI.

## Audit completeness and acceptance

Completed:
- Initial provider seam and architectural comparison.
- Initial Wayland/X11 feature mapping.
- Go provider and upstream Go package checks in CI.
- Overlay unit and non-destructive package checks in CI.

Still required:
1. Generate a machine-readable QML dependency inventory from the exact pinned checkout.
2. Trace imports and QML APIs through all shell components, including optional and transitive dependencies.
3. Map each dependency to an implemented adapter, a safe capability gate or an explicit unsupported state.
4. Run Quickshell 0.3.2 QML load/lint and interaction tests in isolated X11.
5. Verify the original Ryoku daemon discovers the i3 provider and consumes its complete state/action contract.
6. Verify secure-lock and suspend behavior separately before enabling either capability.

This audit is not a line-by-line certification and does not authorize installation on the daily-use host.
