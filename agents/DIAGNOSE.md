## DIAGNOSE pipeline

For investigating a specific failure (bug, regression, test failure, performance issue, unexpected behavior). Produces a findings document and a ticket; optionally flows into DELIVER for remediation.

### 1. Intake
- Restate the failure in one sentence — what's broken, where, who noticed
- Capture user-supplied evidence: error messages, stack traces, logs, repro steps, screenshots, alert text
- Identify subject: which system, which feature, which environment (prod / staging / local), which version
- Decide investigation slug; investigation home: `.mozart/investigations/<slug>.md`
- Note severity if user provided it; otherwise dick assigns from observed impact
- **Ask: report only (INVESTIGATE-ONLY), or report-then-remediate?** If unclear, default to "investigate first, decide after findings"
- Create state file at `.mozart/plans/active/<slug>.state.md` (per the *Directory convention*) with `Status: in-progress`, `Flow: INVESTIGATE-ONLY` (or FULL if remediation already committed), and `Investigation: <path>` populated. The investigation doc itself lives at `.mozart/investigations/active/<slug>.md`
- Create the **flow sketch** at `.mozart/plans/active/<slug>.flow.md` — Shape: DIAGNOSE. The diagram is short for INVESTIGATE-ONLY runs (intake → dick → decision) and grows if the run flows into DELIVER for remediation.

### 2. Investigate (dick)
- Brief dick with: failure description, scope, all user-supplied evidence, the investigation path, and the active ticket lifecycle (he creates the ticket — see Ticket lifecycle section)
- Dick produces the findings doc and creates the ticket in `Investigating` state
- If dick declines (cause already known and stated by user; task is fix-shaped not investigation-shaped), surface that and offer to enter DELIVER directly with the user's stated cause as input

### 3. Decision point
- Present dick's findings inline (severity, root cause one-liner, top remediation option) plus the ticket link and the path to the full investigation doc
- Ask: **report only, or remediate?**
  - **Report only**: pipeline ends. Ticket stays in `Investigating` (or transitions to `Won't Fix` if user explicitly chooses not to fix). Set `Status: complete` and **move the state file and flow sketch** from `active/` to `finished/` (per the *Directory convention*). Move the investigation doc from `investigations/active/<slug>.md` to `investigations/finished/<slug>.md` in the same operation.
  - **Remediate**: confirm which remediation option from dick's findings. Enter DELIVER **at stage 3 (Plan)** with the findings as harry's brief — stage 2 (Research) is typically skipped because dick already did the research. The same ticket continues, transitioning from `Investigating` → `Planned` when harry's plan is ready. The artifacts stay `active-` — the campaign continues; promotion to `finished-` happens at the DELIVER report stage.
- If dick's findings reveal the issue is genuinely security-shaped (xander), infra-shaped (otto), cloud-shaped — a provider behaving other than the claim about it says (nina) — or architecture-shaped (bob), surface that and offer to route to the specialist before remediation. Ticket transitions accordingly.
- **If the fix is a live-system change (not a code change)** — a bad ConfigMap on the running cluster, a failed rollout to re-apply, a package to install, a setting to flip on a host — remediation routes to **OPERATE at stage 3 (Change plan)**, not DELIVER. dick's findings become otto's brief for the change plan. Use the DELIVER-vs-OPERATE boundary test: fix lands via a git/CI/Argo pipeline → DELIVER; fix lands straight on the running system → OPERATE.

### Diagnose-mode rules
- **No reproducible failure → don't fake it.** Dick documents that explicitly. Recommend instrumentation/logging as a remediation option; that's a valid next step.
- **Don't diagnose and fix in the same pass.** Investigation → decision point → remediation are distinct phases. The decision point is where the user steers.
- **Time-box honesty.** Dick's findings note what was NOT investigated. The ticket reflects that same honesty.
- **One ticket per investigation.** If the investigation reveals multiple distinct issues, dick documents them in the findings but creates separate tickets per actionable issue.
- **HEAVY-tier failures get full DIAGNOSE.** Production incidents, data-loss-shaped bugs, security-relevant failures — never short-cut to "I bet I know what it is."
- **Record escape linkage.** When dick's root cause traces to a commit shipped by a prior mozart campaign (the slug is in the commit message), the investigation doc records `Traces-to: <originating-slug>` — and mozart adds the matching line to the originating campaign's state-file `## Escapes` block if that state file is reachable. This is the denominator of the pipeline's defect-removal efficiency; without it, escaped defects are invisible to EVAL and the gates look better than they are.

