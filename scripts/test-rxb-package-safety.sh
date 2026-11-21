#!/usr/bin/env bash
set -euo pipefail

dist="${1:-dist}"
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || { echo "No Arch package artifacts found in $dist" >&2; exit 1; }

base_pkg=""
variant_pkg=""
for pkg in "${packages[@]}"; do
  pkg_name="$(bsdtar -xOf "$pkg" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p' | head -n1)"
  case "$pkg_name" in
    ryoku-desktop) base_pkg="$pkg" ;;
    ryoku-desktop-i3) variant_pkg="$pkg" ;;
  esac
done
[[ -n "$base_pkg" ]] || { echo "Missing ryoku-desktop base package (pkgname metadata)" >&2; exit 1; }
[[ -n "$variant_pkg" ]] || { echo "Missing ryoku-desktop-i3 package (pkgname metadata)" >&2; exit 1; }

base_list="$(bsdtar -tf "$base_pkg")"
variant_list="$(bsdtar -tf "$variant_pkg")"

for forbidden in \
  'usr/share/ryoku/services.tsv' \
  'usr/share/ryoku/lockscreen/' \
  'usr/share/sddm/' \
  'usr/share/wayland-sessions/' \
  'etc/sddm.conf.d/' \
  'usr/lib/environment.d/99-ryoku-session.conf' \
  'usr/lib/environment.d/98-ryoku-dbus.conf' \
  'usr/lib/systemd/user-environment-generators/60-ryoku-xdg-dirs' \
  'usr/share/nautilus-python/extensions/ryoku-stash-menu.py' \
  'usr/lib/udev/rules.d/90-ryoku-gpu.rules' \
  'usr/lib/udev/rules.d/90-ryoku-backlight.rules' \
  'usr/lib/udev/rules.d/60-ryoku-i2c.rules' \
  'usr/lib/systemd/system/ryoku-greeter-guard.service' \
  'usr/lib/sysusers.d/ryoku-i2c.conf' \
  'etc/modules-load.d/ryoku-i2c.conf' \
  'usr/bin/ryoku-qylock-activate' \
  'usr/bin/ryoku-qylock-lock'; do
  if grep -Fq "$forbidden" <<<"$base_list"; then
    echo "Forbidden host integration in base package: $forbidden" >&2
    exit 1
  fi
done

for required in \
  'usr/lib/systemd/user/ryoku-shell.service' \
  'usr/share/ryoku/config/quickshell/shell/shell.qml'; do
  grep -Fq "$required" <<<"$base_list" || {
    echo "Missing expected Ryoku runtime file in base package: $required" >&2
    exit 1
  }
done

for required in \
  'usr/share/xsessions/ryoku-x11.desktop' \
  'usr/lib/systemd/user/ryoku-shell.service.d/10-rxb-x11.conf' \
  'usr/bin/ryoku-x11-session' \
  'usr/bin/ryoku-x11-session-init' \
  'usr/bin/ryoku-wm-i3' \
  'usr/share/ryoku/config/ryoku-x11/config'; do
  grep -Fq "$required" <<<"$variant_list" || {
    echo "Missing expected RXB i3 integration file: $required" >&2
    exit 1
  }
done

echo "RXB package safety checks passed: no global environment, SDDM, lockscreen, boot, or GPU policy changes."
