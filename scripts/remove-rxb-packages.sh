#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || {
    echo "remove-rxb-packages: run as root or install sudo." >&2
    exit 1
  }
  script_path="$(readlink -f "$0")"
  exec sudo env \
    PACMAN_CONFIG="${PACMAN_CONFIG:-}" \
    RXB_PACMAN_NOCONFIRM="${RXB_PACMAN_NOCONFIRM:-0}" \
    "$script_path" "$@"
fi

# Match the installer's test-only no-confirm gate: never permit an
# accidental unprompted removal on a normal Arch/CachyOS host.
if [[ "${RXB_PACMAN_NOCONFIRM:-0}" == 1 ]]; then
  marker=/run/rxb-install-test-disposable
  marker_uid=""
  marker_mode=""
  [[ -f /.dockerenv && ! -L /.dockerenv && -f "$marker" && ! -L "$marker" ]] || {
    echo "remove-rxb-packages: RXB_PACMAN_NOCONFIRM is restricted to the disposable Arch transaction test." >&2
    exit 1
  }
  marker_uid="$(stat -c '%u' -- "$marker" 2>/dev/null || true)"
  marker_mode="$(stat -c '%a' -- "$marker" 2>/dev/null || true)"
  [[ "$marker_uid" == 0 && "$marker_mode" == 600 ]] || {
    echo "remove-rxb-packages: disposable transaction marker is not root-owned mode 0600." >&2
    exit 1
  }
fi

pacman_cmd=(pacman)
if [[ -n "${PACMAN_CONFIG:-}" ]]; then
  [[ -f "$PACMAN_CONFIG" ]] || {
    echo "remove-rxb-packages: PACMAN_CONFIG does not exist: $PACMAN_CONFIG" >&2
    exit 1
  }
  pacman_cmd+=(--config "$PACMAN_CONFIG")
fi
pacman_exec() { "${pacman_cmd[@]}" "$@"; }
pacman_confirmed() {
  local operation="$1"
  shift
  if [[ "${RXB_PACMAN_NOCONFIRM:-0}" == 1 ]]; then
    pacman_exec "$operation" --noconfirm "$@"
  else
    pacman_exec "$operation" "$@"
  fi
}

manifest_dir="/var/lib/rxb"
manifest="$manifest_dir/installed-packages"
refuse_manifest() {
  echo "remove-rxb-packages: refusing an unsafe RXB ownership manifest: $1" >&2
  exit 1
}
if [[ -L "$manifest_dir" ]]; then
  refuse_manifest "$manifest_dir is a symlink"
fi
if [[ ! -e "$manifest_dir" ]]; then
  echo "No RXB installer ownership record exists; refusing to guess which packages to remove." >&2
  echo "If the packages were installed manually, review them with pacman -Q and remove them explicitly." >&2
  exit 2
fi
[[ -d "$manifest_dir" && -O "$manifest_dir" ]] || refuse_manifest "$manifest_dir is not a root-owned directory"
dir_mode="$(stat -c '%a' -- "$manifest_dir")"
(( (8#$dir_mode & 077) == 0 )) || refuse_manifest "$manifest_dir is accessible to group or other users"
if [[ -L "$manifest" ]]; then
  refuse_manifest "$manifest is a symlink"
fi
if [[ ! -e "$manifest" ]]; then
  echo "No RXB installer ownership record exists; refusing to guess which packages to remove." >&2
  echo "If the packages were installed manually, review them with pacman -Q and remove them explicitly." >&2
  exit 2
fi
[[ -f "$manifest" && -O "$manifest" ]] || refuse_manifest "$manifest is not a root-owned regular file"
manifest_mode="$(stat -c '%a' -- "$manifest")"
(( (8#$manifest_mode & 077) == 0 )) || refuse_manifest "$manifest is accessible to group or other users"

declare -a installed=()
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  [[ "$name" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || {
    echo "remove-rxb-packages: invalid package name in manifest: $name" >&2
    exit 1
  }
  if pacman_exec -Q "$name" >/dev/null 2>&1; then
    installed+=("$name")
  fi
done < "$manifest"

if (("${#installed[@]}" > 0)); then
  echo "Removing only packages recorded as newly installed by RXB:"
  printf '  %s\n' "${installed[@]}"
  pacman_confirmed -Rns "${installed[@]}"
fi

rm -f -- "$manifest"
rmdir /var/lib/rxb 2>/dev/null || true

echo
echo "RXB-owned packages removed."
echo "User configuration under ~/.config/ryoku-x11 is preserved; remove it manually only after backing it up."
echo "Packages that predated the RXB installer are not in its removal record."
