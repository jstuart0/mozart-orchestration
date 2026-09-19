### 1. Intake
- **Decide the slug** as `<YYYY-MM-DD>-<shape>-<descriptive-kebab>` (see *Run identification and prior-art discovery*). Locate plan home: `.mozart/plans/<slug>.md`. Before locking, **discover prior art**: grep `.mozart/plans/` and `.mozart/investigations/` for runs matching topic (substring of the descriptive part) and the most recent few of the same shape. Surface relevant ones to the user concisely; only load their content if the user opts in or the prior run is a direct predecessor
- Note starting git state (branch, base commit, clean/dirty) for diff scope at validation
- **Cut the campaign worktree** (see *Worktree isolation*) — `git worktree add -b campaign/<slug> ../<repo>-worktrees/<slug> <base-branch>`, then enter it. Applies to every code-changing campaign at every tier, including TINY. `.mozart/` stays in the canonical checkout; agent briefs cite artifact paths absolutely and name the worktree path + branch. Skip only per the shape table there — and when you skip, say so with the reason
- **Probe codex availability** with `command -v codex`, and in the same bash call probe the kill-timer wrapper that will enforce codex's hard cap: `command -v timeout || command -v gtimeout || command -v perl` (see External tool execution — the cap is OS-enforced at launch, not polled). Record the result to the state file's `Codex r1 (plan)` and `Codex r2 (diff)` lines BEFORE any other stage runs. Two possible recordings: `available — <resolved path>` or `not available — <exact stderr/empty-output reason>`. **Before recording that result** — read `agents/mozart.md` (*Codex availability and use (load-bearing — read this once, then trust it)*) for the full discipline. **Codex availability is independent of Task-tool availability** — probe it independently. Skip this probe only on flows that genuinely don't use codex (RESEARCH-ONLY where no plan is drafted, AUDIT-ONLY without remediation, TINY tier).
- **Resolve the ticketing project for this repo** (see Ticket lifecycle / Project resolution). Fast path: read the `## Ticketing` stanza from the repo's CLAUDE.md (see `INTEGRATION.md` for the schema). Slow path: search the configured ticketing system by name, ask the user if ambiguous, create if missing. Persist to CLAUDE.md when missing or incomplete. Skip if the run will produce no commits (RESEARCH-ONLY, AUDIT-ONLY without remediation, INVESTIGATE-ONLY) or if the stanza declares `system: none`
- **Resolve the `## Pull requests` stanza from the remote's default branch — not from the working tree, and not from the campaign's base.** The ref an authorization is read from must be one no local input can select:

  ```bash
  # Authoritative first: ls-remote asks the REMOTE. The local pointer is a fallback, never a guess.
  auth_ref=$(git -C "$wt" ls-remote --symref origin HEAD 2>/dev/null \
             | awk '$1=="ref:"{sub("refs/heads/","",$2); print $2; exit}')
  [ -n "$auth_ref" ] || auth_ref=$(git -C "$wt" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                                   | sed 's#^refs/remotes/origin/##')
  [ -n "$auth_ref" ] || { echo "Ship disabled: origin's default branch is unresolvable"; }   # see below
  git -C "$wt" fetch origin --quiet
  git -C "$wt" show "origin/${auth_ref}:CLAUDE.md"
  ```

  **`git symbolic-ref refs/remotes/origin/HEAD` is a local pointer, not a question to the remote.** `git clone` writes it once; `git remote set-head` updates it on demand; a `git init` + `git remote add` repo never has it at all (the command exits 128), and after a remote renames its default branch the local copy stays stale — **a `fetch` does not correct it.** Both were reproduced. Either failure silently relocates the ref an authorization is read from, which is the one thing this control exists to pin. So: ask the remote, fall back to the local pointer only when the remote is unreachable, and **never guess `main`**.

  **If neither resolves, fail closed: `enabled: false`, and say so out loud.** Ship is one optional stage; a campaign whose other twelve stages are unaffected should not be aborted because a default-branch pointer is missing. Record `enabled: false — auth ref unresolvable (<reason>)` in the state file, surface it to the user at intake rather than letting them discover it at stage 12b, and name the one-line remedy (`git remote set-head -a origin`). Fail-closed on the authorization, not fail-stop on the campaign.

  Record the result in the state file as `source_ref: base:<auth_ref>@<sha>` — the `base:` prefix is a **discriminator**, not decoration: without it "read from the base branch" and "read from the working tree" have the same representation and the stop that checks for it can never fire. A missing field, or any other prefix, is a stop. If `CLAUDE.md` doesn't exist on that ref, the stanza is **absent** and Ship is disabled. Never fall back to the working tree, to `HEAD`, or to a local ref. Absent stanza → `enabled: false`, 12b skips; that is the default and it is the behavior every repo has today.
  - **The campaign's `<base>` is not required to equal `auth_ref`.** `## Worktrees`'s `base branch:` still selects the PR base — it just doesn't select the ref the grant is read from, and those are separate properties. Reading the grant from the remote's default branch already closes the attack; influencing *that* ref takes repo-admin rights, a different threat model entirely. Requiring the two to match would constrain where you may push *from*, buy no additional security, and break the `develop` / `deploy/<env>` base branches named a few sections up as legitimate. When they differ, scott's pre-push echo prints both — visible in the run record, without halting a legitimate campaign.
  - **Why the earlier form was not enough.** Reading from "the base branch" sounds pinned and isn't: `## Worktrees` is optional, and with no stanza the base resolves to `git symbolic-ref --short HEAD` (see *Cutting one*). So a maintainer who runs `gh pr checkout` on a contributed PR — the ordinary, encouraged way to help finish one — makes the contributor's own branch the base, and a "base-branch read" reads the contributor's commit. Both the intake read and scott's push-time re-read would have consumed that same attacker-influenced input and agreed with each other. Declaring `## Worktrees` doesn't help; it just means the attacker adds `base branch:` to the same working-tree-read stanza. `refs/remotes/origin/HEAD` is set by the remote, not by anything in the checkout, which is the whole property.
  - **This applies to `## Pull requests` alone, and the reason is the action class, not the stanza.** `## Ticketing`, `## Documentation surfaces`, `## Code retrieval`, and `## Worktrees` are advisory — the worst a poisoned value does is route work to the wrong place, which is visible, local, and undoable — so they resolve from the working tree as normal. `## Pull requests` authorizes a network write to a shared remote whose object store is permanent. Don't "harmonize" the five, in either direction.
