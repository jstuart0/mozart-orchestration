## DELIVER pipeline

### 2. Research (sarah, optional — and parallel)

Skip in TINY. In STANDARD/HEAVY, run when:
- Unfamiliar domain, library, or pattern decision
- "Best practices" or "modern way to X" framing
- Multiple plausible approaches and the right one isn't obvious
- User explicitly asked for research

**Researchers run in parallel.** Dispatch in a single message with multiple Task calls:
- **sarah** — primary; surveys codebase prior art + scans web + synthesizes the brief
- **codebase-pattern-finder** — when in-repo examples matter
- **web-search-researcher** — when an external sub-question deserves its own thread

Sarah herself parallelizes her internal tool calls (codebase scan + web search in one batch). She writes the brief to `.mozart/research/<slug>.md` and returns a summary, uniformly — small and substantial jobs alike.

### 2b. Constraints (conditional — narrow)

Runs when the task statement itself trips one of two conditions, evaluated **once, at intake** — never re-derived mid-plan:

1. The task changes **who may do what** — an authorization rule, trust boundary, privilege level, credential path, or the identity an action runs as → **xander**.
2. The task changes behavior covered by a guarantee **already published in this repo** — README / PRIVACY / SECURITY / API docs / CHANGELOG — that the change could falsify → **ian**.

**This is a deliberate narrowing of xander's stage-4 trigger (`### 4. Internal review`, below) and stage-8 trigger (`### 8. Mid-build specialists`)** — both of those also fire on dependency bumps and CI/CD workflow edits, neither of which produces a task-derivable authorization rule. Reusing either table here would turn "no cost when untriggered" into "a cost on most campaigns." If a condition fires, spawn the named lens — xander or ian **only**, narrower than the four-lens pull route in harry's `## Consult requested` (unprompted push must stay rare) — with a **fresh `Task`**: the task statement, nothing else.

**Accepted limitation**: this trigger cannot see a trust boundary that emerges only from an implementation choice made later — that's stage 4's and stage 8's job, not 2b's. Stated as an acceptance, not an omission.

**Returns a constraint card, not a review** — the identical bound the stage-3 consult route's card carries (see stage 3's `## Consult requested` handling, below, for the full spec: `must`/`must-not` bullets, **falsifiable** against something that exists independently of this campaign, no design recommendations, no severities, and the same send-back-once / second-over-run remedy). **2b adds one clause of its own, load-bearing for the boundary dexter's adversarial test checks**: no artifact to review. 2b never sees a plan or a diff, which is what keeps it from degrading into "stage 4, earlier" — a distinction the stage-3 route doesn't need, since a consult can reference a plan already in progress and 2b structurally cannot.

Persist the card to `.mozart/plans/active/<slug>.constraints.md` (append-only, `## <lens> — 2b` per card) and record the path in the state file's `Paths: Constraints` line — the same artifact and mechanism a stage-3 consult uses (see `## Consult requested` handling, stage 3, below). A lens that supplied a 2b card is invoked again at stage 4 by a **fresh `Task`, never `SendMessage`** — see *Continuing a spawned agent vs re-spawning fresh* for the carve-out and its citations.

**On a remediation entry** (AUDIT → remediate, DIAGNOSE → remediate — both enter DELIVER at stage 3, skipping stage 2): evaluate the trigger against the audit or investigation findings, which are exactly the evidence that makes it evaluable. If it fires, run 2b before stage 3; if not, the entry stays at stage 3.

**Skip form**: when neither condition fires, `[-] 2b. Constraints — skipped: no trigger` — never leave it bare `[ ]`.

**The untriggered cost, exactly — four touches, every one an existing mandatory-template field populated with its default, none of them a new document**: one state-file `## Stage progress` row (the skip form above); one flow-sketch `## Stage trace` line (`Stage 2b (Constraints): skipped — no trigger`); one state-file `Paths: Constraints` line, reading `n/a` the same way `Investigation: n/a` already reads on a non-bug-shaped campaign; and one clause in the intake rationale (`2b trigger: none — <reason>`), the same paragraph that already names which conditional specialists were and weren't anticipated. Nothing beyond those four: no `## Deviations from proposed` entry (the intake checklist records the trigger outcome before any agent runs, so a later "still not triggered" is what was proposed, not a divergence from it), no diagram node in either the Proposed or Actual flow (an unanticipated, untriggered stage was never drawn), no `## Findings ledger` row (nothing was raised), no `.mozart/plans/active/<slug>.constraints.md` file (no card to persist), no ticket transition.

### 3. Plan (harry)
- Brief harry: task, research brief (if any), the **absolute** plan path to write to, the worktree path + campaign branch, context
- Harry reads code, drafts the plan (template includes `Documentation to update` and `Pattern parity / wiring sites`)
- **Wiring-sites discipline**: when the plan introduces or extends a pattern (transport wrapper, auth/role gate, structured-error envelope, ARIA attribute set, healthcheck argument, NetworkPolicy shape, securityContext stanza, parity field across Helm/kustomize/compose, etc.), harry must enumerate every existing site that needs the pattern — not just the site being changed. The grep that produced the list is documented in the plan so downstream reviewers and jackson can re-run it. This is the lens that distinguishes "this diff is correct" from "this pattern is consistent across the codebase." Per-commit reviewers see the diff; only the wiring-sites enumeration in the plan makes the population visible to them. **Before reviewing harry's wiring-sites enumeration** — read `agents/mozart.md` (*Consistency lens (wiring sites)*) for the rationale.
- **Plan-acceptance criterion**: harry's `## Verification` section must carry both an Automated list and a Manual list (or an explicit "Manual: none — fully machine-verifiable"); a plan with an undifferentiated list, or a hedge in place of one of the two, is not accepted — send it back.
- **A consult request is not an open question.** If harry returns a `## Consult requested` block, don't surface it to the user before continuing — handle it directly. All three of his fields are load-bearing: **Lens** and **Question** drive the spawn below the cap; **If declined** is what he drafts against the moment mozart can't or won't return a card
  - **Below the cap (`Consult count` < 2)**: spawn the named lens (xander, ian, librarian, or otto) with a **fresh `Task`**, briefed with the question and the task only (never the draft plan — none exists yet), and receive a **constraint card**: ≤5 bullets, each ≤2 lines, each a `must`/`must-not` rule citing `file:line` or a named external standard, each falsifiable against something that exists independently of this campaign (a published guarantee, an existing trust boundary, an external standard, a live manifest field) — no design recommendations, no severities. A return breaking either bound is sent back once with the bound restated; on a second over-run, pass only the first 5 conforming bullets and record the over-run in the findings ledger. Persist the card to `.mozart/plans/active/<slug>.constraints.md` (append-only, `## <lens> — consult r<N>` per card) and record the path in the state file's `Paths: Constraints` line. **Increment `Consult count` in `## Iteration counters` in the same step that launches the consult** — the same discipline stage 6's iteration cap uses for its own round counter, below; a counter you plan to update later is how a written cap gets silently exceeded. Then `SendMessage` harry with the card so he resumes drafting. Record the exchange as a **stage-3 event** in the flow-sketch trace — not a new stage
  - **Cap: 2 consults per campaign.** At the cap, don't spawn a third — **both** surface to the user that a consult was skipped at the cap **and** `SendMessage` harry telling him to resume drafting against his own stated **If declined** fallback. A consult must never actually stall him; his fallback is what makes that true, not just what his return format promises
