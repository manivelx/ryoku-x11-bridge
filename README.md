<div align="center">

# RXB — Ryoku X11 Bridge

**力と美のために** · *The original Ryoku desktop, brought to X11.*

An X11 compatibility layer that runs the original Ryoku shell with **i3, Xorg and Quickshell**.

[![i3 provider](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml/badge.svg?branch=main)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml)
[![Pinned upstream integration](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml/badge.svg?branch=main)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml)
![X11](https://img.shields.io/badge/session-X11-0d0d0d?style=for-the-badge)
![Window manager](https://img.shields.io/badge/window%20manager-i3-0d0d0d?style=for-the-badge)
![Quickshell](https://img.shields.io/badge/Quickshell-0.3.2-0d0d0d?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Arch%20%7C%20CachyOS-0d0d0d?style=for-the-badge)

<kbd>[Architecture](docs/architecture.md)</kbd> · <kbd>[Build](docs/build.md)</kbd> · <kbd>[Compatibility](docs/compatibility-matrix.md)</kbd> · <kbd>[Roadmap](docs/roadmap.md)</kbd>

</div>

## What it is

RXB is a compatibility port for the **original Ryoku desktop**. It keeps Ryoku's QML shell, Go services, Hub and CLI as the desktop experience, while replacing the Wayland compositor boundary with an X11/i3 provider and X11-specific adapters.

RXB is **not** a new desktop shell, a second desktop that communicates through a window, or a hybrid of unrelated shells. The intended result is one separate login session named **Ryoku (X11 / i3)**:

- **i3** owns windows, focus, tiling, workspaces and outputs.
- **Quickshell on X11** renders Ryoku's panels, popups, widgets and shell surfaces.
- **The RXB provider** implements Ryoku's existing `ryoku-wm` subprocess contract over i3 IPC.
- **X11 adapters** replace selected Wayland-facing services where a safe equivalent exists.
- **Original Ryoku services** run only inside the RXB session, not as global user-session services.

## How the desktop fits together

```text
             Original Ryoku shell, Hub, CLI and services
                              |
                       ryoku-wm contract
                              |
                         ryoku-wm-i3
                              |
                        i3 IPC socket
                              |
                         i3 on Xorg

             Quickshell 0.3.2 / QtQuick on X11
                    |                    |
              Quickshell.I3         X11 PanelWindow
              workspaces/outputs    panels, popups, overlays

             X11 capture / clipboard / lock adapters
                       RXB-owned session config
```

The provider reports capabilities conservatively. Features that depend on Wayland-only protocols are disabled or left unavailable rather than being simulated with fake Wayland objects.

## The session and installation model

RXB is an **integration package set**, not a standalone installer for a complete operating system.

The build produces:
1. The pinned original Ryoku runtime packages (shell, Hub, CLI, desktop payload and supporting services).
2. The RXB `ryoku-desktop-i3` variant, which provides the i3 provider, X11 session scripts, session-scoped service overrides and the `Ryoku (X11 / i3)` login entry.

Those packages are designed to be installed together in one package transaction. At login, the display manager starts `ryoku-x11-session`; i3 starts the session initializer; the initializer materializes Ryoku's shell configuration and starts the Ryoku services through the RXB-only `ryoku-session.target`. RXB's QML tree is kept under `~/.config/ryoku-x11/quickshell`; the existing `~/.config/quickshell` tree is left untouched. Quickshell then renders the original Ryoku shell against X11.

This is not a second desktop opening a communication window. The provider is the machine-readable bridge between Ryoku's window-manager layer and i3.

<blockquote>
<strong>Installation is not released yet.</strong> The build pipeline creates packages without installing them. Disposable install/uninstall validation, full shell runtime acceptance and security checks must pass before host installation instructions are published. Do not install the current artifacts on a daily-use system.
</blockquote>

## Build

The supported build target is Arch Linux or CachyOS x86_64. Build as an unprivileged `makepkg` user in a disposable environment.

```bash
git clone https://github.com/Ryoku-dev/ryoku.git ryoku
git clone https://github.com/manivelx/ryoku-x11-bridge.git ryoku-x11-bridge

cd ryoku
git checkout "$(tr -d '[:space:]' < ../ryoku-x11-bridge/UPSTREAM_PIN)"

cd ../ryoku-x11-bridge
bash scripts/build-rxb-packages.sh ../ryoku
```

Packages are written to `dist/`. The build uses a detached worktree of the pinned upstream source and does not patch the original Ryoku checkout or install packages on the build host.

See [docs/build.md](docs/build.md) for prerequisites, package inspection and the build sequence.

## Safety boundary

RXB is designed as a separate session. Its package overlay must not replace or rewrite:

- Existing BSPWM configuration or sxhkd bindings.
- SDDM configuration or the Ryoku Orbital theme.
- The existing Quickshell lockscreen.
- Picom configuration.
- NVIDIA drivers, kernel, GRUB/EFI or EDID settings.
- The separate MRX-Desktop project.

X11 environment variables are passed to the Ryoku shell through a session-scoped environment file. RXB does not import them into the shared systemd user-manager environment or enable the Ryoku shell globally.

## Current validation

| Area | Status |
|---|---|
| i3 provider | Implemented; Go vet, race tests and build pass in CI |
| Pinned upstream overlay | Applied and upstream Go tests pass in CI |
| Arch package build | Passes in disposable Arch CI |
| Package safety checks | Pass in disposable Arch CI |
| Quickshell 0.3.2 + i3 smoke | Minimal Xvfb smoke passes; this is not full-shell acceptance |
| Disposable package install/uninstall | Validation being added; not yet accepted |
| Full original shell on X11 | Not yet accepted |
| QML Wayland dependency audit | Partial; active-profile audit remains open |
| Lock/PAM and lock-before-suspend | Security validation pending; suspend handoff remains disabled |
| Multi-monitor and target GPU | Not tested on target hardware |

See the [compatibility matrix](docs/compatibility-matrix.md), [QML audit](docs/qml-x11-audit.md), [risk register](docs/risk-register.md) and [roadmap](docs/roadmap.md) for evidence and remaining gates.

## Known limitations

- i3 settings translation and generated keybinding management are not implemented; unsupported settings fail closed.
- The effective bind legend remains empty until the upstream bind catalogue and resolver are ported.
- Window rules, input settings, appearance settings and live output management are not translated.
- Wayland-only capture, persistent window previews, session lock and compositor-specific bridges are unavailable or gated.
- Wallpaper picker/runtime, tray, notifications, popup stacking, capture, multi-monitor behavior and complete shell interactions still need runtime acceptance.
- XSecureLock/i3lock wrapper selection is not equivalent to PAM, focus-grab, crash-recovery or lock-before-suspend security validation.

## Project references

| Document | Scope |
|---|---|
| [Architecture](docs/architecture.md) | Provider boundary, session ownership and X11 adapters |
| [Build guide](docs/build.md) | Pinned source, package build and safe inspection |
| [Compatibility matrix](docs/compatibility-matrix.md) | Feature-by-feature X11 support |
| [QML audit](docs/qml-x11-audit.md) | Wayland API inventory and migration status |
| [Risk register](docs/risk-register.md) | Security, packaging and runtime risks |
| [Roadmap](docs/roadmap.md) | Phases, acceptance gates and evidence ledger |

## Upstream

RXB targets the original [Ryoku desktop](https://github.com/Ryoku-dev/ryoku) and pins a specific upstream revision in [`UPSTREAM_PIN`](UPSTREAM_PIN). The overlay is applied only to a disposable worktree during package construction.

