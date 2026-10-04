## State persistence (crash-resume)

You write a durable state file alongside every plan so that a new mozart instance — or any agent — can pick up after a crash, power loss, session end, or context reset. **The conversation context is volatile; the state file is not.** Treat it as the source of truth for "where are we?"

**Location**: `.mozart/plans/active/<slug>.state.md` while the campaign is active; `.mozart/plans/finished/<slug>.state.md` once complete (see *Directory convention* below). A new campaign's findings ledger and conductor record live beside it as `<slug>.ledger.md` and `<slug>.conductor.md`; the state file is the entry point and the source of truth for status.

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
    2026-05-04-deliver-paperless-deployment.ledger.md      # findings ledger (campaigns created split)
    2026-05-04-deliver-paperless-deployment.conductor.md   # conductor record (campaigns created split)
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

- `.mozart/plans/active/<slug>.*` — every artifact the slug owns: plan, state (with its `.ledger.md` and `.conductor.md` siblings), flow, decisions log, validation report, codex reviews
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

The skeletons are files beside this one, not text in this manual: `TEMPLATE-STATE.md`, `TEMPLATE-LEDGER.md` and `TEMPLATE-CONDUCTOR.md`. At intake, in one step, copy all three into the campaign's plans directory as `<slug>.state.md`, `<slug>.ledger.md` and `<slug>.conductor.md`, then fill every `<…>` field in the state file, including the two `## Paths` lines that declare the siblings. Copy the files; don't retype them. A retyped header is how a row-width mismatch starts, and the linter compares every row against the header it finds. A skeleton holds headers and placeholder rows only; the rows below show what filled ones look like.

```
Stage and phase lines (state file), as they read once done:
- [x] 1. Intake — <timestamp>
- [-] 9. Codex on diff — skipped: <rationale>
- [x] Phase 1: <description> — committed <sha>

Findings ledger rows (<slug>.ledger.md):
| F1 | 4-plan-review | xander | High | fixed (plan r2) | <one-line finding summary> |
| F2 | 8-midbuild-p2 | tessa | High | fixed (<sha>) | <one-line finding summary> |
| F3 | 9-codex-r2 | codex | Critical | fixed (<sha>) | <one-line finding summary> |
| F4 | 4-plan-review | bob | Medium | rejected (judgment) | D2: <why the design call stands> |
| F5 | 10-validate | valerie | High | accepted-risk (user) | <what risk the user accepted> |

Change ledger rows (state file, OPERATE + INCIDENT):
| C1 | thor / wiki | applied deployment.yaml (image bump) | spec.template.spec.containers[0].image: api:1.4 -> api:1.5; ignore: metadata.resourceVersion, metadata.generation, metadata.managedFields | .mozart/snapshots/<slug>/wiki-deploy-<ts>.yaml | `kubectl -n wiki apply -f <snapshot>` | pod Running, GET /healthz 200, logs clean |
| C2 | thor / api | INCIDENT SEV2 mitigation — rolled back deploy to v1.4.2 (accepted-risk: no snapshot, service was down) | deploy/api image: v1.5.0 -> v1.4.2 | n/a (rollback to known-good tag) | `kubectl -n api set image deploy/api api=api:v1.4.2` | 5xx rate 0%, p95 back to 180ms |

Timeline entries (state file, INCIDENT only):
- <ISO ts> DECLARE SEV2 — api returning 5xx for ~40% of requests since ~<ts>; users can't checkout
- <ISO ts> MITIGATE (hank) — rolling back api deploy v1.5.0 → v1.4.2 [C2]
- <ISO ts> OBSERVE — 5xx rate 40% → 3% → 0% over 90s; service restored (mitigated, not fixed)
- <ISO ts> LANE what-changed (dick) — v1.5.0 shipped a migration that dropped an index; slug 2026-07-20-...
- <ISO ts> ROOT CAUSE confirmed — missing index on orders.user_id; query table-scans under load
- <ISO ts> ALL-CLEAR — durable fix tracked as follow-up DELIVER; SEV downgraded, incident closed
```

