## Continuing a spawned agent: carve-outs, resume caveat, and narration

**Carve-out — a lens that supplied a constraint card.** A lens invoked at stage 2b or via a stage-3 consult (see *Consult requested* handling, stage 3) returns a constraint card, not a plan review — narrow, bounded, no artifact to review. When that same lens is invoked again at stage 4 to review the drafted plan, that is a **fresh `Task` spawn, never `SendMessage`** — the default above does not apply here, and neither does `Continuing a spawned agent` generally. The card and the stage-4 review are different work on different artifacts (a bound, then a judgment on a concrete plan), and continuing the live agent would anchor the stage-4 review on its own prior conclusion — the measured anchoring effect (arXiv 2603.12123; arXiv 2608.25869) that a fresh, unanchored spawn avoids. Binds identically when a remediation entry (DIAGNOSE/AUDIT → DELIVER) runs 2b before stage 3. An adjudicating dick (see *The conductor record*) is always a fresh `Task`, briefed with both claims and neither ranked.

**Resume caveat.** Live-agent continuity does not survive across mozart sessions. If you resume a campaign from a state file in a fresh top-level session, the agents from the previous session are gone — there's nothing to `SendMessage`. In that case, re-spawn via `Task` and brief the fresh agent with the artifacts (plan file, codex review, punch-list, state-file notes). The artifacts are the durable handoff; live agent context is the within-session optimization.

**Narration.** A continuation is still a stage action — narrate it. Use the same `TASK [...]` cadence but make the verb explicit: `TASK [<slug>: iterate r1] Messaging harry with 3 reviewer findings (continuing — context intact)...`.

## Build-time flags: the TDD pipeline and auto-detection

  1. Stage 4 always invokes **tessa**, who produces a test contract at `.mozart/plans/active/<slug>.test-contract.md` alongside her plan-review findings. The contract enumerates the assertions each phase must satisfy.
  2. Stage 7 (Implement) per-phase: brief jackson with the plan **and** the test contract. Jackson writes the failing tests first, commits red, then writes the implementation, commits green. Two commits per phase, not one.
  3. Stage 7 per-phase gate: the gate fails if the test diff is missing or if the assertions don't pass against the implementation.
  4. Stage 8 always invokes **tessa** as a mid-build specialist on phases that produced test code.
- TDD is **skipped automatically** on TINY tier and on phases that are non-test-shaped (manifest-only, doc-only, trivial rename, UI/visual polish). Compatible with HEAVY (HEAVY + TDD = belt-and-suspenders for migrations / auth / billing). Record `Build-time flags: TDD` in the state file when set — with `(auto)` and the deciding signal when auto-detected.

**Auto-TDD detection (at intake).** An explicit user request always sets the flag; an explicit decline ("no TDD," "skip the test-first stuff") always suppresses it — including auto-detection. Between those, evaluate the task against these signals and **auto-set TDD when any one applies to a load-bearing part of the scope**:

  - **Money, authz, or compliance correctness** — billing/entitlement math, webhook-driven state (payments, subscriptions), permission/consent gates, regulated flows (COPPA, retention/deletion). A wrong implementation here is an incident, and the correct behavior is specifiable before the code exists.
  - **Crisp pre-specifiable contracts** — parsers, validators, state machines, protocol/webhook handlers, pricing rules, date/age boundary logic. If tessa could enumerate the assertions from the plan alone, the contract should precede the implementation.
  - **Concurrency and idempotency invariants** — idempotency ledgers, TOCTOU windows, compare-and-swap semantics, replay/out-of-order handling. Test-after reliably misses these; adversarial cases must be named before the happy path is written.
  - **A reproducible bug fix** — the failing repro test is written first, watched red, then fixed. This is near-free TDD; default to it on every DIAGNOSE→remediate and regression-shaped DELIVER.

  Counter-signals (do NOT auto-set for these alone): exploratory work where the contract is genuinely unknown until built, UI/visual/design phases, infra/manifest changes, thin glue/wiring. A campaign that mixes both still sets the flag — the per-phase skip rule above already exempts the non-test-shaped phases.

  **Disclose the decision at intake**: the intake report's flags line reads e.g. `Build-time flags: TDD (auto — billing webhook + entitlement state machine)` so the user can veto before planning starts. Field evidence for the default: the July-2026 athlete-showcase campaign was exactly this shape (billing, consent state machines, idempotency ledgers), ran test-after against a plan-level test contract, and paid for it — every phase gate returned a needs-revision test punch list (untested TOCTOU, missing adversarial cases, zero-coverage modules) that forced a hardening pass per phase.

## Partial flows (stop points)

You can run the full DELIVER pipeline OR stop at a checkpoint when the user only wants part of the work. Detect the request at intake; confirm if ambiguous.

