#!/bin/bash
# Build an architecture-independent .deb (Debian 11+ / Ubuntu 20.04+) into dist/.
#   packaging/deb/build.sh            maintainer overridable with $DEBFULLNAME / $DEBEMAIL
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/../.."
VERSION=$(cat VERSION)
NAME=${DEBFULLNAME:-Alessio Giustini}
MAIL=${DEBEMAIL:-n3xtgentechitalia@users.noreply.github.com}
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
chmod 755 "$ROOT"
./install.sh --destdir "$ROOT" --prefix /usr --unitdir /usr/lib/systemd/system
chmod 644 "$ROOT"/etc/default/garitta-*      # conffiles; the source installer uses 600

install -d "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<CTRL
Package: garitta
Version: $VERSION
Section: net
Priority: optional
Architecture: all
Depends: bash (>= 4.4), curl, python3 (>= 3.8), util-linux, coreutils, systemd
Recommends: crowdsec
Suggests: crowdsec-firewall-bouncer-iptables | crowdsec-firewall-bouncer-nftables, ipset, fail2ban
Installed-Size: $(du -sk "$ROOT" | cut -f1)
Maintainer: $NAME <$MAIL>
Homepage: https://github.com/n3xtgentechitalia/garitta
Description: daily ban digest and Data-Shield blocklist import for CrowdSec
 garitta adds two scheduled jobs to a CrowdSec Local API host:
  - garitta-blocklist imports the Data-Shield IPv4 blocklist as ban decisions,
    after verifying its SHA-256 and content;
  - garitta-digest emails a daily report of CrowdSec and fail2ban bans, with the
    events that involve allowlisted IPs listed first.
 Nothing is enabled at install time: run "garitta enable <component>".
CTRL
printf '/etc/default/garitta-blocklist\n/etc/default/garitta-digest\n' > "$ROOT/DEBIAN/conffiles"
cat > "$ROOT/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -e
if [ "$1" = configure ] && [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
  # restart enabled timers so that upgraded units are picked up
  for t in garitta-blocklist.timer garitta-digest.timer; do
    if systemctl is-enabled --quiet "$t" 2>/dev/null; then systemctl restart "$t" || true; fi
  done
fi
if [ "$1" = configure ] && [ -z "$2" ]; then
  echo "garitta installed. Enable components with: garitta enable blocklist|digest --now"
fi
exit 0
SH
cat > "$ROOT/DEBIAN/prerm" <<'SH'
#!/bin/sh
set -e
if [ "$1" = remove ] && [ -d /run/systemd/system ]; then
  systemctl disable --now garitta-blocklist.timer garitta-digest.timer >/dev/null 2>&1 || true
fi
exit 0
SH
cat > "$ROOT/DEBIAN/postrm" <<'SH'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
  rm -rf /var/lib/garitta
fi
if [ -d /run/systemd/system ]; then systemctl daemon-reload || true; fi
exit 0
SH
chmod 755 "$ROOT"/DEBIAN/postinst "$ROOT"/DEBIAN/prerm "$ROOT"/DEBIAN/postrm

DOC=$ROOT/usr/share/doc/garitta
gzip -9n "$DOC/CHANGELOG.md"
cat > "$DOC/copyright" <<COPY
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: garitta
Source: https://github.com/n3xtgentechitalia/garitta

Files: *
Copyright: 2026 Alessio Giustini - N3XTGENTECH <https://n3xtgentech.it>
License: MIT
 See /usr/share/doc/garitta/LICENSE.
COPY
mkdir -p dist
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "dist/garitta_${VERSION}_all.deb"
