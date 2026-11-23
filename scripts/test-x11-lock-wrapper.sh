#!/usr/bin/env bash
# Unit-level tests for payload/bin/ryoku-x11-lock.
#
# These tests use stand-in lockers, so they prove the WRAPPER's logic (trusted
# locker directory, per-display lock lifetime, idempotency, spoof rejection,
# session detection). They do not prove PAM authentication; that is covered by
# scripts/test-x11-lock-pam-xephyr.sh against the real lockers.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() {
  exec 8>&-
  # Stand-in lockers are copies of cat started from this tree.
  pkill -KILL -f -- "$tmp/" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# The wrapper resolves lockers only from the literal "locker_dir=/usr/bin"
# line. Tests substitute that single line; they assert the substitution took
# effect so they cannot silently exercise the real /usr/bin.
lockdir="$tmp/trusted"
helperdir="$tmp/xsecurelock-lib"
mkdir -p "$lockdir" "$helperdir" "$tmp/runtime"
chmod 700 "$tmp/runtime"
for helper in auth_x11 authproto_pam; do
  printf '#!/bin/sh\nexit 0\n' > "$helperdir/$helper"
  chmod 0755 "$helperdir/$helper"
done
grep -qx 'locker_dir=/usr/bin' "$root/payload/bin/ryoku-x11-lock" || fail "wrapper no longer defines locker_dir=/usr/bin"
sed -e "s|^locker_dir=/usr/bin\$|locker_dir=$lockdir|" \
  -e "s|/usr/lib/xsecurelock|$helperdir|g" \
  "$root/payload/bin/ryoku-x11-lock" >"$tmp/ryoku-x11-lock"
grep -qx "locker_dir=$lockdir" "$tmp/ryoku-x11-lock" || fail "could not point the wrapper at the test locker directory"
grep -qx "  local auth_module=$helperdir/auth_x11" "$tmp/ryoku-x11-lock" || fail "could not point XSecureLock auth helper at the test fixture"
bash -n "$tmp/ryoku-x11-lock"
wrapper="$tmp/ryoku-x11-lock"
export RXB_LOCK_TEST_MARKER="$tmp/marker"

# Run the wrapper with a clean, explicit session environment.
run_wrapper() { # display [env assignments...]
  local display="$1"; shift
  ${RXB_RUN_PREFIX:-} env -i HOME="$tmp" PATH="${RXB_TEST_PATH:-/usr/bin:/bin}" XDG_RUNTIME_DIR="$tmp/runtime" \
    RXB_LOCK_TEST_MARKER="$RXB_LOCK_TEST_MARKER" DISPLAY="$display" "$@" bash "$wrapper"
}

wait_until() { # seconds command...
  local limit=$(( $1 * 20 )); shift
  for _ in $(seq 1 "$limit"); do
    if "$@"; then return 0; fi
    sleep 0.05
  done
  return 1
}

# Real binaries (not scripts) so /proc/PID/exe is the file we copied.
copy_binary() { cp "$(command -v "$1")" "$2" && chmod +x "$2"; }
count_lockers() { # directory
  local n=0 p exe
  for p in /proc/[0-9]*; do
    [[ -O $p ]] || continue
    exe=$(readlink "$p/exe" 2>/dev/null) || continue
    [[ $exe == "$1/xsecurelock" ]] && n=$((n + 1))
  done
  echo "$n"
}
no_lockers_in() { [[ "$(count_lockers "$1")" == 0 ]]; }
has_lockers() { [[ "$(count_lockers "$1")" -ge "$2" ]]; }

# 1. Wayland: preserved qylock passthrough.
mkdir -p "$tmp/wayland-bin"
printf '#!/bin/sh\nprintf qylock > "$RXB_LOCK_TEST_MARKER"\n' >"$tmp/wayland-bin/ryoku-qylock-lock"
chmod +x "$tmp/wayland-bin/ryoku-qylock-lock"
RXB_TEST_PATH="$tmp/wayland-bin:/usr/bin:/bin" run_wrapper "" WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == qylock ]] || fail "Wayland lock wrapper did not preserve qylock"

