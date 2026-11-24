# RXB installation and rollback

> **Validation-only bundle:** use this procedure only in a disposable Arch/CachyOS VM or a dedicated test installation with a verified recovery path. Do not install RXB on the owner's daily-use desktop yet. The automated package transaction and Xvfb/Xephyr tests pass, but physical input/VT/lock behavior, multi-monitor coverage, and GT 740 / NVIDIA 470 / Picom rendering have not been accepted. Keep the existing BSPWM session, SDDM Orbital theme, Quickshell lockscreen, Picom, NVIDIA driver, kernel, EDID and boot configuration unchanged.

RXB is distributed as an Arch package bundle built and tested against the pinned Ryoku source. The installer does not enable services globally or change the current desktop session.

## Audit blockers — do not skip

The full repository audit (2026-11-24) classified the project as **READY FOR ISOLATED TESTING ONLY**. This guide is not approval to install on a daily-use PC.

- **F1 — upstream host files:** the current `ryoku` package includes a tmpfiles configuration that creates world-writable hand-off files under `/var/lib/ryoku`, and `ryoku-boot-guard.service`. Their effect on the existing Ryoku Orbital SDDM theme has not been verified. Do not install this package set on the owner's PC until the owner explicitly decides whether these files are to be excluded or accepted and documented. No such decision is implied by a passing CI run.
- **F2 — Qt version:** `ryogami` requires `qt6-base>=6.12`. A stale host can pull a Qt upgrade and related package changes into the install transaction. Perform a deliberate full system update, reboot, and verify the existing BSPWM, Orbital SDDM theme and Quickshell lockscreen before considering RXB. Abort if the transaction proposes a Qt/Quickshell upgrade or removal.
- **F3/F4 — dependency transaction:** the installer now refuses known pre-existing conflicts (`bibata-cursor-theme(-bin)`, `gpk-bin`, `tlp`, `tuned-ppd`). It also checks for pending system updates, checks the installed Qt floor, prints a read-only dependency plan, and refuses to upgrade already-installed packages as an RXB side effect. Review every package pacman proposes to install. Do not use `RXB_PACMAN_NOCONFIRM=1` on a host. Abort if the transaction includes packages or removals you have not explicitly approved.
- **F5 — upstream CLI:** do not run `ryoku update`, `ryoku doctor`, `ryoku svc reconcile`, `ryoku boot-guard`, or any `ryoku-host` subcommand on the host. Their host-mutating behavior has not been fully audited.
- **Target hardware:** no acceptance has been performed on the GT 740 / NVIDIA 470 / Picom setup. Lock recovery, real input grabs, VT switching and multi-monitor behavior remain unverified.

These blockers must be resolved, documented and covered by passing tests before the readiness decision can be raised to controlled PC installation testing.

## Before installing

Run the bundled read-only host preflight from your existing BSPWM/X11 session as your normal user:

```bash
bash scripts/rxb-host-preflight.sh
```

It checks the OS/architecture, current X11 display, pacman state, recovery-session presence, installed Ryoku package conflicts, and inventories protected desktop paths and GPU/Quickshell status. It does not install packages or change configuration. **Stop if it reports any failure.** Resolve warnings and confirm the protected paths match your existing setup before proceeding. A passing preflight is not proof of NVIDIA/QtQuick runtime compatibility.

- Use Arch Linux or CachyOS x86_64 with a working Xorg session and pacman.
- Update the system first with `sudo pacman -Syu`. The installer deliberately does not run a partial `pacman -Sy`.
- Create a BTRFS/Snapper snapshot or another recovery point if your system uses one.
- Keep your existing BSPWM session available in the display manager.
- Close other package-manager processes.
- Do not remove or replace the NVIDIA driver, kernel, SDDM Orbital theme, or existing Quickshell lockscreen.

## Download and verify

Download the **rxb-install-bundle** artifact from the successful *pinned upstream integration* GitHub Actions run. Extract it, then from the extracted `rxb-install-bundle` directory run:

```bash
sha256sum -c SHA256SUMS
```

The bundle contains the package archives, install/remove scripts, the package-safety verifier, and the payload files that verifier inspects.

## Install

```bash
bash scripts/install-rxb-packages.sh
```

The script requests sudo when needed. It verifies the package set and protected paths, resolves missing runtime dependencies from the configured Arch repositories without refreshing package databases, prints a read-only dependency plan, refuses pending system updates or implicit upgrades of already-installed packages, installs the complete RXB X11 package set in one pacman transaction, and records only packages newly introduced by this installer. It refuses known package conflicts and refuses to overwrite any Ryoku package that is already installed but is not recorded as RXB-owned; review and resolve an existing Ryoku installation before proceeding.

Because F1 remains unresolved, the installer refuses the current upstream `ryoku` package by default. **Only in a disposable VM or dedicated test installation**, explicitly opt in to the audited upstream host-level files:

```bash
RXB_ALLOW_UNREVIEWED_UPSTREAM_HOST_FILES=1 bash scripts/install-rxb-packages.sh
```

This override is for isolated validation only. Do not set it on the daily-use CachyOS desktop. It does not remove, neutralize, or make the tmpfiles/boot-guard files safe; the owner decision is still pending.

After installation, the display manager should offer **Ryoku (X11 / i3)** as a separate session. RXB does not edit SDDM configuration or the Orbital theme; it only installs the XSession desktop entry. Select the new session at the login screen. Your BSPWM session remains installed.

## First-login checks

Only perform these checks in a disposable VM or dedicated test installation while F1 and the other host-install blockers remain unresolved.

1. Confirm the session is X11 and i3 is the window manager.
2. Confirm the RXB user target and Quickshell services are active.
3. Open the shell panels, launcher, settings and Hub; check that they respond.
4. Test the lock action and unlock with your normal account password. RXB uses XSecureLock when present, otherwise i3lock; both are PAM-backed. The disposable Xephyr acceptance test verifies real XSecureLock and i3lock PAM authentication with a temporary account. It does not validate the owner's actual PAM policy, VT switching, real-machine input grabs or multi-monitor lock coverage.
5. Suspend, hibernate and automatic suspend are intentionally disabled on X11. The shell reports this rather than issuing an unsafe power command.
6. Window live previews and other Wayland-only capture surfaces remain gated where X11 parity has not been proven.

If the session does not start cleanly, log out and select your existing BSPWM session. The RXB package does not replace BSPWM or change the display manager's configuration.

## Roll back

Run the bundled removal script:

```bash
bash scripts/remove-rxb-packages.sh
```

It removes only packages recorded as newly installed by the RXB installer and leaves packages that were already present untouched. Pacman will refuse a removal if another installed package still depends on one of the recorded packages. The script does not delete `~/.config/ryoku-x11`; back it up and remove it manually only if you no longer need those settings.

## What the installer does not change

- `/etc/sddm.conf`, SDDM drop-ins or the Ryoku Orbital theme
- BSPWM session files or user configuration
- Existing Quickshell lockscreen files and `~/.config/quickshell`
- NVIDIA drivers, kernel modules, EDID settings, initramfs, GRUB or EFI files
- Global systemd services or the shared systemd user-manager environment

Real target-hardware acceptance on the GT 740 / NVIDIA 470 / Picom setup remains a separate validation step. Do not infer it from the disposable Arch/Xvfb results.
