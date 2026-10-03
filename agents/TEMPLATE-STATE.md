# Pipeline state: <slug>

**Last updated**: <ISO timestamp>
**Status**: in-progress | stopped | complete | aborted
**Flow**: FULL | PLAN-ONLY | RESEARCH-ONLY | VALIDATE-ONLY | INVESTIGATE-ONLY | OPERATE-FULL | OPERATE-PLAN-ONLY | INCIDENT-FULL | MITIGATE-ONLY
**Tier**: TINY | STANDARD | HEAVY
**Context**: GREENFIELD | BROWNFIELD
**Mode**: AUTONOMOUS | LOOP-IN
**Authoritative checkout**: <path — the checkout where this state file is canonically maintained; copies in other worktrees are replicas>
**Current stage**: <number and name, e.g., "7. Implement (phase 3 of 5)">

## Paths
- Plan: .mozart/plans/<slug>.md
- Investigation: .mozart/investigations/<slug>.md (or n/a if not bug-shaped)
- Research brief: <path or n/a>
- Constraints: <path or n/a — constraint cards from a stage-3 consult or stage 2b>
- Decisions: <.mozart/plans/active/<slug>.decisions.md, or "none yet">
- Findings ledger: <.mozart/plans/active/<slug>.ledger.md>
- Conductor record: <.mozart/plans/active/<slug>.conductor.md>
- Codex r1 (plan): <path or "not yet run">
- Codex r2 (diff): <path or "not yet run">
- Validation report: <path or "not yet run">
- PR: <url + (draft|ready) once 12b opens one, or "n/a — no ## Pull requests stanza">
- Worktree: <path + branch while the campaign runs — merge disposition appended at closeout. "n/a — <reason>" only for the shapes that don't cut one (OPERATE, INCIDENT, EVAL, read-only flows) or an explicit user opt-out>

## Tickets
- ticket: <ticket-id or "not yet created"> (URL: <url>)

## Base commit
<sha at intake>

## Stage progress
- [x] 1. Intake — <timestamp>
- [x] 2. Research — <timestamp> — <agents that ran, or "skipped">
- [x] 2b. Constraints — <timestamp> — <lens invoked, or "skipped: no trigger">
- [x] 3. Plan — <timestamp>
- [x] 4. Internal review — <timestamp> — <reviewers invoked>
- [x] 5. Codex on plan — <timestamp>
- [x] 6. Iterate — <timestamp> — <round count>
- [ ] 7. Implement — in progress, phase <N> of <total>
- [ ] 8. Mid-build specialists (per phase)
- [ ] 9. Codex on diff — <run|skip per tier>
- [ ] 10. Validate
- [ ] 11. Reconcile
- [ ] 12. Documentation (scott)
- [ ] 12b. Ship (scott) — opt-in
- [ ] 13. Report

## Phase tracker (stage 7)
- [x] Phase 1: <description> — committed <sha>
- [x] Phase 2: <description> — committed <sha>
- [ ] Phase 3: <description> — <not started | in progress | failed attempt N/3>
- [ ] Phase 4: <description>

## Iteration counters
- Plan iteration round: <N> / 3
- Per-phase attempts (current phase): <N> / 3
- Reconciliation round: <N> / 3
- Consult count: <N> / 2

## Escapes
- (none yet) | Traces-to: <DIAGNOSE/audit slug that found a defect this campaign shipped>, <phase/sha if known>

## Degraded controls
- (none) | <stage> | <control that was unavailable> | <what it would have caught> | <what ran instead>

## Change ledger (OPERATE + INCIDENT mitigations)
| id | target (context/ns/host) | change | manifest (field: old -> new; ignore: paths; coupling) | snapshot path | rollback command | verify (observed) |
|----|--------------------------|--------|-------------------------------------------------------|---------------|------------------|-------------------|

## Timeline (INCIDENT only)
Append-only, timestamped. The incident spine — survives crashes like the change ledger. mozart (as IC) writes an entry at every state change: declare, each mitigation attempt + result, each hypothesis lane's finding, root-cause confirmation, recovery verification, all-clear.

## Open questions
<from harry's plan or surfaced during the run; "none" if resolved>

## Status notes
<chronology only: escalations, stops, hangs, cross-links, anything a resuming agent should know. Judgment calls go in the decisions log, not here>
