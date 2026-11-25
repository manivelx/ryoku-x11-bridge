#!/usr/bin/env bash
set -euo pipefail
trap 'status=$?; printf "test-rxb-session-lifecycle: failure at line %s: %s (status %s)\\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
socket_pid=""
xcompmgr_pid=""
crash_i3_pid=""
cleanup() {
  if [[ -n "$socket_pid" ]]; then kill "$socket_pid" >/dev/null 2>&1 || true; fi
  if [[ -n "$xcompmgr_pid" ]]; then kill -TERM "$xcompmgr_pid" >/dev/null 2>&1 || true; fi
  if [[ -n "$crash_i3_pid" ]]; then kill -TERM "$crash_i3_pid" >/dev/null 2>&1 || true; fi
  rm -rf "$tmp"
}
trap cleanup EXIT

home="$tmp/home"
config_home="$home/.config"
runtime="$tmp/runtime"
fakebin="$tmp/bin"
seed="$tmp/seed"
mkdir -p "$home" "$config_home/quickshell" "$runtime" "$fakebin" "$seed"
chmod 700 "$runtime"
printf 'I3SOCK="%s"\n' "$runtime/stale-session-socket" > "$runtime/ryoku-x11-session-42.env"
chmod 644 "$runtime/ryoku-x11-session-42.env"
export HOME="$home"
export XDG_CONFIG_HOME="$config_home"
export XDG_RUNTIME_DIR="$runtime"
export DISPLAY=:99
export XDG_SESSION_ID=42
export TEST_I3_SOCKET="$runtime/i3-ipc.sock"
export TEST_STALE_I3_SOCKET="$runtime/stale-i3-ipc.sock"
export I3SOCK="$TEST_STALE_I3_SOCKET"
export TEST_SYSTEMCTL_LOG="$tmp/systemctl.log"
export TEST_LOGINCTL_LOG="$tmp/loginctl.log"
export TEST_XCOMPMGR_LOG="$tmp/xcompmgr.log"
export TEST_XCOMPMGR_PID="$tmp/xcompmgr.pid"
export TEST_RYOKU_APPLY_LOG="$tmp/ryoku-apply.log"
export RYOKU_X11_SEED_DIR="$seed"
export PATH="$fakebin:$repo_root/payload/bin:$PATH"

printf 'preserve this desktop config\n' > "$config_home/quickshell/keep.qml"
mkdir -p "$config_home/ryoku-x11"
printf 'my own keybinds\n' > "$config_home/ryoku-x11/user.conf"
cat > "$seed/config" <<'EOF'
set $mod Mod4
include ~/.config/ryoku-x11/generated.conf
include ~/.config/ryoku-x11/user.conf
EOF
printf 'generated seed\n' > "$seed/generated.conf"
printf 'default user seed\n' > "$seed/user.conf"

cat > "$fakebin/loginctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_LOGINCTL_LOG"
if [[ "$*" == "show-session $XDG_SESSION_ID --property=User --value" ]]; then
  printf '%s\n' "${FAKE_LOGINCTL_USER:-$(id -u)}"
elif [[ "$*" == "show-session $XDG_SESSION_ID --property=Type --value" ]]; then
  printf '%s\n' "${FAKE_LOGINCTL_TYPE:-x11}"
elif [[ "$*" == "show-session $XDG_SESSION_ID --property=Class --value" ]]; then
  printf '%s\n' "${FAKE_LOGINCTL_CLASS:-user}"
else
  echo "unexpected loginctl request: $*" >&2
  exit 2
fi
SH
chmod +x "$fakebin/loginctl"

cat > "$fakebin/i3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --get-socketpath ]]; then
  printf '%s\n' "$TEST_I3_SOCKET"
  exit 0
