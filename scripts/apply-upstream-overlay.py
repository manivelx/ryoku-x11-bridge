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
    start = text.index(marker)
    end = text.index("\\n}", start) + 2
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
    patch_wm_qml(root)
    patch_compositor_service(root)
    patch_lock_dispatch(root)
    print(f"RXB overlay applied to pinned Ryoku {PIN}")
    print("Changed: provider registration, Wm.qml i3 bridge, compositor capability flags, X11 lock dispatch")
    print("Note: this is a source overlay, not a completed/validated desktop build.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"apply-upstream-overlay: {exc}", file=sys.stderr)
        raise SystemExit(1)
