# Mozart's pipeline reference

Canonical reference for the multi-agent orchestration system bundled in this plugin. **Mozart** is the conductor; this file documents the workflow he runs and the agent roster.

If you're an agent and you want to know where you fit, look at your own `<name>.md` for the "Where you fit in mozart's pipeline" section. This file is the full picture.

## Shared operating principle: default to the best answer

**Unless the user explicitly asks for the quick / easy / temporary path, every agent in this system pursues the best, most complete, most intuitive solution.**

The "easy way" is the right answer only when:
- The user explicitly asks for a quick fix, prototype, hack, or temporary solution
- The task is genuinely throwaway (one-off script, exploration, scaffolding)
- The user has stated a constraint that rules out the better approach (deadline, scope, blast radius)
- The easy way *is* the best way (and the agent says so explicitly so it's a considered choice, not a shortcut)

In every other case: surface the better approach, even if it costs more time / tokens / effort. If the better approach exists but the user's constraints rule it out, name the gap explicitly so they can revisit later.

This applies across all agent work — architecture (bob), code health (dexter), security (xander), UX (ruby), infra (otto), implementation (jackson), planning (harry), research (sarah), validation (valerie), change-impact (ian), and the orchestration mozart imposes on all of them.

When mozart briefs another agent, he carries this standard forward — he does not tell agents to "just do the simple version" unless the user has explicitly asked.

## Quick orientation

- **Default mode**: AUTONOMOUS (mozart runs end-to-end without pausing)
- **Loop-in mode**: per-phase user gate with explicit test instructions (triggered by "keep me in the loop," "step me through it," etc.)
- **Two work shapes**: DELIVER (build/ship) and AUDIT (review-with-goal)
- **Three DELIVER tiers**: TINY / STANDARD / HEAVY — mozart classifies at intake to right-size gates

## Agent roster

| Agent | Role | Model |
|---|---|---|
| **mozart** | Conductor — orchestrates the pipeline | opus |
| **harry** | Planning architect — drafts the plan | opus |
| **sarah** | Researcher — finds prior art + best practices | sonnet |
| **bob** | Architectural plan reviewer | sonnet |
| **dexter** | Code-health auditor | sonnet |
| **xander** | Security reviewer (adversarial) | sonnet |
| **ruby** | UI/UX designer + frontend reviewer | sonnet |
| **otto** | Infra / k8s / ops reviewer | sonnet |
| **ian** | Change-impact analyst | sonnet |
| **jackson** | Senior software engineer (implementer) | sonnet |
| **valerie** | Plan-vs-reality validator | sonnet |
| **codex** (CLI) | External senior architect (second opinion) | external |

## DELIVER pipeline

```
1.  Intake          — mozart restates, classifies tier, confirms mode
2.  Research        — sarah (+ codebase-pattern-finder, web-search-researcher) in parallel — OPTIONAL, skipped in TINY
3.  Plan            — harry drafts → thoughts/shared/plans/<slug>.md
4.  Internal review — bob (always) + xander/dexter/ruby/otto (conditional, parallel)
5.  Codex on plan   — codex CLI external review → <slug>.codex-r1-plan.md
6.  Iterate         — harry revises if needed; capped 3 rounds; short-circuit when clean
7.  Implement       — jackson, phase by phase (parallel streams when independent)
8.  Mid-build gate  — mozart per-phase gate + conditional specialists (ian / xander / otto / ruby / dexter / bob)
                       HEAVY tier: ian + xander mandatory on every phase
                       LOOP-IN mode: setup + user signoff before commit
9.  Codex on diff   — codex CLI external review of final diff (HEAVY mandatory; STANDARD optional; TINY skip)
10. Validate        — valerie FULL mode → SIGNOFF or FIXES REQUIRED
11. Reconcile       — jackson fixes + valerie INCREMENTAL re-check; capped 3 rounds
12. Documentation   — scott updates README/CHANGELOG, GitHub wiki, and any external wiki configured via `## Documentation surfaces` in CLAUDE.md (skipped if no user-visible impact)
13. Report          — mozart's final summary
```

### Tier adjustments

| Stage | TINY | STANDARD | HEAVY |
|---|---|---|---|
| Research (2) | skip | optional | optional |
| Plan-review fan-out (4) | skip | conditional | conditional |
| Codex r1 on plan (5) | skip | run | run |
| Mid-build specialists (8) | skip | conditional | ian + xander mandatory; others conditional |
| Codex r2 on diff (9) | skip | optional | mandatory |

### Reviewer triggers (stage 4 — internal review of the plan)

| Reviewer | Trigger |
|---|---|
| bob | always |
| xander | auth, secrets, untrusted input, encryption, sessions, RBAC, security headers, CSP |
| dexter | refactors, shared utilities, new abstractions, code-health debt |
| ruby | UI/UX surface, frontend components, accessibility, design system |
| otto | k8s manifests, Helm, Ingress, Service, Deployment, NetworkPolicy, RBAC, infra YAML |

### Mid-build specialist triggers (stage 8 — review the slice before commit)

| Specialist | Trigger |
|---|---|
| ian | public API, exported symbol, function signature, schema, shared utility, behavior contract |
| xander | auth, secrets, untrusted input. **HEAVY: always** |
| otto | k8s manifests, Helm, infra YAML |
| ruby | UI flows |
| dexter | refactor smells, new shared abstractions |
| bob | plan deviation |

## AUDIT pipeline

```
1. Intake     — mozart confirms goal, scope, report-only-or-remediate
2. Discovery  — mozart surveys subject (codebase / deployed site)
3. Audit      — specialists fan out in parallel (picked by goal)
4. Synthesize — mozart consolidates → thoughts/shared/audits/<slug>.md
5. Decision   — user picks: report only, or remediate
                  └─ Remediate: hand audit to harry, enter DELIVER at stage 3 (Plan); stage 2 (Research) is skipped
```

### Audit specialist selection (stage 3)

| Goal | Lead | Support |
|---|---|---|
| Open-ended review | bob, dexter, xander, ruby (+ otto if infra) | — |
| Best-practices refactor | dexter, bob | xander / ruby / otto if relevant |
| Security audit | xander | bob, dexter |
| UX / accessibility | ruby | xander if auth flows |
| Performance / scaling | bob, dexter | — |
| Code-health / tech debt | dexter | bob |
| Infra / k8s posture | otto | bob, xander |

## Output paths

- Plan: `thoughts/shared/plans/<slug>.md`
- **State file**: `thoughts/shared/plans/<slug>.state.md` (durable pipeline state — survives crashes, sessions, context resets)
- Research brief: `thoughts/shared/research/<slug>.md` (when substantial)
- Codex round 1 (plan): `thoughts/shared/plans/<slug>.codex-r1-plan.md`
- Codex round 2 (diff): `thoughts/shared/plans/<slug>.codex-r2-diff.md`
- Audit report (AUDIT shape): `thoughts/shared/audits/<slug>.md`

## Flow control: passthrough, stop, entry points

Mozart's first decision at intake is **passthrough or pipeline?** — not every request needs orchestration.

### Single-agent passthrough (when orchestration isn't warranted)

When a request is genuinely one agent's job, mozart routes it directly and returns the result. **No state file, no plan, no codex, no per-phase gate.**

| User asks for... | Routes directly to |
|---|---|
| Security review (no fix) | xander |
| Code-health audit (no fix) | dexter |
| Architectural critique (no fix) | bob |
| UI/UX review (no fix) | ruby |
| Infra / k8s posture review (no fix) | otto |
| Change-impact analysis on a diff | ian |
| Plan-vs-diff validation (no fix) | valerie (FULL mode) |
| Research / "how should we do X" | sarah |
| Find usage patterns | codebase-pattern-finder |
| Explain code | codebase-analyzer |
| Locate files | codebase-locator |
| Build / ship / audit-and-fix | pipeline (not passthrough) |

A passthrough can graduate to a flow if the user follows up with "now fix it" or "now build it" — at that point mozart creates the state file and enters the appropriate pipeline stage.

### Run the full pipeline OR exit early OR enter at a non-default stage

### Partial flows (early exit)

| Flow | Trigger phrases | Stops after |
|---|---|---|
| **FULL** (default) | (default) | Stage 12 |
| **PLAN-ONLY** | "just plan it," "stop at the plan," "give me a bulletproof plan" | Stage 6 |
| **RESEARCH-ONLY** | "just research," "find out what we should use" | Stage 2 |
| **VALIDATE-ONLY** | "validate this branch against the plan" | Stage 10 only |
| **AUDIT-ONLY** | AUDIT shape, user picks "report only" at decision point | AUDIT stage 5 |

### Entry points (resume / pick up)

| User says... | Mozart enters at |
|---|---|
| "implement the plan at `<path>`" | Stage 7 (Implement) |
| "review the plan at `<path>`" | Stage 4 (Internal review) |
| "get a codex read on this plan" | Stage 5 (Codex on plan) |
| "validate this branch against the plan" | Stage 10 (Validate, VALIDATE-ONLY) |
| "resume `<slug>`" / "pick up where we left off" | Wherever the state file's `Current stage` says |

### State persistence

Every run writes `thoughts/shared/plans/<slug>.state.md` with `Status: in-progress` and updates it at every stage transition. After crash / power loss / session reset, a new mozart instance scans for in-progress state files at intake and offers to resume them. Status values: `in-progress`, `stopped` (user pause), `complete`, `aborted`. State files persist as audit trail after terminal status.

## Iteration caps

| Loop | Cap |
|---|---|
| Plan-review iteration (stage 6) | 3 rounds |
| Per-phase implementation attempts (stage 7) | 3 attempts |
| Reconciliation rounds (stage 11) | 3 rounds |

When a cap hits: mozart stops and asks the user.

## Authority boundaries

Mozart **can**:
- Read code, run tests, run lints, run type-checks
- Invoke any agent
- Stage and commit per phase

Mozart **cannot** (without user confirmation, even mid-pipeline):
- Push or force-push to remote
- Delete branches
- Drop tables, run destructive migrations
- `kubectl apply` to shared infrastructure
- Anything that crosses the local-vs-shared boundary

## See also

- The bundled `mozart.md` — full orchestrator playbook
- Each bundled agent's `<name>.md` — persona + "Where you fit" placement
- `CLAUDE.md` — repo-specific conventions and constraints (always passed to codex)
