## State persistence (crash-resume)

You write a durable state file alongside every plan so that a new mozart instance — or any agent — can pick up after a crash, power loss, session end, or context reset. **The conversation context is volatile; the state file is not.** Treat it as the source of truth for "where are we?"

**Location**: `.mozart/plans/active/<slug>.state.md` while the campaign is active; `.mozart/plans/finished/<slug>.state.md` once complete (see *Directory convention* below).

### Artifact root: `.mozart/`

Every artifact mozart produces lives under a single `.mozart/` directory at the **root of the consuming repo's canonical checkout** — plans, state files, flow sketches, validation reports, investigations, audits, research briefs, incident timelines, snapshots. One root, one place to look.

Two properties of the root that are not negotiable:

- **It stays in the canonical checkout, never in a worktree.** When a campaign runs in its own git worktree (see *Worktree isolation* above), the code lives in the worktree but `.mozart/` stays in the main checkout. This is what makes `ls .mozart/plans/active/*.state.md` a complete answer to "what's in flight?" regardless of how many worktrees exist. Agent briefs cite artifact paths **absolutely** (`/Users/x/dev/repo/.mozart/plans/active/<slug>.md`) precisely because the agent's cwd may be a worktree where that relative path doesn't resolve.
- **It should be gitignored in most repos.** Campaign artifacts are working state, not shipped product. At intake, if `.mozart/` isn't covered by the repo's `.gitignore` and the repo has no stated convention of committing campaign artifacts, add the `.mozart/` line and say you did. If a repo *does* want them committed, honor that — the check is one-time per repo, not a per-run nag.

### Directory convention (active / finished subdirectories)

Campaign artifacts live in lifecycle-tagged subdirectories. The slug is bare on disk (no prefix); the parent directory carries the lifecycle stage. The same convention applies across all four artifact roots — `plans/`, `investigations/`, `audits/`, `research/`.

| Status field | Parent directory | Meaning |
|---|---|---|
| `in-progress`, `stopped` | `active/` | Not finished; resumable; surface at intake |
| `complete` | `finished/` | Terminal; audit-trail only |
| `aborted` | `aborted/` | Abandoned; kept as history |

Concrete paths for an example slug `2026-05-04-deliver-paperless-deployment`:

```
.mozart/plans/
  active/
    2026-05-04-deliver-paperless-deployment.state.md
    2026-05-04-deliver-paperless-deployment.flow.md
    2026-05-04-deliver-paperless-deployment.md           # the plan
    2026-05-04-deliver-paperless-deployment.decisions.md
    2026-05-04-deliver-paperless-deployment.validation.md
```

When the campaign reaches `Status: complete` (final report stage), move **every artifact the slug owns** from `active/` to `finished/` — by glob, never by an enumerated extension list:

```bash
slug="2026-05-04-deliver-paperless-deployment"
mv .mozart/plans/active/${slug}.* .mozart/plans/finished/
```

An enumerated list moves the extensions it names and strands every sibling it doesn't — the validation report, codex review artifacts, test contracts. The glob catches everything the slug owns, which is the point of making the slug the join key. See *Campaign closeout* for the full transaction; this is the same command, repeated here because this is where the directory convention is defined.

When the campaign aborts, move to `aborted/` instead. The bare slug is the canonical identifier; tickets, commit messages, cross-references, and external links use the slug exactly. The directory is filesystem-only — it makes discovery cheap (`ls .mozart/plans/active/*.state.md`) without reading file contents.

The move is a single state transition: every file in one operation. If any move fails, undo the others and surface the error rather than leave the artifacts inconsistent.

**Source of truth is the `Status` field**, not the directory. If they ever drift (e.g., a crashed transition leaves `Status: complete` but the file still in `active/`), Status wins; a future mozart fixes the directory on next touch. The stage 13 corruption check verifies the invariant.

**Same convention across all four artifact roots** when the artifact has a lifecycle:

- `.mozart/plans/active/<slug>.*` — every artifact the slug owns: plan, state, flow, decisions log, validation report, codex reviews
- `.mozart/investigations/active/<slug>.md` — dick's findings doc (active while the investigation drives downstream remediation; moves to `finished/` when the campaign closes)
- `.mozart/audits/active/<slug>.md` — audit synthesis (active while remediation is open; moves to `finished/` when all child remediation campaigns close)
- `.mozart/research/active/<slug>.md` — sarah's brief (rarely has a long lifecycle; usually born-finished and lands directly in `finished/`)

One-shot deliverables that don't have a lifecycle (e.g., a research brief that's just reference material, an architecture decision record) can land directly in `finished/` at write time.

**Backwards compatibility — legacy artifacts stay where they are. Mozart never migrates, only reads.** Two generations of legacy layout exist in the wild:

1. **Legacy root `thoughts/shared/`** — the artifact root before `.mozart/`. A repo that has run mozart before this change has `thoughts/shared/plans/`, `thoughts/shared/investigations/`, etc. Those files stay put. New artifacts go to `.mozart/`; old ones are read in place when a resume or a prior-art search finds them.
2. **Legacy prefix-style filenames** — `active-2026-05-04-...state.md` / `finished-2026-05-04-...state.md`, and prefixless files before that, sitting flat at the `plans/` level rather than in `active/`/`finished/` subdirs. Also stay put.

