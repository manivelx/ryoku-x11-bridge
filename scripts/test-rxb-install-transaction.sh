#!/usr/bin/env bash
set -euo pipefail

dist="${1:-dist}"
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || { echo "No Arch package artifacts found in $dist" >&2; exit 1; }

declare -a package_names=()
for pkg in "${packages[@]}"; do
  name="$(bsdtar -xOf "$pkg" .PKGINFO | sed -n 's/^pkgname = //p' | head -n1)"
  [[ -n "$name" ]] || { echo "Could not read pkgname from $pkg" >&2; exit 1; }
  package_names+=("$name")
done

cleanup() {
  local status=$?
  trap - EXIT
  local -a present=()
  for name in "${package_names[@]}"; do
    if pacman -Q "$name" >/dev/null 2>&1; then present+=("$name"); fi
  done
  if (("${#present[@]}" > 0)); then
    pacman -Rdd --noconfirm "${present[@]}" >/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT

echo "[install-test] Installing the complete built package set into this disposable Arch container."
pacman -U --noconfirm --nodeps "${packages[@]}"

for name in "${package_names[@]}"; do
  pacman -Q "$name" >/dev/null || { echo "Package was not registered after install: $name" >&2; exit 1; }
done

required_files=(
  /usr/share/xsessions/ryoku-x11.desktop
  /usr/bin/ryoku-x11-session
  /usr/bin/ryoku-x11-session-init
  /usr/bin/ryoku-wm-i3
  /usr/lib/systemd/user/ryoku-shell.service
  /usr/lib/systemd/user/ryoku-shell.service.d/10-rxb-x11.conf
  /usr/lib/systemd/user/ryoku-session.target.wants/ryoku-shell.service
  /usr/lib/systemd/user/ryoku-session.target.wants/ryogami.service
  /usr/share/ryoku/config/quickshell/shell/shell.qml
)
for path in "${required_files[@]}"; do
  [[ -e "$path" ]] || { echo "Expected installed path is missing: $path" >&2; exit 1; }
done

grep -q '^Name=Ryoku (X11 / i3)$' /usr/share/xsessions/ryoku-x11.desktop
grep -q '^Exec=ryoku-x11-session$' /usr/share/xsessions/ryoku-x11.desktop
grep -q '^TryExec=i3$' /usr/share/xsessions/ryoku-x11.desktop

# Package installation must not enable the Ryoku shell globally or start it
# outside the explicit RXB X11 session.
[[ ! -e /usr/lib/systemd/user/default.target.wants/ryoku-shell.service ]]
[[ ! -e /usr/lib/systemd/user/default.target.wants/ryogami.service ]]

echo "[install-test] Removing the complete package set from the disposable container."
pacman -Rdd --noconfirm "${package_names[@]}"
for name in "${package_names[@]}"; do
  if pacman -Q "$name" >/dev/null 2>&1; then
    echo "Package remains registered after removal: $name" >&2
    exit 1
  fi
done
for path in "${required_files[@]}"; do
  [[ ! -e "$path" ]] || { echo "Package-owned path remains after removal: $path" >&2; exit 1; }
done

trap - EXIT
echo "RXB disposable install/uninstall transaction passed."
