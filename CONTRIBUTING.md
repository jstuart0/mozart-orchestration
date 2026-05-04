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
3. **`## Where you fit in mozart's pipeline`** — the DELIVER stage line, a short "Before you / After you" list, triggers, and a "Not your lane" boundary statement. Close with: `See the bundled \`PIPELINE.md\` for the full reference.`
4. **`## Default standard`** — copy the canonical paragraph verbatim from `agents/sarah.md` lines 25–27. This paragraph is the same in every specialist.
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

Clone the repository and install it as a local plugin:

```
/plugin marketplace add /path/to/cloned/mozart-orchestration
```

Then exercise the slash command against a real request in a test repo:

```
/mozart add a health-check endpoint to the API
```

There is no automated test suite for prose-only plugins. "Testing" means reading your diff carefully and confirming the agent behaves as expected when invoked. If you changed a specialist's output format, run it against a sample input and verify the output matches the template. If you changed PIPELINE.md, verify it stays consistent with `agents/mozart.md` (the two must agree on shapes, tiers, partial flows, and agent roster).

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
- If a pipeline shape or flow was changed: PIPELINE.md and mozart.md agree
- CHANGELOG.md has an entry for the change
- JSON files validate: `python3 -m json.tool .claude-plugin/plugin.json > /dev/null`

## Field-notes protocol

The `## Field notes (append-only)` section at the bottom of each specialist persona is an append-only log of cross-project patterns. See `agents/LEARNINGS.md` for the protocol and the entry template. Do not edit any other section of a persona file when adding a field note — those sections are human-authored contracts.

## Issue templates

See `.github/ISSUE_TEMPLATE/` for the bug report, feature request, and new-agent proposal templates. Use them — they make triage faster.
