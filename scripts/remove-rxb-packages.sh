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

manifest="/var/lib/rxb/installed-packages"
[[ -f "$manifest" ]] || {
  echo "No RXB installer ownership record exists; refusing to guess which packages to remove." >&2
  echo "If the packages were installed manually, review them with pacman -Q and remove them explicitly." >&2
  exit 2
}

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
