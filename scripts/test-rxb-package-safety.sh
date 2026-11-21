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
if ! grep -Fq 'EnvironmentFile=%t/ryoku-x11-session.env' "$root/payload/systemd/ryoku-shell.service.d/10-rxb-x11.conf" ||
   ! grep -Fq 'ConditionPathExists=%t/ryoku-x11-session.env' "$root/payload/systemd/ryoku-shell.service.d/10-rxb-x11.conf"; then
  echo "Ryoku shell must consume a session-scoped environment file." >&2
  exit 1
fi
if grep -Fq 'ExecStartPre=-/usr/bin/ryoku-shell quit' "$root/payload/systemd/ryoku-shell.service.d/10-rxb-x11.conf"; then
  echo "X11 unit must not terminate a shell daemon from another session." >&2
  exit 1
fi
if ! grep -Fq 'systemctl --user stop ryoku-session.target' "$root/payload/bin/ryoku-x11-session"; then
  echo "X11 session wrapper must stop its target on exit." >&2
  exit 1
fi
if ! grep -Fq 'ryoku-session.target.wants/ryogami.service' "$root/release/packages/ryoku-desktop-i3/payload.sh"; then
  echo "Ryogami must be linked only to the RXB session target." >&2
  exit 1
fi
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || { echo "No Arch package artifacts found in $dist" >&2; exit 1; }

base_pkg=""
variant_pkg=""
for pkg in "${packages[@]}"; do
  name="${pkg##*/}"
  [[ "$name" == ryoku-desktop-i3-* ]] && variant_pkg="$pkg"
  [[ "$name" == ryoku-desktop-[0-9]* ]] && base_pkg="$pkg"
done
[[ -n "$base_pkg" ]] || { echo "Missing ryoku-desktop base package" >&2; exit 1; }
[[ -n "$variant_pkg" ]] || { echo "Missing ryoku-desktop-i3 package" >&2; exit 1; }

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
  'usr/bin/ryoku-qylock-lock' \
  'usr/lib/systemd/user/ryoku-session.target.wants/ryogami.service' \
  'usr/lib/systemd/user/ryogami.service.d/10-rxb-x11.conf'; do
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
  'usr/lib/systemd/user/ryoku-shell.service.d/10-rxb-x11.conf' \
  'usr/lib/systemd/user/ryogami.service.d/10-rxb-x11.conf' \
  'usr/lib/systemd/user/ryoku-session.target.wants/ryogami.service' \
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