# 2. Locker selection: XSecureLock first, i3lock fallback with exact arguments.
cat >"$lockdir/xsecurelock" <<'FAKE_XSECURELOCK'
#!/bin/sh
printf '%s|%s|%s|%s|%s|%s|%s\n' \
  "${XSECURELOCK_AUTH:-}" "${XSECURELOCK_AUTHPROTO:-}" \
  "${XSECURELOCK_SAVER:-}" "${XSECURELOCK_SWITCH_USER_COMMAND:-}" \
  "${XSECURELOCK_PAM_SERVICE:-}" "${XSECURELOCK_NO_COMPOSITE:-}" \
  "${XSECURELOCK_KEY_FOO_COMMAND:-}" > "$RXB_LOCK_TEST_MARKER"
FAKE_XSECURELOCK
printf '#!/bin/sh\n[ "$1" = "--nofork" ] && [ "$2" = "--color=000000" ] || exit 1\nprintf i3lock > "$RXB_LOCK_TEST_MARKER"\n' >"$lockdir/i3lock"
chmod +x "$lockdir/xsecurelock" "$lockdir/i3lock"
rm -f "$RXB_LOCK_TEST_MARKER"
run_wrapper :90 \
  XSECURELOCK_AUTH=auth_htpasswd \
  XSECURELOCK_AUTHPROTO=authproto_htpasswd \
  XSECURELOCK_SAVER=saver_mpv \
  XSECURELOCK_SWITCH_USER_COMMAND=/tmp/attacker-command \
  XSECURELOCK_PAM_SERVICE=attacker-service \
  XSECURELOCK_NO_COMPOSITE=1 \
  XSECURELOCK_KEY_FOO_COMMAND=/tmp/attacker-command
expected_xsecurelock_env="$helperdir/auth_x11|$helperdir/authproto_pam|||||"
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == "$expected_xsecurelock_env" ]] || {
  fail "XSecureLock environment was not sanitized to the absolute PAM helper paths: $(cat "$RXB_LOCK_TEST_MARKER")"
}
rm "$lockdir/xsecurelock" "$RXB_LOCK_TEST_MARKER"
run_wrapper :91
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == i3lock ]] || fail "i3lock fallback was not selected"

# 3. A stray WAYLAND_DISPLAY inside an RXB X11 session must stay on X11.
rm -f "$RXB_LOCK_TEST_MARKER"
RXB_TEST_PATH="$tmp/wayland-bin:/usr/bin:/bin" run_wrapper :92 WAYLAND_DISPLAY=wayland-0 RYOKU_WM=i3 XDG_SESSION_TYPE=x11
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == i3lock ]] || fail "stray WAYLAND_DISPLAY routed an X11 session to qylock"

# 4. Lockers are never taken from PATH.
mkdir -p "$tmp/hijack"
printf '#!/bin/sh\nprintf hijacked > "$RXB_LOCK_TEST_MARKER"\n' >"$tmp/hijack/xsecurelock"
cp "$tmp/hijack/xsecurelock" "$tmp/hijack/i3lock"
chmod +x "$tmp/hijack/xsecurelock" "$tmp/hijack/i3lock"
rm -f "$RXB_LOCK_TEST_MARKER"
RXB_TEST_PATH="$tmp/hijack:/usr/bin:/bin" run_wrapper :93
[[ "$(cat "$RXB_LOCK_TEST_MARKER")" == i3lock ]] || fail "a locker from PATH was run instead of the trusted one"
mv "$lockdir/i3lock" "$tmp/i3lock.saved"
rm -f "$RXB_LOCK_TEST_MARKER"
status=0
RXB_TEST_PATH="$tmp/hijack:/usr/bin:/bin" run_wrapper :94 2>/dev/null || status=$?
[[ "$status" == 127 ]] || fail "with no trusted locker the wrapper exited $status, want 127"
[[ ! -e "$RXB_LOCK_TEST_MARKER" ]] || fail "a PATH locker ran although no trusted locker is installed"

# 5. Required environment is enforced.
status=0
env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$tmp/runtime" bash "$wrapper" 2>/dev/null || status=$?
[[ "$status" == 69 ]] || fail "missing DISPLAY exit = $status, want 69"
status=0
env -i PATH=/usr/bin:/bin DISPLAY=:95 XDG_RUNTIME_DIR="$tmp/does-not-exist" bash "$wrapper" 2>/dev/null || status=$?
[[ "$status" == 69 ]] || fail "missing runtime dir exit = $status, want 69"

