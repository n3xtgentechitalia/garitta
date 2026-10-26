# garitta-blocklist

Imports the [Data-Shield IPv4 blocklist](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist)
into CrowdSec as `ban` decisions. The bouncers already registered on the Local API enforce them.

## How a run works

1. **Metadata.** Downloads `https://data-shield.eu/data/latest.json`, which holds the SHA-256 and the
   entry count of each profile.
2. **Download.** Fetches the list from the primary publication (GitHub raw). If the SHA-256 differs it
   tries GitLab, Codeberg and jsDelivr in turn. The website refreshes the metadata hourly, so it can
   lag behind a new publication. In that case the run waits `RETRY_WAIT` seconds and tries again, up
   to `RETRIES` rounds. Without a verified copy nothing is imported (`REQUIRE_SHA=yes`).
3. **Validation.** Requires one canonical IPv4 address per line, no duplicates, and a count equal to
   the metadata. One invalid line rejects the whole list.
4. **Capacity.** With the iptables/ipset firewall bouncer, each origin gets an ipset with a fixed
   `maxelem` (131072 by default). With `MAX=auto` the list must fit in 95% of that value.
5. **Import.** `cscli decisions import --format values --type ban --duration 36h --reason data-shield-<profile>`.
   cscli checks the Local API allowlists (CrowdSec ≥ 1.6.8) and skips allowlisted IPs.
6. **Status.** Writes the outcome to `/var/lib/garitta/blocklist/status` and keeps the last imported
   list next to it.

The run exits non-zero whenever it skips an import, so `systemctl --failed` and the digest report
make it visible.

## Why a 36h duration with a daily run

- If one run fails, the protection stays in place.
- IPs removed from the list expire on their own.
- Overlapping imports never unban anything: the Local API reports an IP as expired to the bouncers
  only when its longest decision expires (`longestDecisionForScopeTypeValue`).
- Expired alerts are removed by `db_config.flush.max_age` (7 days by default). In steady state the
  database holds about 7–8 imports (~800k rows for the standard profile).

Data-Shield regenerates the list every two hours, but a daily import is the right trade-off for an
import-based integration. Every import adds a full copy to the CrowdSec database.

## Configuration (`/etc/default/garitta-blocklist`)

| Option | Default | Meaning |
|---|---|---|
| `PROFILE` | `standard` | `standard` or `critical` (broader). The two lists are kept separate. |
| `DURATION` | `36h` | Decision duration. Keep it longer than the timer interval. |
| `MAX` | `auto` | Maximum number of entries. `auto` = 95% of the CrowdSec ipset `maxelem`, else 250000. |
| `MIN` | `20000` | Fewer entries are treated as a truncated download. |
| `REQUIRE_SHA` | `yes` | `no` = after failed verification, import the downloaded copy anyway (format checks only). |
| `RETRIES` / `RETRY_WAIT` | `3` / `600` | Verification rounds and the pause between them, in seconds. |
| `BATCH` | `20000` | Decisions per Local API request. |
| `METADATA_URL`, `MIRRORS` | data-shield.eu, 4 mirrors | Override them for an internal mirror. `{file}` stands for the list file name. |

## Enabling

```sh
sudo garitta-blocklist --dry-run                       # download and verify only
sudo garitta enable blocklist --disable-custom-sharing --now
```

`garitta enable blocklist` checks the Local API, the bouncers, allowlist support and the console
sharing option. If `custom` sharing is on it stops until you choose:

- `--disable-custom-sharing` runs `cscli console disable custom`. Alerts from your own local or
  modified scenarios stop being shared too. Official Hub scenarios and the community blocklist are
  not affected.
- `--accept-custom-sharing` keeps sharing on. Every import is pushed to the Central API.

## Checking

```sh
garitta status
journalctl -u garitta-blocklist -n 30
cscli decisions list --origin cscli-import --scenario data-shield-standard --limit 0 -o raw | wc -l
ipset list -t | grep -E 'Name|entries'
```

## Removing

`sudo garitta disable blocklist` stops the timer, and the decisions expire within `DURATION`.
`--purge` deletes them immediately, together with the state.
