# Building RXB packages

## Scope and safety

This script builds the original Ryoku runtime packages from the pinned upstream checkout, applies the RXB X11 overlay, and builds the i3 provider package.

**It does not install any packages.** Do not install the resulting package set on the existing CachyOS host until the disposable-VM validation phase passes. The build may require development tools already installed on the build machine; use an Arch/CachyOS VM rather than the daily-use desktop.

The overlay explicitly skips the upstream distribution-level SDDM/qylock bundle, system services manifest, hardware helper binaries, udev/modprobe/polkit/logind rules, and boot/UKI integration. It replaces the desktop package install scriptlet with metadata refresh only. The RXB i3 package adds a systemd user drop-in for the Ryoku shell service; it does not change the existing SDDM configuration, Orbital theme, Quickshell lockscreen files, NVIDIA driver, kernel, or bootloader.

## Prerequisites

- Arch Linux or CachyOS x86_64.
- A non-root account allowed to run `makepkg`.
- Git, Python 3, Go, base-devel, and the build dependencies declared by the upstream PKGBUILDs (including the Qt/CMake/Ninja development packages used by Ryoku's QML plugin package).
- Enough free disk space for the upstream checkout and package artifacts.

The script uses `makepkg --nodeps` and does not install build or runtime dependencies. Install the required build tools in the disposable VM before running it.

## Prepare the pinned source

```bash
git clone https://github.com/Ryoku-dev/ryoku.git
cd ryoku
git checkout 0bf11741b22f69f22ad2733025671c7d0a5e1a47
```

Clone RXB separately:

```bash
git clone https://github.com/manivelx/ryoku-x11-bridge.git
```

## Build

From the RXB checkout:

```bash
bash scripts/build-rxb-packages.sh /path/to/ryoku-checkout
```

Artifacts are written to `RXB/dist/` by default. An optional second argument selects another output directory.

The build order is:
1. GPK and Ryoku keyring.
2. Ryoku blobs and palette bridge.
3. Ryoku shell, Hub, Ryogami and CLI.
4. The original Ryoku desktop payload, built from the patched checkout.
5. `ryoku-desktop-i3`, which provides the upstream `ryoku-desktop-compositor` virtual package.

The upstream desktop package's `.install` script is replaced in the patched checkout with a non-destructive scriptlet. The X11 variant does not depend on the umbrella desktop package, avoiding a package dependency cycle.

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
- The X11 provider's i3 settings generator and user keybinding translation are not yet implemented; the initial i3 config is a conservative seed.
- The original shell's Wayland-only services and features remain gated or unavailable on X11.
- Screen recording, wallpaper daemon behavior, some overlays, and complete multi-monitor behavior still need runtime testing.
- The X11 lock path delegates to XSecureLock when installed, otherwise i3lock. Suspend remains disabled/fail-closed until a secure lock-before-suspend handoff is implemented.
- QML runtime validation and real hardware testing on the target GT 740/NVIDIA 470 machine are not yet complete.
