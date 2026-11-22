#!/usr/bin/env bash
set -euo pipefail

dist="${1:-dist}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# This test runs in a disposable container whose PID 1 is not systemd. Disable
# only host package-manager hooks (for example kernel-module reload hooks) in
# this isolated test transaction; package .install scripts and file ownership
# checks still execute normally. A real Arch/CachyOS install uses its normal
# pacman.conf and hooks.
pacman_config="$(mktemp)"
pacman_hook_dir="$(mktemp -d)"
awk -v hook_dir="$pacman_hook_dir" '
  /^\[options\]$/ { print; print "HookDir = " hook_dir; next }
  { print }
' /etc/pacman.conf > "$pacman_config"
pacman() { command pacman --config "$pacman_config" "$@"; }
cleanup_test_config() {
  rm -f -- "$pacman_config"
  rm -rf -- "$pacman_hook_dir"
}
trap cleanup_test_config EXIT
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || { echo "No Arch package artifacts found in $dist" >&2; exit 1; }

declare -a package_names=()
declare -A local_provides=()
declare -A package_versions=()
for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  name="$(sed -n 's/^pkgname = //p' <<<"$metadata" | head -n1)"
  [[ -n "$name" ]] || { echo "Could not read pkgname from $pkg" >&2; exit 1; }
  if [[ "$name" == *-debug ]]; then
    echo "Split debug package must not be installed as part of the RXB runtime set: $name" >&2
    exit 1
  fi
  if [[ "$name" == "ryogami" ]] && grep -Fqx 'depend = skwd-paper-bin' <<<"$metadata"; then
    echo "Optional Paper wallpaper provider must not be a hard install dependency" >&2
    exit 1
  fi
  package_names+=("$name")
  package_versions["$name"]="$(sed -n 's/^pkgver = //p' <<<"$metadata" | head -n1)"
  local_provides["$name"]=1
  while IFS= read -r provided; do
    provided_name="${provided%%[<>=]*}"
    [[ -n "$provided_name" ]] && local_provides["$provided_name"]=1
  done < <(sed -n 's/^provides = //p' <<<"$metadata")
done

# Every Ryoku-owned dependency must be supplied by this exact package set.
# The normal pacman transaction resolves external dependencies from the official
# Arch repositories; this catches hard dependencies that are unavailable there.
for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  while IFS= read -r dependency; do
    dependency_name="${dependency%%[<>=]*}"
    case "$dependency_name" in
      ryoku*|ryogami*|gpk)
        [[ -n "${local_provides[$dependency_name]:-}" ]] || {
          echo "Missing local Ryoku package dependency: $dependency_name (required by $pkg)" >&2
          exit 1
        }
        ;;
    esac
  done < <(sed -n 's/^depend = //p' <<<"$metadata")
done

# Install every external dependency from the official Arch repositories before
# testing the local package transaction. pacman -U does not download missing
# dependencies from sync repositories; relying on the build container's package
# list made this test accidentally incomplete.
declare -a external_dependency_specs=()
declare -A seen_external_dependencies=()
for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  while IFS= read -r dependency; do
    dependency_name="${dependency%%[<>=]*}"
    case "$dependency_name" in
      ryoku*|ryogami*|gpk)
        [[ -n "${local_provides[$dependency_name]:-}" ]] || {
          echo "[install-test] Missing local RXB package/provider: $dependency_name" >&2
          exit 1
        }
        continue
        ;;
    esac
    if [[ -n "${local_provides[$dependency_name]:-}" ]]; then
      continue
    fi
    if [[ -z "${seen_external_dependencies[$dependency]:-}" ]]; then
      seen_external_dependencies["$dependency"]=1
      external_dependency_specs+=("$dependency")
    fi
  done < <(sed -n 's/^depend = //p' <<<"$metadata")
done

