#!/usr/bin/env bash
set -euo pipefail

for command in Xvfb i3 i3-msg xdotool qs xcompmgr ryogami pipewire wireplumber pw-cli ryoku ryoku-shell ryoku-wm-i3 ryoku-hub jq dbus-run-session timeout ps pgrep xrandr maim ryoku-cmd-grim python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "RXB full-shell Xvfb test requires $command" >&2
    exit 127
  }
done

tmp="$(mktemp -d)"
home="$tmp/home"
decoy_home="$tmp/decoy-real-home"
runtime="$tmp/runtime"
mkdir -p "$home" "$decoy_home" "$runtime"
chmod 700 "$runtime" "$decoy_home"
printf 'RXB decoy home sentinel\\n' > "$decoy_home/.rxb-home-sentinel"

assert_decoy_home_untouched() {
  local candidate="$1" unexpected
  [[ -f "$candidate/.rxb-home-sentinel" ]] || return 1
  [[ "$(cat "$candidate/.rxb-home-sentinel")" == "RXB decoy home sentinel" ]] || return 1
  unexpected="$(find "$candidate" -mindepth 1 ! -name .rxb-home-sentinel -print -quit)"
  [[ -z "$unexpected" ]]
}
mutation_probe="$tmp/decoy-mutation-probe"
mkdir -p "$mutation_probe"
printf 'RXB decoy home sentinel\\n' > "$mutation_probe/.rxb-home-sentinel"
touch "$mutation_probe/unexpected-write"
if assert_decoy_home_untouched "$mutation_probe"; then
  echo "decoy-home assertion failed to detect an injected mutation" >&2
  exit 1
fi

export HOME="$decoy_home"
export XDG_CONFIG_HOME="$home/.config"
export XDG_CACHE_HOME="$home/.cache"
export XDG_DATA_HOME="$home/.local/share"
export XDG_STATE_HOME="$home/.local/state"
# User media directories are also isolated; the shell's wallpaper and Stash
# surfaces must not create folders in the decoy real home.
export XDG_PICTURES_DIR="$home/Pictures"
export XDG_DOWNLOAD_DIR="$home/Downloads"
export XDG_RUNTIME_DIR="$runtime"
export RYOKU_X11_BRIDGE=1
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=Ryoku
export RYOKU_WM=i3
export RYOKU_CONFIG_HOME="$XDG_CONFIG_HOME/ryoku-x11/ryoku-config"
export RYOKU_QUICKSHELL_CONFIG_HOME="$RYOKU_CONFIG_HOME/quickshell"
export QT_QPA_PLATFORM=xcb
export TERMINAL=xterm
export QT_QUICK_BACKEND=opengl
export QT_OPENGL=software
export QML_IMPORT_TRACE=1
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
unset WAYLAND_DISPLAY SWAYSOCK I3SOCK

