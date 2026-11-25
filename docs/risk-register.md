# RXB risk register

| ID | Risk | Severity | Mitigation / exit condition |
|---|---|---:|---|
| R1 | X11 lacks Wayland session-lock security semantics | Critical | The manual X11 lock wrapper uses absolute XSecureLock/i3lock helpers, PAM and display-scoped process detection. Disposable Xephyr acceptance passed; automatic idle/auto-lock controls remain hidden and suspend/hibernate remain fail-closed until owner-host grabs, VT switching, multi-monitor and crash/recovery acceptance pass. |
| R2 | Broad Wayland-only QML dependencies | High | Exhaustive import/use inventory; adapt narrowly and preserve original UI |
| R3 | Quickshell X11 surfaces differ from layer-shell | High | Test struts, stacking, focus, popups and hotplug |
| R4 | Go consumers expect compositor state | High | i3 tree/event adapter matching exact upstream frame contract |
| R5 | i3 IPC event/snapshot races | High | Separate event/request sockets, frame validation, debounce and resync |
| R6 | i3 lacks some compositor capabilities | High | Conservative manifest; hide unsupported UI; no fake success |
| R7 | Installer overwrites existing desktop config | Critical | Dedicated RYOKU_CONFIG_HOME and Quickshell tree under RXB config; preserve standard XDG and i3 user config; test package removal |
| R8 | NVIDIA 470 + QtQuick + Picom rendering issues | High | Keep GTK renderer defaults; do not force GSK_RENDERER=gl; no driver/kernel changes; physical GT740 acceptance remains required |
| R9 | X11 capture/preview performance or coordinate errors | High | Dedicated backend, 1080p benchmark and multi-monitor tests |
| R10 | Display backend conflicts with EDID/monitor setup | High | Query-only first; explicit opt-in for apply; no boot arg changes |
| R11 | Quickshell API drift from installed 0.3.2 | Medium | Pin to installed docs/runtime; compile QML against actual version |
| R12 | Upstream moving branch breaks assumptions | Medium | Pin commits and re-audit every update |
| R13 | GPL-3.0 and third-party license obligations | High | Preserve notices; audit asset/plugin/font licenses |
| R14 | Host install disrupts BSPWM, SDDM, Orbital or lockscreen | Critical | Disposable Arch package transaction/removal, package path assertions, isolated user config root and session lifecycle test; explicit host-install approval |
| R15 | GT 740 has no iGPU fallback | High | Keep existing working NVIDIA stack and recovery desktop untouched |
| R16 | Declared RXB licensing may not cover every upstream-derived component, asset, font or bundled dependency | High | RXB provider/session code declares GPL-3.0-only and repository LICENSE/NOTICE files are present; verify the scope of the declaration, upstream GPL obligations, bundled assets and third-party notices before release; owner confirmation remains required |
| R17 | User service enablement or Wayland-only services leak into non-RXB sessions. | High | Use dedicated RXB target and template services; never drop in to upstream Wayland units; do not enable globally or mutate the shared user-manager environment; use per-logind-session EnvironmentFiles, refuse another active/online graphical session for the same UID, and clean stale instances after wrapper crashes. |
| R18 | Upstream host CLI and Hub backends can mutate host GPU, package, user, network, authentication, keymap, time, service, initramfs and greeter state. | Critical | Apply a default-deny host-command allowlist; block Hub GPU, SDDM/lockscreen, Rashin and phone-service privileged actions before pkexec; disable CPU/battery/idle policy writes; preserve saved Wi-Fi profiles during fallback joins; keep read-only queries and explicit safe power actions only. |
| R19 | GTK renderer and NVIDIA 470/GT740 compatibility are not physically validated. | High | Do not force GSK_RENDERER=gl or change the NVIDIA driver/kernel; keep GTK defaults and require controlled GT740 hardware acceptance before claiming rendering compatibility. |
| R20 | Ryoku-owned desktop launchers can appear in the preserved BSPWM session. | Medium | Restrict all six RXB-owned launchers (Hub, Store, app installer, video compressor, Ryoport and Ryoku Neovim) to XDG_CURRENT_DESKTOP=Ryoku; leave user-owned BSPWM launchers and configuration untouched. |

Stop ship if secure lock is not proven, capabilities are overstated, protected files change, active session services must be killed, or regression tests fail.

R18 | Upstream host CLI and Hub backends can mutate host GPU, package, user, network, authentication, keymap, time, service, initramfs and greeter state. | Critical | Apply a default-deny host-command allowlist; block privileged Hub backends and hide unsupported controls before they can invoke pkexec; keep read-only queries and explicit safe power actions only. |
R19 | GTK renderer and NVIDIA 470/GT740 compatibility are not physically validated. | High | Do not force GSK_RENDERER=gl or change the NVIDIA driver/kernel; keep GTK defaults and require controlled GT740 hardware acceptance before claiming rendering compatibility. |
R20 | Ryoku-specific desktop launchers can appear in the preserved BSPWM session. | Medium | Restrict Hub, Store and app-installer desktop entries to XDG_CURRENT_DESKTOP=Ryoku; leave generic utilities and BSPWM configuration untouched. |
