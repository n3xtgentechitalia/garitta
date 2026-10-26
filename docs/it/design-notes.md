# Note di progetto

Le scelte alla base di garitta, ognuna con la sua motivazione. I riferimenti sono a CrowdSec
**v1.8.1** e alla documentazione Data-Shield come consultata a ottobre 2026.

## 1. Import con cscli invece di un bouncer dedicato

Un bouncer *applica* decisioni che esistono già sulla Local API, non può crearne di nuove. Perché una
lista di terzi venga applicata da tutti i bouncer (firewall, nginx, AppSec...) deve diventare un
insieme di decisioni della Local API, e il modo supportato per farlo è `cscli decisions import`.

L'alternativa è un ipset separato con una regola firewall propria. Evita i problemi di database e di
condivisione descritti sotto, ma è invisibile a `cscli`, alle metriche e alla console, copre solo il
firewall e richiede una gestione propria dell'ordine delle regole e della persistenza. Non è
l'approccio di garitta.

## 2. Condivisione delle decisioni importate con la Central API

`pkg/apiserver/apic.go`:

```go
func getScenarioTrustOfAlert(alert *models.Alert) string {
	scenarioTrust := "certified"
	if alert.ScenarioHash == nil || *alert.ScenarioHash == "" {
		scenarioTrust = "custom"
	} ...
	if len(alert.Decisions) > 0 {
		if *alert.Decisions[0].Origin == types.CscliOrigin {   // "cscli", non "cscli-import"
			scenarioTrust = "manual"
		}
	}
```

`cmd/crowdsec-cli/clidecision/import.go` crea l'alert con `ScenarioHash: ""` e decisioni con origin
`cscli-import`. La classificazione è quindi `custom`, non `manual`. `shouldShareAlert` condivide gli
alert custom quando `ShareCustomScenarios` è attivo, e `alertToSignal` copia nel segnale tutte le
decisioni. La documentazione ufficiale dice che gli alert custom/tainted vengono inviati di default e
che i segnali custom non contano per il consenso. Disattivare l'opzione `manual` non ha effetto
sugli import.

Per questo `garitta enable blocklist` non procede con la condivisione `custom` attiva finché
l'operatore non sceglie.

## 3. Le allowlist le applica cscli

`import.go` chiama `Allowlists.CheckIfAllowlistedBulk` per ogni blocco, esclude i valori trovati e
stampa `Value X is allowlisted by Y`. La tabella della documentazione dice lo stesso: *"cscli:
decision is blocked unless special flag is provided"*. garitta quindi non filtra da sé gli IP in
allowlist: si limita a contare le righe stampate da cscli.

## 4. Gli import sovrapposti sono sicuri

`QueryExpiredDecisionsSinceWithFilters`, in `pkg/database/decisions.go`, applica
`longestDecisionForScopeTypeValue`: un bouncer viene informato della scadenza di un IP solo quando
scade la sua decisione più lunga. Una decisione di 36h rinnovata ogni 24h quindi non lascia mai buchi.

## 5. Crescita del database

`FlushAlerts` elimina gli alert più vecchi di `flush.max_age` solo se non hanno decisioni attive
(`alertWithoutActiveDecision`), e durante un import il flush viene sospeso. Con import giornalieri e
`max_age` di 7 giorni (default), il database contiene circa 7–8 import. Per questo l'import è
giornaliero e non ogni due ore, come l'aggiornamento di Data-Shield.

## 6. Verifica secondo le indicazioni di Data-Shield

La documentazione Data-Shield chiede di scaricare liste complete su HTTPS verificato, controllare
SHA-256 e conteggi rispetto allo snapshot pubblicato, non applicare mai una lista troncata,
controllare prima la capienza e lasciare invariata la politica attiva quando un controllo fallisce.
garitta-blocklist fa tutte queste cose. `/data/latest.json` fornisce `sha256` e `blocked` per ogni
profilo.

## 7. Rendere visibili i ban evitati

Le whitelist parser impostano `evt.Whitelisted` già nella fase di parsing, quindi l'evento non arriva
mai a un bucket e al massimo resta una riga di debug. Le allowlist della Local API intervengono in
`CreateAlert` (`alert source %s is allowlisted by %s, skipping`), dopo che l'overflow è stato
registrato a livello info (`Ip X performed 'scenario' ...`). Il report legge queste righe di overflow:
per questo può segnalare i "ban evitati" solo con le allowlist.

## 8. Nessuna dipendenza Python esterna

Il report usa solo la libreria standard (Python ≥ 3.8), così si installa su server minimali e su
Debian 11 / Ubuntu 20.04 senza pip. La configurazione del plugin email di CrowdSec è un YAML piatto,
e per leggerla basta un piccolo lettore dedicato.
