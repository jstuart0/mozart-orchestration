## INCIDENT pipeline

For responding to a **live outage** — service is down or badly degraded *right now*. This is the time-critical form of DIAGNOSE, and it deliberately **inverts DIAGNOSE's core rule**: you mitigate before you fully understand. Restore service first, root-cause second — often concurrently. mozart is the **incident commander (IC)**: it drives tempo, owns the mitigate-vs-wait decision, keeps the timeline, coordinates parallel responders, and calls the all-clear. No new agent — the responders are all reused (dick, hank, otto, xander, percy, scott).

**The whole shape exists to reconcile "time is of the essence" with "do it right" — by splitting rigor across two phases, not choosing one globally:**
- **Mitigation** runs with gates *relaxed* — you accept risk to restore service, and log it (`accepted-risk (incident)` in the change ledger, with a rollback command). Speed wins.
- **Durable fix** runs with gates *fully restored* — once service is back, the permanent fix goes through DELIVER or OPERATE with codex, ian, xander, and a repro-test-first default. Correctness wins.

You don't trade rigor for speed; you *sequence* them.

### The parallelism discipline (read this — it's the part that goes wrong)
**Read-only investigation parallelizes freely; live mutation serializes.** Investigators racing independent hypotheses can't hurt each other — fan them out. But *mutations* to a system that's already broken go through **one hand at a time** (hank), coordinated by the IC. Two responders applying conflicting live changes to a broken cluster is how a SEV2 becomes a SEV1. Fan out the readers; single-thread the writers. (Same "ops state lives in the cluster, not a state file" constraint as OPERATE — amplified, because the system is on fire.)

### SEV tiers (INCIDENT's tier axis — replaces TINY/STANDARD/HEAVY)
| SEV | When | Response |
|---|---|---|
| **SEV1** | Total outage, data-loss risk, security breach in progress, or broad customer impact | All hands. Mitigate immediately; every safe lever on the table. Mandatory post-mortem. Durable fix is HEAVY-tier by default |
| **SEV2** | Major degradation, partial outage, one critical flow down | Mitigate fast; parallel hypothesis fan-out; post-mortem expected |
| **SEV3** | Minor / contained / single-user / cosmetic-but-live | Degrades toward a fast DIAGNOSE → OPERATE; lightweight timeline, post-mortem optional |

When unsure between SEV levels: choose the higher one. Over-responding to a SEV3 costs minutes; under-responding to a SEV1 costs the business.

