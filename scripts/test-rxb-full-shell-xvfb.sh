#!/usr/bin/env bash
set -euo pipefail

for command in Xvfb i3 qs ryoku ryoku-shell ryoku-wm-i3 ryoku-hub jq dbus-run-session timeout; do
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
export QML_IMPORT_TRACE=1
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
set $mod Mod4
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

# Prove the pinned upstream WM seam discovers RXB as a live i3 provider.
# This exercises the same provider detection and caps path used by the Hub,
# not just the standalone RXB binary or a successful QML process launch.
provider_caps="$(ryoku-wm-i3 caps)"
jq -e '.name == "i3" and (.supports | index("workspaces") != null)' <<<"$provider_caps" >/dev/null || {
  echo "RXB i3 provider returned an invalid capability manifest:" >&2
  printf '%s\n' "$provider_caps" >&2
  exit 1
}
provider_state="$(ryoku-wm-i3 state)"
jq -e '(.outputs | type == "array") and (.workspaces | type == "array") and (.windows | type == "array")' <<<"$provider_state" >/dev/null || {
  echo "RXB i3 provider returned an invalid state snapshot:" >&2
  printf '%s\n' "$provider_state" >&2
  exit 1
}
hub_providers="$(ryoku-hub wm list)"
jq -e 'any(.[]; .name == "i3" and .active == true and .caps.name == "i3" and (.caps.supports | index("workspaces") != null))' <<<"$hub_providers" >/dev/null || {
  echo "Pinned upstream Hub did not detect the live RXB i3 provider:" >&2
  printf '%s\n' "$hub_providers" >&2
  exit 1
}
provider_binds="$(ryoku-wm-i3 binds)"
jq -e 'type == "array" and length == 0' <<<"$provider_binds" >/dev/null || {
  echo "RXB introduced a default/custom binding into the empty test i3 config:" >&2
  printf '%s\n' "$provider_binds" >&2
  exit 1
}
echo "RXB leaves the i3 bind catalogue empty when no bindings are declared."

echo "Pinned upstream Hub detected the live RXB i3 provider and capability manifest."

mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
shell_root="$RYOKU_QUICKSHELL_CONFIG_HOME/shell"

# Exercise the real upstream daemon, not a direct Quickshell invocation. The
# daemon performs setupQmlImportPath(), selects the isolated RXB shell tree,
# supervises Quickshell and owns the session IPC socket just as it does after login.
dbus-run-session -- bash -c '
  set -euo pipefail
  shell_root="$1"
  tmp="$2"
  quickshell_root="$3"

  timeout --signal=TERM --kill-after=3s 30s ryoku materialize
  [[ -f "$shell_root/shell.qml" ]] || {
    echo "Ryoku materializer did not create $shell_root/shell.qml" >&2
    find "$RYOKU_CONFIG_HOME" -maxdepth 4 -type f -print >&2 || true
    exit 1
  }

  for module in \
    shell/services/qmldir \
    shell/modules/phone/qmldir \
    stage/qmldir \
    stage/modules/common/qmldir; do
    [[ -f "$quickshell_root/$module" ]] || {
      echo "Required upstream QML module is missing: $quickshell_root/$module" >&2
      find "$quickshell_root" -maxdepth 4 -type f -name qmldir -print >&2 || true
      exit 1
    }
  done
  touch "$tmp/materialized"

  timeout --signal=TERM --kill-after=3s 35s ryoku-shell daemon >"$tmp/daemon.log" 2>&1 &
  daemon_pid=$!
  cleanup_daemon() {
    local status=$?
    trap - EXIT
    ryoku-shell quit >/dev/null 2>&1 || true
    if kill -0 "$daemon_pid" 2>/dev/null; then
      kill -TERM "$daemon_pid" 2>/dev/null || true
    fi
    wait "$daemon_pid" 2>/dev/null || true
    exit "$status"
  }
  trap cleanup_daemon EXIT

  for _ in $(seq 1 100); do
    if ryoku-shell ping >/dev/null 2>&1; then break; fi
    if ! kill -0 "$daemon_pid" 2>/dev/null; then
      cat "$tmp/daemon.log"
      echo "ryoku-shell daemon exited before its IPC socket became ready." >&2
      exit 1
    fi
    sleep 0.1
  done
  ryoku-shell ping >/dev/null || {
    cat "$tmp/daemon.log"
    echo "ryoku-shell daemon did not answer ping." >&2
    exit 1
  }

  status=""
  for _ in $(seq 1 100); do
    status="$(ryoku-shell status 2>/dev/null || true)"
    grep -q "^shell: running$" <<<"$status" && break
    sleep 0.1
  done
  grep -q "^shell: running$" <<<"$status" || {
    cat "$tmp/daemon.log"
    cat "$XDG_STATE_HOME/ryoku/surfaces/shell.log" 2>/dev/null || true
    echo "Ryoku daemon did not keep the full shell component running." >&2
    exit 1
  }

  sleep 3
  status="$(ryoku-shell status 2>/dev/null || true)"
  grep -q "^shell: running$" <<<"$status" || {
    cat "$tmp/daemon.log"
    cat "$XDG_STATE_HOME/ryoku/surfaces/shell.log" 2>/dev/null || true
    echo "Ryoku shell component exited during the daemon smoke window." >&2
    exit 1
  }

  shell_log="$XDG_STATE_HOME/ryoku/surfaces/shell.log"
  [[ -s "$shell_log" ]] || {
    cat "$tmp/daemon.log"
    echo "Ryoku daemon did not create its supervised shell log." >&2
    exit 1
  }
  if grep -Eiq \
    "QQmlApplicationEngine failed to load|failed to load root|module .* is not installed|Type .* unavailable|No such file or directory.*\\.qml|Failed to load configuration|Expected token" \
    "$shell_log"; then
    cat "$shell_log"
    echo "Ryoku daemon reported a fatal QML load/import error." >&2
    exit 1
  fi

  ryoku-shell quit
  wait "$daemon_pid"
  trap - EXIT
  echo "RXB full upstream Ryoku shell daemon stayed healthy under Xvfb + i3."
' _ "$shell_root" "$tmp" "$RYOKU_QUICKSHELL_CONFIG_HOME"

echo "RXB full upstream Ryoku daemon/Xvfb acceptance passed."
