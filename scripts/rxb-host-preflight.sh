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

for cmd in pacman sha256sum stat pgrep vercmp; do
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
    # /var/lib/rxb is intentionally root-only (0700), and its manifest is
    # root-only (0600). A normal-user -r check therefore reports a false
    # absence. Inspect directory metadata without weakening permissions;
    # the root-running installer validates manifest contents and entries.
    if [[ -d /var/lib/rxb && ! -L /var/lib/rxb ]]; then
      manifest_dir_meta="$(stat -c '%u:%a' -- /var/lib/rxb 2>/dev/null || true)"
      manifest_dir_uid="${manifest_dir_meta%%:*}"
      manifest_dir_mode="${manifest_dir_meta#*:}"
      if [[ "$manifest_dir_uid" == 0 && "$manifest_dir_mode" =~ ^[0-7]{3,4}$ ]] &&
        (( (8#$manifest_dir_mode & 077) == 0 )); then
        warn "Root-protected RXB ownership directory exists; the installer will validate its manifest contents as root."
      else
        fail "RXB ownership directory exists but is not root-owned with private permissions."
      fi
    else
      fail "Existing Ryoku packages have no RXB ownership directory; the installer will refuse to claim them."
    fi
  else
    pass "No pre-existing RXB/Ryoku package names were detected."
  fi
fi

# pacman -Q accepts virtual provides, so querying a virtual name can return
# ryoku-cursors even when the standalone conflicting package is not installed.
# Use the exact package-name list from -Qq for conflict checks.
if command -v pacman >/dev/null 2>&1; then
  installed_package_names="$(pacman -Qq 2>/dev/null || true)"
  for package in bibata-cursor-theme bibata-cursor-theme-bin gpk-bin; do
    if grep -Fxq -- "$package" <<<"$installed_package_names"; then
      fail "Exact installed package '$package' conflicts with the RXB package set. Resolve this deliberately before installing."
    fi
  done
  for package in tlp auto-cpufreq tuned-ppd; do
    if pacman -Q "$package" >/dev/null 2>&1; then
      warn "'$package' is installed; ryoku-desktop depends on power-profiles-daemon, which conflicts with it. The installer would stop or ask to remove it."
    fi
  done

  # ryogami requires a recent Qt6. A stale system could make pacman upgrade Qt
  # (and other libraries) as a side effect of the RXB dependency transaction,
  # which can break the existing Quickshell/BSPWM stack. Update the whole system
  # deliberately first.
  qt_version="$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}')"
  if [[ -n "$qt_version" ]]; then
    printf '[INFO] Installed qt6-base: %s (the RXB set requires >= 6.12)\n' "$qt_version"
    if [[ "$(vercmp "$qt_version" 6.12 2>/dev/null || echo -1)" -lt 0 ]]; then
      warn "qt6-base is older than 6.12; installing RXB would pull a Qt upgrade into this system. Run a full, deliberate system update and re-test BSPWM first."
    fi
  else
    warn "qt6-base is not installed; RXB would install Qt as a dependency."
  fi
  if command -v checkupdates >/dev/null 2>&1; then
    pending_source="checkupdates"
    pending="$(checkupdates 2>&1 || true)"
  else
    pending_source="pacman -Qu"
    pending="$(pacman -Qu 2>&1 || true)"
  fi
  if [[ -n "$pending" ]]; then
    pending_rows="$(grep -E '^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+->[[:space:]]+[^[:space:]]+' <<<"$pending" || true)"
    if [[ -n "$pending_rows" ]]; then
      pending_names="$(awk '{print $1}' <<<"$pending_rows" | paste -sd ', ' -)"
      warn "Pending package updates reported by $pending_source: $pending_names. Resolve them in a separately approved maintenance window before RXB testing."
    else
      warn "$pending_source could not verify update state; inspect its output before installing: $pending"
    fi
  else
    pass "No pending package updates were reported by $pending_source."
  fi
fi

# Lock stack: RXB prefers XSecureLock and falls back to i3lock. Neither is
# installed or changed here.
if [[ -x /usr/bin/xsecurelock ]]; then
  pass "XSecureLock is installed in /usr/bin (preferred X11 locker)."
elif [[ -x /usr/bin/i3lock ]]; then
  warn "XSecureLock is absent; RXB will use the i3lock fallback in /usr/bin. Validate lock/unlock on a disposable session before relying on it."
else
  fail "Neither /usr/bin/xsecurelock nor /usr/bin/i3lock exists; RXB refuses to fake a lock screen."
fi

if [[ -e /usr/share/xsessions/ryoku-x11.desktop ]]; then
  warn "A Ryoku (X11 / i3) session entry already exists."
fi
for session in bspwm.desktop; do
  [[ -e "/usr/share/xsessions/$session" ]] || warn "/usr/share/xsessions/$session is missing; confirm a recovery session exists before testing."
done

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
