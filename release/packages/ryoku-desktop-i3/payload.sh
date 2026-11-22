#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: payload.sh build|install [pkgdir] [init]}
case "$mode" in
  build)
    : "${RYOKU_SRC:?RYOKU_SRC is required}"
    : "${RYOKU_BUILD_DIR:?RYOKU_BUILD_DIR is required}"
    mkdir -p "$RYOKU_BUILD_DIR"
    (
      cd "$RYOKU_SRC/cmd/ryoku-wm-i3"
      bridge_version="${RYOKU_BRIDGE_VERSION:-$(tr -d '[:space:]' < "$RYOKU_SRC/RXB_VERSION")}"
      go build -trimpath -ldflags "-X main.version=$bridge_version" -o "$RYOKU_BUILD_DIR/ryoku-wm-i3" .
    )
    ;;
  install)
    pkgdir=${2:?install requires pkgdir}
    init=${3:-systemd}
    : "${RYOKU_SRC:?RYOKU_SRC is required}"
    : "${RYOKU_BUILD_DIR:?RYOKU_BUILD_DIR is required}"
    [[ "$init" == systemd ]] || { echo "RXB supports only systemd user sessions" >&2; exit 1; }
    : "${RYOKU_UPSTREAM_DIR:?build-rxb-packages.sh must set RYOKU_UPSTREAM_DIR to the pinned source tree}"

    # Preserve the RXB license plus the complete pinned upstream license and
    # notice tree. The upstream NOTICE includes component attributions and
    # additional terms (notably the iNiR section 7 requirements).
    license_root="$pkgdir/usr/share/licenses/ryoku-desktop-i3"
    install -Dm644 "$RYOKU_SRC/LICENSE" "$license_root/LICENSE"
    install -Dm644 "$RYOKU_SRC/NOTICE" "$license_root/NOTICE"
    install -Dm644 "$RYOKU_SRC/THIRD_PARTY_NOTICES.md" "$pkgdir/usr/share/doc/ryoku-desktop-i3/THIRD_PARTY_NOTICES.md"
    while IFS= read -r -d '' notice_file; do
      relative_path="${notice_file#"$RYOKU_UPSTREAM_DIR"/}"
      install -Dm644 "$notice_file" "$license_root/upstream/$relative_path"
    done < <(find "$RYOKU_UPSTREAM_DIR" -type f \
      \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'NOTICE' -o -iname 'NOTICE.*' \
         -o -iname 'COPYING' -o -iname 'COPYING.*' -o -iname 'OFL.txt' \
         -o -iname '*.LICENSE-*.txt' \) \
      -not -path '*/.git/*' -print0)

    install -Dm755 "$RYOKU_BUILD_DIR/ryoku-wm-i3" "$pkgdir/usr/bin/ryoku-wm-i3"
    install -Dm755 "$RYOKU_SRC/payload/bin/ryoku-x11-session" "$pkgdir/usr/bin/ryoku-x11-session"
    install -Dm755 "$RYOKU_SRC/payload/bin/ryoku-x11-session-init" "$pkgdir/usr/bin/ryoku-x11-session-init"
    install -Dm755 "$RYOKU_SRC/payload/bin/ryoku-x11-lock" "$pkgdir/usr/bin/ryoku-x11-lock"

    install -d "$pkgdir/usr/share/ryoku/config/ryoku-x11"
    install -m644 "$RYOKU_SRC/payload/ryoku-x11/config" "$pkgdir/usr/share/ryoku/config/ryoku-x11/config"
    install -m644 "$RYOKU_SRC/payload/ryoku-x11/generated.conf" "$pkgdir/usr/share/ryoku/config/ryoku-x11/generated.conf"
    install -m644 "$RYOKU_SRC/payload/ryoku-x11/user.conf" "$pkgdir/usr/share/ryoku/config/ryoku-x11/user.conf"

    # RXB owns dedicated user units. Never drop in to or rewrite the upstream
    # Ryoku Wayland services: those units remain byte-for-byte untouched.
    install -Dm644 "$RYOKU_SRC/payload/systemd/ryoku-x11-session.target" \
      "$pkgdir/usr/lib/systemd/user/ryoku-x11-session.target"
    install -Dm644 "$RYOKU_SRC/payload/systemd/ryoku-shell-x11.service" \
      "$pkgdir/usr/lib/systemd/user/ryoku-shell-x11.service"
    install -Dm644 "$RYOKU_SRC/payload/systemd/ryogami-x11.service" \
      "$pkgdir/usr/lib/systemd/user/ryogami-x11.service"

    # Only the dedicated RXB target owns these services; no default or upstream
    # Ryoku target is enabled or modified.
    install -d "$pkgdir/usr/lib/systemd/user/ryoku-x11-session.target.wants"
    ln -sfn ../ryoku-shell-x11.service "$pkgdir/usr/lib/systemd/user/ryoku-x11-session.target.wants/ryoku-shell-x11.service"
    ln -sfn ../ryogami-x11.service "$pkgdir/usr/lib/systemd/user/ryoku-x11-session.target.wants/ryogami-x11.service"
    install -Dm644 /dev/stdin "$pkgdir/usr/share/xsessions/ryoku-x11.desktop" <<'EOF'
[Desktop Entry]
Name=Ryoku (X11 / i3)
Comment=Ryoku desktop on Xorg with i3
TryExec=i3
Exec=ryoku-x11-session
Type=Application
DesktopNames=Ryoku;
EOF
    ;;
  *)
    echo "unknown payload mode: $mode" >&2
    exit 2
    ;;
esac
