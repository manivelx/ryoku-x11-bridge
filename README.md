# RXB — Ryoku X11 Bridge

RXB is an X11/i3 integration layer for the **original Ryoku desktop**. It keeps Ryoku's shell and visual language as the target and replaces the Wayland compositor-facing boundary with an i3 IPC provider and X11-specific surface adapters.

RXB is not MRX-Desktop, not an end-4 port, and not a hybrid desktop. The goal is a separate Ryoku X11 session that can coexist with other installed sessions.

## Architecture

```text
                  Original Ryoku shell / Hub / CLI
                              |
                       ryoku-wm contract
                              |
                       ryoku-wm-i3
                              |
                 i3 IPC socket (X11 session)
                              |
                       i3 window manager

       Quickshell 0.3.2 / QtQuick on X11
                  |                    |
          Quickshell.I3          X11 PanelWindow
          workspaces/outputs     panels, popups, overlays

       X11 service adapters: capture, clipboard, lock
       RXB-owned config: ~/.config/ryoku-x11/
```

The Go provider speaks the upstream subprocess contract (`caps`, `state`, `watch`, `act`, `apply`, `defaults`, `schema`, `binds`, `outputs`, `session`, and `environment`). It uses i3's framed Unix-socket IPC, separate state queries, a debounced event subscription, and opaque i3 container IDs.

## Safety boundary

The X11 package is intentionally separate from the existing desktop configuration. It must not replace or rewrite:
- BSPWM configuration or sxhkd bindings.
- SDDM configuration or the Ryoku Orbital theme.
- The existing Quickshell lockscreen.
- Picom configuration.
- NVIDIA drivers, kernel, GRUB/EFI, EDID settings, or system power policies.
- The separate MRX-Desktop repository.

The package build script uses a detached worktree of the pinned upstream source. It builds packages but does not install them. Host installation is not an accepted validation method; use a disposable Arch/CachyOS VM or root first.

## Current implementation status

| Area | Current evidence/status |
|---|---|
| Upstream pin and compatibility overlay | Implemented; pinned by `UPSTREAM_PIN` |
| RXB i3 provider | IPC state, semantic actions and conservative capability report implemented; Go 1.22 CI build/vet/race tests passed |
| i3 watch | Initial full sync + ready frame; debounced incremental changed frames; Go race/unit tests passed |
| Provider settings apply | Deliberately fail-closed; no generated file is written yet |
| Effective bind legend | Deliberately empty until the upstream catalogue/rebind resolver is ported |
| X11 session config | RXB-owned seed under `ryoku-x11`; no existing i3/BSPWM config overwritten |
| X11 lock command | Prefers XSecureLock; falls back to i3lock; not yet security-audited |
| Ryogami wallpaper daemon | Starts only through the RXB session target with a session-scoped environment; picker/wallpaper runtime still unverified |
| Quickshell X11 adapters | Source overlay in progress; full original shell runtime is not proven |
| Quickshell 0.3.2 / i3 smoke test | Xvfb smoke harness added; current package/runtime CI result pending; target machine remains untested |
| GT 740 / NVIDIA 470 | No RXB hardware validation yet |
| Install/uninstall/rollback | Not release-ready; disposable-root validation remains open |

## Build

See [docs/build.md](docs/build.md) for prerequisites, pinned source checkout, package build, and safe package inspection.

Quick outline:

```bash
git clone https://github.com/Ryoku-dev/ryoku.git ryoku
git clone https://github.com/manivelx/ryoku-x11-bridge.git ryoku-x11-bridge

cd ryoku
git checkout "$(tr -d '[:space:]' < ../ryoku-x11-bridge/UPSTREAM_PIN)"

cd ../ryoku-x11-bridge
bash scripts/build-rxb-packages.sh ../ryoku
```

The package version tracks the pinned upstream Ryoku `VERSION`, because the i3 package depends on matching Ryoku packages. The provider's own version is maintained separately in `RXB_VERSION` and injected into the binary at link time.

The RXB provider declares Go 1.22 as its module minimum and is CI-tested against Go 1.22. Upstream integration uses Go 1.26.5 because the pinned Ryoku shell/Hub modules declare a Go 1.26 toolchain. These versions are intentionally different.

**Do not install the generated packages on the daily-use desktop.** Inspect package contents and validate installation/uninstallation in a disposable Arch/CachyOS environment first.

## Known limitations and gates

- Settings translation is not implemented. `apply` reports unhonored settings and writes nothing, including in preview mode.
- The bind legend is not yet connected to the upstream bind catalogue/rebind resolver; it returns an empty list rather than fabricated entries.
- Window rules, input settings, appearance settings, and live output management are not translated.
- Some Wayland-only capture, foreign-toplevel, session-lock, and compositor-specific services remain gated or require X11 replacements.
- XSecureLock/i3lock selection is tested as a wrapper only. PAM, focus/input grabs, multi-monitor behavior, failure handling, crash recovery, and lock-before-suspend require separate security testing. Lock-before-suspend remains disabled.
- The full original Quickshell shell still needs runtime validation: panel stacking/struts, popup placement, tray, wallpaper, capture, previews, notifications, and multi-monitor behavior.
- QtQuick rendering, Picom interactions, performance and stability on the GT 740 / NVIDIA 470 are unverified.
- A CI/Xvfb pass is not evidence of target-hardware behavior.

## Licensing

The pinned upstream Ryoku source declares GNU GPL version 3. RXB contains original bridge code and an overlay that modifies upstream source during packaging. The final RXB-specific licensing scope and repository-level license declaration still require the project owner's confirmation. Third-party QML, themes, fonts and assets retain their own license obligations. Do not treat the PKGBUILD license metadata as a substitute for that review.

## Roadmap and evidence

See [docs/roadmap.md](docs/roadmap.md), [docs/compatibility-matrix.md](docs/compatibility-matrix.md), [docs/qml-x11-audit.md](docs/qml-x11-audit.md), and [docs/risk-register.md](docs/risk-register.md). Track these separately for every feature: source inspected, implemented, build passed, unit tests passed, Xephyr/Xvfb passed, target hardware passed, and user confirmed.

No host installation or hardware validation is claimed until the corresponding evidence exists.