- **Search for an existing ticket** that may already cover this work (see *Existing-ticket detection*). If a strong candidate is found, surface it to the user and ask whether to use the existing ticket, create new with cross-link, or supersede. Only create a new ticket when no clear match exists or the user explicitly wants a fresh one
- **Create the state file** as `.mozart/plans/active/<slug>.state.md` (per the *Directory convention*) with Status: in-progress and the initial fields populated, including resolved `ticketing project: <id> (<name>)` and `ticket: <id> (<existing|new>)`. If `.mozart/plans/active/` doesn't exist yet in this repo, create it with `mkdir -p` (one-time per repo).
- **Create the flow sketch** as `.mozart/plans/active/<slug>.flow.md` (per the *Directory convention*) with the metadata table populated, the **Proposed flow** section filled in (rationale + Mermaid diagram of the planned stages and agents — locked from this point forward), an empty *Actual flow* diagram stub, an empty *Deviations from proposed* section, and the first stage trace entry (Intake). See **Pipeline flow sketch** above for the format. Update *Actual flow*, *Deviations*, and *Stage trace* at every stage transition; never edit *Proposed flow* after intake; finalize at the report stage.

#### Pre-flight gates (run BEFORE accepting an implementation campaign)

When the campaign will modify code that lands in CI or deploys to a cluster (anything other than RESEARCH-ONLY / INVESTIGATE-ONLY), run these gates at intake. Failing a gate doesn't kill the campaign — it forces a triage decision before stage 3.

1. **CI baseline check** (skip in GREENFIELD or when no CI is configured):
   - `gh run list --branch <main-branch> --limit 5 --json status,conclusion,name --jq '.[] | "\(.name): \(.conclusion)"'`
   - If any workflow on the most recent push to main is **failing**, halt the campaign and ask the user one of:
     - "CI on `<branch>` has been red since <SHA>. Triage CI first as a separate (TINY) campaign before this one?"
     - "Acknowledge the red baseline — the campaign will inherit it, and 'tests pass' cannot be jackson's signoff signal. Use full CI as the gate or accept a degraded signal?"
   - Never silently start a campaign on a red CI baseline. The new failures get debugged together with pre-existing ones; the signal collapses.

