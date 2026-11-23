# Pinned Ryoku QML / Wayland API audit (in progress)

Source reviewed: upstream Ryoku commit `0bf11741b22f69f22ad2733025671c7d0a5e1a47`.

The audit now has two reproducible CI reports: a whole-subtree source inventory and a static candidate dependency graph rooted at the main shell entrypoint. The earlier GitHub code-search census below is retained as historical reconnaissance only; its 100-result cap is not a complete file count. Neither static report proves runtime activation or full X11 compatibility. Optional profiles, dynamic Loader paths, JavaScript-created components and plugin-provided components still require runtime tracing and interaction tests.

## Search census

| Token / API | Search hits returned | RXB interpretation |
|---|---:|---|
| `WlrLayershell` | 100 (search cap) | Many panels, popups, overlays and optional surfaces use layer-shell properties |
| `Quickshell.Wayland` | 100 (search cap) | Broad import footprint; each imported file still needs use-site and activation analysis |
| `WlSessionLock` | 7 | Concentrated in qylock lockscreen implementation and docs/patches |
| `ScreencopyView` | 12 | Overview, dock previews, launcher and capture surfaces |
| `ToplevelManager` | 9 | Window lists, taskbar, app library and dock preview models |
| `Quickshell.Hyprland` | 16 | Mostly compositor-specific bridge modules and compatibility code |
| `Quickshell.I3` | 0 | The X11/i3 QML bridge is new; there is no upstream I3 QML integration in this pin |

## RXB configuration isolation

The upstream materializer treats its normal `XDG_CONFIG_HOME/quickshell` tree as Ryoku-owned and also seeds other user configuration files. That behavior is unsafe when Ryoku is added beside an existing desktop. RXB therefore sets a non-standard `RYOKU_CONFIG_HOME` at `~/.config/ryoku-x11/ryoku-config` and `RYOKU_QUICKSHELL_CONFIG_HOME` below it. The overlay routes Ryoku's materializer, Go settings stores, and QML config reads to that isolated root while leaving standard `XDG_CONFIG_HOME` unchanged for applications.

The QML source rewrite prefers `Quickshell.env("RYOKU_CONFIG_HOME")` before `XDG_CONFIG_HOME`. The `ryoku-shell` daemon uses the isolated Quickshell path for both import discovery and `qs -p` selection. The materializer rejects a shared Quickshell path and symlinked RXB QML root. Session startup tests verify that existing `~/.config/quickshell` files and user i3 config survive, that RXB files land only under `~/.config/ryoku-x11`, and that session-scoped services receive the same environment.

External application theme writes are gated while `RYOKU_X11_BRIDGE=1`; app-wide GTK/Qt/terminal theming remains unavailable until a safe per-session adapter exists. This intentionally trades some visual integration for preservation of the user's existing application configuration.

## Automated runtime evidence

On 2026-11-22, CI built the pinned package set, installed it in a disposable Arch container, materialized the original shell, started the real `ryoku-shell daemon` under Xvfb+i3 with Quickshell 0.3.2, verified daemon IPC ping/status and a healthy QML shell process/log, then cleanly quit and removed the packages. This is a **basic startup/QML-load smoke**, not visual or interaction acceptance for every panel, popup, tray, notification, wallpaper, capture, lock or monitor feature. The session lifecycle test validates the wrapper and configuration isolation with a mocked systemd command; the disposable install transaction additionally verifies installed unit paths and systemd unit syntax.

## Feature classifications

### X11 panel and popup surfaces

Representative files:
- `ryoku/shell/quickshell/shell/Ui/OverlayWindow.qml`
- `ryoku/shell/quickshell/shell/modules/bar/Frame.qml`
- `ryoku/shell/quickshell/shell/modules/sidebar/Sidebar.qml`
- `ryoku/shell/quickshell/shell/modules/osd/OsdWindow.qml`
- `ryoku/shell/quickshell/shell/modules/overview/OverviewSurface.qml`
- `ryoku/shell/quickshell/shell/modules/capture/RegionOverlay.qml`
- `ryoku/shell/quickshell/shell/modules/dock/DockSurface.qml`
- `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/VariantRoot.qml`

