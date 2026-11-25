# RXB target-hardware acceptance

This checklist separates automated disposable-environment evidence from acceptance on the owner's actual CachyOS desktop. A successful CI run is not target-hardware approval.

## Target hardware profile

| Component | Target |
|---|---|
| Distribution | CachyOS / Arch Linux, x86_64 |
| CPU | AMD Ryzen 7 8700F |
| Memory | 32 GB DDR5 |
| GPU | NVIDIA GeForce GT 740, GK107, 4 GB DDR3 |
| Graphics driver | NVIDIA proprietary legacy 470.256.02 |
| Kernel | CachyOS LTS |
| Display server | Xorg / X11 |
| Existing desktop | BSPWM + sxhkd |
| RXB session | Separate i3 session |
| Compositor | Existing Picom configuration |
| Shell runtime | Quickshell 0.3.2 |
| Display manager | SDDM with Ryoku Orbital theme |
| Existing lockscreen | Quickshell X11 lockscreen |

This is the intended acceptance target, not a compatibility claim. The machine has no integrated-GPU fallback. RXB must use the existing NVIDIA driver and kernel without replacing, upgrading or reconfiguring them.

## Safety rules

- Do not run the RXB installer until the owner has reviewed the final bundle and explicitly approved the controlled test.
- Keep the existing BSPWM session, SDDM Orbital theme, Quickshell lockscreen, Picom configuration, NVIDIA driver, kernel, EDID setup and boot configuration unchanged.
- Do not run a lock test that could strand the active session. Perform real lock testing only after recovery access and a second login path are confirmed.
- Do not enable suspend/hibernate handoff. RXB intentionally fails closed for those actions on X11.
- Review the generated report before sharing it. It excludes window titles, process command lines, serial numbers, network addresses and home-directory contents, but still contains hardware/software inventory.

## Before the controlled test

1. From the existing BSPWM/X11 session, run the bundled read-only preflight and evidence collector. Stop if the preflight reports a failure or pending package updates.
2. Do not run a system update as part of RXB testing. A full update could change the protected CachyOS LTS kernel or NVIDIA 470 driver. Resolve pending updates only in a separate maintenance window that you explicitly approve, then repeat the preflight.
3. If Snapper is configured for the root filesystem, inspect its configurations with `sudo snapper list-configs`. If a `root` configuration exists, create a snapshot before installation:

   ```bash
   sudo snapper -c root create --description "before RXB controlled test"
   ```

4. Back up the existing user configuration directories before proceeding:

   ```bash
   backup="$HOME/rxb-preserve-$(date +%Y%m%d-%H%M%S)"
   mkdir -m 700 "$backup"
   for path in "$HOME/.config/bspwm" "$HOME/.config/sxhkd" "$HOME/.config/picom" "$HOME/.config/quickshell" "$HOME/.local/share/quickshell-lockscreen"; do
     [[ ! -e "$path" ]] || cp -a --parents "$path" "$backup"
   done
   printf 'Preservation backup: %s\n' "$backup"
   ```

5. Keep a working TTY login and confirm that you can return to SDDM and select BSPWM before testing the lock action.

## Read-only evidence collection

From an existing X11 session, run:

```bash
bash scripts/collect-x11-hardware-evidence.sh
```

The script creates `rxb-hardware-evidence/report.txt` with OS/kernel, graphics device and driver, OpenGL renderer, X server, monitor/mode, i3, Picom, Quickshell and relevant package versions. It does not install packages, edit configuration, start/stop services, or invoke the locker.

If the report is being collected after RXB is installed in a disposable test system, the RXB package section also records the installed package versions.

## Manual acceptance sequence

Record each item as pass, fail, or not tested. Attach screenshots/logs only after checking them for personal information.

1. **Session coexistence:** verify the display manager still offers the original BSPWM session and that it starts normally. Confirm the Orbital theme and existing Quickshell lockscreen remain unchanged.
2. **X11 identity:** verify the RXB session reports X11 and i3, not a Wayland compositor.
3. **Display stability:** verify each connected monitor has the expected mode, scale and arrangement. Test hotplug only after a recovery path is available.
4. **Rendering:** inspect panels, popups, launcher, sidebar, overview, wallpaper, notifications and tray. Check for corruption, flicker, black windows and focus/stacking errors.
5. **Input:** verify keyboard focus, pointer interaction, key repeat, mouse buttons and focus recovery after dismissing popups.
6. **Window management:** test tiling, floating, focus, workspace changes, moving windows and application startup.
7. **Shell lifecycle:** open/close surfaces repeatedly, log out cleanly, and verify the original BSPWM session remains unaffected.
8. **Lock security:** CI has validated real XSecureLock/i3lock PAM authentication, wrong-password behavior, deny-all PAM and process cleanup in Xephyr. On the physical PC, validate keyboard/pointer grabs, VT switching, multi-monitor coverage and recovery after locker failure only after a working TTY path is confirmed. Never treat a fullscreen QML surface as a secure lock.
9. **Power safety:** confirm suspend/hibernate are refused on X11. Do not enable a sleep handoff until a separate secure lock-before-suspend protocol and crash/resume tests pass.
10. **Performance:** measure idle and active CPU/GPU/memory use, animation smoothness and stability over an extended session on the GT 740 / NVIDIA 470 / Picom stack.
11. **Rollback:** in a disposable host-equivalent environment, verify removal only removes packages recorded as RXB-owned and leaves pre-existing packages and protected desktop configuration untouched.

## Acceptance record

For every item, record the date, hardware/software profile, result, evidence path and reviewer. Keep these evidence levels separate:

- source inspected
- adapter implemented
- build passed
- unit/regression tests passed
- Xephyr/Xvfb passed
- target hardware passed
- owner confirmed

A report from the read-only collector is inventory evidence only. It does not prove visual quality, input grabs, PAM policy, lock security, service behavior or release readiness.

## Additional RXB X11 release gates

- The automatic idle/auto-lock controls are intentionally hidden on X11. Test the manual RXB lock wrapper only; suspend, hibernate and automatic suspend remain disabled until physical lock, VT-switching and multi-monitor acceptance is complete.
- The RXB session wrapper must refuse a second session while a previous session still owns a live i3 socket. After a simulated wrapper SIGKILL and removal of the old socket, the next login must stop stale per-session services, terminate the stale RXB-owned xcompmgr process and remove the old EnvironmentFile/runtime config.
- The install transaction test must install one real local package into its disposable pacman root, simulate SIGKILL during the local package transaction, and prove the remover removes that partial package using the pre-recorded ownership manifest.
- Ryoku Hub, Store and app-installer launchers must be visible only in the Ryoku desktop session. Generic utilities and the user's BSPWM launchers remain unchanged.
- No GTK renderer is forced. The GT740 with NVIDIA 470.256.02 has not yet passed physical RXB hardware acceptance; do not treat GitHub Actions/Xvfb success as hardware validation.