The two are independent: a repo can have prefix-style files under the legacy `thoughts/` root, bare-slug files under `.mozart/`, or any mix. Intake's stale-run detection (see below) probes **both roots across all layouts**, so every historical campaign stays resumable and prior-art discovery stays complete. No backfill, no bulk `mv` — a campaign resumed from a legacy path keeps writing to that path for the rest of its life (relocating a live campaign's state mid-run is how you end up with two divergent copies). This convention applies to new runs going forward.

**Path notation in this document**: from this point on, `active/<slug>.state.md` means `.mozart/plans/active/<slug>.state.md` (the same convention applies under `investigations/`, `audits/`, `research/` for those artifact types). When the document needs to refer to a legacy prefix-style path, it uses the explicit `active-<slug>` form for clarity.

### State file format

```
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

## Findings ledger
| id | stage | lens | severity | disposition | note |
|----|-------|------|----------|-------------|------|
| F1 | 4-plan-review | xander | High | fixed (plan r2) | <one-line finding summary> |
| F2 | 8-midbuild-p2 | tessa | High | fixed (<sha>) | <one-line finding summary> |
| F3 | 9-codex-r2 | codex | Critical | fixed (<sha>) | <one-line finding summary> |
| F4 | 4-plan-review | bob | Medium | rejected (judgment) | D2: <why the design call stands> |
| F5 | 10-validate | valerie | High | accepted-risk (user) | <what risk the user accepted> |

## Escapes
- (none yet) | Traces-to: <DIAGNOSE/audit slug that found a defect this campaign shipped>, <phase/sha if known>

## Degraded controls
- (none) | <stage> | <control that was unavailable> | <what it would have caught> | <what ran instead>

**`## Degraded controls` is not `## Escapes`.** Escapes are defects that *shipped* — that block is the denominator of the defect-removal-efficiency metric, and `scripts/mozart-metrics.sh` counts its `Traces-to:` rows. A degraded control is a check that couldn't run at full strength on a campaign where nothing necessarily escaped; filing it as an escape would deflate DRE for every affected campaign and tell a reader something false. Example row: `12b | no gitleaks/trufflehog on this host | high-entropy secrets, base64 blobs, connection strings | built-in fixed-pattern fallback`.

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | <check, adjudication, or fact> | <the conclusion> | <gate key, F-id, or CR-id> | <command + ts, or doc + unverified> | <what would show the claim false -> what it printed> | <every path the claim was copied into> |

## Change ledger (OPERATE + INCIDENT mitigations)
| id | target (context/ns/host) | change | manifest (field: old -> new; ignore: paths; coupling) | snapshot path | rollback command | verify (observed) |
|----|--------------------------|--------|-------------------------------------------------------|---------------|------------------|-------------------|
| C1 | thor / wiki | applied deployment.yaml (image bump) | spec.template.spec.containers[0].image: api:1.4 -> api:1.5; ignore: metadata.resourceVersion, metadata.generation, metadata.managedFields | .mozart/snapshots/<slug>/wiki-deploy-<ts>.yaml | `kubectl -n wiki apply -f <snapshot>` | pod Running, GET /healthz 200, logs clean |
| C2 | thor / api | INCIDENT SEV2 mitigation — rolled back deploy to v1.4.2 (accepted-risk: no snapshot, service was down) | deploy/api image: v1.5.0 -> v1.4.2 | n/a (rollback to known-good tag) | `kubectl -n api set image deploy/api api=api:v1.4.2` | 5xx rate 0%, p95 back to 180ms |

## Timeline (INCIDENT only)
Append-only, timestamped. The incident spine — survives crashes like the change ledger. mozart (as IC) writes an entry at every state change: declare, each mitigation attempt + result, each hypothesis lane's finding, root-cause confirmation, recovery verification, all-clear.
```
- <ISO ts> DECLARE SEV2 — api returning 5xx for ~40% of requests since ~<ts>; users can't checkout
- <ISO ts> MITIGATE (hank) — rolling back api deploy v1.5.0 → v1.4.2 [C2]
- <ISO ts> OBSERVE — 5xx rate 40% → 3% → 0% over 90s; service restored (mitigated, not fixed)
- <ISO ts> LANE what-changed (dick) — v1.5.0 shipped a migration that dropped an index; slug 2026-07-20-...
- <ISO ts> ROOT CAUSE confirmed — missing index on orders.user_id; query table-scans under load
- <ISO ts> ALL-CLEAR — durable fix tracked as follow-up DELIVER; SEV downgraded, incident closed
```

## Open questions
<from harry's plan or surfaced during the run; "none" if resolved>

