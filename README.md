<div align="center">

<img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/ryoku/assets/brand/logo-mark-v2.png" alt="Ryoku" width="132" />

# Ryoku X11 Bridge

**力と美のために** · *For the sake of power and beauty.*

The original Ryoku desktop, brought to X11.

[![i3 provider](https://img.shields.io/github/actions/workflow/status/manivelx/ryoku-x11-bridge/go-provider.yml?branch=main&label=i3%20provider&logo=github&logoColor=white&color=0d0d0d&style=for-the-badge)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml)
[![Pinned upstream integration](https://img.shields.io/github/actions/workflow/status/manivelx/ryoku-x11-bridge/upstream-integration.yml?branch=main&label=pinned%20upstream%20integration&logo=github&logoColor=white&color=0d0d0d&style=for-the-badge)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml)
![Session: X11](https://img.shields.io/badge/session-X11-0d0d0d?style=for-the-badge)
![Window manager: i3](https://img.shields.io/badge/window%20manager-i3-0d0d0d?style=for-the-badge)
![Quickshell: 0.3.2](https://img.shields.io/badge/Quickshell-0.3.2-0d0d0d?style=for-the-badge)
![Platform: Arch | CachyOS](https://img.shields.io/badge/platform-Arch%20%7C%20CachyOS-0d0d0d?style=for-the-badge)

[Architecture](docs/architecture.md) · [Build](docs/build.md) · [Compatibility](docs/compatibility-matrix.md) · [QML audit](docs/qml-x11-audit.md) · [Roadmap](docs/roadmap.md)

</div>

> **Stable integration baseline — not an installable release.** This branch contains the initial RXB X11/i3 integration and its source-build validation. It does not include the later installation/rollback workflow or the full package-transaction acceptance suite. Use the development branch for ongoing integration and isolated validation work. Do not install packages built from this branch on a daily-use CachyOS system.

## What it is

Ryoku is a complete Linux desktop with its own shell, services, Hub and command-line tools. **RXB (Ryoku X11 Bridge)** is the compatibility layer intended to run the original Ryoku desktop in a separate X11 session.

RXB does not recreate Ryoku with another shell, merge unrelated desktop projects, or convert an existing BSPWM session into a hybrid desktop. The intended session is **Ryoku (X11 / i3)**:

- **Xorg** provides the X11 display server.
- **i3** owns windows, focus, tiling, workspaces and outputs.
- **Quickshell on X11** renders Ryoku shell surfaces where the upstream APIs permit it.
- **The RXB provider** implements the upstream ryoku-wm subprocess contract over i3 IPC.
- **X11 adapters** replace selected Wayland-facing services where a safe equivalent exists.
- **Original Ryoku components** remain the source of the shell and visual design.

RXB is separate from MRX-Desktop. It does not replace, merge with or modify MRX.

## Architecture

The original Ryoku shell, Hub and CLI call the upstream window-manager contract. RXB supplies the ryoku-wm-i3 provider, which communicates with the i3 IPC socket in the X11 session. Quickshell 0.3.2 and QtQuick render the shell surfaces using the Quickshell.I3 and X11 PanelWindow adapters. X11 service adapters provide capture, clipboard and locking where a safe equivalent exists. RXB keeps its configuration under the dedicated ryoku-x11 configuration directory.

The Go provider implements the upstream subprocess contract: caps, state, watch, act, apply, defaults, schema, binds, outputs, session and environment. It uses i3's framed Unix-socket IPC and keeps X11 session state separate from other desktop sessions.

## Host-preservation boundary

RXB is intended to be a separate Xorg + i3 session. It must not replace or rewrite:

- Existing BSPWM configuration or sxhkd bindings.
- SDDM configuration or the Ryoku Orbital theme.
- The existing Quickshell X11 lockscreen or the user's Quickshell configuration.
- Picom configuration.
- NVIDIA drivers, kernel modules, EDID settings, initramfs, GRUB or EFI files.
- Existing system power-management policy.
- The separate MRX-Desktop repository.

The package build uses a detached worktree of the pinned upstream source. Building packages is not the same as validating a host installation.

## Current status on main

| Area | Status |
|---|---|
| i3 provider and upstream window-manager contract | Initial integration present |
| Quickshell X11 adapter | Initial integration present; full visual acceptance remains open |
| Original Ryoku keybinding catalogue | Upstream catalogue integration present |
| Package build | Source build pipeline present |
| Package installation, upgrade and rollback | Not provided as a supported host workflow on this branch |
| Daily-use installation | Not approved |
| GT 740 / NVIDIA 470 / Picom hardware acceptance | Not performed |

The development branch contains the ongoing package-safety, host-preservation, lock/PAM and disposable-install validation work. Its status is deliberately stricter than a successful source build: CI evidence must match the exact commit being considered, and no physical hardware compatibility is claimed before testing.

## Build

See the build guide for source-build prerequisites and the reproducible upstream pin recorded in UPSTREAM_PIN. The build script produces package artifacts in its configured output directory; it does not install them. Do not run pacman package-install commands on your daily-use system.

## Documentation

- [Architecture](docs/architecture.md)
- [Build](docs/build.md)
- [Compatibility matrix](docs/compatibility-matrix.md)
- [QML/X11 audit](docs/qml-x11-audit.md)
- [Upstream audit](docs/upstream-audit.md)
- [Risk register](docs/risk-register.md)
- [Roadmap](docs/roadmap.md)

## Upstream attribution

RXB adapts the original [Ryoku desktop](https://github.com/Ryoku-dev/ryoku). Upstream code, assets and third-party components retain their respective licenses and attribution requirements. Consult the upstream repository and the license/notice files shipped with the validated development package set before redistributing derived artifacts.
