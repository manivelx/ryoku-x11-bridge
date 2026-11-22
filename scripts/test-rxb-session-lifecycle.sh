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
export HOME="$home"
export XDG_CONFIG_HOME="$config_home"
export XDG_RUNTIME_DIR="$runtime"
export DISPLAY=:99
export TEST_I3_SOCKET="$runtime/i3-ipc.sock"
export TEST_STALE_I3_SOCKET="$runtime/stale-i3-ipc.sock"
# Simulate a valid socket leaked by a previous desktop session; RXB must ignore it.
export I3SOCK="$TEST_STALE_I3_SOCKET"
export TEST_SYSTEMCTL_LOG="$tmp/systemctl.log"
export RYOKU_X11_SEED_DIR="$seed"
export PATH="$fakebin:$repo_root/payload/bin:$PATH"

printf 'preserve this desktop config\n' > "$config_home/quickshell/keep.qml"
mkdir -p "$config_home/ryoku-x11"
printf 'my own keybinds\n' > "$config_home/ryoku-x11/user.conf"
printf 'i3 config seed\n' > "$seed/config"
printf 'generated seed\n' > "$seed/generated.conf"
printf 'default user seed\n' > "$seed/user.conf"

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
  exec bash "$(command -v ryoku-x11-session-init)"
fi
echo "unexpected fake i3 arguments: $*" >&2
exit 2
SH

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
    grep -Fqx 'RYOKU_X11_BRIDGE="1"' "$env_file"
    grep -Fqx "RYOKU_CONFIG_HOME=\"$XDG_CONFIG_HOME/ryoku-x11/ryoku-config\"" "$env_file"
    grep -Fqx "RYOKU_QUICKSHELL_CONFIG_HOME=\"$XDG_CONFIG_HOME/ryoku-x11/ryoku-config/quickshell\"" "$env_file"
    grep -Fqx 'XDG_SESSION_TYPE="x11"' "$env_file"
    grep -Fqx 'DISPLAY=":99"' "$env_file"
    grep -Fqx "I3SOCK=\"$TEST_I3_SOCKET\"" "$env_file"
    grep -Fqx "XDG_CONFIG_HOME=\"$XDG_CONFIG_HOME\"" "$env_file"
    ;;
esac
SH

for command in ryoku-wm-i3 qs ryoku-shell; do
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
grep -Fqx 'i3 config seed' "$config_home/ryoku-x11/config"
grep -Fqx 'generated seed' "$config_home/ryoku-x11/generated.conf"
grep -Fqx 'my own keybinds' "$config_home/ryoku-x11/user.conf"
grep -Fqx 'preserve this desktop config' "$config_home/quickshell/keep.qml"
grep -Fqx 'isolated RXB shell config' "$config_home/ryoku-x11/ryoku-config/quickshell/shell/shell.qml"
grep -Fq -- '--user start ryoku-x11-session.target' "$TEST_SYSTEMCTL_LOG"
grep -Fq -- '--user stop ryoku-x11-session.target' "$TEST_SYSTEMCTL_LOG"
! grep -Fq 'import-environment' "$TEST_SYSTEMCTL_LOG"

if DISPLAY=:99 WAYLAND_DISPLAY=wayland-0 bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a nested Wayland session" >&2
  exit 1
fi
if env -u DISPLAY bash "$repo_root/payload/bin/ryoku-x11-session" >/dev/null 2>&1; then
  echo "session wrapper accepted a missing DISPLAY" >&2
  exit 1
fi

echo "RXB X11 session lifecycle and config isolation tests passed."
