# RXB installation and rollback

> **Validation-only bundle:** use this procedure only in a disposable Arch/CachyOS VM or a dedicated test installation with a verified recovery path. Do not install RXB on the owner's daily-use desktop yet. The automated package transaction and Xvfb/Xephyr tests pass, but physical input/VT/lock behavior, multi-monitor coverage, and GT 740 / NVIDIA 470 / Picom rendering have not been accepted. Keep the existing BSPWM session, SDDM Orbital theme, Quickshell lockscreen, Picom, NVIDIA driver, kernel, EDID and boot configuration unchanged.

RXB is distributed as an Arch package bundle built and tested against the pinned Ryoku source. The installer does not enable services globally or change the current desktop session.

## Audit blockers — do not skip

The full repository audit (2026-11-24) classified the project as **READY FOR ISOLATED TESTING ONLY**. This guide is not approval to install on a daily-use PC.

- **F1 — upstream host files (fixed in this branch):** the RXB overlay sets `RYOKU_X11_BRIDGE=1` for the upstream `ryoku` package and omits both `ryoku-boot-guard.service` and `ryoku.conf` tmpfiles installation. The boot guard can inspect or repoint `/boot/limine.conf` and EFI variables; the tmpfiles rules create shared `/etc/ryoku` and `/var/lib/ryoku` state plus SDDM greeter hand-off files. RXB also removes the upstream `ryoku-keyring` dependency/package: its `.INSTALL` script would add the Ryoku signing key to the system pacman trust database, while RXB's updater is disabled and the local package bundle does not need that repository key. Package safety rejects the boot-guard/tmpfiles paths, the keyring package, keyring files and pacman trust-store scriptlets.
- **F2 — Qt version:** `ryogami` requires `qt6-base>=6.12`. A stale host can pull a Qt upgrade and related package changes into the install transaction. Perform a deliberate full system update, reboot, and verify the existing BSPWM, Orbital SDDM theme and Quickshell lockscreen before considering RXB. Abort if the transaction proposes a Qt/Quickshell upgrade or removal.
- **F3/F4 — dependency transaction:** the installer now refuses known pre-existing conflicts (`bibata-cursor-theme(-bin)`, `gpk-bin`, `tlp`, `tuned-ppd`). It also checks for pending system updates, checks the installed Qt floor, prints a read-only dependency plan, and refuses to upgrade already-installed packages as an RXB side effect. Review every package pacman proposes to install. `RXB_PACMAN_NOCONFIRM=1` is enforced as a disposable-container-only test mode by a root-owned marker; both install and removal scripts reject it on a normal host. Abort if the transaction includes packages or removals you have not explicitly approved.
- **F5 — upstream CLI (guarded in this branch):** `ryoku update`, `rollback`, `boot-guard`, `boot-menu`, `deploy`, `recovery` and `track` are disabled in the RXB build; `ryoku doctor` is forced into read-only `--check` mode. `ryoku-host` blocks service reconciliation, all system-scope service mutations, persistent user-service enable/disable, direct upstream Ryoku service control, `session start` (which imports environment into the shared user manager), session bootstrap/wrapper repair, repository changes, initramfs rebuilds, and suspend/hibernate. Explicit package-management and other privileged UI actions still use the upstream authorization path; only invoke them when you intentionally want that host change.
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

The RXB package build now excludes the upstream boot-guard service and global tmpfiles file entirely. The installer has no bypass switch for them: package safety rejects a stale or modified bundle if either file reappears.

After installation, the display manager should offer **Ryoku (X11 / i3)** as a separate session. RXB does not edit SDDM configuration or the Orbital theme; it only installs the XSession desktop entry. Select the new session at the login screen. Your BSPWM session remains installed.

## First-login checks

Perform the first install and functional acceptance in a disposable VM or dedicated test installation. F1–F5 are guarded in this branch, but target-hardware acceptance (especially GT 740/NVIDIA 470/Picom and real keyboard/pointer lock behavior) remains outstanding.

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