fi
if [[ ${1:-} == -c ]]; then
  [[ -z ${I3SOCK:-} && -z ${SWAYSOCK:-} ]] || {
    echo "session wrapper leaked an inherited i3/Sway socket" >&2
    exit 1
  }
  [[ -f ${2:-} ]] || { echo "i3 config missing" >&2; exit 1; }
  if [[ ${FAKE_I3_HOLD:-0} == 1 ]]; then
    printf '%s\n' "$BASHPID" > "$FAKE_I3_HOLD_PID"
    exec sleep 60
  fi
  [[ ${2:-} == "$XDG_RUNTIME_DIR/ryoku-x11-i3-$XDG_SESSION_ID.conf" ]] || {
    echo "i3 must use the session-only runtime config copy" >&2
    exit 1
  }
  if [[ ${FAKE_I3_CRASH_HOLD:-0} == 1 ]]; then
    bash "$(command -v ryoku-x11-session-init)" || { echo "fake i3 session-init failed" >&2; exit 1; }
    printf '%s\n' "$BASHPID" > "$FAKE_I3_HOLD_PID"
    exec sleep 10
  fi
  grep -Fq "$XDG_CONFIG_HOME/ryoku-x11/generated.conf" "$2" || {
    echo "runtime i3 config did not resolve generated.conf through XDG_CONFIG_HOME" >&2
    exit 1
  }
  grep -Fq "$XDG_CONFIG_HOME/ryoku-x11/user.conf" "$2" || {
    echo "runtime i3 config did not resolve user.conf through XDG_CONFIG_HOME" >&2
    exit 1
  }
  [[ -s "$TEST_RYOKU_APPLY_LOG" ]] || {
    echo "Ryoku keybind apply must complete before i3 starts" >&2
    exit 1
  }
  exec bash "$(command -v ryoku-x11-session-init)"
fi
echo "unexpected fake i3 arguments: $*" >&2
exit 2
SH

cat > "$fakebin/ryoku-wm-i3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == apply ]] || { echo "unexpected provider command: $*" >&2; exit 2; }
[[ ${2:-} == "$RYOKU_CONFIG_HOME/ryoku/desktop.json" ]] || {
  echo "provider did not receive the isolated neutral desktop store path" >&2
  exit 1
}
printf 'apply\n' >> "$TEST_RYOKU_APPLY_LOG"
SH
chmod +x "$fakebin/ryoku-wm-i3"

cat > "$fakebin/ryoku" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == materialize ]] || exit 2
expected="$XDG_CONFIG_HOME/ryoku-x11/ryoku-config/quickshell"
expected_config="$XDG_CONFIG_HOME/ryoku-x11/ryoku-config"
[[ ${RYOKU_CONFIG_HOME:-} == "$expected_config" ]] || {
  echo "materializer did not receive the RXB config root" >&2
  exit 1
}
[[ ${RYOKU_QUICKSHELL_CONFIG_HOME:-} == "$expected" ]] || {
  echo "materializer did not receive the RXB Quickshell root" >&2
  exit 1
}
[[ -f "$XDG_CONFIG_HOME/quickshell/keep.qml" ]] || {
  echo "existing desktop Quickshell config disappeared before materialize" >&2
  exit 1
}
mkdir -p "$RYOKU_QUICKSHELL_CONFIG_HOME/shell"
printf 'isolated RXB shell config\n' > "$RYOKU_QUICKSHELL_CONFIG_HOME/shell/shell.qml"
SH

cat > "$fakebin/systemctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_SYSTEMCTL_LOG"
case "$*" in
  *"start ryoku-shell-x11@${XDG_SESSION_ID}.service ryogami-x11@${XDG_SESSION_ID}.service"*)
    env_file="$XDG_RUNTIME_DIR/ryoku-x11-session-${XDG_SESSION_ID}.env"
    [[ -f "$env_file" ]] || { echo "session EnvironmentFile missing" >&2; exit 1; }
    [[ "$(stat -c %a "$env_file")" == "600" ]] || {
      echo "session EnvironmentFile must be mode 0600" >&2
      exit 1
    }
    grep -Fqx "DISPLAY=\"$DISPLAY\"" "$env_file"
    grep -Fqx "XDG_SESSION_ID=\"$XDG_SESSION_ID\"" "$env_file"
    grep -Fqx "I3SOCK=\"$TEST_I3_SOCKET\"" "$env_file"
    grep -Fqx "XDG_CONFIG_HOME=\"$XDG_CONFIG_HOME\"" "$env_file"
    ;;
