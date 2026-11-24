# RXB X11 troubleshooting and recovery

This guide applies to the separate **Ryoku (X11 / i3)** session. It does not authorize changes to BSPWM, SDDM, Orbital, the existing Quickshell lockscreen, Picom, NVIDIA, the kernel or boot configuration.

## First checks

Run these commands from the RXB session:

```bash
printf 'session=%s desktop=%s display=%s\n' "$XDG_SESSION_TYPE" "$XDG_CURRENT_DESKTOP" "$DISPLAY"
i3-msg -t get_version
qs --version
xrandr --query
if command -v glxinfo >/dev/null 2>&1; then glxinfo -B; else echo "glxinfo is optional and is not installed"; fi
nvidia-smi
systemctl --user --no-pager status \
  ryoku-x11-session.target ryoku-shell-x11.service ryogami-x11.service
```

The expected session type is `x11`. RXB no longer starts Picom automatically or reuses the BSPWM Picom configuration. Do not launch Picom with BSPWM settings to diagnose RXB. The NVIDIA driver should remain the version you had before testing. Do not install or switch drivers to make RXB start.

The session wrapper requires the display-manager-provided `XDG_SESSION_ID`. It verifies that login1 reports the current UID, `Type=x11`, and graphical `Class=user` or `user-early`. The pinned shell sleep guard independently resolves that exact ID; it does not guess a session by UID. Greeter, lock-screen, TTY and manager sessions remain excluded.


## Session missing from SDDM

Check the dedicated XSession entry and installed packages:

```bash
ls -l /usr/share/xsessions/ryoku-x11.desktop
grep -E '^(Name|Exec|TryExec)=' /usr/share/xsessions/ryoku-x11.desktop
pacman -Q ryoku-desktop-i3 ryoku-desktop ryoku-shell ryogami
```

RXB installs a separate session entry. It does not edit SDDM configuration or the Orbital theme. If the entry is missing, do not edit SDDM files manually; collect the logs and use the existing BSPWM session.

## Black screen, missing panels or Hub

RXB intentionally does not start Picom. This isolates the X11 session from the NVIDIA 470/Picom crash seen on the GT 740. It does not stop or modify the BSPWM Picom process or configuration. The RXB shell must remain usable without a compositor; do not copy the BSPWM Picom configuration into RXB.


Switch to a TTY with Ctrl+Alt+F3, log in, and inspect:

```bash
journalctl --user -b --no-pager
journalctl --user -b -u ryoku-x11-session.target \
  -u ryoku-shell-x11.service -u ryogami-x11.service --no-pager
journalctl -b -u sddm --no-pager
i3-msg -t get_version
pgrep -a -f 'i3|quickshell|ryoku|ryogami|picom'
loginctl show-session "$XDG_SESSION_ID" -p Id -p User -p Type -p Class -p Active
```

Return to the display manager and select the existing **BSPWM** session. Do not replace its config with RXB files. The RXB i3 config lives under the dedicated ryoku-x11 configuration directory.

## Lock or authentication issue

RXB uses XSecureLock when available and i3lock as its fallback. Both are expected to use PAM. Before testing the lock action, confirm you can log in from a TTY and know the account password.

```bash
command -v xsecurelock
command -v i3lock
ls -l /usr/lib/xsecurelock/authproto_pam
journalctl --user -b -u ryoku-x11-session.target --no-pager
```

The disposable Xephyr acceptance test validates both lockers, correct and incorrect passwords, deny-all PAM behavior, repeated lock requests and process cleanup. It does not validate your actual PAM policy, physical keyboard/pointer grabs or VT switching.

If a lock screen does not recover, switch to a TTY and use the existing BSPWM session at SDDM. Do not replace `/etc/pam.d/login`, `/etc/pam.d/sddm`, or any existing PAM service. Do not disable authentication to get past a lock screen.

## Capture or screenshot issue

Check the X11 tools and capture adapter:

```bash
command -v maim
command -v xclip
command -v ryoshot
journalctl --user -b -u ryoku-shell-x11.service --no-pager
```

The X11 capture adapter uses the supported X11 path. Wayland-only capture surfaces remain gated where equivalent behavior has not been verified.

## Power actions

Suspend and hibernate are intentionally disabled in RXB. The shell should report that the action is unavailable rather than changing the host's power policy or issuing an unsafe sleep command. Do not try to re-enable these actions through upstream Ryoku service commands.

## Collect evidence

From the extracted RXB bundle, run:

```bash
bash scripts/collect-x11-hardware-evidence.sh
journalctl --user -b --no-pager > "$HOME/rxb-user-journal.txt"
journalctl -b -u sddm --no-pager > "$HOME/rxb-sddm-journal.txt"
```

The evidence collector is read-only. Review the output before sharing it; redact usernames, hostnames, device serials, network names and other private information. Never share passwords, tokens or private authentication material.

## Rollback and removal

From the same verified bundle:

```bash
bash scripts/remove-rxb-packages.sh
```

The removal script removes only packages recorded as newly installed by RXB. It leaves packages that were already installed before RXB untouched and does not delete user configuration.

Keep the RXB user configuration for diagnosis by renaming it rather than deleting it:

```bash
if [[ -d "$HOME/.config/ryoku-x11" ]]; then
  mv "$HOME/.config/ryoku-x11" "$HOME/.config/ryoku-x11.backup-$(date +%Y%m%d-%H%M%S)"
fi
```

Do not run manual `pacman -Rns` commands for the RXB package list. Do not use `RXB_PACMAN_NOCONFIRM=1` on a host; that switch is restricted to the disposable transaction test.

## Host-preservation checklist

After rollback, verify that these remain unchanged:

- BSPWM and sxhkd configuration.
- SDDM configuration and the Ryoku Orbital theme.
- The existing Quickshell X11 lockscreen and Quickshell configuration.
- Picom configuration.
- NVIDIA driver, kernel, EDID settings, initramfs, GRUB and EFI files.
- Existing system power-management policy.
- The separate MRX-Desktop repository.
