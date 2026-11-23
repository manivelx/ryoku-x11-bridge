#!/usr/bin/env bash
# Read-only target-hardware evidence collector for RXB.
# It does not install packages, change settings, start/stop services, or lock the session.
set -euo pipefail

out_dir="${1:-rxb-hardware-evidence}"
mkdir -p -- "$out_dir"
out_dir="$(cd -- "$out_dir" && pwd)"
report="$out_dir/report.txt"
: > "$report"
chmod 600 "$report"

section() { printf '\n## %s\n' "$1" >> "$report"; }
record() {
  local label="$1"; shift
  {
    printf '\n### %s\n' "$label"
    if command -v "$1" >/dev/null 2>&1; then
      "$@" 2>&1 || printf '[command exited non-zero]\n'
    else
      printf '[not installed: %s]\n' "$1"
    fi
  } >> "$report"
}
package_version() {
  local pkg="$1"
  if command -v pacman >/dev/null 2>&1; then
    pacman -Q "$pkg" 2>&1 || true
  else
    printf 'pacman unavailable\n'
  fi
}

section "Collection metadata"
{
  printf 'Collected UTC: '
  date -u '+%Y-%m-%dT%H:%M:%SZ'
  printf 'Report scope: read-only hardware and active X11 stack facts; no window titles or user files collected.\n'
} >> "$report"

section "Operating system and kernel"
{
  if [[ -r /etc/os-release ]]; then
    # Keep only distribution identity fields.
    grep -E '^(NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME)=' /etc/os-release || true
  fi
  uname -srm
} >> "$report"

record "Graphics devices (PCI identity and bound driver)" bash -c 'lspci -nnk 2>/dev/null | grep -A3 -Ei "VGA compatible controller|3D controller|Display controller" || true'
record "NVIDIA GPU summary (no serial numbers)" bash -c 'if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader; else echo "nvidia-smi unavailable"; fi'
record "OpenGL renderer" bash -c 'if command -v glxinfo >/dev/null 2>&1; then glxinfo -B | grep -E "^(direct rendering|OpenGL vendor string|OpenGL renderer string|OpenGL core profile version string|OpenGL version string):"; else echo "glxinfo unavailable"; fi'

section "Active X11 session (safe environment subset)"
{
  for key in XDG_SESSION_TYPE XDG_CURRENT_DESKTOP DESKTOP_SESSION DISPLAY QT_QPA_PLATFORM GDK_BACKEND; do
    if [[ -n "${!key:-}" ]]; then printf '%s=%s\n' "$key" "${!key}"; fi
  done
  printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:+set}"
} >> "$report"

record "X server version" bash -c 'if command -v xdpyinfo >/dev/null 2>&1; then xdpyinfo | grep -E "vendor string|vendor release"; else echo "xdpyinfo unavailable"; fi'
record "Connected monitor count and modes" bash -c 'if command -v xrandr >/dev/null 2>&1; then xrandr --listmonitors; xrandr --query | grep -E " connected|^[[:space:]]+[0-9]+x[0-9]+"; else echo "xrandr unavailable"; fi'
record "Window manager version" i3 --version
record "Compositor version" picom --version
record "Quickshell version" qs --version

section "Relevant installed package versions"
for pkg in linux-cachyos-lts nvidia-470xx-dkms nvidia-utils i3-wm quickshell picom xorg-server xorg-xrandr xsecurelock i3lock; do
  package_version "$pkg" >> "$report"
done

section "RXB package presence"
for pkg in ryoku-desktop-i3 ryoku-desktop ryogami ryoku-wm-i3; do
  package_version "$pkg" >> "$report"
done

section "Locking components (presence only; no lock is triggered)"
{
  for path in /usr/bin/xsecurelock /usr/bin/i3lock /usr/bin/ryoku-x11-lock; do
    if [[ -x "$path" ]]; then printf 'present: %s\n' "$path"; else printf 'absent: %s\n' "$path"; fi
  done
} >> "$report"

printf 'RXB hardware evidence report created: %s\n' "$report"
printf 'Review it for personal details before sharing. This collector intentionally excludes window titles, process command lines, serial numbers, network addresses, and home-directory contents.\n'
