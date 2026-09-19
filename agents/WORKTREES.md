## Worktree isolation (default for code-changing campaigns)

**Every campaign that will modify the repo gets its own git worktree and its own branch, cut at intake.** This is the default, not an optimization for concurrent campaigns — a single campaign in a single session still gets one. The main checkout stays clean and on its own branch; the campaign's commits accumulate somewhere the user can inspect, abandon, or merge as a unit.

Why it's the default rather than a nicety: the main checkout is a shared resource that outlives any one campaign. It carries other work's uncommitted edits, it sits on whatever branch the user was last on (often a deploy/staging branch), and a campaign that implements directly into it makes "what did this campaign actually change?" unanswerable. Field evidence for both halves: phase commits landing on a local `main` instead of the campaign branch, and 4 of 12 checkouts in one project sitting on branches unrelated to their directory names.

### When a worktree is cut

| Shape / flow | Worktree? |
|---|---|
| DELIVER FULL, any tier including TINY | **Yes** — cut at intake |
| AUDIT or DIAGNOSE that flows into remediation | **Yes** — cut at the point remediation is committed to, not at intake |
| VALIDATE-ONLY | No — it validates a branch/diff the user already has. Cutting a fresh worktree off the base branch would validate the wrong tree. Work against the branch the user named |
| AUDIT-ONLY, INVESTIGATE-ONLY, RESEARCH-ONLY, PLAN-ONLY | No — nothing is modified; a worktree would be an empty directory |
| OPERATE | No — the changes land on a live system, not in the repo. If an OPERATE run also needs a repo-side manifest commit, cut one for that commit only |
| INCIDENT | No — the clock is the enemy and mitigation is applied to live systems. A durable-fix campaign spawned *after* the incident closes is a DELIVER campaign and gets one |
| EVAL | No — read-only over campaign artifacts |

TINY is not an exception. A one-line fix is still a ticket, still a branch, still something the user may want to review before it touches their working tree.

### Layout

Worktrees live in a **sibling directory** to the repo, named `<repo>-worktrees/`, one subdirectory per slug:

```
~/dev/myrepo/                                  ← canonical checkout; .mozart/ lives HERE
~/dev/myrepo-worktrees/
  2026-07-25-deliver-search-filters/           ← branch: campaign/2026-07-25-deliver-search-filters
  2026-07-26-deliver-billing-refactor/         ← branch: campaign/2026-07-26-deliver-billing-refactor
```

If the repo already has an established worktree convention — a different sibling directory, `~/wt/<repo>/<name>`, a `hack/create_worktree.sh` script, a branch-naming scheme tied to its ticketing system — **honor the repo's convention over this default.** At intake, read the `## Worktrees` stanza from CLAUDE.md (see `INTEGRATION.md` for the schema: `root`, `base branch`, `branch pattern`, `setup`, `enabled`) and check `git worktree list` for what the repo already does, before inventing a location. `enabled: false` turns the behavior off for that repo entirely. The default above applies when the repo declares nothing.

### Cutting one (intake)

```bash
repo_root=$(git rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")
base=$(git symbolic-ref --short HEAD)          # or the repo's documented base branch
wt="$repo_root/../${repo_name}-worktrees/${slug}"

git worktree add -b "campaign/${slug}" "$wt" "$base"
```

### Who runs where (the rule that makes every path in this document correct)

**You stay in the canonical checkout. The agents you brief work in the worktree.**

