#!/usr/bin/env bash
set -euo pipefail

upstream="${1:?usage: test-rxb-terminal-launcher.sh /path/to/pinned/ryoku}"
launcher="$upstream/ryoku/shell/scripts/ryoku-app"
[[ -x "$launcher" ]] || { echo "patched ryoku-app is missing or not executable: $launcher" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fakebin="$tmp/bin"
mkdir -p "$fakebin" "$tmp/config"
ln -s "$(command -v bash)" "$fakebin/bash"
ln -s /bin/sh "$fakebin/sh"

make_terminal() {
  local name="$1"
  cat > "$fakebin/$name" <<'SH'
#!/bin/sh
printf '%s\n' "${0##*/}" > "$RXB_TERMINAL_TEST_RESULT"
SH
  chmod +x "$fakebin/$name"
}

export RXB_TERMINAL_TEST_RESULT="$tmp/result"
export XDG_CONFIG_HOME="$tmp/config"
export DISPLAY=:99
export WAYLAND_DISPLAY=

# An explicit, installed TERMINAL wins over the RXB fallback order.
make_terminal foot
make_terminal konsole
PATH="$fakebin" RYOKU_X11_BRIDGE=1 TERMINAL=foot "$BASH" "$launcher" terminal
[[ "$(cat "$RXB_TERMINAL_TEST_RESULT")" == foot ]]

# Without an explicit preference, an installed Konsole is selected before xterm.
rm -f "$RXB_TERMINAL_TEST_RESULT"
make_terminal xterm
PATH="$fakebin" RYOKU_X11_BRIDGE=1 TERMINAL= "$BASH" "$launcher" terminal
[[ "$(cat "$RXB_TERMINAL_TEST_RESULT")" == konsole ]]

# If only xterm is installed, it is selected rather than attempting missing Kitty.
rm -f "$RXB_TERMINAL_TEST_RESULT" "$fakebin/konsole"
PATH="$fakebin" RYOKU_X11_BRIDGE=1 TERMINAL= "$BASH" "$launcher" terminal
[[ "$(cat "$RXB_TERMINAL_TEST_RESULT")" == xterm ]]

# Wayland keeps upstream's Kitty fallback unchanged.
rm -f "$RXB_TERMINAL_TEST_RESULT"
make_terminal kitty
PATH="$fakebin" RYOKU_X11_BRIDGE=0 DISPLAY= WAYLAND_DISPLAY=wayland-0 TERMINAL= "$BASH" "$launcher" terminal
[[ "$(cat "$RXB_TERMINAL_TEST_RESULT")" == kitty ]]

# No available X11 terminal must fail with a notification, not a dead exec.
rm -f "$RXB_TERMINAL_TEST_RESULT" "$fakebin/kitty" "$fakebin/foot" "$fakebin/xterm"
cat > "$fakebin/notify-send" <<'SH'
#!/bin/sh
printf notified > "$RXB_TERMINAL_TEST_RESULT"
SH
chmod +x "$fakebin/notify-send"
status=0
PATH="$fakebin" RYOKU_X11_BRIDGE=1 TERMINAL= "$BASH" "$launcher" terminal || status=$?
[[ "$status" == 1 ]]
[[ "$(cat "$RXB_TERMINAL_TEST_RESULT")" == notified ]]

echo "RXB X11 terminal selection tests passed; upstream Wayland fallback preserved."