**`## Degraded controls` is not `## Escapes`.** Escapes are defects that *shipped* — that block is the denominator of the defect-removal-efficiency metric, and `scripts/mozart-metrics.sh` counts its `Traces-to:` rows. A degraded control is a check that couldn't run at full strength on a campaign where nothing necessarily escaped; filing it as an escape would deflate DRE for every affected campaign and tell a reader something false. Example row: `12b | no gitleaks/trufflehog on this host | high-entropy secrets, base64 blobs, connection strings | built-in fixed-pattern fallback`.

**Skip lines are mandatory.** A skipped stage is recorded in the stage list as `[-] <N>. <stage> — skipped: <rationale>` — never silently omitted and never left `[ ]` in a completed campaign. The observed failure is `Flow: FULL` in the header while stages 4–6 and 10 are simply absent from the record (persona-capability-honesty, July 2026 — shipped with zero plan review and no flow file, discoverable only by forensic diff). Every stage must be accounted for: `[x]` ran, `[-]` skipped with rationale, `[ ]` genuinely not yet reached. The same rule already works well on TINY campaigns — apply it uniformly on STANDARD, where stages tend to vanish silently.

**Edit in place, never append duplicates.** Update a stage line by editing it — a state file with two contradictory "Stage 7" lines (one checked, one not) is worse than a stale one, because a resuming mozart can't tell which is true (observed: store-ctx-decomp carried duplicate stage 7 and 9 entries with conflicting checkmarks at `Status: complete`).

**The findings ledger is how the pipeline's ROI gets measured.** Append one row per Critical/High/Medium finding **at the moment it gets a disposition**, to `<slug>.ledger.md` (the state file itself in a single-file campaign) — you already owe every codex r2 Critical/High a disposition before valerie signs off; the ledger is where that disposition lives in structured form. Columns:

- `stage` — where the finding was raised: `2b-constraints`, `3-consult`, `4-plan-review`, `5-codex-r1`, `8-midbuild-p<N>`, `9-codex-r2`, `10-validate`, `11-reconcile`, `12b-ship`
- `lens` — the agent (or `codex`) that raised it
- `disposition` — `fixed (<sha or plan-round>)`; `rejected` (the reviewed work was right, shown empirically — needs a linked `adjudication` conductor row); `rejected (judgment)` (a design call no command could settle — the note starts with the decisions-log entry, `D<n>:`, that records it); `rejected (user)` (the user judged it a false positive); or `accepted-risk (user)` (real, but the user chose to ship). Every row must reach one of these; a terminal campaign with an undispositioned row is a closeout failure
- `note` — one line, enough to recognize the finding without opening the review artifact

Low findings are ledgered only if they were acted on. Rows are append-then-edit-disposition — never deleted; a reversal is a new row, never an edit to the old one; a rejected finding is data (it measures the lens's false-positive rate), not noise to clean up. **Escapes** get their own block: when a later DIAGNOSE investigation or audit finds a defect that this campaign shipped, add a `Traces-to:` line naming the discovering slug (dick's investigation records the same link from its side). A `Traces-to:` line puts the origin campaign's slug first (`Traces-to: <origin-slug>, <phase/sha>`). Anything else first, such as `none`, `n/a`, a ticket id, or `external — <where or why>; <slug>` for an origin with no state file in this repo, names no campaign. The origin's `## Escapes` block must carry a `Traces-to:` line naming the slug of the investigation or post-mortem (its file name up to the first dot), or `mozart-lint.sh` reports `escape-unrecorded`. Keep a campaign that is named but is not the origin out of the label position: put its slug in prose after a non-slug token. Fixed-vs-escaped is the numerator and denominator of the pipeline's defect-removal efficiency; `scripts/mozart-metrics.sh` aggregates both across campaigns.

**The change ledger is OPERATE's crash-safety spine.** Ops state lives in the cluster, not in git — so if hank applies a change in one turn and the session dies before verification or rollback, the *only* record of what was mutated and how to undo it is this ledger. Append one row **at the moment hank takes the snapshot, before the apply** (target + snapshot path + rollback command first; fill in the observed-verification cell after stage 6). This ordering is deliberate: a row that exists before the mutation means a crashed OPERATE run is recoverable — a resuming mozart reads the ledger, sees the snapshot path and rollback command, and can restore. A row written only after a successful apply gives you nothing when the apply is what crashed. Non-OPERATE campaigns leave this block empty or omit it. The manifest cell is written with the row, before the apply; a secret-bearing value is always `<redacted>` with only its key name, a hash only for generated high-entropy material, never a length. Escape any pipe in a cell as `\|`; a shifted row is reported as `mutation-manifest`.

