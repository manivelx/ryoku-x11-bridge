# RXB architecture

## Goal
Run the original Ryoku desktop shell and services on Xorg using i3 and Quickshell. RXB is an X11 compatibility port, not a replacement shell or a hybrid of unrelated desktops. Preserve original QML and Go services wherever their dependencies permit.

## Target host
- CachyOS/Arch Linux x86_64
- Xorg + i3
- Quickshell 0.3.2
- Ryzen 7 8700F, 32 GB DDR5
- NVIDIA GeForce GT 740 (GK107, 4 GB DDR3), proprietary 470.256.02
- CachyOS LTS 6.18.64-1-cachyos-lts
- Acer EK240Y HDMI, 1920x1080@60

## Topology
```
Original Ryoku QML + Go services + Hub
                  |
           RXB compatibility layer
          /          |             \
 Quickshell X11   i3 provider    X11 adapters
          \          |             /
                  Xorg
                   |
             NVIDIA 470
                   |
                 Picom
```

Quickshell owns QML rendering and shell surfaces. i3 owns windows, focus, workspaces, tiling and outputs. RXB's provider implements the upstream ryoku-wm subprocess contract over i3 IPC. Dedicated X11 adapters replace unsupported Wayland services.

## Session service isolation
RXB starts only `ryoku-x11-session.target`, which owns `ryoku-shell-x11.service` and `ryogami-x11.service`. These dedicated units consume a mode-restricted session EnvironmentFile. The original upstream `ryoku-shell.service`, `ryogami.service`, `ryoku-session.target`, and their Wayland-specific hooks are not modified or reused. No default user target is enabled and no global user-manager environment is imported.

## Provider boundary
Implement the upstream `ryoku-wm-<name>` executable contract, not a new API. Inspect and match upstream's current JSON schemas and verbs for caps, state, watch, act, apply, defaults, schema, binds, outputs, session and environment. Window/workspace IDs are opaque handles. Capability declarations are promises and must be conservative. Watch must emit a full initial state, ready frame, typed newline-delimited JSON frames, and recover from socket loss by resynchronizing.

## State ownership
Use Quickshell's i3 integration in QML for workspace/monitor presentation where supported. The provider uses i3 IPC GET_TREE and event subscriptions for Go consumers' window/focus state. Define a single source of truth per field; do not create duplicate QML workspace clients.

## i3 IPC
Use framed i3 IPC with magic header, length and message type. Use request connection(s) for GET_WORKSPACES, GET_OUTPUTS, GET_TREE and RUN_COMMAND; use a separate SUBSCRIBE connection for events. Validate reply type and payload size, handle reconnect, debounce event bursts and resync snapshots. Never expose arbitrary command passthrough as semantic actions.

## Configuration
Keep neutral desktop settings separate from provider-owned wm.i3 settings. Generate only an RXB-owned include file or isolated i3 config. Preview must be side-effect-free. Preserve user config and report every unsupported setting. Never take ownership of another WM's config. RXB materializes Ryoku-managed user configuration at `~/.config/ryoku-x11/ryoku-config` (including QML at `.../ryoku-config/quickshell`) and routes Go services and QML through `RYOKU_CONFIG_HOME`; the user's existing `~/.config/quickshell` and other application configs remain untouched, and normal `XDG_CONFIG_HOME` is not redirected for applications.

## X11 surface adaptation
Quickshell X11 windows are not Wayland layer-shell surfaces. Test struts, stacking, popup placement, focus, click-through and monitor association under i3. Adapt each surface class deliberately rather than assuming WlrLayershell equivalence.

## Locking
A normal fullscreen QML window is not a secure X11 lock. Use a security-reviewed X11 locker (candidate: XSecureLock with PAM) as the security boundary. Ryoku QML may only be a visual layer beneath it. No QML unlock path. Validate grabs, multi-monitor coverage, PAM failure, process death, saver failure and suspend/resume before exposing lock capability.

## Protected resources
current BSPWM/sxhkd configuration, SDDM, Ryoku Orbital theme, existing Quickshell lock screen, existing `~/.config/quickshell` tree and other user config, Picom configuration, NVIDIA driver, kernel, GRUB/EFI, or existing autostart/services. Development uses Xephyr/Xvfb, temporary HOME and isolated i3 configs. Host installation requires explicit approval after rollback is tested.
