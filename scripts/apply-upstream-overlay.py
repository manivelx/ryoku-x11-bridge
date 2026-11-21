#!/usr/bin/env python3
"""Apply the RXB X11 compatibility overlay to the pinned Ryoku checkout."""
from __future__ import annotations

import argparse
import pathlib
import re
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
	args := []string{}
	if err != nil {
		launcher, err = exec.LookPath("i3lock")
		args = []string{"--nofork"}
	}
	if err != nil {
		return fmt.Errorf("X11 secure locker unavailable (install xsecurelock or i3lock): %w", err)
	}
	cmd := exec.Command(launcher, args...)
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() { _ = cmd.Wait() }()
	return nil
}'''
    replace_once(p, old, new)


def _ternary_counts(expr: str) -> tuple[int, int, int]:
    parens = expr.count("(") - expr.count(")")
    questions = len(re.findall(r"\?(?![?.])", expr))
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
    return expr.replace(placeholder, "(shownKeyboardFocus !== WlrKeyboardFocus.None)")


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
        except FileNotFoundError:
            # Some upstream optional bundles contain dangling asset symlinks.
            continue
        if "WlrLayershell." not in text:
            continue
        if p.name == "VariantRoot.qml":
            text = text.replace("WlrLayershell.focusable:", "focusable:")
            text = text.replace("WlrLayershell.keyboardFocus: dismissLayer.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n", "")
        if p.name == "LyricsPicker.qml":
            text = text.replace("WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand\n", "")
        if p.name == "GithubFace.qml":
            text = text.replace('''                    let focusVal = enable ? 1 : 0;
                    if (typeof WlrKeyboardFocus !== "undefined") {
                        focusVal = enable ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None;
                    } else if (typeof WlrLayershell !== "undefined" && WlrLayershell.KeyboardFocus) {
                        focusVal = enable ? WlrLayershell.KeyboardFocus.OnDemand : WlrLayershell.KeyboardFocus.None;
                    }
                    t.WlrLayershell.keyboardFocus = focusVal;''', '''                    t.focusable = !!enable;''')

        lines = text.splitlines()
        out = []
        i = 0
        while i < len(lines):
            line = lines[i]
            match = re.match(r"^(\s*)WlrLayershell\.(layer|keyboardFocus):\s*(.*)$", line)
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
                else:
                    converted = _convert_x11_focus(expression)
                    out.append(f"{indent}focusable: {converted}")
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
        if "WlrLayershell.layer:" in patched or "WlrLayershell.keyboardFocus:" in patched or "WlrLayershell.namespace:" in patched or "WlrLayershell.focusable:" in patched:
            raise RuntimeError(f"{p}: X11 PanelWindow property conversion incomplete")
        if "t.WlrLayershell.keyboardFocus" in patched:
            raise RuntimeError(f"{p}: dynamic Wayland keyboard-focus assignment remains")
        if patched != text:
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
    for dep in ("'xorg-xwayland'", "'qt6-wayland'", "'qt5-wayland'", "'weston'",
                "'wl-clipboard'", "'wl-clip-persist'", "'grim'", "'slurp'",
                "'wtype'", "'hypridle'", "'hyprpicker'"):
        text = text.replace("  " + dep + "\n", "")
    old = '  RYOKU_SRC="$_repo" ' + chr(92) + "\n"
    if text.count(old) != 2:
        raise RuntimeError(f"{p}: expected two payload environment blocks, found {text.count(old)}")
    new = ('  RYOKU_X11_BRIDGE=1 ' + chr(92) + "\n"
           '  RYOKU_SRC="$_repo" ' + chr(92) + "\n")
    text = text.replace(old, new)
    p.write_text(text)

    p = root / "release/packages/ryoku-shell/PKGBUILD"
    text = p.read_text().replace("'wtype'", "").replace("'wl-clipboard'", "")
    p.write_text(text)


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
    patch_x11_clipboard(root)
    patch_x11_region_tools(root)
    patch_lock_dispatch(root)
    patch_ryogami_package(root)\n    patch_x11_package_safety(root)
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
