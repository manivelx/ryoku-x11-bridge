#!/usr/bin/env bash
# Read-only inventory of the built RXB package set. Prints, per package, the
# metadata that can affect a host (depends/conflicts/replaces/provides/backup,
# install scriptlets) and flags every file outside the RXB-private prefixes.
# It installs nothing and never touches the host.
set -euo pipefail

dist="${1:-dist}"
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
((${#packages[@]} > 0)) || { echo "inventory: no packages in $dist" >&2; exit 1; }

# Prefixes that only RXB/Ryoku use. Anything else is host-visible integration.
private_re='^(usr/share/ryoku/|usr/share/licenses/|usr/share/doc/|usr/lib/systemd/user/|usr/lib/ryoku|usr/lib/ryogami|usr/bin/(ryoku|ryogami|gpk|ryovm|ryostore|ryoshot))'
sensitive_re='^(etc/|boot/|usr/lib/udev/|usr/lib/sysusers|usr/lib/tmpfiles|usr/lib/modules|usr/lib/modprobe|usr/lib/systemd/system|usr/lib/systemd/user-environment|usr/lib/environment\.d|usr/share/libalpm/|usr/share/polkit-1/|usr/share/dbus-1/|usr/share/sddm/|usr/share/wayland-sessions/|usr/share/xsessions/|usr/share/applications/|usr/share/icons/|usr/share/fonts/|usr/share/mime/|usr/share/pacman/|usr/lib/sysctl)'

for pkg in "${packages[@]}"; do
  base="${pkg##*/}"
  echo "################ $base"
  info="$(bsdtar -xOf "$pkg" .PKGINFO)"
  grep -E '^(pkgname|pkgver|depend|optdepend|conflict|replaces|provides|backup) = ' <<<"$info" | sed 's/^/  /'
  if bsdtar -tf "$pkg" | grep -qx '\.INSTALL'; then
    echo "  --- .INSTALL scriptlet:"
    bsdtar -xOf "$pkg" .INSTALL | sed 's/^/    | /'
  else
    echo "  (no install scriptlet)"
  fi
  files="$(bsdtar -tf "$pkg" | grep -v '^\.' | sed 's|^\./||' | grep -v '/$' || true)"
  echo "  files: $(wc -l <<<"$files")"
  echo "  --- files outside RXB/Ryoku-private prefixes:"
  grep -Ev "$private_re" <<<"$files" | sed 's/^/    /' || true
  echo "  --- host-sensitive paths (etc, udev, polkit, pacman hooks, sddm, system units, apps, icons, fonts...):"
  grep -E "$sensitive_re" <<<"$files" | sed 's/^/    /' || true
done
