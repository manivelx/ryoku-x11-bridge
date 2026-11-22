#!/usr/bin/env bash
set -euo pipefail

dist="${1:-dist}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob
packages=("$dist"/*.pkg.tar.*)
(("${#packages[@]}" > 0)) || { echo "No Arch package artifacts found in $dist" >&2; exit 1; }

declare -a package_names=()
declare -A local_provides=()
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
pacman -U --noconfirm "${packages[@]}"

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

trap - EXIT
echo "RXB disposable install/uninstall transaction passed."
