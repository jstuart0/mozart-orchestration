# Contributing

Thank you for your interest in improving mozart-orchestration. This is a markdown-only Claude Code plugin — all of its behavior lives in agent persona files, a slash command, and supporting documentation. There is no compiled code.

## Scope of contributions

All of the following are welcome:

- **Bug fixes** — correcting a persona instruction that causes incorrect behavior
- **Persona improvements** — refining an existing agent's operating principles, output format, or working-mode guidance
- **New agents** — adding a specialist or support agent that fills a genuine gap in the pipeline
- **New partial flows** — adding a new early-exit shape (e.g., REVIEW-ONLY) to the DELIVER pipeline
- **New ticketing or docs adapters** — extending `INTEGRATION.md` with a new surface template
- **OSS hygiene** — issue templates, docs, CI improvements

## Persona authoring contract

Every specialist persona file must include, in this order:

1. **YAML frontmatter** — `name`, `description`, `tools`, `model`. The `description` field is what the Claude Code marketplace shows; write it for an external reader who doesn't know the pipeline. ~30–50 words. No jokes.
2. **Opening paragraph** — who the agent is, what its job is, what it explicitly does not do.
3. **`## Where you fit in mozart's pipeline`** — the stage marker, a short "Before you / After you" list, triggers, and a "Not your lane" boundary statement. Close with: `See the bundled \`PIPELINE.md\` for the full reference.` The marker's form is `**Your <PIPELINE> stages**: <list>` and it names **only this agent's own placement** — e.g. `**Your DELIVER stages**: 4 (Internal review — conditional), 8 (Mid-build — conditional).` `<PIPELINE>` is any shape the roster Stages column records for that agent (`agents/README.md`), so an agent the roster places in two shapes carries two marker lines, one per shape, each agreeing with its own roster segment. Placements the roster does not enumerate — AUDIT stage 3, EVAL — stay prose inside the same section rather than inventing a marker the roster can't confirm. **The marker must sit inside this section**, not merely somewhere in the file, and the section appears **exactly once**, ahead of `## Field notes`. Do not restate the whole pipeline: eleven personas each carried a full stage enumeration until it was deduplicated, and every stage rename meant editing eleven files.
4. **`## Default standard`** — copy the canonical paragraph verbatim from the `## Default standard` section of `agents/sarah.md`. This paragraph is the same in every specialist. Cite the section, never a line range: the range that used to be pinned here now holds the placement section instead, so a line pin sends a new contributor to the wrong contract the first time anything above it grows.
5. **`## Core operating principles`** — role-specific principles, as specific subsections.
6. **`## Working mode`** — how the agent processes a task end-to-end, numbered steps.
7. **`## Output format`** — a fenced markdown template for the agent's output artifact.
8. **`## Communicate as you work`** — copy this section verbatim from `agents/sarah.md` or `agents/ruby.md`. It is the same in every specialist.
9. **`## Field notes (append-only)`** — copy the stub from any existing specialist. Append-only; see `agents/LEARNINGS.md` for the protocol.

Use `agents/sarah.md` as the canonical template for a researcher-type agent; use `agents/ian.md` for an analyst-type. Both illustrate the full scaffold.

**Voice**: professional and precise. Match the density and tone of `agents/mozart.md` and `INTEGRATION.md`. No emojis. No jokey lines.

## When you add a new agent, also update

- `agents/PIPELINE.md` — add the agent to the Agent roster table and to the appropriate reviewer/specialist trigger table (stages 4 and 8)
- `agents/mozart.md` — add the agent to the roster list near the top of the file (around lines 7–25)
- `README.md` — add the agent to the "What's in the box" layout tree and update the agent count in the description
- `agents/README.md` — add a row to the appropriate table (Specialists or Support agents)

## Local testing

Clone the repository and install it as a local plugin — read "If your local install is specialized" below first if you already run mozart from a user-scope install:

```
/plugin marketplace add /path/to/cloned/mozart-orchestration
```

Then exercise the slash command against a real request in a test repo:

```
/mozart add a health-check endpoint to the API
```

There is no automated test suite for prose-only plugins. "Testing" means reading your diff carefully and confirming the agent behaves as expected when invoked. If you changed a specialist's output format, run it against a sample input and verify the output matches the template. If you changed PIPELINE.md, verify it stays consistent with `agents/mozart.md` (the two must agree on shapes, tiers, partial flows, and agent roster).

### If your local install is specialized

The repository is the product-neutral source. Nothing host-specific ships from it: no named MCP server in a `tools:` allow-list, no personal tooling named in a persona's instructions, no agent that exists only on one machine. That constraint is what makes the plugin installable by anyone.

A user-scope install under `~/.claude/agents/` may legitimately diverge from it. Wiring a code-aware index straight into the personas — appending the server's tool pattern to each `tools:` line and rewriting the `## Code retrieval` gate to name it — binds the behavior unconditionally, in every repo those agents are invoked in, rather than only where a consuming repo asked for it. That is a reasonable thing to want on your own machine, and it is exactly what must not ship. Agents you keep locally but never proposed for the repo are the same situation. **This divergence is a design difference, not drift to be reconciled.**

