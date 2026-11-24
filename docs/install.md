# RXB installation and rollback

> **Controlled PC test candidate — explicit approval required.** This guide is for a one-time, supervised installation test on the stated CachyOS target only after the owner has reviewed the exact CI artifact and approved installation. It is not a daily-use or general release. Disposable Arch package, Xvfb/i3, real PAM/Xephyr and rollback tests have passed; physical input/VT/lock behavior, multi-monitor coverage, and GT 740 / NVIDIA 470 / Picom rendering remain unverified. Keep the existing BSPWM session, SDDM Orbital theme, Quickshell lockscreen, Picom, NVIDIA driver, kernel, EDID and boot configuration unchanged.

RXB is distributed as an Arch package bundle built and tested against the pinned Ryoku source. The installer does not enable services globally or change the current desktop session.

## Audit blockers — do not skip

The full repository audit (2026-11-24) classified the project as suitable for isolated validation. The latest disposable acceptance has passed, but this guide does not replace the owner's explicit approval or physical hardware acceptance.

- **F1 — upstream host files (fixed in this branch):** the RXB overlay sets `RYOKU_X11_BRIDGE=1` for the upstream `ryoku` package and omits both `ryoku-boot-guard.service` and `ryoku.conf` tmpfiles installation. The boot guard can inspect or repoint `/boot/limine.conf` and EFI variables; the tmpfiles rules create shared `/etc/ryoku` and `/var/lib/ryoku` state plus SDDM greeter hand-off files. RXB also removes the upstream `ryoku-keyring` dependency/package: its `.INSTALL` script would add the Ryoku signing key to the system pacman trust database, while RXB's updater is disabled and the local package bundle does not need that repository key. Package safety rejects the boot-guard/tmpfiles paths, the keyring package, keyring files and pacman trust-store scriptlets.
- **F2 — Qt version:** `ryogami` requires `qt6-base>=6.12`. A stale host can pull a Qt upgrade and related package changes into the install transaction. Do not update the host as part of RXB testing: a full update could change the protected CachyOS LTS kernel or NVIDIA 470 driver. Stop if updates are pending. Only resolve them in a separately approved maintenance window, then verify BSPWM, Orbital SDDM and the existing Quickshell lockscreen before repeating preflight. Abort if the RXB transaction proposes a Qt/Quickshell upgrade or removal.
- **F3/F4 — dependency transaction:** the installer now refuses known pre-existing conflicts (`bibata-cursor-theme(-bin)`, `gpk-bin`, `tlp`, `tuned-ppd`). It also checks for pending system updates, checks the installed Qt floor, prints a read-only dependency plan, and refuses to upgrade already-installed packages as an RXB side effect. Review every package pacman proposes to install. `RXB_PACMAN_NOCONFIRM=1` is enforced as a disposable-container-only test mode by a root-owned marker; both install and removal scripts reject it on a normal host. Abort if the transaction includes packages or removals you have not explicitly approved.
- **F5 — upstream CLI (guarded in this branch):** `ryoku update`, `rollback`, `boot-guard`, `boot-menu`, `deploy`, `recovery` and `track` are disabled in the RXB build; `ryoku doctor` is forced into read-only `--check` mode. `ryoku-host` blocks service reconciliation, all system-scope service mutations, persistent user-service enable/disable, direct upstream Ryoku service control, `session start` (which imports environment into the shared user manager), session bootstrap/wrapper repair, repository changes, initramfs rebuilds, and suspend/hibernate. Explicit package-management and other privileged UI actions still use the upstream authorization path; only invoke them when you intentionally want that host change.
- **Target hardware:** no acceptance has been performed on the GT 740 / NVIDIA 470 / Picom setup. Lock recovery, real input grabs, VT switching and multi-monitor behavior remain unverified.

F1–F5 now have implementation guards and regression coverage. The current disposable CI run is the evidence gate for the exact package bundle. Physical hardware acceptance remains open and must be performed by the owner.

## Before installing

Run the bundled read-only host preflight from your existing BSPWM/X11 session as your normal user:

```bash
bash scripts/rxb-host-preflight.sh
```

It checks the OS/architecture, current X11 display, pacman state, recovery-session presence, installed Ryoku package conflicts, and inventories protected desktop paths and GPU/Quickshell status. It does not install packages or change configuration. **Stop if it reports any failure or pending package updates.** If neither locker binary is installed yet, it warns because the RXB transaction supplies XSecureLock and i3lock. Resolve other warnings and confirm the protected paths match your existing setup before proceeding. A passing preflight is not proof of NVIDIA/QtQuick runtime compatibility.

- Use Arch Linux or CachyOS x86_64 with a working Xorg session and pacman.
- Do not run `sudo pacman -Syu` as part of this RXB test. If preflight reports pending updates, stop; do not bypass the installer's clean-package-state check. Any system maintenance must be separately approved, with the NVIDIA driver and kernel protected.
- If Snapper is configured for the root filesystem, create a root snapshot. Also back up the existing BSPWM, sxhkd, Picom, Quickshell and Quickshell-lockscreen directories as described in [hardware acceptance](hardware-acceptance.md).
- Keep your existing BSPWM session available in the display manager.
- Close other package-manager processes.
- Do not remove or replace the NVIDIA driver, kernel, SDDM Orbital theme, or existing Quickshell lockscreen.

