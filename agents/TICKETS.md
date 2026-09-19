## Ticket lifecycle

Every commit-producing run creates a ticket in the configured ticketing system. Investigations create tickets even when they don't lead to a fix. Tickets are the durable, human-readable record; the plan / findings / state files are how the agents work, but the ticket is what humans read.

The ticketing system, project, state names, and authentication are declared in the consuming repo's `CLAUDE.md` under a `## Ticketing` stanza — see `INTEGRATION.md` for the schema and per-system templates (Plane, Linear, Jira, GitHub Issues, none). **If the stanza declares `system: none` (or is absent), the entire ticket lifecycle below is skipped.** State names referenced throughout this section (`open`, `investigating`, `in_progress`, `in_review`, `verified`, `cancelled`) are abstract names that map per-system per the stanza.

### When tickets get created (and by whom)

| Trigger | Created by | Stage | Initial state |
|---|---|---|---|
| DIAGNOSE — investigation findings drafted | **dick** | DIAGNOSE stage 2 | `investigating` |
| DELIVER — feature, enhancement, refactor (non-bug) | **mozart** | DELIVER stage 1 (intake) | `open` (TINY: `in_progress`) |
| DELIVER — bug-shaped that was preceded by DIAGNOSE | (already exists from dick) | — | transitions `investigating` → `open` |
| AUDIT → DELIVER (remediation chosen) | **mozart** | AUDIT stage 5 (decision point) | `open` |
| AUDIT report-only | **mozart** (optional) | AUDIT stage 5 | `verified` (audit ticket — record only) |

**Rule**: if a run will produce commits, it has a ticket. No silent commits.

### Project resolution (per-repo, runs once per task at intake)

**Each repo mozart works on has its own ticketing project (or board / repo / equivalent unit) — one repo, one project, 1:1.** Many repos already have a corresponding project; the resolution algorithm finds it first and only falls back to creation when nothing matches.

Resolve at intake before any ticket operation. Cache the result in the state file.

**Credentials**: retrieve auth per the `auth:` block in the repo's `## Ticketing` stanza in `CLAUDE.md` (env var, `gh auth token`, secret-manager command, etc.). The exact retrieval pattern depends on the system — see `INTEGRATION.md` for per-system templates. The base URL and project identifier come from the same stanza.

**Resolution order** (stop at first hit):

1. **`## Ticketing` stanza in the repo's CLAUDE.md** — declares `system`, `project`, optional `workspace`/`team`, `states`, `auth`. Parse the `project:` line directly. (See `INTEGRATION.md` for the full schema.)

2. **System lookup by repo name** — call the configured ticketing system's API to list projects/boards/repos and match the local repo's display name (from `package.json` `name`, `pyproject.toml` `name`, `Cargo.toml` `name`, or as fallback the git repo directory name). Try exact match first, then case-insensitive, then identifier match. The exact API call depends on the system (e.g., Plane: `GET /api/v1/workspaces/<ws>/projects/`; Linear: GraphQL `projects` query; Jira: `GET /rest/api/3/project`; GitHub: the repo itself is the project).

3. **Multiple ambiguous matches** → surface to user, ask which one. Don't guess.

4. **No matches** → ask the user before creating. Suggest a name + identifier derived from the repo. On confirmation, create the project (see *Project creation, fallback only* below).

**After resolution (any path that finds or creates a project): persist it to CLAUDE.md.**

The project identifier belongs in the repo's `CLAUDE.md` so the next run takes the fast path — no API lookup, no ambiguity. Mozart always writes the stanza when one doesn't exist or is stale:

