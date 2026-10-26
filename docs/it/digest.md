# garitta-digest

Un'email al giorno con i ban del periodo, invece di una notifica CrowdSec per ogni ban.

## Struttura del report

1. **IP in whitelist coinvolti.** Riquadro rosso (verde se non c'è nulla), una riga per IP con la
   voce di whitelist che lo copre:
   - **BANNATO**: un IP in whitelist ha comunque un ban (CrowdSec, cscli o fail2ban). È il caso più
     grave e compare anche nell'oggetto (`[!! N IP whitelist BANNATI]`).
   - **CrowdSec: ban evitato**: uno scenario è scattato e l'allowlist ha scartato l'alert.
   - **fail2ban: ignorato**: fail2ban ha scartato l'IP per `ignoreip`.
   - **Nextcloud: login fallito**, con il nome utente. Di solito è una password vecchia salvata su un
     dispositivo di una sede.
2. **Ban applicati.** Una riga per IP: paese, AS, motivi (scenari CrowdSec e jail fail2ban, con
   conteggio), scadenza e link alla CTI di CrowdSec.
3. **Stato.** Decisioni attive per origine (CAPI, lists, cscli-import...), ultimo import Data-Shield e
   login Nextcloud falliti.

Il periodo parte dall'ultimo invio riuscito (massimo 7 giorni; 24h per il primo report). Il report
viene inviato anche quando non c'è nulla da segnalare, così il suo arrivo conferma che il servizio
funziona. L'email ha una parte HTML e una in testo semplice, e il report è disponibile in italiano o
in inglese (`REPORT_LANG`).

## Fonti dei dati

| Fonte | Usata per |
|---|---|
| `cscli alerts list --origin crowdsec` / `--origin cscli` | ban degli scenari e ban manuali |
| `crowdsec.log` (anche i file ruotati) | overflow `Ip X performed 'scenario'` da IP in whitelist |
| `fail2ban.log*` | righe `Ban` e `Ignore ... by ip` |
| `nextcloud.log*` | righe `Login failed` (entrambi i formati) |
| `cscli allowlists` + whitelist parser locali | cosa conta come IP in whitelist |
| `cscli decisions list -a` | contatori per origine |

Server SMTP, credenziali, mittente e destinatari vengono letti dal plugin email di CrowdSec
(`/etc/crowdsec/notifications/email.yaml`). Se le notifiche email di CrowdSec funzionano, funziona
anche il report. Cifratura: `ssltls`, `starttls` o `none`.

## Whitelist parser e allowlist

Una **whitelist parser** locale (un file in `parsers/s02-enrich/` con `whitelist: ip: [...]`) scarta
gli eventi *prima* che gli scenari li vedano, quindi un ban evitato non lascia traccia.
Un'**allowlist della Local API** (`cscli allowlists`, CrowdSec ≥ 1.6.8) scarta l'alert *dopo* che lo
scenario è scattato e lo registra nel log. CrowdSec consiglia le allowlist per le regole basate su IP,
e valgono anche per le blocklist e per `cscli decisions add/import`.

`garitta-digest --check-parser-whitelists` elenca le whitelist parser locali e dice se le allowlist
le coprono. `garitta enable digest --move-parser-whitelists` sposta solo quelle **interamente coperte**
(stessi IP/range, senza `expression`) in `/etc/crowdsec/.garitta-backup/parsers/`. La protezione resta
identica e i ban evitati iniziano a comparire nel report.

## Configurazione (`/etc/default/garitta-digest`)

| Opzione | Default | Significato |
|---|---|---|
| `REPORT_LANG` | `en` | `en` oppure `it` |
| `SMTP_CONF` | `/etc/crowdsec/notifications/email.yaml` | Configurazione del plugin email di CrowdSec |
| `MAIL_TO` | *(vuoto)* | Destinatari separati da virgola; vuoto = `receiver_emails` |
| `SUBJECT` | *(vuoto)* | Prefisso dell'oggetto; vuoto = `email_subject` |
| `REPORT_NAME` | *(vuoto)* | Nome del server nel report; vuoto = FQDN |
| `FAIL2BAN_LOG` | `/var/log/fail2ban.log` | Vuoto = ignora fail2ban |
| `NEXTCLOUD_LOG` | `auto` | `auto` = `/var/www/nextcloud/data/nextcloud.log` se esiste; vuoto = ignora |
| `MAX_ROWS` | `300` | Numero massimo di righe nella tabella dei ban |

## Attivazione

```sh
sudo garitta-digest --dry-run --since 24h      # anteprima in /var/lib/garitta/digest/preview.html
sudo garitta set digest REPORT_LANG=it "SUBJECT=Il mio sito - CrowdSec"
sudo garitta enable digest --disable-realtime-email --move-parser-whitelists --now --to tu@example.org
```

`--disable-realtime-email` commenta `- email_default` in `/etc/crowdsec/profiles.yaml` e ne salva una
copia. Le altre notifiche, per esempio Slack, restano attive. Il report parte ogni giorno alle 07:00
(`systemctl edit garitta-digest.timer`).

## Rimozione

`sudo garitta disable digest --restore` ferma il timer, riattiva le email in tempo reale e rimette a
posto le whitelist parser spostate.
