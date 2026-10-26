#!/bin/bash
# Install garitta from a source checkout.
#
#   sudo ./install.sh [--prefix DIR] [--unitdir DIR] [--destdir DIR]
#
#   --prefix   installation prefix (default /usr/local; /usr for distribution packages)
#   --unitdir  systemd unit directory (default /etc/systemd/system, or /usr/lib/systemd/system with --prefix /usr)
#   --destdir  stage into DIR instead of the live system (used to build packages)
#
# Then enable the components you want, e.g.:  sudo garitta enable digest --now
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
PREFIX=/usr/local UNITDIR= DESTDIR=
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) PREFIX=${2:?}; shift ;;
    --unitdir) UNITDIR=${2:?}; shift ;;
    --destdir) DESTDIR=${2:?}; shift ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -z "$UNITDIR" ]; then
  if [ "$PREFIX" = /usr ]; then UNITDIR=/usr/lib/systemd/system; else UNITDIR=/etc/systemd/system; fi
fi
SBINDIR=$PREFIX/sbin DOCDIR=$PREFIX/share/doc/garitta

if [ -z "$DESTDIR" ]; then
  [ "$(id -u)" -eq 0 ] || { echo "run as root (or use --destdir)" >&2; exit 1; }
  missing=()
  for c in bash curl python3 flock sha256sum systemctl; do command -v $c >/dev/null || missing+=("$c"); done
  [ ${#missing[@]} -eq 0 ] || { echo "missing: ${missing[*]} (apt install curl python3 util-linux)" >&2; exit 1; }
  python3 -I -c 'import sys; sys.exit(sys.version_info < (3, 8))' || { echo "python >= 3.8 required" >&2; exit 1; }
  command -v cscli >/dev/null || echo "warning: cscli not found, install CrowdSec before enabling components" >&2
fi

install -d "$DESTDIR$SBINDIR" "$DESTDIR$UNITDIR" "$DESTDIR/etc/default" "$DESTDIR$DOCDIR"
install -m 755 bin/garitta bin/garitta-blocklist bin/garitta-digest "$DESTDIR$SBINDIR/"
for u in systemd/*.service systemd/*.timer; do
  sed "s|@SBINDIR@|$SBINDIR|g" "$u" > "$DESTDIR$UNITDIR/$(basename "$u")"
  chmod 644 "$DESTDIR$UNITDIR/$(basename "$u")"
done
for f in etc/default/*; do
  # never overwrite an existing configuration
  [ -e "$DESTDIR/etc/default/$(basename "$f")" ] || install -m 600 "$f" "$DESTDIR/etc/default/"
done
install -m 644 README.md README.it.md CHANGELOG.md LICENSE "$DESTDIR$DOCDIR/"
cp -r docs "$DESTDIR$DOCDIR/" && chmod -R u=rwX,go=rX "$DESTDIR$DOCDIR/docs"

if [ -z "$DESTDIR" ]; then
  systemctl daemon-reload
  echo "garitta $(cat VERSION) installed in $SBINDIR. Next steps:"
  echo "  sudo garitta enable blocklist --now        # Data-Shield import (see docs/en/blocklist.md)"
  echo "  sudo garitta enable digest --now           # daily ban report (see docs/en/digest.md)"
fi