xvfb_pid=""
i3_pid=""
ryogami_pid=""
compositor_pid=""
cleanup_quickshell_processes() {
  local pass pids pid
  for pass in $(seq 1 50); do
    pids="$(ps -eo pid=,comm=,args= | awk -v root="$tmp" '$2 ~ /^(quickshell|qmlcachegen|qmlcachegen6)$/ && index($0, root) > 0 { print $1 }')"
    [[ -z "$pids" ]] && return 0
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
    done <<<"$pids"
    sleep 0.1
  done
  pids="$(ps -eo pid=,comm=,args= | awk -v root="$tmp" '$2 ~ /^(quickshell|qmlcachegen|qmlcachegen6)$/ && index($0, root) > 0 { print $1 }')"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill -KILL "$pid" 2>/dev/null || true
  done <<<"$pids"
  sleep 0.1
}
cleanup() {
  local status=$?
  trap - EXIT
  cleanup_quickshell_processes
  pkill -x xterm 2>/dev/null || true
  [[ -z "$compositor_pid" ]] || kill -TERM "$compositor_pid" 2>/dev/null || true
  [[ -z "$compositor_pid" ]] || wait "$compositor_pid" 2>/dev/null || true
  [[ -z "$ryogami_pid" ]] || kill -TERM "$ryogami_pid" 2>/dev/null || true
  [[ -z "$i3_pid" ]] || kill "$i3_pid" 2>/dev/null || true
  [[ -z "$xvfb_pid" ]] || kill "$xvfb_pid" 2>/dev/null || true
  [[ -z "$i3_pid" ]] || wait "$i3_pid" 2>/dev/null || true
  [[ -z "$xvfb_pid" ]] || wait "$xvfb_pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    rm -rf -- "$tmp" 2>/dev/null && return "$status"
    sleep 0.3
  done
  echo "warning: could not fully remove $tmp" >&2
  return "$status"
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

# Exercise the same XRender-only compositor the installed RXB wrapper starts.
# It must not depend on Picom, GLX, or the NVIDIA OpenGL stack.
xcompmgr -n >"$tmp/xcompmgr.log" 2>&1 &
compositor_pid=$!
sleep 0.2
kill -0 "$compositor_pid" 2>/dev/null || {
  cat "$tmp/xcompmgr.log" >&2
  echo "RXB xcompmgr XRender compositor failed to start under Xvfb." >&2
  exit 1
}

# Generate the original Ryoku keybinding catalogue before i3 starts, exactly
# as the installed session wrapper does. Validate the actual generated include
# with i3's own config parser before starting the compositor.
ryoku-wm-i3 apply "$RYOKU_CONFIG_HOME/ryoku/desktop.json" >/dev/null
grep -Eq '^bindsym Mod4\+Return exec .*ryoku-app terminal' "$XDG_CONFIG_HOME/ryoku-x11/generated.conf" || {
  echo "RXB generated config does not bind Super+Return to the terminal launcher." >&2
  grep -n 'Mod4.*Return' "$XDG_CONFIG_HOME/ryoku-x11/generated.conf" >&2 || true
  exit 1
}
grep -Eq '^bindsym Mod4\+t layout toggle tabbed split( |$)' "$XDG_CONFIG_HOME/ryoku-x11/generated.conf" || {
  echo "RXB generated config does not preserve Super+T as the tabbed-layout action." >&2
  grep -n 'Mod4.*t ' "$XDG_CONFIG_HOME/ryoku-x11/generated.conf" >&2 || true
  exit 1
}
cat >"$tmp/i3.conf" <<'EOF'
font pango:monospace 8
focus_follows_mouse no
set $mod Mod4
floating_modifier $mod
EOF
printf 'include "%s"\n' "$XDG_CONFIG_HOME/ryoku-x11/generated.conf" >>"$tmp/i3.conf"
i3 -C -c "$tmp/i3.conf" >"$tmp/i3-validate.log" 2>&1 || {
  cat "$tmp/i3-validate.log"
  echo "i3 rejected the generated RXB keybinding configuration." >&2
  exit 1
}
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

# Exercise the real Super+Return path end-to-end: generated i3 binding,
# RXB terminal selection and a live X11 terminal window.
xdotool key --clearmodifiers Super+Return
terminal_ready=0
for _ in $(seq 1 50); do
  if pgrep -x xterm >/dev/null 2>&1; then terminal_ready=1; break; fi
  sleep 0.1
done
if [[ "$terminal_ready" != 1 ]]; then
  cat "$tmp/i3.log" >&2
  echo "Super+Return did not launch the configured X11 terminal through ryoku-app." >&2
  exit 1
fi
pkill -x xterm || true
sleep 0.2

# Prove the pinned upstream WM seam discovers RXB as a live i3 provider.
# This exercises the same provider detection and caps path used by the Hub,
# not just the standalone RXB binary or a successful QML process launch.
provider_caps="$(ryoku-wm-i3 caps)"
jq -e '.name == "i3" and (.supports | index("workspaces") != null) and (.supports | index("windowGeometry") != null) and (.supports | index("persistentScreenCapture") == null)' <<<"$provider_caps" >/dev/null || {
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
jq -e 'type == "array" and length == 105 and all(.[]; (.default | length) > 0 and .kind != "custom") and any(.[]; (.unhonored | length) > 0) and any(.[]; .unhonored == null)' <<<"$provider_binds" >/dev/null || {
  echo "RXB did not expose all 105 shipped Ryoku binds with both supported and explicitly unsupported actions:" >&2
  printf '%s\n' "$provider_binds" >&2
  exit 1
}
echo "RXB exposes all 105 shipped Ryoku binds, with supported actions translated and unsupported actions explicitly marked."

echo "Pinned upstream Hub detected the live RXB i3 provider and capability manifest."

mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
shell_root="$RYOKU_QUICKSHELL_CONFIG_HOME/shell"

# Exercise the real upstream daemon, not a direct Quickshell invocation. The
# daemon performs setupQmlImportPath(), selects the isolated RXB shell tree,
# supervises Quickshell and owns the session IPC socket just as it does after login.
dbus-run-session -- bash -s -- "$shell_root" "$tmp" "$RYOKU_QUICKSHELL_CONFIG_HOME" "$home" <<'RXB_XVFB_TEST'
  set -euo pipefail
  shell_root="$1"
  tmp="$2"
  quickshell_root="$3"
  home="$4"

  # The visualizer's CavaFeed uses PipeWire. A bare Xvfb container has no
  # audio server, so opening the visualizer placement surface can terminate
  # Quickshell before its UI can be exercised. Start a real per-test PipeWire
  # server and session manager; no physical audio device is required.
  pipewire >"$tmp/pipewire.log" 2>&1 &
  pipewire_pid=$!
  wireplumber >"$tmp/wireplumber.log" 2>&1 &
  wireplumber_pid=$!
  cleanup_audio() {
    kill "$wireplumber_pid" "$pipewire_pid" 2>/dev/null || true
    wait "$wireplumber_pid" 2>/dev/null || true
    wait "$pipewire_pid" 2>/dev/null || true
  }
  for _ in $(seq 1 100); do
    [[ -S "$XDG_RUNTIME_DIR/pipewire-0" ]] && break
    if ! kill -0 "$pipewire_pid" 2>/dev/null; then
      cat "$tmp/pipewire.log" "$tmp/wireplumber.log" >&2
      echo "PipeWire exited before creating its runtime socket." >&2
      exit 1
    fi
    sleep 0.05
  done
  [[ -S "$XDG_RUNTIME_DIR/pipewire-0" ]] || {
    cat "$tmp/pipewire.log" "$tmp/wireplumber.log" >&2
    echo "PipeWire did not create its runtime socket." >&2
    exit 1
  }
  # The socket can appear before PipeWire has completed native-protocol
  # initialization. Probe the server itself before Quickshell creates its
  # CavaFeed clients; otherwise the first visualizer surface can race startup
  # and terminate the supervised shell with a transient connection error.
  pipewire_ready=0
  for _ in $(seq 1 100); do
    if pw-cli info 0 >/dev/null 2>&1; then
      pipewire_ready=1
      break
    fi
    if ! kill -0 "$pipewire_pid" 2>/dev/null; then
      cat "$tmp/pipewire.log" "$tmp/wireplumber.log" >&2
      echo "PipeWire exited before its native server became ready." >&2
      exit 1
    fi
    sleep 0.05
  done
  if [[ "$pipewire_ready" != 1 ]]; then
    cat "$tmp/pipewire.log" "$tmp/wireplumber.log" >&2
    echo "PipeWire socket exists but the native server did not become ready." >&2
    exit 1
  fi

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

  timeout --signal=TERM --kill-after=3s 120s ryoku-shell daemon >"$tmp/daemon.log" 2>&1 &
  daemon_pid=$!
  ryogami_pid=""
  cleanup_daemon() {
    local status=$?
    trap - EXIT
    ryoku-shell quit >/dev/null 2>&1 || true
    if kill -0 "$daemon_pid" 2>/dev/null; then
      kill -TERM "$daemon_pid" 2>/dev/null || true
    fi
    wait "$daemon_pid" 2>/dev/null || true
    if [[ -n "$ryogami_pid" ]]; then kill -TERM "$ryogami_pid" 2>/dev/null || true; wait "$ryogami_pid" 2>/dev/null || true; fi
    cleanup_audio
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

  # The old physical failure lost the wallpaper daemon when systemd broke the
  # session target ordering cycle. Start the real pinned Ryogami daemon against
  # the live RXB i3 provider and paint a high-entropy fixture so the captured
  # desktop must contain an actual wallpaper, not merely a black Xvfb root.
  mkdir -p "$home/Pictures/Wallpapers"
  wallpaper_fixture="$home/Pictures/Wallpapers/00-rxb-xvfb-fixture.png"
  python3 - "$wallpaper_fixture" <<'PY'
import struct
import sys
import zlib

width, height = 800, 450
raw = bytearray()
seed = 0x525842
for y in range(height):
    raw.append(0)  # PNG filter: None
    for x in range(width):
        seed = (1664525 * seed + 1013904223) & 0xffffffff
        r = (seed >> 24) & 0xff
        seed = (1664525 * seed + 1013904223) & 0xffffffff
        g = (seed >> 24) & 0xff
        seed = (1664525 * seed + 1013904223) & 0xffffffff
        b = (seed >> 24) & 0xff
        raw.extend((r, g, b))

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 1))
png += chunk(b"IEND", b"")
with open(sys.argv[1], "wb") as image:
    image.write(png)
PY
  ryogami >"$tmp/ryogami.log" 2>&1 &
  ryogami_pid=$!
  ryogami_ready=0
  for _ in $(seq 1 100); do
    if grep -q "ryogami: listening on" "$tmp/ryogami.log" 2>/dev/null; then ryogami_ready=1; break; fi
    if ! kill -0 "$ryogami_pid" 2>/dev/null; then
      cat "$tmp/ryogami.log" >&2
      echo "Ryogami wallpaper daemon exited before opening its X11 provider connection." >&2
      exit 1
    fi
    sleep 0.1
  done
  if [[ "$ryogami_ready" != 1 ]]; then
    cat "$tmp/ryogami.log" >&2
    echo "Ryogami wallpaper daemon did not become ready." >&2
    exit 1
  fi
  timeout 15s ryogami wallpaper set "$wallpaper_fixture" || {
    cat "$tmp/ryogami.log" >&2
    echo "Ryogami could not apply a wallpaper through the RXB i3 provider." >&2
    exit 1
  }
  sleep 2
  if grep -Eiq 'default wallpaper .*:|no active output|provider unavailable|no compositor' "$tmp/ryogami.log"; then
    cat "$tmp/ryogami.log" >&2
    echo "Ryogami reported an X11 wallpaper/provider failure." >&2
    exit 1
  fi

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

  # The Hub uses a separate upstream selector from the shell. Exercise
  # its real open/navigation IPC path and verify it resolves inside the RXB
  # Quickshell root rather than the user's shared XDG Quickshell directory.
  hub_root="$quickshell_root/hub"
  [[ -f "$hub_root/shell.qml" ]] || {
    echo "Ryoku materializer did not create the isolated Hub entrypoint: $hub_root/shell.qml" >&2
    find "$RYOKU_CONFIG_HOME" -maxdepth 5 -type f -name shell.qml -print >&2 || true
    exit 1
  }
  ryoku-shell hub open keybinds
  hub_ready=0
  for _ in $(seq 1 100); do
    if qs -p "$hub_root" ipc call nav section >/dev/null 2>&1; then
      hub_ready=1
      break
    fi
    sleep 0.1
  done
  if [[ "$hub_ready" != 1 ]]; then
    cat "$tmp/daemon.log"
    find "$XDG_RUNTIME_DIR/quickshell" -type f -name "log.log" -exec tail -n 100 {} \; 2>/dev/null || true
    echo "Ryoku Hub did not load and answer its navigation IPC from the isolated RXB config root." >&2
    exit 1
  fi
  qs -p "$hub_root" ipc call hub close >/dev/null 2>&1 || true
  echo "Ryoku Hub loaded and answered navigation IPC from the isolated RXB Quickshell root."

  # Exercise real shell IPC routes so the lazy QML surfaces are loaded at
  # runtime, not merely discovered by the static dependency graph.
  surface_smoke() {
    local command="$1" surface_id="$2" mode="$3" status
    echo "[shell-smoke] Opening $command surface."
    timeout 10s ryoku-shell "$command" >/dev/null
    sleep 1
    status="$(ryoku-shell status 2>/dev/null || true)"
    grep -q "^shell: running$" <<<"$status" || {
      cat "$tmp/daemon.log"
      cat "$shell_log"
      echo "Ryoku shell stopped while opening $command." >&2
      exit 1
    }
    if grep -Eiq 'QQmlApplicationEngine failed to load|failed to load root|module .* is not installed|Type .* unavailable|No such file or directory.*\.qml|Failed to load configuration|Expected token|ReferenceError|TypeError: .* is not a function' "$shell_log"; then
      cat "$shell_log" >&2
      echo "QML runtime error while opening $command." >&2
      exit 1
    fi
    if [[ "$mode" == toggle ]]; then
      timeout 10s ryoku-shell "$command" >/dev/null
    else
      timeout 10s qs -p "$shell_root" ipc call shell closeSurface "" "$surface_id" >/dev/null
    fi
    sleep 0.3
  }

  surface_smoke launcher launcher toggle
  surface_smoke settings settings toggle
  surface_smoke overview overview surface
  surface_smoke quicksettings sidebar-left surface
  surface_smoke clipboard clipboard toggle
  surface_smoke wallpaper-menu wallpaper surface
  surface_smoke cheatsheet cheatsheet surface
  surface_smoke tools tools surface
  surface_smoke ask ask surface
  surface_smoke "ask chat" "ask#chat" surface
  surface_smoke "ask tools" "ask#tools" surface
  surface_smoke screenshot screenshot surface
  surface_smoke visualizer visualizer surface
  surface_smoke visualizer-overlay visualizer-overlay surface
  surface_smoke visualizer-place visualizer-place surface

  # Load the original Ryoshot app in its own Quickshell process. On X11 it must
  # choose the maim fallback, freeze a real Xvfb frame and signal readiness;
  # this catches Wayland-only capture regressions outside the main shell tree.
  ryoshot_root="$quickshell_root/ryoshot"
  ryoshot_ready="$tmp/ryoshot-capture-ready"
  ryoshot_log="$tmp/ryoshot.log"
  [[ -f "$ryoshot_root/shell.qml" ]] || {
    echo "Materialized Ryoshot entrypoint is missing: $ryoshot_root/shell.qml" >&2
    exit 1
  }
  rm -f /tmp/ryoshot-fallback-*.png
  QML_IMPORT_PATH="$quickshell_root" QML2_IMPORT_PATH="$quickshell_root" \
    RYOSHOT_CAPTURE_READY_FILE="$ryoshot_ready" \
    qs -p "$ryoshot_root" >"$ryoshot_log" 2>&1 &
  ryoshot_pid=$!
  for _ in $(seq 1 120); do
    [[ -e "$ryoshot_ready" ]] && break
    if ! kill -0 "$ryoshot_pid" 2>/dev/null; then
      cat "$ryoshot_log"
      echo "Ryoshot exited before its X11 capture fallback became ready." >&2
      exit 1
    fi
    sleep 0.1
  done
  [[ -e "$ryoshot_ready" ]] || {
    cat "$ryoshot_log"
    echo "Ryoshot did not signal a frozen X11 capture frame." >&2
    exit 1
  }
  grep -q "using grim capture" "$ryoshot_log" || {
    cat "$ryoshot_log"
    echo "Ryoshot did not select the expected X11 capture fallback." >&2
    exit 1
  }
  ryoshot_frame="$(find /tmp -maxdepth 1 -type f -name 'ryoshot-fallback-*.png' -print -quit)"
  [[ -n "$ryoshot_frame" && -s "$ryoshot_frame" ]] || {
    cat "$ryoshot_log"
    echo "Ryoshot did not create its fallback screenshot image." >&2
    exit 1
  }
  python3 - "$ryoshot_frame" <<'PY'
import struct
import sys
with open(sys.argv[1], "rb") as image:
    header = image.read(24)
if header[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("Ryoshot fallback is not a PNG")
width, height = struct.unpack(">II", header[16:24])
if (width, height) != (1600, 900):
    raise SystemExit(f"Ryoshot fallback dimensions were {width}x{height}, expected 1600x900")
print(f"Ryoshot X11 fallback captured a {width}x{height} PNG.")
PY
  kill "$ryoshot_pid" 2>/dev/null || true
  wait "$ryoshot_pid" 2>/dev/null || true
  rm -f "$ryoshot_ready" "$ryoshot_frame"
  echo "Original Ryoshot QML app loaded and captured through the X11 fallback."

  # Exercise the X11 capture adapter with a real XRandR output. The installed
  # compatibility command must route to maim rather than the Wayland-only grim.
  capture_output="$(xrandr --query | awk '$2 == "connected" { print $1; exit }')"
  [[ -n "$capture_output" ]] || {
    echo "Xvfb did not expose an active XRandR output." >&2
    exit 1
  }
  capture_file="$tmp/rxb-x11-capture.png"
  ryoku-cmd-grim -o "$capture_output" "$capture_file"
  [[ -s "$capture_file" ]] || {
    echo "X11 capture adapter produced no screenshot." >&2
    exit 1
  }
  python3 - "$capture_file" <<'PY'
import struct
import sys

with open(sys.argv[1], "rb") as image:
    header = image.read(24)
if header[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("X11 capture adapter did not produce a PNG")
width, height = struct.unpack(">II", header[16:24])
if (width, height) != (1600, 900):
    raise SystemExit(f"X11 capture dimensions were {width}x{height}, expected 1600x900")
print(f"X11 capture adapter produced a {width}x{height} PNG.")
PY
  capture_size="$(stat -c %s "$capture_file")"
  if (( capture_size < 500000 )); then
    echo "Xvfb desktop capture is only ${capture_size} bytes; the wallpaper surface appears blank or was never painted." >&2
    exit 1
  fi
  echo "RXB X11 desktop rendered a wallpaper-backed frame (${capture_size} bytes)."
  if [[ -n ${RXB_ARTIFACT_DIR:-} ]]; then
    install -D -m 0644 "$capture_file" "$RXB_ARTIFACT_DIR/rxb-x11-shell-xvfb.png"
    echo "Saved Xvfb shell screenshot to $RXB_ARTIFACT_DIR/rxb-x11-shell-xvfb.png"
  fi

  # Exercise the real daemon lock dispatch on X11 and ensure status reflects
  # the live PAM locker, not a Wayland qylock proof marker.
  if ryoku-shell suspend >/dev/null 2>&1; then
    echo "RXB unexpectedly accepted suspend on X11 without a secure lock handoff." >&2
    exit 1
  fi
  # i3lock and XSecureLock can both be installed in the test container.
  # Count independent roots across both trusted PAM lockers, not only the
  # fallback implementation selected by older test images.
  active_locker_pids() {
    { pgrep -x i3lock || true; pgrep -x xsecurelock || true; } | sort -u
  }
  locker_roots() {
    local all pid ppid
    all="$(active_locker_pids | tr '\n' ' ')"
    for pid in $all; do
      ppid="$(awk '/^PPid:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null)" || continue
      [[ " $all " == *" $ppid "* ]] || printf '%s\n' "$pid"
    done
  }
  ryoku-shell lock >/dev/null
  locker_roots_before="$(locker_roots)"
  [[ -n "$locker_roots_before" && "$(wc -l <<<"$locker_roots_before")" == 1 ]] || {
    cat "$tmp/daemon.log"
    echo "X11 lock dispatch did not start exactly one independent PAM-backed X11 locker." >&2
    ps -eo pid,ppid,comm,args | grep -E '[i]3lock|[x]securelock' >&2 || true
    exit 1
  }
  ryoku-shell lock >/dev/null
  locker_roots_after="$(locker_roots)"
  [[ "$locker_roots_after" == "$locker_roots_before" ]] || {
    echo "Repeated lock request changed independent locker roots ($locker_roots_before -> $locker_roots_after)." >&2
    ps -eo pid,ppid,comm,args | grep -E '[i]3lock|[x]securelock' >&2 || true
    exit 1
  }
  # Terminate every process from this isolated test's trusted locker family.
  active_pids="$(active_locker_pids)"
  for pid in $active_pids; do kill "$pid" 2>/dev/null || true; done
  for _ in $(seq 1 50); do
    [[ -z "$(active_locker_pids)" ]] && break
    sleep 0.1
  done
  [[ -z "$(active_locker_pids)" ]] || {
    echo "PAM locker process family did not exit after termination." >&2
    ps -eo pid,ppid,comm,args | grep -E '[i]3lock|[x]securelock' >&2 || true
    exit 1
  }
  echo "X11 PAM locker start/idempotency/exit checks passed; X11 suspend failed closed."

  ryoku-shell quit
  wait "$daemon_pid"
  trap - EXIT
  echo "RXB full upstream Ryoku shell daemon stayed healthy under Xvfb + i3."
RXB_XVFB_TEST

assert_decoy_home_untouched "$decoy_home" || {
  find "$decoy_home" -mindepth 1 -maxdepth 3 -print >&2
  echo "RXB Xvfb session modified the decoy real home directory." >&2
  exit 1
}
echo "RXB decoy real-home isolation and mutation-detection checks passed."
echo "RXB full upstream Ryoku daemon/Xvfb acceptance passed."
