#!/usr/bin/env bash
set -euo pipefail

for command in Xvfb i3 qs ryoku dbus-run-session timeout; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "RXB full-shell Xvfb test requires $command" >&2
    exit 127
  }
done

tmp="$(mktemp -d)"
home="$tmp/home"
runtime="$tmp/runtime"
mkdir -p "$home" "$runtime"
chmod 700 "$runtime"

export HOME="$home"
export XDG_CONFIG_HOME="$home/.config"
export XDG_CACHE_HOME="$home/.cache"
export XDG_DATA_HOME="$home/.local/share"
export XDG_STATE_HOME="$home/.local/state"
export XDG_RUNTIME_DIR="$runtime"
export RYOKU_X11_BRIDGE=1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=Ryoku
export RYOKU_WM=i3
export RYOKU_CONFIG_HOME="$XDG_CONFIG_HOME/ryoku-x11/ryoku-config"
export RYOKU_QUICKSHELL_CONFIG_HOME="$RYOKU_CONFIG_HOME/quickshell"
export QT_QPA_PLATFORM=xcb
export QT_QUICK_BACKEND=opengl
export QT_OPENGL=software
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
unset WAYLAND_DISPLAY SWAYSOCK I3SOCK

xvfb_pid=""
i3_pid=""
cleanup() {
  [[ -z "$i3_pid" ]] || kill "$i3_pid" 2>/dev/null || true
  [[ -z "$xvfb_pid" ]] || kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

Xvfb -displayfd 3 -screen 0 1600x900x24 -nolisten tcp -ac 3>"$tmp/display-number" >"$tmp/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 1 100); do
  [[ -s "$tmp/display-number" ]] && break
  kill -0 "$xvfb_pid" 2>/dev/null || { cat "$tmp/xvfb.log"; exit 1; }
  sleep 0.05
done
[[ -s "$tmp/display-number" ]] || { cat "$tmp/xvfb.log"; exit 1; }
display_number="$(tr -d '[:space:]' < "$tmp/display-number")"
[[ "$display_number" =~ ^[0-9]+$ ]] || { echo "Xvfb returned invalid display: $display_number" >&2; exit 1; }
export DISPLAY=":$display_number"

cat >"$tmp/i3.conf" <<'EOF'
font pango:monospace 8
focus_follows_mouse no
EOF
i3 -c "$tmp/i3.conf" >"$tmp/i3.log" 2>&1 &
i3_pid=$!
socket=""
for _ in $(seq 1 100); do
  socket="$(env -u SWAYSOCK -u I3SOCK i3 --get-socketpath 2>/dev/null || true)"
  if [[ -n "$socket" && -S "$socket" ]]; then break; fi
  sleep 0.05
done
[[ -n "$socket" && -S "$socket" ]] || { cat "$tmp/i3.log"; exit 1; }
export I3SOCK="$socket"

mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
shell_root="$RYOKU_QUICKSHELL_CONFIG_HOME/shell"

# Materialization and the QML runtime share one disposable D-Bus session, as
# they would in the real login session.
set +e
dbus-run-session -- bash -c '
  set -euo pipefail
  ryoku materialize
  [[ -f "$1/shell.qml" ]]
  timeout --signal=TERM --kill-after=3s 20s qs -p "$1"
' _ "$shell_root" >"$tmp/quickshell.log" 2>&1
status=$?
set -e

[[ -f "$shell_root/shell.qml" ]] || {
  cat "$tmp/quickshell.log"
  echo "Ryoku materializer did not create the RXB shell entry point: $shell_root/shell.qml" >&2
  find "$RYOKU_CONFIG_HOME" -maxdepth 4 -type f -print >&2 || true
  exit 1
}

if [[ $status -ne 124 && $status -ne 143 ]]; then
  cat "$tmp/quickshell.log"
  echo "Full Ryoku Quickshell shell exited unexpectedly (status $status)." >&2
  exit 1
fi

if grep -Eiq \
  'QQmlApplicationEngine failed to load|failed to load root|module .* is not installed|Type .* unavailable|No such file or directory.*\.qml' \
  "$tmp/quickshell.log"; then
  cat "$tmp/quickshell.log"
  echo "Full Ryoku shell reported a fatal QML load/import error." >&2
  exit 1
fi

echo "RXB full upstream Ryoku shell QML stayed alive under Xvfb + i3 for the smoke window."
