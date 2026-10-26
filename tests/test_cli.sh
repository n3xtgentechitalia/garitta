#!/bin/bash
# Tests for bin/garitta that do not touch systemd or the live CrowdSec configuration.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
G=$ROOT/bin/garitta
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export STUB_DIR=$T/stub PATH=$ROOT/tests/stubs:$PATH GARITTA_CONF_DIR=$T/etc
mkdir -p "$STUB_DIR" "$GARITTA_CONF_DIR"
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

printf '# comment\n#SUBJECT=\nMAX_ROWS="10"\n' > "$GARITTA_CONF_DIR/garitta-digest"
check "set writes quoted values"   0 '' "$G" set digest "SUBJECT=My site - CrowdSec" 'MAX_ROWS=20'
check "set replaces old lines"     0 '^SUBJECT="My site - CrowdSec"$' cat "$GARITTA_CONF_DIR/garitta-digest"
check "old entries are gone"       1 '' grep -E 'MAX_ROWS="10"|#SUBJECT=' "$GARITTA_CONF_DIR/garitta-digest"
check "set rejects garbage"        1 'expected KEY=VALUE' "$G" set digest 'lower=1'
check "unknown component"          1 "unknown component 'foo'" "$G" enable foo
check "unknown option"             1 'unknown option for enable blocklist' "$G" enable blocklist --bogus

echo '{"sharing_options": {"custom": true, "manual": true}}' > "$STUB_DIR/console.json"
printf 'name,description\n' > "$STUB_DIR/allowlists.csv"
check "custom sharing must be chosen" 1 "console option 'custom' is on" "$G" enable blocklist
check "help"                       0 'garitta enable blocklist' "$G" --help
check "version"                    0 '^garitta [0-9.]+$' "$G" version

echo "cli: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
