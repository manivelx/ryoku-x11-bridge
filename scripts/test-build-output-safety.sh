#!/usr/bin/env bash
set -euo pipefail

RXB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_SOURCE="${1:?usage: test-build-output-safety.sh /path/to/pinned/ryoku-checkout}"

if (( EUID == 0 )); then
  echo "test-build-output-safety: run as the unprivileged makepkg user." >&2
  exit 1
fi

tmp="$(mktemp -d)"
source_pkgdir="$RXB_ROOT/release/packages/ryoku-desktop-i3"
sentinel="$source_pkgdir/rxb-preserve-test.pkg.tar.zst"
cleanup() {
  rm -rf -- "$tmp"
  rm -f -- "$sentinel"
}
trap cleanup EXIT

# A caller-selected output directory may contain valuable package archives.
# The builder must refuse it without deleting or overwriting anything.
mkdir "$tmp/nonempty"
printf 'preserve-output-artifact\n' > "$tmp/nonempty/keep.pkg.tar.zst"
status=0
bash "$RXB_ROOT/scripts/build-rxb-packages.sh" "$UPSTREAM_SOURCE" "$tmp/nonempty" \
  > "$tmp/refuse.log" 2>&1 || status=$?
[[ "$status" -ne 0 ]] || {
  echo "Builder accepted a non-empty package output directory." >&2
  exit 1
}
[[ "$(cat "$tmp/nonempty/keep.pkg.tar.zst")" == "preserve-output-artifact" ]] || {
  echo "Builder modified an existing output artifact." >&2
  exit 1
}
grep -q "refusing to delete or overwrite" "$tmp/refuse.log" || {
  cat "$tmp/refuse.log" >&2
  echo "Builder did not explain why the non-empty output directory was rejected." >&2
  exit 1
}

# The RXB PKGBUILD lives in the user's checkout, not the disposable upstream
# worktree. A prior package archive there must survive a build unchanged.
[[ ! -e "$sentinel" && ! -L "$sentinel" ]] || {
  echo "Test sentinel already exists: $sentinel" >&2
  exit 1
}
find "$source_pkgdir" -maxdepth 1 -type f -name '*.pkg.tar.*' -printf '%f\n' | sort > "$tmp/source-before"
printf 'preserve-source-artifact\n' > "$sentinel"
{
  cat "$tmp/source-before"
  printf '%s\n' "$(basename "$sentinel")"
} | sort > "$tmp/source-expected"

# Replace makepkg with a tiny deterministic packager. This exercises the
# complete builder/worktree/copy flow without compiling upstream software.
mkdir "$tmp/fakebin"
cat > "$tmp/fakebin/makepkg" <<'FAKE_MAKEPKG'
#!/usr/bin/env bash
set -euo pipefail
pkgname="${PWD##*/}"
dest="${PKGDEST:-$PWD}"
mkdir -p "$dest"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
printf 'pkgname = %s\npkgver = 1.0-1\narch = any\nlicense = MIT\n' "$pkgname" > "$stage/.PKGINFO"
archive="$dest/$pkgname-1.0-1-any.pkg.tar.zst"
tar -C "$stage" -cf - .PKGINFO | zstd -q -T0 -o "$archive"
FAKE_MAKEPKG
chmod 0755 "$tmp/fakebin/makepkg"
mkdir "$tmp/output"
PATH="$tmp/fakebin:$PATH" bash "$RXB_ROOT/scripts/build-rxb-packages.sh" "$UPSTREAM_SOURCE" "$tmp/output"

mapfile -t built < <(find "$tmp/output" -maxdepth 1 -type f -name '*.pkg.tar.*' -print)
[[ "${#built[@]}" -eq 12 ]] || {
  echo "Expected 12 staged runtime packages, found ${#built[@]}." >&2
  printf '  %s\n' "${built[@]}" >&2
  exit 1
}
find "$source_pkgdir" -maxdepth 1 -type f -name '*.pkg.tar.*' -printf '%f\n' | sort > "$tmp/source-after"
diff -u "$tmp/source-expected" "$tmp/source-after" || {
  echo "Builder modified package archives in the RXB source tree." >&2
  exit 1
}

echo "RXB package builder preserves existing output and source artifacts."
