#!/usr/bin/env bash
# Read-only target-host checks for RXB. This script must never install packages,
# change configuration, stop services, or modify the boot/GPU/display stack.
set -uo pipefail

failures=0
warnings=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { warnings=$((warnings + 1)); printf '[WARN] %s\n' "$*" >&2; }
fail() { failures=$((failures + 1)); printf '[FAIL] %s\n' "$*" >&2; }

printf 'RXB target-host preflight (read-only)\n'
printf 'Date: %s\n' "$(date -Is 2>/dev/null || date)"
printf 'User: %s (uid %s)\n' "${USER:-unknown}" "$(id -u)"
printf 'This check does not install, remove, enable, disable, or rewrite anything.\n\n'

if (( EUID == 0 )); then
  fail "Run this preflight as your normal desktop user, not root."
else
  pass "Running as an unprivileged user."
fi

arch="$(uname -m 2>/dev/null || true)"
if [[ "$arch" == x86_64 ]]; then pass "Architecture is x86_64."; else fail "Expected x86_64; detected '$arch'."; fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in
    arch*|*arch*) pass "Detected Arch-family system: ${PRETTY_NAME:-${ID:-unknown}}." ;;
    *) fail "Expected Arch Linux or CachyOS; detected ${PRETTY_NAME:-${ID:-unknown}}." ;;
  esac
else
  fail "/etc/os-release is unavailable."
fi

for cmd in pacman sha256sum stat pgrep; do
  if command -v "$cmd" >/dev/null 2>&1; then pass "Required command available: $cmd."; else fail "Missing required command: $cmd."; fi
done

if [[ -n "${DISPLAY:-}" ]]; then
  pass "DISPLAY is set to $DISPLAY."
  if command -v xdpyinfo >/dev/null 2>&1; then
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then pass "The current X11 display is reachable."; else fail "Cannot connect to the current X11 display."; fi
  elif command -v xset >/dev/null 2>&1; then
    if xset -display "$DISPLAY" q >/dev/null 2>&1; then pass "The current X11 display is reachable."; else fail "Cannot connect to the current X11 display."; fi
  else
    warn "Neither xdpyinfo nor xset is installed; display connectivity could not be verified."
  fi
else
  fail "DISPLAY is unset. Run this from your existing graphical X11 session."
fi

session_type="${XDG_SESSION_TYPE:-unknown}"
if [[ "$session_type" == x11 ]]; then
  pass "XDG_SESSION_TYPE reports X11."
elif [[ "$session_type" == unknown && -n "${DISPLAY:-}" ]]; then
  warn "XDG_SESSION_TYPE is unset; DISPLAY exists, but session type needs manual confirmation."
else
  fail "Expected an X11 session; XDG_SESSION_TYPE='$session_type'."
fi

if pgrep -x bspwm >/dev/null 2>&1; then
  pass "Existing BSPWM session is running and available as the recovery desktop."
else
  warn "BSPWM is not running in this session. Confirm its SDDM session entry remains available before testing."
fi

if [[ -e /var/lib/pacman/db.lck ]]; then
  fail "Pacman database lock exists at /var/lib/pacman/db.lck; close package-manager activity and investigate before proceeding."
else
  pass "No pacman database lock is present."
fi

if command -v pacman >/dev/null 2>&1; then
  existing_ryoku=()
  for package in ryoku-desktop ryoku-desktop-i3 ryogami; do
    if pacman -Q "$package" >/dev/null 2>&1; then existing_ryoku+=("$package"); fi
  done
  if (("${#existing_ryoku[@]}" > 0)); then
    printf '[INFO] Existing Ryoku packages: %s\\n' "${existing_ryoku[*]}"
    if [[ -r /var/lib/rxb/installed-packages ]]; then
      warn "Existing Ryoku packages and an RXB ownership record were found; review both before an upgrade."
    else
      fail "Existing Ryoku packages lack an RXB ownership record; the installer is expected to refuse this state."
    fi
  else
    pass "No pre-existing RXB/Ryoku package names were detected."
  fi
fi

printf '\nHardware and recovery configuration (read-only inventory)\n'
if command -v lspci >/dev/null 2>&1; then
  gpu="$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)"
  if [[ -n "$gpu" ]]; then printf '%s\n' "$gpu"; else warn "No PCI display controller was identified by lspci."; fi
else
  warn "lspci is unavailable; GPU identity was not checked."
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia_info="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true)"
  if [[ -n "$nvidia_info" ]]; then
    printf '[INFO] NVIDIA GPU/driver: %s\n' "$nvidia_info"
    if grep -q '470\.' <<<"$nvidia_info"; then pass "NVIDIA 470 driver is active."; else warn "Active NVIDIA driver is not in the expected 470.x series."; fi
  else
    warn "nvidia-smi exists but cannot query the active driver."
  fi
else
  warn "nvidia-smi is unavailable; proprietary NVIDIA runtime status was not verified."
fi

if command -v qs >/dev/null 2>&1; then
  qs_version="$(qs --version 2>&1 | head -n 1 || true)"
  printf '[INFO] Quickshell: %s\n' "${qs_version:-version unavailable}"
else
  warn "Quickshell command 'qs' is not currently available in PATH."
fi

printf '\nProtected paths (existence only; no files are read or changed)\n'
protected_paths=(
  /etc/sddm.conf
  /etc/sddm.conf.d
  /usr/share/sddm/themes/ryoku-orbital
  /usr/share/xsessions/bspwm.desktop
  "$HOME/.config/bspwm"
  "$HOME/.config/quickshell"
  "$HOME/.local/share/quickshell-lockscreen"
  "$HOME/.config/picom"
  /etc/X11/xorg.conf.d
  /etc/modprobe.d
  /etc/kernel/cmdline
  /etc/default/grub
)
for path in "${protected_paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then printf '[PRESENT] %s\n' "$path"; else printf '[ABSENT]  %s\n' "$path"; fi
done

printf '\nSummary: %s failure(s), %s warning(s).\n' "$failures" "$warnings"
if (( failures > 0 )); then
  printf 'STOP: do not install RXB on this host until every failure is resolved.\n' >&2
  exit 1
fi
printf 'Preflight checks passed. This is not approval to install; review the warnings and release checklist first.\n'
