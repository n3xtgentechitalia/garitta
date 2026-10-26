#!/bin/bash
# Copy this checkout to another host, install it and run a garitta command there.
#
#   ./deploy.sh ssh <user@host> [garitta args...]
#   ./deploy.sh qm  <vmid>      [garitta args...]   Proxmox VE VM, through qemu-guest-agent (run on the node)
#   ./deploy.sh pct <ctid>      [garitta args...]   Proxmox VE container (run on the node)
#
# Example: ./deploy.sh ssh root@srv1 enable digest --disable-realtime-email --now
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
[ $# -ge 2 ] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
kind=$1 target=$2; shift 2
run=""
[ $# -eq 0 ] || run=" && /usr/local/sbin/garitta$(printf ' %q' "$@")"
if git rev-parse --git-dir >/dev/null 2>&1; then
  TGZ=$(git ls-files -z --cached --others --exclude-standard | tar czf - --null -T - | base64 -w0)
else
  TGZ=$(tar czf - --exclude=.git --exclude=dist --exclude=__pycache__ . | base64 -w0)
fi
REMOTE="set -o pipefail; d=\$(mktemp -d) && echo $TGZ | base64 -d | tar xzf - -C \$d && \$d/install.sh$run; rc=\$?; rm -rf \$d; exit \$rc"
case $kind in
  ssh) ssh "$target" "bash -c $(printf %q "$REMOTE")" ;;
  pct) pct exec "$target" -- bash -c "$REMOTE" ;;
  qm)
    # output travels base64-encoded: some characters can stall qemu-guest-agent
    W=$(printf '%s' "$REMOTE" | base64 -w0)
    qm guest exec "$target" --timeout 3000 -- bash -c "{ echo $W | base64 -d | bash; } 2>&1 | base64 -w0; exit \${PIPESTATUS[0]}" |
      python3 -I -c '
import sys, json, base64
d = json.load(sys.stdin)
sys.stdout.write(base64.b64decode(d.get("out-data", "")).decode(errors="replace"))
sys.exit(d.get("exitcode", 0) if d.get("exited", 1) else 99)' ;;
  *) echo "unknown target type: $kind (ssh|qm|pct)" >&2; exit 1 ;;
esac
