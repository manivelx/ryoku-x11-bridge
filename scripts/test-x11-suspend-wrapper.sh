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
PATH="$tmp/x11" DISPLAY=:99 WAYLAND_DISPLAY= RYOKU_WM= XDG_SESSION_TYPE= bash "$wrapper" || status=$?
[[ "$status" == 69 ]] || {
  echo "X11 suspend wrapper exit = $status, want fail-closed exit 69" >&2
  exit 1
}
status=0
PATH="$tmp/x11" DISPLAY=:99 WAYLAND_DISPLAY= RYOKU_WM= XDG_SESSION_TYPE= bash "$wrapper" hibernate || status=$?
[[ "$status" == 69 ]] || {
  echo "X11 hibernate wrapper exit = $status, want fail-closed exit 69" >&2
  exit 1
}
[[ "$(cat "$RXB_SUSPEND_TEST_MARKER")" == notified ]] || {
  echo "X11 suspend refusal did not notify the user" >&2
  exit 1
}

# A stray WAYLAND_DISPLAY inside an RXB X11 session must not select the Wayland
# path: hibernate there would run without any X11 lock.
make_fake_path "$tmp/stray"
for stub in ryoku-shell ryoku-host; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$RXB_SUSPEND_TEST_MARKER"\n' "$stub" >"$tmp/stray/$stub"
  chmod +x "$tmp/stray/$stub"
done
rm -f "$RXB_SUSPEND_TEST_MARKER"
for action in suspend hibernate; do
  status=0
  PATH="$tmp/stray" DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 RYOKU_WM=i3 XDG_SESSION_TYPE=x11 bash "$wrapper" "$action" 2>/dev/null || status=$?
  [[ "$status" == 69 ]] || {
    echo "stray WAYLAND_DISPLAY: $action exited $status, want fail-closed exit 69" >&2
    exit 1
  }
done
[[ ! -e "$RXB_SUSPEND_TEST_MARKER" ]] || {
  echo "stray WAYLAND_DISPLAY reached the Wayland suspend/hibernate path:" >&2
  cat "$RXB_SUSPEND_TEST_MARKER" >&2
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
PATH="$tmp/wayland" DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 RYOKU_WM= XDG_SESSION_TYPE=wayland bash "$wrapper" suspend
PATH="$tmp/wayland" DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 RYOKU_WM= XDG_SESSION_TYPE=wayland bash "$wrapper" hibernate
grep -Fqx 'ryoku-shell suspend' "$RXB_SUSPEND_TEST_MARKER"
grep -Fqx 'ryoku-shell lock' "$RXB_SUSPEND_TEST_MARKER"
grep -Fqx 'ryoku-host power hibernate' "$RXB_SUSPEND_TEST_MARKER"

echo "X11 suspend wrapper tests passed: X11 suspend/hibernate refusal, stray WAYLAND_DISPLAY fail-closed, and Wayland secure-path passthrough."
