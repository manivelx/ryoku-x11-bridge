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

    install -Dm644 "$RYOKU_SRC/payload/systemd/ryoku-shell.service.d/10-rxb-x11.conf" \
      "$pkgdir/usr/lib/systemd/user/ryoku-shell.service.d/10-rxb-x11.conf"
    install -Dm644 "$RYOKU_SRC/payload/systemd/ryogami.service.d/10-rxb-x11.conf" \
      "$pkgdir/usr/lib/systemd/user/ryogami.service.d/10-rxb-x11.conf"

    # Enable the shell only when the RXB session target is explicitly started.
    install -d "$pkgdir/usr/lib/systemd/user/ryoku-session.target.wants"
    ln -sfn ../ryoku-shell.service "$pkgdir/usr/lib/systemd/user/ryoku-session.target.wants/ryoku-shell.service"
    ln -sfn ../ryogami.service "$pkgdir/usr/lib/systemd/user/ryoku-session.target.wants/ryogami.service"
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