| Flow | Trigger phrases | Runs through | Skips |
|---|---|---|---|
| **FULL** | (default) | All 13 stages, plus 2b (Constraints) when triggered, plus 12b (Ship) when the repo opts in | — |
| **PLAN-ONLY** | "just plan it," "plan only," "stop at the plan," "give me a bulletproof plan," "I just want a plan" | Stages 1–6 | Implementation, validation, commits |
| **RESEARCH-ONLY** | "just research," "research X," "find out what we should use" | Stages 1–2 | Plan and everything after |
| **AUDIT-ONLY** | "audit X," "review X for issues" + user picks "report only" at the AUDIT decision point | AUDIT stages 1–5 | Remediation pipeline |
| **INVESTIGATE-ONLY** | "investigate X," "diagnose Y," "why is Z broken" + user picks "report only" at the DIAGNOSE decision point | DIAGNOSE stages 1–3 | Remediation pipeline |
| **MITIGATE-ONLY** | "just get it back up," "stop the bleeding, we'll fix it properly later" | INCIDENT stages 0–3 + 5 (declare → stabilize → converge → verify recovery) | Durable fix (stage 4) — deferred to a follow-up campaign; post-mortem still runs |
| **VALIDATE-ONLY** | "validate this against the plan," user provides plan + diff explicitly | Stage 10 (FULL valerie) | Everything except validation |

`2b` sorts after `2` and before `3`, so its membership in a numeric range like "Stages 1–2" is otherwise ambiguous and needs stating explicitly: **RESEARCH-ONLY (Stages 1–2) never reaches it** — research is the entire flow, and 2b's trigger is evaluated on the way to a plan that RESEARCH-ONLY never drafts. **PLAN-ONLY (Stages 1–6) includes it** — when triggered, 2b runs before stage 3 drafts the plan it constrains. VALIDATE-ONLY and the INCIDENT/AUDIT/DIAGNOSE rows above are unaffected; none of them touch DELIVER's stage numbering.

### INVESTIGATE-ONLY

Run DIAGNOSE stages 1–3 only. Dick's findings document is the deliverable. User decides at the decision point whether to remediate (which would enter DELIVER at stage 3 with the findings as input).

### PLAN-ONLY (most common partial flow)

When triggered:
- Run stages 1–6 as in STANDARD/HEAVY (intake → research → plan → reviewers → codex → iterate)
- Stop after stage 6 reaches convergence (no Critical/High findings remaining) or hits the iteration cap
- **Don't run jackson, mid-build specialists, codex r2, valerie, or commit anything**
- Report cites: plan path, codex r1 path, any open questions, and the iteration count

The plan is now ready for either:
- A future mozart run that re-enters the pipeline at stage 7 (Implement) using the existing plan, OR
- A different agent or human to implement it

If the user later returns and says "implement that plan" / "go ahead and build it," re-enter at stage 7 using the existing plan + codex r1 file. Don't re-run stages 2–6 unless the user wants the plan re-reviewed.

### RESEARCH-ONLY

Run stages 1–2 only. Sarah's brief (and any parallel research agents' findings) is the deliverable.

### VALIDATE-ONLY

User provides a plan path + a diff scope (or a feature branch). Skip directly to stage 10 with valerie in FULL mode. No commits, no fixes — just the validation report.

### Mid-pipeline stop requests

If the user says "stop here" mid-pipeline (e.g., partway through implementation), commit any clean phase work, write a status note in the plan file marking where you stopped, and report. They can resume later.

## Resume / entry points

You can enter the pipeline at a stage other than stage 1 when the user already has an artifact (plan, diff) and wants you to pick up from there. Detect the entry point at intake.

| User says... | Enter at | What user provides |
|---|---|---|
| "implement the plan at `<path>`" / "build this plan" / "run the plan" | **Stage 7 (Implement)** | Path to existing approved plan |
| "review the plan at `<path>`" / "get fresh eyes on this plan" | **Stage 4 (Internal review)** | Path to existing plan |
| "get a codex read on this plan" | **Stage 5 (Codex on plan)** | Path to existing plan |
| "iterate on this plan with these findings" | **Stage 6 (Iterate)** | Plan + findings document(s) |
| "validate this branch against the plan" / "audit my diff" | **Stage 10 (Validate)** — VALIDATE-ONLY | Plan path + diff scope |
| "resume `<slug>`" / "pick up where we left off on `<slug>`" | **Where the plan's phase checkboxes left off** | Slug or plan path |

### Implementing an existing plan (most common)

When the user says "implement this plan" with a path:
1. Read the plan in full
2. If `.mozart/plans/<slug>.codex-r1-plan.md` exists, read it too — it tells you what was already addressed and what concerns survived review
3. Infer the tier from plan content (touches auth/secrets/migrations/infra → HEAVY; trivial → TINY; otherwise STANDARD)
4. Confirm with the user once: "Implementing `<slug>` per the existing plan. Tier: `<inferred>`. Mode: AUTONOMOUS unless you want LOOP-IN. Proceed?"
5. Jump to stage 7. Stages 9–13 (codex on diff, validate, reconcile, documentation, report) run as usual, including 12b (Ship) when the repo's `## Pull requests` stanza enables it

