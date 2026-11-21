# RXB risk register

| ID | Risk | Severity | Mitigation / exit condition |
|---|---|---:|---|
| R1 | X11 lacks Wayland session-lock security semantics | Critical | Dedicated secure X11 locker + PAM; pass multi-monitor, grab, crash and failure tests |
| R2 | Broad Wayland-only QML dependencies | High | Exhaustive import/use inventory; adapt narrowly and preserve original UI |
| R3 | Quickshell X11 surfaces differ from layer-shell | High | Test struts, stacking, focus, popups and hotplug |
| R4 | Go consumers expect compositor state | High | i3 tree/event adapter matching exact upstream frame contract |
| R5 | i3 IPC event/snapshot races | High | Separate event/request sockets, frame validation, debounce and resync |
| R6 | i3 lacks some compositor capabilities | High | Conservative manifest; hide unsupported UI; no fake success |
| R7 | Installer overwrites existing desktop config | Critical | Isolated RXB config/session and rollback; never modify BSPWM config |
| R8 | NVIDIA 470 + QtQuick + Picom rendering issues | High | Incremental X11 rendering tests; no driver/kernel changes |
| R9 | X11 capture/preview performance or coordinate errors | High | Dedicated backend, 1080p benchmark and multi-monitor tests |
| R10 | Display backend conflicts with EDID/monitor setup | High | Query-only first; explicit opt-in for apply; no boot arg changes |
| R11 | Quickshell API drift from installed 0.3.2 | Medium | Pin to installed docs/runtime; compile QML against actual version |
| R12 | Upstream moving branch breaks assumptions | Medium | Pin commits and re-audit every update |
| R13 | GPL-3.0 and third-party license obligations | High | Preserve notices; audit asset/plugin/font licenses |
| R14 | Host install disrupts BSPWM, SDDM, Orbital or lockscreen | Critical | Disposable-root install tests; backup/rollback; explicit approval |
| R15 | GT 740 has no iGPU fallback | High | Keep existing working NVIDIA stack and recovery desktop untouched |
| R16 | RXB license declaration may not match the combined upstream-derived distribution | High | Owner must confirm RXB original-code licensing; preserve upstream GPL-3.0 and third-party notices; no repository LICENSE is asserted yet |
| R17 | User service enablement or Wayland-only services leak into non-RXB sessions | High | Start shell and Ryogami only through the RXB session target; do not enable globally or mutate the shared user-manager environment; use a session-scoped EnvironmentFile; clear qylock power hooks |

Stop ship if secure lock is not proven, capabilities are overstated, protected files change, active session services must be killed, MRX is modified, or regression tests fail.
