#!/usr/bin/env bash
set -euo pipefail

for command in Xvfb i3 qs timeout; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Quickshell/i3 smoke test requires $command" >&2
    exit 127
  }
done

tmp="$(mktemp -d)"
runtime="$tmp/runtime"
mkdir -m 700 "$runtime"
export XDG_RUNTIME_DIR="$runtime"
export DISPLAY=:99
export QT_QPA_PLATFORM=xcb
export QT_QUICK_BACKEND=software
export QT_OPENGL=software

xvfb_pid=""
i3_pid=""
cleanup() {
  [[ -z "$i3_pid" ]] || kill "$i3_pid" 2>/dev/null || true
  [[ -z "$xvfb_pid" ]] || kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

Xvfb "$DISPLAY" -screen 0 1280x720x24 -nolisten tcp -ac >"$tmp/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 1 50); do
  if [[ -S /tmp/.X11-unix/X99 ]]; then break; fi
  sleep 0.1
done
[[ -S /tmp/.X11-unix/X99 ]] || { cat "$tmp/xvfb.log"; exit 1; }

cat >"$tmp/i3.conf" <<'EOF'
font pango:monospace 8
focus_follows_mouse no
EOF
i3 -c "$tmp/i3.conf" >"$tmp/i3.log" 2>&1 &
i3_pid=$!
socket=""
for _ in $(seq 1 50); do
  socket="$(i3 --get-socketpath 2>/dev/null || true)"
  if [[ -n "$socket" && -S "$socket" ]]; then break; fi
  sleep 0.1
done
[[ -n "$socket" && -S "$socket" ]] || { cat "$tmp/i3.log"; exit 1; }
export I3SOCK="$socket"

mkdir -p "$tmp/qml"
cat >"$tmp/qml/shell.qml" <<'EOF'
import Quickshell
import Quickshell.I3

ShellRoot {
    PanelWindow {
        id: smokePanel
        width: 12
        height: 12
        aboveWindows: true
        focusable: false
        visible: true
    }

    Component.onCompleted: {
        console.log("RXB_I3_SMOKE socket=" + I3.socketPath
                    + " workspaceCount=" + I3.workspaces.count
                    + " panelAbove=" + smokePanel.aboveWindows);
        Qt.quit();
    }
}
EOF

if ! timeout 20s qs -p "$tmp/qml" >"$tmp/qs.log" 2>&1; then
  cat "$tmp/qs.log"
  exit 1
fi
grep -q "RXB_I3_SMOKE socket=" "$tmp/qs.log" || {
  cat "$tmp/qs.log"
  echo "Quickshell did not report a successful I3 module initialization." >&2
  exit 1
}
echo "Quickshell $(qs --version 2>&1 | head -n1) I3 module smoke test passed."
