# RXB — Ryoku X11 Bridge

An X11 integration layer for the original Ryoku desktop shell using i3, Quickshell and Xorg.

Initial project documentation and implementation are being developed in this repository.


## Current implementation limits

- The i3 provider currently reports only workspaces, workspace-to-output movement, window/workspace mapping, workspace fullscreen state, window geometry and session exit.
- i3 settings generation and custom keybind translation are not implemented. `apply` fails closed outside dry-run.
- The X11 lock path delegates to XSecureLock; suspend remains fail-closed because the Wayland qylock proof protocol is not portable to X11.
- Quickshell QML adaptation is source-overlay work only. QML loading, panel stacking, capture, wallpaper, tray, service integration and secure-lock behavior still require runtime tests.
- The package skeleton is not a release-ready installer. It must be built in an Arch/CachyOS environment and tested in a disposable root before host installation.
