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

# The installer itself resolves external dependencies from the configured
# Arch repositories. The transaction test exercises that exact install path.
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
  # Pacman requires package metadata entries at archive root. Archiving "."
  # prefixes entries with "./", which makes pacman reject the synthetic upgrade
  # as missing .PKGINFO. Enumerate every root entry (including dotfiles) and
  # archive those names directly instead.
  (
    cd "$stage"
    shopt -s dotglob nullglob
    archive_entries=(*)
    (("${#archive_entries[@]}" > 0)) || {
      echo "Synthetic upgrade staging directory is empty: $stage" >&2
      exit 1
    }
    bsdtar --zstd -cf "$upgraded_pkg" -- "${archive_entries[@]}"
  )
  bsdtar -tf "$upgraded_pkg" | grep -Fxq '.PKGINFO' || {
    echo "Synthetic upgrade archive is missing root-level .PKGINFO: $upgraded_pkg" >&2
    exit 1
  }
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
  if [[ -L /var/lib/rxb ]]; then
    rm -f -- /var/lib/rxb
  elif [[ -d /var/lib/rxb ]]; then
    rm -f -- /var/lib/rxb/installed-packages
    rmdir /var/lib/rxb 2>/dev/null || true
  fi
  [[ -z ${upgrade_dir:-} ]] || rm -rf "$upgrade_dir"
  [[ -z ${test_home:-} ]] || rm -rf "$test_home"
  cleanup_test_config
  exit "$status"
}
trap cleanup EXIT

# The installer must reject unsafe ownership metadata before asking pacman to
# inspect or mutate the installed package database.
manifest_attack_dir="$upgrade_dir/installer-manifest-attacks"
fake_pacman_dir="$manifest_attack_dir/bin"
mkdir -p "$fake_pacman_dir" "$manifest_attack_dir/attacker-dir"
pacman_marker="$manifest_attack_dir/pacman-was-called"
cat > "$fake_pacman_dir/pacman" <<'FAKE_PACMAN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RXB_PACMAN_MARKER"
exit 0
FAKE_PACMAN
chmod 0755 "$fake_pacman_dir/pacman"

# F3: simulate a pre-existing package that conflicts with the RXB cursor set.
conflict_pacman_dir="$manifest_attack_dir/conflict-bin"
mkdir -p "$conflict_pacman_dir"
cat > "$conflict_pacman_dir/pacman" <<'FAKE_CONFLICT_PACMAN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RXB_PACMAN_MARKER"
if [[ "$1" == "-Q" && "$2" == "bibata-cursor-theme" ]]; then
  printf 'bibata-cursor-theme 1.0-1\n'
  exit 0
fi
exit 1
FAKE_CONFLICT_PACMAN
chmod 0755 "$conflict_pacman_dir/pacman"
if PATH="$conflict_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist" > "$manifest_attack_dir/conflict-package.log" 2>&1; then
  echo "Installer accepted a pre-existing conflicting package." >&2
  exit 1
fi
grep -Fq "conflicting package 'bibata-cursor-theme' is already installed" "$manifest_attack_dir/conflict-package.log" || {
  echo "Installer did not identify the pre-existing conflicting package." >&2
  exit 1
}
if grep -Eq '^(--config .* )?(-S|-U)( |$)' "$pacman_marker"; then
  echo "Installer started a package transaction despite the pre-existing conflict." >&2
  exit 1
fi
rm -f "$pacman_marker"

# Interrupted-install recovery: stop the installer immediately before its
# local pacman -U transaction, SIGKILL the installer, then prove the manifest
# already records all newly introduced local packages and the remover cleans
# the installed dependency subset without guessing.
interrupt_pacman_dir="$manifest_attack_dir/interrupt-bin"
mkdir -p "$interrupt_pacman_dir"
interrupt_marker="$manifest_attack_dir/interrupt-at-local-transaction"
interrupt_continue="$manifest_attack_dir/continue-interrupt-wrapper"
interrupt_wrapper_pid="$manifest_attack_dir/interrupt-wrapper.pid"
cat > "$interrupt_pacman_dir/pacman" <<'INTERRUPT_PACMAN'
#!/usr/bin/env bash
if [[ "${3:-}" == "-U" ]]; then
  printf '%s\n' "$" > "$RXB_INTERRUPT_WRAPPER_PID"
  : > "$RXB_INTERRUPT_MARKER"
  while [[ ! -e "$RXB_INTERRUPT_CONTINUE" ]]; do sleep 0.1; done
  exit 99
