# Changelog

All notable changes to this plugin will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