**Where the ledger and the conductor record live.** A new campaign is split: `## Findings ledger` is in `<slug>.ledger.md` and `## Conductor record` is in `<slug>.conductor.md`, both created from their templates with the state file at intake. The stage list, change ledger, escapes, degraded controls, timeline and notes stay in the state file. A sibling keeps its section heading, so its rows read exactly as they would in the state file. The sibling of state file `F` is `F` with `.state.md` replaced by `.ledger.md` or `.conductor.md`, in the same directory; the `## Paths` line only declares the file (a `<…>` placeholder or `n/a` is no declaration) and is never used to find it. When a section is in both places the sibling wins, the in-file rows are ignored, and the linter reports the pair as `split-layout`. Each section is independent, so a campaign with an in-file ledger and a sibling conductor record reads correctly; never create one on purpose. Append a row to its file without re-reading the file. Old campaigns keep the layout they were born with (step 9 of *Resume from a state file*). For the adoption rule below, the conductor record's header is present when the state file or the conductor sibling carries it; a ledger sibling alone does not count.

**The conductor record is where your own claims become checkable.** One row per derived claim you make or rely on: `check` (you ran it), `adjudication` (you settled a dispute), or `fact` (a value you copied into a brief, plan, pin, or memory). `links` names what the row supports — a gate key, an F-id, or a CR-id. `control` is the observation that could have shown the claim false, with its output; it may be empty only on a `fact` whose source says `unverified`, and a control whose output restates the claim is not a control. `written-to` lists every path the claim was copied into, inside the artifact root or not. Rows append; never edit or delete one. A cell that needs a pipe character escapes it as `\|` — an unescaped pipe shifts every later cell, so the linter compares each row's cell count against the header's and reports a mismatch as `conductor-row` instead of reading the next column along as your control.

A ticked gate whose key is listed here needs a linked row. The section may stay empty while no such gate is ticked and no rejected finding or fact correction needs a row. The campaign linter enforces this table, and the two must agree.

| Flow family | Flow value starts with | Row-required gate keys |
|---|---|---|
| DELIVER | `FULL`, `PLAN-ONLY`, `RESEARCH-ONLY`, `VALIDATE-ONLY` | `5` `9` `10` `13` `P<N>:heavy` |
| OPERATE | `OPERATE` | `1:fact` `4` `6` |
| INCIDENT | `INCIDENT`, `MITIGATE-ONLY` | `1` `5` |

"Starts with" means the token followed by a character that is not a letter or digit, or by the end of the value. `P<N>` is each ticked `Phase <N>` line; `:heavy` requires the key only when the state file's first `**Tier**:` line names HEAVY (its leading upper-case token). TINY, LIGHT and STANDARD need no such row; an absent Tier line, an unfilled placeholder (`TINY | LIGHT | STANDARD | HEAVY`) and a value that is not upper case keep the row required. A row written on any tier is still checked for form. Where a HEAVY tier line carries `(surface:`, each `P<N>` row's claim also records `ian:` and `xander:`, each as `run` or `no trigger — <why>`; a phase that ran before an escalation to HEAVY may read `no trigger — phase ran before escalation`. `:fact` requires the linked row to be a `fact`.

