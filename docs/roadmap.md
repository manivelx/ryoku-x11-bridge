# RXB roadmap and acceptance gates

## Phase 0 — Audit and architecture
[x] Repository access verified and initialized
[x] Upstream 1.1.0 commit pinned
[x] Shared provider seam inspected
[x] Initial compositor/provider comparison
[x] Initial X11 compatibility matrix and risk register
[~] Partial QML import and Wayland API inventory recorded in qml-x11-audit.md; exhaustive active-profile inventory remains open
[ ] Go service and runtime dependency inventory
[ ] Installed Quickshell 0.3.2 smoke tests
[ ] Architecture review and acceptance

Status: documentation baseline committed; audit is not yet exhaustive.

## Phase 1 — i3 provider foundation
[~] Provider CLI and conservative capability manifest
[~] i3 IPC framing, state queries, normalized outputs/workspaces/windows
[~] Semantic window/workspace actions
[~] Watch: full initial state + ready, 40 ms event coalescing, changed-frame emission, reconnect/resync
[x] Sway socket fallback removed; only I3SOCK or sanitized i3 socket discovery is accepted
[x] Settings apply remains fail-closed; no placeholder generated config is written
[x] Bind legend returns empty until the upstream catalogue/rebind resolver is ported (no fabricated chords)
[x] Provider CI at Go 1.22: gofmt, vet, race tests, build passed
[x] Quickshell 0.3.2 Quickshell.I3 + X11 PanelWindow smoke test passed in disposable Xvfb CI
[ ] Full upstream shell daemon runtime test in isolated i3 session

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
Secure X11 locker + PAM, lock-before-suspend, output management, capture and recording.
Acceptance: security checklist, multi-monitor, crash and resume tests. Lock remains disabled until accepted.

## Phase 7 — Rendering/performance
QtQuick, NVIDIA 470, Picom, animations, transparency, effects, resource use and stability.
Acceptance: repeatable frame/resource measurements on target hardware.

## Phase 8 — Packaging and installer
[~] Non-installing package build pipeline and X11 session payload
[~] Package safety checks protect SDDM, Orbital, Quickshell lockscreen, boot and GPU integration
[ ] Disposable-root install/uninstall tests, backups and rollback
Acceptance: disposable-root tests prove protected host files remain unchanged.

## Phase 9 — Release validation
Automated Go/QML/build tests, protocol tests, Xephyr/Xvfb, visual tests, real hardware, install/uninstall and docs.
Acceptance: all evidence recorded separately; hardware and user confirmation cannot be inferred.

## Validation discipline
On every failure: capture logs, diagnose root cause, fix, rerun failing test and regressions, document result. Do not call build success runtime success. Hardware tests require user-run collection scripts. No host install without explicit approval.

## Evidence ledger

Evidence is deliberately separate. A checked implementation item does not imply a successful build or runtime test.

| Work item | Source inspected | Implemented | Build passed | Unit passed | Xvfb/Xephyr passed | Target hardware passed | Owner confirmed |
|---|---|---|---|---|---|---|---|
| i3 IPC provider | Yes | Yes, initial | Yes | Yes | Pending | No | No |
| Watch debounce/incremental frames | Yes, upstream frame contract | Yes | Yes | Yes | Pending | No | No |
| Quickshell I3/PanelWindow smoke | Quickshell 0.3.2 API reviewed | Smoke harness | Yes | Yes, Xvfb CI | No | No |
| X11 lock wrapper | XSecureLock/i3lock command paths | Yes, wrapper only | Yes, Arch package CI | Yes, wrapper test | No | No | No |
| Settings/keybind translation | Upstream schema inspected | No; fail-closed/empty | N/A | N/A | No | No | No |
| Ryogami wallpaper service | Go daemon and picker entry inspected; full QML use-site audit pending | RXB-target-only unit + session env adapter | Yes, package CI | Unit/overlay CI | Pending | No | No |
| NVIDIA GT 740 / 470 | Hardware constraints recorded | No hardware changes | N/A | N/A | No | No | No |

