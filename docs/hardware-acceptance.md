# RXB target-hardware acceptance

This checklist separates automated disposable-environment evidence from acceptance on the owner's actual CachyOS desktop. A successful CI run is not target-hardware approval.

## Safety rules

- Do not run the RXB installer on the daily-use desktop until the release owner explicitly approves that stage.
- Keep the existing BSPWM session, SDDM Orbital theme, Quickshell lockscreen, Picom configuration, NVIDIA driver, kernel, EDID setup and boot configuration unchanged.
- Do not run a lock test that could strand the active session. Perform real lock testing only after recovery access and a second login path are confirmed.
- Do not enable suspend/hibernate handoff. RXB intentionally fails closed for those actions on X11.
- Review the generated report before sharing it. It excludes window titles, process command lines, serial numbers, network addresses and home-directory contents, but still contains hardware/software inventory.

## Read-only evidence collection

From an existing X11 session, run:

```bash
bash scripts/collect-x11-hardware-evidence.sh
```

The script creates `rxb-hardware-evidence/report.txt` with OS/kernel, graphics device and driver, OpenGL renderer, X server, monitor/mode, i3, Picom, Quickshell and relevant package versions. It does not install packages, edit configuration, start/stop services, or invoke the locker.

If the report is being collected after RXB is installed in a disposable test system, the RXB package section also records the installed package versions.

## Manual acceptance sequence

Record each item as pass, fail, or not tested. Attach screenshots/logs only after checking them for personal information.

1. **Session coexistence:** verify the display manager still offers the original BSPWM session and that it starts normally.
2. **X11 identity:** verify the RXB session reports X11 and i3, not a Wayland compositor.
3. **Display stability:** verify each connected monitor has the expected mode, scale and arrangement. Test hotplug only after a recovery path is available.
4. **Rendering:** inspect panels, popups, launcher, sidebar, overview, wallpaper, notifications and tray. Check for corruption, flicker, black windows and focus/stacking errors.
5. **Input:** verify keyboard focus, pointer interaction, key repeat, mouse buttons and focus recovery after dismissing popups.
6. **Window management:** test tiling, floating, focus, workspace changes, moving windows and application startup.
7. **Shell lifecycle:** open/close surfaces repeatedly, log out cleanly, and verify the original BSPWM session remains unaffected.
8. **Lock security:** only in a controlled test session, validate XSecureLock/i3lock PAM authentication, wrong-password behavior, physical keyboard/pointer grabs, VT switching, multi-monitor coverage and recovery after locker failure. Never treat a fullscreen QML surface as a secure lock.
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
