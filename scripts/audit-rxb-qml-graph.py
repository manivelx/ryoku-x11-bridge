#!/usr/bin/env python3
"""Conservative static QML dependency and dynamic-loading audit for pinned Ryoku.

The graph follows explicit imports, component types and literal dynamic QML
paths. Non-literal Loader/source expressions and profile-dependent references
are reported separately; this remains a source audit, not runtime proof.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import deque
from pathlib import Path

MODULE_IMPORT_RE = re.compile(r'^\s*import\s+([A-Za-z_][\w.]*)', re.M)
TYPE_RE = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\s*\{')
LOADER_RE = re.compile(r"\bLoader\s*\{")
FACTORY_RE = re.compile(r"\bQt\.(?:createComponent|include)\s*\(([^)]*)\)", re.M)
INLINE_QML_RE = re.compile(r'\bQt\.createQmlObject\s*\(')
LITERAL_PATH_RE = re.compile(r'["\']([^"\']+\.(?:qml|js|mjs))["\']', re.I)
PROFILE_RE = re.compile(r'\b(?:profile|barStyle|shellProfile|shellVariant|activeProfile|profileName)\b', re.I)
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


def _matching_brace(source: str, opening: int) -> int | None:
    """Return the matching closing brace, ignoring comments and quoted strings."""
    depth = 0
    i = opening
    quote = None
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "/" and nxt == "/":
            end = source.find("\n", i + 2)
            i = len(source) if end < 0 else end
            continue
        elif ch == "/" and nxt == "*":
            end = source.find("*/", i + 2)
            i = len(source) if end < 0 else end + 2
            continue
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def loader_source_expressions(source: str) -> list[tuple[int, str]]:
    """Collect only Loader.source expressions; image/video source URLs are not QML loads."""
    found: list[tuple[int, str]] = []
    for loader in LOADER_RE.finditer(source):
        opening = source.find("{", loader.start())
        closing = _matching_brace(source, opening)
        if closing is None:
            continue
        body = source[opening + 1:closing]
        depth = 0
        i = 0
        quote = None
        while i < len(body):
            ch = body[i]
            nxt = body[i + 1] if i + 1 < len(body) else ""
            if quote:
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in ("'", '"'):
                quote = ch
            elif ch == "/" and nxt == "/":
                end = body.find("\n", i + 2)
                i = len(body) if end < 0 else end
                continue
            elif ch == "/" and nxt == "*":
                end = body.find("*/", i + 2)
                i = len(body) if end < 0 else end + 2
                continue
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth = max(0, depth - 1)
            elif depth == 0 and body.startswith("source", i):
                before = body[i - 1] if i else " "
                after = body[i + 6] if i + 6 < len(body) else " "
                if not (before.isalnum() or before in "_$") and not (after.isalnum() or after in "_$"):
                    match = re.match(r"source\s*:\s*([^\n;]+)", body[i:])
                    if match:
                        expr = match.group(1).strip().rstrip(",")
                        line = source.count("\n", 0, opening + 1 + i) + 1
                        found.append((line, expr))
                        i += match.end()
                        continue
            i += 1
    return found


def graph(root: Path, entry: Path) -> dict:
    root = root.resolve()
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
    dynamic_files: set[str] = set()
    dynamic_references: list[dict] = []
    unresolved_dynamic: list[dict] = []
    profile_references: list[dict] = []
    imported_modules: dict[str, set[str]] = {}

    while pending:
        path = pending.popleft()
        if path in visited or not path.is_file():
            continue
        try:
            path.relative_to(root)
        except ValueError:
            continue
        visited.add(path)
        source = path.read_text(encoding="utf-8", errors="replace")
        rel = str(path.relative_to(root))
        visible_dirs = {path.parent}

        for match in re.finditer(r'^\s*import\s+"([^"]+)"(?:\s+as\s+\w+)?', source, re.M):
            target = (path.parent / match.group(1)).resolve()
            if target.is_dir():
                visible_dirs.add(target)
            elif target.is_file():
                if target.suffix == ".qml":
                    pending.append(target)
                else:
                    non_qml_imports.add(f"{rel}: {match.group(1)}")
            else:
                unresolved.add(f"{rel}: {match.group(1)}")

        for uri in MODULE_IMPORT_RE.findall(source):
            imported_modules.setdefault(uri, set()).add(rel)
            target = modules.get(uri)
            if target:
                visible_dirs.add(target)

        targets: set[Path] = set()
        for type_name in TYPE_RE.findall(source):
            for directory in visible_dirs:
                for candidate in by_dir.get(directory, {}).get(type_name, []):
                    if candidate != path:
                        targets.add(candidate.resolve())
        edges[rel] = sorted(str(p.relative_to(root)) for p in targets)
        pending.extend(sorted(targets))

        loader_expressions = loader_source_expressions(source)
        factory_expressions = [
            (source.count("\n", 0, match.start()) + 1, match.group(1).strip())
            for match in FACTORY_RE.finditer(source)
        ]
        if loader_expressions or factory_expressions or INLINE_QML_RE.search(source):
            dynamic_files.add(rel)

        expressions = [
            *((line, expression, "loader-source") for line, expression in loader_expressions),
            *((line, expression, "qml-or-js-factory") for line, expression in factory_expressions),
        ]
        for line, expression, kind in expressions:
            reference = {
                "file": rel,
                "line": line,
                "kind": kind,
                "expression": expression,
                "targets": [],
                "resolution": "unresolved",
            }
            literals = LITERAL_PATH_RE.findall(expression)
            if literals:
                resolved_targets = []
                external_targets = []
                for literal in literals:
                    if literal.startswith(("qrc:/", "file:/", "http:/", "https:/")):
                        external_targets.append(literal)
                        continue
                    target = (path.parent / literal).resolve()
                    try:
                        target.relative_to(root)
                    except ValueError:
                        external_targets.append(literal)
                        continue
                    if target.is_file():
                        resolved_targets.append(str(target.relative_to(root)))
                        if target.suffix.lower() == ".qml":
                            targets.add(target)
                            pending.append(target)
                        else:
                            non_qml_imports.add(f"{rel}: {literal}")
                    else:
                        unresolved.add(f"{rel}: {literal}")
                reference["targets"] = sorted(set(resolved_targets + external_targets))
                if resolved_targets and not external_targets:
                    reference["resolution"] = "resolved-local"
                elif external_targets and not resolved_targets:
                    reference["resolution"] = "external"
                elif resolved_targets and external_targets:
                    reference["resolution"] = "mixed"
            dynamic_references.append(reference)
            if reference["resolution"] == "unresolved":
                unresolved_dynamic.append(reference)

        if INLINE_QML_RE.search(source):
            line = source.count("\n", 0, INLINE_QML_RE.search(source).start()) + 1
            dynamic_references.append({
                "file": rel,
                "line": line,
                "kind": "inline-qml",
                "expression": "Qt.createQmlObject(...)",
                "targets": [],
                "resolution": "inline-source",
            })

        for number, line_text in enumerate(source.splitlines(), 1):
            if PROFILE_RE.search(line_text):
                profile_references.append({
                    "file": rel,
                    "line": number,
                    "text": line_text.strip()[:240],
                })
        # Include literal dynamic QML loads in the dependency graph as well.
        edges[rel] = sorted(str(target.relative_to(root)) for target in targets)

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
        "entry": str(entry.resolve().relative_to(root)),
        "reachable_qml_files": sorted(reachable),
        "unreachable_qml_files": sorted(all_files - reachable),
        "dependency_edges": edges,
        "api_occurrences": api_counts,
        "api_files": api_files,
        "module_imports": {
            uri: sorted(paths) for uri, paths in sorted(imported_modules.items())
        },
        "external_module_imports": sorted(uri for uri in imported_modules if uri not in modules),
        "dynamic_loading_files": sorted(dynamic_files),
        "dynamic_references": sorted(dynamic_references, key=lambda item: (item["file"], item["line"])),
        "unresolved_dynamic_references": sorted(unresolved_dynamic, key=lambda item: (item["file"], item["line"])),
        "non_qml_local_imports": sorted(non_qml_imports),
        "unresolved_local_imports": sorted(unresolved),
        "profile_dependent_files": sorted({item["file"] for item in profile_references}),
        "profile_dependent_references": profile_references,
        "limitations": [
            "Static component-reference resolution is conservative and is not a QML compiler.",
            "Literal dynamic QML paths are followed; non-literal Loader/source expressions and inline JavaScript-created QML are reported but cannot be fully resolved statically.",
            "External module imports identify runtime-provided Qt/Quickshell/plugin dependencies; the graph does not prove that their binaries are installed.",
            "Profile references are source-level candidates; active profile selection and runtime-loaded modules still require runtime tracing.",
            "Reachability is a source-level candidate graph; runtime tracing and interactive acceptance remain required.",
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
