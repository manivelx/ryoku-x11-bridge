#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
socket_pid=""
cleanup() {
  if [[ -n "$socket_pid" ]]; then kill "$socket_pid" >/dev/null 2>&1 || true; fi
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
printf "stale environment\n" > "$runtime/ryoku-x11-session.env"
chmod 644 "$runtime/ryoku-x11-session.env"
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
case "$*" in
  "show-session 42 --property=User --value") printf '%s\n' "${FAKE_LOGINCTL_USER:-$(id -u)}" ;;
  "show-session 42 --property=Type --value") printf '%s\n' "${FAKE_LOGINCTL_TYPE:-x11}" ;;
  "show-session 42 --property=Class --value") printf '%s\n' "${FAKE_LOGINCTL_CLASS:-user}" ;;
  *) echo "unexpected loginctl request: $*" >&2; exit 2 ;;
esac
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
  [[ ${2:-} == "$XDG_RUNTIME_DIR/ryoku-x11-i3.conf" ]] || {
    echo "i3 must use the session-only runtime config copy" >&2
    exit 1
  }
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
  *"start ryoku-x11-session.target"*)
    env_file="$XDG_RUNTIME_DIR/ryoku-x11-session.env"
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
exec sleep 60
SH
chmod +x "$fakebin/xcompmgr"

for command in qs ryoku-shell; do
  cat > "$fakebin/$command" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done
chmod +x "$fakebin"/*

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

bash "$repo_root/payload/bin/ryoku-x11-session"

[[ ! -e "$runtime/ryoku-x11-session.env" ]]
grep -Fqx 'include ~/.config/ryoku-x11/generated.conf' "$config_home/ryoku-x11/config"
grep -Fqx 'include ~/.config/ryoku-x11/user.conf' "$config_home/ryoku-x11/config"
[[ ! -e "$runtime/ryoku-x11-i3.conf" ]]
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
ln -s "$runtime/keep-me" "$runtime/ryoku-x11-session.env"
if bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session initializer accepted a symlinked EnvironmentFile" >&2
  exit 1
fi
[[ ! -L "$runtime/ryoku-x11-session.env" ]]
grep -Fqx "do not overwrite this target" "$runtime/keep-me"

# Replacing a stale hard link must not truncate the file it points to.
ln "$runtime/keep-me" "$runtime/ryoku-x11-session.env"
bash "$repo_root/payload/bin/ryoku-x11-session"
[[ ! -e "$runtime/ryoku-x11-session.env" ]]
grep -Fqx "do not overwrite this target" "$runtime/keep-me"

if DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a nested Wayland session" >&2
  exit 1
fi
if env -u DISPLAY bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a missing DISPLAY" >&2
  exit 1
fi

echo "RXB X11 session lifecycle and logind isolation tests passed."
