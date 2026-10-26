#!/bin/bash
# Remove a source installation of garitta.
#
#   sudo ./uninstall.sh [--prefix DIR] [--purge] [--restore]
#
#   --purge    also delete imported decisions, state and configuration files
#   --restore  undo the CrowdSec changes made by `garitta enable digest` (real-time email, parser whitelists)
set -euo pipefail
PREFIX=/usr/local PURGE=no RESTORE=no
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) PREFIX=${2:?}; shift ;;
    --purge) PURGE=yes ;;
    --restore) RESTORE=yes ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
G=$PREFIX/sbin/garitta
if [ -x "$G" ]; then
  if [ "$PURGE" = yes ]; then "$G" disable blocklist --purge; else "$G" disable blocklist; fi
  if [ "$RESTORE" = yes ]; then "$G" disable digest --restore; else "$G" disable digest; fi
fi
if [ "$PREFIX" = /usr ]; then UNITDIR=/usr/lib/systemd/system; else UNITDIR=/etc/systemd/system; fi
for u in garitta-blocklist garitta-digest; do
  rm -f "$UNITDIR/$u.service" "$UNITDIR/$u.timer"
done
rm -f "$PREFIX/sbin/garitta" "$PREFIX/sbin/garitta-blocklist" "$PREFIX/sbin/garitta-digest"
rm -rf "$PREFIX/share/doc/garitta"
systemctl daemon-reload
if [ "$PURGE" = yes ]; then
  rm -rf /var/lib/garitta /etc/default/garitta-blocklist /etc/default/garitta-digest
fi
echo "garitta removed"
