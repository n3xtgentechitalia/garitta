# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
[private vulnerability reporting](../../security/advisories/new) for this repository, with a
description, the affected version and steps to reproduce. You will get an answer within 7 days.

## Scope

garitta runs as root on hosts that enforce firewall decisions. Relevant reports include:
the ways a tampered blocklist could get imported despite the checks, injection through log content
into the email report, unsafe handling of the CrowdSec configuration, and leaked SMTP credentials.

False positives in the Data-Shield blocklist itself belong to the
[list maintainers](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist/issues).

## Segnalazioni (italiano)

Non aprire issue pubbliche per problemi di sicurezza: usa la segnalazione privata di GitHub
(*Security → Report a vulnerability*).
