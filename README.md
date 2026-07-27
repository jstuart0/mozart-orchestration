# mozart-orchestration

*A Claude Code plugin that turns one request into an orchestrated, narrated, multi-agent pipeline.*

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-0.1.0-green.svg)
![Claude Code Plugin](https://img.shields.io/badge/claude--code-plugin-7B61FF.svg)

## Why this exists

One-shot Claude Code requests either over-fire (one giant context doing everything) or under-deliver (no review, no plan, no validation). Mozart threads the needle: you describe what you want, and he routes it through a real delivery pipeline — research, plan, specialist review, implement, verify, document — using named subagents running in their own contexts. Each stage has a defined scope and a clear handoff. You see every move as it happens.

Mozart handles six shapes of work: **DELIVER** (build or change something), **AUDIT** (review against a goal), **DIAGNOSE** (investigate a failure), **INCIDENT** (respond to a live outage — mitigate first to restore service, race hypotheses in parallel, then durable-fix, with a running timeline and a blameless post-mortem; mozart is the incident commander), **OPERATE** (change or debug a live system — installs, config changes, infra mutations, applied straight to the running cluster/host rather than through a git pipeline), and **EVAL** (evaluate mozart's own field performance from past campaign artifacts and improve the configuration — see `/mozart-eval`). He tiers tasks — TINY / STANDARD / HEAVY (SEV1/2/3 for incidents) — to right-size the gates, classifies project context (GREENFIELD / BROWNFIELD) to decide when duplicate-check agents run, and narrates every Task spawn so you always know who is working and why.

## Quickstart

Install from the Claude Code plugin marketplace:

```
/plugin marketplace add jstuart0/mozart-orchestration
/plugin install mozart-orchestration
```

Then invoke mozart with your request:

```
/mozart <your request>
```

Example invocations:

- `/mozart add OAuth login to the admin panel` — DELIVER, STANDARD tier
- `/mozart audit our auth middleware` — AUDIT shape
- `/mozart investigate why pgvector queries are slow on staging` — DIAGNOSE shape
- `/mozart resume .mozart/plans/<slug>.state.md` — resume a stopped campaign

Without an argument, mozart asks what to orchestrate.

## The pipeline at a glance

```mermaid
flowchart LR
    A[1 · Intake] -.-> B[2 · Research<br/><i>STANDARD/HEAVY</i>]
    B -.-> C[3 · Plan<br/>harry]
    A --> C
    C -.-> D[4 · Plan review<br/><i>STANDARD/HEAVY</i>]
    D -.-> E[5 · Codex r1]
    C --> E
    E --> F[6 · Iterate]
    F --> G[7 · Implement<br/>jackson]
    G -.-> H[8 · Mid-build<br/><i>conditional</i>]
    H -.-> I[9 · Codex r2<br/><i>STANDARD opt /<br/>HEAVY req</i>]
    G -.-> I
    I -.-> J[10 · Validate<br/>valerie]
    G --> J
    J --> K[11 · Reconcile<br/>jackson]
    K --> L[12 · Document<br/>scott]
    L -.-> S[12b · Ship<br/><i>opt-in per repo</i>]
    S -.-> M[13 · Report]
    L --> M
```

Solid edges (`-->`) run on every tier. Dashed edges (`-.->`) mark conditional stages — conditional either on tier or on repo configuration: Research runs on STANDARD/HEAVY; Plan review fan-out runs on STANDARD/HEAVY; Mid-build specialists trigger per-phase when conditions match; Codex r2 is optional on STANDARD and mandatory on HEAVY; Ship runs on every tier but only when the repo declares a `## Pull requests` stanza, so it is off by default.

*AUDIT and DIAGNOSE flows are shorter — see [PIPELINE.md](agents/PIPELINE.md) for the full reference.*

## Orchestration shapes

| Shape | When | Output |
|---|---|---|
| **DELIVER** | "build X", "ship Y", "fix Z" | Working code, verified against the plan, documented |
| **AUDIT** | "review X", "audit Y for Z" | Findings document; optional remediation flow |
| **DIAGNOSE** | "why is X broken?", "investigate Y" | Findings document with symptom / repro / root cause / remediation options |
| **INCIDENT** | "prod is down", "returning 500s", "users can't log in", "SEV1" | Service restored (mitigation, logged + reversible), root cause, durable fix, and a blameless post-mortem with action items |
| **OPERATE** | "install X", "apply this manifest", "the pod is crashlooping" | Verified live-system change with a recorded snapshot + rollback command |

Bug-shaped DELIVER on STANDARD/HEAVY auto-promotes to DIAGNOSE first. A DIAGNOSE or AUDIT whose fix is a live-system change (not a code change) flows into OPERATE. An **active outage** (service down right now) is INCIDENT, not DIAGNOSE — mitigate-first, parallel, SEV-tiered; its durable fix flows into DELIVER or OPERATE with full gates restored.

## Task tiers

| Tier | What it adjusts |
|---|---|
| **TINY** | Skip research, plan-review fan-out, mid-build specialists. Brief jackson directly → verify → commit |
| **STANDARD** | Default — full DELIVER pipeline |
| **HEAVY** | STANDARD + mandatory ian on every phase + mandatory xander mid-build + mandatory codex r2 on the final diff |

Mozart classifies tier at intake based on surface area (auth, schema, migrations, infra, security-critical → HEAVY).

## Project context

| Context | What it controls |
|---|---|
| **GREENFIELD** | Skip librarian. Nothing meaningful to search against. |
| **BROWNFIELD** | Librarian runs at plan review and mid-build for new functions, classes, and services |

When in doubt, mozart classifies BROWNFIELD; librarian short-circuits if the work turns out to be greenfield-shaped in practice.

## What's in the box

```
mozart-orchestration/
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── agents/
│   ├── LEARNINGS.md             # cross-project field notes (append-only)
│   ├── PIPELINE.md              # full pipeline reference
│   ├── bob.md
│   ├── codebase-analyzer.md
│   ├── codebase-locator.md
│   ├── codebase-pattern-finder.md
│   ├── dexter.md
│   ├── dick.md
│   ├── hank.md
│   ├── harry.md
│   ├── ian.md
│   ├── jackson.md
│   ├── librarian.md
│   ├── mozart.md                # the conductor
│   ├── otto.md
│   ├── percy.md
│   ├── ruby.md
│   ├── sarah.md
│   ├── scott.md
│   ├── tessa.md
│   ├── valerie.md
│   ├── web-search-researcher.md
│   └── xander.md
├── commands/
│   └── mozart.md                # the /mozart slash command
├── docs/                        # created in v0.1.0 release
│   └── README.md
├── .github/                     # created in v0.1.0 release
│   ├── ISSUE_TEMPLATE/
│   └── workflows/
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── INTEGRATION.md               # ticketing, docs, code-retrieval, worktree configuration
├── LICENSE
├── README.md
└── SECURITY.md
```

`.mozart/` — mozart's artifact root in **your** repo (not this one): per-campaign state files, plans, flow sketches, validation reports, audits, investigations, research briefs, and incident timelines. Gitignore it unless you want campaign artifacts committed. Repos that ran mozart before this convention keep their artifacts at the legacy `thoughts/shared/` root — mozart reads both and never migrates.

Every code-changing campaign also gets its own git worktree at `../<repo>-worktrees/<slug>` on branch `campaign/<slug>`, cut at intake. `.mozart/` stays in the canonical checkout so `ls .mozart/plans/active/*.state.md` always answers "what's in flight?" regardless of worktree count.

## Live narration

Mozart announces every Task invocation before it starts (one line) and summarizes every return when it comes back (one line), each prefixed `TASK [<stage>]` for scannability. You always know which agent is running, on which campaign, and why.

## Integration

Mozart is pluggable for the surfaces that vary by team:

1. **Ticketing** — Plane, Linear, Jira, GitHub Issues, or none.
2. **Documentation surfaces** — GitHub wiki, in-repo docs, an external wiki (Wiki.js, Notion, Confluence), or a custom mix.
3. **Code retrieval** — an LSP, IDE symbol index, or AST-backed MCP server, if you have one.
4. **Worktrees** — where campaign worktrees live, what they branch from, and how they're named.
5. **Pull requests** — whether mozart pushes the campaign branch and opens the PR at all, and whether it opens as draft or ready.

Configure them by adding stanzas to your repo's `CLAUDE.md`. See [`INTEGRATION.md`](./INTEGRATION.md) for templates and the contract mozart follows.

Every stanza is optional. Without ticketing, mozart skips ticket steps entirely — research, planning, implementation, and verification still work. Without a docs stanza, scott publishes to in-repo `README.md` / `CHANGELOG.md` / `docs/` only. Without a code-retrieval stanza, agents use native `Read`/`Grep`/`Glob`. Without a worktrees stanza, campaigns get `../<repo>-worktrees/<slug>` on branch `campaign/<slug>`. Without a pull-requests stanza — the default — mozart never contacts a remote: it commits to the campaign branch and names it in the final report for you to push yourself.

## Optional: codex CLI

Mozart's pipeline calls an external `codex` CLI at stages 5 (codex-r1-plan, plan review) and 9 (codex-r2-diff, diff review) for fresh-context, second-opinion review. The value is that codex runs with no plan-iteration history, which surfaces issues that in-context agents sometimes miss. The plugin works without codex — those stages skip with a logged note and the pipeline continues.

If you want codex's input, install it from <https://github.com/openai/codex>. On HEAVY tier, codex r2 is mandatory; on STANDARD it's optional; TINY skips both rounds entirely.

## Authority

The mozart agent persona (`agents/mozart.md`) is authoritative for orchestration behavior. The `/mozart` slash command is a thin wrapper that hands control to the persona at the top level of a session.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the persona-authoring contract and instructions for adding new agents.

## License

MIT — see [LICENSE](./LICENSE).