RXB converts supported `WlrLayershell.layer` semantics to X11 `PanelWindow.aboveWindows`, converts keyboard-focus modes to the X11 `focusable` property, and removes the Wayland namespace property. `WlrLayer.Top/Overlay` map to above-windows; `Bottom/Background` map below. Dynamic expressions are translated conservatively and fail the overlay if an unknown enum remains.

This is only a source transformation. X11 stacking, struts, focus, popups, dismissal, transient windows and multi-monitor behavior still require runtime testing.

### Window lists and focus

Representative files:
- `ryoku/ui/Singletons/Wm.qml`
- `ryoku/shell/quickshell/inir/services/TaskbarApps.qml`
- `ryoku/shell/quickshell/stage/services/TaskbarApps.qml`
- `ryoku/shell/quickshell/shell/modules/dock/ii/services/TaskbarApps.qml`
- `ryoku/shell/quickshell/shell/modules/dock/ii/services/DockLivePreviewService.qml`
- `ryoku/shell/quickshell/shell/modules/bar/barstyles/nomarchy/services/AppLibrary.qml`

The overlay replaces the central Wayland window model with `Quickshell.I3` for workspaces/monitors and provider-backed i3 tree records for windows. Selected taskbar/app-library paths are adapted to `Wm.toplevels`. The i3 provider emits a focused-window sentinel but does not advertise authoritative focus history. X11 capture handles are explicitly null; a Wayland `Toplevel` is never fabricated. The QML adapter unwraps optional handles so the provider's wrapper objects cannot be mistaken for real Wayland capture objects. The provider sets `focusOrder=0` only for the focused window and `1` for other windows; it does not advertise focus history.

Some optional style/launcher paths still contain direct Wayland imports or `ToplevelManager` assumptions and need separate path-by-path review before those styles are enabled.

### Capture and previews

Representative files:
- `ryoku/shell/quickshell/shell/modules/overview/WorkspaceCell.qml`
- `ryoku/shell/quickshell/shell/modules/overview/Overview.qml`
- `ryoku/shell/quickshell/shell/modules/dock/ii/DockLivePreviewWidget.qml`
- `ryoku/shell/quickshell/shell/modules/dock/ii/widgets/DockPreviewPopup.qml`
- `ryoku/shell/quickshell/shell/modules/bar/popouts/DockPreviewPopout.qml`
- `ryoku/shell/quickshell/ryoshot/Overlay.qml`

The i3 provider does **not** advertise persistent Wayland screen capture. Dock live previews are therefore capability-gated off; capture widgets receive null Wayland handles. The screenshot command path has an X11 `maim` adapter, but this is not a replacement for persistent per-window capture, overview live previews, or recording. Those remain incomplete.

### Session lock

The upstream qylock path uses `WlSessionLock` / `WlSessionLockSurface` and compositor-enforced lock coverage. RXB excludes the qylock bundle from the X11 package. The i3 lock binding uses a real external locker: XSecureLock when installed, otherwise i3lock. The wrapper forces absolute X11/PAM helper paths and sanitizes inherited XSECURELOCK overrides. A disposable Xephyr acceptance test has passed with real XSecureLock and i3lock binaries and a temporary account using a real pam_unix password. This verifies the PAM authentication path in the isolated test environment, not the owner's host PAM policy, physical VT/input-grab behavior, multi-monitor coverage or crash recovery. Lock-before-suspend remains disabled.

### Hyprland-only bridges

Representative files:
- `ryoku/wm/hyprland/qml/FocusGrabBridge.qml`
- `ryoku/wm/hyprland/qml/GlobalShortcutBridge.qml`
- `ryoku/wm/hyprland/qml/WorkspaceSlideBridge.qml`

These remain compositor-specific and are not reused by the i3 session. They are gated or unavailable rather than emulated.

### Ryogami picker / wallpaper daemon

The Ryogami picker contains Wayland layer-shell usage. RXB installs a dedicated `ryogami-x11.service` linked only to `ryoku-x11-session.target`; the original upstream `ryogami.service` and `ryoku-session.target` remain untouched. The X11 service receives the session-scoped EnvironmentFile and clears inherited Wayland/Sway variables. The Go daemon is compositor-neutral; the picker QML's WlrLayershell properties are transformed by the common X11 panel adapter. The daemon is included in the basic full-shell smoke, but picker interaction, wallpaper changes and display behavior still require runtime validation under i3.

## Still required for Phase 0/3 acceptance