The consequence is that neither direction is a straight copy:

- **Repo to local** — copying `agents/` over your user-scope directory destroys the specialization outright and drops local-only agents. Installing the plugin is a separate case and a murkier one: it writes under `~/.claude/plugins/`, a different path from user scope, so the two installs coexist — and **which copy a session actually loads is not something this document establishes.** Neither situation errors, so before you trust a local test result, confirm which copy is live.
- **Local to repo** — copying a specialized persona back leaks one machine's tool configuration into a project that has to stay tool-agnostic. The PR checklist's "no homelab fingerprints or personal infrastructure references" is this same rule read from the other end.

The trap during a contribution follows from that: **a change made in this repo does not affect a running local mozart until it is synced, and a change made to a local persona while debugging never reaches the repo.** Neither produces an error, and both are easy to forget mid-task. If you edited a persona here and the behavior didn't move, confirm which copy is actually loaded before concluding the edit was wrong.

There is no sync tooling in this repo and no supported command that merges the two trees; reconcile by hand, per file, or keep the specialization as a patch you reapply deliberately. One would be worth adding — a contributor holding a specialized install currently has nothing but discipline standing between a routine reinstall and a silent revert. If what you actually want is a code-aware index in a *consuming* repo rather than in your install, use the supported generic path instead: the `## Code retrieval` stanza in `INTEGRATION.md` reaches it through that repo's configuration, without editing a persona at all.

The CI workflow at `.github/workflows/validate-plugin.yml` checks JSON validity and file presence. Run its logic locally before pushing:

```bash
python3 -m json.tool .claude-plugin/plugin.json > /dev/null
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null
for f in README.md LICENSE INTEGRATION.md CHANGELOG.md CONTRIBUTING.md SECURITY.md \
          CODE_OF_CONDUCT.md .claude-plugin/plugin.json .claude-plugin/marketplace.json \
          commands/mozart.md agents/mozart.md agents/PIPELINE.md agents/LEARNINGS.md; do
  test -f "$f" && echo "OK: $f" || echo "MISSING: $f"
done
```

## Commit and PR style

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Common types for this repo:

- `docs(persona):` — editing a persona file
- `feat(persona):` — new persona or new section in a persona
- `docs(pipeline):` — changes to PIPELINE.md
- `docs(integration):` — changes to INTEGRATION.md
- `chore(ci):` — CI or workflow changes
- `fix(persona):` — correcting an instruction that causes wrong behavior

If Claude collaborated on the change, include:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

## PR checklist

Before opening a pull request, confirm:

- No homelab fingerprints or personal infrastructure references have been introduced
- Voice is consistent with `agents/mozart.md` and `INTEGRATION.md` (professional, no emojis)
- If a new agent was added: PIPELINE.md, mozart.md, README.md, and agents/README.md are all updated
- If a pipeline shape or flow was changed: PIPELINE.md, agents/mozart.md, README.md, agents/README.md, every agent's stage-placement line, `commands/`, `scripts/`, `docs/`, `.github/` templates, and `.claude-plugin/` manifests all agree — grep for the stage marker, don't eyeball it. `.claude-plugin/*.json` is easy to miss because it isn't markdown and no `--include="*.md"` sweep reaches it. Every specialist carries the `**Your <PIPELINE> stages**:` marker, so the marker grep reaches them all — but grep for the generalized form, not for `DELIVER` alone, or you will skip the agents placed in other shapes
- If the change adds or alters a configurable surface, a stanza, or anything that leaves the machine: `INTEGRATION.md` and `PRIVACY.md` are updated too. A flow change reaches both — stage 12b needed a new `INTEGRATION.md` section plus three parity sites in it, and a `PRIVACY.md` carve-out for the plugin's first network egress — and neither file is named in the row above
- CHANGELOG.md has an entry for the change
- JSON files validate: `python3 -m json.tool .claude-plugin/plugin.json > /dev/null`
- Persona-contract gates pass: `bash scripts/mozart-contract-gates.sh` from the root of the checkout whose changes you are submitting — the campaign worktree, when there is one — after `bash -n scripts/mozart-contract-gates.sh`. The script gates the tree it lives in and takes that tree's root as an optional first argument, and it selects files via `git ls-files`, so untracked and gitignored markdown (a `.mozart/` campaign directory, for instance) is out of scope by construction rather than by an exclusion list. Run the syntax check first — a script that doesn't parse produces no gate results, and "no result" is not "no findings". **The gates live in that script and nowhere else**: every one of them scans markdown, so a gate pasted into a markdown file falls inside some gate's scope and passes on the strength of its own text. V0 fails if a gate body is ever mirrored into a scanned doc

## Field-notes protocol

The `## Field notes (append-only)` section at the bottom of each specialist persona is an append-only log of cross-project patterns. See `agents/LEARNINGS.md` for the protocol and the entry template. Do not edit any other section of a persona file when adding a field note — those sections are human-authored contracts.

## Issue templates

See `.github/ISSUE_TEMPLATE/` for the bug report, feature request, and new-agent proposal templates. Use them — they make triage faster.
