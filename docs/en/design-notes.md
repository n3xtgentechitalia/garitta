# Design notes

Decisions behind garitta, with the evidence for each one. References are to CrowdSec **v1.8.1** and
to the Data-Shield documentation as reviewed in October 2026.

## 1. Importing with cscli, not a custom bouncer

A bouncer *enforces* decisions that already exist on the Local API. It cannot add new ones. To have
a third-party list enforced by every bouncer (firewall, nginx, AppSec...), the list must become Local
API decisions, and `cscli decisions import` is the supported way to do that.

The alternative is a separate ipset with its own firewall rule. It avoids the database and the
sharing issues below, but it is invisible to `cscli`, metrics and the console. It covers only the
firewall, and it needs its own rule-ordering and persistence logic. That is not what garitta does.

## 2. Central API sharing of imported decisions

`pkg/apiserver/apic.go`:

```go
func getScenarioTrustOfAlert(alert *models.Alert) string {
	scenarioTrust := "certified"
	if alert.ScenarioHash == nil || *alert.ScenarioHash == "" {
		scenarioTrust = "custom"
	} ...
	if len(alert.Decisions) > 0 {
		if *alert.Decisions[0].Origin == types.CscliOrigin {   // "cscli", not "cscli-import"
			scenarioTrust = "manual"
		}
	}
```

`cmd/crowdsec-cli/clidecision/import.go` creates the alert with `ScenarioHash: ""` and decisions with
origin `cscli-import`. The trust is therefore `custom`, not `manual`. `shouldShareAlert` shares
custom alerts when `ShareCustomScenarios` is on, and `alertToSignal` copies all decisions into the
signal. The official documentation states that custom/tainted alerts are pushed by default and that
custom signals do not count toward consensus. Disabling the `manual` option has no effect on
imports.

That is why `garitta enable blocklist` refuses to proceed with `custom` sharing on until the
operator chooses.

## 3. Allowlists are applied by cscli itself

`import.go` calls `Allowlists.CheckIfAllowlistedBulk` for every batch and excludes the matching
values, printing `Value X is allowlisted by Y`. The documentation table says the same: *"cscli:
decision is blocked unless special flag is provided"*. garitta therefore does not filter allowlisted
IPs itself. It only counts the lines cscli prints.

## 4. Overlapping imports are safe

`pkg/database/decisions.go` `QueryExpiredDecisionsSinceWithFilters` applies
`longestDecisionForScopeTypeValue`. A bouncer is told that an IP has expired only when its longest
decision has expired. A 36h decision refreshed every 24h therefore never produces a gap.

## 5. Database growth

`FlushAlerts` deletes alerts older than `flush.max_age` only if they have no active decision
(`alertWithoutActiveDecision`), and imports take the flush lock while they run. With daily imports
and the default 7d `max_age`, the database holds about 7–8 imports' worth of rows. That is why the
import runs daily rather than every two hours, Data-Shield's own refresh interval.

## 6. Verification follows Data-Shield guidance

The Data-Shield documentation asks integrators to fetch complete lists over verified HTTPS, check
the SHA-256 and the counts against the published snapshot, never apply a truncated list, check
capacity first, and leave the active policy unchanged when a check fails. garitta-blocklist does
each of these. `/data/latest.json` provides `sha256` and `blocked` for each profile.

## 7. Making avoided bans visible

Parser whitelists set `evt.Whitelisted` at the parser stage, so the event never reaches a bucket.
At most a debug line is logged. Local API allowlists act in `CreateAlert`
(`alert source %s is allowlisted by %s, skipping`), after the overflow has been logged at info level
(`Ip X performed 'scenario' ...`). The digest reads those overflow lines, which is why it can report
"ban avoided" only for allowlist-based setups.

## 8. No third-party Python dependencies

The digest uses only the standard library (Python ≥ 3.8). That keeps it installable on minimal
servers and on Debian 11 / Ubuntu 20.04 without pip. The CrowdSec email plugin configuration is a
flat YAML file, and a small dedicated reader is enough for it.