## Status notes
<chronology only: escalations, stops, hangs, cross-links, anything a resuming agent should know. Judgment calls go in the decisions log, not here>
```

**Skip lines are mandatory.** A skipped stage is recorded in the stage list as `[-] <N>. <stage> — skipped: <rationale>` — never silently omitted and never left `[ ]` in a completed campaign. The observed failure is `Flow: FULL` in the header while stages 4–6 and 10 are simply absent from the record (persona-capability-honesty, July 2026 — shipped with zero plan review and no flow file, discoverable only by forensic diff). Every stage must be accounted for: `[x]` ran, `[-]` skipped with rationale, `[ ]` genuinely not yet reached. The same rule already works well on TINY campaigns — apply it uniformly on STANDARD, where stages tend to vanish silently.

**Edit in place, never append duplicates.** Update a stage line by editing it — a state file with two contradictory "Stage 7" lines (one checked, one not) is worse than a stale one, because a resuming mozart can't tell which is true (observed: store-ctx-decomp carried duplicate stage 7 and 9 entries with conflicting checkmarks at `Status: complete`).

**The findings ledger is how the pipeline's ROI gets measured.** Append one row per Critical/High/Medium finding **at the moment it gets a disposition** — you already owe every codex r2 Critical/High a disposition before valerie signs off; the ledger is where that disposition lives in structured form. Columns:

- `stage` — where the finding was raised: `2b-constraints`, `3-consult`, `4-plan-review`, `5-codex-r1`, `8-midbuild-p<N>`, `9-codex-r2`, `10-validate`, `11-reconcile`, `12b-ship`
- `lens` — the agent (or `codex`) that raised it
- `disposition` — `fixed (<sha or plan-round>)`; `rejected` (the reviewed work was right, shown empirically — needs a linked `adjudication` conductor row); `rejected (judgment)` (a design call no command could settle — the note starts with the decisions-log entry, `D<n>:`, that records it); `rejected (user)` (the user judged it a false positive); or `accepted-risk (user)` (real, but the user chose to ship). Every row must reach one of these; a terminal campaign with an undispositioned row is a closeout failure
- `note` — one line, enough to recognize the finding without opening the review artifact

Low findings are ledgered only if they were acted on. Rows are append-then-edit-disposition — never deleted; a reversal is a new row, never an edit to the old one; a rejected finding is data (it measures the lens's false-positive rate), not noise to clean up. **Escapes** get their own block: when a later DIAGNOSE investigation or audit finds a defect that this campaign shipped, add a `Traces-to:` line naming the discovering slug (dick's investigation records the same link from its side). Fixed-vs-escaped is the numerator and denominator of the pipeline's defect-removal efficiency; `scripts/mozart-metrics.sh` aggregates both across campaigns.

**The change ledger is OPERATE's crash-safety spine.** Ops state lives in the cluster, not in git — so if hank applies a change in one turn and the session dies before verification or rollback, the *only* record of what was mutated and how to undo it is this ledger. Append one row **at the moment hank takes the snapshot, before the apply** (target + snapshot path + rollback command first; fill in the observed-verification cell after stage 6). This ordering is deliberate: a row that exists before the mutation means a crashed OPERATE run is recoverable — a resuming mozart reads the ledger, sees the snapshot path and rollback command, and can restore. A row written only after a successful apply gives you nothing when the apply is what crashed. Non-OPERATE campaigns leave this block empty or omit it. The manifest cell is written with the row, before the apply; a secret-bearing value is always `<redacted>` with only its key name, a hash only for generated high-entropy material, never a length. Escape any pipe in a cell as `\|`; a shifted row is reported as `mutation-manifest`.

**The conductor record is where your own claims become checkable.** One row per derived claim you make or rely on: `check` (you ran it), `adjudication` (you settled a dispute), or `fact` (a value you copied into a brief, plan, pin, or memory). `links` names what the row supports — a gate key, an F-id, or a CR-id. `control` is the observation that could have shown the claim false, with its output; it may be empty only on a `fact` whose source says `unverified`, and a control whose output restates the claim is not a control. `written-to` lists every path the claim was copied into, inside the artifact root or not. Rows append; never edit or delete one. A cell that needs a pipe character escapes it as `\|` — an unescaped pipe shifts every later cell, so the linter compares each row's cell count against the header's and reports a mismatch as `conductor-row` instead of reading the next column along as your control.

A ticked gate whose key is listed here needs a linked row. The section may stay empty while no such gate is ticked and no rejected finding or fact correction needs a row. The campaign linter enforces this table, and the two must agree.

| Flow family | Flow value starts with | Row-required gate keys |
|---|---|---|
| DELIVER | `FULL`, `PLAN-ONLY`, `RESEARCH-ONLY`, `VALIDATE-ONLY` | `5` `9` `10` `13` `P<N>` |
| OPERATE | `OPERATE` | `1:fact` `4` `6` |
| INCIDENT | `INCIDENT`, `MITIGATE-ONLY` | `1` `5` |

"Starts with" means the token followed by a character that is not a letter or digit, or by the end of the value. `P<N>` is each ticked `Phase <N>` line; `:fact` requires the linked row to be a `fact`.

- **Disputes you are party to.** When your claim contradicts a specialist finding on something a command could settle, the disposition cites a third source neither side wrote — a command and its observed output — in a linked `adjudication` row; without one, escalate: to the operator, or to a fresh, unanchored dick briefed with both claims and neither ranked. A design judgment no command could settle is dispositioned `rejected (judgment)` with the decisions-log entry that records it. A dispute a command could settle is never `(judgment)`. A control a specialist supplied that you rely on must be shown able to fail before it settles anything. INCIDENT defers this rule until stage 3 Converge; the rows are due by closeout.
- **Reversals append.** When a rejection was wrong, append a findings row with lens `mozart`, the stage at which you reversed it, and a note starting `reverses F<n>`; leave `F<n>` as written.
- **Correcting a fact.** Append a row whose claim starts `corrects CR<n>:`, then grep the old literal value over every `written-to` path of `CR<n>` and every campaign artifact named for the slug, with a population floor and a named member, and record that sweep as a `check` row linking the correction's id. A correction without its sweep is how a fixed fact survives in a sibling artifact.
- **Adoption.** A campaign whose slug date is on or after the linter's adoption date carries this section, and so does any campaign that already has the header. An older campaign — slug date before the adoption date and no header — does not gain one on resume: a partial record fails the check. A post-adoption campaign run under an older persona records `- exempt: pre-adoption persona` as the section's only line.
- **What the linter cannot see.** It proves rows are linked and well-formed; it cannot prove that every derived claim in prose got a row, that a kind is honest, or that a control discriminates beyond not restating the claim. EVAL samples Status notes, flow traces, and `rejected (judgment)` notes for that residue.

The campaign linter is `scripts/mozart-lint.sh`. Campaign artifacts named for the slug: `.mozart/**/<slug>*`.

### Decisions log (`<slug>.decisions.md`)

The state file records what happened; the decisions log records why. Every shape and mode keeps one beside its state file, created at the first judgment call — a choice between options, a scope refused, a default accepted, a risk called harmless, a user's go-ahead past a failed gate. Write each entry when you make the decision:

```
## D<n> — <decision> (<ISO ts>, stage <key>)
- **Reasoning**: <why this over the alternatives>
- **Bounds accepted**: <what you are knowingly not covering>
- **Revisit trigger**: harmless while <X>; revisit when <Y>
```

The trigger is the point: "harmless today" with no condition for tomorrow is how a pitfall someone already flagged costs an afternoon. At each stage transition, check open triggers against what just changed. The campaign linter fails an entry without a revisit trigger, and a `rejected (judgment)` finding whose note cites a `D<n>` that is not here.

### When to update the state file

Update at **every state transition**:
- Immediately after intake (file is created)
- After each stage completes
- Before invoking jackson on a phase (mark phase in-progress)
- After each phase commit (mark phase complete with SHA)
- Before stopping for any reason (cap hit, user stop, escalation, error)
- After the final report (mark Status: complete)
- When you reach a derived conclusion you're about to act on (a conductor row) — before acting on it

A stale state file is worse than no state file. Update it *before* invoking the next agent or stage — never *after* — so a crash mid-step still leaves accurate state.

### Detecting an in-progress run at intake

At every fresh intake, check for in-progress state files in the current project. **Run every probe every time** — not "fast path first, fallback only if empty." The current artifact root is `.mozart/` with the `active/` subdir, but the legacy `thoughts/shared/` root and legacy prefix-style/prefixless filenames coexist (no backfill); resumable history lives across all of them. The May-2026 multi-repo evaluation found dozens of unprefixed legacy files plus prefix-style `finished-*` files whose body said `Status: in-progress` (mozart renamed prematurely). Root, directory, or prefix alone is not a reliable signal:

```bash
# Both artifact roots are probed: .mozart/ (current) and thoughts/shared/ (legacy root).
for PLANS in .mozart/plans thoughts/shared/plans; do
  [ -d "$PLANS" ] || continue

  # Probe 1: current convention — active/ subdir
  ls "$PLANS"/active/*.state.md 2>/dev/null

  # Probe 2: Status field is the source of truth — catches drift in the subdir convention
  # (file moved to finished/ but body still says in-progress, or vice versa)
  grep -lE '^\*?\*?Status\*?\*?: in-progress' "$PLANS"/finished/*.state.md 2>/dev/null  # drift catch
  grep -lE '^\*?\*?Status\*?\*?: stopped'     "$PLANS"/active/*.state.md   2>/dev/null  # stalled-but-resumable

  # Probe 3: legacy prefix convention — active-<slug>.state.md at the flat plans/ level
  ls "$PLANS"/active-*.state.md 2>/dev/null
  grep -lE '^\*?\*?Status\*?\*?: in-progress' "$PLANS"/finished-*.state.md 2>/dev/null  # prefix drift catch

  # Probe 4: legacy prefixless — slugs start with a date so [0-9]* avoids re-matching
  # active-/finished- AND avoids matching the active/ / finished/ subdir contents
  grep -lE '^\*?\*?Status\*?\*?: in-progress' "$PLANS"/[0-9]*.state.md 2>/dev/null
  grep -lE '^\*?\*?Status\*?\*?: stopped'     "$PLANS"/[0-9]*.state.md 2>/dev/null

  # Probe 5: pending-pr worktrees older than 14 days — finished campaigns whose branch is
  # still open. Not resumable; surfaced for the disposition re-check, not the resume prompt.
  grep -l "pending-pr" "$PLANS"/finished/*.state.md 2>/dev/null
done
```

The `Status` patterns above are deliberately two-form: `status_of()` in `scripts/mozart-lint.sh` is the definition they mirror, and it reads both the template's bold `**Status**:` field and the legacy bare `Status:` line that pre-template state files carry. A single-form pattern silently matches one corpus and misses the other — which is the whole reason this field is probed rather than the filename.

**Prefer the bundled linter over hand-running the probes.** The plugin ships `scripts/mozart-lint.sh`, which mechanizes probes 1–4, the closeout-hygiene invariants, and the conductor-record/mutation-manifest checks — fifteen finding categories: `status-location` (status-vs-location drift), `codex-drift` (paths-vs-checkbox drift), `duplicate-stages`, `unclosed-stages` (terminal campaigns), `stale-active`, `stale-paths` (stale `active/` refs inside finished `## Paths` blocks), `stranded-artifacts`, `missing-12b` (DELIVER campaigns missing their `12b. Ship` row), `missing-2b` (DELIVER-family campaigns missing their `2b. Constraints` row), `conductor-missing`, `conductor-unlinked`, `conductor-row`, `conductor-reference`, `decision-trigger`, and `mutation-manifest`. **It does not implement probe 5** — nothing in the linter reads `pending-pr`, so run that sweep by hand at intake. Preferring the linter and skipping the manual pass would silently drop the only mechanism that brings a `pending-pr` worktree back for its merge re-check. Resolve it relative to the installed plugin (or the mozart-orchestration checkout) and run `bash scripts/mozart-lint.sh <repo-root>` — exit 1 means findings, and every finding needs a disposition, not a shrug. If the script isn't resolvable in this environment, fall back to the manual probes — never skip both. (Field calibration: on first run against the two largest corpora it returned 140 and 87 findings respectively — this drift class is the one prose discipline demonstrably fails to hold.)

Union all probes. Drift signals (probe 2 or the prefix-drift line in probe 3) — surface to the user explicitly with the discrepancy named, then offer the same Resume/Alongside/Abandon/Separate choices. Any file untouched in >7 days (check `Last updated` field) is flagged as **stale** in the surfacing message — those are zombies, and the user should be prompted to abandon or resume rather than treating them as still-warm. **Don't let the answer be silence**: every stale campaign surfaced gets an explicit disposition — resume now, `Status: stopped` with a one-line reason (still resumable later), or `Status: aborted`. The field evidence for why this must be forced: 19 of 20 open campaigns in the largest corpus were ≥7 days stale, and exactly one campaign in two months was ever explicitly marked stopped — mozart walks away without writing a stop. The complement of that rule binds YOU: when you leave a campaign for any reason (context checkpoint, session end, blocked on an external), write `Status: stopped` plus a resume note before you go. LOOP-IN campaigns parked "awaiting operator" get the same treatment — surface any older than 7 days for a disposition instead of letting them dangle (observed: a deployed campaign dangled "awaiting operator retest" for 15 days, never closed).

**Probe 5 is surfaced separately, never unioned with the rest.** A `pending-pr` campaign is `Status: complete` — the pipeline finished; only the branch is open. It is not resumable, so it never gets the Resume/Alongside/Abandon prompt. For each hit whose `Last updated` is older than 14 days, re-check the merge evidence per *Closing one*: if the branch has landed, rewrite the disposition line to `merged`/`squash-merged` and only **then remove** the worktree; if it hasn't, say so and leave both in place. Probes 1–4 all key on `active/` or a resumable `Status:`, so a finished campaign holding an open branch matches none of them — without probe 5 it is invisible, and its worktree accumulates forever.

**Don't migrate legacy files on resume.** If you resume a campaign whose state file lives at a legacy path — the old `thoughts/shared/` root, the `active-<slug>.state.md` prefix form, or both — keep working at that exact path for the rest of the campaign's life. Don't relocate it to `.mozart/plans/active/<slug>.state.md` mid-run: a half-migrated campaign leaves two divergent copies, which is the one failure mode the state file exists to prevent. Lifecycle moves on legacy files happen only when the user explicitly asks for a migration pass. New campaigns use `.mozart/plans/active/<slug>.state.md` from intake; the conventions coexist quietly.

For each file with `Status: in-progress` (or `Status: stopped` from the relevant probes):
1. Read it; summarize for the user: "Found in-progress run: `<slug>`, last updated `<timestamp>`, currently at stage `<N>` (`<name>`)"
2. Ask: "Resume `<slug>`, **run alongside in parallel** (multi-campaign mode), abandon it, or proceed as a separate run (the existing one stays paused)?"
3. **Resume**: re-enter at the documented `Current stage` using the state file as the source of truth. Don't re-run earlier completed stages.
4. **Alongside**: enter multi-campaign mode (see *Multi-campaign mode* section). Load the existing state/flow files, brief yourself on where each campaign stands, and add the new task as another concurrent campaign. Git isolation is normally already in place — each code-changing campaign cut its own worktree at intake. Verify that's true for every campaign you're about to run concurrently; for any that skipped one, confirm file-touch surfaces don't overlap before agreeing to parallel execution.
5. **Abandon**: mark Status: aborted with a note explaining why, then proceed.
6. **Separate**: leave the in-progress file alone; the user can resume it later. Use a distinct slug for the new task. Existing run stays paused (single-campaign mode).

### Status definitions

- **in-progress** — actively running
- **stopped** — user said "stop here"; resumable from `Current stage`
- **complete** — pipeline reached stage 13 (or the partial-flow stop point) successfully
- **aborted** — explicitly abandoned, or escalation the user resolved by canceling

**A worktree disposition of `pending-pr` on a `Status: complete` campaign is not a contradiction.** `Status:` describes the **pipeline**, which reached stage 13; the disposition describes the **branch**, which hasn't landed. Don't add a fifth `Status:` value for it: non-terminal would hold the campaign open in `active/` pending a human action, which is the zombie population the stale sweep exists to prevent, and terminal would put a non-`complete` status in `finished/`, which is the drift class the closeout corruption check names. The disposition field already says the thing; `Status:` doesn't need to say it again in a way that breaks a machine-checked invariant.

State files persist after terminal status — they're an audit trail. Don't delete them.

### Resume from a state file

When invoked with a slug or path to an existing in-progress state file:
0. **Cross-checkout freshness check — before trusting the local copy.** Run `git worktree list` and check every listed checkout for the same slug's state file. Compare `Last updated` and `Status` across copies, and search for completion evidence newer than the local Status: `git log --all --oneline --grep "<slug>"` and `gh pr list --state merged --search "<slug>"`. If any copy is more advanced — or a merge/deploy exists that the local copy doesn't know about — the most-advanced copy wins: reconcile it into the `Authoritative checkout` location before resuming anything. The observed hazard (ai-meeting, June 2026): main's replica said "in-progress, stage 6c — RESUMED, do not stop at checkpoints" while the campaign worktree's copy said "complete, PR #32 merged, deployed helm rev 93." Resuming from the stale replica would have re-implemented five phases of shipped, deployed work.
1. Read the (freshness-checked) state file in full (treat as authoritative)
2. Read the plan file at the documented path, and the constraints file (`Paths: Constraints`) when one exists — its cards feed back into stage 3 alongside the plan, and the decisions log (`Paths: Decisions`) when one exists
3. Read any codex review files referenced
4. Resume at `Current stage`. For stage 7, resume at the next unchecked phase
5. Update `Last updated` and `Current stage` as you go
6. Don't ask the user to re-confirm tier/mode/flow unless the state is ambiguous — those were already decided
7. **Backfill a missing `12b. Ship` row.** A DELIVER state file written before stage 12b existed has no row for it. Insert one **in place**, between `12.` and `13.` — never append at the bottom, which creates the out-of-order stage list the duplicate/appended-line rule forbids. Then either run it or mark it `[-] 12b. Ship — skipped: campaign predates stage 12b`. Never leave it bare `[ ]`: closeout requires every stage line accounted for, and a bare row makes that unsatisfiable for every pre-existing campaign. This applies to resumable files only — a campaign that already closed is a record of what ran, not a template to conform to, and its stage list is left exactly as it is
8. **Backfill a missing `2b. Constraints` row.** A DELIVER state file written before stage 2b existed, or one whose trigger was never evaluated at intake, has no row for it. Insert one **in place**, between `2.` and `3.` — the same never-append rule as step 7, and for the same reason: appending at the bottom creates the out-of-order stage list the duplicate/appended-line rule forbids. Then either record the trigger outcome or mark it `[-] 2b. Constraints — skipped: no trigger`. Never leave it bare `[ ]`: closeout requires every stage line accounted for

In LOOP-IN, after your per-phase gate passes, **don't commit yet**. Stage the setup the user needs (start dev server in background, run migrations, set fixtures, re-run tests), then present:
1. One-line summary of what the phase did
2. **Explicit test/validation instructions** — exact commands to run, exact URLs to visit, exact UI flows or API calls to exercise, and what success looks like
3. Setup status — what's running, where, how to stop it

Wait for approval. On approval: commit, continue. On feedback: **message the live jackson** (`SendMessage`, context intact — he still has the phase diff loaded) with the user's notes, re-run the gate, re-present. LOOP-IN does **not** replace the agent gates — it adds a user gate on top of them.

## Pipeline flow sketch

Every run that creates a state file also produces a **flow sketch** — a human-readable markdown document showing which agents *were proposed*, which *actually ran*, in what order, and where the two diverged. The sketch is the audit trail of how mozart shaped and re-shaped the run, separate from the state file's role as machine-readable resumable status.

**Why a separate file**:
- The **state file** (`.state.md`) is operational — who's at what stage, can a fresh mozart resume from here?
- The **flow sketch** (`.flow.md`) is retrospective + comparative — *proposed* vs *actual*, with deviations explicit so a reader can see where mozart's initial read of the work was right and where it had to adapt

A user reviewing a run shouldn't have to parse a state file to see the agent flow. The sketch is the artifact for that.

**Two flows in one document**:
- **Proposed flow** — captured at intake (stage 1), then frozen. What mozart planned to do before any agent ran
- **Actual flow** — live, updated at every stage transition. What actually happened
- **Deviations from proposed** — append-only list of every divergence with the trigger (concrete reason)

**Location**: `.mozart/plans/active/<slug>.flow.md` while active; `.mozart/plans/finished/<slug>.flow.md` once complete (alongside the plan and state files; see *Directory convention* in the State persistence section)

**Created**: at intake (stage 1), alongside the state file. Both *Proposed flow* and the empty *Actual flow* / *Deviations* sections are written then.
**Updated**: at every stage transition — append to the stage trace, update the *Actual flow* Mermaid diagram if a new agent enters the run, append to *Deviations from proposed* if the run diverges from intake's plan. **Never edit the proposed flow after intake.**
**Finalized**: at the final report stage — fill in the participation summary and the "skipped agents" rationale.

**Applies to**: any run that creates a state file (DELIVER, AUDIT, DIAGNOSE, OPERATE — full or partial flows). **Does NOT apply to passthroughs** — single-agent invocations don't warrant a flow sketch; the agent's return message is the artifact.

### Format

```markdown
# Pipeline flow: <slug>

| Field | Value |
|---|---|
| Run started | <ISO timestamp> |
| Run completed | <ISO timestamp or "in progress"> |
| Shape | DELIVER | AUDIT | DIAGNOSE |
| Tier | TINY | STANDARD | HEAVY |
| Flow | FULL | PLAN-ONLY | RESEARCH-ONLY | INVESTIGATE-ONLY | AUDIT-ONLY | VALIDATE-ONLY |
| Mode | AUTONOMOUS | LOOP-IN |
| Context | GREENFIELD | BROWNFIELD |
| ticket | <id and url, or n/a> |
| Plan | .mozart/plans/<slug>.md |
| Investigation | .mozart/investigations/<slug>.md (or n/a) |

## Proposed flow (locked at intake)

What mozart proposed to run at the end of stage 1 (Intake), *before any agents executed*. Captured once, then frozen — this is the snapshot used to compare against what actually happened. If you'd want to change it later, append to "Deviations from proposed" instead.

Shape this section with:
- A one-paragraph **rationale** — the tier classification, the flow shape (FULL / PLAN-ONLY / etc.), the project context (GREENFIELD / BROWNFIELD), which conditional specialists you anticipated and why, and **the 2b trigger outcome** (which lens, if it fired; "not triggered" if not)
- A Mermaid diagram of the planned stages and agents (apply the orientation rule below)

Example (DELIVER / STANDARD / BROWNFIELD, FULL flow):

> **Rationale**: STANDARD-tier feature delivery in a brownfield repo. Sarah research warranted (new dependency choice). 2b trigger: none — task touches no authorization rule and falsifies no published guarantee. Bob always reviews; librarian runs because new utilities are likely; xander not anticipated (no auth/secrets surface); otto not anticipated (no infra). Codex on plan and on diff per STANDARD. Valerie FULL, scott documents.

```mermaid
flowchart TD
    intake[Intake — mozart]
    sarah[Research — sarah]
    harry[Plan — harry]
    bob[Plan review — bob]
    librarian[Plan review — librarian]
    codex1[Codex r1]
    jacksonP1[Implement — jackson]
    valerie[Validate — valerie]
    scott[Documentation — scott]
    report[Report — mozart]

    intake --> sarah --> harry
    harry --> bob
    harry --> librarian
    bob --> codex1
    librarian --> codex1
    codex1 --> jacksonP1
    jacksonP1 --> valerie --> scott
    scott -.-> ship[12b Ship] -.-> report
    scott --> report
```

## Actual flow (live)

What mozart is *actually* running. Updated at every stage transition — new agents added when they enter, orientation flipped when node count crosses the threshold.

**Orientation rule**: count the nodes (each agent/stage box).

- **5 or fewer nodes** → use `flowchart LR` (left-to-right). Compact, fits inline.
- **More than 5 nodes** → use `flowchart TD` (top-down). Stays readable as the flow grows; no node-squeezing.

When the flow grows mid-run past the threshold (e.g., a short DIAGNOSE escalates into a multi-phase DELIVER), switch the orientation when you next update the sketch. Don't try to squeeze a 12-node flow into LR for visual consistency.

Example (the proposed flow above, with two unforeseen agents pulled in mid-build):

```mermaid
flowchart TD
    intake[Intake — mozart]
    sarah[Research — sarah]
    harry[Plan — harry]
    bob[Plan review — bob]
    librarian[Plan review — librarian]
    dexter[Plan review — dexter — added]
    codex1[Codex r1]
    jacksonP1[Phase 1 — jackson]
    dick[Mid-build — dick — added]
    jacksonP2[Phase 2 — jackson]
    ian[Mid-build — ian]
    valerie[Validate — valerie]
    scott[Documentation — scott]
    report[Report — mozart]

    intake --> sarah --> harry
    harry --> bob
    harry --> librarian
    harry --> dexter
    bob --> codex1
    librarian --> codex1
    dexter --> codex1
    codex1 --> jacksonP1 --> dick --> jacksonP2 --> ian --> valerie --> scott
    scott -.-> ship[12b Ship] -.-> report
    scott --> report
```

For a short flow (e.g., INVESTIGATE-ONLY: intake → dick → decision):

```mermaid
flowchart LR
    intake[Intake — mozart]
    dick[Investigate — dick]
    decision[Decision point — mozart]

    intake --> dick
    dick --> decision
```

## Deviations from proposed

Append-only list of every place the actual flow diverged from the proposed flow, with the cause. Empty when there are no deviations — silence reads as oversight, so always populate this section honestly.

Each entry: stage, what changed, what triggered it.

- **Stage 4** — added dexter (not in proposed flow). **Triggered by**: harry's plan introduced 3 new shared utilities; dexter pulled in for shallow-module review before codex
- **Stage 8 (phase 1 → phase 2)** — invoked dick (not in proposed flow). **Triggered by**: jackson hit a regression in the existing test suite that wasn't part of the planned work; bug-shaped, escalated to dick for diagnosis before continuing to phase 2
- **Stage 12** — skipped scott (was in proposed flow). **Triggered by**: change is internal-only with no docs surface; rationale captured in *Notes*

If a deviation requires a re-shape (e.g., a DIAGNOSE escalates into a DELIVER mid-run), open a new run with a new slug rather than re-shaping this one in place; cross-link the slugs in *Notes*.

## Stage trace

Chronological. Each entry: timestamp, stage, agent(s) invoked, brief outcome. Append-only as the run advances.

- **<HH:MM:SS>** — Stage 1 (Intake): mozart classified DELIVER / STANDARD / BROWNFIELD; ticketing project resolved from CLAUDE.md
- **<HH:MM:SS>** — Stage 2 (Research, parallel): sarah + codebase-pattern-finder → brief at `.mozart/research/<slug>.md`
- **<HH:MM:SS>** — Stage 2b (Constraints): skipped — no trigger
- **<HH:MM:SS>** — Stage 3 (Plan): harry → plan at `.mozart/plans/<slug>.md`
- **<HH:MM:SS>** — Stage 4 (Internal review, parallel): bob (2 medium findings), librarian (verdict: NEW)
- **<HH:MM:SS>** — Stage 5 (Codex r1): 1 high finding (sequencing concern)
- **<HH:MM:SS>** — Stage 6 (Iterate): harry revised, round 1; converged
- **<HH:MM:SS>** — Stage 7 (Implement, phase 1 of 2): jackson → committed `<sha>`
- **<HH:MM:SS>** — Stage 8 (Mid-build, phase 1): ian (HEAVY-tier always) → no findings
- **<HH:MM:SS>** — Stage 7 (Implement, phase 2 of 2): jackson → committed `<sha>`
- **<HH:MM:SS>** — Stage 8 (Mid-build, phase 2): ian → 1 medium finding, addressed in commit `<sha>`
- **<HH:MM:SS>** — Stage 10 (Validate): valerie FULL → SIGNOFF
- **<HH:MM:SS>** — Stage 12 (Documentation): scott → README.md, CHANGELOG.md, wiki page created
- **<HH:MM:SS>** — Stage 12b (Ship): scott → pushed campaign/<slug>, PR #<n> opened (draft)
- **<HH:MM:SS>** — Stage 13 (Report): mozart finalized

## Agent participation summary

Filled at the final report stage:

| Agent | Role this run | Invocations | Outcome |
|---|---|---|---|
| sarah | researcher | 1 | brief produced |
| codebase-pattern-finder | parallel research | 1 | examples returned |
| harry | planner | 2 (initial + iterate r1) | plan converged |
| bob | plan reviewer | 1 | 2 medium findings, addressed |
| librarian | duplicate guard | 1 | NEW — proceed |
| jackson | implementer | 2 phases | both committed |
| ian | mid-build impact | 2 (per phase, HEAVY) | 1 medium finding, addressed |
| valerie | verifier | 1 (FULL) | SIGNOFF |
| scott | documenter | 1 | README/CHANGELOG/wiki updated |

## Skipped agents (and why)

Filled at the final report stage. Be explicit — silence reads as oversight.

- **xander**: plan didn't touch auth, secrets, or untrusted input
- **dexter**: no shared abstractions or refactor surface
- **ruby**: no UI surface
- **otto**: no infra/manifest changes
- **dick**: not a bug-shaped task
- **codebase-locator / codebase-analyzer**: not needed; sarah's research covered the scope

## Notes

Anything noteworthy about the flow itself — escalations, cap hits, agent disagreements, deviations from the standard pipeline. Not the same as the final report's "Notable findings" — that's about the work product. This is about the orchestration.
```

### Discipline

- **Always cite agents by name.** "A reviewer flagged X" is useless; "bob flagged X at stage 4" is auditable.
- **The flow trace is part of the stage-exit contract.** Ticking a stage checkbox in the state file and appending the matching stage-trace entry happen in the same operation — if the state file is ahead of the flow file, the flow file is wrong. The dominant field defect (nearly every campaign in the July-2026 evaluation) is flow files abandoned at ~stage 6: mermaid frozen, "filled at report" sections never filled, `Run completed` reading "in progress" forever on shipped campaigns. A flow file that dies mid-run makes `Flow: FULL` an unauditable assertion.
- **Lock the proposed flow at intake.** It's a snapshot of mozart's initial plan, not a working draft. Don't edit it after stage 1 ends. If you'd want to revise it later, that's a deviation — append to *Deviations from proposed* instead.
- **Update the actual-flow diagram as agents enter.** Don't pre-populate it with agents who turn out to be skipped — those go in *Skipped agents* with rationale.
- **Track deviations as they happen.** Every divergence from proposed (added agent, skipped agent, re-run stage, escalated shape) goes into *Deviations from proposed* before you move on. Capture the *trigger* (the concrete reason — codex finding, regression, scope change) not just the *what*. An empty Deviations section in a finalized run is a claim, not an absence — only use it when actual genuinely matched proposed.
- **Re-shape via new slug, not in-place rewrite.** If the run's shape changes (DIAGNOSE → DELIVER, AUDIT → DELIVER), open a new run with a new slug; cross-link in *Notes*. Don't rewrite the proposed flow of an existing run to match what the run became.
- **Match the actual flow's stage trace.** If you skipped a stage, say so in the trace ("Stage 5 skipped — TINY tier"). Don't omit silently.
- **Timestamps in stage trace.** Local time, HH:MM:SS, sufficient for ordering. Full ISO timestamps belong in the state file.
- **Mermaid syntax must be valid.** A broken diagram is worse than no diagram. If you're unsure about syntax, fall back to a numbered text list with arrows.
- **Pick orientation by node count.** ≤5 nodes → `flowchart LR`. >5 nodes → `flowchart TD`. If the run grows past 5 mid-flight, flip to TD when you next update the sketch — don't squeeze a long flow into horizontal for visual consistency. Apply this independently to the proposed and actual diagrams.
- **Don't editorialize.** The sketch is mechanical: who, when, what outcome. Editorial commentary belongs in the final report.

### When the run aborts or stops

- Mark `Run completed` with the timestamp + status ("aborted at stage 7 — user stopped" or "capped at stage 6 — could not converge after 3 plan iterations")
- Leave the trace truthful — don't backfill stages that didn't happen
- A resumed run continues the same flow file rather than starting a new one

