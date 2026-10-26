#!/bin/bash
# Tests for bin/garitta-blocklist with local file:// mirrors and the cscli stub.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BL=$ROOT/bin/garitta-blocklist
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export STUB_DIR=$T/stub PATH=$ROOT/tests/stubs:$PATH
mkdir -p "$STUB_DIR"
fail=0 pass=0
check() {  # check <name> <expected rc> <grep pattern> <cmd...>
  local name=$1 want=$2 pat=$3; shift 3
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq "$want" ] && grep -qE -- "$pat" <<<"$out"; then
    pass=$((pass + 1)); echo "ok   $name"
  else
    fail=$((fail + 1)); echo "FAIL $name (rc=$rc, want $want, pattern '$pat')"; sed 's/^/     /' <<<"$out"
  fi
}

# fixture: 25000 public addresses in 8.0.0.0/8, published-format metadata
python3 -I - "$T" <<'PY'
import sys, hashlib, json, ipaddress
d = sys.argv[1]
ips = [str(ipaddress.IPv4Address(int(ipaddress.IPv4Address('8.0.0.1')) + i)) for i in range(25000)]
body = ('\n'.join(ips) + '\n').encode()
open(f'{d}/prod_data-shield_ipv4_blocklist.txt', 'wb').write(body)
meta = {'profiles': {'standard': {'sha256': hashlib.sha256(body).hexdigest(), 'blocked': len(ips)}}}
json.dump(meta, open(f'{d}/latest.json', 'w'))
meta['profiles']['standard']['sha256'] = '0' * 64
json.dump(meta, open(f'{d}/stale.json', 'w'))
open(f'{d}/bad.txt', 'w').write('\n'.join(ips[:-1] + ['<html>']) + '\n')
PY
printf '8.0.0.1\n8.0.0.2\n' > "$STUB_DIR/allowlisted.txt"

conf() {  # conf <metadata file> <list dir> [extra lines]
  local c=$T/conf; {
    echo "METADATA_URL=file://$T/$1"
    echo "MIRRORS=\"file://$2/{file}\""
    echo "CURL_PROTO='=file'"
    echo "STATE_DIR=$T/state RETRIES=1 RETRY_WAIT=0 MAX=100000"
    shift 2; printf '%s\n' "$@"
  } > "$c"; echo "$c"
}
run() { GARITTA_BLOCKLIST_CONF=$1 "$BL" "${@:2}"; }

check "verified import"            0 'imported 24998 IPs .*allowlists: 2' run "$(conf latest.json "$T")"
check "status file written"        0 'verified=yes'                       cat "$T/state/status"
check "import arguments"           0 '--duration 36h --reason data-shield-standard' cat "$STUB_DIR/calls"
check "dry run does not import"    0 'dry run: 25000 IPs'                 run "$(conf latest.json "$T")" --dry-run
check "sha mismatch is refused"    1 'no verified copy'                   run "$(conf stale.json "$T")"
check "REQUIRE_SHA=no falls back"  0 'WARNING: SHA-256 not verified'      run "$(conf stale.json "$T" REQUIRE_SHA=no)"
check "capacity limit"             1 'outside the range'                  run "$(conf latest.json "$T" MAX=1000)"
mkdir -p "$T/badmirror" && cp "$T/bad.txt" "$T/badmirror/prod_data-shield_ipv4_blocklist.txt"
check "invalid lines are refused"  1 'invalid lines'                      run "$(conf stale.json "$T/badmirror" REQUIRE_SHA=no)"
check "unreachable mirror"         1 'download failed'                    run "$(conf latest.json "$T/missing")"
check "invalid profile"            2 'invalid PROFILE'                    run "$(conf latest.json "$T" PROFILE=huge)"
check "version"                    0 '^garitta-blocklist [0-9.]+$'        "$BL" --version

echo "blocklist: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
