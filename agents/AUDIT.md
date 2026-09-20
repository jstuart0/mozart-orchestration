## AUDIT pipeline

### 1. Intake
- Restate the audit goal in one sentence (open-ended / best-practices / security / UX / a11y / performance / code-health / infra)
- Identify subject (codebase / deployed-site URL / hybrid) and scope boundary
- Decide audit report path (`.mozart/audits/<slug>.md`)
- Ask upfront: **report only, or report-then-remediate?**
- Create the state file and the **flow sketch** in `active/` (`.mozart/plans/active/<slug>.state.md`, `.mozart/plans/active/<slug>.flow.md`) — Shape: AUDIT. Update the flow sketch as each specialist runs. See *Directory convention* in the State persistence section.

### 2. Discovery
- Codebase: structure, language/framework, recent churn (`git log --since='3 months ago' --stat | head`), test posture
- Deployed site: fetch landing + 2-3 key flows; note tech, auth surface, public endpoints
- Capture as "Subject summary" at the top of the audit report

### 3. Audit (parallel fan-out)

Pick specialists by goal:

| Goal | Lead | Support |
|---|---|---|
| Open-ended review | bob, dexter, xander, ruby (+ otto if infra in scope, + nina if a cloud surface or a provider-behaviour claim is in scope) | librarian if duplication suspected, scott if doc-freshness in scope |
| Best-practices refactor | dexter, bob | librarian (duplicate functionality is a top refactor target), xander/ruby/otto if relevant |
| Security audit | xander | bob, dexter |
| UX / accessibility | ruby | xander if auth flows |
| Performance / scaling | percy | bob (structure), dexter (code-health) |
| Code-health / tech debt | dexter, librarian | bob |
| Infra / k8s posture | otto | bob, xander |
| Cloud posture / cloud-semantics | nina | otto, xander |
| Duplication / parallel implementations | librarian | dexter |
| Documentation freshness (README, CHANGELOG, wiki staleness) | scott | dexter if doc duplication, bob if architectural docs are wrong |

Brief each: goal (verbatim), subject + scope, audit report path, their lens.

For deployed-site audits without source: only invoke ruby + xander + nina (they have WebFetch).

### 4. Synthesize

You consolidate into the audit report:
- Deduplicate findings across specialists
- Re-rank with unified severity (Critical/High/Medium/Low) and effort (S/M/L)
- Cluster by theme
- Identify hotspots (files/modules/pages in multiple findings)
- Surface tensions (specialist disagreements)

### 5. Decision point

Present the report; ask: **report only, or remediate?**

- **Report only**: pipeline ends. Set `Status: complete` and **move the state file and flow sketch** from `active/` to `finished/` (per the *Directory convention*). Move the audit synthesis from `audits/active/<slug>.md` to `audits/finished/<slug>.md` in the same operation.
- **Remediate**: confirm scope (Critical+High? specific themes? hotspots? user-chosen subset?). Hand the filtered audit to harry as the brief — you're now in DELIVER **at stage 3 (Plan)**, with the audit serving as research input. Stage 2 is skipped. The artifacts stay `active-` — the campaign continues; promotion to `finished-` happens at the DELIVER report stage.

The final report references both the audit doc and the plan doc.

### RE-AUDIT (delta audits)

When a prior audit of the same scope exists (intake's prior-art discovery surfaces it from `.mozart/audits/`), don't re-run the full fan-out blind. Scope the specialists to (a) the diff since the prior audit's base commit and (b) verification that the prior findings were actually remediated — briefing each with the prior audit doc (and its findings manifest, if one exists) as the baseline. Reserve a full re-fan-out for when the codebase has changed broadly or the prior audit is months stale. The observed waste: six full five-specialist HEAVY audits on the same repo in nine days — from run three onward the findings were single-digit, and the final run's own report described its Highs as "parity gaps from the remediation itself." Delta-scoped runs find those at a fraction of the cost.

### Audit-mode rules
- No goal → push for one. No scope → push for one. "Review this" is too broad.
- Don't audit and fix in the same pass. Remediation is its own DELIVER.
- For deployed-site-only audits, source-readers (dexter, bob) won't have anything to read. Don't invoke them.
- Synthesis is your job; don't outsource it back to a specialist.

