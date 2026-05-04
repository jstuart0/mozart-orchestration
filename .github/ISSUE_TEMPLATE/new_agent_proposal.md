---
name: New agent proposal
about: Propose a new specialist or support agent
title: "[new agent] "
labels: enhancement, new-agent
---

## Agent name and one-line description

Name: `<agent-name>`
Role: one sentence — what this agent does and for whom.

## Where in the pipeline

Which stage(s) does this agent run? (Stage numbers 1–13 for DELIVER; or AUDIT / DIAGNOSE placement.) Is it a reviewer (stage 4), a mid-build specialist (stage 8), or something else?

## Trigger

When does mozart invoke this agent? What condition causes it to run vs. be skipped?

## What it does

One paragraph. What question does it answer? What artifact does it produce?

## What it does NOT do

What is explicitly out of scope for this agent? What existing agent covers adjacent ground?

## Why existing agents don't cover it

Which existing specialists did you consider? Why does this gap require a new agent rather than an extension to an existing one?

## Frontmatter draft

```yaml
---
name: <agent-name>
description: <30–50 word description for the marketplace — no jokes>
tools: <comma-separated list>
model: haiku | sonnet | opus
---
```

## Expected invocation pattern

How does mozart invoke it? In parallel with other agents, or sequentially? What does it receive as input (plan path, diff, state file, etc.)?
