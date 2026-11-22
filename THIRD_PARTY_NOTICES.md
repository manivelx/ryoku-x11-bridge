# Third-party notices and licensing

RXB's provider and session integration is licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE) and the package metadata). RXB integrates the pinned original Ryoku desktop; it does not relicense upstream or third-party components.

## Pinned upstream

- Repository: [Ryoku](https://github.com/Ryoku-dev/ryoku)
- Revision: `0bf11741b22f69f22ad2733025671c7d0a5e1a47` (see [UPSTREAM_PIN](UPSTREAM_PIN))
- Upstream root license: GNU GPL version 3; the upstream package metadata declares GPL-3.0-or-later for the core desktop.
- The upstream [NOTICE](NOTICE) is preserved verbatim. It records component origins, copyright, license distinctions and additional terms. It is authoritative alongside the component-level files copied from the pinned source tree.

## Notable upstream-derived components

The pinned upstream NOTICE describes the following material and its licensing. This summary does not replace those notices or the full license texts.

| Component | Upstream use | License / required notice |
|---|---|---|
| Omarchy quattro shell | Modified Nomarchy bar style | MIT; preserve its LICENSE and NOTICE |
| Caelestia shell | Ryoku.Blobs rendering and animation portions | GPL-3.0 |
| DankMaterialShell | Portions of display configuration UI | MIT |
| OkShell | Frame-bar layout and Bar Studio workflow | GPL-3.0 |
| iNiR by snowarch | Modified Shima bar style | GPL-3.0 plus additional GPL section 7 terms in the upstream NOTICE |
| Serpantinum | Python bar style and related presentation | AGPL-3.0-or-later; preserve its LICENSE and NOTICE |
| skwd-wall | Ryogami wallpaper picker | GPL-3.0-or-later; preserve its LICENSE and NOTICE |
| Roboto Condensed UI subset | Ryogami picker font | Apache-2.0 |
| Symbols Nerd Font | Ryogami picker symbols | MIT |
| Inter, Montserrat and Rubik | iNiR font assets | SIL Open Font License 1.1; preserve each OFL.txt |

The iNiR attribution required by its section 7 terms is present in the README and in the original Shima/Iris About page:

> Based on iNiR by snowarch (https://github.com/snowarch/inir)

Do not remove or alter the upstream NOTICE, the iNiR LICENSE/NOTICE, component-specific LICENSE/NOTICE files, font OFL texts, or vendored dependency license files.

## Package preservation

The `ryoku-desktop-i3` package installs:

- RXB's LICENSE, NOTICE and this third-party inventory under `/usr/share/licenses/ryoku-desktop-i3` and `/usr/share/doc/ryoku-desktop-i3`.
- Every upstream file named LICENSE, NOTICE, COPYING, OFL.txt, or an explicit `.LICENSE-*.txt` notice, preserving its original relative path under `/usr/share/licenses/ryoku-desktop-i3/upstream/`.

This keeps upstream component notices available on the installed system even when the original upstream package split does not install every source-tree notice.

## External runtime dependencies

Quickshell 0.3.2, Qt 6, i3, Xorg, systemd, PipeWire, BlueZ, NetworkManager, UPower and other Arch/CachyOS runtime dependencies are installed as separate distribution packages; RXB does not vendor or relicense them. Their package metadata and upstream license files remain authoritative. The RXB package build pins the Quickshell compatibility target to 0.3.2.

## Vendored Go dependencies

The pinned upstream tree contains vendored Go modules (including D-Bus, TOML, websocket and `golang.org/x/sys` packages). Their original LICENSE/COPYING files are preserved with the upstream vendor trees and copied into the installed upstream-notices directory. Do not replace them with the RXB project license.

This inventory is based on the pinned upstream source tree and package metadata. It is not legal advice; any new bundled asset, font, plugin, or vendored dependency must add its own notice and license text before release.
