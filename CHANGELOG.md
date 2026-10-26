# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-26

### Added
- `garitta-blocklist`: daily import of the Data-Shield IPv4 blocklist as CrowdSec decisions, with
  SHA-256/count verification against `data-shield.eu/data/latest.json`, mirror fallback, strict
  format validation, ipset capacity check and `--dry-run`.
- `garitta-digest`: daily HTML + text email report of CrowdSec and fail2ban bans, allowlisted IPs
  first (banned anyway, ban avoided, fail2ban ignore, failed Nextcloud logins), English and Italian.
- `garitta` command: `enable`, `disable`, `set`, `status`, with explicit opt-in for every CrowdSec
  change (console custom sharing, real-time email, parser whitelists) and `--restore`/`--purge`.
- Source installer, `.deb` package for Debian 11+ / Ubuntu 20.04+, `deploy.sh` for ssh and
  Proxmox VE targets.
- Test suite with a cscli stub, CI on Debian and Ubuntu containers.

[Unreleased]: https://github.com/n3xtgentechitalia/garitta/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/n3xtgentechitalia/garitta/releases/tag/v0.1.0
