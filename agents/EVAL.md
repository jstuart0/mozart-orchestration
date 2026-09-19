## EVAL pipeline (mozart evaluating mozart)

Subject: mozart's own field performance across consuming repos — the campaign artifacts (state files, flow sketches, plans, codex reviews) are the evidence base. Deliverables: an eval report, configuration fixes, and an updated ledger. This is the institutional form of the July-2026 evaluation that produced the hang-proof-codex / atomic-closeout / model-assignment fixes: repeatable, delta-scoped, and — critically — able to answer "did the last round of fixes actually work?"

### Home and artifacts

EVAL spans projects, so its artifacts live in a **user-scope eval home** — not in any consuming repo, and not inside the installed plugin (which is read-only for plugin users). Resolve the eval home in this order: `$MOZART_EVAL_HOME` if set → `~/.mozart/evals/` (default; create with `mkdir -p` on first use).

- **Ledger**: `<eval-home>/ledger.jsonl` — append-only, machine-written, one record per (run, repo, slug, lens). Schema in the plugin's `docs/EVAL.md`.
- **Report**: `<eval-home>/<YYYY-MM-DD>-eval.md` — metrics snapshot, findings, fixes shipped, and the next run's verification targets.
- **Fixes**: for plugin maintainers, normal commits to `agents/`, `scripts/`, `commands/`, `CHANGELOG.md` in the plugin repo. For plugin users who don't maintain the plugin: project-level overrides (`.claude/agents/`), field-note proposals, or an upstream PR — the report records which route each fix took.

### Stages

1. **Scope.** Enumerate consuming repos (or the user names them). Read the ledger; compute the **delta**: campaigns whose state-file hash is new or changed since their last-recorded examination. Revisiting *unchanged* campaigns is allowed only with a **new lens** — a question the ledger shows was never asked of them (record the lens name, so the next run knows it's been asked). Canonical checkouts only: worktree replicas are excluded from the ledger; cross-checkout divergence is itself a finding, reported not ledgered.
2. **Mechanical metrics.** Run `scripts/mozart-lint.sh` per repo; snapshot the numbers into the report. Trends are the diff against the previous report's table. Also run `scripts/mozart-metrics.sh` per repo — it aggregates the campaigns' findings ledgers and escape links into the **pipeline-economics table**: confirmed catches by stage/lens/severity, false-positive rate per lens, escapes, defect-removal efficiency, and catches-per-campaign by tier (see `docs/EVAL.md` → Pipeline economics). It also aggregates a **conductor section**: campaigns with a record, rows by kind, controlled/unverified, and the wrong-override rate (`rejected (judgment)` share). These numbers are the evidence base for stage 5's gate-tuning decisions: a lens with zero catches and a high false-positive share over a meaningful sample gets its trigger tightened; a stage whose catches are all unique to it (nothing upstream found them) is earning its keep.
3. **Fix verification (the load-bearing stage).** For every fix the *previous* eval shipped, test whether campaigns that ran AFTER the fix landed behave differently — drift rates, stall counts, iteration-round counts, whatever metric the fix targeted. A fix whose metric didn't move is a first-class finding: the prose decayed, and the remedy is escalation to mechanical enforcement (a linter check, a template change, a wrapper), not re-stating the prose louder.
4. **Qualitative sampling.** Fan out analysts (parallel, delta-scoped) over new/changed campaigns: gate value vs rubber-stamping, catch attribution (which lens found what), stall/resume forensics, waste patterns. Same fan-out mechanics as the AUDIT pipeline; the ledger is the sampling frame. Sample Status notes, flow traces and reports for unlinked derived claims (absence, count, success, "the specialist is wrong") — the residue the linter can't mechanize; sample `rejected (judgment)` notes for settleable disputes (F33) and manifest cells for secrets Check L misses (F36); re-run `scripts/check-field-note-parity.py` when examined.
5. **Synthesize and fix.** Rank findings by evidence; apply configuration fixes (persona body edits are user-approved per `LEARNINGS.md` — surface, don't self-modify contracts). This stage is also the standing trigger for the field-notes periodic review that `LEARNINGS.md` assigns to the user: propose promotions, prunings, and new entries with evidence attached.
6. **Ledger append + report.** Append one record per (repo, slug, lens) examined this run with the current state-file hash. Write the report ending with **named verification targets for the next run** — an eval that ships fixes without saying how the next eval will measure them is incomplete.

### EVAL-mode rules

- **The ledger is machine-written.** Generate records with a script or loop, never hand-edit. Append-only; corrections are new records, not rewrites. The eval feature must not develop the hygiene disease it exists to detect.
- **Delta by default.** A full re-read of an unchanged corpus requires the user to ask for it. Cost scales with what changed, not with history.
- **Metrics from the linter, judgment from analysts.** Don't burn agent tokens re-deriving numbers a script produces; don't let a script's clean exit stand in for "the campaigns were good."
- **Cross-link to shipped fixes.** Findings that become commits get the SHA in the report; the next run's stage 3 reads that list as its work queue.
- **EVAL doesn't fix consuming repos.** Zombie states, divergent replicas, and stranded artifacts found in a consuming repo are reported with a recommended cleanup pass — executing that cleanup is a separate campaign in that repo, with the user's sign-off.

