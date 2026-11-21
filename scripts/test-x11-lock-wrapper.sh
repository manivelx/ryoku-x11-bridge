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
export RXB_LOCK_TEST_MARKER="$tmp/marker"
PATH="$tmp/prefer" "$locker"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == xsecurelock ]] || {
  echo "XSecureLock was not preferred" >&2
  exit 1
}

make_fake_path "$tmp/fallback"
cat >"$tmp/fallback/i3lock" <<'EOF'
#!/bin/sh
[[ "$1" == --nofork && "$2" == --color=000000 ]]
printf i3lock > "$RXB_LOCK_TEST_MARKER"
EOF
chmod +x "$tmp/fallback/i3lock"
rm -f "$RXB_LOCK_TEST_MARKER"
PATH="$tmp/fallback" "$locker"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == i3lock ]] || {
  echo "i3lock fallback was not selected" >&2
  exit 1
}

echo "X11 lock wrapper selection tests passed."
