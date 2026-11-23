#!/usr/bin/env bash
# Real-locker acceptance test for payload/bin/ryoku-x11-lock.
#
# Runs the UNMODIFIED wrapper against the real /usr/bin/xsecurelock and
# /usr/bin/i3lock on an isolated Xephyr display, authenticating a temporary
# user through REAL PAM (pam_unix). Nothing is mocked: a wrong password must
# leave the screen locked, the correct one must unlock it, and a PAM stack that
# denies everything must keep it locked even for the correct password.
#
# SAFETY: this script creates a user and (for the isolated-PAM case) a uniquely
# named file under /etc/pam.d, and uninstalls xsecurelock for the i3lock pass.
# It therefore refuses to run anywhere except a disposable container started
# for this purpose (RXB_PAM_TEST_DISPOSABLE=1 and /.dockerenv). It never edits
# an existing PAM file and never touches a desktop session.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
artifacts="${RXB_ARTIFACT_DIR:-}"

die() { echo "FAIL: $*" >&2; dump_diagnostics; exit 1; }

if [[ ${RXB_PAM_TEST_DISPOSABLE:-} != 1 || ! -f /.dockerenv || $EUID -ne 0 ]]; then
  echo "refusing to run: this test needs a disposable root container (RXB_PAM_TEST_DISPOSABLE=1)" >&2
  exit 2
fi
if [[ -n ${WAYLAND_DISPLAY:-} || -n ${SWAYSOCK:-} ]]; then
  echo "refusing to run inside a desktop session" >&2
  exit 2
fi
for command in Xvfb Xephyr xdotool xwininfo xterm import runuser flock useradd chpasswd xsecurelock i3lock pacman; do
  command -v "$command" >/dev/null 2>&1 || { echo "missing required command: $command" >&2; exit 127; }
done

# od reads a bounded amount, so there is no early-closing pipe (SIGPIPE under pipefail).
rand_hex() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }

user=rxbpamtest
password="$(rand_hex 10)"
wrong_password="not-$(rand_hex 6)"
tmp="$(cd "$(mktemp -d /tmp/rxb-lock-pam.XXXXXX)" && pwd -P)"
mkdir -p "$tmp/runtime" "$tmp/home" "$tmp/shots"
pam_service_files=()
pam_test_marker="/run/rxb-pam-test-disposable"
pam_test_marker_created=0
xvfb_pid="" xephyr_pid="" xterm_pid="" wrapper_pid=""