- **Disputes you are party to.** When your claim contradicts a specialist finding on something a command could settle, the disposition cites a third source neither side wrote — a command and its observed output — in a linked `adjudication` row; without one, escalate: to the operator, or to a fresh, unanchored dick briefed with both claims and neither ranked. A design judgment no command could settle is dispositioned `rejected (judgment)` with the decisions-log entry that records it. A dispute a command could settle is never `(judgment)`. A control a specialist supplied that you rely on must be shown able to fail before it settles anything. INCIDENT defers this rule until stage 3 Converge; the rows are due by closeout.
- **Reversals append.** When a rejection was wrong, append a findings row with lens `mozart`, the stage at which you reversed it, and a note starting `reverses F<n>`; leave `F<n>` as written.
- **Correcting a fact.** Append a row whose claim starts `corrects CR<n>:`, then grep the old literal value over every `written-to` path of `CR<n>` and every campaign artifact named for the slug, with a population floor and a named member, and record that sweep as a `check` row linking the correction's id. A correction without its sweep is how a fixed fact survives in a sibling artifact.
- **Adoption.** A campaign whose slug date is on or after the linter's adoption date carries this section, and so does any campaign that already has the header. An older campaign — slug date before the adoption date and no header — does not gain one on resume: a partial record fails the check. A post-adoption campaign run under an older persona records `- exempt: pre-adoption persona` as the section's only line.
- **What the linter cannot see.** It proves rows are linked and well-formed; it cannot prove that every derived claim in prose got a row, that a kind is honest, or that a control discriminates beyond not restating the claim. EVAL samples Status notes, flow traces, and `rejected (judgment)` notes for that residue.
- **Phase rows when the surface is `auth`, `secrets` or `security`.** On a HEAVY tier line carrying such a surface, xander runs every phase, so the xander field must be `run`; the one other form is `no trigger — phase ran before escalation` (this qualifies the paragraph above, which names it without conditions), accepted only on a phase at or before `P<k>` and only when the Tier line says `escalated from <TIER>, D<n>` and a conductor row linked to `D<n>` claims `xander: cumulative pass on escalation (through P<k>): run`; phases order by number, then sub-phase letter (`P2` < `P2a` < `P2b` < `P3`), so `through P2` does not cover `P2a`; xander's cumulative-diff pass on escalation covers it (`mozart.md`, *Task tiers*). For campaigns dated 2026-10-04 or later the linter also requires a usable surface record on a HEAVY Tier line (at least one listed word) and both lens fields on every ticked phase row.

The campaign linter is `scripts/mozart-lint.sh`. Campaign artifacts named for the slug: `.mozart/**/<slug>*`, which includes the sibling files `<slug>.ledger.md` and `<slug>.conductor.md`.

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

Append a findings-ledger or conductor row to the end of its file without re-reading the file first. Read it only to edit a disposition, the one edit a row takes.

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

**Prefer the bundled linter over hand-running the probes.** The plugin ships `scripts/mozart-lint.sh`, which mechanizes probes 1–4, the closeout-hygiene invariants, the conductor-record/mutation-manifest checks, and the split-layout check on a campaign's sibling files, and the check that an investigation's or post-mortem's origin records the escape — seventeen finding categories: `status-location` (status-vs-location drift), `codex-drift` (paths-vs-checkbox drift), `duplicate-stages`, `unclosed-stages` (terminal campaigns), `stale-active`, `stale-paths` (stale `active/` refs inside finished `## Paths` blocks), `stranded-artifacts`, `missing-12b` (DELIVER campaigns missing their `12b. Ship` row), `missing-2b` (DELIVER-family campaigns missing their `2b. Constraints` row), `split-layout` (a sibling ledger or conductor file duplicated, missing or headingless), `conductor-missing`, `conductor-unlinked`, `conductor-row`, `conductor-reference`, `decision-trigger`, `mutation-manifest`, and `escape-unrecorded` (a DIAGNOSE or INCIDENT artifact names an origin campaign whose `## Escapes` block does not record it). **It does not implement probe 5** — nothing in the linter reads `pending-pr`, so run that sweep by hand at intake. Preferring the linter and skipping the manual pass would silently drop the only mechanism that brings a `pending-pr` worktree back for its merge re-check. Resolve it relative to the installed plugin (or the mozart-orchestration checkout) and run `bash scripts/mozart-lint.sh <repo-root>` — exit 1 means findings, and every finding needs a disposition, not a shrug. The linter and `scripts/mozart-metrics.sh` source `scripts/lib-campaign.sh` from beside themselves, so the three files travel together; with the library missing or empty either script exits 3. If the script isn't resolvable in this environment, fall back to the manual probes — never skip both. (Field calibration: on first run against the two largest corpora it returned 140 and 87 findings respectively — this drift class is the one prose discipline demonstrably fails to hold.)

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
9. **Detect the layout; never split on resume.** Before you touch a findings-ledger or conductor row, read the state file's own headings and its `## Paths` lines. A state file that carries `## Findings ledger` or `## Conductor record`, or carries neither and declares no sibling, is single-file for life: an old campaign is never split, and a section it needs later is created inside the state file. A state file that declares a sibling (a `- Findings ledger:` or `- Conductor record:` line whose value is a path, not a `<…>` placeholder or `n/a`) is split: its rows go in the sibling beside it. A declared sibling that does not exist is a crash between writing the state file and its siblings: create it from its template when no row of that kind exists anywhere (state file, ledger or conductor sibling), and when one does, surface the disagreement to the user instead of guessing. A campaign that declares a ledger sibling but no conductor sibling follows the adoption rule: a slug dated on or after the linter's adoption date gets `<slug>.conductor.md` from its template, declared in `## Paths`; an earlier one gets none.

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