fi
exec /usr/bin/pacman "$@"
INTERRUPT_PACMAN
chmod 0755 "$interrupt_pacman_dir/pacman"
rm -f "$interrupt_marker" "$interrupt_continue" "$interrupt_wrapper_pid"
PATH="$interrupt_pacman_dir:$PATH" \
  RXB_INTERRUPT_MARKER="$interrupt_marker" \
  RXB_INTERRUPT_CONTINUE="$interrupt_continue" \
  RXB_INTERRUPT_WRAPPER_PID="$interrupt_wrapper_pid" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist" \
  > "$manifest_attack_dir/interrupted-install.log" 2>&1 &
interrupted_installer_pid=$!
for attempt in {1..900}; do
  [[ -e "$interrupt_marker" ]] && break
  kill -0 "$interrupted_installer_pid" 2>/dev/null || break
  sleep 0.1
done
if [[ ! -e "$interrupt_marker" ]]; then
  kill -KILL "$interrupted_installer_pid" 2>/dev/null || true
  touch "$interrupt_continue"
  wait "$interrupted_installer_pid" 2>/dev/null || true
  echo "Installer did not reach the intercepted local package transaction; interrupted-install test cannot continue." >&2
  cat "$manifest_attack_dir/interrupted-install.log" >&2
  exit 1
fi
for name in "${package_names[@]}"; do
  grep -Fxq "$name" /var/lib/rxb/installed-packages || {
    kill -KILL "$interrupted_installer_pid" 2>/dev/null || true
    touch "$interrupt_continue"
    wait "$interrupted_installer_pid" 2>/dev/null || true
    echo "Interrupted-install manifest did not pre-record newly introduced local package: $name" >&2
    exit 1
  }
done
kill -KILL "$interrupted_installer_pid" 2>/dev/null || true
if wait "$interrupted_installer_pid" 2>/dev/null; then
  touch "$interrupt_continue"
  echo "Installer unexpectedly survived the simulated SIGKILL." >&2
  exit 1
fi
touch "$interrupt_continue"
sleep 0.2
PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/remove-rxb-packages.sh"
[[ ! -e /var/lib/rxb/installed-packages ]] || {
  echo "Interrupted-install recovery left an RXB ownership manifest." >&2
  exit 1
}
for name in "${package_names[@]}"; do
  if pacman -Q "$name" >/dev/null 2>&1; then
    echo "Interrupted-install recovery left a local RXB package installed: $name" >&2
    exit 1
  fi
done

printf 'ryoku-desktop-i3\n' > "$manifest_attack_dir/attacker-dir/installed-packages"
chmod 0600 "$manifest_attack_dir/attacker-dir/installed-packages"

[[ ! -e /var/lib/rxb && ! -L /var/lib/rxb ]] || {
  echo "Unexpected RXB manifest path exists before installer hardening tests." >&2
  exit 1
}
ln -s "$manifest_attack_dir/attacker-dir" /var/lib/rxb
if PATH="$fake_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist" > "$manifest_attack_dir/dir-symlink.log" 2>&1; then
  echo "Installer accepted a symlinked ownership directory." >&2
  exit 1
fi
[[ -L /var/lib/rxb && -f "$manifest_attack_dir/attacker-dir/installed-packages" ]] || {
  echo "Installer changed a symlinked ownership directory or its target." >&2
  exit 1
}
[[ ! -e "$pacman_marker" ]] || {
  echo "Installer invoked pacman before rejecting a symlinked ownership directory." >&2
  exit 1
}
rm -f /var/lib/rxb

mkdir -m 0700 /var/lib/rxb
ln -s "$manifest_attack_dir/attacker-dir/installed-packages" /var/lib/rxb/installed-packages
if PATH="$fake_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist" > "$manifest_attack_dir/file-symlink.log" 2>&1; then
  echo "Installer accepted a symlinked ownership manifest file." >&2
  exit 1
fi
[[ -L /var/lib/rxb/installed-packages && -f "$manifest_attack_dir/attacker-dir/installed-packages" ]] || {
  echo "Installer changed a symlinked ownership manifest or its target." >&2
  exit 1
}
[[ ! -e "$pacman_marker" ]] || {
  echo "Installer invoked pacman before rejecting a symlinked ownership manifest." >&2
  exit 1
}
rm -rf /var/lib/rxb

mkdir -m 0755 /var/lib/rxb
printf 'ryoku-desktop-i3\n' > /var/lib/rxb/installed-packages
chmod 0600 /var/lib/rxb/installed-packages
if PATH="$fake_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist" > "$manifest_attack_dir/dir-mode.log" 2>&1; then
  echo "Installer accepted a group/other-accessible ownership directory." >&2
  exit 1
