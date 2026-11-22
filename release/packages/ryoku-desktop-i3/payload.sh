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
