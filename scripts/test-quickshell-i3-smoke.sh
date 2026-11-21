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

Xvfb -displayfd 3 -screen 0 1280x720x24 -nolisten tcp -ac 3>"$tmp/display-number" >"$tmp/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 1 50); do
  [[ -s "$tmp/display-number" ]] && break
  kill -0 "$xvfb_pid" 2>/dev/null || { cat "$tmp/xvfb.log"; exit 1; }
  sleep 0.1
done
[[ -s "$tmp/display-number" ]] || { cat "$tmp/xvfb.log"; exit 1; }
display_number="$(tr -d '[:space:]' < "$tmp/display-number")"
[[ "$display_number" =~ ^[0-9]+$ ]] || { echo "Xvfb returned an invalid display number: $display_number" >&2; exit 1; }
export DISPLAY=":$display_number"
for _ in $(seq 1 50); do
  [[ -S "/tmp/.X11-unix/X$display_number" ]] && break
  sleep 0.1
done
[[ -S "/tmp/.X11-unix/X$display_number" ]] || { cat "$tmp/xvfb.log"; exit 1; }

cat >"$tmp/i3.conf" <<'EOF'
font pango:monospace 8
focus_follows_mouse no
EOF
i3 -c "$tmp/i3.conf" >"$tmp/i3.log" 2>&1 &
i3_pid=$!
socket=""
for _ in $(seq 1 50); do
  socket="$(env -u SWAYSOCK -u I3SOCK i3 --get-socketpath 2>/dev/null || true)"
  if [[ -n "$socket" && -S "$socket" ]]; then break; fi
  sleep 0.1
done
[[ -n "$socket" && -S "$socket" ]] || { cat "$tmp/i3.log"; exit 1; }
export I3SOCK="$socket"

mkdir -p "$tmp/qml"
cat >"$tmp/qml/shell.qml" <<'EOF'
import Quickshell
import Quickshell.I3
import QtQuick

ShellRoot {
    PanelWindow {
        id: smokePanel
        width: 12
        height: 12
        aboveWindows: true
        focusable: false
        visible: true
    }

    Connections {
        target: I3
        function onConnected() {
            if (!I3.socketPath) {
                console.error("RXB_I3_SMOKE connected without a socket path");
                Qt.exit(1);
                return;
            }
            console.log("RXB_I3_SMOKE socket=" + I3.socketPath
                        + " workspaceCount=" + I3.workspaces.values.length
                        + " panelAbove=" + smokePanel.aboveWindows);
            Qt.quit();
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            console.error("RXB_I3_SMOKE timed out waiting for Quickshell.I3");
            Qt.exit(1);
        }
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
