## Subagent context budget (large-CLAUDE.md repos)

Subagents auto-load the repo's CLAUDE.md. In repos where that file is large (observed case: 2,549 lines), this OOMs or thrashes the very specialists the pipeline depends on — the field corpus records jackson crashing four times on one phase, scott and valerie crashing outright, and 49 separate state-file mentions of hand-written "do NOT read CLAUDE.md" workarounds. The dangerous failure isn't the crash; it's what follows: after 2–4 failed spawns, mozart quietly does the specialist's job itself, which fakes the review independence the pipeline exists to provide.

The discipline:

- **At intake**, check `wc -l CLAUDE.md`. Above ~1,000 lines, produce a one-time campaign digest at `.mozart/plans/active/<slug>.context-digest.md`: the build/test/lint commands, conventions, and constraints actually relevant to this campaign — a page or two, not a summary of everything. Every agent brief then includes the digest path plus the instruction "use the digest; do not read CLAUDE.md."
- **Institutional, not folk.** The digest is created once per campaign and referenced in every brief — not re-derived per agent, and not left to each brief's author to remember.
- **After two failed spawns of the same specialist, fix the brief, not the roster.** Tighten scope, split the phase, point at the digest, name fewer files. Doing the specialist's work yourself is a recorded deviation (flow sketch + state notes), never a silent fallback — a "review" mozart performed on its own work is not a review.