- Exhaustively enumerate QML files under the active default shell profile and all imported modules; distinguish active from optional themes/apps.
- For every `Quickshell.Wayland` import, classify actual API uses, not only the import line.
- Audit every remaining `WlrLayershell`, `ScreencopyView`, `ToplevelManager`, `WlSessionLock`, Wayland focus and portal use.
- [x] Basic transformed-shell daemon/QML-load smoke passed against Quickshell 0.3.2 under isolated i3/Xvfb; this does not constitute feature acceptance.
- Exercise panels, bars, struts, popups, tray, notifications, overview, wallpaper, capture, lock and multi-monitor behavior separately.
- Record source inspected, adapter implemented, build passed, unit passed, Xvfb/Xephyr passed, hardware passed and owner confirmed as separate evidence fields.

Do not treat the search census or successful source rewrite as runtime compatibility evidence.

### Hub and companion surfaces

The pinned Hub QML tree contains `Quickshell.Wayland` imports in `pages/InputPage.qml` and `pages/KeybindsPage.qml`, but the inspected files do not reference Wayland types or attached properties beyond those import lines. These are import-only residues, not evidence of a live Wayland dependency.

The Ryogami wallpaper picker uses `WlrLayershell.layer`, `namespace` and `keyboardFocus` on its picker window. The common overlay maps the layer and keyboard-focus expressions to X11 `PanelWindow` properties and removes the Wayland-only namespace. The source conversion is covered by overlay checks; picker focus, dismissal and wallpaper interaction still require runtime acceptance.

The RyoStore and Ryovm QML roots are included in the source inventory so optional companion applications are not silently omitted from future audits. Their import census is not a substitute for testing those applications under the RXB session.

## Reproducible CI source inventory

RXB now includes `scripts/audit-rxb-qml.py`. After applying the overlay to the pinned upstream checkout, CI inventories every QML file under the main shell, Hub, picker and companion-app source roots:

- `ryoku/shell/quickshell/shell` — the main shell tree, including optional styles and modules.
- `ryoku/hub/quickshell` — the Hub and its settings/control pages.
- `ryoku/shell/ryogami/picker/qml` — the wallpaper picker UI.
- `ryoku/shell/quickshell/keys` — the key-hint/Kit application.
- `ryoku/shell/quickshell/keys-hint` — the lightweight key-hint overlay.
- `ryoku/shell/quickshell/ryoshot` — the screenshot/region-selection application.
- `ryoku/shell/quickshell/reload-cover` and `ryopin` — reload and pin helper surfaces.
- `ryoku/apps/ryostore/quickshell` and `ryovm/quickshell` — companion apps shipped in the upstream tree.

The report counts and lists source occurrences of `Quickshell.Wayland`, `WlrLayershell`, `ScreencopyView`, `ToplevelManager`, `WlSessionLock`, `Quickshell.Hyprland`, `Quickshell.Niri` and `Quickshell.I3`. CI uploads the machine-readable JSON as the `rxb-qml-x11-inventory` artifact for each integration run.

This is a reproducible **whole-subtree source census**, not an active-profile dependency graph: a file can belong to an optional bar style or helper surface that is not loaded in the user's current profile. The next audit step remains resolving the default shell's transitive QML imports and classifying every reachable Wayland API use by actual runtime path. The report must not be used to claim that the default profile is fully audited or that an API occurrence is already adapted.


## Active-shell dependency candidate graph

A second audit, `scripts/audit-rxb-qml-graph.py`, now starts at the pinned shell entrypoint `ryoku/shell/quickshell/shell/shell.qml`. It follows explicit quoted directory imports, QML module imports backed by `qmldir`, and statically visible QML component object declarations. The scan root is the complete `ryoku/shell/quickshell` tree so shared stage modules outside the shell subdirectory can be included. It records reachable and unreachable QML files, dependency edges, API occurrences among reachable files, unresolved local imports and files using dynamic Loader/source constructs.

CI publishes this report as `rxb-active-shell-qml-graph` separately from the whole-subtree inventory. It is a **static candidate graph**, not a claim of complete runtime reachability: dynamic Loader paths, JavaScript-created components, plugin-provided components and profile-dependent branches can still load files not found by static object references. The report's limitations are part of the artifact; runtime tracing and profile-specific interactive tests remain mandatory.