if (("${#external_dependency_specs[@]}" > 0)); then
  # pacman -T preserves version constraints and avoids upgrading already
  # installed dependencies (notably Quickshell) when they already satisfy RXB.
  mapfile -t unresolved_specs < <(pacman -T "${external_dependency_specs[@]}" 2>/dev/null || true)
  if (("${#unresolved_specs[@]}" > 0)); then
    mapfile -t external_dependencies < <(
      printf '%s\n' "${unresolved_specs[@]}" |
        sed -E 's/[<>=].*$//' |
        sort -u
    )
    echo "[install-test] Installing unsatisfied external dependencies from the Arch repositories."
    pacman -S --needed --noconfirm "${external_dependencies[@]}"
  fi
  pacman -T "${external_dependency_specs[@]}" >/dev/null || {
    echo "[install-test] External dependency requirements remain unsatisfied after resolution." >&2
    exit 1
  }
fi

# Create a second, metadata-only pkgrel for each package so pacman exercises
# a real version upgrade and downgrade while the payload remains byte-identical.
upgrade_dir="$(mktemp -d)"
mkdir -p "$upgrade_dir/upgrade" "$upgrade_dir/protected"
declare -a upgrade_packages=()
declare -A upgrade_versions=()
for pkg in "${packages[@]}"; do
  metadata="$(bsdtar -xOf "$pkg" .PKGINFO)"
  name="$(sed -n 's/^pkgname = //p' <<<"$metadata" | head -n1)"
  current_version="${package_versions[$name]}"
  package_arch="$(sed -n 's/^arch = //p' <<<"$metadata" | head -n1)"
  current_rel="${current_version##*-}"
  version_base="${current_version%-*}"
  [[ "$current_rel" =~ ^[0-9]+$ ]] || {
    echo "Cannot create deterministic pkgrel upgrade for $name: $current_version" >&2
    exit 1
  }
  next_version="$version_base-$((current_rel + 1))"
  stage="$upgrade_dir/stage-$name"
  mkdir -p "$stage"
  bsdtar -xpf "$pkg" -C "$stage"
  sed -i "s|^pkgver = .*|pkgver = $next_version|" "$stage/.PKGINFO"
  upgraded_pkg="$upgrade_dir/upgrade/$name-$next_version-$package_arch.pkg.tar.zst"
  bsdtar --zstd -cf "$upgraded_pkg" -C "$stage" .
  upgrade_packages+=("$upgraded_pkg")
  upgrade_versions["$name"]="$next_version"
  rm -rf "$stage"
done

test_home="$(mktemp -d)"
export HOME="$test_home"
declare -a protected_paths=()
declare -a protected_snapshots=()
declare -a protected_created=()
protect_path() {
  local path="$1" snapshot="$upgrade_dir/protected/${#protected_paths[@]}"
  mkdir -p "$(dirname "$path")"
  if [[ -e "$path" ]]; then
    cp -a -- "$path" "$snapshot"
    protected_created+=(0)
  else
    printf 'RXB protected sentinel: %s\n' "$path" > "$path"
    protected_created+=(1)
  fi
  protected_paths+=("$path")
  protected_snapshots+=("$snapshot")
}
verify_protected() {
  local index path snapshot
  for index in "${!protected_paths[@]}"; do
    path="${protected_paths[$index]}"
    snapshot="${protected_snapshots[$index]}"
    if [[ "${protected_created[$index]}" == 1 ]]; then
      grep -Fqx "RXB protected sentinel: $path" "$path" || {
        echo "RXB changed a protected host configuration path: $path" >&2
        return 1
      }
    elif ! cmp -s "$snapshot" "$path"; then
      echo "RXB changed a pre-existing protected host configuration path: $path" >&2
      return 1
    fi
  done
}
cleanup_protected() {
  local index path snapshot
  for index in "${!protected_paths[@]}"; do
    path="${protected_paths[$index]}"
    snapshot="${protected_snapshots[$index]}"
    if [[ "${protected_created[$index]}" == 1 ]]; then
      rm -f -- "$path"
    else
      mkdir -p "$(dirname "$path")"
      rm -f -- "$path"
      cp -a -- "$snapshot" "$path"
    fi
  done
}