dump_diagnostics() {
  echo "----- diagnostics -----" >&2
  { echo "uid=${uid:-unset} count_lockers=$(count_lockers 2>&1)";
    for p in $(pgrep -u "$user" -x xsecurelock 2>/dev/null); do
      echo "xsecurelock pid=$p status-uid=$(awk '/^Uid:/{print $2; exit}' /proc/$p/status 2>&1) comm=$(cat /proc/$p/comm 2>&1)"; done; } >&2 || true
  { echo "display: ${disp:-unset}"; ps -eo pid,user,args --sort=pid | grep -E 'xsecurelock|i3lock|Xephyr|Xvfb|ryoku-x11-lock|auth_x11|saver_' | grep -v grep; } >&2 || true
  for f in "$tmp"/*.log; do [[ -f $f ]] && { echo "== $f"; tail -n 40 "$f"; } >&2; done
  if [[ -n ${disp:-} ]]; then
    echo "-- raw pixel probe:" >&2
    runuser -u "$user" -- env -i PATH=/usr/bin:/bin HOME="$tmp/home" DISPLAY="$disp" import -window root -depth 8 -crop 1x1+640+360 +repage txt:- 2>&1 | head -5 >&2 || true
    runuser -u "$user" -- env -i PATH=/usr/bin:/bin HOME="$tmp/home" DISPLAY="$disp" xwininfo -root -tree 2>&1 | head -40 >&2 || true
  fi
  if [[ -n $artifacts ]]; then mkdir -p "$artifacts"; cp -r "$tmp/shots" "$tmp"/*.log "$artifacts/" 2>/dev/null || true; fi
}

cleanup() {
  trap - EXIT
  exec 8>&- 2>/dev/null || true
  pkill -KILL -u "$user" 2>/dev/null || true
  [[ -z $xterm_pid ]] || kill "$xterm_pid" 2>/dev/null || true
  [[ -z $xephyr_pid ]] || kill "$xephyr_pid" 2>/dev/null || true
  [[ -z $xvfb_pid ]] || kill "$xvfb_pid" 2>/dev/null || true
  for f in "${pam_service_files[@]:-}"; do [[ -n $f ]] && rm -f -- "$f"; done
  if [[ -n $artifacts ]]; then mkdir -p "$artifacts"; cp -r "$tmp/shots" "$tmp"/*.log "$artifacts/" 2>/dev/null || true; fi
  userdel -r "$user" >/dev/null 2>&1 || true
  if (( pam_test_marker_created )); then rm -f -- "$pam_test_marker"; fi
  rm -rf -- "$tmp"
}
trap cleanup EXIT

[[ ! -e "$pam_test_marker" && ! -L "$pam_test_marker" ]] || die "disposable PAM test marker already exists"
install -o root -g root -m 0600 /dev/null "$pam_test_marker"
pam_test_marker_created=1

# --- temporary user with a real password -----------------------------------
id "$user" >/dev/null 2>&1 && die "test user $user already exists; refusing to reuse it"
useradd -m -s /bin/bash "$user"
echo "$user:$password" | chpasswd
uid="$(id -u "$user")"
chown -R "$user:$user" "$tmp/runtime" "$tmp/home" "$tmp/shots"
chmod 700 "$tmp/runtime"
chmod 755 "$tmp"

# The wrapper under test is the repository file, byte for byte.
install -m 755 "$root/payload/bin/ryoku-x11-lock" "$tmp/ryoku-x11-lock"
cmp -s "$root/payload/bin/ryoku-x11-lock" "$tmp/ryoku-x11-lock" || die "wrapper copy differs from the repository file"
grep -qx 'locker_dir=/usr/bin' "$tmp/ryoku-x11-lock" || die "wrapper is not using the trusted /usr/bin locker directory"

as_user() { runuser -u "$user" -- env -i PATH=/usr/bin:/bin HOME="$tmp/home" "$@"; }

# --- isolated Xephyr display on an isolated Xvfb parent ---------------------
start_display() {
  # Fixed display numbers are safe: this runs only in a disposable container.
  install -d -m 1777 /tmp/.X11-unix
  local parent=":71"
  as_user Xvfb "$parent" -screen 0 1600x900x24 -nolisten tcp -ac >"$tmp/xvfb.log" 2>&1 &
  xvfb_pid=$!
  for _ in $(seq 1 100); do as_user DISPLAY="$parent" xwininfo -root >/dev/null 2>&1 && break; sleep 0.1; done
  as_user DISPLAY="$parent" xwininfo -root >/dev/null 2>&1 || die "Xvfb parent display did not start"
  disp=":72"
  as_user DISPLAY="$parent" Xephyr "$disp" -screen 1280x720 -nolisten tcp -ac -no-host-grab >"$tmp/xephyr.log" 2>&1 &
  xephyr_pid=$!
  for _ in $(seq 1 100); do as_user DISPLAY="$disp" xwininfo -root >/dev/null 2>&1 && break; sleep 0.1; done
  as_user DISPLAY="$disp" xwininfo -root >/dev/null 2>&1 || die "Xephyr display $disp did not start"
  as_user DISPLAY="$disp" xdotool getdisplaygeometry >"$tmp/geometry.log" 2>&1 || die "XTEST/xdotool cannot talk to Xephyr: $(cat "$tmp/geometry.log")"
  # A real mapped red window is the "desktop" content that the locker must
  # cover (setting the root window background is not reliably readable back).
  as_user DISPLAY="$disp" xterm -b 0 +sb -bg '#ff0000' -fg '#ff0000' -geometry 200x50+0+0 -e sleep 100000 >"$tmp/xterm.log" 2>&1 &
  xterm_pid=$!
}

pixel() { # prints "R G B" of the centre pixel
  as_user DISPLAY="$disp" import -window root -depth 8 -crop 1x1+640+360 +repage txt:- 2>/dev/null |
    sed -n 's/.*(\([0-9]*\),\([0-9]*\),\([0-9]*\).*/\1 \2 \3/p' | tail -n 1
}
shot() { as_user DISPLAY="$disp" import -window root "png:$tmp/shots/$1.png" 2>/dev/null || true; }
is_red() { read -r r g b <<<"$(pixel)"; [[ -n ${r:-} && $r -gt 200 && $g -lt 60 && $b -lt 60 ]]; }
is_covered() { read -r r g b <<<"$(pixel)"; [[ -n ${r:-} && $r -lt 60 ]]; }
# After a rejected password a locker draws feedback (i3lock: a red "wrong" ring
# and text) around the centre, so judge coverage at points well away from it.
pixel_at() { as_user DISPLAY="$disp" import -window root -depth 8 -crop "1x1+$1+$2" +repage txt:- 2>/dev/null |
    sed -n 's/.*(\([0-9]*\),\([0-9]*\),\([0-9]*\).*/\1 \2 \3/p' | tail -n 1; }
