#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$root/payload/bin/ryoku-x11-suspend"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_fake_path() {
  local directory="$1"
  mkdir -p "$directory"
  ln -s "$(command -v bash)" "$directory/bash"
  ln -s "$(command -v sleep)" "$directory/sleep"
}

make_fake_path "$tmp/x11"
cat >"$tmp/x11/notify-send" <<'EOF'
#!/bin/sh
printf notified > "$RXB_SUSPEND_TEST_MARKER"
EOF
chmod +x "$tmp/x11/notify-send"
export RXB_SUSPEND_TEST_MARKER="$tmp/marker"
status=0
PATH="$tmp/x11" DISPLAY=:99 WAYLAND_DISPLAY= RYOKU_X11_BRIDGE=1 bash "$wrapper" || status=$?
[[ "$status" == 69 ]] || {
  echo "X11 suspend wrapper exit = $status, want fail-closed exit 69" >&2
  exit 1
}
[[ "$(cat "$RXB_SUSPEND_TEST_MARKER")" == notified ]] || {
  echo "X11 suspend refusal did not notify the user" >&2
  exit 1
}

make_fake_path "$tmp/wayland"
cat >"$tmp/wayland/ryoku-shell" <<'EOF'
#!/bin/sh
printf 'ryoku-shell %s\n' "$*" >> "$RXB_SUSPEND_TEST_MARKER"
EOF
cat >"$tmp/wayland/ryoku-host" <<'EOF'
#!/bin/sh
printf 'ryoku-host %s\n' "$*" >> "$RXB_SUSPEND_TEST_MARKER"
EOF
chmod +x "$tmp/wayland/ryoku-shell" "$tmp/wayland/ryoku-host"
rm -f "$RXB_SUSPEND_TEST_MARKER"
PATH="$tmp/wayland" DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 bash "$wrapper" suspend
PATH="$tmp/wayland" DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 bash "$wrapper" hibernate
grep -Fqx 'ryoku-shell suspend' "$RXB_SUSPEND_TEST_MARKER"
grep -Fqx 'ryoku-shell lock' "$RXB_SUSPEND_TEST_MARKER"
grep -Fqx 'ryoku-host power hibernate' "$RXB_SUSPEND_TEST_MARKER"

echo "X11 suspend wrapper tests passed: X11 refusal and Wayland secure-path passthrough."