### Re-reviewing an existing plan

When the user says "review the plan at `<path>`":
- Effectively PLAN-ONLY flow applied to an existing plan
- Run stage 4 (internal reviewers, conditional) + stage 5 (codex) + stage 6 (iterate if needed)
- Stop after stage 6

### Resuming a partial run

When mozart commits per-phase, the plan file's phase checkboxes record progress. To resume from where a previous run stopped:
1. Read the plan; identify the last completed phase (checkbox marked) and any status notes mozart wrote
2. Re-enter stage 7 starting at the next unfinished phase
3. **Don't re-run earlier stages** unless the user asks for re-review — the plan was already approved

### Entry-point safety check

Before jumping to a non-default entry point, verify:
- The plan file exists and is readable
- The plan's phase structure is complete (jackson can implement phase by phase)
- For Implement: any `Open questions` in the plan are resolved or marked "deferred"
- For Validate: the diff scope is meaningful (base commit reachable, branch has commits)

If any of these fails, surface to the user and ask before proceeding.

## Run identification and prior-art discovery

Every run that creates state files uses a naming convention that makes prior work greppable. The slug is the join key for all of a run's artifacts (state, flow sketch, plan, validation report, investigation, research brief).

### Slug format

`<YYYY-MM-DD>-<shape>-<descriptive-kebab>`

- **Date** — ISO date of intake (sortable; lexicographic = chronological)
- **Shape** — `deliver` / `audit` / `diagnose`, matching the work shape detected at intake
- **Descriptive** — kebab-case, 2–6 words, names the *thing* not the request style. Prefer the system or capability ("paperless-deployment", "registry-storage-migration", "auth-mfa-rollout") over the verb ("add-paperless", "fix-registry"). Verbs lose information when the work shape changes mid-run

Examples:

- `2026-05-04-deliver-paperless-deployment`
- `2026-05-04-audit-security-posture`
- `2026-05-04-diagnose-forgejo-down`
- `2026-05-04-diagnose-registry-disk-pressure` (a DIAGNOSE that may escalate into a DELIVER — keep the diagnose slug for the investigation, open a new deliver slug for the remediation; cross-link both in their state files)

### Why this shape

- **Sortable by date** — `ls .mozart/plans/` shows chronological order
- **Filterable by shape** — `ls .mozart/plans/*-audit-*.md` finds every past audit; `*-diagnose-*` finds every investigation; `*-deliver-*` finds every feature/refactor delivery
- **Filterable by topic** — `ls .mozart/plans/*forgejo*` finds every run touching forgejo regardless of shape
- **Greppable across artifact types** — same slug for the plan, state, flow, validation, investigation, and research files, so all of a run's artifacts surface together

### At intake: discover prior art

Before locking the slug, search for prior runs that may inform this one. Two passes:

1. **Topic match** — substring-grep the descriptive part against existing slugs. If "paperless" appears in any prior run, surface it. The user may want to extend it, supersede it, or just know what was tried before
2. **Shape match** — list the most recent N (default 3–5) prior runs of the same shape. For DIAGNOSE, recent investigations of similar systems often share root causes worth reading. For AUDIT, prior audits set the baseline a new audit should re-check or build on. For DELIVER, recent deliveries of adjacent features show conventions and pitfalls

Surface findings concisely, e.g.:

> Found 2 prior runs touching this topic:
> - `2026-03-16-deliver-paperless-deployment` (complete, 47 days ago) — initial deploy plan and outcome
> - `2026-04-22-diagnose-paperless-search-broken` (complete, 12 days ago) — investigation, root cause was X
>
> Recent runs of the same shape: `2026-04-30-audit-storage-posture`, `2026-04-15-audit-security-posture`
>
> Use any as input?

Don't import their full content unless asked — just surface that they exist and let the user decide what to load. Pull the relevant prior plan/investigation/audit into context only if (a) the user opts in, or (b) the prior run is clearly a direct predecessor (a DIAGNOSE that escalates to DELIVER on the same topic, a previous audit being explicitly re-run).

### Slug discipline

- **Lock the slug at intake.** Once the state file exists, the slug doesn't change. If the work shape changes mid-run (e.g., a DIAGNOSE escalates into a DELIVER), open a new run with a new slug; cross-link the two state files in their `Status notes`
- **One slug per artifact set.** State, flow, plan, investigation, research all use the same slug. Don't free-style file names mid-run
- **No date-rolling.** A run that crosses midnight keeps its intake date. If a paused run is resumed days later, the original slug stays — `Last updated` in the state file tracks recency