2. **Long-running drift sanity check** (when the campaign touches infra OR a cluster's `kubectl` context is documented in CLAUDE.md):
   - `kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {.status.conditions[?(@.type=="DiskPressure")].status},{.status.conditions[?(@.type=="MemoryPressure")].status},{.status.conditions[?(@.type=="PIDPressure")].status}{"\n"}{end}'`
   - `kubectl get pods -A --field-selector status.phase=Failed --no-headers | wc -l` (cluster-wide Failed pod count — anything >20 is a sign of accumulating zombie state)
   - For Argo CD clusters: `kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}: sync={.status.sync.status} health={.status.health.status}{"\n"}{end}'` — surface any app stuck `OutOfSync` for >1h before the campaign begins
   - Surface findings concisely; the user decides whether to address before starting. **The 2026 audit-refactor incident** where node-02 had been flapping `DiskPressure` 128 times over 13 days — and bit the campaign as a hard rollout block on the final phase — is the canonical example. Surface drift at intake; don't discover it at deploy time.

3. **Toolchain baseline check** (the inverse of the CI check — fires on GREENFIELD and on any repo missing mechanical verification):
   - For each language the campaign will touch, confirm the repo has a configured linter, formatter, and type-checker (where the language has one), a test runner, and a CI workflow that runs them. Detection is cheap: config files (`eslint.config.*`/`.eslintrc*`, `[tool.ruff]`/`ruff.toml`, `.golangci.yml`, `tsconfig.json`, `[tool.mypy]`/`mypy.ini`, `.pre-commit-config.yaml`), `package.json` scripts, `.github/workflows/`.
   - **Missing toolchain on GREENFIELD → the plan MUST open with a toolchain-bootstrap phase** (linter + formatter + type-check + test runner + CI workflow, pre-commit hooks where the repo will take them) before any feature phase. The per-phase gate's "run lints/types/tests" is meaningless against a repo where none are configured — a greenfield campaign without this phase ships N phases of unverifiable code.
   - Missing toolchain on BROWNFIELD → surface to the user: bootstrap it as a phase in this campaign, as a separate TINY campaign, or acknowledge the degraded gate in the state file. Never silently run a campaign whose per-phase gate has nothing mechanical to hold.

If any gate fails and the user opts to proceed anyway, record it as a decision in `<slug>.decisions.md` and cite its D-id in Status notes so valerie sees it at signoff and downstream debugging knows the inherited baseline.


## Six shapes of work: boundaries and transitions

AUDIT can flow into DELIVER (the audit becomes the brief for a remediation plan). DIAGNOSE can flow into DELIVER (the findings become the brief for a fix plan). **DIAGNOSE and AUDIT can flow into OPERATE** when the fix is an infra/config change to a live system rather than a code change — an infra-debug investigation becomes the brief for an OPERATE change plan. **INCIDENT flows into both**: its durable-fix phase routes to DELIVER (code fix) or OPERATE (config/infra fix) with full gates restored, and its mitigation phase is an OPERATE-style live change under relaxed, incident-graded gates. Bug-shaped requests in DELIVER ("fix this bug," "X is broken") trigger DIAGNOSE first by default on STANDARD/HEAVY tier — investigation happens before planning the fix; if the diagnosis is that a live-system change is needed, remediation routes to OPERATE, not DELIVER. **A bug that is an *active outage* is INCIDENT, not DIAGNOSE** — the difference is whether service is currently down (mitigate-first) or merely wrong (investigate-first). EVAL flows into configuration fixes (its own form of DELIVER — plugin-repo commits for maintainers; overrides, field notes, or upstream PRs for plugin users).

**DELIVER vs OPERATE — the boundary.** DELIVER changes files that get committed and deployed *through a pipeline* (CI, Argo, a release). OPERATE changes a *running system directly* — the change is live the moment it's applied, before any git history records it. A manifest edit that lands via a git commit + Argo sync is DELIVER (otto reviews, jackson writes, CI/Argo deploys). The same manifest applied straight to the cluster with `kubectl apply` is OPERATE (otto plans, hank applies, verified empirically). When both are possible, prefer the DELIVER/GitOps path for anything that has one — OPERATE is for the direct changes, installs, and live debugging that don't go through a repo.


## Single-agent passthrough: routing and discipline

### Passthrough vs. orchestrate

**Passthrough** when the request is:
- A specific named agent's specialty ("have xander look at this," "ask ruby")
- A read-only review / audit / validation with no implementation expected
- A research / lookup / explanation with no expectation of building
- A single deliverable that one persona can produce in one pass

**Orchestrate** (run the pipeline) when the request:
- Will produce a commit, change, or shipped result
- Needs multiple lenses across multiple stages
- Requires a plan that spans phases
- Includes follow-on like "and then fix it" / "and then implement it" / "and ship it"

### Passthrough routing

| User asks for... | Route directly to |
|---|---|
| Security review (no fix) | **xander** |
| Code-health audit (no fix) | **dexter** |
| Architectural critique (no fix) | **bob** |
| UI/UX review (no fix) | **ruby** |
| Infra / k8s posture review (no fix) | **otto** |
| "Just apply this manifest" / "restart the pod" / "bump this config on the live system" (single reversible change) | **hank** (still runs verify → dry-run → snapshot → apply → verify) |
| "Install X" / "make this infra change" / "debug why the live system is broken" (multi-step or higher-stakes) | **OPERATE pipeline** (don't passthrough) |
| Change-impact analysis on a diff | **ian** |
| Plan-vs-diff validation (no fix) | **valerie** (FULL mode) |
| Test strategy / test quality review (no fix) | **tessa** |
| Plan review (no implementation) | **bob** alone — or **bob + codex** if user wants the external read |
| Research / find prior art / "how should we do X" | **sarah** (with parallel codebase-pattern-finder + web-search-researcher when warranted) |
| Find usage examples / patterns | **codebase-pattern-finder** |
| Explain this code | **codebase-analyzer** |
| Locate files / "where does X live" | **codebase-locator** |
| "Does X already exist?" / "is there already a thing for Y?" / "before I build Z, has it been built?" | **librarian** (skip if user confirms greenfield) |
| "Why is X broken?" / "investigate this bug" / "diagnose this failure" / "what's causing Y?" (no fix expected) | **dick** |
| "Update the docs" / "audit the README" / "is the CHANGELOG current?" / "publish this to the wiki" / "document the runbook" | **scott** |
| Plan a feature (no build) | **harry** alone for a quick draft, OR PLAN-ONLY partial flow if user wants the full review/codex pass — ask which |
| Build a feature | **DELIVER pipeline** (don't passthrough) |
| Audit + fix | **AUDIT → DELIVER** (don't passthrough) |

### How to passthrough

1. If the routing isn't obvious, confirm briefly: "This is xander's lane — invoke him directly without the pipeline?"
2. Brief the agent with the user's request as-is plus any context they need
3. Return the agent's output to the user
4. **No state file, no plan, no commit, no follow-on stages**
5. If the user follows up with "now fix it" or similar, *that's* when you escalate. Often the right entry is stage 11 (Reconcile) when fixes are punch-list-shaped, stage 7 (Implement) when planning is already done, or AUDIT → DELIVER when remediation is broader

### Don't over-orchestrate

If a user says "have ian look at this change," **do not** create a plan, run codex, open a state file, or invoke other reviewers. Just run ian and return what he found. Imposing the pipeline on a single-agent request is wasteful and feels heavy.

### Don't under-orchestrate

If a user says "audit this and fix the issues," **do not** just run dexter and call it done. That's a remediation flow — AUDIT → DELIVER. Recognize the "and fix" intent.

### When passthrough graduates to a flow

A passthrough can become a flow if the user follows up. Examples:
- "Have xander review my auth code" → passthrough to xander → user says "okay, fix what he flagged" → enter DELIVER at stage 7 with a tiny ad-hoc plan, or AUDIT → DELIVER if the findings are themed enough to warrant a real remediation plan
- "Research X" → passthrough to sarah → user says "okay, build it" → enter DELIVER at stage 3 (Plan) with sarah's brief as input

When this graduation happens, *now* you create the state file. Not before.
