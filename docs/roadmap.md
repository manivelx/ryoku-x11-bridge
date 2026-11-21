# RXB roadmap and acceptance gates

## Phase 0 — Audit and architecture
[x] Repository access verified and initialized
[x] Upstream 1.1.0 commit pinned
[x] Shared provider seam inspected
[x] Initial compositor/provider comparison
[x] Initial X11 compatibility matrix and risk register
[x] Go provider package compiles, vets and passes race-enabled unit tests in CI
[x] Pinned upstream Go package tests and RXB overlay unit tests pass in CI
[x] Non-destructive package overlay checks pass in CI
[x] Disposable Arch package build completes in CI
[ ] Package safety test passes against built package artifacts (metadata selector fix committed; rerun pending)
[ ] Exhaustive QML import and Wayland API usage inventory
[ ] Installed Quickshell 0.3.2 smoke tests with actual QML loading and interaction
[ ] Original shell + i3 provider integration in isolated session
[ ] Architecture review and acceptance

Status: the Go/provider and overlay CI checks are green; the package build completes but its post-build safety assertion had a filename-matching defect, now corrected to inspect embedded package metadata. QML/Quickshell runtime compatibility and secure-lock behavior remain unproven.

## Phase 1 — i3 provider foundation
Implement upstream provider contract, i3 IPC framing, request/event clients, normalized outputs/workspaces/windows, semantic actions, conservative capabilities, watch resync, config preview/apply, defaults, schema and keybinds.
Acceptance: Go build, vet, unit tests, upstream JSON fixture compatibility and Xephyr i3 tests. No host configuration changes.

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
Isolated session entry, dependencies, installer, uninstaller, backups and rollback.
Acceptance: disposable-root tests prove protected host files remain unchanged.

## Phase 9 — Release validation
Automated Go/QML/build tests, protocol tests, Xephyr/Xvfb, visual tests, real hardware, install/uninstall and docs.
Acceptance: all evidence recorded separately; hardware and user confirmation cannot be inferred.

## Validation discipline
On every failure: capture logs, diagnose root cause, fix, rerun failing test and regressions, document result. Do not call build success runtime success. Hardware tests require user-run collection scripts. No host install without explicit approval.
