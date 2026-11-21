#!/usr/bin/env python3
"""Apply the RXB X11 compatibility overlay to the pinned Ryoku checkout."""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

PIN = "0bf11741b22f69f22ad2733025671c7d0a5e1a47"


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


def patch_detect(root: pathlib.Path) -> None:
    p = root / "ryoku/wm/detect.go"
    replace_once(p, 'ProviderWayfire  = "wayfire"\n', 'ProviderWayfire  = "wayfire"\n\tProviderI3       = "i3"\n')
    replace_once(p, '\t{"WAYFIRE_SOCKET", ProviderWayfire, func(h string) []string { return []string{h} }},\n',
        '\t{"WAYFIRE_SOCKET", ProviderWayfire, func(h string) []string { return []string{h} }},\n'
        '\t// i3 exports its IPC socket path to clients in the session.\n'
        '\t{"I3SOCK", ProviderI3, func(h string) []string { return []string{h} }},\n')
    replace_in_map(p, "var configDirs", '\tProviderWayfire:  "wayfire",\n',
                   '\tProviderWayfire:  "wayfire",\n\tProviderI3:       "ryoku-x11",\n')
    replace_once(p, '\tProviderWayfire:  "wayfire.ini",\n', '\tProviderWayfire:  "wayfire.ini",\n\tProviderI3:       "config",\n')
    replace_once(p, '\tProviderWayfire: {"monitors.ini", "keyboard.ini", "user.ini"},\n',
        '\tProviderWayfire: {"monitors.ini", "keyboard.ini", "user.ini"},\n'
        '\tProviderI3:      {"config", "generated.conf", "user.conf"},\n')
    replace_once(p, '\tProviderWayfire:  {"wayfire/user.ini", "wayfire/monitors.ini"},\n',
        '\tProviderWayfire:  {"wayfire/user.ini", "wayfire/monitors.ini"},\n'
        '\tProviderI3:       {"ryoku-x11/user.conf", "ryoku-x11/config"},\n')
    replace_once(p, '\tProviderWayfire:  {"wayfire/wayfire.ini", "ryoku/user_edits/wayfire/wayfire.ini"},\n',
        '\tProviderWayfire:  {"wayfire/wayfire.ini", "ryoku/user_edits/wayfire/wayfire.ini"},\n'
        '\tProviderI3:       {"ryoku-x11/generated.conf"},\n')
    replace_once(p, 'return []string{ProviderHyprland, ProviderNiri, ProviderWayfire}',
        'return []string{ProviderHyprland, ProviderNiri, ProviderWayfire, ProviderI3}')
    replace_in_map(p, "var compositorBins", '\tProviderWayfire:  "wayfire",\n',
                   '\tProviderWayfire:  "wayfire",\n\tProviderI3:       "i3",\n')
    subprocess.run(["gofmt", "-w", str(p)], check=True)


def patch_session_detection(root: pathlib.Path) -> None:
    p = root / "ryoku/wm/detect.go"
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
    replace_once(p, "if entry.IsDir() || filepath.Ext(entry.Name()) != \".desktop\" {",
                 "if entry.IsDir() || filepath.Ext(entry.Name()) != \".desktop\" || (wanted != \"\" && entry.Name() != wanted) {")
    replace_once(p, "entry := name + \".desktop\"\n\tfor _, d := range sessionEntryDirs() {",
                 "entry := name + \".desktop\"\n\tif custom := sessionEntryNames[name]; custom != \"\" { entry = custom }\n\tfor _, d := range sessionDirsFor(name) {")


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
    readonly property var _windowsets: I3.workspaces
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
                activated: Number(w.focusOrder) === 0,
                fullscreen: false,
                screens: screen ? [screen] : [],
                activate: () => root.focusWindow(String(w.id || "")),
                close: () => root.closeWindow(String(w.id || ""))
            });
        }
        return out;
    }'''
    replace_once(p, old, new)
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

    p = root / "ryoku/shell/quickshell/shell/modules/overview/WorkspaceCell.qml"
    replace_once(p, 'captureSource: (!!cell.ov && cell.ov.active && tile.modelData.tl) ? tile.modelData.tl : null',
                 'captureSource: (Wm.caps.persistentScreenCapture === true && !!cell.ov && cell.ov.active && tile.modelData.tl) ? tile.modelData.tl : null')
    replace_once(p, 'visible: tile.modelData.tl !== null',
                 'visible: Wm.caps.persistentScreenCapture === true && tile.modelData.tl !== null')

    p = root / "ryoku/shell/quickshell/shell/modules/overview/Overview.qml"
    replace_once(p, 'captureSource: root.dragTl\n                live: false\n                visible: root.dragTl !== null',
                 'captureSource: Wm.caps.persistentScreenCapture === true ? root.dragTl : null\n                live: false\n                visible: Wm.caps.persistentScreenCapture === true && root.dragTl !== null')


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


def patch_lock_dispatch(root: pathlib.Path) -> None:
    p = root / "ryoku/shell/ipc/actions.go"
    old = '''func lockSession() string {
	if err := ensureSessionLocked(time.Now().Add(lockWait)); err != nil {
		return "err lock: " + err.Error()
	}
	return "ok"
}'''
    new = '''func lockSession() string {
	// X11 has no ext_session_lock_v1. Use a dedicated X11 locker with PAM;
	// never launch the Wayland qylock surface on an X11 session.
	if os.Getenv("WAYLAND_DISPLAY") == "" && os.Getenv("DISPLAY") != "" {
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
	launcher, err := exec.LookPath("xsecurelock")
	if err != nil {
		return fmt.Errorf("X11 secure locker unavailable (install xsecurelock): %w", err)
	}
	cmd := exec.Command(launcher)
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}'''
    replace_once(p, old, new)


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
        replace_once(p, "import Quickshell.Wayland\n", "import Quickshell.Wayland\nimport Ryoku.Ui.Singletons\n")
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
    patch_compositor_service(root)
    patch_wayland_consumers(root)
    patch_x11_capture(root)
    patch_x11_clipboard(root)
    patch_lock_dispatch(root)
    print(f"RXB overlay applied to pinned Ryoku {PIN}")
    print("Changed: provider/session discovery, QML i3 bridge, taskbar/capture adapters, X11 clipboard and lock dispatch")
    print("Note: this is a source overlay, not a completed/validated desktop build.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"apply-upstream-overlay: {exc}", file=sys.stderr)
        raise SystemExit(1)
