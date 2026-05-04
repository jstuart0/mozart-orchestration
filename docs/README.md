# Documentation index

This directory is the future home for deeper plugin documentation: architectural decision records (ADRs), design notes, self-hosted-marketplace deployment guides, and any reference material that outgrows a top-level file.

For now, the authoritative references are:

- [`../agents/PIPELINE.md`](../agents/PIPELINE.md) — full pipeline reference: shapes (DELIVER / AUDIT / DIAGNOSE), tiers, partial flows, multi-campaign mode, codex CLI integration, authority boundaries, and the complete agent roster. Every specialist persona links here.
- [`../agents/LEARNINGS.md`](../agents/LEARNINGS.md) — append-only field-notes protocol for specialists to record cross-project patterns.
- [`../INTEGRATION.md`](../INTEGRATION.md) — how to wire ticketing and documentation surfaces (Plane, Linear, Jira, GitHub Issues, Notion, Wiki.js, Confluence, GitHub Wiki) per-repo via a `CLAUDE.md` stanza.
- [`../agents/README.md`](../agents/README.md) — specialist and support-agent roster with models, stage assignments, and the persona-format scaffold.

PIPELINE.md and LEARNINGS.md live in `agents/` because every persona file links there by relative path. Moving them would require updating ~25 cross-references across 14 agent files; the index above is the preferred discovery path.