esac
SH

cat > "$fakebin/xcompmgr" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'started %s %s\n' "$BASHPID" "$*" >> "$TEST_XCOMPMGR_LOG"
printf '%s\n' "$BASHPID" > "$TEST_XCOMPMGR_PID"
exec python3 -c 'import ctypes,time; ctypes.CDLL(None).prctl(15, b"xcompmgr", 0, 0, 0); time.sleep(60)'
SH
chmod +x "$fakebin/xcompmgr"

for command in qs ryoku-shell; do
  cat > "$fakebin/$command" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done
chmod +x "$fakebin"/*

start_i3_socket_server() {
  python3 - "$TEST_I3_SOCKET" "$TEST_STALE_I3_SOCKET" <<'PY' &
import select, socket, sys
servers = []
for path in sys.argv[1:]:
    server = socket.socket(socket.AF_UNIX)
    server.bind(path)
    server.listen()
    servers.append(server)
while True:
    for server in select.select(servers, [], [])[0]:
        conn, _ = server.accept()
        conn.close()
PY
  socket_pid=$!
  for _ in $(seq 1 50); do
    [[ -S "$TEST_I3_SOCKET" ]] && break
    sleep 0.02
  done
  [[ -S "$TEST_I3_SOCKET" ]]
}
start_i3_socket_server

bash "$repo_root/payload/bin/ryoku-x11-session"

[[ ! -e "$runtime/ryoku-x11-session-42.env" ]]
grep -Fq -- '--user start ryoku-shell-x11@42.service ryogami-x11@42.service' "$TEST_SYSTEMCTL_LOG"
grep -Fqx 'include ~/.config/ryoku-x11/generated.conf' "$config_home/ryoku-x11/config"
grep -Fqx 'include ~/.config/ryoku-x11/user.conf' "$config_home/ryoku-x11/config"
[[ ! -e "$runtime/ryoku-x11-i3-42.conf" ]]
grep -Fqx 'generated seed' "$config_home/ryoku-x11/generated.conf"
grep -Fqx 'my own keybinds' "$config_home/ryoku-x11/user.conf"
grep -Fqx 'preserve this desktop config' "$config_home/quickshell/keep.qml"
grep -Fqx 'isolated RXB shell config' "$config_home/ryoku-x11/ryoku-config/quickshell/shell/shell.qml"
grep -Fq -- '--user start ryoku-x11-session.target' "$TEST_SYSTEMCTL_LOG"
grep -Fq -- '--user stop ryoku-x11-session.target' "$TEST_SYSTEMCTL_LOG"
grep -Fq 'started ' "$TEST_XCOMPMGR_LOG"
xcompmgr_pid="$(cat "$TEST_XCOMPMGR_PID")"
if kill -0 "$xcompmgr_pid" 2>/dev/null; then
  echo "RXB wrapper left its session-owned xcompmgr running after exit" >&2
  exit 1
fi
xcompmgr_pid=""
! grep -Fq 'import-environment' "$TEST_SYSTEMCTL_LOG"
grep -Fqx 'show-session 42 --property=User --value' "$TEST_LOGINCTL_LOG"
grep -Fqx 'show-session 42 --property=Type --value' "$TEST_LOGINCTL_LOG"
grep -Fqx 'show-session 42 --property=Class --value' "$TEST_LOGINCTL_LOG"

# Missing, foreign-user, TTY and greeter identities must be rejected before i3.
if env -u XDG_SESSION_ID bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted missing XDG_SESSION_ID" >&2; exit 1
fi
if FAKE_LOGINCTL_USER=99999 bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted another user's session" >&2; exit 1
fi
if FAKE_LOGINCTL_TYPE=tty bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a TTY session" >&2; exit 1
fi
if FAKE_LOGINCTL_CLASS=greeter bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a greeter session" >&2; exit 1
fi
if FAKE_LOGINCTL_CLASS=user-early bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted an X11 user-early session" >&2; exit 1
fi
if FAKE_LOGINCTL_CLASS=user-early bash "$repo_root/payload/bin/ryoku-x11-session-init" >/dev/null 2>&1; then
  echo "session initializer accepted an X11 user-early session" >&2; exit 1
fi

# A stale symlink at the predictable EnvironmentFile path must not be followed.
printf "do not overwrite this target\\n" > "$runtime/keep-me"
ln -s "$runtime/keep-me" "$runtime/ryoku-x11-session-42.env"
if bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session initializer accepted a symlinked EnvironmentFile" >&2
  exit 1
fi
[[ ! -L "$runtime/ryoku-x11-session-42.env" ]]
grep -Fqx "do not overwrite this target" "$runtime/keep-me"

# Replacing a stale hard link must not truncate the file it points to.
ln "$runtime/keep-me" "$runtime/ryoku-x11-session-42.env"
timeout 10s bash "$repo_root/payload/bin/ryoku-x11-session"
[[ ! -e "$runtime/ryoku-x11-session-42.env" ]]
grep -Fqx "do not overwrite this target" "$runtime/keep-me"

if DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a nested Wayland session" >&2
  exit 1
fi
if env -u DISPLAY bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a missing DISPLAY" >&2
  exit 1
fi

# A second graphical session must be rejected while the first holds the per-user lock.
hold_pid_file="$tmp/held-i3.pid"
FAKE_I3_HOLD=1 FAKE_I3_HOLD_PID="$hold_pid_file" \
  bash "$repo_root/payload/bin/ryoku-x11-session" >"$tmp/held-session.log" 2>&1 &
held_wrapper_pid=$!
for _ in $(seq 1 100); do
  [[ -s "$hold_pid_file" ]] && break
  kill -0 "$held_wrapper_pid" 2>/dev/null || break
  sleep 0.05
done
[[ -s "$hold_pid_file" ]] || { cat "$tmp/held-session.log" >&2; echo "first RXB session did not acquire its lock" >&2; exit 1; }
if bash "$repo_root/payload/bin/ryoku-x11-session" >"$tmp/second-session.log" 2>&1; then
  echo "a concurrent RXB graphical session was accepted" >&2
  exit 1
fi
grep -Fq "another RXB graphical session is already active" "$tmp/second-session.log"
kill -TERM "$(cat "$hold_pid_file")" 2>/dev/null || true
wait "$held_wrapper_pid" 2>/dev/null || true
# The lock file may remain, but flock must release it after a killed session.
bash "$repo_root/payload/bin/ryoku-x11-session"

# Simulate a wrapper SIGKILL after the X11 session and per-session services
# have started. A live old i3 socket must block a new session; once it is gone,
# the next login must stop old service instances and remove stale state.
crash_hold_pid_file="$tmp/crash-i3.pid"
FAKE_I3_HOLD=0 FAKE_I3_CRASH_HOLD=1 FAKE_I3_HOLD_PID="$crash_hold_pid_file" \
  bash "$repo_root/payload/bin/ryoku-x11-session" >"$tmp/crash-session.log" 2>&1 &
crash_wrapper_pid=$!
for _ in $(seq 1 100); do
  [[ -s "$crash_hold_pid_file" && -f "$runtime/ryoku-x11-session-42.env" ]] && break
  kill -0 "$crash_wrapper_pid" 2>/dev/null || break
  sleep 0.05
done
[[ -s "$crash_hold_pid_file" && -f "$runtime/ryoku-x11-session-42.env" ]] || {
  cat "$tmp/crash-session.log" >&2
  echo "crash simulation did not reach the running X11 session" >&2
  exit 1
}
crash_i3_pid="$(cat "$crash_hold_pid_file")"
old_compositor_pid="$(cat "$TEST_XCOMPMGR_PID")"
xcompmgr_pid="$old_compositor_pid"
session_wrapper_pid="$(cat "$runtime/ryoku-x11-session-42.pid")"
kill -KILL "$session_wrapper_pid" 2>/dev/null || true
for _ in $(seq 1 100); do
  kill -0 "$crash_wrapper_pid" 2>/dev/null || break
  sleep 0.05
done
if kill -0 "$crash_wrapper_pid" 2>/dev/null; then
  kill -KILL "$crash_wrapper_pid" 2>/dev/null || true
  echo "RXB session wrapper did not exit after its inner session process was SIGKILLed" >&2
  exit 1
fi
wait "$crash_wrapper_pid" 2>/dev/null || true

grep -Fxq "I3SOCK=\"$TEST_I3_SOCKET\"" "$runtime/ryoku-x11-session-42.env" || {
  echo "crash fixture did not leave the expected live i3 socket in the stale EnvironmentFile" >&2
  cat "$tmp/crash-session.log" >&2
  cat "$runtime/ryoku-x11-session-42.env" >&2
  exit 1
}
export XDG_SESSION_ID=43
[[ "$XDG_SESSION_ID" == "43" ]]
if timeout 10s bash "$repo_root/payload/bin/ryoku-x11-session" >"$tmp/stale-live-session.log" 2>&1; then
  echo "a new RXB session was accepted while a stale session still owned a live i3 socket" >&2
  cat "$tmp/stale-live-session.log" >&2
  cat "$runtime/ryoku-x11-session-42.env" >&2
  exit 1
fi
grep -Fq "previous RXB session 42 still owns a live i3 socket" "$tmp/stale-live-session.log"

kill -TERM "$crash_i3_pid" 2>/dev/null || true
crash_i3_pid=""
kill "$socket_pid" >/dev/null 2>&1 || true
for _ in $(seq 1 100); do
  kill -0 "$socket_pid" 2>/dev/null || break
  sleep 0.02
done
kill -KILL "$socket_pid" 2>/dev/null || true
wait "$socket_pid" 2>/dev/null || true
socket_pid=""
rm -f -- "$TEST_I3_SOCKET" "$TEST_STALE_I3_SOCKET"
TEST_I3_SOCKET="$runtime/i3-ipc-43.sock"
TEST_STALE_I3_SOCKET="$runtime/stale-i3-ipc-43.sock"
export TEST_I3_SOCKET TEST_STALE_I3_SOCKET
start_i3_socket_server

bash "$repo_root/payload/bin/ryoku-x11-session"
[[ ! -e "$runtime/ryoku-x11-session-42.env" ]]
[[ ! -e "$runtime/ryoku-x11-session-42.pid" ]]
[[ ! -e "$runtime/ryoku-x11-compositor-42.pid" ]]
grep -Fq -- '--user stop ryoku-shell-x11@42.service' "$TEST_SYSTEMCTL_LOG"
grep -Fq -- '--user stop ryogami-x11@42.service' "$TEST_SYSTEMCTL_LOG"
if kill -0 "$old_compositor_pid" 2>/dev/null; then
  old_compositor_state="$(ps -o stat= -p "$old_compositor_pid" 2>/dev/null || true)"
  [[ "$old_compositor_state" == Z* ]] || {
    echo "stale-session recovery left the old xcompmgr process running" >&2
    exit 1
  }
fi
xcompmgr_pid=""

echo "RXB X11 session lifecycle and logind isolation tests passed."
