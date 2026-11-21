#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "build-rxb-packages: run as an unprivileged makepkg user, not root." >&2
  exit 1
fi

RXB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_SOURCE="${1:?usage: build-rxb-packages.sh /path/to/pinned/ryoku-checkout [output-dir]}"
OUT="${2:-$RXB_ROOT/dist}"
PIN="0bf11741b22f69f22ad2733025671c7d0a5e1a47"

[[ -d "$UPSTREAM_SOURCE/.git" || -f "$UPSTREAM_SOURCE/.git" ]] || { echo "Not a git checkout: $UPSTREAM_SOURCE" >&2; exit 1; }
HEAD="$(git -C "$UPSTREAM_SOURCE" rev-parse HEAD)"
[[ "$HEAD" == "$PIN" ]] || {
  echo "Expected upstream $PIN, got $HEAD. Refusing to build against an unreviewed revision." >&2
  exit 1
}
command -v makepkg >/dev/null 2>&1 || { echo "makepkg is required (run on Arch/CachyOS)." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < "$UPSTREAM_SOURCE/VERSION")"
[[ -n "$VERSION" ]] || { echo "Upstream VERSION is empty." >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Work in a disposable detached worktree. Never patch the user's upstream clone.
WORKTREE="$(mktemp -d "$OUT/.rxb-upstream.XXXXXX")"
rmdir "$WORKTREE"
git -C "$UPSTREAM_SOURCE" worktree add --detach "$WORKTREE" "$PIN"
trap 'git -C "$UPSTREAM_SOURCE" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || rm -rf "$WORKTREE"' EXIT
UPSTREAM="$WORKTREE"

echo "[1/3] Applying the pinned RXB X11 overlay in the disposable worktree..."
python3 "$RXB_ROOT/scripts/apply-upstream-overlay.py" "$UPSTREAM"

build_package() {
  local repo="$1"
  local name="$2"
  local dir="$repo/release/packages/$name"
  [[ -f "$dir/PKGBUILD" ]] || { echo "Missing PKGBUILD: $dir" >&2; exit 1; }
  echo "Building $name..."
  (
    cd "$dir"
    makepkg --nodeps --clean --noconfirm --force
  )
  local artifact
  artifact="$(find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.*' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
  [[ -n "$artifact" && -f "$artifact" ]] || { echo "No package artifact produced for $name" >&2; exit 1; }
  cp -f "$artifact" "$OUT/"
}

echo "[2/3] Building the original Ryoku runtime and desktop payload..."
for package in gpk ryoku-keyring ryoku-blobs ryoku-palette-bridge ryoku-shell ryoku-hub ryogami ryoku ryoku-desktop; do
  build_package "$UPSTREAM" "$package"
done

echo "[3/3] Building the RXB i3 provider/session package..."
(
  cd "$RXB_ROOT/release/packages/ryoku-desktop-i3"
  RYOKU_PKGVER="$VERSION" makepkg --nodeps --clean --noconfirm --force
)
artifact="$(find "$RXB_ROOT/release/packages/ryoku-desktop-i3" -maxdepth 1 -type f -name '*.pkg.tar.*' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
[[ -n "$artifact" && -f "$artifact" ]] || { echo "No ryoku-desktop-i3 package artifact produced." >&2; exit 1; }
cp -f "$artifact" "$OUT/"

echo
echo "Build complete. Packages are in: $OUT"
echo "No packages were installed. Review them in a disposable Arch/CachyOS VM before any installation."