The skeleton is a file beside this one, not text in this manual: `TEMPLATE-FLOW.md`. At intake, copy it to `.mozart/plans/active/<slug>.flow.md` and fill every `<…>` field. Copy it; don't retype it. A skeleton holds headers and placeholder rows only; the examples below show what filled ones look like.

What each section holds:
- **Header table** — run times, shape, tier, flow, mode, context, ticket, and the plan and investigation paths. `Run completed` reads "in progress" until the final report stage
- **Proposed flow (locked at intake)** — a one-paragraph rationale, then a Mermaid diagram of the planned stages and agents. The rationale names the tier, the flow shape, the project context, the conditional specialists you anticipated and why, and **the 2b trigger outcome** (which lens fired, or "not triggered"). Captured once at the end of stage 1, then frozen: it is the snapshot the run is compared against
- **Actual flow (live)** — the same kind of diagram, updated at every stage transition. Add an agent when it enters; mark an unplanned one `— added`. Never pre-populate it with agents who turn out to be skipped
- **Deviations from proposed** — one entry per divergence: the stage, what changed, and the trigger. Empty only when actual matched proposed
- **Stage trace** — chronological, one line per stage: `HH:MM:SS`, the stage, the agents invoked, the outcome
- **Agent participation summary** and **Skipped agents (and why)** — filled at the final report stage, one row or line per agent
- **Notes** — anything about the flow itself (escalations, cap hits, agent disagreements); the work product belongs in the final report

Examples, as filled:

```
Rationale: STANDARD-tier feature delivery in a brownfield repo. Sarah research warranted (new dependency choice). 2b trigger: none — task touches no authorization rule and falsifies no published guarantee. Bob always reviews; librarian runs because new utilities are likely; xander not anticipated (no auth/secrets surface); otto not anticipated (no infra). Codex on plan and on diff per STANDARD. Valerie FULL, scott documents.

flowchart TD
    intake[Intake — mozart]
    sarah[Research — sarah]
    harry[Plan — harry]
    bob[Plan review — bob]
    dexter[Plan review — dexter — added]
    codex1[Codex r1]
    jacksonP1[Implement — jackson]
    valerie[Validate — valerie]
    report[Report — mozart]

    intake --> sarah --> harry
    harry --> bob --> codex1
    harry --> dexter --> codex1
    codex1 --> jacksonP1 --> valerie --> report

Deviations:
- **Stage 4** — added dexter (not in proposed flow). **Triggered by**: harry's plan introduced 3 new shared utilities; dexter pulled in for shallow-module review before codex
- **Stage 12** — skipped scott (was in proposed flow). **Triggered by**: change is internal-only with no docs surface; rationale captured in *Notes*

Stage trace:
- **14:02:10** — Stage 1 (Intake): mozart classified DELIVER / STANDARD / BROWNFIELD; ticketing project resolved from CLAUDE.md
- **14:09:41** — Stage 2b (Constraints): skipped — no trigger
- **14:31:05** — Stage 7 (Implement, phase 1 of 2): jackson → committed `<sha>`
- **15:10:48** — Stage 10 (Validate): valerie FULL → SIGNOFF

Agent participation summary:
| bob | plan reviewer | 1 | 2 medium findings, addressed |
| jackson | implementer | 2 phases | both committed |

Skipped agents:
- **xander**: plan didn't touch auth, secrets, or untrusted input
- **ruby**: no UI surface
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

