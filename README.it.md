# garitta

[![CI](https://github.com/n3xtgentechitalia/garitta/actions/workflows/ci.yml/badge.svg)](https://github.com/n3xtgentechitalia/garitta/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Report giornaliero dei ban e import della blocklist Data-Shield per [CrowdSec](https://www.crowdsec.net).**

[English](README.md) · [Blocklist](docs/it/blocklist.md) · [Report](docs/it/digest.md) · [Note di progetto](docs/it/design-notes.md)

La *garitta* è il casotto della sentinella. Il progetto aggiunge due piccoli job pianificati a una
macchina che ospita la Local API di CrowdSec:

| Componente | Cosa fa |
|---|---|
| **garitta-blocklist** | Importa una volta al giorno la [blocklist Data-Shield IPv4](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist) (circa 110k indirizzi) come decisioni di ban di CrowdSec. Prima dell'import controlla SHA-256 e numero di voci rispetto ai metadati pubblicati, il formato e la capienza del bouncer. |
| **garitta-digest** | Manda un'email al giorno con i ban di CrowdSec e fail2ban, invece di un'email per ogni ban. In testa gli eventi che riguardano **IP in whitelist**: IP in whitelist bannato comunque, ban evitato grazie all'allowlist, IP ignorato da fail2ban, login Nextcloud falliti con il nome utente. |

I due componenti sono facoltativi e indipendenti. Nessuno dei due parte finché non lo attivi.

```
              ogni giorno 05:30                            ogni giorno 07:00
 data-shield.eu ──► garitta-blocklist ──► cscli decisions import ──► LAPI ──► bouncer (firewall)
 (SHA-256, conteggio) verifica · validazione            ▲              │
                    controllo capienza                  │ allowlist    ▼
                                            alert, decisioni, log ──► garitta-digest ──► email
                                          (crowdsec, fail2ban, nextcloud)
```

## Requisiti

| | Supportato |
|---|---|
| Sistema | Debian 11, 12, 13 · Ubuntu 20.04, 22.04, 24.04 (systemd) |
| CrowdSec | Security Engine con la Local API sulla stessa macchina. Consigliata la 1.6.8 o successiva (allowlist) |
| Pacchetti | `bash`, `curl`, `python3` ≥ 3.8 (solo libreria standard), `util-linux` |
| Facoltativi | `crowdsec-firewall-bouncer` (iptables/nftables), `ipset`, `fail2ban`, Nextcloud |

## Installazione

Dal pacchetto di una release:

```sh
sudo apt install ./garitta_0.1.0_all.deb
```

Dai sorgenti:

```sh
git clone https://github.com/n3xtgentechitalia/garitta.git && cd garitta
sudo ./install.sh                 # /usr/local/sbin, /etc/systemd/system, /etc/default/garitta-*
```

Per costruire il pacchetto: `make deb` (risultato in `dist/`).

## Avvio rapido

```sh
# report giornaliero, prima un'anteprima senza invio
sudo garitta-digest --dry-run --since 24h
sudo garitta set digest REPORT_LANG=it
sudo garitta enable digest --disable-realtime-email --now --to tu@example.org

# import Data-Shield (prima leggi "Condivisione con la Central API" più sotto)
sudo garitta enable blocklist --disable-custom-sharing --now

garitta status
```

Altri comandi: `garitta set <blocklist|digest> CHIAVE=VALORE`, `garitta disable blocklist [--purge]`,
`garitta disable digest [--restore]`. Per installare su altre macchine partendo dal checkout:
`./deploy.sh ssh root@host enable digest --now` (su Proxmox VE: `qm <vmid>`, `pct <ctid>`).

## Cosa cambia garitta in CrowdSec

garitta modifica CrowdSec solo se passi un'opzione esplicita. Ogni modifica viene stampata e si può
annullare:

| Opzione | Modifica | Per annullare |
|---|---|---|
| `enable blocklist --disable-custom-sharing` | `cscli console disable custom` | `cscli console enable custom` |
| `enable digest --disable-realtime-email` | commenta `- email_default` in `profiles.yaml` (backup in `/etc/crowdsec/.garitta-backup/`) | `garitta disable digest --restore` |
| `enable digest --move-parser-whitelists` | sposta nella cartella di backup le whitelist parser locali **interamente coperte** dalle allowlist della Local API | `garitta disable digest --restore` |

### Condivisione con la Central API

La Local API classifica come **custom** gli alert creati da `cscli decisions import` (origin
`cscli-import`, nessun hash di scenario). Se l'opzione console `custom` è attiva, come succede di
default dopo l'enroll, li invia alla Central API di CrowdSec con tutte le decisioni. Con questa
blocklist sono circa 110k IP di terzi a ogni import. Per questo `garitta enable blocklist` si ferma
se trova l'opzione attiva e ti chiede di scegliere. Dettagli e riferimenti al codice in
[docs/it/design-notes.md](docs/it/design-notes.md).

## Configurazione

`/etc/default/garitta-blocklist` e `/etc/default/garitta-digest`: ogni opzione è elencata, commentata,
con il suo valore di default. Le opzioni sono descritte in [docs/it/blocklist.md](docs/it/blocklist.md)
e [docs/it/digest.md](docs/it/digest.md). Per cambiare gli orari: `systemctl edit garitta-<componente>.timer`.

## Sviluppo

```sh
make test     # test shell e Python, senza root e senza CrowdSec (cscli è simulato)
make lint     # shellcheck + ruff
make deb
```

Vedi [CONTRIBUTING.md](CONTRIBUTING.md). Per i problemi di sicurezza segui [SECURITY.md](SECURITY.md).

## Crediti e licenza

- La blocklist Data-Shield IPv4 è curata da [duggytuxy](https://github.com/duggytuxy) e pubblicata
  sotto GPL-3.0. garitta la scarica al momento dell'uso e non la ridistribuisce. I falsi positivi
  vanno segnalati [ai curatori della lista](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist/issues).
- garitta è un progetto indipendente, non affiliato a CrowdSec né approvato da CrowdSec. CrowdSec è
  un marchio del rispettivo proprietario.
- garitta è distribuito con [licenza MIT](LICENSE).

## Autore

Ideato e mantenuto da **Alessio Giustini**, founder di [N3XTGENTECH](https://n3xtgentech.it)
([@n3xtgentechitalia](https://github.com/n3xtgentechitalia)).
