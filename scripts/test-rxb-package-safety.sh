#!/usr/bin/env bash
set -euo pipefail

dist="${1:-dist}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -Fq 'systemctl --user enable' "$root/payload/bin/ryoku-x11-session-init"; then
  echo "X11 session init must not persistently enable the shell for non-RXB sessions." >&2
  exit 1
fi
if ! grep -Fq 'env -u SWAYSOCK -u I3SOCK i3 --get-socketpath' "$root/payload/bin/ryoku-x11-session-init"; then
  echo "X11 session init must sanitize Sway's IPC socket environment." >&2
  exit 1
fi
if grep -Eq 'systemctl --user (import-environment|unset-environment)' "$root/payload/bin/ryoku-x11-session-init"; then
  echo "X11 session init must not mutate the shared systemd user-manager environment." >&2
  exit 1
fi
target_file="$root/payload/systemd/ryoku-x11-session.target"
if ! grep -Fq 'BindsTo=graphical-session.target' "$target_file" ||
   ! grep -Fq 'After=graphical-session-pre.target graphical-session.target' "$target_file"; then
  echo "RXB target must be bound to the active graphical session." >&2
  exit 1
fi
for unit in ryoku-shell-x11.service ryogami-x11.service; do
  unit_file="$root/payload/systemd/$unit"
  if ! grep -Fq 'EnvironmentFile=%t/ryoku-x11-session.env' "$unit_file" ||
     ! grep -Fq 'ConditionPathExists=%t/ryoku-x11-session.env' "$unit_file"; then
    echo "$unit must consume the session-scoped RXB environment." >&2
    exit 1
  fi
  if ! grep -Fq 'PartOf=ryoku-x11-session.target' "$unit_file"; then
    echo "$unit must be owned by the dedicated RXB target." >&2
    exit 1
  fi
  if ! grep -Fq 'UnsetEnvironment=WAYLAND_DISPLAY SWAYSOCK' "$unit_file"; then
    echo "$unit must clear inherited Wayland/Sway variables." >&2
    exit 1
  fi
done
if ! grep -Fq 'systemctl --user stop ryoku-x11-session.target' "$root/payload/bin/ryoku-x11-session"; then
  echo "X11 session wrapper must stop its dedicated target on exit." >&2
  exit 1
fi
if ! grep -Fq 'systemctl --user start ryoku-x11-session.target' "$root/payload/bin/ryoku-x11-session-init"; then
  echo "X11 session initializer must start its dedicated target." >&2
  exit 1
fi
if grep -R -q '10-rxb-x11.conf' "$root/payload/systemd"; then
  echo "RXB must not install global drop-ins into upstream Ryoku service units." >&2
  exit 1
fi
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || { echo "No Arch package artifacts found in $dist" >&2; exit 1; }

base_pkg=""
variant_pkg=""
for pkg in "${packages[@]}"; do
  pkg_name="$(bsdtar -xOf "$pkg" .PKGINFO 2>/dev/null | sed -n 's/^pkgname = //p' | head -n1)"
  if [[ "$pkg_name" == *-debug ]]; then
    echo "Split debug packages must not be included in the RXB runtime artifact set: $pkg_name" >&2
    exit 1
  fi
  case "$pkg_name" in
    ryoku-desktop) base_pkg="$pkg" ;;
    ryoku-desktop-i3) variant_pkg="$pkg" ;;
  esac
done
[[ -n "$base_pkg" ]] || { echo "Missing ryoku-desktop base package (PKGINFO metadata)" >&2; exit 1; }
[[ -n "$variant_pkg" ]] || { echo "Missing ryoku-desktop-i3 package (PKGINFO metadata)" >&2; exit 1; }

# The X11 package set must not pull Wayland-only helper stacks or DKMS.
# DKMS can run kernel-module hooks, which is outside the scope of a desktop
# session install and particularly risky on legacy proprietary GPU drivers.
for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  for forbidden in dkms hypridle hyprpicker wtype wl-clipboard wl-clip-persist grim slurp weston xorg-xwayland qt5-wayland qt6-wayland; do
    if grep -Fqx "depend = $forbidden" <<<"$metadata"; then
      echo "RXB X11 runtime package must not hard-depend on $forbidden: $pkg" >&2
      exit 1
    fi
  done
done

base_list="$(bsdtar -tf "$base_pkg")"
variant_list="$(bsdtar -tf "$variant_pkg")"

for forbidden in \
  'usr/share/ryoku/services.tsv' \
  'usr/share/ryoku/lockscreen/' \
  'usr/share/sddm/' \
  'usr/share/wayland-sessions/' \
  'usr/share/xsessions/bspwm.desktop' \
  'etc/sddm.conf' \
  'etc/sddm.conf.d/' \
  'etc/kernel/cmdline' \
  'etc/default/grub' \
  'boot/grub/' \
  'etc/X11/xorg.conf.d/' \
  'etc/modprobe.d/' \
  'usr/lib/systemd/system-sleep/' \
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
  'usr/bin/ryoku-qylock-lock' \
  'usr/lib/systemd/user/default.target.wants/ryogami.service' \
  'usr/lib/systemd/user/default.target.wants/ryoku-shell-x11.service' \
  'usr/lib/systemd/user/default.target.wants/ryogami-x11.service' \
  'usr/lib/systemd/user/ryoku-shell.service.d/10-rxb-x11.conf' \
  'usr/lib/systemd/user/ryogami.service.d/10-rxb-x11.conf' \
  'usr/lib/systemd/user/ryoku-session.target.wants/ryoku-shell.service' \
  'usr/lib/systemd/user/ryoku-session.target.wants/ryogami.service'; do
  if grep -Fq "$forbidden" <<<"$base_list" || grep -Fq "$forbidden" <<<"$variant_list"; then
    echo "Forbidden host integration in RXB package set: $forbidden" >&2
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
  'usr/lib/systemd/user/ryoku-shell-x11.service' \
  'usr/lib/systemd/user/ryogami-x11.service' \
  'usr/lib/systemd/user/ryoku-x11-session.target' \
  'usr/lib/systemd/user/ryoku-x11-session.target.wants/ryoku-shell-x11.service' \
  'usr/lib/systemd/user/ryoku-x11-session.target.wants/ryogami-x11.service' \
  'usr/bin/ryoku-x11-session' \
  'usr/bin/ryoku-x11-session-init' \
  'usr/bin/ryoku-x11-lock' \
  'usr/bin/ryoku-wm-i3' \
  'usr/share/ryoku/config/ryoku-x11/config'; do
  grep -Fq "$required" <<<"$variant_list" || {
    echo "Missing expected RXB i3 integration file: $required" >&2
    exit 1
  }
done

echo "RXB package safety checks passed: no global environment, SDDM, lockscreen, boot, or GPU policy changes."
