<div align="center">

<img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/ryoku/assets/brand/logo-mark-v2.png" alt="Ryoku" width="132" />

# Ryoku X11 Bridge

**力と美のために** · *For the sake of power and beauty.*

The original Ryoku desktop, brought to X11.

[![Provider CI](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml/badge.svg?branch=rxb%2Fdisposable-install-validation)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml)
[![Upstream integration](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml/badge.svg?branch=rxb%2Fdisposable-install-validation)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml)
![X11](https://img.shields.io/badge/session-X11-0d0d0d?style=for-the-badge)
![i3](https://img.shields.io/badge/window%20manager-i3-0d0d0d?style=for-the-badge)
![Quickshell](https://img.shields.io/badge/Quickshell-0.3.2-0d0d0d?style=for-the-badge)
![Arch](https://img.shields.io/badge/platform-Arch%20%7C%20CachyOS-0d0d0d?style=for-the-badge)

<kbd>[Architecture](docs/architecture.md)</kbd> · <kbd>[Build](docs/build.md)</kbd> · <kbd>[Compatibility](docs/compatibility-matrix.md)</kbd> · <kbd>[QML audit](docs/qml-x11-audit.md)</kbd> · <kbd>[Roadmap](docs/roadmap.md)</kbd>

</div>

> **Development build — not ready for installation on a daily-use machine.** RXB has passed provider tests, pinned upstream Go tests, an Arch package build, and an isolated Quickshell/i3 startup smoke. Disposable Arch package transaction checks have also passed on a prior validated commit. This is not a completed desktop acceptance: interactive shell surfaces, secure locking, multi-monitor behavior, host rollback and the target GT 740 / NVIDIA 470 desktop still need validation.

<div align="center">
  <img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/docs/media/showroom/blue-hour.webp" alt="Original Ryoku desktop visual reference" width="100%" />
  <sub>Original Ryoku upstream showroom image — design reference only, not an RXB X11 screenshot.</sub>
</div>

## What it is

Ryoku is a complete Linux desktop with its own shell, services, Hub and command-line tools. **RXB (Ryoku X11 Bridge)** is the compatibility port that aims to run that original desktop in an X11 session.

The goal is not to recreate Ryoku with another shell, build a generic communication window, or combine unrelated desktop projects. RXB keeps the original Ryoku experience and replaces the Wayland compositor-facing boundary with an i3 provider and narrowly scoped X11 adapters.

The intended result is a separate login session named **Ryoku (X11 / i3)**:

- **Xorg** provides the X11 display server.
- **i3** owns windows, focus, tiling, workspaces and outputs.
- **Quickshell on X11** renders Ryoku's panels, popups, widgets and shell surfaces.
- **The RXB provider** implements Ryoku's existing `ryoku-wm` subprocess contract over i3 IPC.
- **X11 adapters** replace selected Wayland-facing services where a safe equivalent exists.
- **Original Ryoku services** run only inside the RXB session, not as global user-session services.

RXB is separate from MRX-Desktop. It does not replace, merge with or modify MRX.

## The desktop

The original Ryoku shell is the visual and interaction target. Its bar styles, launcher, control sidebar, Hub, widgets, dock, overview and desktop services are upstream Ryoku components; RXB's task is to make those components behave correctly on X11 rather than to substitute a new interface.

<div align="center">
<table>
  <tr>
    <td width="50%"><img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/docs/media/showroom/red-august.webp" alt="Ryoku Red August theme reference" width="100%" /><br /><sub>Red August — upstream reference</sub></td>
    <td width="50%"><img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/docs/media/showroom/rose.webp" alt="Ryoku Rose theme reference" width="100%" /><br /><sub>Rose — upstream reference</sub></td>
  </tr>
  <tr>
    <td width="50%"><img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/docs/media/showroom/teal.webp" alt="Ryoku Teal theme reference" width="100%" /><br /><sub>Teal — upstream reference</sub></td>
    <td width="50%"><img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/docs/media/showroom/aether.webp" alt="Ryoku Aether theme reference" width="100%" /><br /><sub>Aether — upstream reference</sub></td>
  </tr>
</table>
<sub>These images belong to the original Ryoku project. They illustrate the intended visual direction and do not claim that these surfaces are already validated in RXB.</sub>
</div>

### X11 architecture

```text
             Original Ryoku shell, Hub, CLI and services
                              |
                       ryoku-wm contract
                              |
                         ryoku-wm-i3
                              |
                        i3 IPC socket
                              |
                           i3 / Xorg

             Quickshell 0.3.2 / QtQuick on X11
                    |                    |
              Quickshell.I3         X11 PanelWindow
              workspaces/outputs    panels, popups, overlays

             RXB session adapters and isolated config
```

The provider advertises capabilities conservatively. A Wayland-only feature is unavailable until an X11 implementation has been proven; RXB does not fabricate Wayland objects or report unsupported actions as successful.

### Session lifecycle

1. The display manager starts **Ryoku (X11 / i3)**.
2. `ryoku-x11-session` validates the X11 environment and starts i3 with RXB's session configuration.
3. The initializer discovers the active i3 IPC socket, ignoring inherited stale i3/Sway socket variables.
4. RXB materializes Ryoku's QML and settings into its dedicated configuration root.
5. A mode-restricted session environment file is written under `$XDG_RUNTIME_DIR`.
6. `ryoku-x11-session.target` starts the RXB-owned shell and Ryogami services.
7. Quickshell loads the original Ryoku shell against the i3 provider.
8. When i3 exits, the wrapper stops the RXB target and removes the temporary environment file.

The shell is not enabled globally, and X11 variables are not imported into the shared systemd user-manager environment.

## Editions and platform

RXB is currently an **Arch Linux / CachyOS x86_64 development integration**. It targets an Xorg session, i3, systemd user sessions and Quickshell 0.3.2 / QtQuick on X11. It is not an upstream Ryoku edition and does not currently provide an ISO or a stable release.

| Environment | Status |
|---|---|
| Arch Linux x86_64, Xorg + i3 | Development and disposable CI target |
| CachyOS x86_64, Xorg + i3 | Intended target; host acceptance pending |
| Wayland sessions | Not supported by RXB |
| Other distributions | Not currently validated |
| Daily-use installation | Not ready |

The exact Ryoku source revision is pinned in [`UPSTREAM_PIN`](UPSTREAM_PIN). Builds must use that revision; moving upstream branches are not treated as reproducible inputs.

## Feature and validation status

A source adapter, a successful build, an Xvfb smoke test and real desktop acceptance are separate evidence levels.

| Area | Current evidence |
|---|---|
| i3 provider | Implemented; Go formatting, vet, race tests and build passed on a recorded CI commit |
| Upstream overlay | Applied to a disposable pinned worktree; upstream Go test suites passed on a recorded CI commit |
| Quickshell i3 integration | Quickshell.I3 and X11 PanelWindow smoke passed under Xvfb |
| Original shell daemon | Basic daemon IPC and QML-process startup smoke passed in isolated Xvfb+i3 |
| Arch packages | Package build and safety inspection passed in disposable Arch CI |
| Package transaction | Install/remove transaction passed in disposable Arch CI on the recorded successful baseline |
| Full interactive Ryoku shell | Not accepted |
| Active-profile QML / Wayland audit | Partial; exhaustive inventory remains open |
| Keybinding translation | Original 105-action catalogue is resolved into i3 bindings where semantics match; remaining actions are visible with explicit unsupported reasons |
| Secure lock / PAM / lock-before-suspend | Not security-validated; suspend handoff remains disabled |
| Multi-monitor, capture and previews | Not accepted |
| GT 740 / NVIDIA 470 / Picom rendering | Not tested to acceptance on target hardware |
| Daily-host installation and rollback | Not accepted |

See the [compatibility matrix](docs/compatibility-matrix.md), [QML / Wayland audit](docs/qml-x11-audit.md), [risk register](docs/risk-register.md), and [roadmap](docs/roadmap.md) for evidence and release gates.

## Install

**There is no safe daily-host installation procedure yet.**

Do not run `pacman -U`, the upstream Ryoku installer, package-removal commands, or SDDM/session changes on your everyday CachyOS installation. The current workflow is for building and testing inside a disposable Arch/CachyOS VM or snapshot.

RXB's package design deliberately avoids the upstream distribution-level SDDM/qylock bundle, boot/UKI integration, udev/modprobe/polkit/logind rules and global service enablement. It uses a separate `RYOKU_CONFIG_HOME` under `~/.config/ryoku-x11/ryoku-config`, preserving the normal `XDG_CONFIG_HOME` and existing `~/.config/quickshell` tree.

The intended session must coexist with the existing **BSPWM session, SDDM Orbital theme, Quickshell X11 lockscreen, Picom configuration, NVIDIA driver, kernel and boot setup**. Host rollback, lock security, interactive acceptance and target hardware testing remain release gates.

## Build and test

Use a disposable Arch or CachyOS VM with a non-root build account. Install the build prerequisites described in [the build guide](docs/build.md).

Clone the sources:

```bash
git clone https://github.com/Ryoku-dev/ryoku.git ryoku
git clone https://github.com/manivelx/ryoku-x11-bridge.git ryoku-x11-bridge

cd ryoku
git checkout "$(tr -d '[:space:]' < ../ryoku-x11-bridge/UPSTREAM_PIN)"
cd ../ryoku-x11-bridge
```

Build the package set as a normal user:

```bash
bash scripts/build-rxb-packages.sh ../ryoku
```

The script checks the upstream pin, creates a disposable detached worktree, applies the RXB overlay there, builds the original Ryoku packages and the i3 provider package, then removes the temporary worktree. It does **not** install packages.

Run the non-installing checks:

```bash
python3 -m py_compile scripts/apply-upstream-overlay.py
python3 -m unittest discover -s tests

bash -n payload/bin/ryoku-x11-session
bash -n payload/bin/ryoku-x11-session-init
bash -n payload/bin/ryoku-x11-lock

bash scripts/test-x11-lock-wrapper.sh
bash scripts/test-rxb-session-lifecycle.sh
bash scripts/test-rxb-package-safety.sh dist
bash scripts/test-quickshell-i3-smoke.sh
```

The privileged package transaction/removal check runs in disposable Arch CI. It is not a test of installing or rolling back on your real CachyOS host.

## Day to day

Not available yet. The original shell daemon can start in the isolated Xvfb+i3 smoke environment, but the user-facing workflows have not been accepted for everyday use.

RXB does not add custom keybindings; it translates the original shipped Ryoku catalogue without inventing shortcuts. At session startup and when Ryoku applies settings, the provider generates i3 bindings from the pinned 105-action upstream catalogue. Semantically compatible actions are translated; unsupported actions remain visible with explicit reasons. Upstream custom bindings, rebinds, disabled actions and chord conflicts are resolved using Ryoku's precedence rules. The generated include is isolated from the user-owned user.conf. Some upstream actions and non-keybinding desktop settings remain unsupported.

## Hardware

The primary hardware acceptance target is the existing CachyOS desktop:

| Component | Target |
|---|---|
| CPU | AMD Ryzen 7 8700F |
| RAM | 32 GB DDR5 |
| GPU | NVIDIA GeForce GT 740, 4 GB DDR3 |
| NVIDIA driver | Proprietary 470.256.02 |
| Kernel | CachyOS LTS 6.18.64-1 |
| Quickshell | 0.3.2 |
| Window manager | i3 |
| Display server | Xorg |
| Existing desktop | BSPWM / SDDM / Ryoku Orbital |
| Existing lockscreen | Quickshell X11 lockscreen |

This table is the target test profile, not a compatibility claim. The GT 740 has no iGPU fallback in this machine, so RXB must not replace the current NVIDIA stack or jeopardize the working recovery desktop.

## Where things are

| Guide | What it covers |
|---|---|
| [Architecture](docs/architecture.md) | Session ownership, provider contract and X11 adapters |
| [Build guide](docs/build.md) | Pinned source, prerequisites and package generation |
| [Compatibility matrix](docs/compatibility-matrix.md) | X11 strategies and feature acceptance evidence |
| [QML / Wayland audit](docs/qml-x11-audit.md) | QML APIs and migration status |
| [Risk register](docs/risk-register.md) | Security, packaging and runtime risks |
| [Roadmap](docs/roadmap.md) | Phases, release gates and evidence ledger |

## Credits and license

RXB targets the original [Ryoku desktop](https://github.com/Ryoku-dev/ryoku), maintained in the [Ryoku upstream repository](https://github.com/Ryoku-dev/ryoku). The upstream revision is recorded in [`UPSTREAM_PIN`](UPSTREAM_PIN), and the overlay is applied to a disposable worktree during builds.

The RXB i3 package metadata declares `GPL-3.0-or-later`. The repository-level license and combined upstream/third-party notice audit are not yet complete. Preserve all upstream and third-party notices; do not assume that every bundled asset, font or plugin shares the RXB package license. See risk R16 in the [risk register](docs/risk-register.md).

<div align="center">
  <sub>RXB is an independent X11 compatibility effort for the original Ryoku desktop. It is not an official Ryoku release.</sub>
</div>