# 6. Lock lifetime, idempotency and display normalisation with a real binary
# standing in for the locker: cat blocks reading a fifo until the test closes it.
rm -rf "$lockdir" && mkdir -p "$lockdir"
copy_binary bash "$lockdir/xsecurelock"
mkfifo "$tmp/fifo"
run_wrapper :101 <"$tmp/fifo" >/dev/null &
first_pid=$!
exec 8>"$tmp/fifo"
wait_until 5 has_lockers "$lockdir" 1 || fail "the first lock request did not start a locker"
lock_file="$tmp/runtime/ryoku-x11-lock/_101.lock"
[[ -e "$lock_file" ]] || fail "per-display lock file missing: $lock_file"

status=0; run_wrapper :101 </dev/null >/dev/null || status=$?
[[ "$status" == 0 ]] || fail "repeated request on a locked display exited $status, want 0"
# A spelling of the same display (":101.0") must hit the same lock. A locker
# stacked by mistake would block forever on this never-closing fifo, so the
# request is run under a timeout.
mkfifo "$tmp/fifo-dot"
exec 7<>"$tmp/fifo-dot"
status=0; RXB_RUN_PREFIX="timeout 5" run_wrapper :101.0 <"$tmp/fifo-dot" >/dev/null || status=$?
[[ "$status" == 0 ]] || fail "':101.0' request exited $status, want 0 (a second locker was started or the lock was not shared)"
exec 7>&-
[[ "$(count_lockers "$lockdir")" == 1 ]] || fail "repeated lock requests stacked another locker"

# Killing the wrapper must not release the lock: the locker inherits it.
kill -KILL "$first_pid"
wait "$first_pid" 2>/dev/null || true
[[ "$(count_lockers "$lockdir")" == 1 ]] || fail "the locker did not survive its wrapper"
if flock -n "$lock_file" true; then fail "the lock was released while the locker was still running"; fi
status=0; run_wrapper :101 </dev/null >/dev/null || status=$?
[[ "$status" == 0 && "$(count_lockers "$lockdir")" == 1 ]] || fail "request after wrapper death stacked a locker or failed (exit $status)"

# Closing the locker releases the lock, and a new request can lock again.
exec 8>&-
wait_until 5 test "$(count_lockers "$lockdir")" == 0 || fail "the locker did not exit"
wait_until 5 flock -n "$lock_file" true || fail "the lock was not released after the locker exited"
mkfifo "$tmp/fifo2"
run_wrapper :101 <"$tmp/fifo2" >/dev/null &
second_pid=$!
exec 8>"$tmp/fifo2"
wait_until 5 has_lockers "$lockdir" 1 || fail "could not lock again after the previous locker exited"
exec 8>&-
wait "$second_pid" || true

# 6b. A wrapper stopped with SIGTERM must leave a still-running locker
# verifiable (its record must survive), so later requests stay idempotent.
rm -rf "$lockdir" && mkdir -p "$lockdir"
copy_binary bash "$lockdir/xsecurelock"
mkfifo "$tmp/fifo-term"
run_wrapper :106 <"$tmp/fifo-term" >/dev/null &
term_pid=$!
exec 8>"$tmp/fifo-term"
wait_until 5 has_lockers "$lockdir" 1 || fail "SIGTERM case: locker did not start"
sleep 0.3
kill -TERM "$term_pid"
wait "$term_pid" 2>/dev/null || true
[[ "$(count_lockers "$lockdir")" == 1 ]] || fail "SIGTERM case: locker did not survive its wrapper"
status=0; timeout 8 bash -c "$(declare -f run_wrapper); tmp='$tmp'; wrapper='$wrapper'; RXB_LOCK_TEST_MARKER='$RXB_LOCK_TEST_MARKER'; run_wrapper :106 </dev/null >/dev/null" || status=$?
[[ "$status" == 0 ]] || fail "SIGTERM case: request after a signalled wrapper exited $status (record lost)"
[[ "$(count_lockers "$lockdir")" == 1 ]] || fail "SIGTERM case: request stacked a locker"
exec 8>&-
wait_until 5 no_lockers_in "$lockdir" || true

