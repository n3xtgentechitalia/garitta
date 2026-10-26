# Contributing

Thanks for helping. Issues and pull requests are welcome in English or Italian.

## Development setup

No root, CrowdSec or network access is needed for the tests: `tests/stubs/cscli` stands in for
cscli and the blocklist tests use local `file://` mirrors.

```sh
make test          # tests/test_blocklist.sh + python unittest
make lint          # shellcheck (bash) + ruff (python), if installed
make deb           # dist/garitta_<version>_all.deb
```

## Guidelines

- **Compatibility.** Debian 11+ and Ubuntu 20.04+: bash ≥ 4.4 and Python ≥ 3.8, standard library
  only. Do not add runtime dependencies.
- **Safety first.** Anything that changes the CrowdSec configuration must be opt-in, print what it
  does, back up what it touches, and be reversible with `garitta disable ... --restore`.
- **Fail closed.** If a check fails, keep the current state (no partial imports) and exit non-zero
  so the failure shows in `systemctl --failed`.
- **Tests.** Every behaviour change needs a test. Bug fixes start with a failing test.
- **Docs.** User-facing changes update both `docs/en` and `docs/it` plus `CHANGELOG.md`
  (`Unreleased` section).
- **Versioning.** Bump `VERSION` and the `VERSION=` constant in `bin/*` together; `make check-version`
  verifies they match.
- Commit messages: short imperative subject (`digest: group bans per IP`), with details in the body.

## Contribuire (italiano)

Le stesse regole valgono in italiano: test senza root (cscli è simulato), nessuna nuova dipendenza,
ogni modifica a CrowdSec facoltativa, annunciata e reversibile, documentazione aggiornata sia in
`docs/en` sia in `docs/it`.
