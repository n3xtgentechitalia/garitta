# garitta-digest

One email a day with the bans of the period, instead of one CrowdSec notification per ban.

## Report layout

1. **Allowlisted IPs involved.** Shown in a red box (green when there is nothing), one row per IP,
   with the allowlist entry that covers it:
   - **BANNED** – an allowlisted IP has a ban anyway (CrowdSec, cscli or fail2ban). This is the most
     severe case and is also flagged in the subject (`[!! N allowlisted IPs BANNED]`).
   - **CrowdSec: ban avoided** – a scenario fired and the allowlist dropped the alert.
   - **fail2ban: ignored** – fail2ban skipped the IP because of `ignoreip`.
   - **Nextcloud: failed login**, with the user name. This usually means an old password saved on a
     device at a trusted site.
2. **Bans applied.** One row per IP: country, AS, reasons (CrowdSec scenarios and fail2ban jails,
   with counts), expiry, and a link to the CrowdSec CTI.
3. **Status.** Active decisions per origin (CAPI, lists, cscli-import...), the last Data-Shield
   import, and failed Nextcloud logins.

The period runs from the last successful report (at most 7 days; 24h for the first report). A
report is sent even when there is nothing to show, so its arrival also confirms the service works.
The email has an HTML part and a plain-text part, and the report is available in English or
Italian (`REPORT_LANG`).

## Data sources

| Source | Used for |
|---|---|
| `cscli alerts list --origin crowdsec` / `--origin cscli` | bans applied by scenarios and by hand |
| `crowdsec.log` (rotated files too) | `Ip X performed 'scenario'` overflows from allowlisted IPs |
| `fail2ban.log*` | `Ban` and `Ignore ... by ip` lines |
| `nextcloud.log*` | `Login failed` lines (both formats) |
| `cscli allowlists` + local parser whitelists | what counts as allowlisted |
| `cscli decisions list -a` | counters by origin |

SMTP server, credentials, sender and recipients are read from the CrowdSec email plugin
(`/etc/crowdsec/notifications/email.yaml`). If CrowdSec email notifications work, the digest works
too. Encryption: `ssltls`, `starttls` or `none`.

## Parser whitelists vs. allowlists

A local **parser whitelist** (a file in `parsers/s02-enrich/` with `whitelist: ip: [...]`) drops events
*before* scenarios run, so a ban it avoids leaves no trace. A **Local API allowlist** (`cscli
allowlists`, CrowdSec ≥ 1.6.8) drops the alert *after* the scenario fires and logs it. CrowdSec
recommends allowlists for IP-based rules, and they also apply to blocklists and to
`cscli decisions add/import`.

`garitta-digest --check-parser-whitelists` lists the local parser whitelists and whether the
allowlists cover them. `garitta enable digest --move-parser-whitelists` moves only the **fully
covered** ones (same IPs/ranges, no `expression`) to `/etc/crowdsec/.garitta-backup/parsers/`.
Protection stays the same, and avoided bans start appearing in the report.

## Configuration (`/etc/default/garitta-digest`)

| Option | Default | Meaning |
|---|---|---|
| `REPORT_LANG` | `en` | `en` or `it` |
| `SMTP_CONF` | `/etc/crowdsec/notifications/email.yaml` | CrowdSec email plugin configuration |
| `MAIL_TO` | *(empty)* | Comma-separated recipients; empty = `receiver_emails` |
| `SUBJECT` | *(empty)* | Subject prefix; empty = `email_subject` |
| `REPORT_NAME` | *(empty)* | Server name in the report; empty = FQDN |
| `FAIL2BAN_LOG` | `/var/log/fail2ban.log` | Empty = ignore fail2ban |
| `NEXTCLOUD_LOG` | `auto` | `auto` = `/var/www/nextcloud/data/nextcloud.log` if present; empty = ignore |
| `MAX_ROWS` | `300` | Maximum rows in the bans table |

## Enabling

```sh
sudo garitta-digest --dry-run --since 24h      # preview in /var/lib/garitta/digest/preview.html
sudo garitta set digest REPORT_LANG=it "SUBJECT=My site - CrowdSec"
sudo garitta enable digest --disable-realtime-email --move-parser-whitelists --now --to you@example.org
```

`--disable-realtime-email` comments out `- email_default` in `/etc/crowdsec/profiles.yaml` and backs
it up. Other notifications, such as Slack, are left alone. The report is sent daily at 07:00
(`systemctl edit garitta-digest.timer`).

## Removing

`sudo garitta disable digest --restore` stops the timer, re-enables real-time email and puts the
moved parser whitelists back.