is_covered_away_from_centre() {
  local pt r g b
  for pt in "100 100" "600 600"; do
    read -r r g b <<<"$(pixel_at $pt)"
    [[ -n ${r:-} && $r -lt 60 ]] || return 1
  done
}

locker_pids() { # real locker processes owned by the test user
  # XSecureLock is non-dumpable: /proc/PID/exe is unreadable even for root in a
  # container without CAP_SYS_PTRACE, so identify by real uid + process name.
  local p comm
  for p in /proc/[0-9]*; do
    [[ "$(awk '/^Uid:/{print $2; exit}' "$p/status" 2>/dev/null)" == "$uid" ]] || continue
    comm=$(cat "$p/comm" 2>/dev/null) || continue
    case "$comm" in xsecurelock | i3lock) echo "${p#/proc/}" ;; esac
  done
}
# i3lock forks a helper child even with --nofork, so count independent lockers:
# locker processes whose parent is not itself a locker process.
count_lockers() {
  local all p pp n=0
  all=" $(locker_pids | tr '\n' ' ') "
  for p in $all; do
    pp=$(awk '/^PPid:/{print $2; exit}' "/proc/$p/status" 2>/dev/null) || continue
    [[ "$all" == *" $pp "* ]] || n=$((n + 1))
  done
  echo "$n"
}
# Every locker process, helpers included (used to prove full cleanup).
no_lockers() { [[ -z "$(locker_pids)" ]]; }
lockers_at_least() { [[ "$(count_lockers)" -ge "$1" ]]; }
wait_until() { local limit=$(( $1 * 10 )); shift; for _ in $(seq 1 "$limit"); do "$@" && return 0; sleep 0.1; done; return 1; }
# The wrapper's record of the running locker must verify (pid + start time).
state_recorded() {
  local f="$tmp/runtime/ryoku-x11-lock/$(printf '%s' "${disp//[^A-Za-z0-9_.-]/_}").state" pid start cur rest
  read -r pid start <"$f" 2>/dev/null || return 1
  rest="$(sed 's/^.*) //' "/proc/$pid/stat" 2>/dev/null)" || return 1
  set -- $rest; cur="${20:-}"
  [[ -n $cur && $cur == "$start" ]]
}
lock_file_held() { ! as_user flock -n "$tmp/runtime/ryoku-x11-lock/$(printf '%s' "${disp//[^A-Za-z0-9_.-]/_}").lock" true; }

start_wrapper() { # logfile [VAR=value...]
  local log="$1"; shift
  as_user DISPLAY="$disp" XDG_RUNTIME_DIR="$tmp/runtime" RXB_PAM_TEST_DISPOSABLE=1 "$@" "$tmp/ryoku-x11-lock" >"$log" 2>&1 &
  wrapper_pid=$!
}
wrapper_alive() { kill -0 "$wrapper_pid" 2>/dev/null; }
wrapper_gone() { ! wrapper_alive; }

type_password() { # text
  as_user DISPLAY="$disp" xdotool key Shift_L   # wake XSecureLock's prompt without typing a character
  sleep 1.2
  as_user DISPLAY="$disp" xdotool type --delay 60 -- "$1"
  as_user DISPLAY="$disp" xdotool key Return
}

# Exercise one real locker. $1 = label, $2 = expected result for the CORRECT
# password (unlock|stay-locked), remaining args = environment for the wrapper.
exercise() {
  local label="$1" expect="$2"; shift 2
  echo "=== $label ==="
  wait_until 10 is_red || die "$label: the red test window is not visible before locking (cannot judge coverage)"
  shot "$label-1-before"
  [[ "$(count_lockers)" == 0 ]] || die "$label: a locker was already running before the test"

  start_wrapper "$tmp/$label-wrapper.log" "$@"
  wait_until 20 lockers_at_least 1 || die "$label: the wrapper did not start a real locker"
  wait_until 10 is_covered || die "$label: screen is not covered after locking (centre pixel stayed red)"
  wrapper_alive || die "$label: wrapper exited while locking"
  lock_file_held || die "$label: the per-display lock is not held while the locker runs"
  wait_until 5 state_recorded || die "$label: the wrapper's locker record does not verify against /proc"
  shot "$label-2-locked"
  [[ "$(count_lockers)" == 1 ]] || die "$label: expected exactly one locker, found $(count_lockers)"

  # Repeated lock requests: success, no second locker, same locker process.
  local before after status=0
  before="$(locker_pids | tr '\n' ' ')"
  timeout 20 runuser -u "$user" -- env -i PATH=/usr/bin:/bin HOME="$tmp/home" DISPLAY="$disp" XDG_RUNTIME_DIR="$tmp/runtime" RXB_PAM_TEST_DISPOSABLE=1 "$@" "$tmp/ryoku-x11-lock" >"$tmp/$label-repeat.log" 2>&1 || status=$?
  [[ "$status" == 0 ]] || die "$label: repeated lock request exited $status"
  after="$(locker_pids | tr '\n' ' ')"
  [[ "$before" == "$after" ]] || die "$label: repeated lock request changed the locker set ($before -> $after)"

  # Wrong password: must remain locked.
  type_password "$wrong_password"
  sleep 4
  wrapper_alive || die "$label: an INCORRECT password ended the wrapper (unlocked)"
  [[ "$(count_lockers)" == 1 ]] || die "$label: locker count changed after an incorrect password"
  is_covered_away_from_centre || die "$label: screen uncovered after an incorrect password"
  lock_file_held || die "$label: lock released after an incorrect password"
  shot "$label-3-after-wrong"

  # Correct password: unlocks through PAM, or (deny-all stack) must not.
  type_password "$password"
  if [[ $expect == unlock ]]; then
    wait_until 25 wrapper_gone || die "$label: the CORRECT password did not unlock"
    local rc=0; wait "$wrapper_pid" || rc=$?
    [[ "$rc" == 0 ]] || die "$label: locker exited $rc after the correct password, want 0"
    wait_until 10 no_lockers || die "$label: locker processes remain after unlocking"
    wait_until 10 is_red || die "$label: screen not restored after unlocking"
    lock_file_held && die "$label: lock still held after unlocking"
    # No helper left behind (auth/saver helpers).
    pgrep -u "$user" -f 'auth_x11|authproto|saver_' >/dev/null && die "$label: helper processes survived the unlock"
    shot "$label-4-unlocked"
  else
    sleep 4
    wrapper_alive || die "$label: a deny-all PAM stack still let the correct password unlock (authentication is not delegated to PAM)"
    is_covered || die "$label: screen uncovered under a deny-all PAM stack"
    shot "$label-4-still-locked"
    # Same-user kill is an inherent X11-locker limitation; used here only to clean up.
    pkill -TERM -u "$user" -x xsecurelock || true
    wait_until 15 wrapper_gone || die "$label: could not clean up the deny-all locker"
    wait "$wrapper_pid" 2>/dev/null || true
    pkill -KILL -u "$user" -f 'auth_x11|authproto|saver_' 2>/dev/null || true
  fi
  echo "ok: $label"
}

# --- evidence that the lockers really are PAM clients -----------------------
echo "--- installed locker packages and PAM linkage ---"
pacman -Q xsecurelock i3lock pam
ldd /usr/bin/i3lock | grep -E 'libpam' || die "i3lock is not linked against libpam"
helpers="$(pacman -Ql xsecurelock | awk '{print $2}' | grep -E 'authproto_pam|auth_x11' || true)"
echo "$helpers"
[[ -n $helpers ]] || die "xsecurelock package ships no PAM auth helpers"
for helper in $helpers; do
  [[ -f $helper && -x $helper ]] || continue
  case "$helper" in *authproto_pam) ldd "$helper" | grep -E 'libpam' || die "$helper is not linked against libpam" ;; esac
done
[[ -f /etc/pam.d/i3lock ]] && { echo "--- /etc/pam.d/i3lock (read only) ---"; cat /etc/pam.d/i3lock; } || echo "note: /etc/pam.d/i3lock is not shipped"
ls /etc/pam.d | grep -E '^(xsecurelock|system-auth)$' || true

start_display

# Case 1: XSecureLock with the PAM service it was built to use (no config edits).
exercise xsecurelock-default unlock

# Case 2: XSecureLock with a unique isolated PAM service: real pam_unix only.
svc="rxb-test-$(rand_hex 5)"
svc_file="/etc/pam.d/$svc"
[[ ! -e $svc_file ]] || die "unique PAM service name collided with an existing file"
printf 'auth     required pam_unix.so\naccount  required pam_unix.so\n' >"$svc_file"
pam_service_files+=("$svc_file")
exercise xsecurelock-isolated-pam unlock XSECURELOCK_PAM_SERVICE="$svc"

# Case 3: negative control. An isolated PAM stack that denies everyone must
# keep the screen locked even for the correct password. This proves the unlock
# decision comes from PAM and not from the wrapper or the test harness.
svc_deny="rxb-test-deny-$(rand_hex 5)"
printf 'auth     required pam_deny.so\naccount  required pam_permit.so\n' >"/etc/pam.d/$svc_deny"
pam_service_files+=("/etc/pam.d/$svc_deny")
exercise xsecurelock-deny-all-pam stay-locked XSECURELOCK_PAM_SERVICE="$svc_deny"

# Case 4: the i3lock fallback. Remove xsecurelock so the unmodified wrapper
# takes its real fallback branch; PAM service is the package's /etc/pam.d/i3lock.
[[ -f /etc/pam.d/i3lock ]] || die "i3lock package ships no /etc/pam.d/i3lock; PAM authentication cannot work"
pacman -Rdd --noconfirm xsecurelock >/dev/null
! command -v xsecurelock >/dev/null 2>&1 || die "xsecurelock is still installed"
exercise i3lock-fallback unlock

# Final cleanliness: nothing left running for the test user, lock file free.
[[ "$(count_lockers)" == 0 ]] || die "lockers left running at the end"
echo "X11 lock PAM acceptance passed on isolated Xephyr: real xsecurelock and i3lock, real pam_unix, wrong password stays locked, correct password unlocks, deny-all PAM stays locked, repeated requests do not stack lockers."