### 0. Declare + triage (seconds, not a full intake)
- **Severity**: assign SEV1/2/3 from observed impact (what's down, who's affected, since when)
- **Scope**: the affected system, blast radius, and the user-visible symptom in one line
- **Open the timeline** at `.mozart/incidents/active/<slug>.timeline.md` immediately — the first entry is the DECLARE line. This is the spine; every subsequent action appends to it
- **Observability gate**: check whether the repo's `CLAUDE.md` documents a monitoring/SLO stack (Prometheus/Grafana, alerting, dashboards). **If none is configured, surface it now**: "recovery cannot be measured objectively — the all-clear (stage 5) will be manual and subjective, and this incident may have gone undetected longer than it should." Recommend an **observability campaign as a post-incident follow-up**. Don't block the response on it — but name the gap in the timeline so the post-mortem carries it as an action item
- Create the state file (`Status: in-progress`, `Flow: INCIDENT-FULL` or `MITIGATE-ONLY`, SEV level) and flow sketch (Shape: INCIDENT) in `active/`. Resolve the ticket per the Ticket lifecycle (an incident always gets one — it's the durable human record)

### 1. Stabilize (mitigate) — runs concurrent with stage 2
- Identify the **fastest safe path to restore service**: roll back the last deploy, fail over, scale up, restart, flip a feature flag off, drain a bad node, shed load. Prefer the reversible lever
- **hank executes, single-threaded** (see the parallelism discipline). Under an active incident, restoring service can outrank a full snapshot — but hank still records the rollback command and tags the change `accepted-risk (incident)` in the change ledger. This is the *only* sanctioned relaxation of hank's "never mutate without a snapshot" rule, and only under a declared incident
- **Verify the mitigation empirically** — did the symptom actually clear? Append the observed result to the timeline. A mitigation that didn't help gets rolled back (its command is in the ledger) before the next lever is tried — don't stack unverified changes
- **One lever, one variable.** Each mitigation changes one variable and records its mutation manifest (see Operate-mode rules) in its timeline entry and change-ledger row, secret-bearing values `<redacted>`. Its read-back comparison runs, without blocking, once the symptom check clears, and no later than stage 3 Converge
- If the fastest safe mitigation is genuinely unknown, that's what stage 2 races to find — but a known-good rollback almost always exists and should be tried first

### 2. Race hypotheses (parallel) — runs concurrent with stage 1
- **Fan out investigators, one per hypothesis lane**, each read-only, each reporting findings to the timeline. Canonical lanes:
  - **what-changed** — recent deploys/merges/config changes correlated with the incident start (the highest-yield lane; most incidents are "something changed"). dick leads; correlate against the timeline's DECLARE timestamp
  - **dependency** — DB, upstream API, cache, auth provider, DNS, cert expiry
  - **resource** — OOM, disk/inode, connection-pool exhaustion, CPU throttle, PID pressure (otto)
  - **traffic / data** — load spike, retry storm, poison message, hot key
  - **security** — active attack, credential compromise, exfiltration (xander, if the shape smells like it)
  - **performance** — latency/throughput collapse under normal load (percy)
- Not every lane runs — pick by symptom. First-to-confirm wins; the IC (mozart) reads the lanes as they report and steers
- These are read-only and independent → run them as a **single parallel Task batch**

### 3. Converge — confirm root cause
- Synthesize the lanes; confirm the actual cause with evidence
- **Distinguish "mitigated" from "fixed."** The stage-1 mitigation likely masked the symptom without addressing the cause — say which is true. A rolled-back deploy restored service but the *bug* is still in the code
- If the mitigation fully and durably resolved it (e.g., a bad node drained and the workload is healthy elsewhere with no recurrence risk), the durable-fix stage may be a no-op — but say so explicitly

### 4. Durable fix — full gates restored
- Route the permanent fix to **DELIVER** (code fix) or **OPERATE** (config/infra fix) using the DELIVER-vs-OPERATE boundary test. This runs the *normal* pipeline with all gates — codex, ian, xander as applicable — because service is already restored and you can afford correctness now
- **Repro-test-first by default**: the incident is the ultimate regression. Write the failing test that reproduces the outage condition, watch it red, then fix (DELIVER with the TDD build-time flag). This is near-free and prevents recurrence
- If the user chose **MITIGATE-ONLY**, stop here: the durable fix is a tracked follow-up campaign, not part of this incident. Record it as an action item

### 5. Verify recovery — service-level, empirical
- Confirm service is *actually* back at the service level — error rate, latency (p95/p99), throughput, and SLO/SLA back to baseline; not "the pod is Running." Use the monitoring the observability gate found; if none, empirical checks (curl the real user flow, watch error logs) and say the all-clear is manual
- Only the IC calls the all-clear, and only against observed recovery — never "should be fine now." Append the ALL-CLEAR entry (with the evidence) to the timeline and downgrade/close the SEV

### 6. Post-mortem (blameless) — scott
- **scott** writes the blameless post-mortem to `.mozart/incidents/<slug>.postmortem.md` (and the external wiki if `## Documentation surfaces` is configured): the timeline, root cause, contributing factors, what detection/response worked and what didn't, and **action items**
- Each action item becomes a **follow-up campaign** (the durable fix if MITIGATE-ONLY, plus preventions: the missing alert, the guard that would have caught it, the observability gap from stage 0)
- **Escape linkage**: if the root cause traces to a commit shipped by a prior mozart campaign, record `Traces-to: <slug>` in the post-mortem and mirror it into that campaign's state-file `## Escapes` block. Real-world outages are the highest-signal escapes EVAL can measure — they're the defects every gate missed all the way to production
- Move the timeline, post-mortem, state file, and flow sketch from `active/` to `finished/`; set `Status: complete`

### Incident-mode rules
- **Mitigate first; understand second.** The inversion of DIAGNOSE. A known-good rollback beats a perfect diagnosis when service is down
- **One hand on the live system.** Investigation parallelizes; mitigation serializes through the IC. Never run concurrent live mutations during an incident
- **One variable per mitigation; verify it before the next.** Unverified changes on a broken system compound the confusion; roll back what didn't help. The read-back comparison against each mitigation's manifest runs once its symptom check clears and no later than stage 3 Converge — before a durable fix replaces the mitigation — never blocks, and a mismatch it finds becomes a post-mortem finding
- **Disputes wait for Converge.** The conductor-record dispute rule does not gate mitigation; its rows are written at stage 3 and are due by closeout
- **Mitigated ≠ fixed.** Always say which. The durable fix is not optional — it's deferred to full-rigor DELIVER/OPERATE, not skipped
- **The timeline is the source of truth.** Append at every state change. It's what makes the post-mortem honest and the resume-after-crash possible
- **Blameless post-mortem, always on SEV1/SEV2.** The output is action items, not attribution. Detection gaps and observability gaps are first-class findings
- **Don't over-declare.** A slow query with service still up is DIAGNOSE, not INCIDENT. The mitigate-first machinery is for actual outages; imposing it on a non-outage wastes the tempo and the all-clear ceremony

