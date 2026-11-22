# Building RXB packages

## Scope and safety

This script builds the original Ryoku runtime packages from the pinned upstream checkout, applies the RXB X11 overlay, and builds the i3 provider package.

**It does not install any packages.** Do not install the resulting package set on the existing CachyOS host until the disposable-VM validation phase passes. The build may require development tools already installed on the build machine; use an Arch/CachyOS VM rather than the daily-use desktop.

The overlay explicitly skips the upstream distribution-level SDDM/qylock bundle, system services manifest, hardware helper binaries, udev/modprobe/polkit/logind rules, and boot/UKI integration. It replaces the desktop package install scriptlet with metadata refresh only. The RXB i3 package adds a systemd user drop-in for the Ryoku shell service and starts it only through `ryoku-session.target`; it does not call `systemctl --user enable` or import X11 variables into the shared user-manager environment. The session writes a mode-0600 environment file for the Ryoku shell unit and removes it when i3 exits. The Ryogami Go daemon is linked only into `ryoku-session.target` and receives the same session-scoped environment file. RXB uses `RYOKU_CONFIG_HOME` under `~/.config/ryoku-x11/ryoku-config` while leaving normal `XDG_CONFIG_HOME` unchanged for applications. Upstream lock/greeter mutation, app-wide theme writes, and host icon/font changes are gated by `RYOKU_X11_BRIDGE=1`. Its picker QML is covered by the panel-property overlay, but wallpaper/picker runtime behavior remains unvalidated. It does not change the existing SDDM configuration, Orbital theme, Quickshell lockscreen files, the existing `~/.config/quickshell` tree, NVIDIA driver, kernel, or bootloader. RXB's Ryoku-managed config is materialized under `~/.config/ryoku-x11/ryoku-config` (including Quickshell at `~/.config/ryoku-x11/ryoku-config/quickshell`). The overlay routes Ryoku services and QML to that root through `RYOKU_CONFIG_HOME` without changing the session's normal `XDG_CONFIG_HOME`, so applications keep using their existing configs.

## Prerequisites

- Arch Linux or CachyOS x86_64.
- A non-root account allowed to run `makepkg`.
- Git, Python 3, Go, base-devel, and the build dependencies declared by the upstream PKGBUILDs (including the Qt/CMake/Ninja development packages used by Ryoku's QML plugin package).
- Enough free disk space for the upstream checkout and package artifacts.

The script creates a detached temporary Git worktree at the pinned commit, applies the overlay there, and removes that worktree after packaging. It does not modify your original upstream clone. It uses `makepkg --nodeps` and does not install build or runtime dependencies; install the required build tools in the disposable VM before running it.

## Prepare the pinned source

```bash
git clone https://github.com/Ryoku-dev/ryoku.git ryoku
git clone https://github.com/manivelx/ryoku-x11-bridge.git ryoku-x11-bridge

cd ryoku
git checkout "$(tr -d '[:space:]' < ../ryoku-x11-bridge/UPSTREAM_PIN)"
```

## Build

From the RXB checkout:

```bash
bash scripts/build-rxb-packages.sh /path/to/ryoku-checkout
```

Artifacts are written to `RXB/dist/` by default. An optional second argument selects another output directory.

The pinned upstream revision is read from `UPSTREAM_PIN`. The RXB provider version is read from `RXB_VERSION` and injected with Go linker flags. The Arch package `pkgver` for `ryoku-desktop-i3` follows the pinned upstream `VERSION`, while upstream packages such as `ryoku-desktop` and `ryogami` keep their own independent `pkgver`/`pkgrel` values. The i3 variant therefore depends on those package names without imposing a false version equality. The RXB provider module declares Go 1.22, its CI tests that minimum, and upstream integration uses Go 1.26.5 because the pinned shell/Hub modules declare that toolchain.

The build order is:
1. GPK and Ryoku keyring.
2. Ryoku blobs and palette bridge.
3. Ryoku shell, Hub, Ryogami and CLI.
4. `ryoku-cursors` and `ryoku-cursor-material`.
5. The original Ryoku desktop payload, built from the patched checkout.
6. `ryoku-desktop-i3`, which provides the upstream `ryoku-desktop-compositor` virtual package.

The upstream desktop package's `.install` script is replaced in the patched checkout with a non-destructive scriptlet. The i3 variant follows the same provider/base dependency pattern as the upstream Hyprland and niri variants: it depends on the matching `ryoku-desktop` base and provides `ryoku-desktop-compositor`. Treat the base, cursor dependencies and variant as one package set. CI verifies that all Ryoku-owned dependencies are represented in the artifact set, then performs an install/remove transaction inside a disposable Arch container with external dependency resolution disabled. This validates package registration, payload paths, session wiring and removal; it is not a host install or a full dependency-install test.

## Verify package artifacts

```bash
for f in dist/*.pkg.tar.*; do
  pacman -Qip "$f"
  pacman -Qlp "$f"
done
```

Do not run `pacman -U` on the daily-use system. First install into a disposable VM/root, verify that SDDM, the Orbital theme, the existing Quickshell lockscreen, NVIDIA 470, kernel and EFI files remain unchanged, then test the separate "Ryoku (X11 / i3)" session.

## Current limitations

- This is a package-build pipeline, not an installation or rollback tool.
- The X11 provider's i3 settings generator and user keybinding translation are not yet implemented; the initial i3 config is a conservative seed. The session lifecycle test verifies that RXB uses its own `~/.config/ryoku-x11` and `~/.config/ryoku-x11/ryoku-config` trees while preserving an existing `~/.config/quickshell` directory.
- The original shell's Wayland-only services and features remain gated or unavailable on X11.
- App-wide GTK/Qt/terminal theming, system font changes, icon-theme changes, and upstream lock/greeter management are disabled in RXB until they have safe per-session adapters.
- Screen recording, wallpaper daemon behavior, some overlays, and complete multi-monitor behavior still need runtime testing.
- The X11 lock command prefers XSecureLock and falls back to i3lock. The wrapper selection is testable, but PAM authentication, input grabs, multi-monitor coverage, failure behavior and crash recovery still need security tests. Suspend remains disabled/fail-closed until a secure lock-before-suspend handoff is implemented.
- QML runtime validation and real hardware testing on the target GT 740/NVIDIA 470 machine are not yet complete.
