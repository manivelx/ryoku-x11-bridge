<div align="center">

# 〖 RXB — Ryoku X11 Bridge 〗

**力と美のために** · *The original Ryoku desktop, brought to X11.*

An X11 compatibility layer for the original Ryoku desktop, using **Xorg, i3 and Quickshell**.

[![i3 provider](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml/badge.svg?branch=main)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/go-provider.yml)
[![Pinned upstream integration](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml/badge.svg?branch=main)](https://github.com/manivelx/ryoku-x11-bridge/actions/workflows/upstream-integration.yml)
![X11](https://img.shields.io/badge/session-X11-0d0d0d?style=for-the-badge)
![Window manager](https://img.shields.io/badge/window%20manager-i3-0d0d0d?style=for-the-badge)
![Quickshell](https://img.shields.io/badge/Quickshell-0.3.2-0d0d0d?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Arch%20%7C%20CachyOS-0d0d0d?style=for-the-badge)

<kbd>[Architecture](docs/architecture.md)</kbd> · <kbd>[Build](docs/build.md)</kbd> · <kbd>[Compatibility](docs/compatibility-matrix.md)</kbd> · <kbd>[QML audit](docs/qml-x11-audit.md)</kbd> · <kbd>[Roadmap](docs/roadmap.md)</kbd>

</div>

> **Development status — not ready for installation on a daily-use machine.**
> RXB is still in integration and acceptance testing. The package build and parts of the automated test suite exist, but a passing build is not proof that the complete Ryoku desktop works on X11. Do not install RXB on your primary CachyOS system until this README explicitly marks the release as approved and the project owner has completed the pre-install review.

## • overview •

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
7. The initializer starts `ryoku-session.target`; the Ryoku shell and Ryogami services are linked only to this target.
8. Quickshell loads the original Ryoku shell against the X11/i3 provider.
9. When i3 exits, the session wrapper stops the RXB target and removes the temporary environment file.

RXB does not enable the Ryoku shell globally or import X11 variables into the shared systemd user-manager environment.

### What RXB is / isn't

RXB is an **integration package set**, not a standalone operating-system installer. It is designed to add one separate X11 session alongside the user's existing desktop.

The following must remain untouched by RXB installation and removal:

- Existing BSPWM configuration and sxhkd bindings.
- SDDM configuration and the Ryoku Orbital theme.
- The existing Quickshell lockscreen.
- The existing `~/.config/quickshell` tree.
- Existing Picom configuration.
- NVIDIA drivers, kernel, GRUB/EFI and EDID settings.
- Normal application configuration under `XDG_CONFIG_HOME`.

RXB stores its own Ryoku configuration below `~/.config/ryoku-x11/`. It does not repurpose the shared Quickshell configuration directory. App-wide GTK/Qt/terminal theming, icon/font changes and upstream lock/greeter management are gated until safe per-session implementations are available.

**Do not run an installer, package removal command, driver change, kernel change or SDDM reconfiguration as part of RXB testing unless the specific step is documented and approved.**

### Software overview

| Component | Purpose in RXB |
|---|---|
| Original Ryoku | Upstream QML shell, Hub, CLI and desktop services |
| Quickshell | QtQuick runtime for panels, popups, widgets and shell surfaces |
| Xorg | X11 display server |
| i3 | Window management, workspaces, focus, outputs and IPC |
| RXB provider | Implements the upstream `ryoku-wm` contract through i3 IPC |
| Picom | Existing X11 compositor; RXB does not replace or rewrite its configuration |
| X11 adapters | Compatibility layer for selected clipboard, capture, lock and session behaviors |
| systemd user session | Starts Ryoku services only inside the RXB session target |

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

## • instructions •

### Build from source

> **Build only in a disposable Arch/CachyOS VM.** The build script does not install packages, but it does compile upstream components and requires a complete set of build dependencies.

### 1. Install build tools in the disposable VM

Update the disposable Arch/CachyOS environment and install the toolchain used by the integration CI:

```bash
sudo pacman -Syu --needed
sudo pacman -S --needed \
  base-devel git curl go jq cmake ninja pkgconf python fish librsvg \
  xorg-xcursorgen hyprcursor xcur2png tesseract-data-eng \
  wayland wayland-protocols ffmpeg \
  qt6-base qt6-declarative qt6-multimedia qt6-shadertools \
  qt6-quick3d qt6-svg qt6-5compat qt6-imageformats qt6-wayland \
  vulkan-headers imagemagick quickshell i3-wm i3lock \
  xorg-server-xvfb xorg-xrandr maim xclip slop dbus
```

The package list may change with the pinned upstream PKGBUILDs. If `makepkg` reports a missing build dependency, stop and update the documented dependency set rather than using `--nodeps` to bypass a missing tool.

### 2. Clone RXB and the original Ryoku source

Use sibling directories so the commands below work unchanged:

```bash
git clone https://github.com/Ryoku-dev/ryoku.git
git clone https://github.com/manivelx/ryoku-x11-bridge.git

cd ryoku
git checkout "$(tr -d '[:space:]' < ../ryoku-x11-bridge/UPSTREAM_PIN)"
```

The upstream checkout must match the exact commit in `UPSTREAM_PIN`. The build script refuses an unpinned or different upstream revision.

### 3. Build the package set

Run as a normal, unprivileged user—not as root:

```bash
cd ../ryoku-x11-bridge
bash scripts/build-rxb-packages.sh ../ryoku
```

Packages are written to `dist/` by default. An optional second argument selects another output directory:

```bash
bash scripts/build-rxb-packages.sh ../ryoku /path/to/output
```

The build creates a detached temporary Git worktree at the pinned upstream commit, applies the RXB overlay there, builds the original Ryoku runtime packages and then builds `ryoku-desktop-i3`. It removes the temporary worktree after packaging. It does not patch your original Ryoku clone or install packages on the build host.

### 4. Inspect the generated packages

```bash
for package in dist/*.pkg.tar.*; do
  echo "===== $package ====="
  pacman -Qip "$package"
  pacman -Qlp "$package"
done
```

Do not install the packages on your primary desktop. Package inspection is not installation acceptance.

### Package inspection and automated validation

The repository contains these checks:

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

The disposable installation transaction is privileged and must run only inside the disposable Arch container/VM. CI runs it after resolving external dependencies from the official Arch repositories. It checks package registration, expected installed paths, the X11 session entry, service scoping and package removal. It is not a test of host rollback or the user's daily desktop.

For the complete CI workflow, see [`.github/workflows/upstream-integration.yml`](.github/workflows/upstream-integration.yml).

### Installation and first login

<blockquote>
<strong>Not approved for host installation yet.</strong> The steps in this section describe the intended release installation flow so it is documented in advance. Do not execute them on your primary CachyOS desktop until the release gate is changed by the project owner and the pre-install review is complete.
</blockquote>

### Release installation flow

When the package set has passed disposable installation/removal, runtime, security and target-hardware acceptance, the intended installation procedure is:

1. Back up important user data and ensure that the existing BSPWM session remains selectable.
2. Download the exact RXB package artifact attached to the approved GitHub Actions run, or build the exact reviewed commit using the instructions above.
3. Extract the package files into a dedicated directory such as `dist/`.
4. Review the package names and dependencies from their `.PKGINFO` metadata.
5. Install external dependencies from the official Arch repositories.
6. Install the complete local Ryoku + RXB package set in one pacman transaction.
7. Verify that the new `Ryoku (X11 / i3)` X11 session entry exists.
8. Log out and select the new session from the SDDM session selector. Keep BSPWM available as the recovery session.

The dependency and package transaction commands will be finalized against the exact release artifacts before host testing. Do not guess package versions or install a partial subset: the original Ryoku base packages and the RXB i3 variant are intended to be installed as one coherent package set.

### First login

After installation is explicitly approved:

1. Log out of the current desktop.
2. At SDDM, open the session selector.
3. Select **Ryoku (X11 / i3)**.
4. Log in normally.
5. Wait for i3, the RXB provider, the Ryoku session target and Quickshell to start.
6. If the session fails, return to SDDM and choose the existing BSPWM session. Do not disable or replace the existing session to troubleshoot RXB.

The package adds an X11 session desktop entry; it must not replace the SDDM configuration or the Orbital theme. No manual `systemctl --user enable ryoku-shell` command should be used. RXB starts the shell only through `ryoku-session.target` while the RXB X11 session is active.

### Starting and using the Ryoku desktop

The normal launch method is the SDDM session selector described above. The desktop entry invokes `ryoku-x11-session`, which starts i3 and initializes the Ryoku session.

Do not launch the shell daemon manually from BSPWM or another desktop. In particular, do not run `systemctl --user start ryoku-shell` outside the RXB session: the service requires the session-specific X11 environment and i3 IPC socket.

### Verify the active session

From a terminal opened inside the Ryoku session:

```bash
printf 'Session type: %s\n' "$XDG_SESSION_TYPE"
printf 'Desktop: %s\n' "$XDG_CURRENT_DESKTOP"
printf 'Window manager: %s\n' "$RYOKU_WM"

i3 --get-socketpath
systemctl --user status ryoku-session.target ryoku-shell.service ryogami.service
```

Expected session identifiers are `x11`, `Ryoku` and `i3`. The shell and wallpaper daemon should be associated with the RXB session target, not enabled under the default user target.

### Exit the session

Use the session's logout action or log out through the desktop/session controls. The session wrapper is responsible for stopping `ryoku-session.target` and removing its temporary environment file when i3 exits.

### Starter keybindings

These are the bindings in the current RXB i3 seed configuration. They are a conservative starting point, not a claim that every upstream shell action is fully functional yet. The `Super` key is `Mod4`.

| Key | Action |
|---|---|
| `Super + Return` | Launch the configured Ryoku terminal action |
| `Super + Space` | Open the Ryoku launcher action |
| `Super + Escape` | Open quick settings |
| `Super + ,` | Open Ryoku Hub |
| `Super + W` | Open the Ryogami wallpaper UI |
| `Super + Shift + S` | Screenshot action |
| `Super + L` | Lock through the RXB X11 locker wrapper |
| `Super + Q` | Close the focused window |
| `Super + F` | Toggle fullscreen |
| `Super + Shift + F` | Toggle floating |
| `Super + Arrow` | Move focus |
| `Super + Shift + Arrow` | Move the focused window |
| `Super + 1…9` | Switch workspace |
| `Super + Shift + 1…9` | Move window to workspace |
| `Super + Shift + R` | Reload the i3 configuration action |
| `Super + Shift + E` | Exit the session action |

User-owned overrides belong in `~/.config/ryoku-x11/user.conf`. Do not edit the packaged seed expecting changes to survive package upgrades.

## • configuration •

### Configuration locations

RXB keeps its configuration separate from the existing desktop:

| Path | Purpose |
|---|---|
| `~/.config/ryoku-x11/config` | RXB-owned i3 session configuration |
| `~/.config/ryoku-x11/generated.conf` | RXB-generated configuration |
| `~/.config/ryoku-x11/user.conf` | RXB user-owned i3 settings |
| `~/.config/ryoku-x11/ryoku-config/` | Ryoku configuration root used by RXB |
| `~/.config/ryoku-x11/ryoku-config/quickshell/` | RXB's Quickshell configuration tree |
| `$XDG_RUNTIME_DIR/ryoku-x11-session.env` | Temporary, mode-restricted session environment file |

The existing `~/.config/quickshell` directory remains separate and must not be overwritten. Do not copy the entire old Quickshell directory into the RXB configuration root unless a migration step is explicitly documented.

## • support and recovery •

### Troubleshooting

These commands are diagnostic only; they do not change the system configuration.

### Session does not appear in SDDM

Check that the session desktop file is installed:

```bash
test -f /usr/share/xsessions/ryoku-x11.desktop && cat /usr/share/xsessions/ryoku-x11.desktop
command -v i3
command -v ryoku-x11-session
```

If the file is missing, do not create it manually on the host. Capture the package list and installation logs and return to the existing BSPWM session.

### Session returns to SDDM or shows a blank screen

From BSPWM or a TTY, collect:

```bash
journalctl -b -u sddm --no-pager
journalctl --user -b --no-pager
systemctl --user status ryoku-session.target ryoku-shell.service ryogami.service
```

Also capture:

```bash
uname -r
pacman -Q i3-wm quickshell
nvidia-smi
cat /proc/driver/nvidia/version
```

Do not change the NVIDIA driver, kernel, EDID configuration, Picom configuration or display manager to work around an RXB failure without reviewing the logs first.

### Quickshell or Ryoku shell does not start

Check the session environment and service status:

```bash
echo "$DISPLAY"
echo "$XDG_SESSION_TYPE"
echo "$I3SOCK"
i3 --get-socketpath
systemctl --user status ryoku-session.target ryoku-shell.service
journalctl --user -u ryoku-shell.service -b --no-pager
```

Do not start the service globally as a workaround. The session environment file is created by the RXB session initializer and is removed when the session exits.

### Collect a diagnostic report

Before changing anything, collect the commands above, the exact Git commit or package versions, and the SDDM/session logs. Redact usernames, tokens, private paths and other personal data before sharing logs publicly.

### Uninstallation and recovery

Host uninstallation is not approved yet. The package-removal test currently runs in a disposable Arch environment; it does not prove that removing RXB from a machine with pre-existing Ryoku packages is safe.

For current development, use a disposable VM snapshot and test the complete package transaction and removal there. Do not run broad `pacman -Rns ryoku*` commands: they can remove unrelated or previously installed packages. A host rollback procedure will be published only after the installer records the exact packages it added and the removal path has been tested.

If an RXB session fails on a test machine, select the existing BSPWM session at SDDM. RXB must not require changing the default session or disabling the existing desktop.

## • limitations and safety •

### Security model and known limitations

- X11 does not provide the same compositor-enforced session-lock semantics as Wayland. The current XSecureLock/i3lock wrapper selection is not proof of secure PAM authentication, focus/input grabs, crash recovery or lock-before-suspend behavior.
- Lock-before-suspend remains disabled until the secure handoff is implemented and tested.
- Wayland-only capture, persistent window previews, some overview features and compositor-specific bridges are unavailable or gated.
- i3 settings translation and generated keybinding management are incomplete; unsupported settings must fail closed.
- The effective bind legend remains empty until the upstream bind catalogue and resolver are ported.
- Window rules, input settings, appearance settings and live output management are not fully translated.
- Wallpaper picker/runtime, tray, notifications, popup stacking, capture, multi-monitor behavior and complete shell interactions still need runtime acceptance.
- App-wide GTK/Qt/terminal theming and system font/icon changes are intentionally gated to preserve existing configuration.
- Upstream qylock and greeter management is disabled in RXB.
- NVIDIA 470 + QtQuick + Picom rendering has not passed target-hardware acceptance.
- The exhaustive active-profile QML/Wayland dependency audit remains open.

Stop testing if protected configuration changes, the existing desktop stops working, a lock/security behavior is uncertain, or the package manager proposes removing unrelated desktop components.

## • development •

### Development workflow

1. Read [`UPSTREAM_PIN`](UPSTREAM_PIN) before modifying upstream-derived behavior.
2. Keep upstream changes in the overlay; do not modify the original Ryoku checkout.
3. Keep RXB code and tests in this repository.
4. Run formatting, unit, race, package-safety, session lifecycle and Xvfb smoke tests.
5. Run the full upstream integration workflow against the exact pinned commit.
6. Update the compatibility matrix, QML audit, risk register and roadmap with evidence—not assumptions.
7. Do not mark host installation ready until disposable installation/removal, full-shell runtime, security and target-hardware acceptance are complete.

CI keeps validation runs per commit so a newer push does not cancel the result for an earlier commit. Always check the run associated with the exact commit under review.

## • upstream and project links •

### Documentation and upstream

| Document | Scope |
|---|---|
| [Architecture](docs/architecture.md) | Provider boundary, session ownership and X11 adapters |
| [Build guide](docs/build.md) | Pinned source, build prerequisites, package build and inspection |
| [Compatibility matrix](docs/compatibility-matrix.md) | Feature-by-feature X11 support |
| [QML audit](docs/qml-x11-audit.md) | Wayland API inventory and migration status |
| [Risk register](docs/risk-register.md) | Security, packaging and runtime risks |
| [Roadmap](docs/roadmap.md) | Phases, acceptance gates and evidence ledger |

RXB targets the original [Ryoku desktop](https://github.com/Ryoku-dev/ryoku) and pins a specific upstream revision in [`UPSTREAM_PIN`](UPSTREAM_PIN). The overlay is applied only to a disposable worktree during package construction.

- **RXB repository:** https://github.com/manivelx/ryoku-x11-bridge
- **Ryoku upstream:** https://github.com/Ryoku-dev/ryoku
