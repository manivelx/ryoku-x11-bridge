#!/usr/bin/env python3
"""Inventory Wayland/compositor-specific QML APIs in the pinned Ryoku shell tree.

This is a source census, not a runtime-activation proof. It deliberately reports
whole shell subtrees so optional styles and helper apps are not mistaken for the
default active profile.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

API_PATTERNS = {
    "wayland_import": re.compile(r"^\s*import\s+Quickshell\.Wayland\b", re.M),
    "wlr_layershell": re.compile(r"\bWlrLayershell\b"),
    "screencopy_view": re.compile(r"\bScreencopyView\b"),
    "toplevel_manager": re.compile(r"\bToplevelManager\b"),
    "session_lock": re.compile(r"\bWlSessionLock(?:Surface)?\b"),
    "hyprland_import": re.compile(r"^\s*import\s+Quickshell\.Hyprland\b", re.M),
    "niri_import": re.compile(r"^\s*import\s+Quickshell\.Niri\b", re.M),
    "i3_import": re.compile(r"^\s*import\s+Quickshell\.I3\b", re.M),
}
ROOTS = {
    "main_shell": Path("ryoku/shell/quickshell/shell"),
    "key_hint_app": Path("ryoku/shell/quickshell/keys"),
    "screenshot_app": Path("ryoku/shell/quickshell/ryoshot"),
}


def scan_root(repo: Path, name: str, relative: Path) -> dict[str, Any]:
    base = repo / relative
    files: list[dict[str, Any]] = []
    totals = {key: 0 for key in API_PATTERNS}
    if not base.is_dir():
        return {"root": relative.as_posix(), "exists": False, "qml_files": 0,
                "totals": totals, "files": files}
    for path in sorted(base.rglob("*.qml")):
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            files.append({"path": path.relative_to(repo).as_posix(),
                          "read_error": str(error)})
            continue
        hits: dict[str, int] = {}
        for api, pattern in API_PATTERNS.items():
            count = len(pattern.findall(source))
            if count:
                hits[api] = count
                totals[api] += count
        if hits:
            files.append({"path": path.relative_to(repo).as_posix(),
                          "apis": hits})
    return {"root": relative.as_posix(), "exists": True,
            "qml_files": sum(1 for _ in base.rglob("*.qml")),
            "totals": totals, "files": files}


def build_report(repo: Path) -> dict[str, Any]:
    repo = repo.resolve()
    roots = {name: scan_root(repo, name, relative)
             for name, relative in ROOTS.items()}
    combined = {key: sum(item["totals"][key] for item in roots.values())
                for key in API_PATTERNS}
    return {
        "schema_version": 1,
        "scope_note": (
            "Whole QML source subtrees, including optional styles and helper "
            "apps; not proof that every listed file is active in the default profile."
        ),
        "roots": roots,
        "combined_totals": combined,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream_repo", type=Path,
                        help="checkout root containing the ryoku/ directory")
    parser.add_argument("--output", type=Path,
                        help="write JSON report here instead of stdout")
    args = parser.parse_args()
    report = build_report(args.upstream_repo)
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
