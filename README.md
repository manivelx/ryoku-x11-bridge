<div align="center">

# Ryoku X11 Bridge

**力と美のために** · *The original Ryoku desktop, adapted for X11.*

An X11 compatibility port for Ryoku using **Xorg, i3 and Quickshell**.

[![i3 provider](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml/badge.svg?branch=rxb%2Fdisposable-install-validation)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml)
[![Pinned upstream integration](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml/badge.svg?branch=rxb%2Fdisposable-install-validation)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml)
![X11](https://img.shields.io/badge/session-X11-0d0d0d?style=for-the-badge)
![i3](https://img.shields.io/badge/window%20manager-i3-0d0d0d?style=for-the-badge)
![Quickshell](https://img.shields.io/badge/Quickshell-0.3.2-0d0d0d?style=for-the-badge)
![Arch](https://img.shields.io/badge/platform-Arch%20%7C%20CachyOS-0d0d0d?style=for-the-badge)

<kbd>[Architecture](docs/architecture.md)</kbd> · <kbd>[Build](docs/build.md)</kbd> · <kbd>[Compatibility](docs/compatibility-matrix.md)</kbd> · <kbd>[QML audit](docs/qml-x11-audit.md)</kbd> · <kbd>[Roadmap](docs/roadmap.md)</kbd>

</div>

> **Development build — do not install on your daily-use PC yet.** The exact current commit has passed CI provider, upstream Go tests, Arch package build, Quickshell/Xvfb shell smoke, and disposable Arch install/removal. This is package and integration evidence, not proof that every desktop feature works. Secure locking, feature interactions, multi-monitor behavior and your GT 740 / NVIDIA 470 desktop have not passed acceptance.

<img src="https://raw.githubusercontent.com/Ryoku-dev/ryoku/main/docs/media/showroom/blue-hour.webp" alt="Ryoku upstream desktop visual reference. RXB has not yet reproduced or validated this complete appearance on X11." width="100%" />

<div align="center"><sub>Upstream Ryoku visual reference — illustrative only; not an RXB X11 screenshot.</sub></div>

### What RXB is

RXB is a compatibility port for the **original [Ryoku desktop](https://github.com/Ryoku-dev/ryoku)**. It keeps Ryoku's QML shell, Go services, Hub and CLI as the desktop experience, while replacing the Wayland compositor boundary with an X11/i3 provider and X11-specific adapters.

RXB is not a new desktop shell, a communication window, or a hybrid of unrelated shells. It is a separate desktop integration project and does not replace, merge with, or modify **MRX-Desktop**. MRX-Desktop remains unfinished and under active development; it is not being treated as a daily-use desktop.

The intended result is a separate login session named **Ryoku (X11 / i3)**:

- **Xorg** provides the X11 display server.
- **i3** owns windows, focus, tiling, workspaces and outputs.
- **Quickshell on X11** renders Ryoku's panels, popups, widgets and shell surfaces.
- **The RXB provider** implements Ryoku's existing `ryoku-wm` subprocess contract over i3 IPC.
- **X11 adapters** replace selected Wayland-facing services where a safe equivalent exists.
- **Original Ryoku services** run only inside the RXB session, not as global user-session services.

The goal is to run the original Ryoku experience on X11—not to imitate it with a different shell.

## The X11 port

### Architecture

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

### Session startup sequence

1. The display manager starts the `Ryoku (X11 / i3)` X11 session entry.
2. `ryoku-x11-session` validates the X11 environment and starts i3 with the RXB-owned starter configuration.
3. The i3 startup command runs `ryoku-x11-session-init`.
4. The initializer discovers the active i3 IPC socket, ignoring inherited stale i3/Sway socket variables.
5. RXB materializes the original Ryoku QML/configuration into its dedicated configuration root.
6. A mode-restricted session environment file is written under `$XDG_RUNTIME_DIR`.
7. The initializer starts `ryoku-x11-session.target`; the Ryoku shell and Ryogami services are linked only to this target.
8. Quickshell loads the original Ryoku shell against the X11/i3 provider.
9. When i3 exits, the session wrapper stops the RXB target and removes the temporary environment file.

RXB does not enable the Ryoku shell globally or import X11 variables into the shared systemd user-manager environment.

## Hardware and compatibility

## • platform and compatibility •

### Target platform

### Supported development target

- Arch Linux or CachyOS, x86_64.
- systemd user sessions.
- Xorg and i3.
- Quickshell 0.3.2 / QtQuick X11.
- The pinned Ryoku upstream revision recorded in [`UPSTREAM_PIN`](UPSTREAM_PIN).

### Target-machine validation profile

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

This table describes the test target, not a claim that RXB has already passed on this hardware. No RXB step should replace the existing NVIDIA driver, kernel, boot configuration, SDDM theme or working recovery session.

### Feature and validation status

A source implementation, a successful compile, an Xvfb smoke test and a real desktop acceptance test are different evidence levels. Do not treat them as interchangeable.

| Area | Current evidence |
|---|---|
| i3 provider | Implemented; Go formatting, vet, race tests and build have passed in CI on earlier validated commits |
| Pinned upstream overlay | Implemented; upstream Go test suites have passed in CI on earlier validated commits |
| Arch package build | Builds in a disposable Arch CI container on earlier validated commits |
| Package safety inspection | Implemented; earlier CI checks passed |
| Quickshell 0.3.2 + i3 smoke | Minimal Xvfb smoke has passed; not full-shell acceptance |
| Disposable install/uninstall | Test and dependency resolution are being hardened; latest branch acceptance is pending |
| Full original Ryoku shell on X11 | Not accepted |
| Active-profile QML / Wayland audit | Partial; exhaustive audit remains open |
| Lock/PAM and lock-before-suspend | Security validation pending; suspend handoff remains disabled |
| Multi-monitor behavior | Not accepted |
| GT 740 + NVIDIA 470 + Picom rendering | Not tested to acceptance on target hardware |
| Host installation and rollback | Not accepted |

Check the [live GitHub Actions runs](https://github.com/manivelx/ryoku-x11-bridge/actions) for the result associated with the current commit. A result from an older commit does not validate later changes.

Detailed evidence and remaining gates:
- [Compatibility matrix](docs/compatibility-matrix.md)
- [QML / Wayland audit](docs/qml-x11-audit.md)
- [Risk register](docs/risk-register.md)
- [Roadmap and acceptance gates](docs/roadmap.md)

## Build and test

RXB is currently a developer integration project. Build and disposable acceptance are available; a safe host installation is not.

### 1. Build in a disposable Arch or CachyOS VM

Install the build dependencies in a VM or snapshot that can be discarded:

```bash
sudo pacman -Syu --needed
sudo pacman -S --needed \
  base-devel git curl go jq cmake ninja pkgconf python fish librsvg \
  xorg-xcursorgen hyprcursor xcur2png tesseract-data-eng \
  wayland wayland-protocols ffmpeg \
  qt6-base qt6-declarative qt6-multimedia qt6-shadertools \
  qt6-quick3d qt6-svg qt6-5compat qt6-imageformats qt6-wayland \
  vulkan-headers imagemagick quickshell i3-wm i3lock \
  xorg-server-xvfb xorg-xrandr maim xclip slop dbus mesa
```

### 2. Clone the pinned sources

```bash
git clone https://github.com/Ryoku-dev/ryoku.git
git clone https://github.com/manivelx/ryoku-x11-bridge.git

cd ryoku
git checkout "$(tr -d '[:space:]' < ../ryoku-x11-bridge/UPSTREAM_PIN)"
```

### 3. Build RXB packages

Run as a normal user, not root:

```bash
cd ../ryoku-x11-bridge
bash scripts/build-rxb-packages.sh ../ryoku
```

Packages are written to `dist/`. This creates a disposable worktree at the pinned upstream revision, applies the RXB overlay there and builds the package set. It does not patch the original Ryoku checkout or install packages on the build host.

### 4. Run non-installing checks

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

The privileged full package transaction/removal test runs in the disposable Arch CI environment only. Review the exact [GitHub Actions run](https://github.com/manivelx/ryoku-x11-bridge/actions/runs/45008912887) and its artifacts for the current commit.

## Install

<blockquote>

**Not available for host installation.**

Do not run `pacman -U`, the Ryoku upstream installer, package removal commands, or any SDDM/session changes on your daily CachyOS installation. RXB has not completed host rollback, security, interactive feature or GT 740/NVIDIA 470 acceptance. This is not an install guide yet.

</blockquote>

The intended release design is a separate **Ryoku (X11 / i3)** login session. It must leave the existing BSPWM session, SDDM Orbital theme, Quickshell lockscreen, Picom configuration, NVIDIA driver, kernel and boot setup untouched. The release installer and rollback procedure will be documented only after those guarantees have been tested on an isolated target.

## Day to day

Not available yet. The upstream Ryoku shell daemon can be started in the disposable Xvfb+i3 smoke environment, but user-facing desktop workflows and controls are not accepted for daily use. RXB does not add custom keybindings: the upstream Ryoku binding catalogue and faithful i3 translation are still being ported. The active-bind view currently reports actual i3 config bindings only.

## Where things are

| Guide | Scope |
|---|---|
| [Architecture](docs/architecture.md) | Session ownership, provider contract and X11 adapters |
| [Build guide](docs/build.md) | Pinned source, build prerequisites and package generation |
| [Compatibility matrix](docs/compatibility-matrix.md) | X11 strategy and feature acceptance evidence |
| [QML / Wayland audit](docs/qml-x11-audit.md) | QML API dependencies and migration status |
| [Risk register](docs/risk-register.md) | Security, packaging and runtime risks |
| [Roadmap](docs/roadmap.md) | Phases, release gates and evidence ledger |

## Upstream, credits and license

RXB targets the original [Ryoku desktop](https://github.com/Ryoku-dev/ryoku). The pinned upstream source revision is recorded in [`UPSTREAM_PIN`](UPSTREAM_PIN); the overlay is applied to a disposable worktree during builds.

## • license and attribution •

The RXB i3 package metadata currently declares `GPL-3.0-or-later`. The RXB repository does not yet contain a top-level `LICENSE` file, and the combined upstream-derived distribution still requires a final license and notice audit. Do not infer that every upstream asset, font, QML plugin or bundled component shares the RXB package license.

Before publishing a release artifact for redistribution, the project owner must confirm the RXB source license, add the corresponding repository license file, and preserve all upstream and third-party notices. This is tracked as risk **R16** in the [risk register](docs/risk-register.md).

- **RXB:** https://github.com/manivelx/ryoku-x11-bridge
- **Ryoku upstream:** https://github.com/Ryoku-dev/ryoku
