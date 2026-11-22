#!/usr/bin/env python3
"""Build a conservative, static QML dependency graph for the pinned Ryoku shell.

This follows explicit local directory/module imports and QML component types used
in object declarations. It is intentionally conservative: dynamic Loader sources,
JavaScript-created components, plugin-provided QML and runtime profile selection
cannot be resolved statically and are reported as caveats.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import deque
from pathlib import Path

# Keep module URI parsing separate from quoted directory imports.
MODULE_IMPORT_RE = re.compile(r'^\s*import\s+([A-Za-z_][\w.]*)', re.M)
TYPE_RE = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\s*\{')
API_PATTERNS = {
    "Quickshell.Wayland": re.compile(r'\bimport\s+Quickshell\.Wayland\b'),
    "WlrLayershell": re.compile(r'\bWlrLayershell\b'),
    "ScreencopyView": re.compile(r'\bScreencopyView\b'),
    "ToplevelManager": re.compile(r'\bToplevelManager\b'),
    "WlSessionLock": re.compile(r'\bWlSessionLock(?:Surface)?\b'),
    "Quickshell.Hyprland": re.compile(r'\bimport\s+Quickshell\.Hyprland\b'),
    "Quickshell.Niri": re.compile(r'\bimport\s+Quickshell\.Niri\b'),
    "Quickshell.I3": re.compile(r'\bimport\s+Quickshell\.I3\b'),
}
DYNAMIC_RE = re.compile(r'\b(?:Loader|Component)\s*\{|\bsource\s*:\s*(?:Qt\.resolvedUrl|[A-Za-z_$])')


def qml_files(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.qml") if p.is_file())


def module_map(root: Path) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for qmldir in root.rglob("qmldir"):
        try:
            text = qmldir.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in re.finditer(r'^\s*module\s+([A-Za-z_][\w.]*)', text, re.M):
            found[match.group(1)] = qmldir.parent
    return found


def graph(root: Path, entry: Path) -> dict:
    files = qml_files(root)
    by_dir: dict[Path, dict[str, list[Path]]] = {}
    for path in files:
        by_dir.setdefault(path.parent, {}).setdefault(path.stem, []).append(path)
    modules = module_map(root)
    pending = deque([entry.resolve()])
    visited: set[Path] = set()
    edges: dict[str, list[str]] = {}
    unresolved: set[str] = set()
    non_qml_imports: set[str] = set()
    dynamic: set[str] = set()

    while pending:
        path = pending.popleft()
        if path in visited or not path.is_file():
            continue
        try:
            path.relative_to(root.resolve())
        except ValueError:
            continue
        visited.add(path)
        source = path.read_text(encoding="utf-8", errors="replace")
        visible_dirs = {path.parent}
        for match in re.finditer(r'^\s*import\s+"([^"]+)"(?:\s+as\s+\w+)?', source, re.M):
            target = (path.parent / match.group(1)).resolve()
            if target.is_dir():
                visible_dirs.add(target)
            elif target.is_file():
                if target.suffix == ".qml":
                    pending.append(target)
                else:
                    non_qml_imports.add(f"{path.relative_to(root)}: {match.group(1)}")
            else:
                unresolved.add(f"{path.relative_to(root)}: {match.group(1)}")
        for uri in MODULE_IMPORT_RE.findall(source):
            target = modules.get(uri)
            if target:
                visible_dirs.add(target)

        targets: set[Path] = set()
        for type_name in TYPE_RE.findall(source):
            for directory in visible_dirs:
                for candidate in by_dir.get(directory, {}).get(type_name, []):
                    if candidate != path:
                        targets.add(candidate.resolve())
        edges[str(path.relative_to(root))] = sorted(str(p.relative_to(root)) for p in targets)
        pending.extend(sorted(targets))
        if DYNAMIC_RE.search(source):
            dynamic.add(str(path.relative_to(root)))

    api_counts = {name: 0 for name in API_PATTERNS}
    api_files = {name: [] for name in API_PATTERNS}
    for path in sorted(visited):
        source = path.read_text(encoding="utf-8", errors="replace")
        rel = str(path.relative_to(root))
        for name, pattern in API_PATTERNS.items():
            count = len(pattern.findall(source))
            if count:
                api_counts[name] += count
                api_files[name].append({"file": rel, "occurrences": count})

    reachable = {str(p.relative_to(root)) for p in visited}
    all_files = {str(p.relative_to(root)) for p in files}
    return {
        "entry": str(entry.resolve().relative_to(root.resolve())),
        "reachable_qml_files": sorted(reachable),
        "unreachable_qml_files": sorted(all_files - reachable),
        "dependency_edges": edges,
        "api_occurrences": api_counts,
        "api_files": api_files,
        "dynamic_loading_files": sorted(dynamic),
        "non_qml_local_imports": sorted(non_qml_imports),
        "unresolved_local_imports": sorted(unresolved),
        "limitations": [
            "Static component-reference resolution is conservative and is not a QML compiler.",
            "Dynamic Loader/source paths, JavaScript-created components, plugins and profile-dependent runtime selection may add dependencies.",
            "Reachability is a source-level candidate graph; runtime tracing and interactive acceptance remain required."
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream", type=Path, help="pinned Ryoku checkout root")
    parser.add_argument("--root", default="ryoku/shell/quickshell", help="QML root relative to upstream")
    parser.add_argument("--entry", default="shell/shell.qml", help="entry QML file relative to QML root")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = (args.upstream / args.root).resolve()
    entry = (root / args.entry).resolve()
    if not root.is_dir() or not entry.is_file():
        parser.error(f"missing QML root or entry: {root} / {entry}")
    report = graph(root, entry)
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
