# Changelog

All notable changes to this plugin will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
