# Upstream Ryoku audit

## Pin
- Upstream: https://github.com/Ryoku-dev/ryoku
- Audited version: 1.1.0
- Audited main commit: 0bf11741b22f69f22ad2733025671c7d0a5e1a47
- Commit date: 2026-11-17
- Commit URL: https://github.com/Ryoku-dev/ryoku/commit/0bf11741b22f69f22ad2733025671c7d0a5e1a47
- Upstream declares GNU GPL-3.0. Preserve file notices and audit third-party asset licenses before copying code/assets.

## Shared provider seam
Relevant upstream files:
- ryoku/wm/caps.go — capability manifest
- ryoku/wm/state.go — state and frame structures
- ryoku/wm/action.go — semantic action IDs
- ryoku/wm/client.go — subprocess protocol and provider discovery
- ryoku/wm/detect.go — session/environment detection
- ryoku/wm/hyprland/* — reference provider
- ryoku/wm/niri/* — socket-driven reference provider
- ryoku/wm/wayfire/* — IPC/config reference provider

The provider is a subprocess protocol, not an in-process Go interface. It includes capability manifests, state snapshots, newline-delimited watch frames, semantic actions, config apply, defaults, schema, keybinds, output layout, session and environment handoff. Match exact upstream schemas and error behavior. Do not branch consumer logic on provider name/version. Capabilities are behavior promises. IDs are opaque. Apply preview must not write.

## Provider references
Hyprland provider uses hyprctl and compositor sockets, plus Hyprland-owned config. niri uses its Unix socket and KDL. Wayfire uses its IPC socket and INI composition. None is an existing X11/i3 provider; their architecture is useful, but protocol and configuration cannot be copied blindly.

## QML/Wayland audit leads
Searches of the pinned tree identified use of:
- Quickshell.Wayland, WlrLayershell, WlrKeyboardFocus
- WlSessionLock and WlSessionLockSurface in qylock
- ScreencopyView in overview, dock previews and capture flows
- ToplevelManager / foreign-toplevel paths in taskbar and launcher services
- Quickshell.Hyprland in compositor-specific bridges
- Wayland-specific capture, keyboard focus and surface behavior

Search results are leads, not a complete dependency proof. Each imported type, usage, conditional and transitive dependency must be inventoried. Search coverage is currently incomplete.

## Quickshell
The target host and CI use Quickshell 0.3.2. CI passed the Quickshell.I3 + X11 PanelWindow API smoke and a basic full-shell daemon/QML-load smoke under Xvfb+i3. This confirms the tested API surface and startup path only; visual stacking, struts, focus, popups, tray, notifications, wallpaper picker, capture, lock and multi-monitor interactions remain separate acceptance items. Current online documentation may differ from the installed package.

## Lock security
The original qylock depends on Wayland session-lock semantics. X11 cannot provide the same compositor-enforced ext_session_lock_v1 guarantee. Do not port it as a normal fullscreen QML window. Candidate: XSecureLock + PAM as the authoritative locker; QML visual only.

## Hardware risks
The GT 740 is Kepler. NVIDIA 470.256.02 is the legacy proprietary stack currently working on Xorg. CI has exercised the shell with Xvfb/software rendering, not the target GPU. Still test QtQuick/GLX/EGL, Picom interaction, shader/effect support, 1080p capture performance and multi-monitor redraw without changing the driver/kernel. No target-hardware validation has been performed.

## Audit completeness
Initial architecture/provider audit, Quickshell 0.3.2 API smoke, package build, package-safety checks, basic full-shell daemon/QML-load smoke and disposable Arch install/removal have passed in CI. Exhaustive QML import/use inventory, complete service dependency audit, interactive feature validation and target-hardware/security acceptance remain open. This document must not be treated as a complete line-by-line certification of the upstream source tree.
