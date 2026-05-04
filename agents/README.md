# Agents

This directory contains every persona file loaded by the mozart-orchestration plugin. See the bundled `PIPELINE.md` for the full pipeline reference: shapes, tiers, partial flows, trigger tables, and authority boundaries.

To add a new agent, read the authoring contract in [`../CONTRIBUTING.md`](../CONTRIBUTING.md).

---

## Specialists (14)

Ordered by DELIVER pipeline stage.

| Agent | Role | Model | Stages |
|-------|------|-------|--------|
| mozart | Delivery conductor — orchestrates all three pipeline shapes | opus | 1–13 (all) |
| sarah | Technical researcher — surfaces prior art and best practices | sonnet | 2 (optional) |
| harry | Planner — produces the phased implementation plan | opus | 3, 6 |
| bob | Architect reviewer — evaluates design, layering, and trade-offs | sonnet | 4, 8 |
| dexter | Code-health reviewer — duplication, complexity, naming, test seams | sonnet | 4, 8 |
| xander | Security reviewer — threat model, injection, auth, secrets | sonnet | 4, 8 |
| ruby | UX reviewer — states, accessibility, responsive, voice | sonnet | 4, 8 |
| otto | Infrastructure-ops reviewer — infra, config, deployment, ops | sonnet | 4, 8 |
| librarian | Code archaeologist — does this already exist? (BROWNFIELD only) | sonnet | 4, 8 |
| ian | Change-impact analyst — ripple effects from the diff | sonnet | 8 |
| jackson | Implementer — writes and reconciles code, phase by phase | sonnet | 7, 11 |
| dick | Bug investigator — DIAGNOSE lead; reproduces, isolates, roots out | sonnet | DIAGNOSE 2 |
| valerie | Validator — checks implementation against the plan | sonnet | 10, 11 |
| scott | Technical writer — documentation, CHANGELOG, release notes | sonnet | 12 |

---

## Support agents (4)

Invoked by specialists for lookups and research; not pipeline stages themselves.

| Agent | Role | Model | Used by |
|-------|------|-------|---------|
| codebase-locator | Finds files matching a description or topic | haiku | sarah, librarian |
| codebase-analyzer | Reads and summarizes code for higher-level agents | sonnet | sarah, dick, ian |
| codebase-pattern-finder | Finds usage patterns across the codebase | sonnet | sarah, librarian |
| web-search-researcher | Searches the web and fetches external pages | sonnet | sarah |

---

## Persona format

Every specialist file contains these nine sections, in order:

1. **YAML frontmatter** — `name`, `description`, `tools`, `model`
2. **Opening paragraph** — who the agent is, what its job is, what it does not do
3. **`## Where you fit in mozart's pipeline`** — stage line, before/after, triggers, "not your lane" boundary
4. **`## Default standard`** — canonical paragraph (copy verbatim from `sarah.md`)
5. **`## Core operating principles`** — role-specific subsections
6. **`## Working mode`** — numbered steps for processing a task end-to-end
7. **`## Output format`** — fenced markdown template for the agent's output artifact
8. **`## Communicate as you work`** — canonical section (copy verbatim from `sarah.md` or `ruby.md`)
9. **`## Field notes (append-only)`** — append-only cross-project patterns; see `LEARNINGS.md` for the protocol

Use `sarah.md` as the canonical template for researcher/analyst types; use `ian.md` for narrowly-scoped analyst types. Both illustrate the full scaffold.
