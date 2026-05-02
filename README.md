# mozart-orchestration

A Claude Code plugin that ships **mozart** — a senior delivery conductor — and the roster of specialist subagents he conducts.

Mozart turns a single user request ("ship X", "audit Y", "investigate Z") into an orchestrated, narrated, multi-agent pipeline: research, plan, review, implement, verify, document. He recognizes when orchestration *isn't* warranted and routes single-agent requests directly. He tiers tasks (TINY / STANDARD / HEAVY), classifies project context (GREENFIELD / BROWNFIELD), and chooses between three pipeline shapes (DELIVER / AUDIT / DIAGNOSE).

## What's in the box

**Conductor:**
- `mozart` — orchestrates work end-to-end. Invoked via the `/mozart` slash command (he must run at the top level of a session to have `Task` access).

**Specialist personas** mozart conducts:
- `sarah` — researcher (current best practices + prior art)
- `harry` — planning architect
- `bob` — solution architect / plan reviewer
- `dexter` — code-health auditor
- `xander` — security engineer
- `ruby` — UI/UX designer & frontend engineer
- `otto` — infrastructure / Kubernetes / ops engineer
- `ian` — change-impact analyst
- `librarian` — code archaeologist (does it already exist?)
- `dick` — bug investigator
- `jackson` — implementing engineer
- `valerie` — plan-vs-diff verifier
- `scott` — technical writer

**Bundled support agents** mozart routes to for lookups and research:
- `codebase-locator`, `codebase-analyzer`, `codebase-pattern-finder`, `web-search-researcher`

## Install

This plugin can be installed from a Claude Code marketplace, or by cloning into your local plugins directory. Once installed, the `/mozart` slash command becomes available, and all agents are loadable via `Task(subagent_type="<name>", ...)`.

## How to use

```
/mozart <your request>
```

Examples:

- `/mozart add SSO via Authentik for the admin panel`
- `/mozart investigate why pgvector queries are slow on staging`
- `/mozart audit the codebase for tech debt`
- `/mozart have xander review my auth middleware` *(passthrough — no pipeline)*
- `/mozart resume thoughts/shared/plans/<slug>.state.md`
- `/mozart drive these 3 tickets in parallel: <list>` *(multi-campaign)*

If you don't pass an argument, mozart will ask what to orchestrate.

## Integration

Mozart is **pluggable** for two surfaces that vary by team:

1. **Ticketing** — Plane, Linear, Jira, GitHub Issues, or none.
2. **Documentation surfaces** — GitHub wiki, in-repo docs, an external wiki (Wiki.js, Notion, Confluence), or a custom mix.

Configure both by adding stanzas to your repo's `CLAUDE.md`. See [`INTEGRATION.md`](./INTEGRATION.md) for templates and the contract mozart follows.

If you don't configure ticketing, mozart skips ticket steps entirely — research, planning, implementation, and verification still work. If you don't configure docs, scott will publish to in-repo `README.md` / `CHANGELOG.md` / `docs/` only.

## Three orchestration shapes

| Shape | When | Output |
|---|---|---|
| **DELIVER** | "build X", "ship Y", "fix Z" | Working code, verified against the plan, documented |
| **AUDIT** | "review X", "audit Y for Z" | Findings document; optional remediation flow |
| **DIAGNOSE** | "why is X broken?", "investigate Y" | Findings document with symptom / repro / root cause / remediation options |

Bug-shaped DELIVER on STANDARD/HEAVY auto-promotes to DIAGNOSE first.

## Task tiers

| Tier | What it adjusts |
|---|---|
| **TINY** | Skip research, plan-review fan-out, mid-build specialists. Brief jackson directly → verify → commit |
| **STANDARD** | Default — full DELIVER pipeline |
| **HEAVY** | STANDARD + mandatory ian on every phase + mandatory xander mid-build + mandatory codex r2 on the final diff |

Mozart classifies tier at intake based on surface (auth, schema, migrations, infra, security-critical → HEAVY).

## Project context

| Context | What it controls |
|---|---|
| **GREENFIELD** | Skip librarian. Nothing meaningful to search against. |
| **BROWNFIELD** | Librarian runs at plan review and mid-build for new functions/classes/services |

When in doubt, mozart classifies BROWNFIELD; the librarian short-circuits if the work turns out to be greenfield-shaped in practice.

## Live narration

Mozart narrates every Task invocation before it starts (one line) and summarizes every return when it comes back (one line). The user always knows which agent is running and why.

## Repository layout

```
mozart-orchestration/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── mozart.md              # the /mozart slash command
├── agents/
│   ├── mozart.md              # the conductor
│   ├── sarah.md, harry.md, ruby.md, bob.md, dexter.md, xander.md,
│   ├── otto.md, ian.md, librarian.md, dick.md, jackson.md,
│   ├── scott.md, valerie.md   # the specialists
│   ├── codebase-locator.md, codebase-analyzer.md,
│   └── codebase-pattern-finder.md, web-search-researcher.md
├── README.md
├── INTEGRATION.md             # ticketing + docs configuration
└── LICENSE
```

## Authority

The mozart agent persona (`agents/mozart.md`) is authoritative for orchestration behavior. The `/mozart` slash command is a thin wrapper that hands control to the persona at the top level of a session.

## License

MIT — see [LICENSE](./LICENSE).
