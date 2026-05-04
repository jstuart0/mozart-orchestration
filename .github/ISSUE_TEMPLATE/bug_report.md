---
name: Bug report
about: Report a problem with the plugin
title: "[bug] "
labels: bug
---

## Which agent / shape / phase

Which agent was running when the problem occurred (mozart, harry, jackson, valerie, etc.)? Which pipeline shape (DELIVER / AUDIT / DIAGNOSE)? Which stage number (1–13)?

## What happened

Describe the observed behavior. Paste the relevant `TASK [...]` narration lines if available.

## What you expected

Describe what you expected the agent to do instead.

## Reproducer

```
/mozart <your exact request>
```

Paste any relevant `CLAUDE.md` configuration (redact secrets, service names, infrastructure details):

```yaml
# paste relevant stanza here
```

## Environment

- Claude Code version:
- Plugin version: (check `.claude-plugin/plugin.json`)
- OS:

## Logs / artifacts

If available, paste the relevant section of `thoughts/shared/plans/<slug>.state.md`. Redact any secrets or private infrastructure details before pasting.
