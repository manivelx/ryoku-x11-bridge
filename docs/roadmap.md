# RXB roadmap and acceptance gates

## Phase 0 — Audit and architecture
[x] Repository access verified and initialized
[x] Upstream 1.1.0 commit pinned
[x] Shared provider seam inspected
[x] Initial compositor/provider comparison
[x] Initial X11 compatibility matrix and risk register
[x] Reproducible CI source census covers main shell, key-hint and screenshot QML trees; JSON inventory artifact is uploaded per integration run
[~] Static active-shell QML dependency candidate graph now runs in CI; dynamic/profile reachability and exhaustive API-use classification remain open
[ ] Go service and runtime dependency inventory
[x] Quickshell 0.3.2 API and basic full-shell daemon/QML-load smoke passed in disposable Xvfb+i3 CI
[ ] Architecture review and acceptance

Status: automated provider, overlay, upstream Go, package, installer/rollback, session lifecycle and Xvfb+i3 shell/lock smoke gates are being validated on the current head. Full feature interaction, real PAM security and target-hardware acceptance remain separate gates.

## Phase 1 — i3 provider foundation
[~] Provider CLI and conservative capability manifest
[~] i3 IPC framing, state queries, normalized outputs/workspaces/windows
[~] Semantic window/workspace actions
[~] Watch: full initial state + ready, 40 ms event coalescing, changed-frame emission, reconnect/resync
[x] Sway socket fallback removed; only I3SOCK or sanitized i3 socket discovery is accepted
[x] Settings apply remains fail-closed; no placeholder generated config is written
[~] Bind legend exposes all 105 pinned upstream Ryoku actions plus live i3 custom binds; semantically compatible actions are generated from the neutral store, rebinds/disabled/custom precedence is resolved, and untranslated actions remain explicitly unhonored
[x] Provider CI at Go 1.22: gofmt, vet, race tests, build passed
[x] Quickshell 0.3.2 Quickshell.I3 + X11 PanelWindow smoke test passed in disposable Xvfb CI
[x] Full upstream shell daemon runtime smoke passed under Xvfb + i3: materialize, daemon IPC ping/status, QML shell process/log and clean quit; interactive/hardware acceptance remains open

Acceptance: Go build, vet, unit tests, upstream JSON fixture compatibility and Xephyr/Xvfb i3 tests. No host configuration changes.

## Phase 2 — Go daemon integration
Integrate with original Ryoku consumers; verify provider discovery, session detection, caps, state frames, actions, settings and error handling.
Acceptance: original Go daemon recognizes provider in isolated session.

## Phase 3 — Quickshell X11 integration
Load original QML in Quickshell 0.3.2; adapt Wayland-only surfaces, window state, focus, keyboard and monitor behavior.
Acceptance: QML load/lint and interaction tests in Xephyr, then hardware.

## Phase 4 — Shell experience
Panels, wallpaper, dock, widgets, settings, overview, task list, previews, notifications and interactions.
Acceptance: visual and interaction evidence for every surface; unsupported capabilities gated.

## Phase 5 — Desktop services
Audio, media, Bluetooth, networking, power, tray, clipboard and session controls.
Acceptance: real DBus/PipeWire/BlueZ/UPower integration tests.

## Phase 6 — Secure lock and display management
[x] X11 lock action dispatches to XSecureLock when available, otherwise i3lock; no fullscreen QML surface is treated as a secure lock.
[x] Lock-state detection is scoped to a live i3lock/XSecureLock process on the current X display; repeated requests are idempotent.
[x] Suspend, hibernate and automatic suspend are disabled/fail-closed on X11; all known shell-owned power entry points route through the refusal wrapper or the Go host guard.
[~] Real PAM authentication, keyboard/pointer grabs, VT switching, multi-monitor coverage, crash/recovery, output management, capture and recording remain unaccepted.
Acceptance: complete the real X11 security checklist before enabling any sleep handoff.

## Phase 7 — Rendering/performance
QtQuick, NVIDIA 470, Picom, animations, transparency, effects, resource use and stability.
Acceptance: repeatable frame/resource measurements on target hardware.

## Phase 8 — Packaging and installer
[x] Non-installing package build pipeline and X11 session payload passed in Arch CI
[x] Package safety checks protect SDDM, Orbital, Quickshell lockscreen, boot and GPU integration
[~] Disposable Arch package install/upgrade/rejected-transaction/rollback/removal is exercised through the same RXB installer and ownership-manifest removal scripts shipped in the bundle; current-head validation pending, host rollback remains separate
Acceptance: package transaction/removal passes in disposable Arch; session tests prove shared XDG and Quickshell config are not overwritten. Host dependency resolution and actual login-session behavior remain target-machine checks.

## Phase 9 — Release validation
Automated Go/QML/build tests, protocol tests, Xephyr/Xvfb, visual tests, real hardware, install/uninstall and docs.
Acceptance: all evidence recorded separately; hardware and user confirmation cannot be inferred.

## Validation discipline
CI validates the current branch head: a newer push intentionally cancels superseded in-progress runs to avoid wasting the disposable Arch build slot. Only a completed run for the current head is release evidence. On every failure: capture logs, diagnose root cause, fix, rerun failing test and regressions, document result. Do not call build success runtime success. Hardware tests require user-run collection scripts. No host install without explicit approval.

## Evidence ledger

Evidence is deliberately separate. A checked implementation item does not imply a successful build or runtime test.

| Work item | Source inspected | Implemented | Build passed | Unit passed | Xvfb/Xephyr passed | Target hardware passed | Owner confirmed |
|---|---|---|---|---|---|---|---|
| i3 IPC provider | Yes | Yes, initial | Yes | Yes | Pending | No | No |
| Watch debounce/incremental frames | Yes, upstream frame contract | Yes | Yes | Yes | Pending | No | No |
| Quickshell I3/PanelWindow + full shell daemon smoke | Quickshell 0.3.2 API reviewed; static active-shell QML graph artifact added | Full-shell Xvfb/i3 daemon harness; static dependency candidate graph | Yes | Yes, Xvfb CI | Yes, smoke only | No | No |
| X11 lock wrapper | XSecureLock/i3lock PAM process paths and display identity | Yes, lock dispatch/state/idempotency and suspend fail-closed guard | Pending current-head Arch run | Yes, wrapper + Go regression tests | Xvfb lock process smoke pending current-head Arch run | No | No |
| Settings/keybind translation | Pinned 105-action catalogue, neutral desktop store, rebind/disabled/custom precedence and i3 GET_CONFIG contract | Partial: semantic i3 mappings are generated before session start and on settings apply; unsupported actions and other desktop settings are explicitly reported; settings file is never overwritten | Pending current CI | Pending current CI | Pending current Xvfb integration | No | No |
| RXB systemd service isolation | Dedicated target and X11-only units reviewed | Session EnvironmentFile, graphical-session binding and no upstream unit drop-ins | Yes | Systemd unit verification + lifecycle tests | No, unit/lifecycle smoke only | No | No |
| Ryogami wallpaper service | Go daemon and picker entry inspected; full QML use-site audit pending | Dedicated RXB X11 unit + isolated config root | Yes, package CI | Unit/overlay CI | Daemon included in basic shell smoke; picker interaction pending | No | No |
| User config isolation | Materializer and QML config paths inspected | RYOKU_CONFIG_HOME + separate Quickshell root; app theme writes gated | Pending | Pending | Pending | No | No |
| NVIDIA GT 740 / 470 | Hardware constraints recorded | No hardware changes | N/A | N/A | No | No | No |