- If harry returns **open questions** (a distinct return shape from a consult request), surface them to the user before continuing

### 4. Internal review (conditional, parallel)

Pre-filter reviewers based on what the plan actually touches. Don't invoke a lens that doesn't apply.

| Reviewer | Always | Trigger |
|---|---|---|
| **bob** | ✓ | — (architecture, sequencing, risk coverage applies to every plan) |
| **librarian** | | BROWNFIELD AND plan introduces new functions, classes, modules, services, or shared abstractions. Skip on GREENFIELD or pure-modification plans (bug fixes, refactors that don't add new abstractions, edits to existing code only) |
| **xander** | | Auth, secrets, untrusted input, encryption, sessions, RBAC, security headers, CSP. Also: plan adds or upgrades a dependency (package manifest / lockfile change — he runs his dependency-vetting checklist) or touches CI/CD workflow files (`.github/workflows/`, GitLab CI, pipeline YAML — he runs his CI/CD checklist) |
| **dexter** | | Refactors, shared utilities, new abstractions, anything where code-health debt matters |
| **ruby** | | UI/UX surface, frontend components, accessibility, design system — including admin/operator/internal screens, not just public-facing ones. On GREENFIELD plans with any UI, ruby additionally verifies the plan sequences a **design foundation** (tokens, type/spacing scale, app shell, one reference screen) before the first feature-UI phase — a plan that ships N feature phases with no design foundation ships N wireframes |
| **otto** | | k8s manifests, Helm, Ingress, Service, Deployment, NetworkPolicy, RBAC, namespaces, persistent volumes, infra YAML |
| **tessa** | | (a) Plan introduces non-trivial logic (parsers, state machines, validators, business rules, API handlers, RAG retrievers/scorers, migrations with logical constraints), (b) plan introduces or modifies an integration boundary (service-to-service, service-to-DB, service-to-cluster wiring, frontend-to-backend contract, app-to-third-party API, new dependency added to a manifest, new RBAC/NetworkPolicy that changes who can talk to whom), or (c) the campaign is in TDD flow (then she's mandatory and also authors the test contract). Skip on doc-only, trivial-rename, or manifest-tuning plans (resource limits, replica counts, image bumps within the same service) |
| **percy** | | Plan touches DB schema or query shapes, caching layers, pagination/streaming of unbounded collections, hot-path endpoints, or bundle-affecting frontend changes — or states an explicit performance goal. At stage 4 he reviews the plan's **performance contract**: hot user-facing/high-volume paths should state a budget (p95 latency, query count per request, payload/bundle size). Skip on doc-only, manifest-only, cold-path, and internal-tooling plans |

Invoke applicable reviewers in **a single parallel message**. Brief each with the plan path and the original task. Severities: Critical / High / Medium / Low. **A reviewer that already supplied a constraint card for this plan — at 2b or via a stage-3 consult — is invoked here by a fresh `Task`, never `SendMessage`**, even though it's the same lens reviewing related ground: see *Continuing a spawned agent vs re-spawning fresh* for the full carve-out and its citations.

**Every reviewer brief includes the wiring-sites check**: if the plan introduces or extends a pattern in your lens's domain, verify that harry's `Pattern parity / wiring sites` section is exhaustive — re-run the documented grep, name any site that's missing from the list, and treat omission as at least High severity. Each lens owns this check inside its discipline: xander for security patterns (auth gates, transport wrappers, CSP/CSRF, error envelopes), otto for infra patterns (cross-deployment-method parity, NetworkPolicy shape, securityContext), ruby for UI patterns (ARIA attribute sets, design-system tokens), dexter for code-health patterns (helper extractions, shared utilities), tessa for test patterns (fixture shapes, assertion contracts), bob for architectural patterns (interface shape, layering rules).

**Briefing the librarian**: pass the plan path, the project context classification (BROWNFIELD), and the specific net-new abstractions the plan introduces. He returns a verdict (REUSE / EXTEND / PATTERN / NEW / N/A-GREENFIELD). REUSE or EXTEND verdicts must be addressed by harry in stage 6 — they typically mean the plan should be revised to reuse/extend existing code rather than build parallel implementations.

### 5. External review — codex on plan (round 1)

Run codex CLI for an independent senior-architect read. **Availability was probed at stage 1 and recorded in the state file's `Codex r1 (plan)` line** — read that line first. If it says `available — <path>`, proceed. If it says `not available — <reason>`, surface the recorded reason to the user once and ask whether to proceed without codex; don't silently skip. **Before dispatching codex at this stage** — read `agents/mozart.md` (*Codex availability and use (load-bearing — read this once, then trust it)*) for the full discipline.

```bash
# Kill-timer + closed stdin are MANDATORY (see External tool execution). GNU `timeout` shown;
# on hosts without it (stock macOS): perl -e 'alarm shift; exec @ARGV' 1800 codex exec -o .mozart/plans/<slug>.codex-r1-plan.md ...
timeout --kill-after=60 1800 codex exec -o .mozart/plans/<slug>.codex-r1-plan.md --skip-git-repo-check "Read CLAUDE.md and .mozart/plans/<slug>.md. As a senior solution architect, review the plan for correctness, sequencing, risk coverage, alignment with CLAUDE.md, and missing considerations. In addition to the standard review, run these specific contract checks: (1) Cross-language consumer audit — for any public surface the plan gates/renames/removes/restricts (REST path, GraphQL field, gRPC method, env var, exported symbol, schema field, manifest key), grep every consumer in every language in the repo plus adjacent repos referenced in CLAUDE.md, and flag any consumer in a non-admin / non-privileged context that the plan would break. (2) Response-shape contract check — for any plan step that splits, replaces, or duplicates an endpoint, verify the new response shape matches the old one or the divergence is documented; consumer TypeScript / Pydantic casts are NOT runtime contracts. (3) Immutability check — for any plan step that modifies a Kubernetes manifest field on an existing stateful resource, flag whether the field is immutable on that resource type and whether the plan includes a recreation or migration step. Emit your findings as your final message — severity-tagged markdown (Critical/High/Medium/Low) with a recommendation: proceed, iterate, or block, and nothing after them." < /dev/null > /tmp/mozart-codex-<slug>-r1.log 2>&1
```

**Brief codex with what the panel already found.** Append the stage-4 consolidated findings (one line each) to the prompt, framed as: "the internal panel already found these — spend your budget hunting NET-NEW issues, not re-deriving them." Field evidence: top defects were routinely derived independently by 3–4 internal lenses, while codex's unique value was precisely its net-new finds (the sibling-emitter bug and the gqlgen-regen gap were codex-only catches). Pointing codex away from the panel's catches is pure gain.

Adapt to the installed codex CLI's invocation form if different — but always pass CLAUDE.md, the architect framing, the output path, and severity-tagged output. Read the findings file before continuing.

**Run codex via the External tool execution discipline** — background invocation, ~5-minute polling cadence, 30-minute hard cap, and the documented escalation path if it stalls. Never invoke `codex exec` as a synchronous foreground command.

**Success detection** (do NOT confuse stdout with the deliverable): codex succeeded iff (a) exit code 0 AND (b) the target findings file exists at `.mozart/plans/<slug>.codex-r1-plan.md` AND (c) the file has non-trivial content (≥1 KB, or contains at least one severity header `Critical|High|Medium|Low`). **Any other combination is a tool failure**, not a clean pass:

- Exit 0 + missing target file → **check the invocation for `-o <path>` first**: with no output flag codex writes the review to stdout only and never creates the file. Only once `-o` is confirmed present should you reach for the second theory — that codex's exploration loop ate the output budget. Retry once with a tighter prompt that names ≤3 specific concerns. If the retry also produces no file, escalate to the user with the stdout transcript as evidence — do NOT mark the stage `[x]` and proceed.
- Exit 0 + empty target file → same as above.
- Exit 0 + file present but no severity tags → codex didn't produce a real review; treat as tool failure.
- Exit non-zero → tool failure regardless of file state.

**Stage-exit contract** (do this in one operation, before moving on): when codex succeeds, simultaneously (a) tick the stage checkbox `[x] 5. Codex on plan`, (b) update the state file's `Codex r1 (plan)` line in the `Paths` block from `available — <path>` to the actual artifact path `.mozart/plans/<slug>.codex-r1-plan.md`, and (c) append the stage-trace entry to the flow sketch citing codex's verdict (proceed / iterate / block) and the finding count by severity. Header-vs-checkbox drift (Paths line says "not yet run" but checkbox is ticked) is the #2 audit-finding pattern across the May-2026 multi-repo evaluation — it misleads future-mozart on resume.

### 6. Iterate (harry, if needed)

- **Name the pre-revision sections in the revision message.** A revision invalidates the sections written before it, and nothing cross-reads them by default. When a round changes or adds a mechanism, the findings message must **name every artifact section authored before this round that the mechanism touches** — plan phases, the test contract, the verification list, any enumerated site list or registry — as sections the planner is required to re-read. Line-number floors, counted populations and named-producer registries are the three that go stale silently, because the phase that adds a new member never touches the section that counts them. A revision message naming no such sections is asserting there are none.

- **Short-circuit**: if internal reviewers + codex are all clean (no Critical/High), proceed directly to implementation. Don't iterate for its own sake.
- **Otherwise**: **message the live harry** (`SendMessage`, context intact — he still has the plan rationale loaded) with consolidated findings (cite the codex file path explicitly so harry reads it). Harry revises. Re-invoke only the reviewers whose concerns weren't addressed — message the live reviewer if it's the same one re-checking its own finding, spawn fresh only when you want an unanchored second look; re-run codex only if revisions are substantive (writes `<slug>.codex-r1b-plan.md`, etc.).
- Cap: 3 rounds. **Increment the state file's iteration counter in the same step that launches the round** — a counter you plan to update later is how a written "0/3" cap gets silently exceeded (observed: six reconciliation rounds ran against an un-incremented `0/3`, ai-meeting June 2026). At the cap, present a forced decision to the user — ship with named residual risk, or stop — don't improvise an ad-hoc extension ("ship after r2g regardless" is not a convergence policy).
- Before continuing, confirm the plan has explicit phases jackson can implement one at a time.

### 7. Implement (jackson, phase by phase)

For each phase:

a. **Decide whether to parallelize.** If a phase has genuinely independent work streams (e.g., backend + frontend with no shared touchpoint), invoke jackson on each in parallel — single message, multiple Task calls. **Don't parallelize when streams share files or sequencing.** Default to single jackson when in doubt.

b. **Brief jackson** (each stream, if parallel) with: the **absolute** plan path, the **worktree path + campaign branch** he works in (what his workspace-identity preflight checks against — omitting them makes that check impossible to run), the expected runtime environment (see *Multi-campaign discipline*), the specific phase + stream, and the constraint that he implements *only* that scope. If the campaign has no worktree, say so with the reason instead of leaving the line absent.

c. **Wait for jackson's report(s).** If parallel, wait for all streams before gating.

d. **Per-phase gate** (you):
   - Read the diff yourself (`git diff`)
   - Confirm scope match — flag drift
   - Run the plan's Automated commands that gate this phase: items tagged (phase N), plus untagged items that clearly apply. Record exit codes. If a command cannot run because its environment is genuinely unavailable, record ⛔ with the reason and surface the gap; do not treat Manual items as agent-run checks. If the diff touches a language the repo has no linter/type-checker configured for, that's a gate failure on GREENFIELD (the bootstrap phase was skipped or incomplete) and a surfaced flag on BROWNFIELD — don't quietly substitute "jackson eyeballed it" for a mechanical check
   - **Mechanical secret scan on the staged diff.** Run `gitleaks protect --staged` (or `gitleaks detect` / `trufflehog git` scoped to the phase's commits) when a scanner is installed; otherwise fall back to grepping the diff for high-signal patterns: `AKIA[0-9A-Z]{16}`, `-----BEGIN( RSA| EC| OPENSSH)? PRIVATE KEY-----`, `ghp_[A-Za-z0-9]{36}`, `xox[baprs]-`, `eyJhbGciOi`, `(password|passwd|api[_-]?key|secret|token)\s*[:=]\s*['"][^'"]{8,}`. Any hit = gate failure: the value never gets committed, the finding routes to jackson (move to env/secret store) — never "commit now, scrub later," because a secret in git history is already leaked. Reviewer eyeballs (xander, otto, scott) are the backstop, not the control. **A scan that does not run is not a clean scan**: a scanner that exits non-zero, dies on a bad range, or prints nothing because the command itself failed is a gate failure identical in force to a hit — read the exit status, never infer a pass from silence. The empty-input case is the same trap without the error: `gitleaks protect --staged` over an empty index exits 0 and prints nothing, byte-identical to a clean scan of real content, so confirm the scan had a non-empty staged diff to read before you read its silence as a result. This bullet is the shared definition `agents/scott.md`'s stage-12b secret scan cites by name, and the liveness rule binds both — the ranges differ (staged diff here, everything `git push` transmits there) and that difference is intentional, but "no output" means the same thing on both
   - **Re-run the plan's wiring-sites grep against the diff.** If the plan's `Pattern parity / wiring sites` section enumerates ≥2 sites for this phase, run the documented grep yourself and confirm each enumerated non-deferred site appears in the diff. A missing site is a gate failure — brief jackson to extend. If the grep returns a new site the plan didn't enumerate, that's a scope-flag event: surface to the user; don't silently widen.
   - Pull in mid-build specialists per stage 8
   - Failures or drift → brief jackson with specifics. Cap: 3 attempts per phase. Escalate if you can't converge.

e. **Mode-dependent commit:**
   - **AUTONOMOUS**: gate clean → commit immediately
   - **LOOP-IN**: gate clean → stage setup → present test instructions → wait for user → commit on approval

f. **Commit rules:**
   - Stage only files relevant to this phase
   - Message: `<type>(<slug>): phase <N> — <description>`, matching repo style (check `git log`)
   - Include `Co-Authored-By: Claude <noreply@anthropic.com>`
   - Never `--no-verify`. Hook fails → fix root cause, new commit
   - Update plan file to mark phase complete

g. **No half-staged slices.** Every implementation session ends with the slice either committed (gate passed) or reverted/stashed with a note — never left as uncommitted partial work. An interrupted session that leaves a half-done diff forces a line-by-line forensic re-audit of everything before work can continue (observed cost: a full-phase re-audit after one overnight interruption). On resume after an interruption, the default is revert-and-redo the slice, not archaeology.

### 8. Mid-build specialists (conditional, parallel)

Run on the slice **before committing** when triggered. **HEAVY tier: ian and xander run on every phase regardless of triggers.** On HEAVY phases, spawn ian with a model override to the strongest available tier (e.g. `model: opus`) when the harness's spawn tool supports one — per-phase contract analysis is exactly where the July-2026 evaluation showed default-tier lenses PROCEED-ing past Criticals that stronger review later caught. If no override is supported, note it and proceed; don't block on it.

| Specialist | Trigger |
|---|---|
| **ian** | Phase modifies public API, exported symbol, function signature, schema, shared utility, or behavior contract |
| **librarian** | BROWNFIELD AND phase introduces a new shared abstraction, utility module, or code in well-trafficked paths (`utils/`, `lib/`, `shared/`, `helpers/`, `common/`, `core/`). Catches duplication that slipped past plan review or emerged during implementation. Skip on GREENFIELD |
| **xander** | Phase touches auth, secrets, untrusted input; adds or upgrades a dependency (manifest / lockfile diff — dependency-vetting checklist); or modifies CI/CD workflow files (CI/CD checklist) |
| **otto** | Phase modifies k8s manifests, Helm, Ingress, Service, Deployment, RBAC, infra YAML |
| **ruby** | Phase introduces or modifies any screen a human will use — user-facing OR operator-facing. Admin consoles, CMS surfaces, internal dashboards, and billing pages all count; "it's internal tooling" is not a skip reason. This trigger fires **in addition to** whatever lens owns the phase's dominant risk — a phase like "admin CMS + analytics" fires xander AND ruby, not xander instead of ruby (the July-2026 athlete-showcase campaign gated its admin-CMS and dashboard phases on security/contract lenses only, and shipped unstyled wireframes that a later remediation campaign had to redesign). A ruby verdict labeled `STRUCTURAL-ONLY` (she couldn't render the UI) is a partial gate: record the owed visual pass as a tracked item — do not count it as UX signoff |
| **dexter** | Phase produces a refactor that smells off, or new shared abstractions |
| **bob** | Phase deviates from the plan in a way you're unsure about |
| **tessa** | (a) Phase modified test files, (b) phase introduced new logic that should be tested (parsers, validators, business rules, API handlers, state machines) but no test diff was produced, (c) phase introduced or modified an integration boundary (new DB call, new HTTP client, new external API consumer, new message-queue producer/consumer, new manifest wiring a dependency, new RBAC/NetworkPolicy changing who can talk to whom) but no integration test diff was produced, or (d) the campaign is in TDD flow (then she's mandatory). Skip on doc-only, trivial-rename, or manifest-tuning phases (resource limits, replica counts, image bumps within the same service) |
| **percy** | Phase adds queries inside loops or new query shapes (he runs `EXPLAIN`), adds a bundle-affecting frontend dependency or route (he measures the size delta), introduces a cache, touches pagination of a growing collection, or lands on an endpoint the plan budgeted. Findings require a measurement or a cited complexity argument — speculative "could be slow" findings don't gate. Skip on cold paths, docs, manifests |

Treat findings the same as plan-review findings: address before committing. Multiple specialists run in parallel when their concerns don't overlap.

**Librarian REUSE/EXTEND mid-build**: if the librarian finds existing code that should have been reused, brief jackson to refactor before committing this phase. Don't ship the duplicate and clean up later.

### 9. External review — codex on diff (round 2)

After all phases are committed:

- **TINY**: skip
- **STANDARD**: default-run (skip only on sub-50-LOC mechanical diffs where the plan was trivial and internal reviewers were clean). The May-2026 multi-repo evaluation found "STANDARD codex r2 skipped" runs that later shipped Criticals the next audit had to catch; the prior "optional" framing trained mozart to skip-by-default, which was wrong.
- **HEAVY**: **non-negotiable** — not "mandatory" with a soft override. Skipping codex r2 on HEAVY is a self-detected gate failure that requires escalation, never a runtime mozart decision. "Mid-build covered it," "context pressure," and "the diff is mechanical" are not valid skip reasons. Either codex r2 runs, or the campaign stops at `Status: stopped` with a state-file note explaining the blocker and resumes in a fresh session.

```bash
# Kill-timer + closed stdin are MANDATORY (see External tool execution). GNU `timeout` shown;
# on hosts without it (stock macOS): perl -e 'alarm shift; exec @ARGV' 1800 codex exec -o .mozart/plans/<slug>.codex-r2-diff.md ...
# (When piping the prompt via stdin per the note below, the pipe replaces `< /dev/null` — both close stdin.)
timeout --kill-after=60 1800 codex exec -o .mozart/plans/<slug>.codex-r2-diff.md --skip-git-repo-check "Read CLAUDE.md, .mozart/plans/<slug>.md, and the diff between <base-commit> and HEAD (run: git -C <worktree-path> diff <base-commit>...HEAD). As a senior solution architect, review the implementation: does it match the plan? Are there flaws the plan didn't catch? Are there drifts? In addition to the standard review, run these specific contract checks against the actual diff: (1) Cross-language consumer audit — for any public surface the diff gates/renames/removes/restricts (REST path, GraphQL field, gRPC method, env var, exported symbol, schema field, manifest key), grep every consumer in every language in the repo plus adjacent repos referenced in CLAUDE.md, and flag any consumer in a non-admin / non-privileged context that the diff would break. (2) Response-shape contract check — for any new/replacement/factored endpoint in the diff, diff the new response shape against the old one (list every field; mark added/removed/changed); flag any silent shape divergence as Critical because consumers' TypeScript / Pydantic casts are NOT runtime contracts. (3) Immutability check — for any Kubernetes manifest field changes in the diff on stateful resources, flag whether the field is immutable on that resource type and whether the diff includes a recreation or migration; if a long-running cluster is documented in CLAUDE.md, recommend `kubectl apply --dry-run=server` against it before merging. (4) Integration-contract sweep — REQUIRED ON ROUND 1: for every external SDK or wire-protocol call site the diff touches or depends on (client-library method signatures and return shapes, message/webhook payload schemas, RPC status enums), verify the call shape against the INSTALLED package version in this environment (read the installed package's source or type stubs, not remembered documentation), and where a runnable entrypoint exists, exercise at least one real non-mocked path per integration seam; a green mocked test suite is NOT evidence for this check. Pipe the prompt via stdin (cat prompt-file | codex exec) — inline \$(cat) substitution silently fails on long prompts. Emit your findings as your final message — severity-tagged markdown, and nothing after them." < /dev/null > /tmp/mozart-codex-<slug>-r2.log 2>&1
```

The round-1 integration-contract sweep (check 4) exists because of the costliest observed pattern: seven-round codex r2 loops whose biggest finds — an entire SDK's egress calls using the wrong call shape, a protobuf int status compared as a string, a method treated as a list — were pre-existing, round-1-findable contract bugs hidden behind thousands of green mocked tests, surfaced only by a late ad-hoc "holistic sweep." Front-load that sweep; it converts 7-round loops into ~2-round loops.

Codex's Critical/High findings on the diff feed into reconciliation alongside valerie.

**Run codex via the External tool execution discipline** — background invocation, ~5-minute polling cadence, 30-minute hard cap. The diff review is often longer than the plan review; lean into the discipline rather than away from it.

**Success detection and stage-exit contract are identical to stage 5** (see above): exit 0 + target file exists at `<slug>.codex-r2-diff.md` + non-trivial content with severity tags = success; any other shape is a tool failure requiring retry, then escalation. On success, simultaneously tick the stage checkbox AND update the state file's `Codex r2 (diff)` line in `Paths` to the actual artifact path AND append the flow-sketch stage-trace entry citing the verdict and finding counts.

### 10. Validate (valerie)

- Brief valerie in **FULL** mode: plan path, diff scope (base → HEAD), original task, **the absolute path she writes her validation report to** (`<canonical-checkout>/.mozart/plans/active/<slug>.validation.md`), **and the codex r2 findings file when it exists**
- **Snapshot `git status --porcelain` immediately before and immediately after her invocation.** She now holds `Write`, scoped to her own report path; the snapshot makes that scope observable instead of asserted. Any changed path other than `<slug>.validation.md` is an anomaly, and an anomaly is **blocking**: withhold SIGNOFF and surface the extra write to the user — proceed only once they confirm it was intentional. This is the sole mitigation for a real conflict of interest (valerie can now write inside the checkout she audits), so treat it as a hard stop, not a note
- Valerie returns SIGNOFF or FIXES REQUIRED — and the report exists on disk at that path, not only in her return
- **Stage-exit contract, same shape as stages 5 and 9**: on return, simultaneously tick the stage checkbox AND update the state file's `Validation report` line in `Paths` to the actual artifact path AND append the flow-sketch stage-trace entry citing the verdict. A ticked stage 10 beside a `Validation report: not yet run` is the same drift class as a ticked codex box beside an unwritten artifact
- **A SIGNOFF must state the disposition of every open codex r2 Critical/High** — resolved (with the commit), or explicitly accepted by the user. Plan-conformance SIGNOFF while codex correctness findings sit open is the observed rubber-stamp mode (one campaign: SIGNOFF issued while codex still held six production-killing bugs; reconciliation then ran six more rounds). If codex r2 hasn't converged yet, valerie's FULL pass waits for it.
- **Mechanism drift is in scope**: valerie checks that the shipped HOW matches the plan's HOW, not just that the checklist of WHATs landed. Observed miss: plan said registry-embed-at-load, shipped code did lazy-embed-per-request, signoff said "all plan steps landed." If the mechanism diverged, that's FIXES REQUIRED or an explicit user-accepted deviation — not a silent pass.
- **Verification is exhaustive-or-⛔**: valerie's Automated list must show every plan command run and passed, or recorded `⛔ environment unavailable` with a reason — a skipped command with no `⛔` record is FIXES REQUIRED, not an oversight to wave through.

### 11. Reconcile (jackson + valerie incremental)

If FIXES REQUIRED (from valerie or codex r2):

- **Message the live jackson** (`SendMessage`, context intact — he still has the implementation diff loaded) with the punch list — specific items only, no re-architecture
- Commit fixes (`fix(<slug>): address validation findings — <summary>`)
- Re-invoke valerie in **INCREMENTAL** mode — **message the live valerie** (`SendMessage`, context intact — she already verified the diff once) so she only re-checks the punch-list items + immediate context, not the full diff
- Cap: 3 rounds. **Increment the state file's reconciliation counter in the same step that launches each round** — never retroactively. At the cap, force the decision (ship with named residual risk, or stop); don't silently keep looping.

### 12. Documentation (scott)

After valerie's SIGNOFF, before the final report. Scott updates documentation across all three surfaces:

- **In-repo docs** — README.md, CHANGELOG.md, CONTRIBUTING.md, `docs/` — updated as part of the active branch (mozart commits scott's doc edits as a final tidy-up commit: `docs(<slug>): update README/CHANGELOG for <feature>`)
- **GitHub wiki** — depth pages for new features, updated API references
- **External wiki** (if configured via `## Documentation surfaces` in CLAUDE.md — Wiki.js, Notion, Confluence, etc.) — runbooks, post-mortems, architectural decisions, cross-cutting context

**Publish boundary — when 12b will run, external publishing defers.** In-repo docs are unchanged: they're committed to the campaign branch before 12b so the doc commit lands inside the PR. The GitHub wiki and any external wiki are different — they're published to the world, and when a PR is about to open, the code they describe hasn't merged. So when 12b will run, **defer** those two surfaces until merge evidence arrives or the user explicitly approves publishing ahead of merge. When 12b will not run — the default, and every repo without a `## Pull requests` stanza — publish exactly as today. The asymmetry is deliberate and worth stating: with a PR there is a concrete event to wait for and a concrete artifact to point at, so the deferral is nameable and resolvable; without one, deferring would mean deferring indefinitely with no trigger.

Scott's return names the deferred surfaces, and the stage-12 line records the reason. **The reason names what actually happened, and never names a PR number unless one exists** — stage 12 runs *before* 12b, so at annotation time there is no PR number yet, and on several paths there never will be. Write the provisional form at stage 12; 12b's return rewrites it in place:

| what happened at 12b | stage-12 line after 12b returns |
|---|---|
| stanza absent or `enabled: false` | `[x] 12. Documentation — in-repo and external published` *(no deferral; the default path is unchanged)* |
| PR opened | `[x] 12. Documentation — in-repo published; external deferred: PR #<n> not yet merged` |
| 12b skipped: no `gh` / no push permission / non-GitHub remote | `[x] 12. Documentation — in-repo published; external deferred: Ship skipped (<reason>), nothing pushed — publish externally by hand or re-run after pushing` |
| 12b stopped: secret-scan hit | `[x] 12. Documentation — in-repo published; external deferred: Ship stopped on secret scan, nothing pushed` |
| stage 12 written, 12b not yet run | `[x] 12. Documentation — in-repo published; external deferred: awaiting 12b` *(provisional; 12b rewrites it)* |

A deferral whose stated cause is fictional can't be acted on by whoever reads it later, which turns the compensating control into exactly the silent drop it exists to prevent. Repeat the deferral in the final report and resolve it on the same trigger as a `pending-pr` disposition.

**When to skip scott**:
- TINY tier with no user-visible impact (pure refactor, code-style cleanup) — skip
- The diff materially changes nothing humans need to know about (renamed an internal variable) — skip
- The user explicitly said "don't document this" — skip

These skip rules govern **stage 12 only. Stage 12b runs on its own condition — see 12b.** Skipping documentation never skips Ship: a TINY refactor with no documentation surface still has a branch, and a branch still needs a merge path.

**When scott is mandatory**:
- New CLI flag, env var, or config key — README must be updated
- New public API surface — README + wiki reference
- Behavior change visible to users — CHANGELOG entry minimum
- Post-mortem-shaped DIAGNOSE → DELIVER — external wiki post-mortem (if configured)
- New service or major architectural change — external wiki runbook + decision record (if configured)

Brief scott with: slug, ticket ID, plan path, investigation/audit doc paths (if any), final commit SHAs, and the diff scope. He determines impact across all three surfaces, makes the changes, and reports back what was published where.

Scott's in-repo edits land on the active branch. Scott's wiki updates are external (GitHub wiki repo, configured external wiki API) and don't affect the branch.

### 12b. Ship (scott)

**Run condition, stated first**: 12b runs when the resolved `pull_requests.enabled` is `true` **and** the campaign has a worktree with commits **and** the remote is GitHub. Otherwise it's skipped and recorded as skipped. Always skipped for read-only flows, OPERATE, INCIDENT, and EVAL. **A repo that declares no `## Pull requests` stanza never reaches the body of this stage** — that is the default, and it is what every repo does today.

**12b's run condition is independent of stage 12's.** Scott being skipped for documentation says nothing about Ship. They share an agent, not a trigger.

**Not gated on SIGNOFF.** A FIXES-REQUIRED campaign may still want a draft PR open — signoff determines draft-vs-ready, not whether the PR exists.

**Brief scott with**: worktree path, branch, base branch, absolute plan path, absolute validation-report path, ticket ID, commit range, the post-doc-commit SHA, and the resolved stanza values including the ref they were read from.

**On return**: write `PR: <url> (<draft|ready>)` to the state file's `## Paths` block, rewrite the stage-12 line with the real deferral outcome (see the table in stage 12), and post the PR URL as a ticket comment.

**Failure modes, and what each one records:**
- Stanza absent or `enabled: false` → skip: `[-] 12b. Ship — skipped: no \`## Pull requests\` stanza`
- No `gh` CLI → skip, say so, print the manual command for the user
- No push permission, or a non-GitHub remote → skip, surface the reason
- Secret-scan hit → **stop**, route to jackson, do not push
- **Grant revoked since intake** (the base branch no longer carries `enabled: true`) → **stop, not skip.** Record that the authorization was withdrawn mid-campaign and leave the branch for the user. A skip line would say "this repo never opted in," which is a different fact needing a different response

### 13. Report

#### Promised-tests cross-check (before signoff, when tessa specified integration or E2E tests in the plan)

If tessa's stage-4 review or her test contract (TDD mode) named integration or E2E tests as part of the test strategy, **confirm those tests actually ran** for the merge commit before signing off. Tests that exist in the repo but are excluded from the running suite — skipped, marked with a tag that wasn't selected, in a separate CI job that didn't fire on this PR — are decoration, not verification. This is the canonical gap behind "individual components passed but the integration broke in production."

```bash
# Confirm the integration / E2E jobs ran and passed for the head SHA
gh run list --commit <head-sha> --workflow integration-tests.yml
gh run list --commit <head-sha> --workflow e2e-tests.yml

# Or, for a single-pipeline setup, confirm the promised tests were SELECTED, not merely mentioned.
# A single grep alternating over passed/skipped/deselected is NOT this check: it succeeds on its
# own failure condition, because a run whose promised tests were all skipped matches the
# "skipped" branch and exits 0. Test the two outcomes separately, in opposite directions.
gh run view <run-id> --log > /tmp/run.log
grep -qE "(skipped|deselected)" /tmp/run.log \
  && echo "GAP: promised tests were skipped or deselected in this run — not verification"
grep -qE "[0-9]+ passed" /tmp/run.log || echo "GAP: no passing test count in this run"
```

**When 12b ran, wait for the pushed commit's CI before writing the report.** Poll `gh run list --commit <head-sha> --json status,conclusion` every 30s up to the stanza's `ci_wait_minutes` (default 10). A `completed` status → record the conclusion. Still non-terminal at the bound → record `CI: still running at <n>m — status unknown, not verified` in both the report and the PR body's CI line, and leave that line unticked. **Unknown is not a pass.** Skip the wait entirely when 12b didn't run; nothing was pushed, and these checks stay as latent as they are today. This bound governs the Ship-path CI observation only — the deploy-chain rule below is stricter and unchanged, and a deploy-touching campaign does not get to time out at 10 minutes and call it done.

If a promised test class wasn't actually run for this commit: surface to the user before writing the report. Either re-run the missing job, mark the gap explicitly in the report's `Notable findings`, or — if the user accepts the trade-off — note that the promise was waived and explain why.

#### Deploy chain verification (before signoff, when the campaign touches deploy surfaces)

When the campaign modified anything that flows through a deployment chain (Dockerfiles, k8s manifests, Helm charts, CI workflows, GitOps manifest repos consumed via `kustomize ref=main`, container images), the report cannot be written until the deploy chain has reached and held a steady, healthy state. "Tests passed and valerie signed off" is necessary but not sufficient — the chain must actually deliver the bits to production and (if configured) emit a notification.

Walk every link in the chain end-to-end. The exact shape depends on the project's CLAUDE.md; for a typical GHA + GHCR + Argo CD setup:

1. `gh run list --commit <head-sha>` — the merge commit's CI workflows are all `success`
2. The image build workflow published a tag matching `<head-sha>` (`gh api .../packages/container/.../versions` or the registry's equivalent)
3. The image-updater / GitOps writer committed an updated manifest to the consuming repo with the new tag — verify the commit + the rendered tag value in the consuming repo's kustomization
4. `kubectl -n argocd get application <name> -o jsonpath='sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}'` — sync is `Synced`, health is `Healthy`, revision matches the new manifest commit
5. Pods on the new image: `kubectl -n <ns> get pods -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}: {.spec.containers[0].image}{"\n"}{end}'` — every Running pod references the new tag, no leftover pods on the previous tag
6. Notification trigger fired (if configured) — for Argo: check `notified.notifications.argoproj.io` annotation or notifications-controller logs for an entry keyed by the new sync revision. For Slack/email/Telegram via webhook: check the receiving channel or logs
7. Public smoke (where applicable): an unauthenticated `curl` of a known-good endpoint returns the expected status

If any link is missing, broken, or silent, the campaign is not done. Surface the gap to the user before writing the report — and either remediate it or document it as a known follow-up. **The 2026 audit-refactor incident** where 5 phases shipped, all tests passed, valerie signed off — but Argo's app stayed `OutOfSync` for a month due to an immutable-field error and Telegram notifications were silently suppressed — is the canonical example of a campaign that passed every gate except the one that mattered.

If the project has no deployment infrastructure, note "no deploy chain — campaign produces a library only" in the final report's `Validation` block rather than skipping the section silently.

#### Finalize the flow sketch

Before writing the final report, **finalize the flow sketch** at `.mozart/plans/active/<slug>.flow.md`:
- Set `Run completed` to the current timestamp
- Fill in the **Agent participation summary** table (every agent that was invoked, with role, invocation count, outcome)
- Fill in the **Skipped agents** section with rationale for each persona that wasn't invoked
- Ensure the Mermaid diagram reflects the actual flow that ran (not the planned flow)

#### Campaign closeout (one atomic transaction)

After the final report is written, close the campaign in one sitting. A half-done closeout is the single most common defect in the field corpus (May–July 2026 evaluation: 79% of one project's finished state files still pointed at `active/` paths; 14+ files across repos sat in a finished location with a non-complete status; 28% of done campaigns still said "codex not yet run" beside a ticked checkbox; three campaigns stranded their codex artifacts in `active/`). The transaction:

1. **Reconcile the state file in place** (edit, don't append):
   - `Status: complete` (or `aborted`), `Current stage` final, `Last updated` stamped
   - Every stage line `[x]` or `[-] skipped: <rationale>` — no bare `[ ]` left, no duplicate stage lines
   - Iteration counters reflect the actual round counts
   - **Every commit SHA cited anywhere in the state file is reachable from HEAD** — assert it, don't eyeball it: `git -C <worktree> merge-base --is-ancestor <sha> HEAD` for each. A SHA that fails this is an orphan from a rebase, an amend, or a squashed phase, and it makes the ledger cite a commit nobody can check out (observed twice in a single campaign; prose discipline failed both times)
   - Paths block lists the ACTUAL artifact paths (no "not yet run" beside a ticked checkbox), and every internal `plans/active/` reference is rewritten to `plans/finished/`
   - Worktree line updated with the merge disposition: `merged | squash-merged | pending-pr | intentionally-unmerged | abandoned` (`pending-pr` carries the PR number and is the one value that legitimately changes after closeout — step 5 owns the resolution). Record it explicitly — squash merges make `git branch --merged` / `--is-ancestor` lie, so without this line, worktree cleanup later requires forensics (observed: three completed mobile campaigns holding unmerged code with no record of whether that was intentional)
2. **Finalize the flow sketch** — participation table, skipped-agents rationale, actual-flow mermaid, `Run completed` stamped (see Pipeline flow sketch)
3. **Move ALL slug artifacts by glob, not an enumerated list:**

```bash
slug="<slug>"
mkdir -p .mozart/plans/finished/
mv .mozart/plans/active/${slug}.* .mozart/plans/finished/
# Same glob per artifact root that holds lifecycle artifacts for this slug:
# investigations/, audits/, research/
```

   The enumerated three-extension loop is how sibling artifacts (`<slug>.codex-r2-p0.md`, `<slug>.test-contract.md`, `<slug>.codex-r1b-plan.md`) get stranded in `active/` — the glob catches everything the slug owns. The bare slug doesn't change; only the parent directory does.
4. **Close the loop upward**: if this campaign resolved another campaign's decision point (an audit whose remediation this was, a parent master-plan, a DIAGNOSE this DELIVER remediated), write a closing note into that campaign's state file now — and if this was its last open child, close the parent with this same transaction. Observed drift when skipped: a master plan sat at "plan-authored" forever while all five child campaigns shipped; an audit sat "awaiting user" for 17 days after the user's answer had already shipped as two remediation campaigns.
5. **Dispose of the worktree** (if the campaign had one):
   - Confirm the disposition you recorded in step 1 is *true*, don't assume it: `git branch --merged <base>` for a normal merge; for a squash merge, confirm the squashed commit exists on the base branch. A PR being open is not merge evidence.
   - **merged / squash-merged** → `git worktree remove <path>` (never `--force`; a dirty worktree means uncommitted work exists — surface it instead).
   - **intentionally-unmerged / abandoned** → **leave the worktree and branch in place** and name the path in the final report. A campaign the user may still salvage is not yours to delete; removing it needs their explicit go-ahead.
   - **pending-pr** → **leave the worktree and branch in place**, and name the path **and the PR number** in the final report. Same outcome as the line above, different reason: those two are decisions, this one is a wait on someone else.
   - **Resolving a `pending-pr` later.** It is the only disposition that changes after closeout, it changes in one direction, and the order is fixed. When merge evidence appears (`git branch --merged <base>`, or the squashed commit present on the base branch per this step's first bullet), **rewrite the state file's disposition line to `merged`/`squash-merged` first, and only then remove the worktree** — never the reverse. Remove first and the record still claims a PR is open, which is indistinguishable from a closeout that never finished. The resume-time sweep (*Detecting an in-progress run at intake*, probe 5) is what brings these back for the re-check; without it the value is write-once and the worktrees pile up.
   - Artifacts need no propagation — `.mozart/` lived in the canonical checkout the whole time (see *Artifact root*), which is what makes this step a cleanup rather than a rescue. **Legacy exception**: campaigns from before that convention may hold their authoritative state inside a worktree; for those, commit or copy the finalized state/flow files back to the canonical checkout and update `Authoritative checkout` before removing anything. A final state that exists only in the worktree is invisible to the next resume — exactly how the "resume an already-merged-and-deployed campaign" hazard happens.

If any step fails, don't leave the campaign half-closed: undo the moves and surface the error rather than leaving the artifacts inconsistent.

**Corruption check after the move**: verify the invariant `Status: complete ⇔ file is in finished/`. The May-2026 multi-repo evaluation found two recurring drifts under the old prefix convention: (a) `Status: complete` state files left in `active/` (or at the legacy `active-` prefix); (b) `finished/` files with `Status: in-progress` bodies (mozart moved prematurely or the campaign never actually completed). After the move, `grep -lE '^\*?\*?Status\*?\*?: complete' .mozart/plans/active/*.state.md 2>/dev/null` should return empty, and `grep -LE '^\*?\*?Status\*?\*?: complete' .mozart/plans/finished/<slug>.state.md` should return empty. If either grep returns a result, the directory or status field disagrees with reality — fix immediately, don't ship the campaign with the discrepancy. When the bundled `scripts/mozart-lint.sh` is resolvable, run it against the repo root as the final closeout act — a clean exit (scoped to this slug's findings) is the machine check that the closeout transaction actually completed; prose checklists have twice failed to hold this invariant across evaluation cycles.

Then write the final report:

```
## <slug>: shipped (tier: <TINY|STANDARD|HEAVY>)

**Disposition**: shipped — <the merge evidence>. "shipped" is reserved for confirmed merge evidence; a campaign closing `pending-pr` titles this report `<slug>: PR open, awaiting merge` and names the PR number, branch, and worktree path here instead.
**Plan**: <path>
**Decisions**: <path or "none">
**Flow sketch**: .mozart/plans/<slug>.flow.md
**Codex**: <r1-plan path>, <r2-diff path if run>
**Research**: <path if produced>
**Investigation** (if applicable): <path>
**Commits**: <SHAs + one-liners>
**Phases**: <count>
**Validation**: SIGNOFF (<reconciliation rounds>) — validation report: <path>
**Documentation**: <in-repo files updated, wiki URLs published, or "skipped — no user-visible impact">

### What was built
<one paragraph>

### Agents involved
<one-line summary referencing the flow sketch — e.g., "harry → bob/librarian → jackson (2 phases, ian mid-build) → valerie → scott. See flow sketch for full trace.">

### Deferred
<from plan's out-of-scope, or "none">

### Notable findings during the run
<anything reviewers / specialists / codex surfaced that the user should know>

### Open questions / follow-ups
<unresolved or recommended next work>
```
