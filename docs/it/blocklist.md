# garitta-blocklist

Importa la [blocklist Data-Shield IPv4](https://github.com/duggytuxy/Data-Shield_IPv4_Blocklist) in
CrowdSec come decisioni `ban`. Le applicano i bouncer già registrati sulla Local API.

## Come funziona un'esecuzione

1. **Metadati.** Scarica `https://data-shield.eu/data/latest.json`, che contiene SHA-256 e numero di
   voci di ogni profilo.
2. **Download.** Scarica la lista dalla pubblicazione primaria (raw GitHub). Se lo SHA-256 non
   coincide prova GitLab, Codeberg e jsDelivr. Il sito aggiorna i metadati ogni ora, quindi possono
   essere in ritardo su una nuova pubblicazione: in quel caso l'esecuzione aspetta `RETRY_WAIT`
   secondi e riprova, fino a `RETRIES` volte. Senza una copia verificata non importa nulla
   (`REQUIRE_SHA=yes`).
3. **Validazione.** Richiede un IPv4 canonico per riga, nessun duplicato e un conteggio uguale ai
   metadati. Una sola riga non valida blocca l'intera lista.
4. **Capienza.** Con il firewall bouncer in modalità iptables/ipset, ogni origine ha un ipset con
   `maxelem` fisso (131072 di default). Con `MAX=auto` la lista deve stare nel 95% di quel valore.
5. **Import.** `cscli decisions import --format values --type ban --duration 36h --reason data-shield-<profilo>`.
   cscli controlla le allowlist della Local API (CrowdSec ≥ 1.6.8) e scarta gli IP che ci sono dentro.
6. **Stato.** Scrive l'esito in `/var/lib/garitta/blocklist/status` e conserva lì accanto l'ultima
   lista importata.

L'esecuzione termina con errore ogni volta che salta un import, così il problema si vede in
`systemctl --failed` e nel report giornaliero.

## Perché durata 36h con esecuzione giornaliera

- Se un'esecuzione fallisce, la protezione resta attiva.
- Gli IP tolti dalla lista scadono da soli.
- Import sovrapposti non sbloccano nulla: la Local API comunica ai bouncer la scadenza di un IP solo
  quando scade la sua decisione più lunga (`longestDecisionForScopeTypeValue`).
- Gli alert scaduti vengono eliminati da `db_config.flush.max_age` (7 giorni di default). A regime il
  database contiene circa 7–8 import (~800k righe per il profilo standard).

Data-Shield rigenera la lista ogni due ore, ma per un'integrazione basata sull'import quella
giornaliera è il compromesso giusto: ogni import aggiunge una copia completa al database di CrowdSec.

## Configurazione (`/etc/default/garitta-blocklist`)

| Opzione | Default | Significato |
|---|---|---|
| `PROFILE` | `standard` | `standard` oppure `critical` (più ampia). Le due liste restano separate. |
| `DURATION` | `36h` | Durata delle decisioni. Tenerla più lunga dell'intervallo del timer. |
| `MAX` | `auto` | Numero massimo di voci. `auto` = 95% del `maxelem` degli ipset di CrowdSec, altrimenti 250000. |
| `MIN` | `20000` | Sotto questa soglia il download viene considerato troncato. |
| `REQUIRE_SHA` | `yes` | `no` = se la verifica fallisce importa comunque la copia scaricata (solo controlli di formato). |
| `RETRIES` / `RETRY_WAIT` | `3` / `600` | Tentativi di verifica e pausa tra un tentativo e l'altro, in secondi. |
| `BATCH` | `20000` | Decisioni per ogni richiesta alla Local API. |
| `METADATA_URL`, `MIRRORS` | data-shield.eu, 4 mirror | Da cambiare per usare un mirror interno. `{file}` sta per il nome del file della lista. |

## Attivazione

```sh
sudo garitta-blocklist --dry-run                       # solo download e verifica
sudo garitta enable blocklist --disable-custom-sharing --now
```

`garitta enable blocklist` controlla la Local API, i bouncer, il supporto alle allowlist e l'opzione
di condivisione della console. Se la condivisione `custom` è attiva si ferma finché non scegli:

- `--disable-custom-sharing` esegue `cscli console disable custom`. Smettono di essere condivisi anche
  gli alert dei tuoi scenari locali o modificati. Gli scenari ufficiali dell'Hub e la community
  blocklist non cambiano.
- `--accept-custom-sharing` lascia la condivisione attiva: ogni import viene inviato alla Central API.

## Verifiche

```sh
garitta status
journalctl -u garitta-blocklist -n 30
cscli decisions list --origin cscli-import --scenario data-shield-standard --limit 0 -o raw | wc -l
ipset list -t | grep -E 'Name|entries'
```

## Rimozione

`sudo garitta disable blocklist` ferma il timer e le decisioni scadono entro `DURATION`. Con `--purge`
vengono cancellate subito insieme allo stato.
