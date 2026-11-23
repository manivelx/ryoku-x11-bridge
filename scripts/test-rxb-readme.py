#!/usr/bin/env python3
"""Validate README Markdown structure and repository-relative links."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"


def heading_slug(text: str) -> str:
    text = re.sub(r"\s+#+\s*$", "", text).strip().lower()
    text = text.replace(chr(96), "")
    text = re.sub(r"[^\w\- ]", "", text, flags=re.UNICODE)
    return re.sub(r"\s+", "-", text).strip("-")


def markdown_anchors(markdown: str) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for line in markdown.splitlines():
        match = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not match:
            continue
        base = heading_slug(match.group(1))
        count = counts.get(base, 0)
        counts[base] = count + 1
        anchors.add(base if count == 0 else f"{base}-{count}")
    return anchors


def main() -> int:
    text = README.read_text(encoding="utf-8")
    errors: list[str] = []

    if text.count(chr(96) * 3) % 2:
        errors.append("README has an unclosed fenced code block.")

    if "not ready for installation on a daily-use machine" not in text:
        errors.append("README must clearly state the current host-installation gate.")

    if "Ryoku (X11 / i3)" not in text:
        errors.append("README must document the exact SDDM session name.")


    # The README must retain the upstream-inspired layout while distinguishing
    # reference imagery from an RXB screenshot and keeping the X11 safety gates.
    required_phrases = (
        "Ryoku X11 Bridge",
        "For the sake of power and beauty.",
        "Original Ryoku upstream showroom image",
        "not an RXB X11 screenshot",
        "Ryoku (X11 / i3)",
        "not ready for installation on a daily-use machine",
        "GT 740",
        "NVIDIA 470",
        "RXB does not add custom keybindings",
    )
    for phrase in required_phrases:
        if phrase not in text:
            errors.append(f"README is missing required project statement: {phrase}")

    if text.count("<img ") < 4:
        errors.append("README should include the Ryoku-inspired visual gallery.")

    # Keep all top-of-page badges visually consistent. GitHub's native
    # workflow badge endpoint ignores Shields styling, so workflow status
    # badges must use the Shields workflow-status endpoint like the static
    # environment badges do.
    badge_lines = [
        line for line in text.splitlines()
        if line.startswith("![") or line.startswith("[![")
    ]
    if len(badge_lines) != 6:
        errors.append(f"README should contain exactly six status/platform badges; found {len(badge_lines)}.")
    if any("style=for-the-badge" not in line for line in badge_lines):
        errors.append("Every README status/platform badge must use the same for-the-badge style.")
    if any(
        "actions/workflows/" in line
        and "img.shields.io/github/actions/workflow/status/" not in line
        for line in badge_lines
    ):
        errors.append("Workflow badges must use the Shields endpoint so their style matches the static badges.")
    if r"\\n|" in text:
        errors.append("README contains a literal \\n sequence that breaks a Markdown table row.")

    links = re.findall(r"\[[^\]]+\]\(([^)]+)\)", text)
    for raw_target in links:
        target = raw_target.strip()
        if not target or re.match(r"^(?:https?://|mailto:|tel:)", target, re.I):
            continue
        fragment = unquote(raw_target.split("#", 1)[1]) if "#" in raw_target else ""
        target_path = unquote(target.split("#", 1)[0])
        if not target_path:
            if fragment and fragment not in markdown_anchors(text):
                errors.append(f"Broken README heading link: #{fragment}")
            continue

        destination = (ROOT / target_path).resolve()
        if not destination.is_relative_to(ROOT.resolve()):
            errors.append(f"README link escapes repository: {raw_target}")
            continue
        if not destination.exists():
            errors.append(f"README link target does not exist: {raw_target}")
            continue
        if fragment and destination.suffix.lower() in {".md", ".markdown"}:
            anchors = markdown_anchors(destination.read_text(encoding="utf-8"))
            if fragment not in anchors:
                errors.append(f"README link has missing heading: {raw_target}")

    if errors:
        for error in errors:
            print(f"README check: {error}", file=sys.stderr)
        return 1

    print(f"README check passed: {len(links)} links inspected; fenced blocks balanced.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