# Model the protected desktop files from a disposable owner's existing system.
# Existing files are snapshotted and restored on failure; absent paths receive
# unique sentinels. No live machine configuration is involved in this test.
for protected in \
  /etc/sddm.conf \
  /etc/sddm.conf.d/99-rxb-protected.conf \
  /usr/share/sddm/themes/ryoku-orbital/rxb-protected.marker \
  /usr/share/xsessions/bspwm.desktop \
  /etc/X11/xorg.conf.d/99-rxb-protected.conf \
  /etc/modprobe.d/99-rxb-protected.conf \
  /etc/kernel/cmdline \
  /etc/default/grub \
  /boot/grub/grub.cfg \
  "$HOME/.config/bspwm/bspwmrc" \
  "$HOME/.config/quickshell/lockscreen.qml" \
  "$HOME/.local/share/quickshell-lockscreen/shell.qml" \
  "$HOME/.config/picom/picom.conf" \
  "$HOME/.config/ryoku-x11/user.conf"; do
  protect_path "$protected"
done

cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n ${verify_root:-} ]]; then rm -rf "$verify_root"; fi
  local -a present=()
  for name in "${package_names[@]}"; do
    if pacman -Q "$name" >/dev/null 2>&1; then present+=("$name"); fi
  done
  if (("${#present[@]}" > 0)); then
    pacman -Rdd --noconfirm "${present[@]}" >/dev/null || true
  fi
  cleanup_protected
  [[ -z ${upgrade_dir:-} ]] || rm -rf "$upgrade_dir"
  [[ -z ${test_home:-} ]] || rm -rf "$test_home"
  cleanup_test_config
  exit "$status"
}
trap cleanup EXIT

echo "[install-test] Installing the complete built package set into this disposable Arch container."
pacman -U --noconfirm "${packages[@]}"

for name in "${package_names[@]}"; do
  actual_version="$(pacman -Q "$name" | awk '{print $2}')"
  [[ "$actual_version" == "${package_versions[$name]}" ]] || {
    echo "Package was not registered at its built version after install: $name ($actual_version)" >&2
    exit 1
  }
done
verify_protected

echo "[install-test] Upgrading every RXB package to a synthetic higher pkgrel."
pacman -U --noconfirm "${upgrade_packages[@]}"
for name in "${package_names[@]}"; do
  actual_version="$(pacman -Q "$name" | awk '{print $2}')"
  [[ "$actual_version" == "${upgrade_versions[$name]}" ]] || {
    echo "Package upgrade did not reach expected version for $name: $actual_version" >&2
    exit 1
  }
done
verify_protected

echo "[install-test] Rolling back every RXB package to its original built version."
# A malformed archive must abort the whole transaction without changing
# the already-installed upgraded package set. A subsequent valid install
# proves recovery and rolls every package back to its original built version.
invalid_pkg="$upgrade_dir/invalid.pkg.tar.zst"
printf 'not an Arch package archive\n' > "$invalid_pkg"
if pacman -U --noconfirm "${packages[@]}" "$invalid_pkg"; then
  echo "pacman unexpectedly accepted an invalid RXB transaction archive" >&2
  exit 1
fi
for name in "${package_names[@]}"; do
  actual_version="$(pacman -Q "$name" | awk '{print $2}')"
  [[ "$actual_version" == "${upgrade_versions[$name]}" ]] || {
    echo "Rejected transaction changed the installed RXB package state: $name ($actual_version)" >&2
    exit 1
  }
done
verify_protected

pacman -U --noconfirm "${packages[@]}"
for name in "${package_names[@]}"; do
  actual_version="$(pacman -Q "$name" | awk '{print $2}')"
  [[ "$actual_version" == "${package_versions[$name]}" ]] || {
    echo "Package rollback did not restore original version for $name: $actual_version" >&2
    exit 1
  }
done
verify_protected