# 7. No false success: the lock is held but nothing verified is locking.
# (a) a plain holder, (b) a binary NAMED xsecurelock outside the trusted
# directory with the right DISPLAY (process-name spoofing).
for case_name in plain spoof; do
  display=":10$([[ $case_name == plain ]] && echo 2 || echo 3)"
  key="_${display#:}"
  mkdir -p "$tmp/runtime/ryoku-x11-lock"
  lock_file="$tmp/runtime/ryoku-x11-lock/$key.lock"
  if [[ $case_name == plain ]]; then
    ( exec 9>"$lock_file"; flock -n 9; exec sleep 30 ) 9>/dev/null &
    holder=$!
  else
    mkdir -p "$tmp/spoof"
    copy_binary bash "$tmp/spoof/xsecurelock"
    mkfifo "$tmp/fifo-spoof"
    ( exec 9>"$lock_file"; flock -n 9; DISPLAY="$display" exec "$tmp/spoof/xsecurelock" <"$tmp/fifo-spoof" >/dev/null ) &
    holder=$!
    exec 8>"$tmp/fifo-spoof"
  fi
  sleep 0.3
  status=0
  start=$SECONDS
  run_wrapper "$display" </dev/null >/dev/null 2>"$tmp/err-$case_name" || status=$?
  [[ "$status" == 75 ]] || fail "$case_name holder: wrapper exited $status, want 75 (no verified locker)"
  grep -q "no verified locker" "$tmp/err-$case_name" || fail "$case_name holder: missing explanation on stderr"
  (( SECONDS - start < 6 )) || fail "$case_name holder: wrapper waited too long"
  kill -KILL "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  exec 8>&-
done

# 8. Forged or stale lock records are rejected. The lock is held by a plain
# holder; the state file names (a) a renamed copy outside the trusted
# directory with a correct start time, (b) a genuine trusted locker with a
# WRONG start time (what a reused PID looks like), (c) garbage.
starttime_of() { local s r; s=$(<"/proc/$1/stat"); r=${s##*) }; set -- $r; echo "${20}"; }
rm -rf "$lockdir" && mkdir -p "$lockdir" "$tmp/spoof2"
copy_binary bash "$lockdir/xsecurelock"
copy_binary bash "$tmp/spoof2/xsecurelock"
mkfifo "$tmp/fifo-trusted" "$tmp/fifo-spoof2"
"$lockdir/xsecurelock" <"$tmp/fifo-trusted" >/dev/null & trusted_pid=$!
"$tmp/spoof2/xsecurelock" <"$tmp/fifo-spoof2" >/dev/null & spoof_pid=$!
exec 8>"$tmp/fifo-trusted"; exec 7>"$tmp/fifo-spoof2"
sleep 0.3
display=:105
state="$tmp/runtime/ryoku-x11-lock/_105.state"
( exec 9>"$tmp/runtime/ryoku-x11-lock/_105.lock"; flock -n 9; exec sleep 30 ) 9>/dev/null &
holder=$!
sleep 0.3
check_rejected() { # label
  local status=0
  run_wrapper "$display" </dev/null >/dev/null 2>&1 || status=$?
  [[ "$status" == 75 ]] || fail "$1: wrapper exited $status, want 75 (forged record accepted)"
}
printf '%s %s\n' "$spoof_pid" "$(starttime_of "$spoof_pid")" >"$state"
check_rejected "renamed locker outside the trusted directory"
printf '%s %s\n' "$trusted_pid" "$(( $(starttime_of "$trusted_pid") + 1 ))" >"$state"
check_rejected "wrong start time (PID reuse)"
printf 'garbage\n' >"$state"
check_rejected "malformed record"
# Positive control: the correct record for the trusted locker IS accepted.
printf '%s %s\n' "$trusted_pid" "$(starttime_of "$trusted_pid")" >"$state"
status=0; run_wrapper "$display" </dev/null >/dev/null 2>&1 || status=$?
[[ "$status" == 0 ]] || fail "a correct record for a live trusted locker was rejected (exit $status)"
kill -KILL "$holder" "$trusted_pid" "$spoof_pid" 2>/dev/null || true
wait 2>/dev/null || true
exec 8>&- 7>&-

echo "X11 lock wrapper tests passed: Wayland passthrough, session detection, trusted locker directory, PATH hijack refusal, lifetime of the per-display lock, idempotency, :D/:D.S normalisation, refusal to report success without a verified locker, and rejection of forged/stale lock records."