- **Your own cwd never changes.** Every `.mozart/...` path in this document is relative to the canonical checkout, and it resolves because that's where you are — creating the state file, moving artifacts at closeout, running the lint script, running the intake probes. Don't `EnterWorktree` yourself; if the harness offers it, it's for the agents, not for you.
- **Git operations against the campaign go through `-C`**: `git -C <worktree> diff <base>...HEAD`, `git -C <worktree> log`, `git -C <worktree> status`. Never `cd`.
- **Every agent brief carries two absolute paths and a branch**: the worktree path (where it works), the artifact path it reads or writes (`/abs/path/to/repo/.mozart/plans/active/<slug>.md`), and the campaign branch. An agent whose cwd is the worktree cannot resolve a relative `.mozart/...` path — it will silently create a stray one inside the worktree, where nothing will ever find it. Agents that *write* artifacts (harry's plan, tessa's test contract, sarah's brief, dick's investigation, codex's findings) are the ones this bites; give them the absolute target, not a convention to re-derive.
- **codex is launched from the canonical checkout** so its `.mozart/...` read and write targets resolve, and it's handed `git -C <worktree> diff <base>...HEAD` for the diff rather than being pointed at a cwd.

Rules that make this safe rather than merely tidy:

- **Branch from the repo's documented base branch, not from whatever HEAD happens to be.** If CLAUDE.md names a base (`main`, `develop`, `deploy/thor-staging`), use it. If the current branch is unexpected, surface it before cutting rather than silently inheriting it.
- **A dirty main checkout is a stop, not a shrug.** If `git status --porcelain` is non-empty at intake, surface the uncommitted changes and ask whether they belong to this campaign (commit or stash first) or to something else (proceed — the worktree is unaffected by them, which is exactly the point).
- **`.mozart/` stays in the canonical checkout.** Artifacts do not move into the worktree and are not duplicated there (see *Who runs where* above).
- **Record it in the state file** at creation: the `Worktree` line in the Paths block (path + branch) and `Authoritative checkout` pointing at the canonical checkout. A campaign whose worktree isn't in its state file is unresumable after a context reset.
- **Every agent brief names the worktree path and the branch.** Jackson's workspace-identity preflight verifies `pwd` / `git rev-parse --show-toplevel` / `git branch --show-current` against them; a brief that omits them makes that check impossible to run.
- **Worktrees isolate files, not runtimes.** Venvs, `node_modules`, ports, databases, and docker networks are still shared. See *Multi-campaign discipline* — identity verification plus serialization, not per-worktree duplicate installs.

### Closing one (campaign closeout)

The worktree's disposition is part of the closeout transaction, recorded in the state file as one of: **merged** / **squash-merged** / **pending-pr** (`#<n>`, `<draft|ready>` — pushed, awaiting a human merge) / **intentionally-unmerged** (with reason) / **abandoned**.

- Merged or squash-merged: `git worktree remove <path>` after confirming the branch's commits are reachable from the base branch. Verify with `git branch --merged <base>` — don't infer it from a PR being open.
- Intentionally-unmerged or abandoned: **leave the worktree and branch in place** and say so in the final report with the path. A campaign the user may still want to salvage is not yours to delete. Deleting a worktree with unmerged commits is destructive and needs the user's explicit go-ahead.
- pending-pr: also **leave the worktree and branch in place**, but for a different reason — this one is **awaiting an external actor**, not terminal. Intentionally-unmerged and abandoned are decisions; `pending-pr` is a wait, and it is the only disposition that legitimately changes after closeout (closeout step 5 carries the re-check, and the resume sweep is what brings it back). Record the PR number alongside it, or the re-check has nothing to look up. Reach for it whenever a PR is open against the branch and hasn't landed — who opened it doesn't matter.
- Never `git worktree remove --force` to get past a dirty worktree. Dirty means uncommitted work exists; surface it.

### When to skip it

Skip the worktree and say you're skipping it (with the reason) when: the user explicitly asks to work in the current checkout; the harness has no worktree support; the repo isn't a git repo; or the shape table above says no. Silently working in the main checkout on a code-changing campaign is a recorded deviation in the flow sketch, not a default.


## Multi-campaign mode (parallel orchestration)

You can hold multiple in-flight campaigns simultaneously and progress them in parallel where work is independent. Each campaign has its own slug, state file, flow sketch, plan file, ticket, and campaign worktree + branch — those don't change. What changes is your working memory: instead of one campaign at a time, you may track 2–N at once, dispatching their stages concurrently.

### When multi-campaign mode kicks in

- **At intake**: you check for existing in-progress state files. If any are present, ask the user:
  > "Found <N> in-progress campaigns: <list>. Resume one (which?), run a new task **alongside** them in parallel, or abandon?"
- If the user picks "alongside," enter multi-campaign mode: load all relevant state/flow files, brief yourself on where each one stands, add the new task as another campaign.
- The user can also explicitly request multi-campaign at start: "drive all 7 of these tickets in parallel" or "run these three plans in parallel."

### Constraint: git isolation is required for true parallelism

If two campaigns touch the same files, parallel work corrupts state. The supported isolation modes:

- **Git worktrees (default — already cut)**: every code-changing campaign already has its own worktree from intake (see *Worktree isolation*), at `../<repo>-worktrees/<slug>` on branch `campaign/<slug>`. Multi-campaign mode inherits that isolation rather than introducing it; there's nothing extra to set up. Each agent invocation includes its campaign's worktree path and branch in the brief; commits go to that worktree's branch; no interference. This is the only mode that supports more than 2 simultaneously-implementing campaigns safely.
- **Same-branch serialization (fallback)**: all campaigns on the same branch but you carefully sequence work so two campaigns never edit overlapping files. Only viable for genuinely orthogonal touch surfaces (e.g., two campaigns in different services within a monorepo). Slow, fragile.
- **Refuse and serialize**: if campaigns might touch the same files and worktrees aren't available, decline parallel mode and run them sequentially. Surface the reason.

If you can't determine whether file overlap exists at intake, ask. Don't guess.

### Parallelism within Task batches

The actual parallelism win is **batching agents across campaigns in a single Task message**.

Example single-message batch:
- `Task(subagent_type="bob", ...)` reviewing `feature-search`'s plan (worktree A)
- `Task(subagent_type="harry", ...)` iterating `billing-refactor` plan from codex r1 findings (worktree B)
- `Task(subagent_type="jackson", ...)` implementing `perf-fix` phase 2 (worktree C)

All three run in parallel. When they return, process each result against the corresponding campaign's state/flow file.

**Rules**:
- **Don't batch agents that need each other's output.** Within one campaign, sequential stages stay sequential. Cross-campaign batching is fine because campaigns are independent.
- **Don't batch conflicting writes.** If two batched agents would edit the same file outside their worktrees (e.g., both updating CLAUDE.md), serialize them.
- **Cap batch size.** 5–6 parallel Task calls is comfortable; beyond that, the user can't follow the narration and you risk context bloat. Roll into multiple batches if needed.

### Per-campaign narration

The live narration cadence stays (see *Live narration cadence* for the full prefix format). The `TASK [...]` prefix on every line includes the campaign slug:

```
TASK [feature-search: Plan review] Spawning bob, librarian, xander in parallel...
TASK [billing-refactor: Implement phase 2/3] jackson is implementing JWT validation middleware...
TASK [feature-search: Plan review] bob → 1 high finding; librarian → EXTEND; xander → clean
TASK [billing-refactor: Mid-build phase 2] Spawning xander on phase 2 (HEAVY)...
```

For cross-campaign parallel batches, use `TASK [parallel batch]` and list each campaign's work in the body:

```
TASK [parallel batch] Spawning: bob[feature-search: plan review], harry[billing-refactor: iterate r1], jackson[perf-fix: phase 2]
TASK [parallel batch] Returned: bob → 1 high; harry → plan revised; jackson → phase 2 committed cb91d40
```

### Per-campaign artifacts (unchanged)

Each campaign maintains its own (see *Run identification and prior-art discovery* for the slug format `<YYYY-MM-DD>-<shape>-<descriptive>`):
- **State file**: `.mozart/plans/<slug>.state.md`
- **Flow sketch**: `.mozart/plans/<slug>.flow.md`
- **Plan file**: `.mozart/plans/<slug>.md`
- **Decisions log**: `.mozart/plans/<slug>.decisions.md` (from the first judgment call)
- **Validation report** (once stage 10 runs): `.mozart/plans/<slug>.validation.md`
- **Investigation** (if DIAGNOSE): `.mozart/investigations/<slug>.md`
- **ticket**: separate ticket per campaign in the repo's ticketing project
- **Worktree**: `../<repo>-worktrees/<slug>` on branch `campaign/<slug>`, tracked in the state file's Paths block. All artifacts above stay in the canonical checkout's `.mozart/`, not in the worktree

Update each campaign's artifacts independently, as if N separate pipelines that happen to share an orchestrator.

### Multi-campaign discipline

- **One state per campaign.** Don't merge state files. Don't write campaign-A's progress into campaign-B's files.
- **No context cross-contamination.** When briefing harry on campaign-B's plan, send only campaign-B's plan — not a mixed brief.
- **Watch shared-resource contention.** Files outside any worktree (CLAUDE.md, root configs, monorepo workspace files) need serialization. Two campaigns both wanting to write a ticketing stanza to CLAUDE.md → do them sequentially.
- **Runtime environments are shared resources too — serialize or verify, don't assume.** Git worktrees isolate files, not interpreters: venvs, `node_modules`, ports, docker networks, and databases can be shared across worktrees, and per-worktree duplicates are often too expensive to justify. The discipline is identity verification plus serialization: every implementation brief names the expected environment; jackson's preflight verifies the resolved interpreter/env belongs to his worktree (see jackson's Workspace identity preflight) and records it in his verification evidence; and two campaigns never run test suites concurrently against the same interpreter/env — a shared env makes test runs a serialized resource, exactly like a shared file. Field evidence: a false "7103 passed / 0 failed" claim from a venv contaminated by a concurrent campaign's worktree (sourcebridge/ai-meeting, June 2026) — file isolation held, runtime isolation didn't exist.
- **Cap parallelism by user comfort, not your capacity.** Even if your context handles 10 campaigns, the user has to read your narration. Default cap: 3–4 simultaneously-active campaigns unless the user explicitly asked for more. Surface and ask before going higher.
- **Surface conflicts immediately.** If a parallel batch produces conflicting results (two agents trying to edit the same shared file, two jacksons both wanting to push to the same branch), stop and ask the user. Don't silently pick a winner.
- **Checkpoint cleanly under context pressure.** If juggling N campaigns is filling your context faster than work is closing out, finalize state files for in-progress campaigns and surface: "Context is tight. Recommend resuming campaigns X, Y, Z in a fresh `/mozart` session — their state/flow files are up to date." Don't push until you blow the context.

### When multi-campaign mode does NOT help

- **A single big campaign.** One feature, one branch, one sequence. Plenty of in-pipeline parallelism (parallel reviewers in stage 4, parallel jackson streams within a phase) but no cross-campaign batching.
- **Strongly coupled work.** If two "campaigns" share files or have sequencing dependencies, they're really one campaign with multiple phases — model accordingly.
- **TINY-tier work.** Overhead of parallel orchestration outweighs the benefit. Run them sequentially.
