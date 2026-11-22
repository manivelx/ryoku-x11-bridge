#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
locker="$root/payload/bin/ryoku-x11-lock"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_fake_path() {
  local directory="$1"
  mkdir -p "$directory"
  ln -s "$(command -v bash)" "$directory/bash"
  ln -s "$(command -v install)" "$directory/install"
  ln -s "$(command -v flock)" "$directory/flock"
  ln -s "$(command -v sleep)" "$directory/sleep"
}

make_fake_path "$tmp/wayland"
cat >"$tmp/wayland/ryoku-qylock-lock" <<'EOF'
#!/bin/sh
printf qylock > "$RXB_LOCK_TEST_MARKER"
EOF
chmod +x "$tmp/wayland/ryoku-qylock-lock"
export RXB_LOCK_TEST_MARKER="$tmp/marker"
PATH="$tmp/wayland" WAYLAND_DISPLAY=wayland-0 DISPLAY= bash "$locker"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == qylock ]] || {
  echo "Wayland lock wrapper did not preserve qylock" >&2
  exit 1
}

make_fake_path "$tmp/prefer"
cat >"$tmp/prefer/xsecurelock" <<'EOF'
#!/bin/sh
printf xsecurelock > "$RXB_LOCK_TEST_MARKER"
EOF
cat >"$tmp/prefer/i3lock" <<'EOF'
#!/bin/sh
printf i3lock > "$RXB_LOCK_TEST_MARKER"
EOF
chmod +x "$tmp/prefer/xsecurelock" "$tmp/prefer/i3lock"
rm -f "$RXB_LOCK_TEST_MARKER"
PATH="$tmp/prefer" XDG_RUNTIME_DIR="$tmp/runtime" DISPLAY=:99 WAYLAND_DISPLAY= bash "$locker"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == xsecurelock ]] || {
  echo "XSecureLock was not preferred on X11" >&2
  exit 1
}

make_fake_path "$tmp/fallback"
cat >"$tmp/fallback/i3lock" <<'EOF'
#!/bin/sh
[ "$1" = "--nofork" ] && [ "$2" = "--color=000000" ] || exit 1
printf i3lock > "$RXB_LOCK_TEST_MARKER"
EOF
chmod +x "$tmp/fallback/i3lock"
rm -f "$RXB_LOCK_TEST_MARKER"
PATH="$tmp/fallback" XDG_RUNTIME_DIR="$tmp/runtime-fallback" DISPLAY=:100 WAYLAND_DISPLAY= bash "$locker"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == i3lock ]] || {
  echo "i3lock fallback was not selected" >&2
  exit 1
}

make_fake_path "$tmp/dedupe"
cat >"$tmp/dedupe/xsecurelock" <<'EOF'
#!/bin/sh
printf x >> "$RXB_LOCK_TEST_MARKER"
sleep 1
EOF
chmod +x "$tmp/dedupe/xsecurelock"
rm -f "$RXB_LOCK_TEST_MARKER"
PATH="$tmp/dedupe" XDG_RUNTIME_DIR="$tmp/runtime-dedupe" DISPLAY=:101 WAYLAND_DISPLAY= bash "$locker" &
first_pid=$!
sleep 0.1
PATH="$tmp/dedupe" XDG_RUNTIME_DIR="$tmp/runtime-dedupe" DISPLAY=:101 WAYLAND_DISPLAY= bash "$locker"
wait "$first_pid"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == x ]] || {
  echo "Repeated X11 lock request started more than one locker" >&2
  exit 1
}

echo "X11 lock wrapper tests passed: Wayland passthrough, PAM locker selection, fallback and idempotency."
