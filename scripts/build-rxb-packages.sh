#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "build-rxb-packages: run as an unprivileged makepkg user, not root." >&2
  exit 1
fi

RXB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_SOURCE="${1:?usage: build-rxb-packages.sh /path/to/pinned/ryoku-checkout [output-dir]}"
OUT="${2:-$RXB_ROOT/dist}"
PIN="$(tr -d '[:space:]' < "$RXB_ROOT/UPSTREAM_PIN")"
RXB_VERSION="$(tr -d '[:space:]' < "$RXB_ROOT/RXB_VERSION")"

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
shopt -s nullglob
existing_artifacts=("$OUT"/*.pkg.tar.*)
if ((${#existing_artifacts[@]} > 0)); then
  echo "Output directory already contains package archives; refusing to delete or overwrite them:" >&2
  printf '  %s\n' "${existing_artifacts[@]}" >&2
  echo "Choose an empty output directory or move the existing archives first." >&2
  exit 1
fi

# Work in a disposable detached worktree. Never patch the user's upstream clone.
WORKTREE="$(mktemp -d "$OUT/.rxb-upstream.XXXXXX")"
rmdir "$WORKTREE"
I3_PKGDEST=""
cleanup_build() {
  if [[ -n "$I3_PKGDEST" && -d "$I3_PKGDEST" ]]; then
    rm -rf -- "$I3_PKGDEST"
  fi
  git -C "$UPSTREAM_SOURCE" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || rm -rf -- "$WORKTREE"
}
git -C "$UPSTREAM_SOURCE" worktree add --detach "$WORKTREE" "$PIN"
trap cleanup_build EXIT
UPSTREAM="$WORKTREE"

echo "[1/3] Applying the pinned RXB X11 overlay in the disposable worktree..."
python3 "$RXB_ROOT/scripts/apply-upstream-overlay.py" "$UPSTREAM"

copy_runtime_packages() {
  local pkg pkgname
  local -a runtime_artifacts=()
  for pkg in "$@"; do
    pkgname="$(bsdtar -xOf "$pkg" .PKGINFO | sed -n 's/^pkgname = //p' | head -n1)"
    if [[ "$pkgname" == *-debug ]]; then
      echo "Skipping split debug package from runtime set: $pkgname"
      continue
    fi
    runtime_artifacts+=("$pkg")
  done
  (("${#runtime_artifacts[@]}" > 0)) || { echo "No runtime package artifacts found." >&2; exit 1; }
  cp -f -- "${runtime_artifacts[@]}" "$OUT/"
}

build_package() {
  local repo="$1"
  local name="$2"
  local dir="$repo/release/packages/$name"
  [[ -f "$dir/PKGBUILD" ]] || { echo "Missing PKGBUILD: $dir" >&2; exit 1; }
  echo "Building $name..."
  # makepkg may emit a separate -debug package after the main package.
  # Keep those symbols out of the runtime set: upstream split debug packages
  # can share build IDs and are not required to install or run the desktop.
  find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.*' -delete
  (
    cd "$dir"
    makepkg --nodeps --clean --noconfirm --force
  )
  local -a artifacts
  mapfile -t artifacts < <(find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.*' -print | sort)
  (("${#artifacts[@]}" > 0)) || { echo "No package artifacts produced for $name" >&2; exit 1; }
  copy_runtime_packages "${artifacts[@]}"
}

echo "[2/3] Building the original Ryoku runtime and desktop payload..."
for package in gpk ryoku-blobs ryoku-palette-bridge ryoku-shell ryoku-hub ryogami ryoku-cursors ryoku-cursor-material ryoku ryoku-desktop; do
  build_package "$UPSTREAM" "$package"
done

echo "[3/3] Building the RXB i3 provider/session package..."
i3_package_dir="$RXB_ROOT/release/packages/ryoku-desktop-i3"
I3_PKGDEST="$(mktemp -d "$OUT/.rxb-i3-pkgdest.XXXXXX")"
(
  cd "$i3_package_dir"
  PKGDEST="$I3_PKGDEST" RYOKU_UPSTREAM_DIR="$UPSTREAM" RYOKU_PKGVER="$VERSION" RYOKU_BRIDGE_VERSION="$RXB_VERSION" makepkg --nodeps --clean --noconfirm --force
)
mapfile -t i3_artifacts < <(find "$I3_PKGDEST" -maxdepth 1 -type f -name '*.pkg.tar.*' -print | sort)
(("${#i3_artifacts[@]}" > 0)) || { echo "No ryoku-desktop-i3 package artifacts produced." >&2; exit 1; }
copy_runtime_packages "${i3_artifacts[@]}"
rm -rf -- "$I3_PKGDEST"
I3_PKGDEST=""

echo
echo "Build complete. Packages are in: $OUT"
echo "No packages were installed. Review them in a disposable Arch/CachyOS VM before any installation."
