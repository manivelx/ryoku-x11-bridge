# RXB — Ryoku X11 Bridge

An X11 integration layer for the original Ryoku desktop shell using i3, Quickshell and Xorg.

RXB runs the original Ryoku shell and services in an i3/X11 session through a native i3 window-manager provider and a narrowly scoped X11 compatibility overlay. The upstream Ryoku source remains a separate, pinned, read-only build input.

## Repository state

The repository contains:
- A Go-based `ryoku-wm-i3` provider with i3 IPC state, watch and semantic action support.
- A pinned-upstream overlay for X11-specific shell adaptation.
- Arch package build scripts and a dedicated `ryoku-desktop-i3` package.
- CI checks for provider tests, overlay behavior, package assembly and isolated smoke validation.

## Validation status

CI has previously passed the provider, upstream Go tests and overlay validation. The package-build workflow exposed a package-safety test defect: its artifact discovery relied on filenames rather than package metadata. RXB now identifies the base and i3 packages through their embedded `.PKGINFO` fields. The corrected workflow must pass before package safety is considered validated.

A successful package build is not evidence that the complete shell works on real X11 hardware. Quickshell 0.3.2 runtime behavior, full QML surface compatibility, secure locking, multi-monitor behavior, and the target NVIDIA 470/GT 740 rendering path still require evidence.

## Safety boundaries

- Builds never install packages on the host.
- Development and runtime validation use Xephyr/Xvfb or a disposable Arch/CachyOS environment.
- Existing BSPWM/sxhkd configuration, SDDM and the Ryoku Orbital theme, current Quickshell lockscreen, Picom configuration, NVIDIA driver, kernel and boot files are protected.
- Secure lock and suspend handoff stay unavailable until separately security-tested.
- Upstream Ryoku is used as a pinned, read-only source.

See [docs/build.md](docs/build.md), [docs/architecture.md](docs/architecture.md), [docs/compatibility-matrix.md](docs/compatibility-matrix.md), and [docs/roadmap.md](docs/roadmap.md).
