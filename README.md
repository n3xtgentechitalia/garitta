# garitta

[![CI](https://github.com/n3xtgentechitalia/garitta/actions/workflows/ci.yml/badge.svg)](https://github.com/n3xtgentechitalia/garitta/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Daily ban digest and Data-Shield blocklist import for [CrowdSec](https://www.crowdsec.net).**

[Italiano](README.it.md) · [Blocklist](docs/en/blocklist.md) · [Digest](docs/en/digest.md) · [Design notes](docs/en/design-notes.md)

*Garitta* is Italian for a sentry box. The project adds two small scheduled jobs to a host that runs
the CrowdSec Local API:

| Component | What it does |
|---|---|
| **garitta-blocklist** | Imports the [Data-Shield IPv4 blocklist](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist) (about 110k addresses) as CrowdSec ban decisions once a day. Before importing it checks the SHA-256 and the entry count against the published metadata, the format, and the bouncer capacity. |
| **garitta-digest** | Sends one email a day with the CrowdSec and fail2ban bans, instead of one email per ban. Events that involve **allowlisted IPs** come first: an allowlisted IP that is banned anyway, a ban avoided by the allowlist, an IP ignored by fail2ban, failed Nextcloud logins with the user name. |

Both components are optional and independent. Nothing runs until you enable it.

```
              daily 05:30                                  daily 07:00
 data-shield.eu ──► garitta-blocklist ──► cscli decisions import ──► LAPI ──► bouncers (firewall)
 (SHA-256, count)   verify · validate                   ▲              │
                    capacity check                      │ allowlists   ▼
                                            alerts, decisions, logs ──► garitta-digest ──► email
                                          (crowdsec, fail2ban, nextcloud)
```

## Requirements

| | Supported |
|---|---|
| OS | Debian 11, 12, 13 · Ubuntu 20.04, 22.04, 24.04 (systemd) |
| CrowdSec | Security Engine with the Local API on the same host. 1.6.8+ recommended (allowlists) |
| Packages | `bash`, `curl`, `python3` ≥ 3.8 (standard library only), `util-linux` |
| Optional | `crowdsec-firewall-bouncer` (iptables/nftables), `ipset`, `fail2ban`, Nextcloud |

## Installation

From a release package:

```sh
sudo apt install ./garitta_0.1.0_all.deb
```

From source:

```sh
git clone https://github.com/n3xtgentechitalia/garitta.git && cd garitta
sudo ./install.sh                 # /usr/local/sbin, /etc/systemd/system, /etc/default/garitta-*
```

To build the package yourself: `make deb` (output in `dist/`).

## Quick start

```sh
# daily report; preview it first without sending anything
sudo garitta-digest --dry-run --since 24h
sudo garitta enable digest --disable-realtime-email --now --to you@example.org

# Data-Shield import (read "Central API sharing" below first)
sudo garitta enable blocklist --disable-custom-sharing --now

garitta status
```

Other commands: `garitta set <blocklist|digest> KEY=VALUE`, `garitta disable blocklist [--purge]`,
`garitta disable digest [--restore]`. To install on other machines from a checkout:
`./deploy.sh ssh root@host enable digest --now` (Proxmox VE targets: `qm <vmid>`, `pct <ctid>`).

## What garitta changes in CrowdSec

garitta only changes CrowdSec when you pass an explicit option. Each change is printed and can be
undone:

| Option | Change | Undo |
|---|---|---|
| `enable blocklist --disable-custom-sharing` | `cscli console disable custom` | `cscli console enable custom` |
| `enable digest --disable-realtime-email` | comments out `- email_default` in `profiles.yaml` (backup in `/etc/crowdsec/.garitta-backup/`) | `garitta disable digest --restore` |
| `enable digest --move-parser-whitelists` | moves local parser whitelists **fully covered** by Local API allowlists to the backup directory | `garitta disable digest --restore` |

### Central API sharing

The Local API classifies alerts created by `cscli decisions import` as **custom** (origin
`cscli-import`, no scenario hash). When the console option `custom` is on, which is the default
after enrollment, it pushes them to the CrowdSec Central API with all their decisions. With this
blocklist that is about 110k third-party IPs per import. `garitta enable blocklist` therefore stops
when the option is on and asks you to choose. Details and source references are in
[docs/en/design-notes.md](docs/en/design-notes.md).

## Configuration

`/etc/default/garitta-blocklist` and `/etc/default/garitta-digest`; every option is listed, commented
out, with its default. The options are described in [docs/en/blocklist.md](docs/en/blocklist.md) and
[docs/en/digest.md](docs/en/digest.md). Run times: `systemctl edit garitta-<component>.timer`.

## Development

```sh
make test     # shell + Python tests, no root and no CrowdSec needed (cscli is stubbed)
make lint     # shellcheck + ruff
make deb
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described in [SECURITY.md](SECURITY.md).

## Credits and license

- The Data-Shield IPv4 blocklist is maintained by [duggytuxy](https://github.com/duggytuxy) and
  published under GPL-3.0. garitta downloads it at run time and does not redistribute it. Report
  false positives [to the list maintainers](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist/issues).
- garitta is an independent project, not affiliated with or endorsed by CrowdSec. CrowdSec is a
  trademark of its owner.
- garitta is released under the [MIT License](LICENSE).

## Author

Created and maintained by **Alessio Giustini**, founder of [N3XTGENTECH](https://n3xtgentech.it)
([@n3xtgentechitalia](https://github.com/n3xtgentechitalia)).
