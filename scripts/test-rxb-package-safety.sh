#!/usr/bin/env bash
set -euo pipefail

dist="${1:-dist}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# RXB must not ship hand-written i3 shortcuts. The original upstream Ryoku
# catalogue is the sole source of generated keybindings.
for config in "$root/payload/ryoku-x11/config" "$root/payload/ryoku-x11/generated.conf"; do
  if grep -Eq '^[[:space:]]*bind(sym|code)[[:space:]]' "$config"; then
    echo "RXB must not ship custom i3 keybindings in $config." >&2
    exit 1
  fi
done

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
if grep -Eq '^(After|Before|Wants|Requires|BindsTo|PartOf)=.*graphical-session' "$target_file"; then
  echo "RXB X11 target must not depend on graphical-session.target; X11 DM sessions do not reliably start it." >&2
  exit 1
fi
if grep -Fxq 'After=ryoku-x11-session.target' "$root/payload/systemd/ryoku-shell-x11.service"; then
  echo "RXB shell must not be ordered after a target that Wants it (would create a target ordering cycle)." >&2
  exit 1
fi
if ! grep -Fq 'After=ryoku-shell-x11.service' "$root/payload/systemd/ryogami-x11.service"; then
  echo "Ryogami must start after the RXB shell daemon." >&2
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
  if [[ "$pkg_name" == "ryoku-keyring" ]]; then
    echo "RXB must not install or trust the upstream pacman signing key; its updater is disabled." >&2
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
  if [[ "$pkg" == "$variant_pkg" ]]; then
    if ! grep -Fqx 'depend = xcompmgr' <<<"$metadata"; then
      echo "RXB i3 variant must include the isolated XRender compositor dependency." >&2
      exit 1
    fi
    if grep -Fqx 'depend = picom' <<<"$metadata"; then
      echo "RXB must not hard-depend on Picom." >&2
      exit 1
    fi
    
  fi
  for forbidden in dkms hypridle hyprpicker wtype wl-clipboard wl-clip-persist grim slurp weston xorg-xwayland qt5-wayland qt6-wayland; do
    if grep -Fqx "depend = $forbidden" <<<"$metadata"; then
      echo "RXB X11 runtime package must not hard-depend on $forbidden: $pkg" >&2
      exit 1
    fi
  done
done

base_list="$(bsdtar -tf "$base_pkg")"
variant_list="$(bsdtar -tf "$variant_pkg")"
all_list="$(for pkg in "${packages[@]}"; do bsdtar -tf "$pkg"; done)"

# No RXB package may modify pacman's global trust database. The upstream
# ryoku-keyring .INSTALL runs pacman-key --populate ryoku; RXB uses local
# package artifacts and has the upstream updater disabled.
for pkg in "${packages[@]}"; do
  install_script="$(bsdtar -xOf "$pkg" .INSTALL 2>/dev/null || true)"
  if grep -Eq 'pacman-key[[:space:]]+--populate|pacman-key[[:space:]]+-a' <<<"$install_script"; then
    echo "RXB package contains a pacman trust-store mutation: $pkg" >&2
    exit 1
  fi
  if grep -Eiq '(^|[;&|[:space:]])(systemctl|loginctl|systemd-run|ryoku-host|mkinitcpio|dracut|efibootmgr|bootctl|limine|udevadm|modprobe|tmpfiles)([[:space:]]|$)' <<<"$install_script"; then
    echo "RXB package contains a host service, boot, kernel, or tmpfiles scriptlet mutation: $pkg" >&2
    exit 1
  fi
done

# The RXB package must carry the project license and the complete pinned
# upstream notice tree, including iNiR's additional terms and font licenses.
for required_notice in \
  'usr/share/licenses/ryoku-desktop-i3/LICENSE' \
  'usr/share/licenses/ryoku-desktop-i3/NOTICE' \
  'usr/share/licenses/ryoku-desktop-i3/upstream/NOTICE' \
  'usr/share/licenses/ryoku-desktop-i3/upstream/ryoku/shell/quickshell/inir/NOTICE' \
  'usr/share/licenses/ryoku-desktop-i3/upstream/ryoku/shell/quickshell/inir/LICENSE' \
  'usr/share/licenses/ryoku-desktop-i3/upstream/ryoku/shell/quickshell/inir/assets/fonts/inter/OFL.txt' \
  'usr/share/doc/ryoku-desktop-i3/THIRD_PARTY_NOTICES.md'; do
  grep -Fq "$required_notice" <<<"$variant_list" || {
    echo "RXB package is missing required license/notice: $required_notice" >&2
    exit 1
  }
done
bsdtar -xOf "$variant_pkg" ./usr/share/licenses/ryoku-desktop-i3/upstream/ryoku/shell/quickshell/inir/NOTICE | grep -Fq "Additional terms (GNU GPL version 3, section 7)" || {
  echo "RXB package did not preserve the iNiR section 7 terms." >&2
  exit 1
}

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
  'usr/lib/systemd/system/ryoku-boot-guard.service' \
  'usr/lib/tmpfiles.d/ryoku.conf' \
  'usr/share/pacman/keyrings/' \
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
  if grep -Fq "$forbidden" <<<"$all_list"; then
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
  'usr/bin/ryoku-x11-suspend' \
  'usr/bin/ryoku-wm-i3' \
  'usr/share/ryoku/config/ryoku-x11/config'; do
  grep -Fq "$required" <<<"$variant_list" || {
    echo "Missing expected RXB i3 integration file: $required" >&2
    exit 1
  }
done

if ! grep -Fq 'Suspend and hibernate are disabled on X11' "$root/payload/bin/ryoku-x11-suspend"; then
  echo "X11 suspend wrapper must fail closed with an explicit user-facing explanation." >&2
  exit 1
fi
if grep -Eq 'systemctl (suspend|hibernate)|loginctl (suspend|hibernate)' "$root/payload/bin/ryoku-x11-suspend"; then
  echo "X11 suspend wrapper must not issue a direct sleep command." >&2
  exit 1
fi

echo "RXB package safety checks passed: no global environment, SDDM, lockscreen, boot, GPU policy, or unguarded suspend changes."
