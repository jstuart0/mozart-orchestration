# Security

## Reporting a vulnerability

**Preferred**: open a [GitHub Security Advisory](https://github.com/jstuart0/mozart-orchestration/security/advisories/new) on this repository. GitHub Security Advisories are private by default — the report will not be visible until you and the maintainer agree on a disclosure timeline.

**Alternate**: email `jay.stuart@agileservicesgrp.com` with "Security:" in the subject line if you prefer not to use GitHub.

Best-effort acknowledgment within 5 business days.

## Scope

This is a markdown-only Claude Code plugin. It contains no compiled code, no server, and no runtime dependency. Agents in this plugin receive the following capabilities from the Claude Code harness:

- **Shell access** (`Bash`) — agents can run arbitrary shell commands in the user's environment
- **File read/write** (`Read`, `Edit`, `Write`) — agents can read and modify files on the local filesystem
- **Web access** (`WebFetch`, `WebSearch`) — agents can fetch external URLs and run web searches
- **Subagent dispatch** (`Task`) — mozart can spawn other agents, each of which also receives the above capabilities

The user is responsible for reviewing what mozart and its subagents are asked to run. Mozart's own authority constraints (no unprompted pushes to remote, no destructive shared-state operations without explicit user confirmation) are documented in `agents/PIPELINE.md` under "Authority boundaries". Those constraints are enforced by the persona instructions, not by the harness — they are behavioral, not sandboxed.

**Vulnerability classes of interest:**
- Persona instructions that can be coerced into issuing destructive commands without user confirmation
- Prompt injections that cause an agent to exfiltrate or log secrets
- Template examples that reference probeable infrastructure or real credentials
- Agent chaining patterns that bypass the authority boundaries documented in PIPELINE.md

## Out of scope

- Bugs in the third-party ticketing or documentation services themselves (Plane, Linear, Jira, Wiki.js, etc.)
- Bugs in the Claude Code harness or Anthropic's infrastructure
- Bugs in the consuming repo's `CLAUDE.md` configuration
- Social-engineering attacks against the plugin's human users

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |
