# Changelog

All notable changes to this plugin will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added — percy (performance engineer) + findings ledger (pipeline economics)

Performance was the last unowned lens from the best-practices audit: the AUDIT table routed "performance / scaling" to bob+dexter (neither has a perf checklist), and a diff that turns one query into forty passes every correctness gate because nothing in the pipeline measures anything. Percy closes that — and lands together with the instrumentation that will measure whether he (and every other gate) earns his keep.

- **`agents/percy.md`** (new) — senior performance engineer, **measurement-first**: every finding carries either a measurement he took (`EXPLAIN`, endpoint timing, bundle-size diff, profile) or a three-legged complexity argument (the pattern, the unboundedness, the hot path — all cited). "Could be slow" is not a finding; premature-optimization findings are an explicit anti-pattern. At plan review he audits the **performance contract** (hot paths should state budgets: p95, query count, payload/bundle size) rather than demanding speed everywhere — which gives tessa's "perf assertions when the contract states one" rule something to bind against. Checklist spans DB (N+1, missing indexes, unbounded queries), network (chatty loops, sync I/O, missing timeouts), caching (no invalidation story = High), memory, frontend (measured bundle deltas, waterfalls, Web Vitals), algorithms, and batch/concurrency. Has Bash for measurement; read-only on source; never load-tests shared systems. Division of labor: k8s sizing stays with otto, structure with bob, code-health with dexter.
- **Wiring** — stage-4 and stage-8 conditional triggers in `mozart.md` (DB/query shapes, caching, pagination, hot-path endpoints, bundle-affecting changes, stated perf goals; skip cold paths/docs/manifests); AUDIT "Performance / scaling" lead flips from bob+dexter to percy (they support).
- **Findings ledger** (`mozart.md` state-file format) — one row per dispositioned Critical/High/Medium finding: stage, lens, severity, `fixed (<sha>)` / `rejected` / `accepted-risk (user)`. Rows are never deleted (a rejected finding measures the lens's false-positive rate). New `## Escapes` block records `Traces-to:` links when a later DIAGNOSE/audit finds a defect the campaign shipped; dick's investigation template records the same link from the discovering side, and mozart mirrors it back.
- **`scripts/mozart-metrics.sh`** (new) — aggregates ledgers + escapes across all state-file layouts into the pipeline-economics table: confirmed catches by stage/lens/severity, false-positive rate per lens, escapes, defect-removal efficiency, catches-per-campaign by tier. Wired into EVAL stage 2 alongside `mozart-lint.sh`; `docs/EVAL.md` gains the **Pipeline economics** report section with the gate-tuning decision rules (zero-catch/high-FP lens → tighten trigger; unique-catch stage → keep) and the honesty caveats (catch counts are a lower bound — prevention is invisible; only valerie-confirmed dispositions count, so raw finding volume can't be Goodhart-ed).
- **Drift fixes swept up in the wiring**: `agents/PIPELINE.md` roster/tables predated tessa (added) and carried stale model assignments (bob/ruby/valerie are opus, dick is sonnet — now match the agent frontmatter); plugin.json description now says four shapes / 15 subagents.

Percy is the first agent added *with* his evaluation instrumentation in place: after ~10 campaigns the ledger's catch and false-positive numbers say whether his triggers are right — measured, not argued.

### Added — coding-practice gap closures: toolchain bootstrap gate, dependency vetting, mechanical secret scan, observability + error-handling standards, CI/CD workflow review

A best-practices audit of the agent roster found the pipeline strong on planning, review, and verification discipline, but with six unowned practices — most of them variants of one meta-gap: the system mechanizes enforcement of its own state files (`mozart-lint.sh`) but not of the code it ships. Closures:

- **`agents/mozart.md` — pre-flight gate 3: toolchain baseline check.** The per-phase gate's "run lints/types/tests" silently assumed the repo *has* a linter, formatter, type-checker, and CI. New intake gate: missing toolchain on GREENFIELD forces a toolchain-bootstrap phase before any feature phase; on BROWNFIELD it forces a surfaced triage decision (bootstrap here, separate TINY campaign, or acknowledged degraded gate). The per-phase gate now fails when a diff touches a language with no configured mechanical check on GREENFIELD.
- **`agents/mozart.md` — mechanical secret scan at the per-phase gate.** `gitleaks`/`trufflehog` when installed, high-signal grep fallback otherwise (AWS keys, private-key blocks, `ghp_`/`xox`-prefixed tokens, JWT prefixes, inline password/api-key assignments). Any hit is a gate failure routed to jackson — never "commit now, scrub later." Reviewer eyeballs demoted from control to backstop.
- **`agents/xander.md` — dependency vetting checklist** (new section): provenance/typosquat, maintenance health, advisories against the resolved version, license, transitive footprint + install scripts, pinning + lockfile-in-same-diff. Scaled: patch bumps get advisories+pinning only; new dependencies get all six. Plus a **CI/CD pipelines** checklist item (unpinned actions, over-broad workflow token permissions, `${{ }}` injection of attacker-controlled context, `pull_request_target` + PR-head checkout, fork-PR secret exposure, cache poisoning). Both wired as stage-4 and stage-8 triggers in `mozart.md` and `PIPELINE.md` (manifest/lockfile diffs and workflow-file diffs now summon xander).
- **`agents/jackson.md` — Observability and Error handling sections** (new): structured logs with level discipline, correlation-ID propagation, no secrets/PII in logs, health+metrics surfaces on new long-running services ("a service that can fail silently is unfinished"); one error idiom per codebase, wrap-with-context across layers, structured domain errors vs loud unexpected failures, log-once-where-handled, user-facing messages say what to do next. Gives dexter's "inconsistent error handling" anti-pattern a positive spec to enforce against.
- **`agents/otto.md` — observability wiring** added to operational hygiene: new long-running services ship with the documented monitoring stack (scrape annotations / ServiceMonitor) and at least one down/crash-loop alert — the silent month-long Argo sync failure is the canonical incident.
- **`agents/harry.md` — toolchain-before-features sequencing rule** + self-review checklist item: GREENFIELD plans open with a toolchain-bootstrap phase.

Deliberately not changed: no numeric coverage floor (tessa's coverage-as-proof position stands) and no style-nit review lens (that's the bootstrapped linter's job — which is exactly why the toolchain gate exists).

### Added — EVAL: a fourth work shape (mozart evaluating mozart)

Mozart can now evaluate its own field performance from the campaign artifacts past runs left behind — and, critically, verify whether the previous evaluation's fixes actually changed behavior in campaigns that ran after they landed. This institutionalizes the ad-hoc July-2026 evaluation that produced the hang-proof-codex / atomic-closeout / model-assignment fixes.

- **`agents/mozart.md`** — DELIVER/AUDIT/DIAGNOSE become **four shapes** with EVAL; new **EVAL pipeline** section: six stages (scope → mechanical metrics via `scripts/mozart-lint.sh` → fix verification → delta-scoped qualitative sampling → synthesize and fix → ledger append + report) and EVAL-mode rules (machine-written append-only ledger, delta by default, canonical checkouts only, named verification targets required).
- **`commands/mozart-eval.md`** (new) — `/mozart-eval` runs the pipeline at top level. Never scans the filesystem uninvited: repos come from arguments or the user.
- **`docs/EVAL.md`** (new) — ledger schema and report template. Eval artifacts live in a **user-scope eval home** (`$MOZART_EVAL_HOME`, default `~/.mozart/evals/`) — never inside a consuming repo or the installed plugin, so a user's repo names, paths, and campaign details stay on their machine and the feature works with read-only plugin installs.
- **Tracking with deliberate revisits**: the ledger records which *lens* examined each campaign (`inventory`, `execution-quality`, custom), keyed by state-file hash. Unchanged campaigns are skipped by default but can be legitimately re-examined under a new lens — re-reading is a recorded decision, not an accident.
- **Fix-verification stage is load-bearing**: a shipped fix whose target metric didn't move in the post-fix cohort is itself a finding, escalating from prose to mechanical enforcement — the two prior evaluation cycles showed prose-only fixes decay.

### Added — configuration-layer fixes: gate model bumps, identity preflights, hygiene linter, real-path seam rule

Follow-up to the July-2026 evaluation, targeting the issue classes that trace to agent *configuration* rather than runtime discipline:

- **Model assignments on the single-point-of-failure gates**: valerie (final validation gate) and bob (the always-on plan reviewer) bumped `sonnet` → `opus`. The evaluation's "codex catches what the panel missed" gap was partly a config artifact — every internal reviewer ran on sonnet while codex is a frontier-class external agent. Wide parallel fan-out lenses stay on sonnet for cost. Mozart's stage 8 now requests a model override to opus for ian on HEAVY phases when the spawn tool supports one.
- **jackson: Workspace identity preflight** (new section) — before first edit and before any commit, verify `pwd` / `git rev-parse --show-toplevel` / `git branch --show-current` against the briefed worktree and campaign branch (evidence: phase commits landed on local `main`; 4 of 12 checkouts sat on branches unrelated to their directory names). Before any test run, verify the interpreter/venv resolves inside the current worktree and record the identity in verification evidence (evidence: a false "7103 passed / 0 failed" from a venv contaminated by a concurrent campaign's worktree).
- **mozart: runtime environments are shared resources** (multi-campaign discipline) — worktrees isolate files, not interpreters. Rather than resource-heavy per-worktree duplicate installs, the rule is identity-verification + serialization: briefs name the expected env, jackson's preflight proves it, and concurrent campaigns never run suites against the same interpreter/env simultaneously.
- **`scripts/mozart-lint.sh`** (new) — mechanizes the state-file invariants prose has twice failed to hold: status-vs-location drift (both subdir and legacy prefix layouts), paths-vs-checkbox codex drift, duplicate stage lines, unclosed stage lists in terminal campaigns, stale actives (>7 days), stale `active/` refs inside finished files, and sibling artifacts stranded in `active/` for finished slugs. Exit 1 on findings. Wired into mozart's intake (preferred over the manual probes) and closeout (final machine check). First-run calibration: 140 findings on ai-meeting, 87 on sourcebridge, clean on this repo.
- **tessa: binding one-real-path-per-seam rule** — every integration seam a plan or phase introduces/modifies requires at least one test exercising the real dependency, or an explicit written waiver naming the substitute (periodic smoke / query replay / contract pin). Mocked-only coverage at a seam is a High finding minimum; a green mocked suite at a seam is *no* evidence (evidence: "NON-FUNCTIONAL in production despite 6,590 passing tests").

### Added — July-2026 field-evaluation fixes: hang-proof codex, atomic closeout, cross-checkout resume safety

A July-2026 evaluation of ~285 campaigns across 12 repos (ai-meeting's 78-campaign corpus — 100% mozart-run — plus sourcebridge's 67 and ten smaller corpora) found the pipeline's rigor sound (codex r2 repeatedly caught Criticals no internal lens saw) but its bookkeeping and hang-handling leaky. Fixes:

- **Hang-proof external tools** (the "codex fails and mozart waits forever" bug). Root cause: `codex exec` blocks forever on an open stdin in background invocations — observed as multi-hour stalls at 0.1s CPU that look "alive" to process polling. The External tool execution discipline now mandates: (1) closed stdin (`< /dev/null`, or the prompt piped via stdin); (2) an OS-enforced kill-timer armed at launch (GNU `timeout`, or the portable `perl -e 'alarm shift; exec @ARGV'` on stock macOS) so a hang self-terminates instead of relying on a polled cap mozart may never get back to; (3) CPU-time growth as the liveness signal — "process is alive" is not one; (4) on timer kill, retry once with closed stdin, then escalate — a timeout is a tool failure, never a skip rationale, including on STANDARD tier. Both codex invocation templates (stages 5/9) carry the wrapper + redirects; intake probes the kill-wrapper alongside `command -v codex`. Prompt-echo output files (exit 0, no findings) added to the canonical tool-failure list with retry-once handling.
- **Campaign closeout is one atomic transaction** (stage 13 "Promote artifacts" rewritten as "Campaign closeout"): reconcile the state file in place (no bare `[ ]`, no duplicate stage lines, real iteration counts, Paths block actual + internal `active/` refs rewritten to `finished/`, worktree merge disposition recorded as merged / squash-merged / intentionally-unmerged / abandoned), finalize the flow sketch, move ALL slug artifacts by glob (the enumerated 3-extension loop stranded codex/test-contract siblings in `active/`), close parent/upstream campaigns whose decision point this run resolved, and propagate the final state to the canonical checkout. Evidence: 79% of ai-meeting's finished state files still pointed at `active/` paths; 14+ files across repos sat in a finished location with a non-complete status.
- **Cross-checkout freshness check on resume** (new step 0) + new `Authoritative checkout` state-file field: before resuming, scan `git worktree list` checkouts for newer/divergent copies of the slug's state file and for merge evidence newer than the local Status. Prevents the observed near-miss: main's replica said "in-progress, stage 6c — resume" while the campaign worktree's copy said "complete, PR #32 merged, deployed."
- **Skip honesty**: skipped stages are recorded as `[-] <stage> — skipped: <rationale>` lines — `Flow: FULL` with silently absent stages is no longer representable. State files are edited in place, never appended into duplicate stage lines. Flow-trace appends are part of the stage-exit contract (same operation as the checkbox tick) — flow files died at ~stage 6 in nearly every evaluated campaign.
- **Enforced iteration counters** (stages 6 and 11): the counter increments in the same step that launches the round; at cap, a forced ship-or-stop decision. Observed: six reconciliation rounds ran against a written, never-incremented `0/3`.
- **Codex r2 round-1 integration-contract sweep** (new contract check 4): verify external SDK/wire call shapes against the *installed* package versions and exercise one real non-mocked path per integration seam. The costliest observed pattern was 7-round r2 loops whose biggest finds (wrong SDK call shapes, protobuf-int status) were round-1-findable contract bugs hidden behind mocked-green suites.
- **Codex r1 briefed with the internal panel's findings**, framed as "hunt net-new only" — top defects were independently re-derived by 3–4 lenses while codex's unique value was its net-new catches.
- **Subagent context budget** (new section): repos with >~1,000-line CLAUDE.md get a one-time per-campaign context digest every brief points at ("use the digest; do not read CLAUDE.md"); after two failed spawns of a specialist, fix the brief — mozart inlining the specialist's job is a recorded deviation, never a silent fallback. Evidence: a 2,549-line CLAUDE.md OOM'd jackson 4×, plus scott and valerie; 49 state-file mentions of the hand-written workaround.
- **RE-AUDIT delta mode** (AUDIT pipeline): when a prior audit of the same scope exists, specialists scope to the diff since it + remediation verification instead of a blind full fan-out. Observed waste: six full five-specialist HEAVY audits in nine days finding single-digit regressions of the remediation itself.
- **Abandonment dispositions at intake**: every stale (>7 days) campaign surfaced at intake gets an explicit disposition (resume / `stopped` / `aborted`); mozart writes `Status: stopped` with a resume note whenever it walks away; LOOP-IN "awaiting operator" states get the same 7-day surfacing. Evidence: 19 of 20 open campaigns stale in the largest corpus, with exactly one explicit stop recorded in two months.
- **No half-staged slices** (stage 7g): every implementer session ends with the slice committed or reverted; resume-after-interruption defaults to revert-and-redo, not forensic re-audit of a partial diff.
- **`agents/valerie.md`** — mechanism drift named inside failure mode 3 (the shipped HOW must match the plan's HOW, not just the checklist of WHATs); SIGNOFF now requires a stated disposition for every open codex r2 Critical/High; stale "codex r2 (HEAVY only)" note aligned with the STANDARD-default-run rule. Mozart's stage 10 brief passes valerie the codex r2 findings file and blocks SIGNOFF around undispositioned findings.
- **State-file template** — new `Authoritative checkout` header field and `Worktree` Paths line (path + branch during the run, merge disposition at closeout).

### Changed — lifecycle convention: `active-` / `finished-` filename prefix → `active/` / `finished/` subdirectories

The lifecycle of campaign artifacts (state file, flow sketch, plan, plus investigations / audits / research with their own lifecycle) is now expressed as a parent subdirectory, not a filename prefix. The slug is bare on disk; the parent directory carries the lifecycle stage:

- `thoughts/shared/plans/active/<slug>.state.md` (was: `active-<slug>.state.md`)
- `thoughts/shared/plans/finished/<slug>.state.md` (was: `finished-<slug>.state.md`)
- Same shape under `thoughts/shared/investigations/`, `thoughts/shared/audits/`, `thoughts/shared/research/` for those artifact types

Lifecycle moves are `mv` operations between sibling subdirectories rather than rename operations on flat-directory siblings. Everything else (slug format, state-file contents, flow-sketch contents, the `Status` field as source of truth, stage 13 corruption check) is unchanged.

**No backfill.** Existing prefix-style files (`active-<slug>.state.md`, `finished-<slug>.state.md`) and prefixless legacy files at the flat `thoughts/shared/plans/` level remain where they are. Mozart does NOT migrate them. Intake's stale-run detection now probes both layouts so historical campaigns remain resumable in place. Migration of legacy files only happens when the user explicitly asks for a migration pass.

Why: the May-2026 multi-repo evaluation showed the prefix convention had its own drift class — `mv` to `finished-` prefix while body still says `Status: in-progress` is structurally identical to the new mv-to-finished/ drift, but the prefix layout is harder to scan visually (`ls plans/` mixes lifecycle stages on the same listing) and prefix-typo footguns appeared in commit messages and cross-references. Subdir layout makes `ls plans/active/` its own filter, leaves the slug bare for clean cross-linking, and avoids the prefix-vs-no-prefix-vs-different-prefix tri-state that historical state files already drifted across.

**Edits:**
- **`agents/mozart.md`** — section renamed `Filename convention` → `Directory convention` with full rewrite of the rules + concrete bash for the `mv` lifecycle moves. Stage 1 (Intake) creates artifacts in `active/` (with `mkdir -p` on first use). Stage 13 (Report) moves to `finished/` and runs the corruption check against the new layout. AUDIT and DIAGNOSE intake / decision-point sections updated to use `active/` and to move audit/investigation docs alongside the state+flow on lifecycle transitions. Intake stale-run detection extended from 3-probe union to 4-probe union (current subdir layout + drift catch + legacy prefix + legacy prefixless) with an explicit "don't migrate legacy on resume" rule. Orchestration discipline updated: mozart's allowed edits include moving artifacts between `active/` / `finished/` / `aborted/` subdirs at lifecycle transitions.
- **`agents/tessa.md`** — TDD test contract path updated to `thoughts/shared/plans/active/<slug>.test-contract.md`.

### Added — codex discipline + state-file hygiene + intake stale-run detection

A multi-repo evaluation across four agentpulse / os-project-athena / sourcebridge / ai-meeting (97 state files + 65 flow sketches, May 2026) surfaced one dominant pattern: **mozart frequently false-skips codex** — asserting unavailability without probing, conflating Task-tool absence with codex-CLI absence, reading codex stdout instead of the target findings file, and never updating the state-file `Paths` block after codex actually runs. The state-file `Codex r1: not yet run` template literal then misleads future-mozart on resume, compounding the skip.

This release adds load-bearing codex discipline plus adjacent state-file hygiene fixes:

- **`agents/mozart.md` — new top-level `Codex availability and use` section** (placed near "Default standard"). Frames codex as a load-bearing CLI gate, not optional decoration. Explicit invariants: codex is a CLI (not a subagent), Task-tool availability is independent of codex availability, success detection requires (exit 0 + target file exists + non-trivial content with severity tags), reading stdout instead of the target file is a canonical false-skip pattern.
- **`agents/mozart.md` stage 1 (Intake)** — adds a `command -v codex` probe at intake; result recorded to the state file's `Codex r1 (plan)` and `Codex r2 (diff)` lines before any other stage runs.
- **`agents/mozart.md` stage 5 (Codex r1)** — reads the recorded probe result instead of re-asserting availability. Adds an explicit success-detection block (exit + file + content). Adds a stage-exit contract requiring simultaneous (checkbox + Paths update + flow-sketch trace) in one operation.
- **`agents/mozart.md` stage 9 (Codex r2)** — STANDARD tier flipped from "optional" to "default-run." HEAVY tier upgraded from "mandatory" to "non-negotiable" with explicit non-skip-reasons listed. Same success detection + stage-exit contract as stage 5.
- **`agents/mozart.md` Orchestration discipline** — three new hardenings: caps are hard (cap reduction is user-only, never mozart's autonomous call); context pressure is a stop signal not a skip signal (collapsing mandatory gates under context pressure is invalid; the correct response is `Status: stopped` and resume in a fresh session); state-file `Paths` block must stay in sync with stage progress.
- **`agents/mozart.md` "Detecting an in-progress run at intake"** — both probes now run every time (not "fast path first, fallback only if empty"). Added a third probe for `finished-*` files whose body still says `Status: in-progress` (rename-drift catch). Added a >7-day staleness flag in the surfacing message.
- **`agents/mozart.md` stage 13 (Promote artifacts to finished-)** — adds a corruption check after the rename: `Status: complete ⇔ filename prefix is finished-`. Two grep one-liners verify the invariant before the campaign is declared shipped.
- **`agents/harry.md` self-review checklist** — promotes "every claim about the current codebase is backed by a file I actually read (and ideally cited `file:line`)" to require `file:line` citation grounded via a code-aware index (LSP, IDE Go-to-Definition, a tree-sitter symbol-search tool, a code-aware MCP server when configured, or `grep` when none is available). The May-2026 evaluation linked ungrounded plan references to 4-5 codex iteration rounds on the same campaign; this self-review bullet is the upstream fix.

What this catches that the prior pipeline didn't:

- Codex r1/r2 skipped on HEAVY runs with no probe evidence
- Codex returning exit 0 + empty target file treated as clean pass
- State-file `Paths` block claiming "Codex r1: not yet run" when codex actually ran (artifact exists on disk)
- Cap-reduction "to conserve context" shipping under-reviewed plans
- HEAVY mid-build specialists consolidated into "codex r2 covers it" (and codex r2 then BLOCKs)
- Unprefixed legacy state files invisible to the `active-*.state.md` glob at intake
- `finished-*` files whose body is still `Status: in-progress` (premature rename)
- Plan iteration thrash on HEAVY (4-5 codex rounds) caused by ungrounded `file:line` references

### Added — wiring-sites discipline (closes the per-commit consistency gap)

Audits routinely catch a class of finding that per-commit gates structurally cannot see: patterns wired into one site but missed at parallel sites the diff didn't touch (security defenses on sibling providers, cross-deployment-method drift between Helm/kustomize/compose files, ARIA patterns on newly-introduced sibling components). Each individual diff is internally correct; the per-discipline reviewers each look at the diff; nobody looks at the *population* of sites that should be parallel.

This release threads a wiring-sites discipline through the pipeline so the population becomes visible to per-commit gates at every stage:

- **`agents/harry.md`** — new `Pattern parity / wiring sites` section in the plan template. When a plan introduces or extends a pattern, harry enumerates every existing site that needs the pattern, with the grep command that produced the list. Added a corresponding self-review checklist bullet.
- **`agents/mozart.md`** — new top-level `Consistency lens (wiring sites)` subsection explaining the rationale. Stage 3 description requires harry's enumeration; stage 4 brief requires each reviewer to verify the enumeration is exhaustive within their discipline; stage 7d (per-phase gate) re-runs the documented grep against the diff and treats missing sites as a gate failure.
- **`agents/jackson.md`** — strengthened `Verify before claiming done` with an "exercise the path the work targets, not the happy path" rule (the canonical regression mode: a banner-rendering fix where the success path renders correctly but the error path silently keeps the old color because no reviewer drove the failure path). Added a `Pattern parity / wiring sites` bullet to the non-negotiable contract-checks block.
- **`agents/valerie.md`** — added a fourth failure mode, `Pattern incomplete` — re-runs the plan's documented grep against the post-diff tree and flags any enumerated non-deferred site that didn't land. Added a verification-evidence bullet requiring proof that the path the work targets was actually exercised, not just the happy path.

Skipped on plans that introduce no pattern (pure bug fix in a single function, isolated feature add with no analogue elsewhere) — but the plan still says so explicitly. Silence is not the same as "no pattern."

## [0.1.0] - 2026-05-03

### Added

- **14 specialist personas**: mozart (conductor), sarah (researcher), harry (planner), bob (architect), dexter (code-health), xander (security), ruby (UX), otto (infrastructure-ops), librarian (code-archaeologist), ian (change-impact), jackson (implementer), dick (bug-investigator), valerie (validator), scott (technical-writer)
- **4 support agents**: codebase-locator, codebase-analyzer, codebase-pattern-finder, web-search-researcher
- **Three orchestration shapes**: DELIVER (build/ship), AUDIT (review against a goal), DIAGNOSE (investigate a failure)
- **Three task tiers**: TINY (single-agent passthrough), STANDARD (full pipeline), HEAVY (extended reviews + mandatory codex rounds)
- **Two project contexts**: GREENFIELD (skip librarian), BROWNFIELD (librarian surveys prior art at plan review and mid-build)
- **Six partial flows**: FULL, PLAN-ONLY, RESEARCH-ONLY, INVESTIGATE-ONLY, AUDIT-ONLY, VALIDATE-ONLY
- **Multi-campaign mode**: drive 2–4 campaigns concurrently, each with its own slug, state file, plan, ticket, and git worktree
- **State persistence**: `<slug>.state.md` tracks pipeline position across sessions; `<slug>.flow.md` is a Mermaid diagram + chronological trace
- **Pluggable ticketing surfaces**: Plane, Linear, Jira, GitHub Issues, Notion (configured per-repo via `CLAUDE.md` stanza)
- **Pluggable documentation surfaces**: Wiki.js, Confluence, Notion, GitHub Wiki, in-repo files
- **`/mozart` slash command** — entry point that runs mozart at the top level of a Claude Code session so `Task` is available for subagent dispatch
- **`.claude-plugin/marketplace.json`** — enables `/plugin marketplace add jstuart0/mozart-orchestration`
- **`agents/PIPELINE.md`** — shared reference doc cross-linked by every specialist persona
- **`agents/LEARNINGS.md`** — append-only field-notes protocol for specialist personas to record cross-project patterns
- **Live narration cadence**: every Task invocation announced before it starts, summarized on return, tagged `TASK [<stage>]`
- **Codex CLI integration**: optional external `codex` CLI runs fresh-context review at stage 5 (plan) and stage 9 (diff); pipeline degrades gracefully when codex is not installed

### Notes

Initial public release.
