# RXB risk register

| ID | Risk | Severity | Mitigation / exit condition |
|---|---|---:|---|
| R1 | X11 lacks Wayland session-lock security semantics | Critical | XSecureLock/i3lock PAM wrapper and display-scoped process detection are implemented; Xvfb startup/idempotency smoke passes. Keep suspend/hibernate/automatic suspend fail-closed. Real PAM authentication, keyboard/pointer grabs, VT switching, multi-monitor coverage and crash/recovery tests remain mandatory before enabling sleep. |
| R2 | Broad Wayland-only QML dependencies | High | Exhaustive import/use inventory; adapt narrowly and preserve original UI |
| R3 | Quickshell X11 surfaces differ from layer-shell | High | Test struts, stacking, focus, popups and hotplug |
| R4 | Go consumers expect compositor state | High | i3 tree/event adapter matching exact upstream frame contract |
| R5 | i3 IPC event/snapshot races | High | Separate event/request sockets, frame validation, debounce and resync |
| R6 | i3 lacks some compositor capabilities | High | Conservative manifest; hide unsupported UI; no fake success |
| R7 | Installer overwrites existing desktop config | Critical | Dedicated RYOKU_CONFIG_HOME and Quickshell tree under RXB config; preserve standard XDG and i3 user config; test package removal |
| R8 | NVIDIA 470 + QtQuick + Picom rendering issues | High | Incremental X11 rendering tests; no driver/kernel changes |
| R9 | X11 capture/preview performance or coordinate errors | High | Dedicated backend, 1080p benchmark and multi-monitor tests |
| R10 | Display backend conflicts with EDID/monitor setup | High | Query-only first; explicit opt-in for apply; no boot arg changes |
| R11 | Quickshell API drift from installed 0.3.2 | Medium | Pin to installed docs/runtime; compile QML against actual version |
| R12 | Upstream moving branch breaks assumptions | Medium | Pin commits and re-audit every update |
| R13 | GPL-3.0 and third-party license obligations | High | Preserve notices; audit asset/plugin/font licenses |
| R14 | Host install disrupts BSPWM, SDDM, Orbital or lockscreen | Critical | Disposable Arch package transaction/removal, package path assertions, isolated user config root and session lifecycle test; explicit host-install approval |
| R15 | GT 740 has no iGPU fallback | High | Keep existing working NVIDIA stack and recovery desktop untouched |
| R16 | Declared RXB licensing may not cover every upstream-derived component, asset, font or bundled dependency | High | RXB provider/session code declares GPL-3.0-only and repository LICENSE/NOTICE files are present; verify the scope of the declaration, upstream GPL obligations, bundled assets and third-party notices before release; owner confirmation remains required |
| R17 | User service enablement or Wayland-only services leak into non-RXB sessions | High | Use dedicated RXB target and service units; never drop in to upstream Wayland units; do not enable globally or mutate the shared user-manager environment; use a session-scoped EnvironmentFile; omit qylock power hooks |

Stop ship if secure lock is not proven, capabilities are overstated, protected files change, active session services must be killed, or regression tests fail.