# A fresh disposable Arch container must not acquire these Wayland-only tools
# or DKMS as a side effect of installing the RXB X11 runtime. qt6-wayland is
# intentionally checked in RXB package metadata above, not here: the Arch
# Quickshell package may bring it as its own optional backend/build prerequisite.
for forbidden in dkms hypridle hyprpicker wtype wl-clipboard wl-clip-persist grim slurp weston xorg-xwayland qt5-wayland; do
  if pacman -Q "$forbidden" >/dev/null 2>&1; then
    echo "RXB X11 install unexpectedly installed forbidden dependency: $forbidden" >&2
    exit 1
  fi
done

required_files=(
  /usr/share/xsessions/ryoku-x11.desktop
  /usr/bin/ryoku-x11-session
  /usr/bin/ryoku-x11-session-init
  /usr/bin/ryoku-wm-i3
  /usr/lib/systemd/user/ryoku-shell.service
  /usr/lib/systemd/user/ryoku-x11-session.target
  /usr/lib/systemd/user/ryoku-shell-x11.service
  /usr/lib/systemd/user/ryogami-x11.service
  /usr/lib/systemd/user/ryoku-x11-session.target.wants/ryoku-shell-x11.service
  /usr/lib/systemd/user/ryoku-x11-session.target.wants/ryogami-x11.service
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
[[ ! -e /usr/lib/systemd/user/default.target.wants/ryoku-shell-x11.service ]]
[[ ! -e /usr/lib/systemd/user/default.target.wants/ryogami-x11.service ]]
[[ ! -e /usr/lib/systemd/user/ryoku-shell.service.d/10-rxb-x11.conf ]]
[[ ! -e /usr/lib/systemd/user/ryogami.service.d/10-rxb-x11.conf ]]
[[ ! -e /usr/lib/systemd/user/ryoku-session.target.wants/ryoku-shell.service ]]
[[ ! -e /usr/lib/systemd/user/ryoku-session.target.wants/ryogami.service ]]

# Validate the installed user-unit files offline. `systemd-analyze --user
# verify` attempts to contact the caller's live user manager on some systemd
# versions, which is unavailable in this disposable container. Build a minimal
# temporary root, map the user units into its system-unit search path, and add
# explicit stubs for session-only dependencies. This checks unit syntax,
# dependency references, and ExecStart paths without starting a manager or
# changing the host/container's systemd state.
command -v systemd-analyze >/dev/null 2>&1 || {
  echo "systemd-analyze is required to verify the RXB user units." >&2
  exit 1
}
verify_root="$(mktemp -d)"
mkdir -p "$verify_root/usr/lib/systemd/system" "$verify_root/usr/bin"
for unit in graphical-session.target graphical-session-pre.target sysinit.target; do
  printf '[Unit]\nDescription=RXB offline verification stub (%s)\n' "$unit" \
    > "$verify_root/usr/lib/systemd/system/$unit"
done
printf '[Unit]\nDescription=RXB offline session slice stub\n[Slice]\n' \
  > "$verify_root/usr/lib/systemd/system/session.slice"
for executable in ryoku-shell ryogami; do
  : > "$verify_root/usr/bin/$executable"
  chmod 0755 "$verify_root/usr/bin/$executable"
done
for unit in ryoku-x11-session.target ryoku-shell-x11.service ryogami-x11.service; do
  install -m 0644 "/usr/lib/systemd/user/$unit" \
    "$verify_root/usr/lib/systemd/system/$unit"
done
systemd-analyze verify --root="$verify_root" --man=no \
  "$verify_root/usr/lib/systemd/system/ryoku-x11-session.target" \
  "$verify_root/usr/lib/systemd/system/ryoku-shell-x11.service" \
  "$verify_root/usr/lib/systemd/system/ryogami-x11.service"
rm -rf "$verify_root"
verify_root=""

# Exercise the installed upstream QML entry point with the packaged i3 provider.
# Run as an unprivileged account, but only after the disposable package set is installed.
if ! id builder >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash builder
fi
runuser -u builder -- bash "$repo_root/scripts/test-rxb-full-shell-xvfb.sh"

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
verify_protected

cleanup_protected
rm -rf "$upgrade_dir" "$test_home"
cleanup_test_config
trap - EXIT
echo "RXB disposable install/uninstall transaction passed."
