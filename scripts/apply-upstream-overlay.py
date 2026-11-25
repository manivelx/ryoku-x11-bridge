#!/usr/bin/env python3
"""Apply the RXB X11 compatibility overlay to the pinned Ryoku checkout."""
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys

PIN = (pathlib.Path(__file__).resolve().parents[1] / "UPSTREAM_PIN").read_text().strip()


def replace_once(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one patch anchor, found {count}: {old[:100]!r}")
    path.write_text(text.replace(old, new, 1))


def replace_in_map(path: pathlib.Path, marker: str, old: str, new: str) -> None:
    text = path.read_text()
    try:
        start = text.index(marker)
    except ValueError as exc:
        raise RuntimeError(f"{path}: map marker not found: {marker}") from exc
    try:
        end = text.index("\n}", start) + 2
    except ValueError as exc:
        raise RuntimeError(f"{path}: closing brace not found for map: {marker}") from exc
    section = text[start:end]
    count = section.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one {marker} entry, found {count}")
    path.write_text(text[:start] + section.replace(old, new, 1) + text[end:])


def patch_detect_file(p: pathlib.Path) -> None:
    replace_once(p, 'ProviderWayfire  = "wayfire"',
                 'ProviderWayfire  = "wayfire"\n\tProviderI3       = "i3"')
    replace_once(p, '{"WAYFIRE_SOCKET", ProviderWayfire, func(h string) []string { return []string{h} }},',
                 '{"WAYFIRE_SOCKET", ProviderWayfire, func(h string) []string { return []string{h} }},\n'
                 '\t// i3 exports its IPC socket path to clients in the session.\n'
                 '\t{"I3SOCK", ProviderI3, func(h string) []string { return []string{h} }},')
    replace_in_map(p, "var configDirs", 'ProviderWayfire:  "wayfire",',
                   'ProviderWayfire:  "wayfire",\n\tProviderI3:       "ryoku-x11",')
    replace_once(p, 'ProviderWayfire:  "wayfire.ini",',
                 'ProviderWayfire:  "wayfire.ini",\n\tProviderI3:       "ryoku-x11/config",')
    replace_once(p, 'ProviderWayfire: {"monitors.ini", "keyboard.ini", "user.ini"},',
                 'ProviderWayfire: {"monitors.ini", "keyboard.ini", "user.ini"},\n\tProviderI3:      {"ryoku-x11/config", "ryoku-x11/generated.conf", "ryoku-x11/user.conf"},')
    replace_once(p, 'ProviderWayfire:  {"wayfire/user.ini", "wayfire/monitors.ini"},',
                 'ProviderWayfire:  {"wayfire/user.ini", "wayfire/monitors.ini"},\n\tProviderI3:       {"ryoku-x11/user.conf", "ryoku-x11/config"},')
    replace_once(p, 'ProviderWayfire:  {"wayfire/wayfire.ini", "ryoku/user_edits/wayfire/wayfire.ini"},',
                 'ProviderWayfire:  {"wayfire/wayfire.ini", "ryoku/user_edits/wayfire/wayfire.ini"},\n\tProviderI3:       {"ryoku-x11/generated.conf"},')
    replace_once(p, 'return []string{ProviderHyprland, ProviderNiri, ProviderWayfire}',
                 'return []string{ProviderHyprland, ProviderNiri, ProviderWayfire, ProviderI3}')
    replace_in_map(p, "var compositorBins", 'ProviderWayfire:  "wayfire",',
                   'ProviderWayfire:  "wayfire",\n\tProviderI3:       "i3",')
    subprocess.run(["gofmt", "-w", str(p)], check=True)


def patch_detect(root: pathlib.Path) -> None:
    files = [root / "ryoku/wm/detect.go"]
    files.extend(root.glob("**/vendor/ryoku-wm/detect.go"))
    for p in files:
        patch_detect_file(p)


def patch_session_detection_file(p: pathlib.Path) -> None:
    old = '''var sessionEntryDirs = func() []string {
	dirs := []string{"/usr/local/share/wayland-sessions", "/usr/share/wayland-sessions"}
	for _, d := range filepath.SplitList(os.Getenv("XDG_DATA_DIRS")) {
		if d != "" {
			dirs = append(dirs, filepath.Join(d, "wayland-sessions"))
		}
	}
	return dirs
}'''
    new = '''var sessionEntryDirs = func() []string {
	dirs := []string{"/usr/local/share/wayland-sessions", "/usr/share/wayland-sessions"}
	for _, d := range filepath.SplitList(os.Getenv("XDG_DATA_DIRS")) {
		if d != "" {
			dirs = append(dirs, filepath.Join(d, "wayland-sessions"))
		}
	}
	return dirs
}

var xSessionEntryDirs = func() []string {
	dirs := []string{"/usr/local/share/xsessions", "/usr/share/xsessions"}
	for _, d := range filepath.SplitList(os.Getenv("XDG_DATA_DIRS")) {
		if d != "" {
			dirs = append(dirs, filepath.Join(d, "xsessions"))
		}
	}
	return dirs
}

var sessionEntryNames = map[string]string{ProviderI3: "ryoku-x11.desktop"}

func sessionDirsFor(name string) []string {
	dirs := sessionEntryDirs()
	if name == ProviderI3 {
		dirs = append(dirs, xSessionEntryDirs()...)
	}
	return dirs
}'''
    replace_once(p, old, new)
    replace_once(p, "for _, dir := range dirs {\n\t\tentries, err := os.ReadDir(dir)",
                 "wanted := sessionEntryNames[name]\n\tfor _, dir := range sessionDirsFor(name) {\n\t\tentries, err := os.ReadDir(dir)")
    replace_once(p, 'if entry.IsDir() || filepath.Ext(entry.Name()) != ".desktop" {',
                 'if entry.IsDir() || filepath.Ext(entry.Name()) != ".desktop" || (wanted != "" && entry.Name() != wanted) {')
    replace_once(p, 'entry := name + ".desktop"\n\tfor _, d := range sessionEntryDirs() {',
                 'entry := name + ".desktop"\n\tif custom := sessionEntryNames[name]; custom != "" { entry = custom }\n\tfor _, d := range sessionDirsFor(name) {')


def patch_session_detection(root: pathlib.Path) -> None:
    files = [root / "ryoku/wm/detect.go"]
    files.extend(root.glob("**/vendor/ryoku-wm/detect.go"))
    for p in files:
        patch_session_detection_file(p)


def patch_wm_qml(root: pathlib.Path) -> None:
    p = root / "ryoku/ui/Singletons/Wm.qml"
    replace_once(p, 'import Quickshell.WindowManager\nimport Quickshell.Wayland',
                 'import Quickshell.I3')
    old = '''    // Bound at declaration so the Wayland registry binds early; the lists fill in
    // asynchronously after connect.
    readonly property var _windowsets: WindowManager.windowsets
    property var _toplevelModel: ToplevelManager.toplevels
    readonly property var toplevels: root._toplevelModel ? root._toplevelModel.values : []'''
    new = '''    // X11/i3 workspace and monitor state is provided by Quickshell's native
    // I3 module. Window identity and geometry come from the RXB provider.
    readonly property var _windowsets: I3.workspaces.values
    readonly property var _toplevelModel: null
    readonly property var toplevels: {
        const rows = root._winResidue || [];
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const w = rows[i];
            let screen = null;
            for (let j = 0; j < Quickshell.screens.length; j++) {
                if (Quickshell.screens[j].name === String(w.output || "")) {
                    screen = Quickshell.screens[j];
                    break;
                }
            }
            out.push({
                id: String(w.id || ""),
                appId: String(w.appId || ""),
                title: String(w.title || ""),
                toplevel: null,
                activated: Number(w.focusOrder) === 0,
                fullscreen: w.fullscreen === true,
                screens: screen ? [screen] : [],
                activate: () => root.focusWindow(String(w.id || "")),
                close: () => root.closeWindow(String(w.id || ""))
            });
        }
        return out;
    }'''
    replace_once(p, old, new)
    replace_once(p, "const tl = (arr && at < arr.length) ? arr[at] : null;",
                 "const entry = (arr && at < arr.length) ? arr[at] : null;\n"
                 "            const tl = entry ? (entry.toplevel ?? entry) : null;")
    old = '''                id: s.name,
                name: s.name,
                active: s.active === true,
                urgent: s.urgent === true,
                canActivate: s.canActivate === true,
                windows: 0,
                occupied: false,
                fullscreen: false,
                special: false,
                output: "",
                layout: ""'''
    new = '''                id: s.name,
                name: s.name,
                index: s.number,
                active: s.active === true,
                urgent: s.urgent === true,
                canActivate: true,
                windows: 0,
                occupied: false,
                fullscreen: false,
                special: false,
                output: s.monitor ? s.monitor.name : "",
                layout: ""'''
    replace_once(p, old, new)


def patch_compositor_service(root: pathlib.Path) -> None:
    p = root / "ryoku/shell/quickshell/inir/services/CompositorService.qml"
    replace_once(p, 'readonly property bool nativeOverview: true',
                 'readonly property bool nativeOverview: Wm.caps.nativeOverview === true')
    replace_once(p, 'readonly property bool windowWorkspaceMap: false',
                 'readonly property bool windowWorkspaceMap: Wm.caps.windowWorkspaceMap === true')



def patch_x11_terminal_launcher(root: pathlib.Path) -> None:
    # Upstream's default terminal is Kitty. RXB supports the user's installed
    # X11 terminal without forcing a particular terminal package onto CachyOS.
    p = root / "ryoku/shell/scripts/ryoku-app"
    replace_once(p, 'conf="${XDG_CONFIG_HOME:-$HOME/.config}/ryoku"',
                 'config_root="${RYOKU_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}}"\nconf="$config_root/ryoku"')
    replace_once(p, '\tterminal) echo "kitty" ;;', '''\tterminal)
\t\tif [[ "${RYOKU_X11_BRIDGE:-}" == "1" && -n "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
\t\t\tif [[ -n "${TERMINAL:-}" ]] && command -v "${TERMINAL%% *}" >/dev/null 2>&1; then
\t\t\t\techo "$TERMINAL"
\t\t\t\treturn 0
\t\t\tfi
\t\t\tfor candidate in kitty foot konsole xfce4-terminal xterm; do
\t\t\t\tif command -v "$candidate" >/dev/null 2>&1; then
\t\t\t\t\techo "$candidate"
\t\t\t\t\treturn 0
\t\t\t\tfi
\t\t\tdone
\t\t\techo ""
\t\telse
\t\t\techo "kitty"
\t\tfi ;;
''')
    p.chmod(0o755)

def patch_x11_capture(root: pathlib.Path) -> None:
    p = root / "ryoku/shell/scripts/ryoku-cmd-grim"
    text = p.read_text()
    anchor = "runtime=${XDG_RUNTIME_DIR:-/tmp}"
    if anchor not in text:
        raise RuntimeError(f"{p}: expected grim helper header")
    x11 = '''# X11 uses maim, not the Wayland-only grim protocol.
if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then
  output=""
  geometry=""
  destination=""
  while (($#)); do
    case "$1" in
      -o) output=${2:-}; shift 2 ;;
      -g) geometry=${2:-}; shift 2 ;;
      -c) shift ;;
      --) shift; destination=${1:-}; break ;;
      -*) echo "ryoku-cmd-grim: unsupported X11 option: $1" >&2; exit 2 ;;
      *) destination=$1; shift ;;
    esac
  done
  if [[ -n "$output" && -z "$geometry" ]]; then
    geometry="$(xrandr --query 2>/dev/null | awk -v name="$output" '$1 == name && $2 == "connected" { for (i=3; i<=NF; i++) if ($i ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$/) { print $i; exit } }')"
    [[ -n "$geometry" ]] || { echo "ryoku-cmd-grim: cannot resolve active output geometry for $output" >&2; exit 1; }
  fi
  command -v maim >/dev/null 2>&1 || { echo "ryoku-cmd-grim: install maim for X11 capture" >&2; exit 127; }
  args=()
  [[ -n "$geometry" ]] && args+=(-g "$geometry")
  [[ -n "$destination" ]] && args+=("$destination")
  exec maim "${args[@]}"
fi

'''
    p.write_text(text.replace(anchor, x11 + anchor, 1))

    p = root / "ryoku/shell/quickshell/ryoshot/lib/capture-backend.js"
    replace_once(p, "function shouldUseGrim(setting, desktop, niriSocket) {\n    if (setting === \"1\") return true;",
                 "function shouldUseGrim(setting, desktop, niriSocket, display, waylandDisplay) {\n    if (setting === \"1\") return true;\n    if (display && !waylandDisplay) return true;")

    p = root / "ryoku/shell/quickshell/ryoshot/Overlay.qml"
    replace_once(p, 'Quickshell.env("NIRI_SOCKET"))',
                 'Quickshell.env("NIRI_SOCKET"), Quickshell.env("DISPLAY"), Quickshell.env("WAYLAND_DISPLAY"))')

    p = root / "ryoku/shell/quickshell/shell/modules/launcher/variants/hero/LocalFrost.qml"
    text = p.read_text()
    if "import Ryoku.Ui.Singletons" not in text:
        replace_once(p, "import QtQuick\n", "import QtQuick\nimport Ryoku.Ui.Singletons\n")
    replace_once(p, "(root.captureStarted && root.captureWanted)",
                 "(root.captureStarted && root.captureWanted && Wm.caps.persistentScreenCapture === true)")

    p = root / "ryoku/shell/quickshell/shell/modules/bar/popouts/DockPreviewPopout.qml"
    replace_once(p, "readonly property bool hasCapture: !!(tile.win && tile.win.toplevel)",
                 "readonly property bool hasCapture: Wm.caps.persistentScreenCapture === true && !!(tile.win && tile.win.toplevel)")

    for p in (
        root / "ryoku/shell/quickshell/shell/modules/bar/barstyles/python/launcher/Launcher.qml",
        root / "ryoku/shell/quickshell/shell/modules/launcher/variants/python/LauncherSurface.qml",
    ):
        old = '''    readonly property bool isToplevelFullscreen: {
        try {
            if (typeof ToplevelManager !== "undefined" && ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.fullscreen) {
                let atl = ToplevelManager.activeToplevel;
                if (atl.screens && atl.screens.length > 0) {
                    return atl.screens.indexOf(launcherWindow.screen) !== -1;
                }
                return true;
            }
        } catch (e) {}
        return false;
    }'''
        new = '''    readonly property bool isToplevelFullscreen:
        launcherWindow.screen ? Wm.outputHasFullscreen(launcherWindow.screen.name) : false'''
        replace_once(p, old, new)

    p = root / "ryoku/shell/quickshell/shell/modules/overview/WorkspaceCell.qml"
    replace_once(p, 'captureSource: (!!cell.ov && cell.ov.active && tile.modelData.tl) ? tile.modelData.tl : null',
                 'captureSource: (Wm.caps.persistentScreenCapture === true && !!cell.ov && cell.ov.active && tile.modelData.tl) ? tile.modelData.tl : null')
    replace_once(p, 'visible: tile.modelData.tl !== null',
                 'visible: Wm.caps.persistentScreenCapture === true && tile.modelData.tl !== null')

    p = root / "ryoku/shell/quickshell/shell/modules/overview/Overview.qml"
    replace_once(p, 'captureSource: root.dragTl\n                live: false\n                visible: root.dragTl !== null',
                 'captureSource: Wm.caps.persistentScreenCapture === true ? root.dragTl : null\n                live: false\n                visible: Wm.caps.persistentScreenCapture === true && root.dragTl !== null')



def patch_x11_login1_graphical_session(root: pathlib.Path) -> None:
    # RXB X11 sessions are Class=user only. Preserve upstream Wayland's
    # user and user-early classes, while rejecting X11 greeter/lock/early.
    p = root / "ryoku/shell/ipc/sleepwake.go"
    replace_once(p, '''func graphicalLogin1UserSession(sessionType, sessionClass string) bool {
	return sessionType == "wayland" &&
		(sessionClass == "user" || sessionClass == "user-early")
}''', '''func graphicalLogin1UserSession(sessionType, sessionClass string) bool {
	if sessionType == "x11" {
		return sessionClass == "user"
	}
	return sessionType == "wayland" &&
		(sessionClass == "user" || sessionClass == "user-early")
}''')
    test = root / "ryoku/shell/ipc/sleepwake_x11_session_test.go"
    test.write_text("""package main

import "testing"

func TestRXBGraphicalLogin1UserSession(t *testing.T) {
	tests := []struct { name, typ, class string; want bool }{
		{"x11 user", "x11", "user", true},
		{"x11 early user rejected", "x11", "user-early", false},
		{"wayland user", "wayland", "user", true},
		{"wayland early user", "wayland", "user-early", true},
		{"tty rejected", "tty", "user", false},
		{"greeter rejected", "x11", "greeter", false},
		{"lock-screen rejected", "x11", "lock-screen", false},
		{"manager rejected", "x11", "manager", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := graphicalLogin1UserSession(tt.typ, tt.class); got != tt.want {
				t.Fatalf("graphicalLogin1UserSession(%q, %q) = %v, want %v",
					tt.typ, tt.class, got, tt.want)
			}
		})
	}
}
""")


def patch_x11_suspend(root: pathlib.Path) -> None:
    p = root / "ryoku/shell/quickshell/shell/services/SessionActions.qml"
    replace_once(p, '''        if (action === "lock" || action === "suspend") {
            Quickshell.execDetached(["ryoku-shell", action]);
            return;
        }''',
        '''        if (action === "lock") {
            Quickshell.execDetached(["ryoku-x11-lock"]);
            return;
        }
        if (action === "suspend") {
            Quickshell.execDetached(["ryoku-x11-suspend"]);
            return;
        }''')

    p = root / "ryoku/shell/quickshell/inir/modules/common/functions/Session.qml"
    replace_once(p, '''    function powerAction(args: var): void {
        Quickshell.execDetached(["/bin/sh", "-c", root.powerActionScript, "sh"].concat(args))
    }''',
        '''    function powerAction(args: var): void {
        if (Quickshell.env("DISPLAY") && !Quickshell.env("WAYLAND_DISPLAY")
                && (args[0] === "suspend" || args[0] === "hibernate")) {
            Quickshell.execDetached(["ryoku-x11-suspend", args[0]]);
            return;
        }
        Quickshell.execDetached(["/bin/sh", "-c", root.powerActionScript, "sh"].concat(args))
    }''')
    replace_once(p, '''    function lock() {
        Quickshell.execDetached(["ryoku-shell", "lock"]);
    }

    function suspend() {
        if (Config.options?.idle?.lockBeforeSleep !== false) {
            lock()
            _suspendTimer.restart()
        } else {
            powerAction(["suspend"])
        }
    }''',
        '''    function lock() {
        Quickshell.execDetached(["ryoku-x11-lock"]);
    }

    function suspend() {
        if (Quickshell.env("DISPLAY") && !Quickshell.env("WAYLAND_DISPLAY")) {
            Quickshell.execDetached(["ryoku-x11-suspend"]);
            return;
        }
        if (Config.options?.idle?.lockBeforeSleep !== false) {
            lock()
            _suspendTimer.restart()
        } else {
            powerAction(["suspend"])
        }
    }''')
    replace_once(p, '''    function hibernate() {
        if (hibernateCapabilityKnown && !canHibernate) {
            root.refreshSleepCapabilities()
            root._notifyHibernateUnavailable()
            return
        }

        lock();
        _hibernateTimer.restart()
    }''',
        '''    function hibernate() {
        if (Quickshell.env("DISPLAY") && !Quickshell.env("WAYLAND_DISPLAY")) {
            Quickshell.execDetached(["ryoku-x11-suspend", "hibernate"]);
            return;
        }
        if (hibernateCapabilityKnown && !canHibernate) {
            root.refreshSleepCapabilities()
            root._notifyHibernateUnavailable()
            return
        }

        lock();
        _hibernateTimer.restart();
    }''')

    p = root / "ryoku/shell/quickshell/stage/services/Battery.qml"
    replace_once(p, "readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend",
                 "readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend && !(Quickshell.env(\"DISPLAY\") && !Quickshell.env(\"WAYLAND_DISPLAY\"))")
    tick = chr(96)
    old = 'Quickshell.execDetached(["bash", "-c", ' + tick + 'systemctl suspend || loginctl suspend' + tick + ']);'
    replace_once(p, old, 'Quickshell.execDetached(["ryoku-x11-suspend"]);')

    p = root / "ryoku/shell/quickshell/shell/modules/bar/barstyles/python/syspanel/SystemPanelPowerActions.qml"
    replace_once(p, 'Quickshell.execDetached(["ryoku-shell", "lock"]);',
                 'Quickshell.execDetached(["ryoku-x11-lock"]);')
    replace_once(p, 'Quickshell.execDetached(["ryoku-host", "power", "suspend"]);',
                 'Quickshell.execDetached(["ryoku-x11-suspend"]);')
    replace_once(p, 'Quickshell.execDetached(["ryoku-host", "power", "hibernate"]);',
                 'Quickshell.execDetached(["ryoku-x11-suspend", "hibernate"]);')

    p = root / "ryoku/shell/quickshell/shell/modules/bar/barstyles/python/widgets/faces/user/UserFace.qml"
    replace_once(p, 'Quickshell.execDetached(["ryoku-shell", "lock"])',
                 'Quickshell.execDetached(["ryoku-x11-lock"])')
    replace_once(p, 'Quickshell.execDetached(["ryoku-host", "power", "suspend"])',
                 'Quickshell.execDetached(["ryoku-x11-suspend"])')

    p = root / "ryoku/shell/quickshell/shell/modules/phone/scripts/phone/kdeconnect_runcommands.py"
    replace_once(p, '"ryoku-lock": ("PC: lock the screen", f"{IPC} lock activate"),',
                 '"ryoku-lock": ("PC: lock the screen", "ryoku-x11-lock"),')
    replace_once(p, '"ryoku-suspend": ("PC: suspend", "systemctl suspend"),',
                 '"ryoku-suspend": ("PC: suspend (disabled on X11 until secure handoff)", "ryoku-x11-suspend"),')

    p = root / "ryoku/shell/quickshell/keys/commands/catalog/linux.json"
    text = p.read_text()
    text = text.replace('"command": "systemctl suspend"', '"command": "ryoku-x11-suspend"')
    text = text.replace('"command": "loginctl suspend"', '"command": "ryoku-x11-suspend"')
    p.write_text(text)

    for p in (root / "ryoku/shell/nomarchy/bin").glob("*"):
        if not p.is_file():
            continue
        try:
            text = p.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        updated = text.replace("ryoku-qylock-lock", "ryoku-x11-lock")
        updated = updated.replace("ryoku-shell suspend", "ryoku-x11-suspend")
        if updated != text:
            p.write_text(updated)


def patch_x11_clipboard(root: pathlib.Path) -> None:
    p = root / "ryoku/shell/ipc/clipboard.go"
    text = p.read_text()
    old = 'cmd := exec.Command("wl-copy", "--type", mime)'
    if text.count(old) != 2:
        raise RuntimeError(f"{p}: expected two Wayland clipboard writers, found {text.count(old)}")
    text = text.replace(old, "cmd := selectionCopyCommand(mime)")
    insert = '''func selectionCopyCommand(mime string) *exec.Cmd {
	if os.Getenv("WAYLAND_DISPLAY") == "" && os.Getenv("DISPLAY") != "" {
		return exec.Command("xclip", "-selection", "clipboard", "-t", mime, "-i")
	}
	return exec.Command("wl-copy", "--type", mime)
}

'''
    anchor = "func (s *clipState) copy(id uint64) error {"
    if text.count(anchor) != 1:
        raise RuntimeError(f"{p}: clipboard copy function anchor missing")
    text = text.replace(anchor, insert + anchor, 1)
    keep = "func (s *clipState) keepSelection() {\n\treapStrayClipPersist()"
    keep_new = "func (s *clipState) keepSelection() {\n\tif os.Getenv(\"WAYLAND_DISPLAY\") == \"\" && os.Getenv(\"DISPLAY\") != \"\" { return }\n\treapStrayClipPersist()"
    if keep not in text:
        raise RuntimeError(f"{p}: selection keeper anchor missing")
    p.write_text(text.replace(keep, keep_new, 1))

    test = root / "ryoku/shell/ipc/clipboard_x11_test.go"
    test.write_text("""package main

import (
	"path/filepath"
	"testing"
)

func TestRXBSelectionCopyCommandChoosesX11Backend(t *testing.T) {
	t.Setenv("DISPLAY", ":99")
	t.Setenv("WAYLAND_DISPLAY", "")
	if got := filepath.Base(selectionCopyCommand("image/png").Path); got != "xclip" {
		t.Fatalf("X11 clipboard writer = %q, want xclip", got)
	}
}

func TestRXBSelectionCopyCommandKeepsWaylandBackend(t *testing.T) {
	t.Setenv("DISPLAY", ":99")
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	if got := filepath.Base(selectionCopyCommand("image/png").Path); got != "wl-copy" {
		t.Fatalf("Wayland clipboard writer = %q, want wl-copy", got)
	}
}

func TestRXBX11ClipboardMimeFiltersProtocolTargets(t *testing.T) {
	got := x11ClipboardMime([]string{"TARGETS", "MULTIPLE", "TIMESTAMP", "UTF8_STRING"})
	if got != "UTF8_STRING" {
		t.Fatalf("selected MIME = %q, want UTF8_STRING", got)
	}
	if got := normalizeX11Mime("UTF8_STRING"); got != "text/plain;charset=utf-8" {
		t.Fatalf("normalized MIME = %q", got)
	}
	if got := x11ClipboardMime([]string{"TARGETS", "MULTIPLE", "TIMESTAMP"}); got != "" {
		t.Fatalf("protocol-only targets returned %q", got)
	}
}
""")

    p = root / "ryoku/shell/ipc/clipwatch.go"
    text = p.read_text()
    text = text.replace('import (\n', 'import (\n\t"context"\n', 1)
    text = text.replace('\t"os"\n', '\t"os"\n\t"os/exec"\n', 1)
    old = '''func (s *clipState) watch() {
	if self, err := os.Executable(); err == nil {'''
    new = '''func (s *clipState) watch() {
	if os.Getenv("WAYLAND_DISPLAY") == "" && os.Getenv("DISPLAY") != "" {
		s.watchX11()
		return
	}
	if self, err := os.Executable(); err == nil {'''
    if old not in text:
        raise RuntimeError(f"{p}: watcher entry point not found")
    text = text.replace(old, new, 1)
    add = '''func (s *clipState) watchX11() {
	if _, err := exec.LookPath("xclip"); err != nil {
		log.Printf("ryoku-shell: X11 clipboard history disabled: xclip is not installed")
		return
	}
	var lastHash uint64
	for {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		targets, err := exec.CommandContext(ctx, "xclip", "-selection", "clipboard", "-o", "-t", "TARGETS").Output()
		cancel()
		if err == nil {
			mime := x11ClipboardMime(strings.Fields(string(targets)))
			if mime == "" {
				lastHash = 0
			} else {
				data, readErr := readX11Selection(mime)
				if readErr == nil && len(data) > 0 && len(data) <= clipMaxEntryBytes {
					hash := clipHash(data)
					if hash != lastHash {
						s.ingest(normalizeX11Mime(mime), data)
						lastHash = hash
					}
				}
			}
		} else {
			lastHash = 0
		}
		time.Sleep(900 * time.Millisecond)
	}
}

func x11ClipboardMime(offered []string) string {
	filtered := make([]string, 0, len(offered))
	for _, mime := range offered {
		switch strings.ToUpper(mime) {
		case "TARGETS", "MULTIPLE", "TIMESTAMP", "SAVE_TARGETS":
			continue
		}
		filtered = append(filtered, mime)
	}
	return pickBestMime(filtered)
}

func normalizeX11Mime(mime string) string {
	switch mime {
	case "UTF8_STRING", "TEXT", "STRING":
		return "text/plain;charset=utf-8"
	default:
		return mime
	}
}

func readX11Selection(mime string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "xclip", "-selection", "clipboard", "-o", "-t", mime)
	stdout, err := cmd.StdoutPipe()
	if err != nil { return nil, err }
	if err := cmd.Start(); err != nil { return nil, err }
	data, readErr := io.ReadAll(io.LimitReader(stdout, clipMaxEntryBytes+1))
	waitErr := cmd.Wait()
	if ctx.Err() != nil { return nil, ctx.Err() }
	if readErr != nil { return nil, readErr }
	if waitErr != nil { return nil, waitErr }
	if len(data) > clipMaxEntryBytes { return nil, fmt.Errorf("clipboard selection exceeds %d bytes", clipMaxEntryBytes) }
	return data, nil
}

'''
    anchor = "func dialWayland() (*net.UnixConn, error) {"
    if text.count(anchor) != 1:
        raise RuntimeError(f"{p}: Wayland dial anchor missing")
    text = text.replace(anchor, add + anchor, 1)
    p.write_text(text)


def patch_x11_region_tools(root: pathlib.Path) -> None:
    helper = root / "ryoku/shell/scripts/ryoku-cmd-clipboard-copy"
    helper.write_text('''#!/usr/bin/env bash
set -euo pipefail
mime=${1:-text/plain}
shift || true
if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then
  exec xclip -selection clipboard -t "$mime" -i "$@"
fi
exec wl-copy --type "$mime" "$@"
''')
    helper.chmod(0o755)

    for name, tool in (("ryoku-cmd-ocr", "tesseract"), ("ryoku-cmd-qr-scan", "zbarimg")):
        p = root / "ryoku/shell/scripts" / name
        text = p.read_text()
        if name == "ryoku-cmd-ocr":
            replace_once(p, "for c in tesseract wl-copy notify-send; do need \"$c\"; done",
                         "for c in tesseract notify-send; do need \"$c\"; done\n"
                         "if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then need xclip; else need wl-copy; fi")
        else:
            replace_once(p, "for c in zbarimg wl-copy notify-send xdg-open; do need \"$c\"; done",
                         "for c in zbarimg notify-send xdg-open; do need \"$c\"; done\n"
                         "if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then need xclip; else need wl-copy; fi")
        replace_once(p, "for c in grim slurp; do need \"$c\"; done",
                     "if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then\n"
                     "    for c in maim slop xclip xrandr; do need \"$c\"; done\n"
                     "  else\n    for c in grim slurp; do need \"$c\"; done\n  fi")
        replace_once(p, 'geometry="$(slurp 2>/dev/null)" || exit 130',
                     'if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then\n'
                     '    geometry="$(slop -f \'%g\' 2>/dev/null)" || exit 130\n'
                     '  else\n    geometry="$(slurp 2>/dev/null)" || exit 130\n  fi')
        if name == "ryoku-cmd-ocr":
            replace_once(p, "printf '%s' \"$text\" | wl-copy",
                         "printf '%s' \"$text\" | ryoku-cmd-clipboard-copy text/plain")
        else:
            replace_once(p, "printf '%s' \"$result\" | wl-copy",
                         "printf '%s' \"$result\" | ryoku-cmd-clipboard-copy text/plain")

    p = root / "ryoku/shell/scripts/ryoku-cmd-google-lens"
    replace_once(p, "for command in grim slurp; do",
                 "if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then\n"
                 "  for command in maim slop xrandr; do\n"
                 "    command -v \"$command\" >/dev/null 2>&1 || { notify_failure \"$command is not installed\"; exit 1; }\n"
                 "  done\n"
                 "else\n  for command in grim slurp; do")
    replace_once(p, "\tdone\n\tinput_file=$(mktemp",
                 "\t\tdone\nfi\n\tinput_file=$(mktemp")
    replace_once(p, "geometry=$(slurp 2>/dev/null) || {",
                 "if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then\n"
                 "\tgeometry=$(slop -f '%g' 2>/dev/null) || {\n"
                 "\t\trm -f -- \"$input_file\"\n\t\texit 130\n\t}\n"
                 "\telse\n\tgeometry=$(slurp 2>/dev/null) || {")
    replace_once(p, "\t}\n\t[[ -n $geometry ]] || {",
                 "\t}\n\tfi\n\t[[ -n $geometry ]] || {")

    p = root / "ryoku/shell/quickshell/shell/modules/dock/ii/draw/LiveDrawWindow.qml"
    replace_once(p, "ryoku-cmd-grim -o \"$1\" - | wl-copy --type image/png",
                 "ryoku-cmd-grim -o \"$1\" - | ryoku-cmd-clipboard-copy image/png")
    replace_once(p, 'ryoku-cmd-grim ${1:+-o \"$1\"} \"$f\" && wl-copy --type image/png < \"$f\"',
                 'ryoku-cmd-grim ${1:+-o \"$1\"} \"$f\" && ryoku-cmd-clipboard-copy image/png < \"$f\"')


def patch_lock_dispatch(root: pathlib.Path) -> None:
    p = root / "ryoku/shell/ipc/actions.go"
    old = '''// lockSession locks the screen with qylock, the in-session lock Ryoku ships.
// The shell has no lock surface of its own.
func lockSession() string {
	if err := ensureSessionLocked(time.Now().Add(lockWait)); err != nil {
		return "err lock: " + err.Error()
	}
	return "ok"
}'''
    new = '''// lockSession dispatches to a PAM-backed X11 locker on Xorg. X11 has no
// compositor-confirmed lock proof, so it is never accepted for suspend.
func lockSession() string {
	if rxbX11Session() {
		if isLocked() {
			return "ok"
		}
		if err := spawnX11Locker(); err != nil {
			return "err lock: " + err.Error()
		}
		return "ok"
	}
	if err := ensureSessionLocked(time.Now().Add(lockWait)); err != nil {
		return "err lock: " + err.Error()
	}
	return "ok"
}

func spawnX11Locker() error {
	launcher, err := exec.LookPath("ryoku-x11-lock")
	if err != nil {
		return fmt.Errorf("X11 lock wrapper unavailable: %w", err)
	}
	cmd := exec.Command(launcher)
	if err := cmd.Start(); err != nil {
		return err
	}
	wait := make(chan error, 1)
	go func() { wait <- cmd.Wait() }()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if isLocked() {
			return nil
		}
		select {
		case waitErr := <-wait:
			wait = nil
			if waitErr != nil {
				return fmt.Errorf("X11 lock wrapper exited before a PAM locker became active: %w", waitErr)
			}
		default:
		}
		time.Sleep(25 * time.Millisecond)
	}
	if wait != nil {
		_ = cmd.Process.Kill()
		<-wait
	}
	return fmt.Errorf("X11 lock wrapper did not establish a live PAM locker on display %s within 2 seconds", os.Getenv("DISPLAY"))
}'''
    replace_once(p, old, new)
    old_guard = '''func ensureSessionLocked(deadline time.Time) error {
	lockRequestMu.Lock()'''
    new_guard = '''func ensureSessionLocked(deadline time.Time) error {
	// X11 has no accepted compositor-secure lock-before-suspend handshake.
	// Fail closed even if a stale Wayland qylock marker or process exists.
	if rxbX11Session() {
		return fmt.Errorf("secure lock-before-suspend is not available on X11; suspend and hibernate are disabled")
	}
	lockRequestMu.Lock()'''
    replace_once(p, old_guard, new_guard)

    p = root / "ryoku/shell/ipc/lockrecovery.go"
    text = p.read_text()
    old = '''func (d *daemon) confirmLockRecovery() {
	if d.lockRecovery != nil {'''
    new = '''func (d *daemon) confirmLockRecovery() {
	// qylock recovery watches Wayland proof generations. The X11 locker has
	// its own process lifetime and must not arm a qylock restart loop.
	if rxbX11Session() {
		return
	}
	if d.lockRecovery != nil {'''
    if text.count(old) != 1:
        raise RuntimeError(f"{p}: lock recovery anchor missing")
    text = text.replace(old, new, 1)
    p.write_text(text)

    p = root / "ryoku/shell/ipc/control.go"
    text = p.read_text()
    old = '''// isLocked accepts only generation- and session-bound compositor proof. A
// marker from a killed or different-session locker is stale and removed.
func isLocked() bool {
	marker := lockMarker()'''
    new = '''// isLocked uses a live, trusted locker process for X11 and generation-bound
// compositor proof for Wayland. A fullscreen QML surface is never a lock.
func isLocked() bool {
	if rxbX11Session() {
		return x11LockerActive(os.Getenv("XDG_RUNTIME_DIR"), os.Getenv("DISPLAY"))
	}
	marker := lockMarker()'''
    if text.count(old) != 1:
        raise RuntimeError(f"{p}: lock-state anchor missing")
    text = text.replace(old, new, 1)
    p.write_text(text)

    helper = root / "ryoku/shell/ipc/rxb_x11.go"
    helper.write_text("""package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// rxbTrustedLockerDir is the only directory whose i3lock/xsecurelock binaries
// are accepted as a real X11 locker. It must match locker_dir in
// ryoku-x11-lock.
const rxbTrustedLockerDir = "/usr/bin"

// rxbX11Session reports whether this process belongs to an RXB X11 session.
// It must not depend on WAYLAND_DISPLAY being empty: a stray variable in an
// X11 session must never route lock or suspend into the Wayland path.
func rxbX11Session() bool {
	if os.Getenv("RYOKU_WM") == "i3" || os.Getenv("XDG_SESSION_TYPE") == "x11" {
		return true
	}
	return os.Getenv("WAYLAND_DISPLAY") == "" && os.Getenv("DISPLAY") != ""
}

// normalizeX11Display drops the screen number so ":0" and ":0.0" name the
// same display.
func normalizeX11Display(display string) string {
	colon := strings.LastIndex(display, ":")
	dot := strings.LastIndex(display, ".")
	if colon >= 0 && dot > colon {
		return display[:dot]
	}
	return display
}

// x11LockStateKey mirrors ryoku-x11-lock: the screen number is dropped and
// characters outside [A-Za-z0-9_.-] become underscores.
func x11LockStateKey(display string) string {
	display = normalizeX11Display(display)
	var b strings.Builder
	for _, r := range display {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '.' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	return b.String()
}

// x11LockerActive reports whether the wrapper-recorded locker for this display
// is alive. XSecureLock is non-dumpable, so /proc/PID/{exe,environ} cannot be
// used to find it; ryoku-x11-lock records "<pid> <starttime>" instead.
func x11LockerActive(runtimeDir, display string) bool {
	if runtimeDir == "" || display == "" {
		return false
	}
	path := filepath.Join(runtimeDir, "ryoku-x11-lock", x11LockStateKey(display)+".state")
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return verifyX11LockerState("/proc", string(data), os.Getuid(), rxbTrustedLockerDir)
}

// verifyX11LockerState checks a "<pid> <starttime>" record against procRoot.
// The start time rejects a reused PID; the owner, process name and (when the
// kernel lets us read it) executable path must match a trusted locker.
func verifyX11LockerState(procRoot, state string, uid int, trustedDir string) bool {
	fields := strings.Fields(state)
	if len(fields) != 2 {
		return false
	}
	pid, err1 := strconv.ParseUint(fields[0], 10, 32)
	start, err2 := strconv.ParseUint(fields[1], 10, 64)
	if err1 != nil || err2 != nil || pid == 0 {
		return false
	}
	dir := filepath.Join(procRoot, strconv.FormatUint(pid, 10))
	stat, err := os.ReadFile(filepath.Join(dir, "stat"))
	if err != nil {
		return false
	}
	text := string(stat)
	closing := strings.LastIndex(text, ") ")
	if closing < 0 {
		return false
	}
	rest := strings.Fields(text[closing+2:])
	if len(rest) < 20 || rest[0] == "Z" || rest[0] == "X" {
		return false
	}
	if got, err := strconv.ParseUint(rest[19], 10, 64); err != nil || got != start {
		return false
	}
	status, err := os.ReadFile(filepath.Join(dir, "status"))
	if err != nil {
		return false
	}
	owned := false
	for _, line := range strings.Split(string(status), "\\n") {
		if strings.HasPrefix(line, "Uid:") {
			f := strings.Fields(line)
			owned = len(f) > 1 && f[1] == strconv.Itoa(uid)
			break
		}
	}
	if !owned {
		return false
	}
	comm, err := os.ReadFile(filepath.Join(dir, "comm"))
	if err != nil {
		return false
	}
	switch strings.TrimSpace(string(comm)) {
	case "xsecurelock", "i3lock":
	default:
		return false
	}
	// Readable only for dumpable processes (i3lock). When readable it must be
	// a trusted binary; an unreadable link (xsecurelock) is not a reason to fail.
	if exe, err := os.Readlink(filepath.Join(dir, "exe")); err == nil {
		exe = strings.TrimSuffix(exe, " (deleted)")
		if exe != trustedDir+"/xsecurelock" && exe != trustedDir+"/i3lock" {
			return false
		}
	}
	return true
}
""")

    test = root / "ryoku/shell/ipc/rxb_x11_lock_test.go"
    test.write_text("""package main

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

const fakeStatRest = " 1 4242 4242 0 -1 4194560 100 0 0 0 1 1 0 0 20 0 1 0 987654 1000 100 18446744073709551615"

func fakeProc(t *testing.T, comm, state, uid, exe string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "4242")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("stat", "4242 ("+comm+") "+state+fakeStatRest)
	write("status", "Name:\\t"+comm+"\\nUid:\\t"+uid+"\\t"+uid+"\\t"+uid+"\\t"+uid+"\\n")
	write("comm", comm+"\\n")
	if exe != "" {
		if err := os.Symlink(exe, filepath.Join(dir, "exe")); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestRXBVerifyX11LockerState(t *testing.T) {
	uid := strconv.Itoa(os.Getuid())
	trusted := "/usr/bin"
	good := "4242 987654\\n"
	cases := []struct {
		name  string
		root  string
		state string
		want  bool
	}{
		{"xsecurelock non-dumpable (exe unreadable)", fakeProc(t, "xsecurelock", "S", uid, ""), good, true},
		{"i3lock with trusted exe", fakeProc(t, "i3lock", "S", uid, "/usr/bin/i3lock"), good, true},
		{"trusted exe replaced by upgrade", fakeProc(t, "i3lock", "S", uid, "/usr/bin/i3lock (deleted)"), good, true},
		{"reused PID (start time differs)", fakeProc(t, "xsecurelock", "S", uid, ""), "4242 987655\\n", false},
		{"zombie", fakeProc(t, "xsecurelock", "Z", uid, ""), good, false},
		{"other user", fakeProc(t, "xsecurelock", "S", strconv.Itoa(os.Getuid()+1), ""), good, false},
		{"renamed non-locker process", fakeProc(t, "bash", "S", uid, ""), good, false},
		{"readable but untrusted exe named i3lock", fakeProc(t, "i3lock", "S", uid, "/tmp/i3lock"), good, false},
		{"PATH-installed locker", fakeProc(t, "xsecurelock", "S", uid, "/usr/local/bin/xsecurelock"), good, false},
		{"malformed record", fakeProc(t, "xsecurelock", "S", uid, ""), "garbage", false},
		{"pid zero", fakeProc(t, "xsecurelock", "S", uid, ""), "0 987654", false},
		{"process gone", t.TempDir(), good, false},
	}
	for _, c := range cases {
		if got := verifyX11LockerState(c.root, c.state, os.Getuid(), trusted); got != c.want {
			t.Errorf("%s: verifyX11LockerState = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestRXBX11LockStateKeyMatchesWrapper(t *testing.T) {
	for display, want := range map[string]string{":0": "_0", ":0.0": "_0", ":99.1": "_99", "localhost:10.0": "localhost_10", "unix:1": "unix_1"} {
		if got := x11LockStateKey(display); got != want {
			t.Errorf("x11LockStateKey(%q) = %q, want %q", display, got, want)
		}
	}
}

func TestRXBX11LockerActiveRequiresRecord(t *testing.T) {
	dir := t.TempDir()
	if x11LockerActive(dir, ":99") {
		t.Fatal("no record must mean not locked")
	}
	if x11LockerActive("", ":99") || x11LockerActive(dir, "") {
		t.Fatal("empty runtime dir or display must mean not locked")
	}
}

func TestRXBX11SessionDetectionIgnoresStrayWaylandDisplay(t *testing.T) {
	t.Setenv("DISPLAY", ":99")
	t.Setenv("RYOKU_WM", "i3")
	t.Setenv("XDG_SESSION_TYPE", "x11")
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	if !rxbX11Session() {
		t.Fatal("a stray WAYLAND_DISPLAY routed an RXB X11 session to the Wayland path")
	}
	t.Setenv("RYOKU_WM", "")
	t.Setenv("XDG_SESSION_TYPE", "wayland")
	if rxbX11Session() {
		t.Fatal("a genuine Wayland session was treated as X11")
	}
}
""")

    test = root / "ryoku/shell/ipc/rxb_x11_suspend_guard_test.go"
    test.write_text("""package main

import (
	"strings"
	"testing"
	"time"
)

func TestRXBX11SecureSuspendFailsClosed(t *testing.T) {
	t.Setenv("DISPLAY", ":99")
	t.Setenv("WAYLAND_DISPLAY", "")
	err := ensureSessionLocked(time.Now().Add(time.Second))
	if err == nil || !strings.Contains(err.Error(), "disabled") {
		t.Fatalf("X11 suspend lock gate error = %v, want fail-closed disabled error", err)
	}

	// A stray WAYLAND_DISPLAY inside an RXB X11 session must not reopen the
	// Wayland lock-before-suspend path.
	t.Setenv("RYOKU_WM", "i3")
	t.Setenv("XDG_SESSION_TYPE", "x11")
	t.Setenv("WAYLAND_DISPLAY", "wayland-0")
	err = ensureSessionLocked(time.Now().Add(time.Second))
	if err == nil || !strings.Contains(err.Error(), "disabled") {
		t.Fatalf("stray WAYLAND_DISPLAY gate error = %v, want fail-closed disabled error", err)
	}
}
""")

    p = root / "ryoku/cli/internal/host/power.go"
    text = p.read_text()
    old = '''	case "poweroff", "reboot", "suspend", "hibernate":
		if len(args) != 1 {
			return ExitUsage
		}'''
    new = '''	case "poweroff", "reboot", "suspend", "hibernate":
		if len(args) != 1 {
			return ExitUsage
		}
		if args[0] == "suspend" || args[0] == "hibernate" {
			if rxbX11Session() {
				return a.failf("suspend and hibernate are disabled on X11 until secure lock-before-suspend is implemented")
			}
		}'''
    if text.count(old) != 1:
        raise RuntimeError(f"{p}: host power action anchor missing")
    text = text.replace(old, new, 1)
    p.write_text(text)
    (root / "ryoku/cli/internal/host/rxb_x11.go").write_text("""package host

import "os"

// rxbX11Session reports whether this process belongs to an RXB X11 session.
// A stray WAYLAND_DISPLAY must not re-enable suspend or hibernate there.
func rxbX11Session() bool {
	if os.Getenv("RYOKU_WM") == "i3" || os.Getenv("XDG_SESSION_TYPE") == "x11" {
		return true
	}
	return os.Getenv("WAYLAND_DISPLAY") == "" && os.Getenv("DISPLAY") != ""
}
""")
    test = root / "ryoku/cli/internal/host/rxb_x11_power_guard_test.go"
    test.write_text("""package host

import "testing"

func TestRXBHostPowerRejectsSuspendAndHibernateOnX11(t *testing.T) {
	cases := map[string]map[string]string{
		"plain X11":           {"DISPLAY": ":99", "WAYLAND_DISPLAY": "", "RYOKU_WM": "", "XDG_SESSION_TYPE": ""},
		"stray WAYLAND_DISPLAY": {"DISPLAY": ":99", "WAYLAND_DISPLAY": "wayland-0", "RYOKU_WM": "i3", "XDG_SESSION_TYPE": "x11"},
	}
	for name, env := range cases {
		for key, value := range env {
			t.Setenv(key, value)
		}
		for _, action := range []string{"suspend", "hibernate"} {
			runner := &fakeRunner{}
			app, _, _ := testApp(runner, map[string]string{"RYOKU_HOST_INIT": "systemd", "RYOKU_HOST_PKGMGR": "pacman"})
			if code := app.Power([]string{action}); code == ExitOK {
				t.Fatalf("%s: %s unexpectedly succeeded on X11", name, action)
			}
			if len(runner.commands) != 0 {
				t.Fatalf("%s: %s invoked a host power command: %#v", name, action, runner.commands)
			}
		}
	}
}
""")

def _ternary_counts(expr: str) -> tuple[int, int, int]:
    parens = expr.count("(") - expr.count(")")
    questions = len(re.findall(r"(?<!\?)\?(?![?.])", expr))
    colons = len(re.findall(r"(?<!:):(?!:)", expr))
    return parens, questions, colons


def _convert_x11_layer(expr: str) -> str:
    expr = expr.strip()
    placeholders = {}
    for token, replacement in (
        ("shownLayer", "(shownLayer === WlrLayer.Top || shownLayer === WlrLayer.Overlay)"),
        ("root.surfaceLayer", "(root.surfaceLayer === WlrLayer.Top || root.surfaceLayer === WlrLayer.Overlay)"),
    ):
        if token in expr:
            placeholder = f"__RXB_LAYER_{len(placeholders)}__"
            expr = expr.replace(token, placeholder)
            placeholders[placeholder] = replacement
    expr = re.sub(r"\bWlrLayer\.(?:Top|Overlay)\b", "true", expr)
    expr = re.sub(r"\bWlrLayer\.(?:Bottom|Background)\b", "false", expr)
    if "WlrLayer." in expr:
        raise RuntimeError(f"unhandled WlrLayer expression in X11 overlay: {expr}")
    for placeholder, replacement in placeholders.items():
        expr = expr.replace(placeholder, replacement)
    return expr


def _convert_x11_focus(expr: str) -> str:
    expr = expr.strip()
    placeholder = "__RXB_KEYBOARD_FOCUS__"
    if "shownKeyboardFocus" in expr:
        expr = expr.replace("shownKeyboardFocus", placeholder)
    expr = re.sub(r"\bWlrKeyboardFocus\.(?:Exclusive|OnDemand)\b", "true", expr)
    expr = re.sub(r"\bWlrKeyboardFocus\.None\b", "false", expr)
    if "WlrKeyboardFocus." in expr:
        raise RuntimeError(f"unhandled WlrKeyboardFocus expression in X11 overlay: {expr}")
    return expr.replace(placeholder, "!!shownKeyboardFocus")


def patch_x11_panel_properties(root: pathlib.Path) -> None:
    # PanelWindow's aboveWindows/focusable properties are portable to X11.
    # WlrLayershell's attached object is null on X11, so static attached
    # property assignments must not be evaluated by the shell.
    for p in root.rglob("*.qml"):
        # The qylock package is a separate Wayland security boundary and is
        # deliberately not modified by the desktop-shell X11 adapter.
        if "ryoku/lockscreen/" in p.as_posix():
            continue
        if not p.is_file():
            continue
        try:
            text = p.read_text()
            original_text = text
        except FileNotFoundError:
            # Some upstream optional bundles contain dangling asset symlinks.
            continue
        # Remove the optional Wayland attached-object focus fallback wherever
        # it occurs. The preceding portable PanelWindow focusable assignment
        # is authoritative on X11. Balanced braces handle nested if/else blocks.
        marker = "if (t.WlrLayershell !== undefined) {"
        while marker in text:
            marker_at = text.index(marker)
            block_start = text.rfind("\n", 0, marker_at) + 1
            open_at = text.index("{", marker_at)
            depth = 0
            block_end = None
            for offset in range(open_at, len(text)):
                if text[offset] == "{":
                    depth += 1
                elif text[offset] == "}":
                    depth -= 1
                    if depth == 0:
                        block_end = offset + 1
                        break
            if block_end is None:
                raise RuntimeError(f"{p}: unterminated dynamic Wayland focus block")
            if block_end < len(text) and text[block_end:block_end + 1] == "\n":
                block_end += 1
            text = text[:block_start] + text[block_end:]

        if "WlrLayershell." not in text and text == original_text:
            continue
        if p.name == "VariantRoot.qml":
            text = text.replace("WlrLayershell.focusable:", "focusable:")
            text = text.replace("WlrLayershell.keyboardFocus: dismissLayer.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n", "")
        if p.name == "LyricsPicker.qml":
            text = text.replace("WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand\n", "")
        lines = text.splitlines()
        out = []
        i = 0
        while i < len(lines):
            line = lines[i]
            match = re.match(r"^(\s*)WlrLayershell\.(layer|keyboardFocus|exclusionMode):\s*(.*)$", line)
            if match:
                indent, prop, expr = match.groups()
                parts = [expr.strip()]
                j = i + 1
                while j < len(lines):
                    candidate = lines[j].strip()
                    if not candidate:
                        break
                    parens, questions, colons = _ternary_counts(" ".join(parts))
                    if (parens <= 0 and questions <= colons
                            and not candidate.startswith(("?", ":", "||", "&&"))
                            and not parts[-1].rstrip().endswith(("?", ":", "||", "&&"))):
                        break
                    parts.append(candidate)
                    j += 1
                expression = " ".join(parts).strip()
                if prop == "layer":
                    converted = _convert_x11_layer(expression)
                    out.append(f"{indent}aboveWindows: {converted}")
                elif prop == "keyboardFocus":
                    converted = _convert_x11_focus(expression)
                    out.append(f"{indent}focusable: {converted}")
                else:
                    # PanelWindow exposes the same exclusionMode policy on X11.
                    out.append(f"{indent}exclusionMode: {expression}")
                i = j
                continue
            if re.match(r"^\s*WlrLayershell\.namespace\s*:", line):
                i += 1
                continue
            if re.match(r"^(\s*)WlrLayershell\.focusable:", line):
                line = re.sub(r"WlrLayershell\.focusable:", "focusable:", line, count=1)
            out.append(line)
            i += 1
        patched = "\n".join(out) + ("\n" if text.endswith("\n") else "")
        if re.search(r"\bWlrLayershell\.\w+\s*:", patched):
            raise RuntimeError(f"{p}: X11 PanelWindow property conversion incomplete")
        if re.search(r"\bt\.WlrLayershell\b", patched):
            raise RuntimeError(f"{p}: dynamic Wayland attached-object access remains")
        if patched != original_text:
            p.write_text(patched)


def patch_wayland_consumers(root: pathlib.Path) -> None:
    # The original taskbar/dock paths used Wayland foreign-toplevel objects.
    # RXB's Wm singleton now supplies provider-backed wrappers with activate/close.
    p = root / "ryoku/shell/quickshell/inir/services/TaskbarApps.qml"
    replace_once(p, "import inir.services\n", "import inir.services\nimport Ryoku.Ui.Singletons\n")
    replace_once(p, "target: ToplevelManager.toplevels\n        function onValuesChanged()",
                 "target: Wm\n        function onWindowsChanged()")
    replace_once(p, "(ToplevelManager.toplevels?.values ?? [])", "(Wm.toplevels ?? [])")

    p = root / "ryoku/shell/quickshell/inir/services/TrayService.qml"
    text = p.read_text()
    if "import Ryoku.Ui.Singletons" not in text:
        replace_once(p, "import QtQuick\n", "import QtQuick\nimport Ryoku.Ui.Singletons\n")
    text = p.read_text()
    if "ToplevelManager.toplevels.values" not in text:
        raise RuntimeError(f"{p}: expected foreign-toplevel iteration")
    p.write_text(text.replace("ToplevelManager.toplevels.values", "Wm.toplevels"))

    p = root / "ryoku/shell/quickshell/stage/services/TaskbarApps.qml"
    replace_once(p, "import Quickshell.Wayland\n", "import Quickshell.Wayland\nimport Ryoku.Ui.Singletons as RyokuUi\n")
    replace_once(p, "ToplevelManager.toplevels.values", "RyokuUi.Wm.toplevels")

    p = root / "ryoku/shell/quickshell/shell/modules/dock/ii/services/TaskbarApps.qml"
    replace_once(p, "ToplevelManager.toplevels.values", "RyokuUi.Wm.toplevels")

    p = root / "ryoku/shell/quickshell/shell/modules/dock/ii/services/DockLivePreviewService.qml"
    replace_once(p, "(ToplevelManager.toplevels?.values ?? [])", "(Wm.toplevels ?? [])")
    replace_once(p, "target: ToplevelManager\n\n        function onActiveToplevelChanged()", "target: Wm\n\n        function onFocusedWindowChanged()")

    p = root / "ryoku/shell/quickshell/shell/modules/bar/barstyles/nomarchy/services/AppLibrary.qml"
    replace_once(p, "try { return ToplevelManager.toplevels.values.length } catch (e) { return 0 }",
                 "return Wm.windows.length")
    replace_once(p, "root.launchActiveToplevel = ToplevelManager.activeToplevel",
                 'root.launchActiveToplevel = Wm.focusedWindow ? String(Wm.focusedWindow.id) : ""')
    replace_once(p, "ToplevelManager.activeToplevel === root.launchActiveToplevel",
                 '(Wm.focusedWindow ? String(Wm.focusedWindow.id) : "") === root.launchActiveToplevel')
    replace_once(p, "target: ToplevelManager.toplevels\n    function onValuesChanged()",
                 "target: Wm\n    function onWindowsChanged()")
    replace_once(p, "target: ToplevelManager\n    function onActiveToplevelChanged()",
                 "target: Wm\n    function onFocusedWindowChanged()")
    replace_once(p, "ToplevelManager.activeToplevel !== root.launchActiveToplevel",
                 '(Wm.focusedWindow ? String(Wm.focusedWindow.id) : "") !== root.launchActiveToplevel')


def patch_ryogami_package(root: pathlib.Path) -> None:
    p = root / "release/packages/ryogami/PKGBUILD"
    replace_once(p, "'qt6-multimedia' 'qt6-imageformats' 'skwd-paper-bin'",
                 "'qt6-multimedia' 'qt6-imageformats'")
    replace_once(p, "optdepends=('yt-dlp: YouTube wallpaper source'",
                 "optdepends=('skwd-paper-bin: optional Wallpaper Engine scene renderer'\\n"
                 "            'yt-dlp: YouTube wallpaper source'")


def patch_x11_package_safety(root: pathlib.Path) -> None:
    # The upstream desktop package normally installs distribution-wide boot,
    # udev, modprobe, polkit, logind and SDDM integration. RXB must not apply
    # those host policies to the user's existing CachyOS/BSPWM/SDDM install.
    p = root / "release/packages/ryoku-desktop/payload.sh"
    text = p.read_text()
    old_manifest = '  install -Dm644 "$_repo/system/services/manifest.tsv" ' + chr(92) + '\n    "$pkgdir/usr/share/ryoku/services.tsv"'
    new_manifest = ('  if [[ ${RYOKU_X11_BRIDGE:-0} != 1 ]]; then\n'
                    '    install -Dm644 "$_repo/system/services/manifest.tsv" ' + chr(92) + '\n'
                    '      "$pkgdir/usr/share/ryoku/services.tsv"\n'
                    '  fi')
    if text.count(old_manifest) != 1:
        raise RuntimeError(f"{p}: system service manifest install anchor missing")
    text = text.replace(old_manifest, new_manifest, 1)
    start = text.index("# the qylock lockscreen bundle + its installer")
    end = text.index("  if [[ $RYOKU_INIT_MODE == systemd ]]; then\n    # Keep session-critical units", start)
    text = text[:start] + '  if [[ ${RYOKU_X11_BRIDGE:-0} != 1 ]]; then\n' + text[start:end] + '  fi\n\n' + text[end:]

    # Do not install environment.d or session environment generators globally:
    # they would change the user's existing BSPWM/SDDM session as well.
    start = text.index("# The AI-usage collectors behind the qsbar AI pill ship with ryoku-rashin.")
    end = text.index("  # the decor art", start)
    text = text[:start] + '  if [[ ${RYOKU_X11_BRIDGE:-0} != 1 ]]; then\n' + text[start:end] + '  fi\n\n' + text[end:]

    old_nautilus = '  install -Dm644 "$_repo/ryoku/apps/nautilus/ryoku-stash-menu.py" ' + chr(92) + '\n    "$pkgdir/usr/share/nautilus-python/extensions/ryoku-stash-menu.py"'
    new_nautilus = ('  if [[ ${RYOKU_X11_BRIDGE:-0} != 1 ]]; then\n'
                    '    install -Dm644 "$_repo/ryoku/apps/nautilus/ryoku-stash-menu.py" ' + chr(92) + '\n'
                    '      "$pkgdir/usr/share/nautilus-python/extensions/ryoku-stash-menu.py"\n'
                    '  fi')
    if text.count(old_nautilus) != 1:
        raise RuntimeError(f"{p}: Nautilus extension install anchor missing")
    text = text.replace(old_nautilus, new_nautilus, 1)

    old_hw_helpers = '''  for s in "$_repo"/system/hardware/*/ryoku-*; do
    [[ -f $s && -x $s ]] || continue
    install -Dm755 "$s" "$pkgdir/usr/bin/${s##*/}"
  done'''
    new_hw_helpers = '''  if [[ ${RYOKU_X11_BRIDGE:-0} != 1 ]]; then
    for s in "$_repo"/system/hardware/*/ryoku-*; do
      [[ -f $s && -x $s ]] || continue
      install -Dm755 "$s" "$pkgdir/usr/bin/${s##*/}"
    done
  fi'''
    if text.count(old_hw_helpers) != 1:
        raise RuntimeError(f"{p}: system hardware helper loop anchor missing")
    text = text.replace(old_hw_helpers, new_hw_helpers, 1)

    start = text.index("  # GPU primary-renderer udev rule")
    end = text.rindex('\n}\ncase "${1:-}" in')
    text = text[:start] + '  if [[ ${RYOKU_X11_BRIDGE:-0} != 1 ]]; then\n' + text[start:end] + '\n  fi' + text[end:]
    p.write_text(text)

    # Package hooks become metadata refresh only; no host service reconciliation,
    # power-policy changes, hardware rules, boot/UKI updates or SDDM changes.
    safe_install = root / "release/packages/ryoku-desktop/ryoku-desktop.install"
    safe_install.write_text('''# RXB X11 variant: intentionally non-destructive package hooks.
_hint() {
  cat <<'EOF'
==> RXB installed the Ryoku X11/i3 session without changing SDDM, the existing
    lock screen, boot configuration, GPU drivers, or system services.
    Select "Ryoku (X11 / i3)" only when ready to test the session.
EOF
}
_refresh() {
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications 2>/dev/null || true
}
pre_install() { :; }
pre_upgrade() { :; }
post_install() { _refresh; _hint; }
post_upgrade() { _refresh; _hint; }
post_remove() { _refresh; }
''')

    p = root / "release/packages/ryoku-desktop/PKGBUILD"
    text = p.read_text()
    # RXB is an X11 session. Remove Wayland-only helpers and DKMS from the
    # base package's hard dependencies; DKMS can trigger kernel-module rebuild
    # hooks on the host and is needed only for optional xpadneo controller support.
    for dep in ("'xorg-xwayland'", "'qt6-wayland'", "'qt5-wayland'", "'weston'",
                "'wl-clipboard'", "'wl-clip-persist'", "'grim'", "'slurp'",
                "'wtype'", "'hypridle'", "'hyprpicker'", "'dkms'"):
        text = re.sub(r"(?m)^  " + re.escape(dep) + r"(?:[ \t]+#.*)?\n", "", text)

    text = text.replace(
        "  # Two clients the Hyprland variant used to own that are protocol-neutral, not\n"
        "  # Hyprland-specific: niri serves ext-idle-notify-v1 and wlr-screencopy/layer-\n"
        "  # shell just the same. Shipping only with the Hyprland variant left a niri box\n"
        "  # with no idle management and a dead color picker everywhere; base reaches both.\n",
        "  # RXB deliberately does not install Wayland idle or color-picker helpers.\n"
        "  # Those features remain gated in the X11 session.\n",
    )
    text = text.replace(
        "  # Game controllers: xpadneo-dkms (Xbox One/Series Bluetooth pads, from the AUR\n"
        "  # step) needs DKMS and headers for every installed kernel. The installer pairs\n"
        "  # each shipped kernel with its headers, and doctor fills a missing\n"
        "  # <kernel>-headers package on existing Arch and CachyOS boxes. Keeping only\n"
        "  # dkms here avoids forcing stock linux-headers onto a box that has no stock\n"
        "  # linux kernel.\n",
        "  # DKMS is optional in RXB: it is only needed for the separate xpadneo\n"
        "  # Xbox controller driver and must not trigger kernel-module rebuild hooks\n"
        "  # merely because an X11 desktop session is installed.\n",
    )
    text = text.replace(
        "optdepends=(\n",
        "optdepends=(\n"
        "  'dkms: optional xpadneo-dkms Xbox controller driver support'\n",
        1,
    )
    old = '  RYOKU_SRC="$_repo" ' + chr(92) + "\n"
    if text.count(old) != 2:
        raise RuntimeError(f"{p}: expected two payload environment blocks, found {text.count(old)}")
    new = ('  RYOKU_X11_BRIDGE=1 ' + chr(92) + "\n"
           '  RYOKU_SRC="$_repo" ' + chr(92) + "\n")
    text = text.replace(old, new)
    p.write_text(text)

    p = root / "release/packages/ryoku-desktop/PKGBUILD"
    replace_once(p, "  'ryoku-keyring'\n", "")

    p = root / "release/packages/ryoku-shell/PKGBUILD"
    text = p.read_text().replace("'wtype'", "").replace("'wl-clipboard'", "")
    p.write_text(text)

    # The upstream boot guard is a host-wide update recovery mechanism. It
    # can inspect/repoint /boot/limine.conf and EFI variables before the
    # display manager starts. RXB does not own boot/update policy, and the
    # original tmpfiles rules also mutate /etc/ryoku, /var/lib/ryoku and
    # SDDM greeter hand-off files. Do not ship either file in the X11 build.
    p = root / "release/packages/ryoku/payload.sh"
    replace_once(
        p,
        '''\tif [ "$init" = systemd ]; then
\t\tinstall -Dm644 "$RYOKU_SRC/ryoku/cli/systemd/ryoku-boot-guard.service" \\
\t\t\t"$destdir/usr/lib/systemd/system/ryoku-boot-guard.service"
\t\tinstall -Dm644 "$RYOKU_SRC/ryoku/cli/systemd/ryoku.tmpfiles.conf" \\
\t\t\t"$destdir/usr/lib/tmpfiles.d/ryoku.conf"
\telse''',
        '''\tif [ "$init" = systemd ]; then
\t\tif [ "${RYOKU_X11_BRIDGE:-0}" != 1 ]; then
\t\t\tinstall -Dm644 "$RYOKU_SRC/ryoku/cli/systemd/ryoku-boot-guard.service" \\
\t\t\t\t"$destdir/usr/lib/systemd/system/ryoku-boot-guard.service"
\t\t\tinstall -Dm644 "$RYOKU_SRC/ryoku/cli/systemd/ryoku.tmpfiles.conf" \\
\t\t\t\t"$destdir/usr/lib/tmpfiles.d/ryoku.conf"
\t\tfi
\telse''',
    )
    p = root / "release/packages/ryoku/PKGBUILD"
    text = p.read_text()
    old = '  RYOKU_SRC="$_repo" ' + chr(92) + "\n"
    if text.count(old) != 2:
        raise RuntimeError(f"{p}: expected two payload environment blocks, found {text.count(old)}")
    text = text.replace(
        old,
        '  RYOKU_X11_BRIDGE=1 ' + chr(92) + "\n" + old,
    )
    p.write_text(text)

    # The stock Ryoku updater/doctor can manage the host OS, boot entries,
    # services and package state. RXB is a session integration, not a distro
    # manager: make doctor read-only and refuse host update/boot workflows.
    p = root / "ryoku/cli/main.go"
    replace_once(
        p,
        "func main() {",
        """func rxbGuardCommand(command string, args []string) ([]string, bool) {
	switch command {
	case "update", "rollback", "boot-guard", "boot-menu", "deploy", "recovery", "track":
		return args, true
	case "doctor":
		if len(args) == 0 || args[0] != "--check" {
			args = append([]string{"--check"}, args...)
		}
	}
	return args, false
}

func main() {""",
    )
    replace_once(
        p,
        """	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error""",
        """	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	guardedArgs, blocked := rxbGuardCommand(os.Args[1], os.Args[2:])
	if blocked {
		die("'%s' is disabled in the RXB X11 build; host update, rollback and boot management remain under the existing OS.", os.Args[1])
	}
	os.Args = append([]string{os.Args[0], os.Args[1]}, guardedArgs...)
	var err error""",
    )

    # Never let a generic doctor reconciliation rewrite the host's system or
    # user service activation roster in an RXB session.
    p = root / "ryoku/cli/internal/host/command.go"
    replace_once(
        p,
        """func (a *App) Execute(args []string) int {
	if len(args) == 0 {""",
        """func rxbHostCommandBlocked(args []string) bool {
	if len(args) < 2 {
		return false
	}
	switch args[0] {
	case "pkg":
		switch args[1] {
		case "installed", "installed-at", "available", "status", "why", "advice", "version", "owner", "count", "local":
			return false
		default:
			return true
		}
	case "users":
		return args[1] != "list" && args[1] != "caps"
	case "auth":
		return !(args[1] == "fingerprint" && len(args) == 3 && args[2] == "status")
	case "network":
		return true
	case "time":
		return args[1] != "zone" && args[1] != "zones"
	case "keymap":
		return true
	case "phone":
		return args[1] != "status"
	case "power":
		return args[1] != "capabilities" && args[1] != "reboot" && args[1] != "poweroff" &&
			!(args[1] == "profile" && len(args) >= 3 && args[2] == "get")
	case "snapshots":
		return len(args) > 1 && args[1] == "create"
	case "transient":
		return true
	case "svc":
		if args[1] == "reconcile" {
			return true
		}
		scope := "--user"
		verbIndex := 1
		for verbIndex < len(args) && (args[verbIndex] == "--user" || args[verbIndex] == "--system") {
			scope = args[verbIndex]
			verbIndex++
		}
		if verbIndex >= len(args) {
			return false
		}
		verb := args[verbIndex]
		switch verb {
		case "enable", "disable":
			// Persistent activation changes can leak upstream Ryoku units into
			// BSPWM or other sessions. RXB owns only its dedicated session target.
			return true
		case "start", "stop", "restart", "try-restart", "reload", "kill", "reset-failed", "daemon-reload":
			if scope == "--system" {
				return true
			}
			for _, name := range args[verbIndex+1:] {
				switch name {
				case "ryoku-boot-guard", "ryoku-boot-guard.service", "ryoku-shell", "ryoku-shell.service", "ryogami", "ryogami.service":
					return true
				}
			}
		}
	case "session":
		return args[1] == "start" || args[1] == "ensure" || args[1] == "fix-wrappers"
	case "repo":
		return args[1] == "set-channel" || args[1] == "sync"
	case "initramfs":
		return args[1] == "rebuild"
	}
	return false
}

func (a *App) Execute(args []string) int {
	if len(args) == 0 {""",
    )
    replace_once(
        p,
        """	if args[0] == "--help" || args[0] == "-h" || args[0] == "help" {
		fmt.Fprint(a.cfg.Stdout, Usage)
		return ExitOK
	}
	switch args[0] {""",
        """	if args[0] == "--help" || args[0] == "-h" || args[0] == "help" {
		fmt.Fprint(a.cfg.Stdout, Usage)
		return ExitOK
	}
	if rxbHostCommandBlocked(args) {
		fmt.Fprintln(a.cfg.Stderr, "ryoku-host: this host-wide mutation is disabled in the RXB X11 build; RXB does not own system service, session bootstrap, repository, initramfs or suspend/hibernate policy.")
		return ExitFalse
	}
	switch args[0] {""",
    )

    (root / "ryoku/cli/main_rxb_guard_test.go").write_text("""package main

import "testing"

func TestRXBGuardBlocksHostUpdateAndBootCommands(t *testing.T) {
	for _, command := range []string{"update", "rollback", "boot-guard", "boot-menu", "deploy", "recovery", "track"} {
		if _, blocked := rxbGuardCommand(command, nil); !blocked {
			t.Errorf("%q should be blocked in the RXB X11 build", command)
		}
	}
}

func TestRXBGuardMakesDoctorReadOnly(t *testing.T) {
	args, blocked := rxbGuardCommand("doctor", []string{"--explain"})
	if blocked {
		t.Fatal("doctor should remain available in read-only mode")
	}
	if len(args) != 2 || args[0] != "--check" || args[1] != "--explain" {
		t.Fatalf("doctor args = %#v, want --check --explain", args)
	}
	if _, blocked := rxbGuardCommand("doctor", []string{"--check"}); blocked {
		t.Fatal("explicit read-only doctor check should be allowed")
	}
}
""")
    (root / "ryoku/cli/internal/host/command_rxb_guard_test.go").write_text("""package host

import "testing"

func TestRXBHostGuardBlocksSystemServiceMutationsAndPersistentActivation(t *testing.T) {
	blockedCases := [][]string{
		{"svc", "--system", "enable", "ryoku-boot-guard"},
		{"svc", "--system", "start", "ryoku-boot-guard"},
		{"svc", "--system", "restart", "NetworkManager"},
		{"svc", "--user", "--system", "start", "NetworkManager"},
		{"svc", "--user", "enable", "ryoku-shell"},
		{"svc", "--user", "disable", "ryogami"},
		{"svc", "--user", "start", "ryoku-shell"},
		{"power", "suspend"},
		{"power", "hibernate"},
		{"session", "start"},
		{"pkg", "install", "example"},
		{"pkg", "remove", "example"},
		{"users", "delete", "example", "--erase-files"},
		{"users", "set-password", "example"},
		{"auth", "fingerprint", "set", "sudo", "on"},
		{"network", "wifi-backend", "get"},
		{"network", "wifi-backend", "set", "iwd"},
		{"time", "set-zone", "Etc/UTC"},
		{"keymap", "set", "us"},
		{"phone", "enable"},
		{"power", "profile", "performance"},
		{"power", "profile", "set", "balanced"},
		{"snapshots", "create", "before-test"},
		{"transient", "start", "example"},
	}
	for _, args := range blockedCases {
		if !rxbHostCommandBlocked(args) {
			t.Errorf("%v should be blocked in the RXB X11 build", args)
		}
	}
}

func TestRXBHostGuardKeepsReadOnlyAndSessionScopedActions(t *testing.T) {
	allowedCases := [][]string{
		{"svc", "--user", "is-active", "ryoku-shell"},
		{"svc", "--user", "start", "pipewire"},
		{"svc", "--system", "is-active", "NetworkManager"},
		{"power", "reboot"},
		{"power", "capabilities"},
		{"power", "profile", "get", "balanced"},
		{"pkg", "installed", "quickshell"},
		{"users", "list"},
		{"users", "caps"},
		{"auth", "fingerprint", "status"},
		{"time", "zone"},
		{"time", "zones"},
		{"phone", "status"},
		{"session", "check"},
	}
	for _, args := range allowedCases {
		if rxbHostCommandBlocked(args) {
			t.Errorf("%v should remain available", args)
		}
	}
}

func TestRXBHostMutationsAreBlockedBeforeHostRunner(t *testing.T) {
	blockedCases := [][]string{
		{"svc", "--system", "start", "NetworkManager"},
		{"svc", "--user", "enable", "ryoku-shell"},
		{"session", "start"},
		{"power", "suspend"},
		{"snapshots", "create", "before-test"},
	}
	for _, args := range blockedCases {
		runner := &fakeRunner{}
		app, _, _ := testApp(runner, nil)
		if code := app.Execute(args); code != ExitFalse {
			t.Fatalf("%v exit = %d, want blocked", args, code)
		}
		if len(runner.commands) != 0 {
			t.Fatalf("%v unexpectedly reached host command runner: %#v", args, runner.commands)
		}
	}
}

func TestRXBPowerBlocksSuspendAndHibernateBeforeRunningHostCommands(t *testing.T) {
	for _, action := range []string{"suspend", "hibernate"} {
		runner := &fakeRunner{}
		app, _, _ := testApp(runner, nil)
		if code := app.Execute([]string{"power", action}); code != ExitFalse {
			t.Fatalf("%s exit = %d, want blocked", action, code)
		}
		if len(runner.commands) != 0 {
			t.Fatalf("%s unexpectedly reached host command runner: %#v", action, runner.commands)
		}
	}
}
""")
    # The upstream power test must reflect RXB's fail-closed sleep policy.
    p = root / "ryoku/cli/internal/host/power_test.go"
    replace_once(
        p,
        '''for _, action := range []string{"poweroff", "reboot", "suspend", "hibernate"} {''',
        '''for _, action := range []string{"poweroff", "reboot"} {''',
    )
    # The upstream host package tests exercise generic distro-management
    # commands. In RXB, initramfs rebuild and session bootstrap are deliberately
    # blocked; adapt those expectations instead of weakening the runtime guard.
    p = root / "ryoku/cli/internal/host/initramfs_test.go"
    replace_once(
        p,
        '''if code := app.Execute([]string{"initramfs", "rebuild"}); code != ExitOK {
				t.Fatalf("initramfs rebuild exit = %d", code)
			}''',
        '''if code := app.Execute([]string{"initramfs", "rebuild"}); code != ExitFalse {
				t.Fatalf("RXB initramfs rebuild exit = %d, want blocked", code)
			}
			if len(runner.commands) != 0 {
				t.Fatalf("blocked initramfs rebuild reached host runner: %#v", runner.commands)
			}''',
    )
    replace_once(
        p,
        '''if code := app.Execute([]string{"initramfs", "rebuild"}); code != ExitOK {
		t.Fatalf("initramfs rebuild exit = %d", code)
	}
	if got := argv(runner.commands[0]); got != "pkexec ryoku-host initramfs rebuild" {
		t.Fatalf("escalation = %q", got)
	}''',
        '''if code := app.Execute([]string{"initramfs", "rebuild"}); code != ExitFalse {
		t.Fatalf("RXB initramfs rebuild exit = %d, want blocked", code)
	}
	if len(runner.commands) != 0 {
		t.Fatalf("blocked initramfs rebuild reached host runner: %#v", runner.commands)
	}''',
    )
    replace_once(
        p,
        '''if code := app.Execute([]string{"initramfs", "rebuild"}); code != ExitAbsent {
		t.Fatalf("missing dracut exit = %d, want %d", code, ExitAbsent)
	}
	if stderr.String() != "dracut is not installed\\n" {
		t.Fatalf("missing dracut stderr = %q", stderr.String())
	}''',
        '''if code := app.Execute([]string{"initramfs", "rebuild"}); code != ExitFalse {
		t.Fatalf("RXB initramfs rebuild exit = %d, want blocked", code)
	}
	if len(app.cfg.Runner.(*fakeRunner).commands) != 0 {
		t.Fatal("blocked initramfs rebuild reached host runner")
	}''',
    )

    replace_once(
        p,
        '''			got := make([]string, len(runner.commands))
			for index := range runner.commands {
				got[index] = argv(runner.commands[index])
			}
			if !reflect.DeepEqual(got, test.commands) {
				t.Fatalf("commands = %v, want %v", got, test.commands)
			}''',
        '''			if len(runner.commands) != 0 {
				t.Fatalf("blocked initramfs rebuild reached host runner: %#v", runner.commands)
			}''',
    )
    replace_once(
        p,
        '''app, _, stderr := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": "dnf"})''',
        '''app, _, _ := testApp(&fakeRunner{}, map[string]string{"RYOKU_HOST_PKGMGR": "dnf"})''',
    )

    p = root / "ryoku/cli/internal/host/turnstile_test.go"
    replace_once(
        p,
        '''	for _, args := range [][]string{
		{"session", "ensure", "--system"},
		{"session", "ensure", "--user"},
		{"session", "check"},
		{"session", "fix-wrappers", "--backup-dir", "/unused"},
	} {
		if code := app.Execute(args); code != ExitOK {
			t.Fatalf("%v exit = %d", args, code)
		}
	}''',
        '''	for _, test := range []struct {
		args []string
		want int
	}{
		{[]string{"session", "ensure", "--system"}, ExitFalse},
		{[]string{"session", "ensure", "--user"}, ExitFalse},
		{[]string{"session", "check"}, ExitOK},
		{[]string{"session", "fix-wrappers", "--backup-dir", "/unused"}, ExitFalse},
	} {
		if code := app.Execute(test.args); code != test.want {
			t.Fatalf("%v exit = %d, want %d", test.args, code, test.want)
		}
	}''',
    )

    (root / "ryoku/cli/internal/host/rxb_guard_test.go").write_text("""package host

import (
	"strings"
	"testing"
)

func TestRXBBlocksServiceReconciliation(t *testing.T) {
	runner := &fakeRunner{}
	app, _, stderr := testApp(runner, nil)
	if got := app.Execute([]string{"svc", "reconcile", "--system"}); got != ExitFalse {
		t.Fatalf("svc reconcile exit = %d, want %d", got, ExitFalse)
	}
	if !strings.Contains(stderr.String(), "disabled in the RXB X11 build") {
		t.Fatalf("missing RXB safety explanation: %q", stderr.String())
	}
	if len(runner.commands) != 0 {
		t.Fatalf("blocked command reached host runner: %#v", runner.commands)
	}
	for _, args := range [][]string{
		{"svc", "--system", "is-active", "NetworkManager"},
		{"repo", "channel"},
		{"pkg", "installed", "quickshell"},
		{"power", "capabilities"},
	} {
		if rxbHostCommandBlocked(args) {
			t.Errorf("read-only command should not be blocked: %#v", args)
		}
	}
	for _, args := range [][]string{
		{"svc", "reconcile", "--system"},
		{"session", "ensure", "--user"},
		{"session", "fix-wrappers"},
		{"repo", "set-channel", "testing"},
		{"repo", "sync"},
		{"initramfs", "rebuild"},
	} {
		if !rxbHostCommandBlocked(args) {
			t.Errorf("host-wide mutation should be blocked: %#v", args)
		}
	}
}
""")

    # Snapshot creation is a host-wide snapper mutation. Keep normal
    # discovery/label tests, but skip tests whose premise is that RXB may invoke
    # the privileged snapshot writer.
    p = root / "ryoku/cli/internal/host/snapshots_test.go"
    for test_name in (
        "TestSnapshotCreateRunsNumberedSnapshotAndCleanup",
        "TestSnapshotCreateStopsAfterSnapperFailure",
        "TestSnapshotCreateRequiresToolAndRootConfig",
        "TestSnapshotCreateKeepsUnsupportedReason",
        "TestSnapshotsUnavailableInSnapshotLookBoot",
    ):
        old = f"func {test_name}(t *testing.T) {{"
        new = old + '\\n\\tt.Skip("RXB disables host snapshot creation")'
        replace_once(p, old, new)

def patch_x11_privileged_hub_backends(root: pathlib.Path) -> None:
    # RXB is a session bridge, not a host administrator. Keep read-only GPU
    # discovery and dry-run plans, but block every GPU operation that would
    # escalate or write host configuration/sysfs.
    p = root / "ryoku/hub/backend/gpuapply.go"
    replace_once(p, '''\tfor _, a := range args[1:] {
\t\tif a == "--dry-run" {
\t\t\tdryRun = true
\t\t}
\t}
\tif action == "enable" {''',
                 '''\tfor _, a := range args[1:] {
\t\tif a == "--dry-run" {
\t\t\tdryRun = true
\t\t}
\t}
\tif !dryRun {
\t\treturn fmt.Errorf("GPU passthrough host changes are disabled in the RXB X11 build")
\t}
\tif action == "enable" {''')
    p = root / "ryoku/hub/backend/gputune.go"
    replace_once(p, '''\tif len(args) == 0 {
\t\treturn fmt.Errorf("gpu tune needs caps|get|set|reset")
\t}
\tswitch args[0] {''',
                 '''\tif len(args) == 0 {
\t\treturn fmt.Errorf("gpu tune needs caps|get|set|reset")
\t}
\tif args[0] == "set" || args[0] == "reset" || args[0] == "preset" {
\t\treturn fmt.Errorf("live GPU tuning is disabled in the RXB X11 build")
\t}
\tswitch args[0] {''')
    # GPU mode and firmware MUX changes are separate host mutation paths
    # from passthrough/tuning. Keep their status queries, deny all writes.
    p = root / "ryoku/hub/backend/gpumode.go"
    replace_once(p, '''\tcase "set":
\t\tif len(args) < 2 {''',
                 '''\tcase "set":
\t\treturn fmt.Errorf("GPU render-mode changes are disabled in the RXB X11 build")
\t\tif len(args) < 2 {''')
    p = root / "ryoku/hub/backend/gpumux.go"
    replace_once(p, '''\tcase "set":
\t\tif len(args) < 2 || (args[1] != "hybrid" && args[1] != "discrete") {''',
                 '''\tcase "set":
\t\treturn fmt.Errorf("GPU display-routing MUX changes are disabled in the RXB X11 build")
\t\tif len(args) < 2 || (args[1] != "hybrid" && args[1] != "discrete") {''')

    # The upstream lock page can change PAM/keyring settings and install an
    # SDDM greeter theme through pkexec. RXB must preserve the existing Orbital
    # greeter and Quickshell X11 lockscreen, so deny both command entry points.
    p = root / "ryoku/hub/backend/lock.go"
    replace_once(p, '''\tcase "set":
\t\tif len(args) < 2 {
\t\t\treturn fmt.Errorf("lock set needs a slug")
\t\t}
\t\treturn setLockSkin(args[1])
\tcase "apply-greeter":
\t\tif len(args) < 3 {
\t\t\treturn fmt.Errorf("lock apply-greeter needs a slug and true or false")
\t\t}
\t\tclock24h, err := strconv.ParseBool(args[2])
\t\tif err != nil {
\t\t\treturn fmt.Errorf("invalid clock format %q", args[2])
\t\t}
\t\treturn applyGreeter(args[1], clock24h)''',
                 '''\tcase "set", "apply-greeter":
\t\treturn fmt.Errorf("host lockscreen, PAM and SDDM changes are disabled in the RXB X11 build")''')

    # Display-layout changes must not publish a new SDDM greeter primary-output
    # hint into /var/lib/ryoku on the host.
    p = root / "ryoku/hub/backend/outputs.go"
    replace_once(p, '''func publishGreeterPrimary(layout []wm.OutputLayout) {
\t// The page's''',
                 '''func publishGreeterPrimary(layout []wm.OutputLayout) {
\tif os.Getenv("RYOKU_X11_BRIDGE") == "1" {
\t\treturn
\t}
\t// The page's''')

    # Keep the settings visible but disable every control that can mutate
    # GPU mode, CPU host profiles, PAM or SDDM in the RXB build.
    p = root / "ryoku/hub/quickshell/pages/GpuPage.qml"
    replace_once(p, '''                SettingCard {
                    width: gfxCol.colWidth
                    title: I18n.tr("RYOKU RENDERS ON")''',
                 '''                SettingCard {
                    width: gfxCol.colWidth
                    visible: false // RXB keeps GPU mode and firmware MUX read-only.
                    title: I18n.tr("RYOKU RENDERS ON")''')
    replace_once(p, '''                SettingCard {
                    width: gfxCol.colWidth
                    title: I18n.tr("CPU POWER PROFILES")''',
                 '''                SettingCard {
                    width: gfxCol.colWidth
                    visible: false // RXB does not apply host power profiles.
                    title: I18n.tr("CPU POWER PROFILES")''')
    p = root / "ryoku/hub/quickshell/pages/LockscreenPage.qml"
    replace_once(p, '''Item {
    id: pg''',
                 '''Item {
    id: pg
    enabled: false // RXB preserves the existing SDDM Orbital and Quickshell X11 lockscreen.''')

    p = root / "ryoku/hub/backend/rxb_privileged_host_test.go"
    p.write_text("""package main

import (
    "os"
    "path/filepath"
    "testing"

    wm "ryoku-wm"
)

func TestRXBBlocksGpuModeAndMuxWrites(t *testing.T) {
    if err := runGpuMode([]string{"set", "performance"}); err == nil {
        t.Fatal("GPU render-mode mutation unexpectedly allowed")
    }
    if err := runGpuMux([]string{"set", "discrete"}); err == nil {
        t.Fatal("GPU firmware MUX mutation unexpectedly allowed")
    }
}

func TestRXBBlocksLockscreenAndGreeterMutations(t *testing.T) {
    for _, args := range [][]string{
        {"set", "clockwork/orbital"},
        {"apply-greeter", "clockwork/orbital", "true"},
    } {
        if err := runLock(args); err == nil {
            t.Fatalf("runLock(%v) unexpectedly allowed a host lockscreen/SDDM mutation", args)
        }
    }
}

func TestRXBDoesNotPublishGreeterPrimaryOutput(t *testing.T) {
    t.Setenv("RYOKU_X11_BRIDGE", "1")
    path := filepath.Join(t.TempDir(), "greeter-primary")
    t.Setenv("RYOKU_GREETER_PRIMARY_FILE", path)
    publishGreeterPrimary([]wm.OutputLayout{{Name: "DP-1", Enabled: true, X: 0, Y: 0}})
    if _, err := os.Stat(path); !os.IsNotExist(err) {
        t.Fatalf("RXB wrote SDDM greeter primary-output state: stat err = %v", err)
    }
}
""")

    # Hide the corresponding Hub controls as well as enforcing backend guards;
    # no UI action should reach pkexec in an RXB session.
    p = root / "ryoku/hub/quickshell/pages/GpuPage.qml"
    replace_once(p, '''                SettingCard {
                    width: gfxCol.colWidth
                    title: I18n.tr("TUNING · THIS SESSION")''',
                 '''                SettingCard {
                    width: gfxCol.colWidth
                    visible: false // RXB keeps host GPU tuning read-only.
                    title: I18n.tr("TUNING · THIS SESSION")''')
    replace_once(p, '''                SettingCard {
                    width: gfxCol.colWidth
                    title: I18n.tr("GPU PASSTHROUGH · ADVANCED")''',
                 '''                SettingCard {
                    width: gfxCol.colWidth
                    visible: false // RXB never changes host passthrough or kernel configuration.
                    title: I18n.tr("GPU PASSTHROUGH · ADVANCED")''')

    p = root / "ryoku/hub/backend/gpuapply_rxb_test.go"
    p.write_text("""package main

import (
    "strings"
    "testing"
)

func TestRXBGpuPassthroughMutationBlockedBeforePrivilegeEscalation(t *testing.T) {
    for _, args := range [][]string{{"enable"}, {"disable"}} {
        err := runGpuApply(args)
        if err == nil || !strings.Contains(err.Error(), "disabled in the RXB X11 build") {
            t.Fatalf("runGpuApply(%v) = %v, want RXB fail-closed error", args, err)
        }
    }
}

func TestRXBGpuPassthroughDryRunRemainsAvailable(t *testing.T) {
    // Dry-run may report a plan, but must never apply it. The test uses a
    // temporary etc root and only asserts that no host files are created.
    t.Setenv("RYOKU_ETC_ROOT", t.TempDir())
    if err := applyPlan("disable", "rxb-test-user", "/usr/bin/ryoku-hub", true); err != nil {
        t.Fatalf("read-only dry-run failed: %v", err)
    }
}

func TestRXBGpuTuningMutationBlocked(t *testing.T) {
    for _, args := range [][]string{{"set", "0000:01:00.0", "power_limit", "50"}, {"reset"}, {"preset", "performance"}} {
        err := runGpuTune(args)
        if err == nil || !strings.Contains(err.Error(), "disabled in the RXB X11 build") {
            t.Fatalf("runGpuTune(%v) = %v, want RXB fail-closed error", args, err)
        }
    }
}
""")

def patch_quickshell_config_isolation(root: pathlib.Path) -> None:
    # Keep all Ryoku-managed user configuration in a session-owned subtree.
    # Standard XDG_CONFIG_HOME remains unchanged for applications launched by
    # the session, and the user's existing ~/.config/quickshell is never owned.
    p = root / "ryoku/cli/internal/sys/paths.go"
    replace_once(p, 'func ConfigHome() string { return Xdg("XDG_CONFIG_HOME", ".config") }',
                 '''func ConfigHome() string {
	if d := os.Getenv("RYOKU_CONFIG_HOME"); d != "" {
		return d
	}
	return Xdg("XDG_CONFIG_HOME", ".config")
}''')
    replace_once(p, 'filepath.Join(ConfigHome(), "user-dirs.dirs")',
                 'filepath.Join(Xdg("XDG_CONFIG_HOME", ".config"), "user-dirs.dirs")')

    p = root / "ryoku/cli/internal/updater/materialize.go"
    old = '''func Materialize() error {
	base := sys.BaseConfigDir()
	dest := sys.ConfigHome()
	state := materializeStatePath()
'''
    new = '''func Materialize() error {
	base := sys.BaseConfigDir()
	dest := sys.ConfigHome()
	quickshellRoot := filepath.Join(dest, "quickshell")
	if override := os.Getenv("RYOKU_QUICKSHELL_CONFIG_HOME"); override != "" {
		expected := filepath.Join(dest, "quickshell")
		if !filepath.IsAbs(dest) || filepath.Clean(override) != filepath.Clean(expected) {
			return fmt.Errorf("RYOKU_QUICKSHELL_CONFIG_HOME must be %s", expected)
		}
		if info, err := os.Lstat(expected); err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("refusing symlinked RXB Quickshell config path: %s", expected)
		}
		quickshellRoot = expected
	}
	materializedPath := func(rel string) string {
		if strings.HasPrefix(rel, "quickshell/") {
			return filepath.Join(quickshellRoot, strings.TrimPrefix(rel, "quickshell/"))
		}
		return filepath.Join(dest, rel)
	}
	state := materializeStatePath()
'''
    replace_once(p, old, new)
    replace_once(p, "dst := filepath.Join(dest, rel)", "dst := materializedPath(rel)")
    replace_once(p, 'if local, err := walkRel(filepath.Join(dest, "quickshell")); err == nil {',
                 'if local, err := walkRel(quickshellRoot); err == nil {')
    replace_once(p, '''			_ = os.Remove(filepath.Join(dest, full))
			pruneEmptyParents(dest, filepath.Dir(full))''',
                 '''			_ = os.Remove(filepath.Join(quickshellRoot, rel))
			pruneEmptyParents(quickshellRoot, filepath.Dir(rel))''')
    replace_once(p, '''		_ = os.Remove(filepath.Join(dest, rel))
		pruneEmptyParents(dest, filepath.Dir(rel))''',
                 '''		_ = os.Remove(materializedPath(rel))
		if strings.HasPrefix(rel, "quickshell/") {
			quickshellRel := strings.TrimPrefix(rel, "quickshell/")
			pruneEmptyParents(quickshellRoot, filepath.Dir(quickshellRel))
		} else {
			pruneEmptyParents(dest, filepath.Dir(rel))
		}''')
    replace_once(p, 'os.ReadFile(filepath.Join(dest, rel)); err == nil {',
                 'os.ReadFile(materializedPath(rel)); err == nil {')

    # QML reads and Go services must use the RXB config root for Ryoku-owned
    # settings, while external applications keep the ordinary XDG config home.
    for qml in root.rglob("*.qml"):
        if not qml.is_file():
            continue
        text = qml.read_text()
        patched = text.replace(
            'Quickshell.env("XDG_CONFIG_HOME")',
            '(Quickshell.env("RYOKU_CONFIG_HOME") || Quickshell.env("XDG_CONFIG_HOME"))',
        )
        if patched != text:
            qml.write_text(patched)

    p = root / "ryoku/shell/ipc/theming.go"
    replace_once(p, "func themeAppsEnabled() bool {",
                 '''func themeAppsEnabled() bool {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" {
		return false
	}''')

    p = root / "ryoku/hub/backend/matugen.go"
    replace_once(p, "func renderActiveTemplates(cfg matugenConfig, pal map[string]string) {",
                 '''func renderActiveTemplates(cfg matugenConfig, pal map[string]string) {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" {
		return
	}''')
    p = root / "ryoku/hub/backend/schemes.go"
    replace_once(p, "func blankGtk() {",
                 '''func blankGtk() {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" {
		return
	}''')

    p = root / "ryoku/shell/ipc/matugen.go"
    replace_once(p, '''func matugenReload(mode string, emitter kdePaletteSignalEmitter) {
	scheme := "prefer-dark"''',
                 '''func matugenReload(mode string, emitter kdePaletteSignalEmitter) {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" {
		nudgePalette()
		return
	}
	scheme := "prefer-dark"''')

    p = root / "ryoku/shell/quickshell/inir/scripts/colors/sync-system-fonts.sh"
    replace_once(p, "set -euo pipefail\n",
                 "set -euo pipefail\n\n# RXB keeps host GTK/Qt font settings untouched.\n[[ ${RYOKU_X11_BRIDGE:-0} != 1 ]] || exit 0\n")
    p = root / "ryoku/shell/scripts/ryoku-cmd-folders"
    replace_once(p, "set -u\n",
                 "set -u\n\n# RXB does not change the host icon-theme setting or shared icon tree.\n[ ${RYOKU_X11_BRIDGE:-0} != 1 ] || exit 0\n")

    p = root / "ryoku/shell/ipc/widgetwatch.go"
    replace_once(p, '''// ryokuConfigDir is ~/.config/ryoku (honouring XDG_CONFIG_HOME), the dir the
// Ryoku Settings sections write. Empty only when the home dir is unknowable.
func ryokuConfigDir() string {
	dir := os.Getenv("XDG_CONFIG_HOME")''',
                 '''// ryokuConfigHome is the RXB-scoped Ryoku config root when present;
// ordinary XDG_CONFIG_HOME remains the app config root.
func ryokuConfigHome() string {
	if dir := os.Getenv("RYOKU_CONFIG_HOME"); dir != "" {
		return dir
	}
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return dir
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config")
}

// ryokuConfigDir is the directory the Ryoku Settings sections write.
func ryokuConfigDir() string {
	dir := ryokuConfigHome()''')
    replace_once(p, '''	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return ""
		}
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, "ryoku")
}''',
                 '''	if dir == "" {
		return ""
	}
	return filepath.Join(dir, "ryoku")
}''')

    # Shell IPC paths that belong to Ryoku state use the session root. GTK's
    # icon-theme reader deliberately remains on standard XDG_CONFIG_HOME.
    for rel, old, new in (
        ("ryoku/shell/ipc/updates.go",
         'base := os.Getenv("XDG_CONFIG_HOME")\n\tif base == "" {\n\t\tbase = filepath.Join(os.Getenv("HOME"), ".config")\n\t}',
         'base := ryokuConfigHome()'),
        ("ryoku/shell/ipc/record.go",
         '''func recordingConfigPath() string {
	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		if home, err := os.UserHomeDir(); err == nil {
			dir = filepath.Join(home, ".config")
		}
	}
	return filepath.Join(dir, "ryoku", "recording.json")
}''',
         '''func recordingConfigPath() string {
	dir := ryokuConfigHome()
	if dir == "" {
		return ""
	}
	return filepath.Join(dir, "ryoku", "recording.json")
}'''),
        ("ryoku/shell/ipc/theming.go",
         'base := os.Getenv("XDG_CONFIG_HOME")\n\tif base == "" {\n\t\tbase = filepath.Join(os.Getenv("HOME"), ".config")\n\t}',
         'base := ryokuConfigHome()'),
        ("ryoku/shell/ipc/bar.go",
         'configRoot := os.Getenv("XDG_CONFIG_HOME")\n\t\tif configRoot == "" {\n\t\t\thome, _ := os.UserHomeDir()\n\t\t\tconfigRoot = filepath.Join(home, ".config")\n\t\t}',
         'configRoot := ryokuConfigHome()'),
        ("ryoku/shell/ipc/music.go",
         'base := os.Getenv("XDG_CONFIG_HOME")\n\tif base == "" {\n\t\tbase = filepath.Join(os.Getenv("HOME"), ".config")\n\t}',
         'base := ryokuConfigHome()'),
        ("ryoku/shell/ipc/matugen.go",
         'if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {\n\t\treturn d\n\t}\n\treturn filepath.Join(os.Getenv("HOME"), ".config")',
         'return ryokuConfigHome()'),
    ):
        replace_once(root / rel, old, new)

    # Keep Ryoku-owned Hub state isolated, but leave external app configuration
    # (GTK, Qt, Kitty, Starship, Voxtype, Fastfetch, etc.) on normal XDG paths.
    p = root / "ryoku/hub/backend/schemes.go"
    replace_once(p, 'p := filepath.Join(configHome(), "ryoku", name)',
                 'p := filepath.Join(ryokuConfigHome(), "ryoku", name)')
    replace_once(p, '''	_ = exec.Command("gsettings", "set", "org.gnome.desktop.interface", "font-name", "Space Grotesk 11").Run()''',
                 '''	if os.Getenv("RYOKU_X11_BRIDGE") != "1" {
		_ = exec.Command("gsettings", "set", "org.gnome.desktop.interface", "font-name", "Space Grotesk 11").Run()
	}''')

    p = root / "ryoku/hub/backend/icon_theme.go"
    replace_once(p, "func applyIconTheme(theme string) error {",
                 '''func applyIconTheme(theme string) error {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" {
		return fmt.Errorf("icon theme changes are disabled in the RXB session")
	}''')
    p = root / "ryoku/hub/backend/lock.go"
    replace_once(p, '''func runLock(args []string) error {
	if len(args) == 0 {''',
                 '''func runLock(args []string) error {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" && (len(args) == 0 || args[0] != "list") {
		return fmt.Errorf("upstream lock theme and greeter management is disabled in the RXB session")
	}
	if len(args) == 0 {''')
    p = root / "ryoku/hub/backend/starship.go"
    replace_once(p, "func applyStarship(state starshipState, persist bool) error {",
                 '''func applyStarship(state starshipState, persist bool) error {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" {
		return fmt.Errorf("Starship config changes are disabled in the RXB session")
	}''')
    p = root / "ryoku/hub/backend/fastfetch.go"
    replace_once(p, '''func runFastfetch(args []string) error {
	if len(args) == 0 {''',
                 '''func runFastfetch(args []string) error {
	if os.Getenv("RYOKU_X11_BRIDGE") == "1" && (len(args) == 0 ||
		(args[0] != "get" && args[0] != "preview" && args[0] != "effective")) {
		return fmt.Errorf("Fastfetch config changes are disabled in the RXB session")
	}
	if len(args) == 0 {''')

    p = root / "ryoku/hub/backend/config.go"
    replace_once(p, 'func configPath() string {',
                 '''func ryokuConfigHome() string {
	if base := os.Getenv("RYOKU_CONFIG_HOME"); base != "" {
		return base
	}
	if base := os.Getenv("XDG_CONFIG_HOME"); base != "" {
		return base
	}
	return filepath.Join(os.Getenv("HOME"), ".config")
}

func configPath() string {''')
    replace_once(p, '''func configPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "hub.toml")
}''',
                 '''func configPath() string {
	return filepath.Join(ryokuConfigHome(), "ryoku", "hub.toml")
}''')
    for rel, old, new in (
        ("ryoku/hub/backend/profile.go",
         '''func profileDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku")
}''',
         '''func profileDir() string { return filepath.Join(ryokuConfigHome(), "ryoku") }'''),
        ("ryoku/hub/backend/matugen.go",
         '''func matugenConfigPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "matugen.json")
}''',
         '''func matugenConfigPath() string {
	return filepath.Join(ryokuConfigHome(), "ryoku", "matugen.json")
}'''),
        ("ryoku/hub/backend/schemes.go",
         '''func themeStatePath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "theme.json")
}''',
         '''func themeStatePath() string {
	return filepath.Join(ryokuConfigHome(), "ryoku", "theme.json")
}'''),
        ("ryoku/hub/backend/gpupreset.go",
         '''func presetsPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "gpu-presets.json")
}''',
         '''func presetsPath() string {
	return filepath.Join(ryokuConfigHome(), "ryoku", "gpu-presets.json")
}'''),
        ("ryoku/hub/backend/rice.go",
         '''func ryokuConfigDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku")
}''',
         '''func ryokuConfigDir() string { return filepath.Join(ryokuConfigHome(), "ryoku") }'''),
        ("ryoku/hub/backend/lighting.go",
         '''func lightingPath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "lighting.json")
}''',
         '''func lightingPath() string {
	return filepath.Join(ryokuConfigHome(), "ryoku", "lighting.json")
}'''),
    ):
        replace_once(root / rel, old, new)
    p = root / "ryoku/hub/backend/lock.go"
    replace_once(p, 'filepath.Join(xdgHome("XDG_CONFIG_HOME", ".config"), "ryoku", "shell.json")',
                 'filepath.Join(ryokuConfigHome(), "ryoku", "shell.json")')
    p = root / "ryoku/hub/backend/palettebridge.go"
    replace_once(p, '''func paletteBridgeConfigRoot() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return d
	}
	return filepath.Join(paletteBridgeHome(), ".config")
}''',
                 '''func paletteBridgeConfigRoot() string { return ryokuConfigHome() }''')
    p = root / "ryoku/hub/backend/fastfetch.go"
    text = p.read_text()
    old_path = 'filepath.Join(configHome(), "ryoku", "shell.json")'
    if old_path not in text:
        raise RuntimeError(f"{p}: expected Fastfetch Ryoku settings path")
    p.write_text(text.replace(old_path, 'filepath.Join(ryokuConfigHome(), "ryoku", "shell.json")'))

    p = root / "ryoku/rashin/backend/paths.go"
    replace_once(p, 'cfg := os.Getenv("XDG_CONFIG_HOME")',
                 'cfg := os.Getenv("RYOKU_CONFIG_HOME")\n\tif cfg == "" {\n\t\tcfg = os.Getenv("XDG_CONFIG_HOME")\n\t}')
    p = root / "ryoku/rashin/backend/user.go"
    replace_once(p, 'if v := os.Getenv("XDG_CONFIG_HOME"); v != "" {',
                 'if v := os.Getenv("RYOKU_CONFIG_HOME"); v != "" {\n\t\treturn v\n\t}\n\tif v := os.Getenv("XDG_CONFIG_HOME"); v != "" {')

    p = root / "ryoku/shell/ryogami/daemon/config.go"
    replace_once(p, 'func ryokuConfigDir() string {\n\tif d := os.Getenv("XDG_CONFIG_HOME"); d != "" {',
                 'func ryokuConfigDir() string {\n\tif d := os.Getenv("RYOKU_CONFIG_HOME"); d != "" {\n\t\treturn filepath.Join(d, "ryoku")\n\t}\n\tif d := os.Getenv("XDG_CONFIG_HOME"); d != "" {')
    replace_once(p, 'if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {\n\t\treturn filepath.Join(d, "ryogami-wall")',
                 'if d := os.Getenv("RYOKU_CONFIG_HOME"); d != "" {\n\t\treturn filepath.Join(d, "ryogami-wall")\n\t}\n\tif d := os.Getenv("XDG_CONFIG_HOME"); d != "" {\n\t\treturn filepath.Join(d, "ryogami-wall")')

    p = root / "ryoku/apps/ryostore/backend/provider_plugins.go"
    replace_once(p, 'func configHome() string {\n\tif base := os.Getenv("XDG_CONFIG_HOME"); base != "" {',
                 'func configHome() string {\n\tif base := os.Getenv("RYOKU_CONFIG_HOME"); base != "" {\n\t\treturn base\n\t}\n\tif base := os.Getenv("XDG_CONFIG_HOME"); base != "" {')

    p = root / "ryoku/palette-bridge/main.go"
    replace_once(p, 'config := os.Getenv("XDG_CONFIG_HOME")',
                 'config := os.Getenv("RYOKU_CONFIG_HOME")\n\tif config == "" {\n\t\tconfig = os.Getenv("XDG_CONFIG_HOME")\n\t}')

    p = root / "ryoku/i18n/i18n.go"
    text = p.read_text()
    old_home = 'home := os.Getenv("XDG_CONFIG_HOME")'
    if text.count(old_home) != 2:
        raise RuntimeError(f"{p}: expected two config-home selections, found {text.count(old_home)}")
    new_home = 'home := os.Getenv("RYOKU_CONFIG_HOME")\n\tif home == "" {\n\t\thome = os.Getenv("XDG_CONFIG_HOME")\n\t}'
    p.write_text(text.replace(old_home, new_home))

    p = root / "ryoku/cli/internal/securitykey/config.go"
    replace_once(p, 'if v := strings.TrimSpace(os.Getenv("XDG_CONFIG_HOME")); v != "" {',
                 'if v := strings.TrimSpace(os.Getenv("RYOKU_CONFIG_HOME")); v != "" {\n\t\treturn v\n\t}\n\tif v := strings.TrimSpace(os.Getenv("XDG_CONFIG_HOME")); v != "" {')

    p = root / "ryoku/shell/ipc/actions.go"
    replace_once(p, '''	if shellDir != "" {
		return []string{"-p", filepath.Join(shellDir, "quickshell", name)}
	}
	return []string{"-c", name}''',
                 '''	if shellDir != "" {
		return []string{"-p", filepath.Join(shellDir, "quickshell", name)}
	}
	if root := os.Getenv("RYOKU_QUICKSHELL_CONFIG_HOME"); root != "" {
		return []string{"-p", filepath.Join(root, name)}
	}
	return []string{"-c", name}''')

    # Hub has a dedicated selector too; keep it in the RXB-owned Quickshell
    # tree rather than falling back to the user's shared ~/.config/quickshell.
    p = root / "ryoku/shell/ipc/control.go"
    replace_once(p, '''	if shellDir != "" {
		return []string{"-p", filepath.Join(shellDir, "..", "hub", "quickshell")}
	}
	return []string{"-c", "hub"}''',
                 '''	if shellDir != "" {
		return []string{"-p", filepath.Join(shellDir, "..", "hub", "quickshell")}
	}
	if root := os.Getenv("RYOKU_QUICKSHELL_CONFIG_HOME"); root != "" {
		return []string{"-p", filepath.Join(root, "hub")}
	}
	return []string{"-c", "hub"}''')

    p = root / "ryoku/shell/ipc/daemon.go"
    replace_once(p, 'configRoot := os.Getenv("XDG_CONFIG_HOME")',
                 'configRoot := os.Getenv("RYOKU_CONFIG_HOME")\n\tif configRoot == "" {\n\t\tconfigRoot = os.Getenv("XDG_CONFIG_HOME")\n\t}')
    replace_once(p, '''	myCfg := os.Getenv("XDG_CONFIG_HOME")
	if myCfg == "" {
		myCfg = myHome + "/.config"
	}''',
                 '''	myCfg := os.Getenv("XDG_CONFIG_HOME")
	if myCfg == "" {
		myCfg = myHome + "/.config"
	}
	myRyokuCfg := os.Getenv("RYOKU_CONFIG_HOME")
	myQuickshell := os.Getenv("RYOKU_QUICKSHELL_CONFIG_HOME")''')
    replace_once(p, "if !sameSessionEnv(string(envRaw), myHome, myCfg) {",
                 "if !sameSessionEnv(string(envRaw), myHome, myCfg, myRyokuCfg, myQuickshell) {")
    replace_once(p, "func sameSessionEnv(environ, home, cfgDir string) bool {",
                 "func sameSessionEnv(environ, home, cfgDir, ryokuCfgDir, quickshellDir string) bool {")
    replace_once(p, "return c == cfgDir",
                 'return c == cfgDir && env["RYOKU_CONFIG_HOME"] == ryokuCfgDir && env["RYOKU_QUICKSHELL_CONFIG_HOME"] == quickshellDir')

    test = root / "ryoku/cli/internal/updater/materialize_rxb_test.go"
    test.write_text("""package updater

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMaterializeIsolatesRXBQuickshellConfig(t *testing.T) {
	base, xdg := t.TempDir(), t.TempDir()
	configHome := filepath.Join(xdg, "ryoku-x11", "ryoku-config")
	quickshell := filepath.Join(configHome, "quickshell")
	t.Setenv("RYOKU_CONFIG_BASE", base)
	t.Setenv("XDG_CONFIG_HOME", xdg)
	t.Setenv("RYOKU_CONFIG_HOME", configHome)
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("RYOKU_QUICKSHELL_CONFIG_HOME", quickshell)

	writeFile(t, filepath.Join(base, "quickshell/shell/shell.qml"), "RXB shell")
	writeFile(t, filepath.Join(base, "quickshell/shell/old.qml"), "old RXB file")
	writeFile(t, filepath.Join(base, "gtk-3.0/settings.ini"), "RXB GTK settings")
	writeFile(t, filepath.Join(xdg, "gtk-3.0/settings.ini"), "existing GTK settings")
	writeFile(t, filepath.Join(xdg, "quickshell/shell/shell.qml"), "existing desktop shell")
	writeFile(t, filepath.Join(xdg, "quickshell/keep.qml"), "existing user config")

	if err := Materialize(); err != nil {
		t.Fatalf("materialize isolated RXB config: %v", err)
	}
	wantFile(t, filepath.Join(quickshell, "shell/shell.qml"), "RXB shell")
	wantFile(t, filepath.Join(configHome, "gtk-3.0/settings.ini"), "RXB GTK settings")
	wantFile(t, filepath.Join(xdg, "gtk-3.0/settings.ini"), "existing GTK settings")
	wantFile(t, filepath.Join(xdg, "quickshell/shell/shell.qml"), "existing desktop shell")
	wantFile(t, filepath.Join(xdg, "quickshell/keep.qml"), "existing user config")

	if err := os.Remove(filepath.Join(base, "quickshell/shell/old.qml")); err != nil {
		t.Fatal(err)
	}
	if err := Materialize(); err != nil {
		t.Fatalf("materialize after upstream QML removal: %v", err)
	}
	if _, err := os.Stat(filepath.Join(quickshell, "shell/old.qml")); !os.IsNotExist(err) {
		t.Fatalf("stale RXB QML was not pruned from the isolated tree: %v", err)
	}
	wantFile(t, filepath.Join(xdg, "quickshell/shell/shell.qml"), "existing desktop shell")
}

func TestMaterializeRejectsSharedQuickshellRootOverride(t *testing.T) {
	base, xdg := t.TempDir(), t.TempDir()
	configHome := filepath.Join(xdg, "ryoku-x11", "ryoku-config")
	t.Setenv("RYOKU_CONFIG_BASE", base)
	t.Setenv("XDG_CONFIG_HOME", xdg)
	t.Setenv("RYOKU_CONFIG_HOME", configHome)
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("RYOKU_QUICKSHELL_CONFIG_HOME", filepath.Join(xdg, "quickshell"))

	if err := Materialize(); err == nil {
		t.Fatal("materialize accepted the shared ~/.config/quickshell path for RXB")
	}
}
""")

    test = root / "ryoku/shell/ipc/rxb_quickshell_path_test.go"
    test.write_text("""package main

import (
	"path/filepath"
	"testing"
)

func TestRXBQuickshellConfigSelector(t *testing.T) {
	activeShimaRoot.Store("")
	t.Setenv("RYOKU_QUICKSHELL_CONFIG_HOME", "/tmp/rxb/config/quickshell")
	got := qsSelect("shell")
	if len(got) != 2 || got[0] != "-p" || got[1] != filepath.Join("/tmp/rxb/config/quickshell", "shell") {
		t.Fatalf("RXB Quickshell selector = %#v", got)
	}
}

func TestRXBHubQuickshellConfigSelector(t *testing.T) {
	if shellDir != "" {
		t.Skip("development checkout selector takes precedence")
	}
	t.Setenv("RYOKU_QUICKSHELL_CONFIG_HOME", "/tmp/rxb/config/quickshell")
	got := hubSelect()
	if len(got) != 2 || got[0] != "-p" || got[1] != filepath.Join("/tmp/rxb/config/quickshell", "hub") {
		t.Fatalf("RXB Hub Quickshell selector = %#v", got)
	}
}

func TestRXBMatugenReloadSkipsHostDesktopCommands(t *testing.T) {
	t.Setenv("RYOKU_X11_BRIDGE", "1")
	old := runCommand
	calls := 0
	runCommand = func(string, ...string) error {
		calls++
		return nil
	}
	defer func() { runCommand = old }()
	matugenReload("dark", nil)
	if calls != 0 {
		t.Fatalf("RXB matugen reload invoked %d host desktop commands", calls)
	}
}

func TestRXBDisablesExternalAppTheming(t *testing.T) {
	t.Setenv("RYOKU_X11_BRIDGE", "1")
	if themeAppsEnabled() {
		t.Fatal("RXB session unexpectedly enabled shared application theming")
	}
}

func TestRXBSameSessionEnvIncludesRyokuConfigRoots(t *testing.T) {
	env := "HOME=/home/test\\x00XDG_CONFIG_HOME=/home/test/.config\\x00RYOKU_CONFIG_HOME=/home/test/.config/ryoku-x11/ryoku-config\\x00RYOKU_QUICKSHELL_CONFIG_HOME=/home/test/.config/ryoku-x11/ryoku-config/quickshell\\x00"
	if !sameSessionEnv(env, "/home/test", "/home/test/.config", "/home/test/.config/ryoku-x11/ryoku-config", "/home/test/.config/ryoku-x11/ryoku-config/quickshell") {
		t.Fatal("same RXB config roots were not recognized as the same session")
	}
	if sameSessionEnv(env, "/home/test", "/home/test/.config", "/home/test/.config/ryoku-x11/ryoku-config", "/home/test/.config/quickshell") {
		t.Fatal("different Quickshell roots were treated as the same session")
	}
}
""")

    test = root / "ryoku/hub/backend/config_rxb_test.go"
    test.write_text("""package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRXBConfigHomeIsolatedFromExternalAppConfig(t *testing.T) {
	xdg := t.TempDir()
	rxb := filepath.Join(xdg, "ryoku-x11", "ryoku-config")
	t.Setenv("XDG_CONFIG_HOME", xdg)
	t.Setenv("RYOKU_CONFIG_HOME", rxb)

	if got := ryokuConfigHome(); got != rxb {
		t.Fatalf("Ryoku config home = %q, want %q", got, rxb)
	}
	if got := configPath(); got != filepath.Join(rxb, "ryoku", "hub.toml") {
		t.Fatalf("Hub config path = %q, want RXB root", got)
	}
	if got := profileDir(); got != filepath.Join(rxb, "ryoku") {
		t.Fatalf("profile dir = %q, want RXB root", got)
	}
	if got := configHome(); got != xdg {
		t.Fatalf("external app config home = %q, want standard XDG %q", got, xdg)
	}
}

func TestRXBBlocksHostLockAndAppConfigMutations(t *testing.T) {
	t.Setenv("RYOKU_X11_BRIDGE", "1")
	if err := runLock([]string{"set", "example"}); err == nil {
		t.Fatal("RXB allowed upstream lock theme mutation")
	}
	if err := applyIconTheme("Papirus"); err == nil {
		t.Fatal("RXB allowed shared icon theme mutation")
	}
	if err := applyStarship(starshipState{}, false); err == nil {
		t.Fatal("RXB allowed shared Starship config mutation")
	}
	if err := runFastfetch([]string{"reset"}); err == nil {
		t.Fatal("RXB allowed shared Fastfetch config mutation")
	}
}

func TestRXBThemeWritesDoNotTouchSharedAppConfig(t *testing.T) {
	xdg := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", xdg)
	t.Setenv("RYOKU_CONFIG_HOME", filepath.Join(xdg, "ryoku-x11", "ryoku-config"))
	t.Setenv("RYOKU_X11_BRIDGE", "1")

	renderActiveTemplates(matugenConfig{}, nil)
	blankGtk()
	if _, err := os.Stat(filepath.Join(xdg, "gtk-3.0")); !os.IsNotExist(err) {
		t.Fatalf("RXB theme pipeline touched shared GTK config: %v", err)
	}
}
""")

    test = root / "ryoku/cli/internal/sys/paths_rxb_test.go"
    test.write_text("""package sys

import (
	"os"
	"path/filepath"
	"testing"
)

func TestConfigHomePrefersRXBRoot(t *testing.T) {
	xdg := t.TempDir()
	rxb := filepath.Join(xdg, "ryoku-x11", "ryoku-config")
	t.Setenv("XDG_CONFIG_HOME", xdg)
	t.Setenv("RYOKU_CONFIG_HOME", rxb)
	if got := ConfigHome(); got != rxb {
		t.Fatalf("ConfigHome() = %q, want RXB root %q", got, rxb)
	}
}

func TestPicturesDirStillUsesStandardXDGConfig(t *testing.T) {
	xdg := t.TempDir()
	rxb := filepath.Join(xdg, "ryoku-x11", "ryoku-config")
	pictures := filepath.Join(t.TempDir(), "Pictures")
	if err := os.MkdirAll(pictures, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(xdg, "user-dirs.dirs"), []byte("XDG_PICTURES_DIR=\\""+pictures+"\\"\\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_CONFIG_HOME", xdg)
	t.Setenv("RYOKU_CONFIG_HOME", rxb)
	t.Setenv("XDG_PICTURES_DIR", "")
	if got := PicturesDir(); got != pictures {
		t.Fatalf("PicturesDir() = %q, want standard XDG path %q", got, pictures)
	}
}
""")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ryoku_checkout", type=pathlib.Path)
    args = parser.parse_args()
    root = args.ryoku_checkout.resolve()
    if not (root / ".git").exists():
        raise RuntimeError(f"not a git checkout: {root}")
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if head != PIN:
        raise RuntimeError(f"upstream pin mismatch: expected {PIN}, got {head}")
    patch_detect(root)
    patch_session_detection(root)
    patch_wm_qml(root)
    patch_x11_panel_properties(root)
    patch_compositor_service(root)
    patch_wayland_consumers(root)
    patch_x11_capture(root)
    patch_x11_terminal_launcher(root)
    patch_x11_clipboard(root)
    patch_x11_region_tools(root)
    patch_lock_dispatch(root)
    patch_x11_suspend(root)
    patch_x11_login1_graphical_session(root)
    patch_ryogami_package(root)
    patch_x11_package_safety(root)
    patch_x11_privileged_hub_backends(root)
    patch_quickshell_config_isolation(root)
    print(f"RXB overlay applied to pinned Ryoku {PIN}")
    print("Changed: provider/session discovery, QML i3 bridge, X11 panel/taskbar/capture/clipboard/lock adapters, and non-destructive package policy")
    print("Note: this is a source overlay, not a completed/validated desktop build.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"apply-upstream-overlay: {exc}", file=sys.stderr)
        raise SystemExit(1)