- If the repo's `CLAUDE.md` has no `## Ticketing` stanza → append it (use the per-system template from `INTEGRATION.md`). **`## Ticketing` only — never `## Pull requests`**, which is the human's to author and is deliberately excluded from your edit whitelist (see *Orchestration discipline*). Don't generalize this instruction to "the stanza mozart resolved."
- If the stanza exists but is missing fields → fill them in
- If the stanza exists and is correct → no change
- If the stanza exists with a *different* project ID than what was resolved → surface the conflict to the user (don't silently overwrite)

If the repo has no `CLAUDE.md` at all, surface to the user — that's a separate problem (every repo mozart works on should have one). Don't auto-create CLAUDE.md.

**Resolution result** is also recorded in the state file under `ticketing:` (system, project, active_ticket) and reused for the entire run.

**Mismatch surfacing**: if the stanza declares one workspace/team/auth but the API call returns evidence of another (e.g., wrong workspace token), surface to the user — likely a credentials issue or a multi-workspace setup. Don't silently switch.

### Project creation (fallback only — when resolution finds nothing)

Only used when the user confirms no existing project matches and they want a new one. Default name = repo's display name; default identifier = first 4 uppercase letters of the name (e.g., `os-project-athena` → `ATHE`).

The creation API call depends on the system. Refer to the system's docs (the four packaged systems — Plane, Linear, Jira, GitHub — all have well-known REST/GraphQL endpoints for project/team/repo creation). After creation, mozart **always** writes the resulting project identifier, name, and identifier into the repo's `CLAUDE.md` under a `## Ticketing` stanza (per the persist-to-CLAUDE.md rule above). This is part of project creation, not optional — every newly-created project must end up recorded in the repo so the next run is the fast path.

After project creation, bootstrap states and labels if the system requires it (Plane and Linear support custom workflows; Jira workflows are typically pre-configured at the project template level; GitHub Issues uses labels for state). Bootstrap is idempotent: agents check first, create only if missing.

**States** (the abstract workflow mozart uses — map to system-specific names per the stanza):
- `open` — initial state for newly-filed tickets
- `investigating` — DIAGNOSE-shaped tickets while dick is working
- `in_progress` — implementation underway
- `in_review` — implementation complete, awaiting validation
- `verified` — valerie signed off; the ticket is closed for this run
- `cancelled` — won't-fix / superseded / abandoned

**Labels** (apply multiple per ticket as appropriate — most systems support labels/tags):
- Type: `bug`, `feature`, `investigation`, `audit`, `remediation`, `tech-debt`, `infra`, `security`, `enhancement`, `refactor`
- Severity: `severity:critical`, `severity:high`, `severity:medium`, `severity:low`
- Source agent: `agent:dick`, `agent:harry`, `agent:jackson`, `agent:valerie`, `agent:dexter`, `agent:xander`, `agent:otto`, `agent:bob`, `agent:ruby`, `agent:mozart`, `agent:librarian`

The first agent to need ticketing in a fresh project runs the bootstrap. State file records bootstrap completion so subsequent runs skip it.

### Existing-ticket detection (use, don't duplicate)

**Before creating a new ticket at intake, search the resolved project for tickets that may already cover this work.** Duplicate tickets fragment the audit trail, confuse stakeholders, and lose context that the original ticket already captured.

When this check runs:
- Always at DELIVER intake (before mozart creates the feature/refactor ticket)
- Always at AUDIT-with-remediation transition (before mozart creates the audit-remediation ticket)
- Skip when dick already created an investigation ticket in the same run (DIAGNOSE → DELIVER continuation reuses dick's ticket — see *DIAGNOSE pipeline*)
- Skip when the user invokes mozart with an explicit ticket reference ("/mozart implement ticket PROJ-42") — the ticket is given; read and use it directly

Search criteria (run at least the first two):

1. **Title keywords**: extract the 2–3 most distinctive nouns from the user's restated task and search ticket titles
2. **Active states only**: limit to non-terminal states (`open`, `investigating`, `in_progress`, `in_review` per the abstract names — map to system-specific state names from the stanza). Exclude `verified` and `cancelled` unless the user explicitly says "resume the closed one"
3. **Labels** (when applicable): if the work is bug-shaped, search for `bug` plus relevant area labels

Search via the configured system's API. Each system has a query/filter mechanism for tickets by title keyword + state — e.g., Plane's `/issues/?search=...&state__group=...`, Linear's GraphQL `issues(filter: ...)`, Jira's JQL `summary ~ "..." AND status in (...)`, or `gh issue list --search ... --state open` for GitHub. If the system's search isn't available or returns nothing useful, fall back to listing recent active tickets and matching client-side on title.

**If candidates found, surface to the user**:

```
TASK [Intake] Found existing ticket(s) that may match this work:
  - [PROJ-42] "Add SSO via $IDP" — state: open, last updated 3 days ago
  - [PROJ-31] "OAuth integration for admin panel" — state: in_progress, last updated yesterday

Use [PROJ-42], use [PROJ-31], create new (existing tickets stay as-is), or describe how this task differs?
```

**Behavior on user choice**:

- **Use existing**: skip ticket creation. Read the existing ticket's body + most recent comments to absorb context already captured. State file's `active_ticket:` field references the existing ticket. If the existing ticket's state is behind where mozart is starting (e.g., ticket is in `open` but mozart is at intake about to start work), post a comment ("Resuming via mozart pipeline") and transition to the appropriate state (`in_progress` for active DELIVER, `investigating` for DIAGNOSE-shaped intake).
- **Create new with cross-link**: create the new ticket as usual but add a `Related: <existing-id>` line in the body. Use this when the existing ticket is similar but genuinely different scope.
- **Supersede the old**: create new, comment on the old ticket ("Superseded by <new-id>: <reason>"), and (with user confirmation) transition the old to `cancelled`. Rare — use only when the old ticket is clearly stale or wrong.
- **No clear match (or user says "create new, ignore those")**: proceed with normal ticket creation.

**Confidence rules for the search**:
- **High confidence match** (title nearly identical + active state + recent activity) → strongly recommend "use existing" in the surfacing message
- **Medium confidence** (title overlaps but scope unclear) → present neutrally, let the user decide
- **Low confidence** (only loose keyword overlap) → don't bother surfacing; just create new

Don't surface every loosely-matching ticket. False-positive surfacing is its own friction. Aim for ≤3 candidates per check; if you'd surface more than 3, narrow the search and re-run.

### Ticket body templates

Tickets are durable. Body must be rich enough that a reader six months later understands what happened, why, and what was done. Most ticketing systems support markdown — use it.

#### Investigation ticket (dick creates)

```markdown
# <one-line summary of the failure — readable to non-technical reviewers>

| Field | Value |
|---|---|
| Type | investigation |
| Severity | <critical \| high \| medium \| low> |
| Confidence in root cause | <high \| medium \| low> |
| Reproduced | <yes \| no \| partial> |
| Investigator | dick |
| Investigation doc | `.mozart/investigations/<slug>.md` |

## Symptom
<what was observed; quote precisely; include error messages verbatim where they fit>

## Reproduction
<minimum steps to trigger; environment specifics; or "could not reproduce — see investigation doc for details">

```bash
# exact commands if applicable
```

## Root cause
<the confirmed cause in one paragraph, with key evidence cited inline>

**Key evidence:**
- `<file:line>` — <what's there, why it matters>
- Commit `<sha>` — <what changed, when>
- Log excerpt — <quote with timestamp>

**Causal chain (root cause → symptom):**
1. <step>
2. <step>
3. <observed symptom>

## Affected scope
<where else this pattern manifests or could manifest; specific file:line citations>

## Remediation options
1. **<Option A>** — <one-line approach>
   - Pros: <...>; Cons: <...>; Effort: <S \| M \| L>
   - Recommended downstream agent: <jackson \| harry-then-jackson \| xander \| otto \| bob>
2. **<Option B>** — <one-line approach>
   - Pros / Cons / Effort / Downstream

## Recommended next step
<one line: who should pick this up, with what scope>

## Open questions
<anything the next agent needs the user to confirm>

## What was NOT investigated
<time-box honesty: what didn't get checked and why>

---
*Investigation by dick. Full doc: `.mozart/investigations/<slug>.md`*
```

#### Feature / enhancement / refactor ticket (mozart creates at intake)

```markdown
# <one-line summary of the feature/change>

| Field | Value |
|---|---|
| Type | <feature \| enhancement \| refactor \| tech-debt> |
| Tier | <TINY \| STANDARD \| HEAVY> |
| Project context | <GREENFIELD \| BROWNFIELD> |
| Mode | <AUTONOMOUS \| LOOP-IN> |

## Goal
<what we're building and why; the user's restated intent>

## Scope
<what's deliberately in>

## Out of scope
<what's deliberately out — important to record up front>

## Acceptance criteria
<concrete, testable conditions for "done"; what the user expects to see when this ships>

## Plan
<link to plan once drafted: `.mozart/plans/<slug>.md`. "TBD until stage 3" before then.>

## Risks / open questions
<from plan once drafted; "TBD until plan is drafted" before then>

## Related artifacts
- State file: `.mozart/plans/<slug>.state.md`
- Research brief: <path or n/a>

---
*Created by mozart at intake. Plan and progress will be linked as the pipeline advances.*
```

#### Audit + remediation ticket (mozart creates at AUDIT decision point)

```markdown
# <audit goal>

| Field | Value |
|---|---|
| Type | audit + remediation |
| Audit goal | <verbatim from intake> |
| Audit doc | `.mozart/audits/<slug>.md` |

## Findings summary
<count by severity; top hotspots>

## Selected for remediation
<the scope user picked: Critical+High? specific themes? specific files?>

## Plan
<link to plan once drafted>

---
*Audit performed by: <specialists>. Remediation orchestrated by mozart.*
```

### Comment templates (every significant pipeline event)

Every state transition has a comment. Every commit has a comment. No silent state changes.

**Plan drafted** (mozart posts on harry's behalf):
```markdown
**Plan drafted** — `.mozart/plans/<slug>.md`

**Phases**:
1. <phase 1 — one-line>
2. <phase 2 — one-line>
...

**Internal review**: <reviewers run, verdict>
**Codex r1**: <verdict, link>
**Librarian**: <REUSE \| EXTEND \| PATTERN \| NEW \| N/A-GREENFIELD — link if findings>

State: <prior> → `in_progress`
```

**Per-phase commit** (jackson posts):
```markdown
**Phase <N> of <total> complete** — `<commit-sha>`

**What was done**:
<one-paragraph summary>

**Files changed**:
- `<path>`
- `<path>`

**Automated verification run**: exact commands, exit codes, and relevant output for the plan's Automated commands gating this phase: items tagged (phase N), plus untagged items that clearly apply
- <command> — <pass/fail — exact output or exit code>

**Manual verification**: not ticked by jackson; carry any plan Manual items forward for the user
- <item, if any>

**Next**: phase <N+1> — <description>
```

**Mid-build specialist finding** (mozart posts):
```markdown
**<specialist> review on phase <N>**

**Severity**: <Critical \| High \| Medium \| Low>

**Findings**:
<summary>

**Resolution**: <addressed in commit `<sha>` \| pending fix \| accepted as-is with rationale>
```

**Validation SIGNOFF** (valerie posts):
```markdown
**Validation: SIGNOFF** ✓

- Plan coverage: <N/N> steps verified
- Diff coverage: <N/N> changes accounted for
- Verification results: Automated commands all passed or are recorded ⛔ environment unavailable with reasons; Manual items carried forward unticked: <N>

State: `in_review` → `verified`. Closing.
```

**Validation FIXES REQUIRED** (valerie posts):
```markdown
**Validation: FIXES REQUIRED**

**Punch list**:
1. <item> — `<file:line>` — <why it matters>
2. <item> — `<file:line>` — <why it matters>

State: `in_review` → `in_progress` (reconciliation round <N>)
Reconciliation will be performed by jackson; valerie will re-validate INCREMENTAL.
```

**Reconciliation complete** (jackson posts):
```markdown
**Reconciliation complete** — addresses validation punch list

**Commits**:
- `<sha>` — <one-liner>

Re-running valerie INCREMENTAL.
```

**Final report** (mozart posts):
```markdown
**Shipped** ✓

- Tier: <TINY \| STANDARD \| HEAVY>
- Phases: <N>
- Validation: SIGNOFF after <N> reconciliation rounds — validation report: `.mozart/plans/<slug>.validation.md`

**Final commits**: <SHAs>
**Plan**: `.mozart/plans/<slug>.md`
**Codex**: r1 / r2 paths
**Investigation** (if applicable): `.mozart/investigations/<slug>.md`

**Notable findings during the run**:
<anything reviewers/specialists/codex surfaced worth noting>

**Deferred** (out of scope or future work):
<from plan>
```

### Lifecycle responsibilities (who does what when)

| Stage transition | Agent | Action |
|---|---|---|
| Investigation findings drafted | **dick** | Create ticket (state: `investigating`), body: investigation template |
| Feature/non-bug intake | **mozart** | Create ticket (state: `open` or `in_progress` for TINY), body: feature template |
| Audit → remediate decision | **mozart** | Create ticket (state: `open`), body: audit template |
| Plan drafted (stage 3 + 6 converged) | **mozart** | Comment with plan link + phases; transition `open` → `in_progress` |
| Per-phase commit (stage 7) | **jackson** | Comment with phase summary, SHA, files, verification run |
| Mid-build specialist finding addressed (stage 8) | **mozart** | Comment with specialist verdict + how it was addressed |
| All phases committed; codex r2 complete (HEAVY) | **mozart** | Transition `in_progress` → `in_review`; comment with codex r2 verdict |
| Validation SIGNOFF (stage 10) | **valerie** | Comment with validation summary; transition `in_review` → `verified` |
| Validation FIXES REQUIRED (stage 10) | **valerie** | Comment with punch list; transition `in_review` → `in_progress` |
| Reconciliation commits (stage 11) | **jackson** | Comment with fix SHAs |
| Reconciliation re-validated (stage 11) | **valerie** | Same as initial validation result (SIGNOFF or FIXES REQUIRED) |
| Specialist-only resolution (e.g., security mitigation, infra-only fix) | **xander / otto** as appropriate | Comment with what was done; transition to `verified` |
| Won't fix decision | **mozart** (with user approval) | Comment with rationale; transition to `cancelled` |
| Run aborted mid-pipeline | **mozart** | Comment with abort reason and current state; transition to `open` (resumable) or `cancelled` (terminal) |

### Ticket discipline

- **Markdown everywhere.** Headers, lists, code blocks, links. Most ticketing systems render it; the few that don't will at least display it as plain text.
- **Cite everything.** Every comment that references work cites a `file:line`, commit SHA, or artifact path.
- **No silent state changes.** Every state transition is preceded by an explanatory comment.
- **The ticket reflects current reality at all times.** Don't let it drift behind the actual run state. Specifically:
  - **State transitions happen the moment the corresponding gate passes**, not at the end of the run. Plan converges → transition `Planned` → `In Progress` immediately. Validation signs off → transition `In Review` → `Verified` immediately. Don't batch transitions for "tidiness later."
  - **Comments are posted at the moment of the event**, not in retrospect. Phase 2 commits → comment now, not when phase 5 commits.
  - **At every stage transition, verify the ticket's current state matches expectations** before invoking the next agent. If drifted (e.g., user manually changed the ticket between mozart steps), reconcile with a comment explaining the catch-up before proceeding.
  - **At resume**, before continuing the pipeline: read the ticket's current state and recent comments, compare to the state file. If they disagree, post a reconciliation comment and align them before any agent runs.
  - **At pause / abort / cap-hit**, immediately comment on the ticket explaining what happened and the resumption path. A run that stops without explanation in the ticket leaves the next reader (you, future-you, the user, anyone else) guessing.
  - **At each pipeline step that produces an artifact** (research brief, plan, investigation, codex review, validation report, documentation update), link or summarize it in a ticket comment within that same step.
- **No stale tickets.** If a ticket sits without progress for 7 days mid-run, add a status note explaining why. If you can't update the ticket (API down, network issue), surface the failure once and continue — but log the gap in the state file so the ticket can be reconciled later.
- **Link the artifacts.** Plan, investigation, audit, codex review files all linked in the body or comments.
- **Don't paste secrets.** Logs, query results, error messages — scrub credentials, tokens, PII before commenting.
- **Match commit messages.** Ticket title and commit messages should be consistent so a reader can follow the thread.
- **One ticket per actionable unit.** If an investigation reveals 3 distinct issues, that's 3 tickets — not one ticket with a list.
- **Don't duplicate tickets.** Run the existing-ticket detection at intake (see *Existing-ticket detection* above). When in doubt about a near-match, surface to the user rather than auto-creating a parallel ticket.

### When ticket creation fails

If auth retrieval fails, the API is unreachable, or anything else blocks ticket creation:
1. Surface the failure to the user **once** with the actual error
2. Offer to proceed without ticketing (record in state file: "Tickets disabled this run; reason: <X>")
3. Continue the regular pipeline — ticketing is tracking, not correctness

Don't loop on ticket failures. Don't retry indefinitely. Don't silently skip — always surface.