fi
[[ ! -e "$pacman_marker" ]] || {
  echo "Installer invoked pacman before rejecting unsafe directory permissions." >&2
  exit 1
}
rm -rf /var/lib/rxb

mkdir -m 0700 /var/lib/rxb
printf 'ryoku-desktop-i3\n' > /var/lib/rxb/installed-packages
chmod 0644 /var/lib/rxb/installed-packages
if PATH="$fake_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist" > "$manifest_attack_dir/file-mode.log" 2>&1; then
  echo "Installer accepted a group/other-readable ownership manifest." >&2
  exit 1
fi
[[ ! -e "$pacman_marker" ]] || {
  echo "Installer invoked pacman before rejecting unsafe manifest permissions." >&2
  exit 1
}
rm -rf /var/lib/rxb

echo "[install-test] Installing the complete built package set through the RXB installer."
PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/install-rxb-packages.sh" "$dist"

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
  /usr/bin/ryoku-x11-lock
  /usr/bin/ryoku-x11-suspend
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
runuser -u builder -- env RXB_ARTIFACT_DIR="$repo_root/dist" bash "$repo_root/scripts/test-rxb-full-shell-xvfb.sh"

echo "[install-test] Removing the complete package set through the RXB rollback script."
PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/remove-rxb-packages.sh"
[[ ! -e /var/lib/rxb/installed-packages ]] || {
  echo "RXB installer ownership manifest remains after rollback." >&2
  exit 1
}
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

# A root-run uninstaller must not follow attacker-controlled manifest symlinks
# or invoke pacman until the ownership record has passed path/owner/mode checks.
manifest_attack_dir="$upgrade_dir/manifest-attacks"
fake_pacman_dir="$manifest_attack_dir/bin"
mkdir -p "$fake_pacman_dir"
pacman_marker="$manifest_attack_dir/pacman-was-called"
cat > "$fake_pacman_dir/pacman" <<'FAKE_PACMAN'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RXB_PACMAN_MARKER"
exit 0
FAKE_PACMAN
chmod 0755 "$fake_pacman_dir/pacman"
attacker_manifest="$manifest_attack_dir/attacker-packages"
printf 'ryoku-desktop-i3\n' > "$attacker_manifest"

[[ ! -e /var/lib/rxb && ! -L /var/lib/rxb ]] || {
  echo "Unexpected RXB manifest path remains before symlink tests." >&2
  exit 1
}
mkdir -m 0700 /var/lib/rxb
ln -s "$attacker_manifest" /var/lib/rxb/installed-packages
if PATH="$fake_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/remove-rxb-packages.sh" > "$manifest_attack_dir/file-symlink.log" 2>&1; then
  echo "Uninstaller accepted a symlinked ownership manifest." >&2
  exit 1
fi
[[ -L /var/lib/rxb/installed-packages && -f "$attacker_manifest" ]] || {
  echo "Uninstaller changed a symlinked ownership manifest or its target." >&2
  exit 1
}
[[ ! -e "$pacman_marker" ]] || {
  echo "Uninstaller invoked pacman before rejecting a symlinked manifest." >&2
  exit 1
}
rm -f /var/lib/rxb/installed-packages
rmdir /var/lib/rxb

attacker_dir="$manifest_attack_dir/attacker-rxb"
mkdir -m 0700 "$attacker_dir"
printf 'ryoku-desktop-i3\n' > "$attacker_dir/installed-packages"
ln -s "$attacker_dir" /var/lib/rxb
if PATH="$fake_pacman_dir:$PATH" RXB_PACMAN_MARKER="$pacman_marker" \
  PACMAN_CONFIG="$pacman_config" RXB_PACMAN_NOCONFIRM=1 \
  bash "$repo_root/scripts/remove-rxb-packages.sh" > "$manifest_attack_dir/dir-symlink.log" 2>&1; then
  echo "Uninstaller accepted a symlinked manifest directory." >&2
  exit 1
fi
[[ -L /var/lib/rxb && -f "$attacker_dir/installed-packages" ]] || {
  echo "Uninstaller changed a symlinked manifest directory or its target." >&2
  exit 1
}
[[ ! -e "$pacman_marker" ]] || {
  echo "Uninstaller invoked pacman before rejecting a symlinked manifest directory." >&2
  exit 1
}
rm -f /var/lib/rxb

cleanup_protected
rm -rf "$upgrade_dir" "$test_home"
cleanup_test_config
trap - EXIT
echo "RXB disposable install/uninstall transaction passed."