## Download and verify

Download the **rxb-install-bundle** artifact from the successful *pinned upstream integration* GitHub Actions run. Extract it, then from the extracted `rxb-install-bundle` directory run:

```bash
sha256sum -c SHA256SUMS
```

The bundle contains the package archives, install/remove scripts, read-only host preflight, hardware evidence collector, installation and troubleshooting guides, hardware acceptance checklist, licensing notices, and the payload files. Verify the SHA256SUMS file before running any script.

## Install

```bash
bash scripts/install-rxb-packages.sh
```

The script requests sudo when needed. It verifies the package set and protected paths, resolves missing runtime dependencies from the configured Arch repositories without refreshing package databases, prints a read-only dependency plan, refuses pending system updates or implicit upgrades of already-installed packages, installs the complete RXB X11 package set in one pacman transaction, and records only packages newly introduced by this installer. Read the entire pacman plan before confirming it. Abort if it proposes package removals, protected driver/kernel changes, unexpected dependency changes or any package you have not approved. Never set RXB_PACMAN_NOCONFIRM on the host.

The RXB package build now excludes the upstream boot-guard service and global tmpfiles file entirely. The installer has no bypass switch for them: package safety rejects a stale or modified bundle if either file reappears.

After installation, the display manager should offer **Ryoku (X11 / i3)** as a separate session. RXB does not edit SDDM configuration or the Orbital theme; it only installs the XSession desktop entry. Select the new session at the login screen. Your BSPWM session remains installed.

## First-login checks

Perform the first install only after reviewing the artifact, creating a recovery point and explicitly approving the controlled PC test. This is not a daily-use release. Target-hardware acceptance (especially GT 740/NVIDIA 470/Picom and real keyboard/pointer lock behavior) remains outstanding.

1. Confirm the session is X11 and i3 is the window manager: `printf '%s\\n' "$XDG_SESSION_TYPE"` and `i3-msg -t get_version`.
2. Confirm the RXB user target and Quickshell services are active: `systemctl --user status ryoku-x11-session.target ryoku-shell-x11.service ryogami-x11.service`.
3. Open the original shell panels, launcher, settings and Hub; check navigation and window focus.
4. Verify the existing Picom process and rendering: `pgrep -a picom`, `xrandr --query`, `nvidia-smi`, and `glxinfo -B` if installed.
5. Test one lock/unlock cycle only after confirming a working TTY login and recovery path. Use your normal account password. CI has verified real XSecureLock and i3lock PAM behavior in Xephyr; your actual PAM policy, physical input grabs, VT switching and multi-monitor lock coverage still require testing.
6. Capture a screenshot and test the X11 capture adapter.
7. Suspend, hibernate and automatic suspend are intentionally disabled on X11. Do not try to enable them.
8. Window live previews and other Wayland-only capture surfaces remain gated where X11 parity has not been proven.

If the session does not start cleanly, log out and select your existing BSPWM session. The RXB package does not replace BSPWM or change the display manager's configuration.

## Roll back

Run the bundled removal script:

```bash
bash scripts/remove-rxb-packages.sh
```

It removes only packages recorded as newly installed by the RXB installer and leaves packages that were already present untouched. Pacman will refuse a removal if another installed package still depends on one of the recorded packages. The script does not delete `~/.config/ryoku-x11`. Keep it for diagnosis or rename it to a backup after removal; do not delete it until you have reviewed its contents.

## Troubleshooting and evidence collection

From the extracted bundle, collect read-only evidence:

```bash
bash scripts/collect-x11-hardware-evidence.sh
journalctl --user -b --no-pager > "$HOME/rxb-user-journal.txt"
journalctl -b -u sddm --no-pager > "$HOME/rxb-sddm-journal.txt"
```

For session failures, inspect:

```bash
journalctl --user -b -u ryoku-x11-session.target \
  -u ryoku-shell-x11.service -u ryogami-x11.service --no-pager
journalctl -b -u sddm --no-pager
i3-msg -t get_version
qs --version
xrandr --query
nvidia-smi
```

See [TROUBLESHOOTING.md](troubleshooting.md) for session, Hub, lock, capture and recovery steps. If RXB fails, return to SDDM and select BSPWM; do not edit SDDM or replace the Orbital theme. The removal script is the rollback path.

## What the installer does not change

- `/etc/sddm.conf`, SDDM drop-ins or the Ryoku Orbital theme
- BSPWM session files or user configuration
- Existing Quickshell lockscreen files and `~/.config/quickshell`
- NVIDIA drivers, kernel modules, EDID settings, initramfs, GRUB or EFI files
- Global systemd services or the shared systemd user-manager environment

Real target-hardware acceptance on the GT 740 / NVIDIA 470 / Picom setup remains a separate validation step. Do not infer it from the disposable Arch/Xvfb results.
